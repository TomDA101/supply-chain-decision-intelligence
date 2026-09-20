{{ config(materialized='table') }}

with orders as (

    select *
    from {{ ref('stg_order_list') }}

),

capacity as (

    select *
    from {{ ref('prep_order_capacity') }}

),

plant_products as (

    select *
    from {{ ref('stg_products_per_plant') }}

),

plant_ports as (

    select *
    from {{ ref('stg_plantports') }}

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

        max(c.daily_capacity) as current_daily_capacity,
        max(c.capacity_utilization_ratio) as current_capacity_utilization

    from orders o

    left join capacity c
        on o.order_id = c.order_id

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

        pp.plant_code as alternative_plant

    from current_demand d

    join plant_products pp
        on d.product_id = pp.product_id
        and d.current_plant <> pp.plant_code

    join plant_ports pport
        on pp.plant_code = pport.plant_code
        and d.origin_port = pport.port

)

select *
from eligible_alternatives