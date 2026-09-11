-- models/mart/mart_customer_apindex.sql

with base as (
    select *
    from prep_customer_kpi_base
),

-- Plant dependency per customer: how many distinct plants serve them, and
-- whether they depend on a single plant entirely (100% of their orders).
plant_dependency as (
    select
        customer,
        count(distinct plant_code) as n_distinct_plants,
        (count(distinct plant_code) = 1) as is_single_plant_exposed
    from prep_order_capacity
    group by customer
),

-- Completeness flag: which customers have all three KPI inputs, and which
-- dimension(s) are missing for the rest. Operational-view use only.
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
-- Freight rate: right-skewed but continuous. Capacity utilization: dominated
-- by a single plant (~93% of order volume), causing most customers to share
-- an identical max value — a genuine structural tie, not an artifact.
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

-- Min-max normalization to 0-1. Only customers with a non-null value
-- contribute to MIN/MAX. Higher = higher priority for action, consistent
-- across all three KPIs.
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

-- Quartile thresholds and per-KPI flags. Computed on the static norm columns
-- (not on any weighted composite), so these are independent of the Tableau
-- weighting parameter and stable regardless of which profile is selected.
-- Precomputing this in SQL avoids a WINDOW_PERCENTILE table calc having to
-- be rebuilt consistently on every sheet in Tableau.
thresholds as (
    select
        percentile_cont(0.75) within group (order by freight_cost_exposure_norm)
            as freight_p75,
        percentile_cont(0.75) within group (order by capacity_risk_norm)
            as capacity_p75
    from normalized
    where has_complete_kpi_data
),

-- Static, weighting-independent flags only. Which dimension is *currently*
-- driving a customer's priority depends on the live-adjustable weighting
-- profile and is therefore computed in Tableau (comparing the three
-- Contribution fields), not here. These flags supply the stable "is this
-- dimension structurally high for this customer at all" input to that
-- Tableau formula.
flagged_recommendations as (
    select
        n.*,
        (n.freight_cost_exposure_norm >= t.freight_p75) as freight_top_quartile,
        (n.capacity_risk_norm >= t.capacity_p75) as capacity_top_quartile,
        (n.pct_late > 0) as has_late_deliveries
    from normalized n
    cross join thresholds t
),

-- Stable, human-readable customer label. Fixed alphabetically by the
-- original customer ID — independent of APIndex ranking or weighting, so
-- the same customer always carries the same label across every dashboard
-- and every weighting profile.
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

    -- raw values (tooltips / drill-down in Tableau)
    weighted_avg_rate,
    avg_capacity_utilization,
    avg_delivery_deviation_days,
    pct_late,

    -- normalized 0-1 scores (index inputs; weighting applied in Tableau)
    freight_cost_exposure_norm,
    capacity_risk_norm,
    delivery_risk_norm,

    -- precomputed, weighting-independent building blocks for the
    -- Recommended Action logic (built as a live Tableau field, since the
    -- dominant dimension depends on the selected weighting profile)
    freight_top_quartile,
    capacity_top_quartile,
    has_late_deliveries,

    -- plant dependency (structural context, feeds strategic narrative)
    n_distinct_plants,
    is_single_plant_exposed,

    -- data completeness (operational-view use only)
    has_complete_kpi_data,
    missing_kpi_dimensions,

    n_freight_orders,
    n_capacity_orders,
    n_delivery_orders

from labeled ;





-- models/mart/mart_plant_overview.sql


-- Grain: one row per plant.
-- Deliberately kept separate from mart_customer_apindex (customer grain) to avoid a fan-out
-- when relating plant-level capacity figures to order-level or customer-level data,
-- Use a dashboard action filter to connect this to the customer mart interactively, not a data-model relationship.

with capacities as (
    select *
    from stg_wh_capacities
),

costs as (
    select *
    from stg_wh_costs
),

orders as (
    select *
    from stg_order_list
),

port_links as (
    select *
    from stg_plantports
),

product_links as (
    select *
    from stg_products_per_plant
),

order_stats as (
    select
        plant_code,
        count(*) as order_count,
        count(distinct customer) as n_customers_served
    from orders
    group by plant_code
),

port_counts as (
    select
        plant_code,
        count(distinct port) as n_ports
    from port_links
    group by plant_code
),

product_counts as (
    select
        plant_code,
        count(distinct product_id) as n_products
    from product_links
    group by plant_code
),

combined as (
    select
        c.plant_code,
        c.daily_capacity,
        co.unit_costs,

        coalesce(os.order_count, 0) as order_count,
        coalesce(os.n_customers_served, 0) as n_customers_served,
        coalesce(pc.n_ports, 0) as n_ports,
        coalesce(prc.n_products, 0) as n_products,

        round(
            coalesce(os.order_count, 0)::numeric / nullif(c.daily_capacity, 0), 4
        ) as capacity_utilization_ratio,

        round(
            100.0 * coalesce(os.order_count, 0) / nullif(sum(coalesce(os.order_count, 0)) over (), 0), 2
        ) as pct_of_total_order_volume

    from capacities c
    left join costs co on c.plant_code = co.plant_code
    left join order_stats os on c.plant_code = os.plant_code
    left join port_counts pc on c.plant_code = pc.plant_code
    left join product_counts prc on c.plant_code = prc.plant_code
)
select
    plant_code,
    daily_capacity,
    unit_costs,
    order_count,
    pct_of_total_order_volume,
    capacity_utilization_ratio,
    n_customers_served,
    n_ports,
    n_products,
    (order_count > 0) as is_active_plant
from combined
order by capacity_utilization_ratio desc nulls last

