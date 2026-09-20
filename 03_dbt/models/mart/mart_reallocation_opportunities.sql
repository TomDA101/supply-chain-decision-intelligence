{{ config(materialized='table') }}

with orders as (

    select *
    from {{ ref('stg_order_list') }}

),

capacity as (

    select *
    from {{ ref('prep_order_capacity') }}

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

)

select *
from current_demand