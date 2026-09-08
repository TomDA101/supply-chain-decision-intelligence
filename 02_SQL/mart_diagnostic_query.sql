-- Diagnostic query (mart): distribution of the three raw variables, including the detection of individual dominant outliers.


-- Distribution check: min, max, median, stddev per raw KPI metric
select
    'freight_rate' as kpi,
    min(weighted_avg_rate) as min_val,
    percentile_cont(0.5) within group (order by weighted_avg_rate) as median_val,
    max(weighted_avg_rate) as max_val,
    stddev(weighted_avg_rate) as stddev_val,
    avg(weighted_avg_rate) as avg_val
from prep_customer_kpi_base
union all
select
    'capacity_utilization',
    min(avg_capacity_utilization),
    percentile_cont(0.5) within group (order by avg_capacity_utilization),
    max(avg_capacity_utilization),
    stddev(avg_capacity_utilization),
    avg(avg_capacity_utilization)
from prep_customer_kpi_base
union all
select
    'pct_late',
    min(pct_late),
    percentile_cont(0.5) within group (order by pct_late),
    max(pct_late),
    stddev(pct_late),
    avg(pct_late)
from prep_customer_kpi_base;


-- based on the values of the dignostic query:

-- 1. Check, quantification of capacity clustering

select
    avg_capacity_utilization,
    count(*) as n_customers
from prep_customer_kpi_base
group by avg_capacity_utilization
order by n_customers desc
limit 5;