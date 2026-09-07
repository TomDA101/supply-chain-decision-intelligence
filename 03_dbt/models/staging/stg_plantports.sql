{{ config(materialized='table') }}


with source_data as (
    select *
    from {{ source('raw', 'plantports') }}
    ),

    cleaned_plantports as (
    select
        "Plant Code"::varchar(20)    as plant_code,
        "Port"::varchar(10)          as port
      
    from source_data
)

select * from cleaned_plantports