# Status Update 3 — Modeling Phase Results

**Project:** Supply Chain Performance & Decision Intelligence (APIndex) </br>
**Phase:** dbt staging → prep → mart complete; Tableau dashboard in progress

---

## Pipeline Overview

<p align="left">
  <img src="../images/Lineage2.png" width="1200">
</p>

**Staging → Prep → Mart:** a single source of truth (`mart_customer_apindex`, 46 customers)
that feeds all three stakeholder perspectives in Tableau. A second mart, `mart_plant_overview` (19 plants),
is deliberately kept separate (data blending) to avoid a "fan-out."

---

## Thesis Adjustments During Modeling

Two theses evolved during the modeling phase as the initial assumptions were tested against the data:

- **Freight Cost Exposure:** two separate adjustments. Switched from an
  absolute weight × rate cost to a relative rate-pressure proxy, since only
  ~40% of lanes followed a consistent cost pattern. Separately, the metric was log-transformed before normalization to address the same right-skew issue observed in capacity (Insight 1).
- **Customer C46:** started as a suspected data error (extreme freight outlier); diagnostic testing traced it to  specific rows and ruled out a thin sample, join error, and bracket-nesting bug.


---

## Insight 1 — Capacity Risk Concentration by Plant

**Thesis:** Capacity Risk in the current index is strongly influenced by plant-level concentration — 26 of 46 customers share an identical
normalized score, meaning the KPI reflects network concentration more than
individual customer risk.

**Evidence:** A distribution check that revealed the skewed distribution and led to the log transformation. Additionally, the clustering quantification, which identified the 26/46 cluster.

**Results:**

<details>
<summary>SQL — distribution check (also covers freight_rate, pct_late)</summary>

```sql
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
```
 
</details>

| kpi | min_val | median_val | max_val | stddev_val | avg_val |
|---|---|---|---|---|---|
| freight_rate | 0.0424 | 0.0484 | 3.4665 | 0.5299 | 0.1752 |
| capacity_utilization | 0.3786 | 8.4294 | 8.4294 | 2.3154 | 7.4922 |
| pct_late | 0 | 0 | 0.1324 | 0.0200 | 0.0030 |
 
***Freight rate:** mean well above median, with an extreme upper range → strong evidence of a right-skewed distribution.</br> **Capacity utilization:**
median equals max (8.4294) — confirms the clustering directly, not just via
the separate count query below.*


<details>
<summary>SQL</summary>

```sql
select
    avg_capacity_utilization,
    count(*) as n_customers
from prep_customer_kpi_base
group by avg_capacity_utilization
order by n_customers desc
limit 5;
```

</details>


| avg_capacity_utilization | n_customers |
|---|---|
| 8.4294 | **26** |
| 1.4354	| 3 |
| 8.261544	| 1 |
| 8.4101241573	| 1 |
| 8.3932497537	| 1 |
| ... | ... |


*One utilization value alone accounts for 26 of 46 customers, indicating that the capacity KPI is strongly shaped by a shared structural driver rather than customer-specific variation.*

**Limitation** This limits the KPI's power to differentiate customers within
that group — worth flagging as an open limitation, not hiding it.

**Why this matters going forward:** the grain tension is exactly why the
dashboard is designed around three separate perspectives rather than one
score — at the Strategic level, network concentration *is* the signal;
at the Operational level, the index still needs to differentiate
individual customer action despite the shared structural component.

---

## Insight 2 — Diagnosing the C46 Freight Outlier

**Thesis:** Customer C46's extreme freight rate is not explained by a modeling or join artifact, but traces back to a duplicate-bracket rate structure on one lane (PORT09→PORT09) — kept in the dataset and flagged, not excluded.

**Evidence:** Six-step diagnostic: thin
sample ruled out, lane-level breakdown, bracket-nesting check, mode/transit
pattern check, re-run.

**Sample (Step 2 — lane-level breakdown for C46):**

<details>
<summary>SQL</summary>

```sql
select 
    f.carrier, 
    o.origin_port, 
    o.destination_port, 
    o.service_level, 
    count(*), 
    avg(f.avg_rate)
from prep_order_freight f
join stg_order_list o on f.order_id = o.order_id
where f.customer = 'V555555_6'
group by f.carrier, o.origin_port, o.destination_port, o.service_level
order by count(*) desc;
```

</details>




| Lane | Orders | Avg. rate |
|---|---|---|
| PORT04 → PORT09 (DTP) | 729 | 0.048 (normal) |
| PORT09 → PORT09 (DTP) | 32 | 12.28 (~256x higher) |

*The high average isn't spread across all of C46's orders — it's driven by
32 orders on one specific row — a deviation that warrants closer investigation rather than simply being smoothed out via averaging.*

**Caveat (working theory, not confirmed by the dataset):** The pattern
(GROUND mode, 0–1 transit days, origin = destination) suggests a local
handling/storage fee rather than standard freight transport — while plausible, this is not explicitly confirmed by any field in the source data.

---

## Outlook

- **Dashboard build:** Tableau, three stakeholder perspectives
  (Operational / Tactical / Strategic) — *work in progress*, directly
  informed by the customer-vs-network tension surfaced in Insight 1.
- **Sensitivity analysis:** planned once the Tableau weighting parameters
  are live, to test how robust these theses are across different KPI
  weighting profiles.
- **VMI customer flag:** staged (`stg_vmi_customers`) but not incorporated
  into the APIndex — not relevant to building the core index, since there
  is no evidence yet that VMI status affects any of the three KPIs.
  Relevance will be assessed after the build via a group-level comparison
  (VMI vs. non-VMI customers on rate, capacity, and delivery); only added
  as a dimension if a clear effect emerges.

</br></br></br></br></br></br></br></br>

<details>
<summary><b> All Theses </b></summary>
 
1. **Freight cost** — relative rate-pressure proxy instead of weight × rate
   (driven by data reliability)
2. **Capacity risk** — plant-level concentration ← *shown as Insight 1*
3. **Index architecture** — normalized KPI components exposed separately
   instead of a fixed composite score
4. **C46 outlier** — diagnosed, not removed ← *shown as Insight 2*
5. **Data completeness** — 13% of customers excluded from the
   tactical/strategic view (incomplete KPI inputs)
