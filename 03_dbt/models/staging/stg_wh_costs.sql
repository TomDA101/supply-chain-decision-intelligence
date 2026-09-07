{{ config(materialized='table') }}


with source_data as (
    select *
    from {{ source('raw', 'whcosts') }}
    ),

cleaned_whcosts as (
    select
        "WH"::varchar(20) as plant_code,
        "Cost/unit"::numeric(10,2) as unit_costs
    from source_data
)
select * from cleaned_whcosts