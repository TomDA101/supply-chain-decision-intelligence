{{ config(materialized='table') }}


with orders as (
    select *
    from {{ ref('stg_order_list') }}
),
freight as (
    select *
    from {{ ref('stg_freight_rates') }}
),
matched as (
    select
        o.order_id,
        o.customer,
        o.carrier,
        o.plant_code,
        o.weight,
        avg(f.rate)          as avg_rate,
        avg(f.minimum_cost)  as avg_minimum_cost
    from orders o
    join freight f
        on o.carrier = f.carrier
        and o.origin_port = f.origin_port
        and o.destination_port = f.destination_port
        and o.service_level = f.service_level
        and o.weight between f.min_weight_qty and f.max_weight_qty
    where o.carrier != 'V44_3'
    group by o.order_id, o.customer, o.carrier, o.plant_code, o.weight
)
select * from MATCHED