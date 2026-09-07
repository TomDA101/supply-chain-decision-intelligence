{{ config(materialized='table') }}


with orders as (
    select *
    from {{ ref('stg_order_list') }}
),
capacities as (
    select *
    from {{ ref('stg_wh_capacities') }}
),
plant_order_counts as (
    select
        plant_code,
        count(*) as plant_order_count
    from orders
    group by plant_code
),
plant_utilization as (
    select
        c.plant_code,
        c.daily_capacity,
        p.plant_order_count,
        round(p.plant_order_count::numeric / nullif(c.daily_capacity, 0), 4) as capacity_utilization_ratio
    from capacities c
    join plant_order_counts p
        on c.plant_code = p.plant_code
)
select
    o.order_id,
    o.customer,
    o.plant_code,
    pu.daily_capacity,
    pu.plant_order_count,
    pu.capacity_utilization_ratio
from orders o
join plant_utilization pu
    on o.plant_code = pu.plant_code