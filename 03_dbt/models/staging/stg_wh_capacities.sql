{{ config(materialized='table') }}


with source_data as (
    select *
    from {{ source('raw', 'whcapacities') }}
    ),

cleaned_whcapacities as (
    select
        "Plant ID"::varchar(20) as plant_code,
        "Daily Capacity "::integer as daily_capacity
    from source_data
)
select * from cleaned_whcapacities