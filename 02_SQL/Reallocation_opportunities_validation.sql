-- Review and validate reallocation opportunities
--
-- Purpose:
-- Validate whether the reallocation candidates identified in
-- mart_reallocation_opportunities are structurally plausible and suitable
-- for use as operational decision-support context in Tableau.
--
-- A candidate is considered structurally eligible when an alternative plant:
--   1. supports the same product,
--   2. is connected to the same origin port,
--   3. differs from the current plant.
--
-- Capacity utilization in this analysis represents observed order pressure
-- within the analyzed dataset. It does NOT confirm physical spare capacity.


-- Step 1: Check overall candidate population.
-- Goal: understand the size and coverage of the reallocation network.

select
    count(*) as total_rows,
    count(distinct customer) as customers,
    count(distinct product_id) as products,
    count(distinct current_plant) as current_plants,
    count(distinct alternative_plant) as alternative_plants
from mart_reallocation_opportunities;

-- Result:
-- 256 structurally eligible reallocation candidates
-- 23 customers
-- 74 products
-- 5 current plants
-- 6 alternative plants
--
-- Interpretation:
-- Reallocation potential is selective rather than universal.
-- Only part of the customer network has an alternative plant satisfying
-- the same-product / same-origin-port eligibility rules.


-- Step 2: Validate the intended mart grain.
-- Goal: ensure that candidate generation did not introduce join fan-out.

select
    customer,
    product_id,
    origin_port,
    current_plant,
    alternative_plant,
    count(*) as n
from mart_reallocation_opportunities
group by
    customer,
    product_id,
    origin_port,
    current_plant,
    alternative_plant
having count(*) > 1
order by n desc;

-- Result:
-- 0 rows.
--
-- Conclusion:
-- The intended grain
-- customer × product × origin_port × current_plant × alternative_plant
-- is unique. No duplicate candidate combinations were introduced.


-- Step 3: Classify candidates by observed capacity context.
-- Goal: distinguish observed improvements from structurally eligible
-- but unobserved alternatives and higher-pressure alternatives.
--
-- Labels below match alternative_status in mart_reallocation_opportunities
-- directly, so results here are traceable back to the production column.

select
    alternative_status,
    count(*) as candidates,
    count(distinct customer) as customers
from mart_reallocation_opportunities
group by 1
order by candidates desc;

-- Result:
--
-- Unutilized Candidate:
--   225 candidates across 17 customers
--
-- Observed Improvement:
--   23 candidates across 13 customers
--
-- Higher Capacity Pressure:
--   8 candidates across 6 customers
--
-- Same Capacity Pressure:
--   0 candidates
--
-- Interpretation:
-- 23 candidates provide direct observed evidence of lower capacity pressure
-- at an active alternative plant.
--
-- 225 candidates are structurally eligible but belong to alternative plants
-- with no observed order activity in the analyzed dataset. These represent
-- potential network options, not confirmed spare capacity.
--
-- 8 candidates are structurally feasible but would move demand toward a plant
-- with higher observed capacity pressure and therefore do not represent a
-- capacity-pressure improvement.


-- Step 4: Inspect preferred alternatives.
-- Goal: validate the ranking used for operational decision support.

select
    customer,
    product_id,
    origin_port,
    current_plant,
    alternative_plant,
    alternative_status,
    current_capacity_utilization,
    alternative_capacity_utilization,
    capacity_utilization_improvement,
    order_count,
    total_units
from mart_reallocation_opportunities
where alternative_rank = 1
order by
    customer,
    product_id,
    origin_port;

-- Result:
-- Preferred alternatives show all expected cases:
--
-- Observed Improvement:
-- Current plant has higher observed capacity pressure than the alternative.
--
-- Unutilized Candidate:
-- Alternative plant supports the product and origin port but has no observed
-- orders in the analyzed dataset.
--
-- Higher Capacity Pressure:
-- Alternative is structurally eligible but has higher observed capacity
-- pressure than the current plant.
--
-- The ranking therefore preserves structurally eligible alternatives while
-- prioritizing candidates supported by observed improvement evidence.


-- Step 5: Investigate the strong presence of PLANT11.
-- Goal: verify whether PLANT11's frequent appearance as an Unutilized Candidate
-- is caused by genuine network coverage or by a join/modeling artifact.

select
    pp.plant_code,
    count(distinct pp.product_id) as supported_products,
    count(distinct p.port) as connected_ports,
    c.daily_capacity
from stg_products_per_plant pp
join stg_plantports p
    on pp.plant_code = p.plant_code
left join stg_wh_capacities c
    on pp.plant_code = c.plant_code
where pp.plant_code = 'PLANT11'
group by
    pp.plant_code,
    c.daily_capacity;

-- Result:
-- PLANT11
-- supported_products = 96
-- connected_ports    = 1
-- daily_capacity     = 332
--
-- Interpretation:
-- PLANT11's frequent appearance is structurally plausible.
-- The plant supports a broad product portfolio (96 products), is connected
-- to one origin port, and has a defined daily capacity.
--
-- Its frequent candidate status is therefore explained by network structure,
-- not by duplicate candidate generation or join fan-out.
--
-- However, no orders for PLANT11 are observed in the analyzed order dataset.
-- Its operational availability cannot be confirmed from the available data.


-- Final conclusion:
--
-- The reallocation model produces 256 unique, structurally eligible
-- customer-product-port-plant alternatives across 23 customers.
--
-- Candidate generation is technically valid:
--   - no duplicate grain combinations were found,
--   - alternatives support the same product,
--   - alternatives share the same origin-port network,
--   - current and alternative plants are distinct.
--
-- The capacity context provides additional differentiation:
--   - 23 candidates across 13 customers show lower observed capacity pressure,
--   - 225 candidates across 17 customers point to structurally eligible plants
--     with no observed order activity,
--   - 8 candidates across 6 customers show higher observed capacity pressure.
--
-- PLANT11 was separately reviewed because of its strong representation among
-- unutilized candidates. Its 96 supported products, single-port connection,
-- and recorded daily capacity explain this pattern and provide no indication
-- of a join artifact.
--
-- Decision-support interpretation:
--
-- "Observed Improvement" provides the strongest evidence for a potential
-- reallocation opportunity.
--
-- "Unutilized Candidate" identifies a structurally feasible network option,
-- but must not be interpreted as confirmed available capacity.
--
-- "Higher Capacity Pressure" remains visible for transparency but should not
-- be presented as a capacity-driven improvement.
--
-- The mart is therefore suitable as an operational decision-support layer,
-- while final reallocation decisions would require additional operational
-- information not contained in the dataset, such as confirmed available
-- capacity, production constraints, lead times, and reallocation costs.
