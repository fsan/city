# Traffic and public transport slice

## Play

T opens the movable Transport Authority window. G toggles queue pressure and vehicle-density influence clouds; O toggles street condition. Click a street in traffic view, use the street selector, or follow a queue hotspot to inspect it and assign mixed, bus, or cycle lanes, or add/remove that segment’s crosswalks. The ordinary street inspector also links to these controls.

Two circular bus lines start in Bellwether. Select a line, then Edit route on map. Stops have unique numbered street addresses and snap to the 323 street junctions. Add addresses in the window, remove/reorder stops, drag gold stop markers, or drag a route segment to insert a stop. The drawn route follows actual street links. Close or move the window to work on the map; WASD, zoom and rotation still work. Apply explicitly, or Escape to discard. New line and Remove line manage up to eight services, each initially with two buses and 2–16 unique stops. Withdrawn line slots retain their financial history and may be reused.

Fare caps and subsidies apply only when submitted. Inspect bus occupancy, speed, boardings, revenue, running costs and available operator cash. Bus buttons locate individual vehicles. Resident inspectors show transport ownership, parked locations, travel wallet, income, chosen mode, time spent waiting and departure-time choice scores. These scores combine estimated time with a cost penalty weighted by income; they are not promises of actual arrival times.

## Module boundaries

`src/simulation/transport.zig` owns vehicles, directional lane lists, junction admission, queues, bus services, fares and the temporary route draft. It imports only the scene. `residents.zig` owns trip decisions, vehicle ownership and boarding/alighting. `game.zig` orders updates and settles subsidies through `finance.zig`. Rendering never advances traffic. `web/transport.js` owns window state, address labels and map editing gestures; simulation commands validate changes in Zig. HTML remains in `web/index.html`.

IDs are stable array slots: car slot equals resident ID; bus slots start at population + line ID × 3. Two of each line's three reserved slots are used. Road allocation belongs to the road ID. Bus routes are ordered stops; dragging a segment adds a stop, not a separate non-stopping waypoint.

## Vehicles and lanes

Vehicles accelerate at 2 abstract m/s² and brake according to the available following gap. Body lengths are 1.5 for cars and 2.7 for buses, with a 0.5 safety gap. Cars have a maximum speed of 7; buses 5.5, reduced by road condition, grade and works. Each directional link has a general lane and an optional bus lane. Admission requires downstream room. Vehicles keep their footprint on the approach until they can enter the exit link, so queues can extend backwards along streets. Entry reservations prevent two vehicles claiming the same space in one fixed step.

Signals use a staggered 12-second cycle: horizontal green for five seconds, clearance, vertical green for five seconds, clearance. Junction traversal/turns are simplified to link transitions; visible red/green lamps share the admission clock, but there are no separate turning arcs, pedestrian signals or collision physics at intersection interiors. Shared scene next-hop routing favours maintained, gentler streets. Cars respond to congestion when choosing a mode, but do not dynamically detour around a queue yet.

Bus lanes use an independent lane queue. Cycle lanes raise the bicycle speed multiplier from 3 to 4.5. Both allocations reduce car speed by 20%. Existing vehicles finish their current link in their old lane when allocation changes, avoiding overlapping merges. Allocation has no construction cost or lead time in this slice. A segment can have either a bus allocation or a cycle allocation, not both.

The traffic overlay displays a three-second smoothed pressure: queued vehicles / 5, capped at 100%. A vehicle below 0.6 m/s counts as queued. This measures queue pressure, not percentage of road capacity. Road reports expose unsmoothed vehicle and queue counts. Cars and buses follow terrain height. Residents walk building frontage connectors to their parked car nodes; parked cars are stored as locations rather than individual parked geometry.

## Residents

Residents compare walking, cycling, driving and a single bus journey before departure. Walking and cycling consider slope and road condition; driving includes expected signals, current queue pressure and fuel/parking cost. A bicycle or car is usable only at its parked location. Bus estimates include access/egress walking, expected wait, ride time and fare. Direct bus journeys only: no transfers. Access and egress are limited to 45 walking-cost units. Waiting residents fall back to walking after 180 simulation seconds or if they cannot afford the fare. A changed/withdrawn line also causes walking fallback.

Initial transport cash and income are deterministic placeholders. A car costs £1,800; purchase needs £2,400 available and estimated commute time savings worth more than its running cost. Ownership is reconsidered daily at home. Car trips debit 0.014 × walking route cost + £0.30; ownership costs £8/day. Residents receive 25% of their placeholder daily income as disposable cash after living expenses. This is a mobility wallet, not a complete household/payroll economy. Bicycles are initially owned by two thirds of residents. The original short home/work routines remain; full shifts, schools and shopping are future work. Repair crews always walk so assignment interruption remains safe.

## Buses and money

Each line has two 24-seat buses and a five-second stop dwell. Riders physically walk to a stop, wait, board an available seat, ride with its vehicle and walk from their exit stop. Full buses leave riders waiting. Boarding order is resident iteration order within a simulation step, not a persistent FIFO queue.

Operators charge min(fare cap, £3). Cap and per-boarding subsidy are independently editable from £0–£10. A subsidy supports the operator; it is not an additional deduction from the passenger fare. Each line starts with £3,000 private capital. Each active bus costs £0.18/s, including while stopped. Fares and funded subsidies credit line cash; costs debit it. Unfunded subsidies are not paid and do not create municipal debt. Subsidies use uncommitted municipal money and ledger category 7, preserving work-order reserves.

When a line changes or closes, its buses finish their current segment; riders alight at the next junction and continue on foot. Empty old buses retire and revised services dispatch at their new stops. Thus passengers are never teleported, but empty fleet deployment is abstracted. Buses also unload and suspend service when operator cash runs out. The first service-agreement increment is in `service-agreements.md`; fleet purchase and full company payroll remain future work.

## Verification and limits

Docker ReleaseSafe build, JavaScript syntax checks and live in-app browser checks cover loading, new/withdrawn lines, address-based stops, stop dragging, route-segment dragging, policies and map overlays. An ephemeral WASM smoke run exercised 600 simulated seconds, live lane changes and route withdrawal; no test suite was added. It checked lane spacing, passenger conservation and capacity, and invalid command rejection. The final run completed 16,234 trips, recorded 89 boardings, kept the maximum occupancy at 24, and found no spacing violations across 61 samples; withdrawn-line riders reached zero. Render vertices were finite. Existing repair delivery was also checked after the transport integration.

Sessions are in memory and reset on refresh. There is no server authority or save format. This is a bounded, inspectable transport model, not a complete traffic engineering simulator. Keep the explicit limitations above when extending it.


## September geometry and mobility update

Roads and sidewalks split at every terrain crease. Asphalt is 3.5 m wide, accommodating the outer bus lane’s full width. Vehicles render above the highest of their four footprint corners, and their stop position leaves half-body clearance before the node. Body-length following gaps still apply. Turns remain discrete rather than swept collision geometry; accidents are not simulated.

The amber traffic plot uses measured current vehicle counts, grouped into 3×3-junction areas below 2× zoom and individual junction areas closer in. Each cloud is centred at the vehicle-count-weighted street midpoint, with radius growing with count. It illustrates local concentration rather than an empirically calibrated congestion catchment. Street colours retain the independent queue-pressure measure. The plot updates every twelve rendered frames.

Focused verification after this update: Docker ReleaseSafe build and browser load, zoom, traffic overlay, crossing toggle and service-offer UI. A temporary WASM smoke check completed 14,137 trips over 640 simulation seconds, with 434,484 maximum sampled vertices, finite render data and valid reserves. Separate checks covered car/pedestrian picking, fleet reduction and passenger conservation. No persistent test suite was introduced.
