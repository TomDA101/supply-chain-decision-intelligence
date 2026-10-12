-- Fan-out diagnosis (duplicate matches per order)

-- Diagnosis: how many FreightRates rows match per order?
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
order by n_matches ;


-- Root cause check

select carrier, origin_port, destination_port, service_level,
       min_weight_qty, max_weight_qty,
       count(distinct carrier_type) as n_carrier_types,
       count(distinct transport_mode ) as n_modes,
       count(*) as n_rows
from stg_freight_rates
group by 1,2,3,4,5,6
having count(*) > 1
order by n_rows desc
limit 10 ;


-- Zero-match diagnosis (orders with no rate at all)

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
and o.carrier != 'V44_3'  -- CRF exclusion ;


-- Check A: Root cause breakdown

select distinct o.carrier, o.origin_port, o.destination_port, o.service_level
from stg_order_list o
where o.carrier != 'V44_3'
and not exists (
    select 1 from stg_freight_rates f
    where o.carrier = f.carrier and o.origin_port = f.origin_port
      and o.destination_port = f.destination_port and o.service_level = f.service_level
) ;


-- Check B — lane exists, but the order weight falls outside all brackets defined for that specific lane

select count(*) as n_zero_matches_non_crf
from stg_order_list o
where o.carrier != 'V44_3'
and not exists (
    select 1 from stg_freight_rates f
    where o.carrier = f.carrier and o.origin_port = f.origin_port
      and o.destination_port = f.destination_port and o.service_level = f.service_level
      and o.weight between f.min_weight_qty and f.max_weight_qty
) ;
