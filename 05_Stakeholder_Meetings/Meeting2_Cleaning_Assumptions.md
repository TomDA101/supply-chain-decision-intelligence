# Stakeholder-Meeting No.2 — Data Cleaning & Assumptions
**Supply Chain Decision Intelligence** -
Thomas Rabe · neue fische Data Analytics Bootcamp

---

## The Dataset, in Brief


<p align="left">
  <img src="../images/dataset_raw.png" width="800">
</p>


---

## Two Cleaning Fixes

| Table | Before → After | Fix |
|---|---|---|
| **FreightRates** | 1,540 → 1,537 rows | 3 fully duplicated rate rows removed |
| **OrderList** | 9,215 → 9,213 rows | 2 orders with Weight = 0 despite valid quantity — removed |

*Kept intentionally:* 123 orders (1.3%) flagged as both ahead **and** late — treated as a signal rather than silently corrected.

---

## Beyond Cleaning: Structural Findings

*The work of data cleaning is never truly finished — two structural peculiarities emerged during the preparation of data for modeling.*

1. **Freight-rate matching is sparse**</br>
   Only ~0.5% of orders have a single clean rate match — an aggregation strategy is required before any cost KPI can be built.

2. **Ship-ahead scheduling is not continuous**</br>
   Only 5 distinct day values appear (0, 1, 3, 5, 6) — indicating a discrete pattern rather than a continuous variable.


---

## Key Assumption: Carrier V44_3 / CRF

**854 orders (9.3%)** have no matching freight rate.

**Not a data-quality gap.** </br>
Carrier V44_3 (service level CRF) is customer-arranged shipping — by design, no lane exists for it in FreightRates. These orders are excluded from cost calculations, not treated as missing data.

Confirmed directly by the dataset author (Kalganova), not a forum assumption:
[brunel.figshare.com — Supply Chain Logistics Problem Dataset, file 20162015](https://brunel.figshare.com/articles/dataset/Supply_Chain_Logistics_Problem_Dataset/7558679?file=20162015)

---

## Other Modeling Assumptions

1. **Snapshot, not a trend**</br>
   All orders share one date → trend analysis dropped.

2. **Customer as the level of analysis**</br>
Values ​​for "Plant" and "Port" are concentrated (92–100%) on a single value – insufficient differentiation for a meaningful analysis.

3. **Capacity = stress test**</br>
   WhCapacities is current-state; OrderList is historical → Interpret as a comparison of demand against current capacity limits, rather than a utilization report.

---

## What's Next

- dbt staging & preparation framework ✓
- KPI construction → in progress
- Action Priority Index → next focus
