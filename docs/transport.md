# Traffic and public transport slice

## Play

T opens the movable Transport Authority window. G toggles queue pressure and vehicle-density influence clouds; O toggles street condition. Click a street in traffic view, use the street selector, or follow a queue hotspot to inspect it and assign mixed, bus, or cycle lanes, or add/remove that segment’s crosswalks. The ordinary street inspector also links to these controls.

Two circular bus lines start in Bellwether. Select a line, then Edit route on map. Stops have unique numbered street addresses and snap to valid kerbside sidewalk locations, not arbitrary road or building centres. Add addresses in the window, remove/reorder stops, drag gold stop markers, or drag a route segment to insert a stop. Active lines keep visible kerbside stop poles and signs on the map even when the Transport Authority window is closed; the selected line adds a larger highlight. The drawn route follows actual street links. Close or move the window to work on the map; WASD, zoom and rotation still work. Apply explicitly, or Escape to discard. New line and Remove line manage up to eight services, each initially with two buses and 2–16 unique stops. Withdrawn line slots retain their financial history and may be reused.

Fare caps and subsidies apply only when submitted. Inspect bus occupancy, speed, boardings, revenue, running costs and available operator cash. Bus buttons locate individual vehicles. Resident inspectors show transport ownership, parked locations, household balance, income, chosen mode, time spent waiting and departure-time choice scores. These scores combine estimated time with a cost penalty weighted by income; they are not promises of actual arrival times.

## Module boundaries

`src/simulation/transport.zig` owns vehicles, directional lane lists, junction admission, queues, bus services, fares and the temporary route draft. It imports the scene and independent operator accounts. `residents.zig` owns trip decisions, vehicle ownership and boarding/alighting. `game.zig` orders updates and settles subsidies through `finance.zig`. Rendering never advances traffic. `web/transport.js` owns window state, address labels and map editing gestures; simulation commands validate changes in Zig. HTML remains in `web/index.html`.

IDs are stable array slots: car slot equals resident ID; bus slots start at population + line ID × 3. Two of each line's three reserved slots are used. Road allocation belongs to the road ID. Bus routes are ordered stops; dragging a segment adds a stop, not a separate non-stopping waypoint.

## Vehicles and lanes

Vehicles accelerate gradually and carry momentum across ordinary street segments instead of stopping at every node. They brake for actual target stops, red signals, blocked downstream lanes and the following gap; a failed entry settles the vehicle at the node rather than producing a per-segment stutter. Body lengths are 1.5 for cars and 2.7 for buses, with a 0.5 safety gap. Cars have a maximum speed of 7; buses 5.5, reduced by road condition, grade and works. Each directional link has a general lane and an optional bus lane. Admission requires downstream room. Vehicles keep their footprint on the approach until they can enter the exit link, so queues can extend backwards along streets. Entry reservations prevent two vehicles claiming the same space in one fixed step.

Signals use a staggered 12-second cycle: horizontal green for five seconds, clearance, vertical green for five seconds, clearance. Junction traversal/turns are simplified to link transitions; visible red/green lamps share the admission clock, but there are no separate turning arcs, pedestrian signals or collision physics at intersection interiors. Shared scene next-hop routing favours maintained, gentler streets. Cars respond to congestion when choosing a mode, but do not dynamically detour around a queue yet.

Bus lanes use an independent lane queue. Cycle lanes raise the bicycle speed multiplier from 3 to 4.5. Both allocations reduce car speed by 20%. Existing vehicles finish their current link in their old lane when allocation changes, avoiding overlapping merges. Allocation has no construction cost or lead time in this slice. A segment can have either a bus allocation or a cycle allocation, not both.

The traffic overlay displays a three-second smoothed pressure: queued vehicles / 5, capped at 100%. A vehicle below 0.6 m/s counts as queued. This measures queue pressure, not percentage of road capacity. Road reports expose unsmoothed vehicle and queue counts. Cars and buses follow terrain height. Residents walk building frontage connectors to their parked car nodes; parked cars are stored as locations rather than individual parked geometry.

## Residents

Residents compare walking, cycling, driving and a single bus journey before departure. Walking and cycling consider slope and road condition; driving includes expected signals, current queue pressure and fuel/parking cost. A bicycle or car is usable only at its parked location. Bus estimates include access/egress walking, expected wait, ride time and fare. Direct bus journeys only: no transfers. Access and egress are limited to 45 walking-cost units. Waiting residents fall back to walking after 180 simulation seconds or if they cannot afford the fare. A changed/withdrawn line also causes walking fallback. Those real transitions are counted in the passenger-outcome report, not inferred from arrivals.

Car ownership is a household purchase: a car costs £1,800 and the household must hold £2,400 to buy one. A purchase is made only when the daily time a car saves over the resident's own alternative (cycling where they own a bicycle, walking where they do not) is worth more than that day's running cost, valued at the resident's posted wage. Ownership is reconsidered daily at home. Car trips debit 0.014 × walking route cost + £0.30; ownership costs £8/day. Purchase and trip costs come from the shared household balance, not a separate mobility wallet. Bicycles are initially owned by two thirds of residents. The original short home/work routines remain; full shifts, schools and shopping are future work. Repair crews always walk so assignment interruption remains safe.

## Buses and money

Each line has two 24-seat buses and a five-second stop dwell. Riders physically walk to a stop, wait, board an available seat, ride with its vehicle and walk from their exit stop. Full buses leave riders waiting. Boarding order is resident iteration order within a simulation step, not a persistent FIFO queue.

Operators charge min(fare cap, £3). Cap and per-boarding subsidy are independently editable from £0–£10. A subsidy supports the operator; it is not an additional deduction from the passenger fare. One working-capital account per company funds all its lines; line totals only attribute income/costs. Costs are £0.06 vehicle + £0.12 labour per active bus-second, including held traffic, plus £2 prepaid clearance at dispatch. See `service-agreements.md` for capital, shifts and safe retirement accounting. Unfunded subsidies are not paid and do not create municipal debt. Subsidies use uncommitted municipal money and ledger category 7, preserving work-order reserves.

When a line changes or closes, its buses finish their current segment; riders alight at the next junction and continue on foot. Empty old buses retire and revised services dispatch at their new stops. Thus passengers are never teleported, but empty fleet deployment is abstracted. Buses also unload and suspend service when operator cash runs out. The first service-agreement increment is in `service-agreements.md`; explicit bus purchases, sales, maintenance and driver recruitment are in `operator-workforce-slice.md`.

A service bus occupies a specific owned unit for its whole trip, including the clearing leg after a withdrawal or route change, so a clearing bus physically blocks replacement dispatch. Units wear only while moving, dwelling or held in traffic; clearing causes no wear. An exhausted unit stops at the next stop, unloads and enters paid maintenance, and a repair that cannot be funded leaves the unit unavailable rather than creating hidden debt.

## Verification and limits

Docker ReleaseSafe build, JavaScript syntax checks and live in-app browser checks cover loading, new/withdrawn lines, address-based stops, stop dragging, route-segment dragging, policies and map overlays. An ephemeral WASM smoke run exercised 600 simulated seconds, live lane changes and route withdrawal; no test suite was added. It checked lane spacing, passenger conservation and capacity, and invalid command rejection. The final run completed 16,234 trips, recorded 89 boardings, kept the maximum occupancy at 24, and found no spacing violations across 61 samples; withdrawn-line riders reached zero. Render vertices were finite. Existing repair delivery was also checked after the transport integration.

The live simulation runs in browser memory and resets on refresh. Manual local save/load restores an exported town, including journeys, routes and observations; see `save-load-slice.md`. There is no server authority or automatic persistence. This is a bounded, inspectable transport model, not a complete traffic engineering simulator. Keep the explicit limitations above when extending it.


## September geometry and mobility update

Roads and sidewalks split at every terrain crease. Asphalt is 3.5 m wide, accommodating the outer bus lane’s full width. Vehicles render above the highest of their four footprint corners, and their stop position leaves half-body clearance before the node. Body-length following gaps still apply. Turns remain discrete rather than swept collision geometry; accidents are not simulated.

The amber traffic plot uses measured current vehicle counts, grouped into 3×3-junction areas below 2× zoom and individual junction areas closer in. Each cloud is centred at the vehicle-count-weighted street midpoint, with radius growing with count. It illustrates local concentration rather than an empirically calibrated congestion catchment. Street colours retain the independent queue-pressure measure. The plot updates every twelve rendered frames.

Focused verification after this update: Docker ReleaseSafe build and browser load, zoom, traffic overlay, crossing toggle and service-offer UI. A temporary WASM smoke check completed 14,137 trips over 640 simulation seconds, with 434,484 maximum sampled vertices, finite render data and valid reserves. Separate checks covered car/pedestrian picking, fleet reduction and passenger conservation. No persistent test suite was introduced.

## Measured stop regularity

Transport Authority → Observed stop arrivals & regularity reports actual approach-to-dwell visits, current waiting counts and completed interarrival intervals in simulation seconds. Deployment, clearance and relief-only junction stops are excluded. Stops with no visits or eligible interval pairs are explicitly unobserved/insufficient. Full buses count as arrivals; these measurements do not promise a seat or describe resident waiting duration.

Current and most recent retired route/coverage records remain separate, with stable stop-node identities. Edits and withdrawal archive the prior route; coverage changes start a new record. Daytime intervals spanning closed hours are omitted; all-day intervals include midnight. Last eligible/mean/min/max remain aggregates of eligible completed pairs, so the last eligible interval may predate the latest arrival. Locate buttons focus the stop. See [precise semantics and checks](stop-regularity-slice.md). No payment or penalty rules changed.

Agreement-specific interval targets are now available under Bus operators & service agreements. These start fresh at acceptance and retain results in the agreement register; they do not reuse lifetime route statistics. Live first-arrival/overdue states and route-change suspension are diagnostic only. See service-agreements.md and regularity-target-slice.md.

## Passenger waiting outcomes

Transport Authority → Passenger waiting outcomes and District bus-wait comparison report what happened to residents who actually waited. A wait start is recorded on the first fixed step at the boarding stop. A completed wait is an actual boarding; mean/min/max use completed waits only. Current waiting is live and excluded from those averages. A full in-service bus encountered by an eligible waiting resident is one capacity denial per bus dwell; a later boarding does not erase the denial.

Abandonments separate scheduled timeout, closed-hours timeout, unaffordable fare, and route/service removal. An abandoned-after-capacity flag records that a full bus had been encountered, without claiming that capacity alone caused the abandonment. Records stay with the current or most recent retired route/coverage version, and route edits/withdrawal close waits against the old version before archiving. District comparison groups observed waits by the resident's home district; it is not population-wide access and excludes trips that chose walking, cycling or driving. See [passenger outcomes slice](passenger-outcomes-slice.md). No fare, boarding-order, dispatch, routing, agreement or payment rule changed.

## Street types, parking and learned travel

Street segments now have a class — lane, street or avenue — chosen in the road
tool and priced at £18/£25/£40 per metre. Class sets the car speed limit, so an
avenue carries cars at 1.18× the 7 m/s base while a lane is limited to 0.82×.
Free-flow speeds are proportional: pedestrians walk at 1.4 m/s, cyclists ride at
4.2 m/s (5.0 in a protected cycle lane) and cars are faster than both.

Walkers and cyclists now obey the same signals as cars. A turn across a junction
is admitted while the marked crossing's parallel pedestrian phase is green, or
while no vehicle is within 14 m of the junction when no crossing is marked; a
30-second bounded patience stops anybody being stuck. Cars yield when somebody
is actually on the crossing. Waiting is recorded per resident.

Bicycle parks and car parks are seeded where districts are busy, each with a
hard slot count, and streets and avenues add kerbside car spaces priced in bands
by the movement actually observed on that segment, capped at £1.20. A traveller
aims for the place they expect to be free, falls back to the nearest free space
when the first choice is full, and walks the rest of the way; a cyclist rides
the kerb-side lane of their own direction of travel and parks before entering a
building. A bicycle kept at home is taken inside; a return journey parks on the
street in this slice.

Every resident keeps a small learned model: mean observed trip seconds per mode
and departure bucket, and a remembered chance of a free space per parking place
and arrival bucket, updated as a simple first-order Markov estimate. Both are
folded in as one bounded batch when residents arrive at work or home. Mode
choice and the time to leave home read that model, so a car-owning household
that bought a car uses it unless another mode is clearly better. The departure
lead is taken from the fastest mode the resident could actually use, so a longer
learned commute leaves home earlier and car owners use the shorter car estimate. Parking fees
are municipal receipts in ledger kind 11. See
[the slice note](street-types-parking-learning-slice.md) for limits.
