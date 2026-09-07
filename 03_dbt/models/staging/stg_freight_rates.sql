{{ config(materialized='table') }}


with source_data as (
    select *
    from {{ source('raw', 'freight_rates') }}
),

cleaned_freight as (
    select
        "Carrier"::varchar(20)        as carrier,
        "orig_port_cd"::varchar(10)   as origin_port,
        "dest_port_cd"::varchar(10)   as destination_port,
        "minm_wgh_qty"::numeric(10,2) as min_weight_qty,
        "max_wgh_qty"::numeric(10,2)  as max_weight_qty,
        "svc_cd"::varchar(10)         as service_level,
        "minimum cost"::numeric(10,2) as minimum_cost,
        "rate"::numeric(10,4)         as rate,
        "mode_dsc"::varchar(20)       as transport_mode,
        "tpt_day_cnt"::integer        as transit_days,
        "Carrier type"::varchar(20)   as carrier_type
    from source_data
)

select * from cleaned_freight