-- Review and verify notable data from the Tableau view
--
-- C46 (predominantly red, Freight) and C29 (predominantly orange, Delivery) stand out sharply.
-- Under operational weighting (Delivery = 60%), the orange dominance of C29 is expected,
-- but C46's large red Freight component—despite a Freight weight of only 20%—looked like a
-- genuine outlier in the raw data (possibly a few orders with very high rates).


-- Step 1: Pull C46's raw freight inputs and order count.
-- Goal: check if this is a thin sample (1-2 orders skewing the average) or a robust value.

select customer_label, customer, weighted_avg_rate, n_freight_orders, freight_cost_exposure_norm
from mart_customer_apindex
where customer_label = 'C46';

-- Result: weighted_avg_rate = 3.4665 (≈ the dataset-wide max), backed by 761 orders —
-- not a thin sample. The customer's rate genuinely sits at the top of the distribution.


-- Step 2: Break the rate down by lane (carrier/port/service level) to see if it's driven
-- by one specific lane or spread evenly across C46's orders.

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

-- Result:
-- 729 orders via PORT04→PORT09 (DTP) at the normal rate (0.048) — the majority, unremarkable
-- 32 orders via PORT09→PORT09 (DTP) at 12.2784 — ~256x higher than the normal lane
-- The high average is driven almost entirely by this one small, high-rate lane.


-- Step 3: Is PORT09→PORT09 (origin = destination) a one-off oddity or a recurring pattern
-- in FreightRates?

select carrier, origin_port, destination_port, service_level, min_weight_qty, max_weight_qty, rate
from stg_freight_rates
where origin_port = destination_port;

-- Result: recurring — multiple carriers (V444_8, V444_5, V444_0) have rate entries for this
-- combination, at clearly different price levels. Not a single bad row.


-- Step 4: Broader check — how many lanes overall have an extreme rate spread (max/min > 10x)
-- within the same carrier/route/service level? Tests whether this is isolated or systemic.

select carrier, origin_port, destination_port, service_level,
       min(rate) as min_rate, max(rate) as max_rate, count(*) as n_rows
from stg_freight_rates
group by carrier, origin_port, destination_port, service_level
having max(rate) / nullif(min(rate), 0) > 10
order by max(rate) desc;

-- Result: several lanes show a wide min/max spread, but on inspection this reflects the
-- normal weight-bracket rate structure (many narrow brackets, expected discount tiering),
-- not the same anomaly seen for C46.


-- Step 5: Hypothesis — does the PORT09→PORT09 anomaly come from a narrow bracket nested
-- inside a wide "catch-all" bracket (0–5,000 kg) for the same lane, so a single order
-- matches both and the fan-out join averages a normal rate with an extreme one?

select a.carrier, a.origin_port, a.destination_port, a.service_level,
       a.min_weight_qty as narrow_min, a.max_weight_qty as narrow_max, a.rate as narrow_rate,
       b.min_weight_qty as wide_min, b.max_weight_qty as wide_max, b.rate as wide_rate
from stg_freight_rates a
join stg_freight_rates b
    on a.carrier = b.carrier
    and a.origin_port = b.origin_port
    and a.destination_port = b.destination_port
    and a.service_level = b.service_level
    and a.min_weight_qty >= b.min_weight_qty
    and a.max_weight_qty <= b.max_weight_qty
    and a.rate != b.rate
where a.origin_port = a.destination_port;

-- Result: 60 rows returned, but on inspection min/max bounds were identical between "a" and
-- "b" — this condition also catches exact-duplicate brackets, not true nesting. Needs a
-- stricter check (step 6).


-- Step 6: Re-run with a strict nesting condition (excludes exact-duplicate brackets, keeps
-- only genuine subset relationships).

select a.carrier, a.origin_port, a.destination_port, a.service_level,
       a.min_weight_qty as narrow_min, a.max_weight_qty as narrow_max, a.rate as narrow_rate,
       b.min_weight_qty as wide_min, b.max_weight_qty as wide_max, b.rate as wide_rate
from stg_freight_rates a
join stg_freight_rates b
    on a.carrier = b.carrier
    and a.origin_port = b.origin_port
    and a.destination_port = b.destination_port
    and a.service_level = b.service_level
    and a.min_weight_qty >= b.min_weight_qty
    and a.max_weight_qty <= b.max_weight_qty
    and (a.min_weight_qty > b.min_weight_qty or a.max_weight_qty < b.max_weight_qty)
where a.origin_port = a.destination_port
order by (b.max_weight_qty - b.min_weight_qty) desc;

-- Result: 0 rows. Nesting hypothesis rejected.


-- Conclusion:
-- C46's outlier value is fully explained by the already-documented fan-out ambiguity
-- (duplicate rate brackets with no distinguishing column, resolved via AVG(rate) per the
-- join diagnosis) — not a new data issue. On the PORT09→PORT09 lane, the duplicate brackets
-- happen to have an unusually wide rate spread (0.03 vs. 12-22), which is why this customer's
-- average is pulled so high. No exclusion needed; existing AVG-based handling already covers
-- this case. Flagged in the dashboard as a validated, explainable outlier rather than removed.
-- The PORT09→PORT09 rate anomaly likely reflects a different fee type than standard freight transport:
-- the high-rate entries (12-21) are all GROUND mode with 0-1 transit days (vs. AIR, 0-14 days for the normal-rate entrieson this lane)
-- and origin equals destination. This pattern is more consistent with a local handling/storage fee than a transport rate,
-- though the dataset contains no field confirming this explicitly.
