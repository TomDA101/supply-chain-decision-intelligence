{{ config(materialized='table') }}

-- models/prep/prep_customer_kpi_base.sql

with freight as (
    select *
    from {{ ref('prep_order_freight') }}
),
capacity as (
    select *
    from {{ ref('prep_order_capacity') }}
),
delivery as (
    select *
    from {{ ref('prep_order_delivery') }}
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
        count(*)  as n_delivery_orders,
        avg(delivery_deviation_days) as avg_delivery_deviation_days,
        sum(case when delivery_status = 'Late' then 1 else 0 end)::numeric / nullif(count(*), 0) as pct_late
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
full outer join customer_capacity c on f.customer = c.customer
full outer join customer_delivery d on f.customer = d.customer