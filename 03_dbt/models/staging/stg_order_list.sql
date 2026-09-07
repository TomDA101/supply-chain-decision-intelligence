{{ config(materialized='table') }}

with source_data as (
    select *
    from {{ source('raw', 'order_list') }}
),
cleaned_orders as (
    select
        "Order ID"::integer          as order_id,
        "Order Date"::date           as order_date,
        "Origin Port"::varchar(10)   as origin_port,
        "Carrier"::varchar(20)       as carrier,
        "Service Level"::varchar(10) as service_level,
        "Ship ahead day count"::integer as ship_ahead_day_count,
        "Ship Late Day count"::integer  as ship_late_day_count,
        "Customer"::varchar(20)      as customer,
        "Product ID"::varchar(20)    as product_id,
        "Plant Code"::varchar(20)    as plant_code,
        "Destination Port"::varchar(10) as destination_port,
        "Unit quantity"::integer     as unit_quantity,
        "Weight"::numeric(10,2)      as weight
    from source_data
)
select * from cleaned_orders