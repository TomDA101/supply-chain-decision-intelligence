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
from normalized