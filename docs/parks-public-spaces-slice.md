# Parks and public spaces (numbered list item 13)

This slice gives the authored green lots consequences. Before it, a park was
drawn, planted and walked to, and nothing else read it: no condition, no
maintenance bill, no measured catchment, and no value anywhere in the model.
`src/simulation/parks.zig` is new and owns all of it.

## What changed

- Every park, playground and plaza now carries a record keyed to its authored
  lot: a condition (0–100), visits today and ever, and the maintenance money it
  has personally received. The record never invents a second map, so
  redevelopment, the renderer and the snapshot all keep reading one row per lot.
- The walking graph decides the catchment. A green lot counts a home only when
  `city.walkCost` reaches it inside 900 m, so a park across the river or behind a
  missing link serves nobody. The same cost decides which green space a resident
  picks for a leisure errand, and a neglected park is measurably less attractive.
- Maintenance is a real municipal expense. Each park needs a bounded daily
  amount — an area rate, a kind rate and a small per-visit wear term — and the
  chosen funding level (minimum, standard, enhanced) multiplies it. The city
  pays it in sixteen bounded instalments through the ordinary 30-second
  operating pass, recorded in the municipal ledger as **kind 13**. When the
  treasury cannot pay, coverage falls and the park simply deteriorates.
- Condition moves in both directions each frame: it recovers in proportion to
  the paid coverage and wears with use. Nothing else changes it.
- Amenity is bounded to **+5%** of a lot's assessed value. `city.assessedValueFor`
  already multiplied the authored base by measured sunlight and road access; it
  now multiplies by the best nearby park benefit as well, so a cared-for park
  lifts its neighbours' assessment and a neglected or distant one does not.
- District trust reads `parks.districtBenefit`, so a neglected park is a real
  local cost rather than a cosmetic one.

## Commands and data

- `parks_create(parcel, kind)` converts a vacant lot already zoned **Civic /
  park reserve** into a park (0), playground (1) or plaza (2). It charges the
  municipal ledger **kind 14** and refuses when the parcel, the zone or the
  funds do not allow it. The lot keeps its identity, position, frontage, node,
  street and address number; only its use, value, height and parcel link change.
- `parks_set_funding(level)` accepts 0–2.
- Group 32 reads one public-space record: 0 lot, 1 kind, 2 district, 3/4 x/z,
  5/6 width/depth, 7 condition, 8/9 visits today/ever, 10/11 accessible homes
  and residents, 12/13 mean walk and access score, 14/15 maintenance needed and
  paid today, 16 coverage, 17 amenity benefit, 18 lifetime maintenance received,
  19/20 the street and number the lot fronts, so the panel shows an address
  rather than raw world coordinates.
- Group 0 fields 90–105 are the running totals: 90 park count, 91 mean
  condition, 92/93 visits ever/today, 94–96 maintenance spend/need/paid, 97
  coverage, 98 parks below standard, 99 accessible homes, 100 mean amenity, 101
  funding level, 102 parks created, 103 municipal construction spend, 104
  residents within a catchment, 105 green area in square metres.
- `web/planning.js` gains a **Parks** mode on G with a condition/catchment table,
  a funding selector and the conversion button; it only reports back what Zig
  accepted, exactly like the road, zoning and permit panels.

## Save schema

Schema moves to **v16 / `bellwether-2028-02-v16`**; v15 and older files are
rejected with result 3. The public-space ring, its funding and its two money
counters are serialized and validated field by field: each record must name a
green lot, each must be unique, condition and visits are bounded, and the
maintenance counters stay ordered. Catchment, access score and amenity are
derived and therefore never trusted from a file — `parks.restore` recomputes
them, then `city.reassess()` rebuilds the roll.

Three pre-existing save-path defects were repaired while chasing round trips, as
the earlier kickoff instructed when a slice touches the snapshot: the
development plan left `road.works` flags with no owning contract order, so an
init save was invalid; the housing validator required
`owner_cash >= paid_rent + paid_ownership`, which a longer session breaks once
taxes draw owner cash; and kerbside occupancy was bounded by the whole parking
facility list instead of the kerbside spaces. The ledger's kind ceiling also
rises to 14, with kinds 13 and 14 named to their own party/order rules.

## Verified

A focused ReleaseSafe probe outside the repository reports `checks=33
failures=0` on the development town: 820 lots / 1,328 nodes / 1,624 roads with
64 authored green lots and one record each; mean condition 72.95 and mean
amenity 0.6549, with 358 homes and 3,840 residents inside a catchment; a daily
maintenance need of GBP 3,061.38 paid in bounded instalments and booked as a
kind-13 municipal expense; a minimum funding level paying GBP 956.70 of the
GBP 3,061.38 need over a whole day and the enhanced level paying GBP 2,870.00
(0.31x and 0.94x of the bill), with an invalid level refused; real resident
visits recorded on walking arrivals (869 ever, 304 in the sampled day); civic
reserve parcel 29 converted at GBP 5,077.76, the lot becoming green space and
booking as kind 14, and a non-reserve vacant lot refused; park amenity lifting a
neighbour's assessed value with a positive assessed roll; positive district
trust while funded; and a v16 round trip returning 0 at 7,938,408 bytes with a
v15 file returning 3. Docker ReleaseSafe builds and `node --check` pass, and
`make build` publishes `/output/city.wasm`.

## Limits

- Condition, the daily area/kind/visit rates and the funding multipliers are
  bounded policy numbers, not tenders or real maintenance schedules. There is no
  equipment inventory, no vandalism, no season and no staffing model.
- The catchment is a walk-graph distance, not a measured park usage survey, and
  the amenity term is a single bounded multiplier rather than a hedonic price.
- New public space can only convert an already zoned civic reserve; the slice
  does not demolish standing buildings, buy land, or subdivide parcels.
- The renderer still plants every green lot from its own seed and does not draw
  condition, so a neglected park looks the same as a cared-for one.
