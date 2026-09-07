# prep_order_freight — Join Diagnosis & Decision Log

**Scope:** Diagnosis of the OrderList ↔ FreightRates join (weight-bracket join on
carrier, origin port, destination port, and service level) prior to building the
`prep_order_freight` model. Documents two structural issues discovered during
diagnosis — unmatched orders (zero-match) and duplicate rate matches (fan-out) —
and the decisions taken to resolve them.

---

## 1. Background

The Freight Cost Exposure KPI requires matching each order in `stg_order_list` to
a corresponding rate in `stg_freight_rates`, using:

- `carrier`
- `origin_port` / `destination_port`
- `service_level`
- `weight` falling within `[min_weight_qty, max_weight_qty]`

The EDA notebook (Section 5) had already confirmed that 100% of cost-eligible order
weights fall within *at least one* FreightRates bracket **globally** — i.e. across
the full table. This check does not guarantee that a weight falls within a bracket
of the *specific* lane (carrier + route + service level) that order would actually
be quoted on. That distinction turned out to matter (see Section 3).

---

## 2. Step 1 — Fan-out diagnosis (duplicate matches per order)

**Question:** Does the join produce more than one FreightRates match per order?

```sql
with order_freight_matches as (
    select
        o.order_id,
        count(*) as n_matches
    from stg_order_list o
    join stg_freight_rates f
        on o.carrier = f.carrier
        and o.origin_port = f.origin_port
        and o.destination_port = f.destination_port
        and o.service_level = f.service_level
        and o.weight between f.min_weight_qty and f.max_weight_qty
    group by o.order_id
)
select
    n_matches,
    count(*) as n_orders
from order_freight_matches
group by n_matches
order by n_matches
```

**Result:**

| n_matches | n_orders |
|---|---|
| 1 | 34 |
| 2 | 6,228 |
| 4 | 733 |

Only 34 orders (0.5%) resolve to a single unambiguous rate. The overwhelming
majority match 2 or 4 rate rows — this is the standard case, not an edge case.

### 2.1 Root cause check

Tested whether an additional, unused column (`carrier_type`, `mode_dsc`) explains
the duplicate rows:

```sql
select carrier, origin_port, destination_port, service_level,
       min_weight_qty, max_weight_qty,
       count(distinct carrier_type) as n_carrier_types,
       count(distinct transport_mode) as n_modes,
       count(*) as n_rows
from stg_freight_rates
group by 1,2,3,4,5,6
having count(*) > 1
order by n_rows desc
limit 10
```

**Result:** `n_carrier_types = 1` and `n_modes = 1` in every duplicated group.
No column in the table distinguishes the duplicate rate rows — the ambiguity is
structural in `FreightRates` itself, not caused by a missing join key.

### 2.2 Decision

**Use `AVG(rate)` when multiple FreightRates rows match the same order.**

Rationale: no column distinguishes which of the duplicate rows was actually
applied historically, so no min/max selection is defensible without an
unsupported assumption:

- `MIN` would assume "cheapest rate always applies" — unsupported
- `MAX` would assume a worst-case/conservative framing — more appropriate for a
  risk KPI (e.g. Capacity Risk) than for a relative cost-exposure KPI
- `AVG` makes no claim about which row is "correct"; it neutrally reflects the
  range of rates on file for that lane/bracket combination

---

## 3. Step 2 — Zero-match diagnosis (orders with no rate at all)

**Question:** Are there orders that match zero FreightRates rows?

```sql
select count(*) as n_zero_matches
from stg_order_list o
where not exists (
    select 1
    from stg_freight_rates f
    where o.carrier = f.carrier
      and o.origin_port = f.origin_port
      and o.destination_port = f.destination_port
      and o.service_level = f.service_level
      and o.weight between f.min_weight_qty and f.max_weight_qty
)
```

**Result: 2,218 zero-match orders** — substantially more than the 854 CRF/V44_3
orders already known from the EDA.

### 3.1 Root cause breakdown

**Check A — fully missing lanes** (carrier + route + service level combination
does not exist in FreightRates at all, independent of weight):

```sql
select distinct o.carrier, o.origin_port, o.destination_port, o.service_level
from stg_order_list o
where not exists (
    select 1 from stg_freight_rates f
    where o.carrier = f.carrier and o.origin_port = f.origin_port
      and o.destination_port = f.destination_port and o.service_level = f.service_level
)
```

**Result:** exactly 3 missing lane combinations, all `carrier = 'V44_3'`
(CRF) — confirming that CRF is the only case where the *lane itself* is absent.

**Check B — lane exists, but the order weight falls outside all brackets
defined for that specific lane:**

```sql
select count(*) as n_zero_matches_non_crf
from stg_order_list o
where o.carrier != 'V44_3'
and not exists (
    select 1 from stg_freight_rates f
    where o.carrier = f.carrier and o.origin_port = f.origin_port
      and o.destination_port = f.destination_port and o.service_level = f.service_level
      and o.weight between f.min_weight_qty and f.max_weight_qty
)
```

**Result: exactly 1,364.**

### 3.2 Reconciliation

| Cause | n_orders | Nature |
|---|---|---|
| CRF / V44_3 | 854 | Lane does not exist in FreightRates (customer-arranged shipping, per dataset FAQ) |
| Weight-bracket gap | 1,364 | Lane exists, but no bracket at that lane covers the order's weight |
| **Total zero-match** | **2,218** | ✓ matches the diagnostic query in Section 3 exactly |

The EDA's global weight-coverage check (100% of weights fall within *some*
bracket in the table) remains correct as stated, but does not extend to
per-lane coverage. This gap is only visible once the actual join is performed —
it is a newly identified, second data-completeness limitation of the dataset,
distinct from and additional to the known CRF exclusion.

### 3.3 Decision

**Exclude the 1,364 weight-bracket-gap orders from cost calculation, using the
same treatment as CRF/V44_3.**

Rationale: identical reasoning to the CRF exclusion — no rate can be attributed
to these orders without inventing a bracket that does not exist in the source
data. A nearest-bracket fallback was considered and rejected, as it would
introduce fabricated cost figures not supported by the dataset.

---

## 4. Resulting logic for `prep_order_freight`
*snapshot at time of this diagnosis*

```sql
with matched as (
    select
        o.order_id,
        o.weight,
        avg(f.rate) as rate,
        avg(f.minimum_cost) as minimum_cost
    from stg_order_list o
    join stg_freight_rates f
        on o.carrier = f.carrier
        and o.origin_port = f.origin_port
        and o.destination_port = f.destination_port
        and o.service_level = f.service_level
        and o.weight between f.min_weight_qty and f.max_weight_qty
    where o.carrier != 'V44_3'  -- CRF exclusion
    group by o.order_id, o.weight
)
select * from matched
```

**On including `minimum_cost`:** carried through as a reference value only (not
part of the Freight Cost Exposure formula itself, per the Section 3 decision to
use `rate` alone as the cost proxy). It can support a sense check in Tableau —
e.g. flagging customers whose average `rate` sits close to or below the
lane-level `minimum_cost` floor, which may indicate low-weight/high-frequency
shipping patterns. Same `AVG` aggregation logic applies here for the same
reason as `rate`: no column distinguishes the duplicate FreightRates rows.

Orders excluded here (854 CRF + 1,364 weight-bracket gap = 2,218 total) are not
silently dropped from the project — they remain fully present in
`stg_order_list` for Delivery Reliability and any future longitudinal
validation, since only the cost dimension is affected.