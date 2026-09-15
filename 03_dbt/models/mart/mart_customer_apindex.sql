{{ config(materialized='table') }}

with base as (
    select *
    from {{ ref('prep_customer_kpi_base') }}
),

plant_dependency as (
    select
        customer,
        count(distinct plant_code) as n_distinct_plants,
        (count(distinct plant_code) = 1) as is_single_plant_exposed
    from {{ ref('prep_order_capacity') }}
    group by customer
),

customer_rate_stats as (
    select
        customer,
        percentile_cont(0.5) within group (order by avg_rate) as median_rate
    from {{ ref('prep_order_freight') }}
    group by customer
),

order_rate_flags as (
    select
        f.customer,
        f.order_id,
        f.avg_rate,
        crs.median_rate,
        (f.avg_rate > 3 * crs.median_rate) as is_ambiguous_rate_order
    from {{ ref('prep_order_freight') }} f
    join customer_rate_stats crs
        on f.customer = crs.customer
),

freight_ambiguity as (
    select
        customer,
        bool_or(is_ambiguous_rate_order) as has_ambiguous_freight_data,
        count(*) filter (where is_ambiguous_rate_order) as n_ambiguous_orders
    from order_rate_flags
    group by customer
),
flagged as (
    select
        b.*,
        pd.n_distinct_plants,
        pd.is_single_plant_exposed,
        coalesce(fa.has_ambiguous_freight_data, false) as has_ambiguous_freight_data,
        coalesce(fa.n_ambiguous_orders, 0) as n_ambiguous_orders,

        case
            when b.weighted_avg_rate is null
                or b.avg_capacity_utilization is null
                or b.avg_delivery_deviation_days is null
            then false
            else true
        end as has_complete_kpi_data,

        concat_ws(', ',
            case when b.weighted_avg_rate is null then 'Freight' end,
            case when b.avg_capacity_utilization is null then 'Capacity' end,
            case when b.avg_delivery_deviation_days is null then 'Delivery' end
        ) as missing_kpi_dimensions
    from base b
    left join plant_dependency pd
        on b.customer = pd.customer
    left join freight_ambiguity fa
        on b.customer = fa.customer
),

transformed as (
    select
        *,
        case
            when weighted_avg_rate is not null
            then ln(weighted_avg_rate + 1)
        end as log_freight_rate,

        case
            when avg_capacity_utilization is not null
            then ln(avg_capacity_utilization + 1)
        end as log_capacity_utilization
    from flagged
),

normalized as (
    select
        *,
        (log_freight_rate - min(log_freight_rate) over ())
            / nullif(max(log_freight_rate) over () - min(log_freight_rate) over (), 0)
            as freight_cost_exposure_norm,

        (log_capacity_utilization - min(log_capacity_utilization) over ())
            / nullif(max(log_capacity_utilization) over () - min(log_capacity_utilization) over (), 0)
            as capacity_risk_norm,

        (pct_late - min(pct_late) over ())
            / nullif(max(pct_late) over () - min(pct_late) over (), 0)
            as delivery_risk_norm
    from transformed
),

thresholds as (
    select
        percentile_cont(0.75) within group (order by freight_cost_exposure_norm)
            as freight_p75,
        percentile_cont(0.75) within group (order by capacity_risk_norm)
            as capacity_p75
    from normalized
    where has_complete_kpi_data
),

flagged_recommendations as (
    select
        n.*,
        (n.freight_cost_exposure_norm >= t.freight_p75) as freight_top_quartile,
        (n.capacity_risk_norm >= t.capacity_p75) as capacity_top_quartile,
        (n.pct_late > 0) as has_late_deliveries
    from normalized n
    cross join thresholds t
),

labeled as (
    select
        *,
        'C' || lpad(row_number() over (order by customer)::text, 2, '0')
            as customer_label
    from flagged_recommendations
)

select
    customer,
    customer_label,
    weighted_avg_rate,
    avg_capacity_utilization,
    avg_delivery_deviation_days,
    pct_late,
    freight_cost_exposure_norm,
    capacity_risk_norm,
    delivery_risk_norm,
    freight_top_quartile,
    capacity_top_quartile,
    has_late_deliveries,
    has_ambiguous_freight_data,
    n_ambiguous_orders,
    n_distinct_plants,
    is_single_plant_exposed,
    has_complete_kpi_data,
    missing_kpi_dimensions,
    n_freight_orders,
    n_capacity_orders,
    n_delivery_orders

from labeled
