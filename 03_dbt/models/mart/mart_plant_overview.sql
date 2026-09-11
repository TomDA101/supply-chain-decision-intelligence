{{ config(materialized='table') }}


with capacities as (
    select *
    from {{ ref('stg_wh_capacities') }}
),

costs as (
    select *
    from {{ ref('stg_wh_costs') }}
),

orders as (
    select *
    from {{ ref('stg_order_list') }}
),

port_links as (
    select *
    from {{ ref('stg_plantports') }}
),

product_links as (
    select *
    from {{ ref('stg_products_per_plant') }}
),

order_stats as (
    select
        plant_code,
        count(*) as order_count,
        count(distinct customer) as n_customers_served
    from orders
    group by plant_code
),

port_counts as (
    select
        plant_code,
        count(distinct port) as n_ports
    from port_links
    group by plant_code
),

product_counts as (
    select
        plant_code,
        count(distinct product_id) as n_products
    from product_links
    group by plant_code
),

combined as (
    select
        c.plant_code,
        c.daily_capacity,
        co.unit_costs,

        coalesce(os.order_count, 0) as order_count,
        coalesce(os.n_customers_served, 0) as n_customers_served,
        coalesce(pc.n_ports, 0) as n_ports,
        coalesce(prc.n_products, 0) as n_products,

        round(
            coalesce(os.order_count, 0)::numeric / nullif(c.daily_capacity, 0), 4
        ) as capacity_utilization_ratio,

        round(
            100.0 * coalesce(os.order_count, 0) / nullif(sum(coalesce(os.order_count, 0)) over (), 0), 2
        ) as pct_of_total_order_volume

    from capacities c
    left join costs co on c.plant_code = co.plant_code
    left join order_stats os on c.plant_code = os.plant_code
    left join port_counts pc on c.plant_code = pc.plant_code
    left join product_counts prc on c.plant_code = prc.plant_code
)

select
    plant_code,
    daily_capacity,
    unit_costs,
    order_count,
    pct_of_total_order_volume,
    capacity_utilization_ratio,
    n_customers_served,
    n_ports,
    n_products,
    (order_count > 0) as is_active_plant
from combined
order by capacity_utilization_ratio desc nulls last
