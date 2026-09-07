{{ config(materialized='table') }}


with source_data as (
    select *
    from {{ source('raw', 'vmicustomers') }}
    ),

cleaned_vmicustomers as (
    select
        "Plant Code"::varchar(20)   as plant_code,
        "Customers"::varchar(10)    as customer
      
    from source_data
)
select * from cleaned_vmicustomers 