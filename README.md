# Supply Chain Decision Intelligence

**Status:** Work in progress — capstone project, neue fische Data Analytics Bootcamp.
This README reflects the current stage and will be extended as the project develops.

## Project Idea 🎯

A BI framework that moves from static reporting toward actionable decision support
for supply chain performance. Three base KPIs — Delivery Reliability, Freight Cost
Exposure, and Capacity Risk — are combined into a weighted Action Priority Index,
calculated per customer and viewed through three stakeholder perspectives
(Operational, Tactical, Strategic). Details on KPI logic and weighting are still
being finalized and will be documented as the pipeline progresses.

***Optional validation:** If time permits, the decision logic will be challenged against an independent longitudinal supply-chain dataset to assess its transferability across different operational and financial performance measures.*

## Dataset

**Source:** Dzalbs, I. & Kalganova, T. (2019). *Supply Chain Logistics Problem
Dataset (Version 2)<sup> * </sup>. Brunel University London, Figshare.
https://brunel.figshare.com/articles/dataset/Supply_Chain_Logistics_Problem_Dataset/7558679

**Setup:** Download the file and place it at `data/Supply chain logisitcs problem.xlsx`
before running `01_Notebooks/01_Data_eda_cleaning.ipynb`.

**Related publication:** Dzalbs, I., & Kalganova, T. (2020). Accelerating supply
chains with Ant Colony Optimization across a range of hardware solutions.
*Computers & Industrial Engineering*, 147, 106610.

**Structure:** 7 tables —

| Table | Rows | Cols | Notes |
|---|---|---|---|
| OrderList | 9,215 | 14 | Single-date snapshot (2013-05-26) |
| FreightRates | 1,540 | 11 | 3 duplicate rows identified, to be removed |
| WhCosts | 19 | 2 | |
| WhCapacities | 19 | 2 | Current-state capacity constraints (orders/day) |
| ProductsPerPlant | 2,036 | 2 | |
| VmiCustomers | 14 | 2 | |
| PlantPorts | 22 | 2 | |

*Wh = Warehouse | vmi = Vendor Managed Inventory*

<details>
<summary><b> Table Columns </b></summary>

**OrderList**
- Order ID
- Order Date
- Origin Port
- Carrier
- TPT
- Service Level
- Ship ahead day count
- Ship Late Day count
- Customer
- Product ID
- Plant Code
- Destination Port
- Unit quantity
- Weight

**FreightRates**
- Carrier
- orig_port_cd
- dest_port_cd
- minm_wgh_qty
- max_wgh_qty
- svc_cd
- minimum cost
- rate
- mode_dsc
- tpt_day_cnt
- Carrier type

**WhCosts**
- WH
- Cost/unit

**WhCapacities**
- Plant ID
- Daily Capacity

**ProductsPerPlant**
- Plant Code
- Product ID

**VmiCustomers**
- Plant Code
- Customers

**PlantPorts**
- Plant Code
- Port
</details>

<p align="center">
  <img src="images/sc_datamodel.png" width="900">
</p>

No missing values across any table. Key characteristics established during EDA:

- **Snapshot, not time series:** all 9,215 orders share a single order date;
  trend analysis is out of scope for this dataset.
- **CRF / carrier V44_3:** ~9.3% of orders (854) have no corresponding freight
  rate by design (customer-arranged shipping, confirmed via the dataset authors'
  FAQ) and are excluded from cost calculations.
- **Aggregation level — Customer:** Plant Code and Origin/Destination Port are
  too concentrated (92.7%–100% on a single value) to serve as a meaningful
  primary dimension; Customer (46 unique values, ~10.6% max share) was selected
  instead.
- **Capacity framing:** `WhCapacities` reflects current-state constraints while
  `OrderList` is historical, so capacity analysis is framed as a stress test of
  historical demand against present-day constraints, not a retrospective
  utilization report.
  <br><br><br>
  
<sup> * </sup> The dataset originates from a research collaboration between Brunel University London and Caterpillar Inc. (funded project, Feb–Aug 2015, PI: Prof. Tatiana Kalganova), which also produced the underlying peer-reviewed publication (Dzalbs & Kalganova, 2020, Computers & Industrial Engineering). While the dataset is not explicitly labeled as derived from real Caterpillar operations, the industrial funding context and the structural realism of the data (plant/port networks, freight rate tables, order volumes) suggest it may reflect anonymized real-world logistics patterns rather than a purely synthetic simulation.<br><br>

## Workflow (planned)

Python/Pandas (EDA, cleaning) → SQL (PostgreSQL/DBeaver) → dbt (staging → prep → mart) → 
Tableau (dashboard) → GitHub (code, files and images)

<p align="center">
  <img src="images/workflow.png" width="850">
</p>

## Repository Structure

```
01_Notebooks/             Jupyter notebooks
02_SQL/                   SQL deliverables
03_dbt/                   dbt models
04_Dashboard/             Tableau workbook / exports
05_Stakeholder_meetings/  status presentations  
data/                     Raw dataset (gitignored, not versioned – see setup instructions)
images/                   png files

```

## Current Progress

### Step 1
- [x] Business Question
- [x] Raw data
- [x] EDA/Cleaning

### Step 2 via SQL/dbt
- [w.i.p.] KPI/Index definition
- [ ] KPI/Index calculation
- [ ] dbt models (staging _ prep _ mart,)

### Step 3
- [ ] Tableau dashboard
- [ ] *optional validation*
- [ ] Final presentation (deadline: September 29)
