{{ config(materialized='table') }}

with orders as (

    select *
    from {{ ref('stg_order_list') }}

),

capacities as (

    select *
    from {{ ref('stg_wh_capacities') }}

),

plant_products as (

    select *
    from {{ ref('stg_products_per_plant') }}

),

plant_ports as (

    select *
    from {{ ref('stg_plantports') }}

),

plant_order_counts as (

    select
        plant_code,
        count(*) as observed_order_count
    from orders
    group by plant_code

),

plant_capacity as (

    select
        c.plant_code,
        c.daily_capacity,
        coalesce(p.observed_order_count, 0) as observed_order_count,

        round(
            coalesce(p.observed_order_count, 0)::numeric
            / nullif(c.daily_capacity, 0),
            4
        ) as observed_capacity_utilization

    from capacities c

    left join plant_order_counts p
        on c.plant_code = p.plant_code

),

current_demand as (

    select
        o.customer,
        o.product_id,
        o.origin_port,
        o.plant_code as current_plant,

        count(*) as order_count,
        sum(o.unit_quantity) as total_units,
        sum(o.weight) as total_weight,

        max(pc.daily_capacity) as current_daily_capacity,
        max(pc.observed_capacity_utilization)
            as current_capacity_utilization

    from orders o

    left join plant_capacity pc
        on o.plant_code = pc.plant_code

    group by
        o.customer,
        o.product_id,
        o.origin_port,
        o.plant_code

),

eligible_alternatives as (

    select
        d.customer,
        d.product_id,
        d.origin_port,
        d.current_plant,
        d.order_count,
        d.total_units,
        d.total_weight,

        d.current_daily_capacity,
        d.current_capacity_utilization,

        pp.plant_code as alternative_plant,

        ac.daily_capacity as alternative_daily_capacity,
        ac.observed_order_count as alternative_observed_order_count,
        ac.observed_capacity_utilization
            as alternative_capacity_utilization,

        d.current_capacity_utilization
            - ac.observed_capacity_utilization
            as capacity_utilization_improvement

    from current_demand d

    join plant_products pp
        on d.product_id = pp.product_id
        and d.current_plant <> pp.plant_code

    join plant_ports pport
        on pp.plant_code = pport.plant_code
        and d.origin_port = pport.port

    left join plant_capacity ac
        on pp.plant_code = ac.plant_code

),

classified_alternatives as (

    select
        *,

        case
            when alternative_observed_order_count = 0
                then 'Unutilized Candidate'

            when capacity_utilization_improvement > 0
                then 'Observed Improvement'

            when capacity_utilization_improvement = 0
                then 'Same Capacity Pressure'

            else 'Higher Capacity Pressure'
        end as alternative_status

    from eligible_alternatives

),

ranked_alternatives as (

    select
        *,

        row_number() over (

            partition by
                customer,
                product_id,
                origin_port,
                current_plant

            order by

                case alternative_status
                    when 'Observed Improvement' then 1
                    when 'Unutilized Candidate' then 2
                    when 'Same Capacity Pressure' then 3
                    when 'Higher Capacity Pressure' then 4
                end,

                capacity_utilization_improvement desc nulls last,
                alternative_plant

        ) as alternative_rank

    from classified_alternatives

)

select *
from ranked_alternatives