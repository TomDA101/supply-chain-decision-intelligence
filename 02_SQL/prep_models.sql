-- models/prep/prep_order_freight.sql

-- Orders excluded from this model (not via an explicit filter, but implicitly via the INNER JOIN condition below)
-- 854 CRF/V44_3 orders (also excluded explicitly via the WHERE clause) + 1,364 orders whose weight falls outside
-- all brackets defined for their specific lane.

with orders as (
    select *
    from stg_order_list
),
freight as (
    select *
    from stg_freight_rates
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
select * from MATCHED ;



-- models/prep/prep_order_capacity.sql

with orders as (
    select *
    from stg_order_list
),
capacities as (
    select *
    from stg_wh_capacities
),
plant_order_counts as (
    select
        plant_code,
        count(*) as plant_order_count
    from orders
    group by plant_code
),
plant_utilization as (
    select
        c.plant_code,
        c.daily_capacity,
        p.plant_order_count,
        round(p.plant_order_count::numeric / nullif(c.daily_capacity, 0), 4) as capacity_utilization_ratio
    from capacities c
    join plant_order_counts p
        on c.plant_code = p.plant_code
)
select
    o.order_id,
    o.customer,
    o.plant_code,
    pu.daily_capacity,
    pu.plant_order_count,
    pu.capacity_utilization_ratio
from orders o
join plant_utilization pu
    on o.plant_code = pu.plant_code
