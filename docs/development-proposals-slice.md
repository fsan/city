# Development proposals and permits (numbered list item 10; next free slice label 18)

Bounded batch: private construction that responds to the zoning the player has
applied and to the demand the live simulation has actually generated. A private
developer lodges a proposal for a zoned vacant site; the player grants or
refuses the permit; an approved proposal pays a development levy into the
municipal ledger and is built over a bounded number of simulation days. No new
crews, materials, terrain grading or foundation costs are added — those are
numbered item 11, and this batch must not pre-empt them.

The label is recorded as 18 because 15, 16 and 17 are already taken by the
dense-town batch and its repair, and item 11 of the numbered list collides with
the traffic-signal note. See the numbering note in `Next Agent Kickoff.md`.

## What the town could not do before

`docs/city-planning.md` records the inherited state: zoning "defines permitted
future use; it does not yet simulate developer demand or automatic
construction. Road-frontage parcel packing is deliberately simple and axis
aligned; redevelopment and parcel subdivision remain future work." Every vacant
lot placed by `seedBuildings` stayed vacant for the whole session, so a player
could zone a district and watch nothing happen, and the report panel had no
development domain to read.

## Rules now in force

- **Sites are authored vacant lots, redeveloped in place.** A proposal always
  targets a lot whose `kind` is `.vacant` and whose parcel is zoned
  residential, commercial, industrial or mixed. The lot keeps its identity,
  position, frontage, node, street and address number; only its use, height,
  value and capacity change, and the parcel's `building` link is filled in. No
  array grows, no identifier is renumbered and no parcel is created, so the
  snapshot, the renderer, the assessment roll and every report agree by
  construction.
- **Unzoned and civic-reserve land is never developed.** Zone 0 and zone 5 are
  refusals, not a slow path.
- **Demand is measured, not assumed.** For each district the scan reads the
  live town: occupied residents per dwelling and occupied residents per
  commercial premises, each normalised against the same ratio for the whole
  city. A district is only eligible when its own ratio stands at or above
  `demand_threshold` (1.35x the citywide ratio) and it still has an eligible
  vacant site.
- **Use follows the zone.** Residential zoning proposes a home or apartment,
  commercial zoning proposes a shop, office or market, industrial zoning
  proposes a works depot, and mixed use takes whichever of the two pressures is
  higher. The choice is recorded on the proposal so the player can see what was
  asked for and why.
- **Bounded lodging.** At most `max_lodged_per_day` (2) proposals are lodged per
  simulation day, a district holds at most one undecided proposal, and the
  undecided queue is capped at `max_pending` (8). The scan runs once per day, in
  the same rollover that already runs housing, employment and parking.
- **Undecided proposals lapse.** A proposal carries a deadline of
  `offer_days` (5) simulation days. Silence is a decision: a lapsed proposal is
  retired with its own reason and never builds.
- **The permit is the money.** Granting a permit takes
  `levy_rate` (0.0005) of the assessed value as a development levy, rounded to
  pennies and recorded in the municipal ledger as kind 12 with the proposal's
  own one-based number. Construction is the developer's cost and never touches
  the municipal account. A refused or lapsed proposal moves no money.
- **Construction is bounded and visible.** An approved proposal builds for
  `build_days` (2 to 6 days, from the proposed height) of simulation time, then
  completes. Until then the lot is still vacant, so nothing is built early.
- **A completed dwelling becomes a real home.** The new unit is enrolled in the
  housing roll exactly as `housing.init` enrols an authored home, with the same
  rent and ownership-cost formulas, so the existing move search can find it and
  a household can genuinely move in.
- **A completed workplace becomes a real employer.** The new building appends
  one company and takes the next company index, with the same capacity, wage,
  skill requirement and contractor flag `residents.init` derives from the same
  kind. Existing company indices are untouched, so employment, wage arrears and
  the crew lists keep their meaning.
- **Refusals are explicit.** A refusal or lapse records one of: no eligible
  site, not zoned for development, no measured demand, site already built on,
  refused by the authority, or lapsed undecided. A refused proposal can never
  be revived; a fresh proposal for the same site is a new application.

## Measured

The numbers below come from a throwaway ReleaseSafe probe outside the
repository. The dense town is fixed, so the probe reports the same authored
baseline the slice-17 note records (820 lots of 900 storage, 1,328 nodes of
1,600, 1,624 roads of 3,200) and then measures what development does to it.

| check | result |
|-------|--------|
| authored town, unchanged | 820 lots of 900 storage, 1,328 nodes, 1,624 roads |
| composition after the site reserve | 10 vacant, 265 homes, 93 apartments, 130 shops, 105 offices, 13 depots, 91 bicycle parks, 2 car parks |
| eligible sites before any zoning | 0 |
| districts over the demand threshold | 7 of 12 hold a vacant site; the busiest, district 4, measures 2.058x |
| first application | lodged on the engine's own site (parcel 29), zone 1, apartment, levy £1,300.00, deadline 4400 |
| levy reconciliation | cash delta and ledger kind-12 delta both equal £1,300.00 |
| completion | dwelling enrolled with rent £117.00 and ownership cost £57.20, occupants 0, parcel link filled |
| workplace completion | office, capacity 95, company count 295 -> 296, employer link correct |
| refusal / lapse | refused and lapsed with no money moved and their own reason codes |
| zoning respected | every application sits on zone 1-4; unzoned and civic land never attracts one |
| v13 save/load round trip | result 0, count 9, next_number 10, built 2, levies £2,500.00, pending 3 |
| staged round trips | load 0 at init, offer, accept, built, refuse, lapse and shop |
| v12 file | result 3 |
| six simulated days | peak 1,126 cars, 11 applications lodged, £2,500.00 in levies |

## Limits

- Construction is deliberately abstract: no crews, no materials, no terrain
  grading and no foundation cost. Numbered item 11 owns those.
- A proposal never redevelops an occupied or already built lot, so the authored
  town's standing buildings are permanent in this batch.
- Demand is a structural ratio of residents to dwellings and premises, not a
  price model: it says where the town is crowded, not what a square metre is
  worth.
- The levy is a flat share of assessed value. There is no tender, no competing
  applicant and no negotiation.
