-- models/mart/mart_customer_apindex.sql

with base as (
    select *
    from prep_customer_kpi_base
),
-- Plant dependency per customer: how many distinct plants serve them, and whether they depend on a single plant entirely (100% of their orders).
plant_dependency as (
    select
        customer,
        count(distinct plant_code) as n_distinct_plants,
        (count(distinct plant_code) = 1) as is_single_plant_exposed
    from prep_order_capacity
    group by customer
),
-- Completeness flag: which customers have all three KPI inputs, and which dimension(s) are missing for the rest. Operational-view use only.
flagged as (
    select
        b.*,
        pd.n_distinct_plants,
        pd.is_single_plant_exposed,
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
),
-- Log-transform freight rate and capacity utilization before scaling.
-- Freight rate: right-skewed but continuous (most customers cluster low, e.g. 0.042-0.09, a few pull the max up to 3.47) — log compresses the tail so mid-range differentiation isn't lost to min-max scaling.
-- Capacity utilization: dominated by PLANT03 (~93% of order volume), causing 26 of 46 customers to share the identical max value (8.4294) — a genuine
-- structural tie, not an artifact. Log does not (and should not) break these ties; it only affects the spread of the remaining, non-tied customers.
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
-- Min-max normalization to 0-1. Only customers with a non-null value contribute to MIN/MAX, so the scale reflects the actual observed range among customers who have that KPI.
-- Direction: higher normalized value = higher priority for action, consistent across all three KPIs.
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
)
select
    customer,

    -- raw values (tooltips / drill-down in Tableau)
    weighted_avg_rate,
    avg_capacity_utilization,
    avg_delivery_deviation_days,
    pct_late,

    -- normalized 0-1 scores (index inputs; weighting applied in Tableau)
    freight_cost_exposure_norm,
    capacity_risk_norm,
    delivery_risk_norm,

    -- plant dependency (structural context, feeds strategic narrative)
    n_distinct_plants,
    is_single_plant_exposed,

    -- data completeness (operational-view use only)
    has_complete_kpi_data,
    missing_kpi_dimensions,

    n_freight_orders,
    n_capacity_orders,
    n_delivery_orders
    
from NORMALIZED ;