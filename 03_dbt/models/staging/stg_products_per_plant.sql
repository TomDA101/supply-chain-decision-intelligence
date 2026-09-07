{{ config(materialized='table') }}


with source_data as (
    select *
    from {{ source('raw', 'productsperplant') }}
    ),

cleaned_productsperplant as (
    select
        "Plant Code"::varchar(20)    as plant_code,
        "Product ID"::varchar(20)    as product_id

   from source_data
)
select * from cleaned_productsperplant