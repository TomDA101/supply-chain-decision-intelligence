-- models/staging/stg_order_list.sql
with source_data as (
    select *
    from order_list ol 
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




-- models/staging/stg_freight_rates.sql

-- testing, if the three duplicates realy dropped

SELECT COUNT(*) FROM freight_rates fr  ;


with source_data as (
    select *
    from freight_rates fr
),
cleaned_freight as (
    select
        "Carrier"::varchar(20)        as carrier,
        "orig_port_cd"::varchar(10)   as orig_port_cd,
        "dest_port_cd"::varchar(10)   as dest_port_cd,
        "minm_wgh_qty"::numeric(10,2) as minm_wgh_qty,
        "max_wgh_qty"::numeric(10,2)  as max_wgh_qty,
        "svc_cd"::varchar(10)         as svc_cd,
        "minimum cost"::numeric(10,2) as minimum_cost,
        "rate"::numeric(10,4)         as rate,
        "mode_dsc"::varchar(20)       as mode_dsc,
        "tpt_day_cnt"::integer        as tpt_day_cnt,
        "Carrier type"::varchar(20)   as carrier_type
        -- 4 trailing empty columns dropped here (excel export artifact)
    from source_data
)
select * from cleaned_freight



-- -- models/staging/stg_plantports.sql


with source_data as (
    select *
    from plantports p 
),
cleaned_plantports as (
    select
        "Plant Code"::varchar(20)    as plant_code,
        "Port"::varchar(10)          as port
      
    from source_data
)
select * from cleaned_plantports  ;


-- -- models/staging/stg_productsperplant.sql


with source_data as (
    select *
    from productsperplant p 
),
cleaned_productsperplant as (
    select
        "Plant Code"::varchar(20)    as plant_code,
        "Product ID"::varchar(10)    as product_id
      
    from source_data
)
select * from cleaned_productsperplant  ;


-- -- models/staging/stg_vmicustomers.sql


with source_data as (
    select *
    from vmicustomers v 
),
cleaned_vmicustomers as (
    select
        "Plant Code"::varchar(20)   as plant_code,
        "Customers"::varchar(10)    as customers
      
    from source_data
)
select * from cleaned_vmicustomers   ;


-- -- models/staging/stg_whcapacities.sql


with source_data as (
    select *
    from whcapacities w 
),
cleaned_whcapacities as (
    select
        "Plant ID"::varchar(20) as plant_code,
        "Daily Capacity "::integer as daily_capacity
    from source_data
)
select * from cleaned_whcapacities



-- -- models/staging/stg_whcosts.sql


with source_data as (
    select *
    from whcosts w 
),
cleaned_whcosts as (
    select
        "WH"::varchar(20) as plant_code,
        "Cost/unit"::numeric(10,2) as unit_costs
    from source_data
)
select * from cleaned_whcosts ;
