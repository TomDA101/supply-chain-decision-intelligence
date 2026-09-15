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
        avg(f.minimum_cost)  as avg_minimum_cost,
        
-- Ratio between the highest and lowest matched FreightRates rate for this order.
-- A high ratio flags orders where the fan-out matches rate rows with materially different price levels (not just minor duplicate noise)
-- the case that surfaced this: PORT09->PORT09 entries mixing normal AIR transport rates with much higher GROUND, 0-transit-day rates
-- (likely a different fee type, e.g. local handling/storage, not confirmed by any field in the source data)
        max(f.rate) / nullif(min(f.rate), 0) as rate_spread_ratio
        
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
    on o.plant_code = pu.plant_code ;


-- models/prep/prep_order_delivery.sql

-- Excludes 123 orders (1.3%) where ship_ahead_day_count and ship_late_day_count are both > 0 simultaneously — a logical contradiction in the source data with no clear resolution (cannot be both early and late).
-- Full population, not filtered here: on-time orders (both = 0, 47.3%), ahead-only, and late-only orders.

with orders as (
    select *
    from stg_order_list
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
select * from delivery ;




-- models/prep/prep_customer_kpi_base.sql

with freight as (
    select *
    from prep_order_freight
),
capacity as (
    select *
    from prep_order_capacity
),
delivery as (
    select *
    from prep_order_delivery
),
customer_freight as (
    select
        customer,
        count(*) as n_freight_orders,
        sum(weight * avg_rate) / nullif(sum(weight), 0) as weighted_avg_rate
    from freight
    group by customer
),
customer_capacity as (
    select
        customer,
        count(*) as n_capacity_orders,
        avg(capacity_utilization_ratio) as avg_capacity_utilization
    from capacity
    group by customer
),

customer_delivery as (
    select
        customer,
        count(*) as n_delivery_orders,
        avg(delivery_deviation_days) as avg_delivery_deviation_days,
        sum(case when delivery_status = 'Late' then 1 else 0 end)::numeric
            / nullif(count(*), 0) as pct_late
    from delivery
    group by customer
)
select
    coalesce(f.customer, c.customer, d.customer) as customer,
    f.n_freight_orders,
    f.weighted_avg_rate,
    c.n_capacity_orders,
    c.avg_capacity_utilization,
    d.n_delivery_orders,
    d.avg_delivery_deviation_days,
    d.pct_late
from customer_freight f
full outer join customer_capacity c
    on f.customer = c.customer
full outer join customer_delivery d
    on coalesce(f.customer, c.customer) = d.customer


-- Testing values

-- Check 1: How many distinc customers?

select count(distinct customer) as n_customers_total
from stg_order_list;
-- first result: only 43 customers instead of 46 / fix ist the length of staging model in customers -> change to varchar(30)!!

-- final test
select count(*) from prep_customer_kpi_base; -- succsess: 46 customer!


-- Check 2: Customers who appear in stg_order_list but do not show up in ANY of the three prep models (they would be completely missing after the FULL OUTER JOIN)

select distinct o.customer
from stg_order_list o
where o.customer not in (select customer from prep_order_freight)
  and o.customer not in (select customer from prep_order_capacity)
  and o.customer not in (select customer from prep_order_delivery);

-- Check 3: Customers with NULL in one of the three KPI columns after the join
-- (informative, not an error per se — but good to know how many are affected)

select
    count(*) as n_customers,
    count(*) filter (where weighted_avg_rate is null)         as missing_freight,
    count(*) filter (where avg_capacity_utilization is null)  as missing_capacity,
    count(*) filter (where avg_delivery_deviation_days is null) as missing_delivery
from prep_customer_kpi_base;





-- diagnostic code / debugging test errors on dbt 

select customer, length(customer) as len, count(*)
from prep_customer_kpi_base
group by customer, length(customer)
having customer in (
    select customer
    from prep_customer_kpi_base
    group by customer
    having count(*) > 1
)
order by customer;

select * from prep_customer_kpi_base where customer = 'V55555_53';

