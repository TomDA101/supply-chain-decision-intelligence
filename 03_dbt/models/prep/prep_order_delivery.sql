{{ config(materialized='table') }}


with orders as (
    select *
    from {{ ref('stg_order_list') }}
),
delivery as (
    select
        order_id,
        customer,
        plant_code,
        ship_ahead_day_count,
        ship_late_day_count,
        (ship_late_day_count - ship_ahead_day_count) as delivery_deviation_days,
        case
            when ship_late_day_count > 0 then 'Late'
            when ship_ahead_day_count > 0 then 'Early'
            else 'On Time'
        end as delivery_status
    from orders
    where not (ship_ahead_day_count > 0 and ship_late_day_count > 0)
)
select * from delivery