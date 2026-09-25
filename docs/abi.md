# Browser / Zig boundary

`src/main.zig` exports commands and a read-only scalar accessor `read(group, id, field)`. It returns f64 values, using -1 for missing records. JavaScript presentation helpers live in `web/data.js` and `web/reports.js`; Zig retains all rule validation. Do not infer Zig struct packing in JavaScript.

Groups: 0 city metrics; 1 properties; 2 districts; 3 residents; 4 companies; 5 streets; 6 orders; 7 ledger (newest first); 8 history (oldest retained first). The corresponding switches in `main.zig` are the field contract. Keep field numbers stable when extending it. District names use a UTF-8 pointer plus length.

Passenger service outcomes are exposed by groups 18/19 (per stop), group 10 fields 35–40 (per line), and group 22 (per home district). They count real simulation transitions in `residents.zig`; report polling never increments them.

Commands: init, update, set_speed, set_funding, apply_taxes, offer, revise, cancel_order; camera pan/rotate/zoom_at/reset_camera/focus/pick; select_resident and set_overlay. `quote` exposes each company's current estimated minimum and refusal reason for a draft. Money and order commands return success or an explicit validation result; errors never partly mutate a transaction.

`draw` fills a reusable vertex buffer and returns vertex count. `vertex_pointer` plus memory exposes interleaved clip XYZ/RGB floats. UI refreshes twice per real-time second and only builds visible reports. Table cells are reused so refreshing a report does not steal keyboard focus. Snapshot history is recorded every 30 simulation seconds, up to 96 records; no invented pre-session history.

## Transport extension

Groups 9–12 are transport policy/counters, bus lines, street nodes and vehicles. Existing group numbers remain stable. Resident fields 13–26 add mode (0 walk, 1 cycle, 2 car, 3 bus), wallet, income, car/bike ownership, bus wait, bus vehicle ID, parked car node, four departure scores (-1 unavailable), chosen bus line and parked bike node. Fields 30/31 expose an in-progress wait start timestamp (-1 not waiting) and full-bus mask (debug/verification). Street fields 10–13 are vehicle count, queue count, smoothed pressure and allocation (0 mixed, 1 bus, 2 cycle).

Group 9 fields 0–4: fare cap, boarding subsidy, total paid subsidy, actual fare, node count; 5–8: active trips per mode; 9: people waiting at stops. Group 10 fields 0–8: active, stop count, boardings, cumulative revenue, costs, operator cash, fleet count, aboard, route version. Fields 16–31 are ordered stop node IDs. Fields 35–40 are wait starts, completed waits, capacity denials, abandoned waits, mean completed wait (seconds), and abandoned-after-capacity for the current observation record. Group 11 fields 0–4: world x/z/elevation, screen x/y. Fields 5/6 are street ID and number; 7/8 are the kerbside stop world position, 9 is valid-stop, and 10/11 are the kerbside stop screen position. Group 12 fields 0–10: active, x/z, speed, passengers, node/next, segment progress, line ID (-1 car), dwell, current lane.

Commands: `transport_policy(cap, subsidy)` validates bounds; `transport_select(id)` selects an overlay; `transport_draft(count)` and `transport_stop(index,node)` populate a draft; `transport_apply(line)` validates the complete draft atomically; `transport_edit_end()` hides the draft; `transport_remove(line)` withdraws service; `transport_lane(road,allocation)` changes allocation. `route_next(from,to)` returns the street path used by the editor and buses. `focus(12,id)` locates a vehicle. Overlay modes are 0 off, 1 street condition, 2 traffic pressure.

Avoid copying large global arrays into read paths: iterate by reference. This slice exposed WASM stack exhaustion when expanding the resident record while iterating array values; references fixed it without increasing memory limits. All reporters use the scalar interface, never struct offsets.


## Geometry / crossing / agreement additions

- Group 0 fields 26/27: selected resident (-1 none), camera zoom.
- Group 1 field 12: sunlight assessment proxy (0.35–1).
- Group 3 field 27: actual trip origin node.
- Group 5 field 14: segment crosswalks enabled.
- `set_crosswalk(road, enabled)` validates 0/1, changes both endpoint markings, rebuilds walking routes.
- Group 13 (line ID): 0 status (none/offered/active/expired/cancelled), 1 operator, 2 fleet, 3 duration seconds, 4 maximum price, 5 paid, 6 remaining reserved, 7 delivered bus-seconds, 8 refusal (none/capacity/price), 9 start time.
- Group 14 (operator ID 0–2): 0 capacity, 1 assigned fleet/drivers, 2 cumulative agreement receipts.
- `service_offer(line, operator, fleet, days, price)` reserves a valid offer; `service_cancel(line)` settles earned pennies and releases the balance.
- Building kind 7 is vacant land. Existing IDs and enum values are retained.


## Traffic signals and crosswalks

Group 29 exposes traffic-signal heads as one flat index over junctions and their
arms. Fields: 0 junction index, 1 node, 2 street, 3 arm slot, 4 arms on that
junction, 5 state (0 red, 1 amber, 2 green), 6 green seconds, 7 amber seconds,
8 full cycle seconds, 9 seconds until this arm changes, 10/11 head world x/z,
12 signalised junction count, 13 minimum green, 14 maximum green. Exactly one
arm of a junction is green at a time; a junction with no signal is uncontrolled
and its vehicles are never gated.

Green and amber are simulation seconds, and one simulation second is three
simulation minutes. `signal_set_green(node, seconds)` and
`signal_set_yellow(node, seconds)` clamp to the group-29 minimum and maximum and
return the applied value, or -1 when that junction has no signal. The floors are
half a simulation second for green and amber (fields 13/14 and 26/27) and zero
for the off time (fields 24/25), so small values such as 1.0 or 0.5 are stored
exactly as typed rather than replaced by a larger default.

Commands: `signal_place(road, node)` signalises an existing road end and returns
its flat head, refusing a road that does not touch the node. `signal_remove(node)`
turns a junction's signal off. `signal_place_screen(x, y)` and
`crosswalk_place_screen(x, y)`/`crosswalk_remove_screen(x, y)` take screen pixels
and snap to the nearest junction arm or street segment within 9 m; a crosswalk
also signalises a junction end whose degree is 3 or more. `signal_pick(x, y)`
selects the nearest head under the cursor in screen pixels and returns its flat
index, and `signal_selected()` reports that selection. `signal_preview_screen(x, y)`
and `crosswalk_preview_screen(x, y)` return the snap target under the cursor
without placing anything, so the tools can preview where a click would land.
Head positions sit 3.4 m along the arm and 2.6 m across it, so a light is set back
from the corner.

### Per-light timing, flashing yellow and coordination (slice 12)

Group 29 carries the granular properties of each individual light. Fields 15 red
(the all-red "off" time in simulation seconds), 16 manual flash mode (-1 forced
off, 0 follows the daily window, 1 forced on), 17 whether the light is blinking
yellow right now, 18 whether the daily window is in use, 19/20 the window's start
and end hour of the simulation day, 21 coordination group (-1 ungrouped), 22 the
delay in simulation seconds behind that group's leader, 23 preemption (0 normal,
1 cross traffic held for an emergency, 2 open on flashing yellow), 24/25 the
minimum and maximum off time, 26/27 the minimum and maximum amber, 28/29 the
minimum and maximum coordination delay, 30 whether the amber lamp is lit in this
half of the blink, 31-34 each arm's state, and 35-38 each arm's street. State 3
means flashing yellow, so a branch that is neither committed nor waiting reports
3 rather than a colour.

While a light blinks yellow every approach may go, slowly and yielding: drivers
are held until the junction box is clear of whoever went in ahead, and approach
speeds are halved. Pedestrians keep priority at a yielding junction. A preemption
of kind 1 holds the cross traffic outright, which is what an emergency service
needs and which no simulated driver may cross.

Group 30 is the coordination map. By link index: 0 leader junction, 1 follower
junction, 2 leader node, 3 follower node, 4 delay seconds, 5 active, 6/7 the two
group ids, 8 whether the follower is blinking. Links make a follower run its
leader's cycle, held back by the delay.

Commands: `signal_set_red(node, seconds)` clamps to fields 24/25 and returns the
applied value or -1. `signal_set_flash_schedule(node, start_hour, end_hour,
enabled)` sets the daily window (a start later than the end runs overnight).
`signal_flash_manual(node, mode)` and `signal_flash_bulk(scope, key, mode)` set
the manual switch for one light, a whole street (scope 1, key street) or every
light (scope 0); they return how many lights changed. `signal_apply_bulk(scope,
key, field, value)` writes one property across the same three scopes, where field
0 green, 1 amber, 2 off time, 3/4 window hours, 5 window enabled and 6 manual
flash mode, and returns the number of lights that took the value.

`signal_alert(node, kind, seconds)` is the emergency hook a police or firefighter
dispatcher will use; kind 1 holds the cross traffic, 2 opens the junction on
flashing yellow and 3 releases it. Alerts are queued and applied at the next
update, and a timed hold expires on its own. `signal_alerts_pending()`,
`signal_alerts_handled()` and `signal_alerts_pushed()` report the queue. Police
and firefighters are not simulated yet, so today the player's own controls raise
these alerts. `signal_link(from, to, delay)` and `signal_unlink(from, to)` edit
the map and `signal_link_count()`/`signal_links_total()` report it.

## Planning additions

Group 0 field 28 is graph revision. Node and road counts are now live counts. Group 1 fields 13/14 are street ID and property number. Group 3 fields 28/29 are destination/origin building IDs (multiple buildings may share a node). Group 5 fields 15/16 are street ID and pedestrian count. Group 11 fields 5/6 are the stop's street ID and number.

Group 15 fields 0–5: road preview error, price, length, parcel count, selected parcel, enclosed-block count. Group 16 by parcel: x, z, zone, existing building (-1 vacant), block (-1 open frontage), street ID, address number.

Commands: `road_begin(curved)`, `road_point(index,x,z)`, `road_screen_point(index,x,y)`, `road_build()`, `road_cancel()`, `zoning_show(enabled)`, `zoning_pick(screenX,screenY)`, `zoning_apply(parcel,zone,wholeBlock)`. Overlay 3 is pedestrian density.

## Development proposals and permits (slice 18)

Private development responds to the zoning the player has applied and to demand
the live simulation has actually generated. A proposal always targets an
authored lot whose kind is vacant (7) and whose parcel is zoned residential,
commercial, industrial or mixed; the lot is redeveloped in place, so it keeps
its identity, position, frontage, node, street and address number.

Group 31 reads one application by newest-first index. Fields: 0 application
number (one-based), 1 parcel, 2 building (the authored lot), 3 district, 4 zone,
5 proposed kind (see `web/data.js`), 6 height, 7 assessed value, 8 capacity,
9 levy in pounds, 10 offered time, 11 decision deadline, 12 decided time,
13 expected completion time, 14 decision (0 offered, 1 approved, 2 refused,
3 lapsed, 4 built), 15 reason (0 none, 1 no eligible site, 2 not zoned,
3 no measured demand, 4 site already built on, 5 refused by the authority,
6 lapsed undecided), 16 the measured pressure that justified the application,
17 applications ever lodged, 18 currently pending, 19 retained records.
Out-of-range indexes return -1.

Group 0 fields 70-78 are the running totals: 70 pending applications, 71 permits
under construction, 72 completed buildings, 73 applications refused, 74 lapsed,
75 ever lodged, 76 development levies received, 77 zoned vacant sites that are
eligible right now, 78 applications lodged today. Group 16 field 7 is the
pending application on that parcel, newest first, or -1.

Commands: `development_accept(id)` grants the permit, records the levy in the
municipal ledger as kind 12 under the application's own number and starts a
bounded 2-6 day build; it returns false and retires the application with reason
4 when the site is no longer vacant. `development_refuse(id)` retires the
application with reason 5. Both return false for an application that has already
been decided. The levy is the only money this batch moves; construction is the
applicant's own cost.

## Agreement review additions

`service_quote(operator,fleet,days,price,field)` is read-only: fields 0 minimum acceptable penny price, 1 reason (0 eligible, 1 capacity, 2 price, 3 invalid terms), 2 available fleet/drivers. Invalid terms return -1 for other fields. Offer and acceptance share this validation. Price must round to a positive penny and be at most £1 billion.

Group 13 retains fields 0–9 and adds: 10 unique agreement number (one-based), 11 expected bus-seconds to date, 12 earned payment including unsettled pennies, 13 released reserve on closure, 14 offered time, 15 closed time, 16 line ID, 17 route version at offer, 18 offered stop count, 19 retained closed-record count, 20 total closed-record count. Fields 32–47 return original offered stop IDs. Status 5 means revised/replaced offer; 6 means line withdrawn. Fields 19/20 are global counts, available through any valid line ID.

Group 17 reads closed agreements newest first using the same fields. Out-of-range records return -1; the ring retains 64. History values other than global counts remain immutable. Ledger category 8's party is operator ID and order is the one-based agreement number (not line ID or repair-order ID).

Group 10 field 9 counts this line's waiting passengers; 10–14 count requested fleet slots currently unavailable, moving, dwelling, held at signals/queues, and clearing an old route. Counts partition the requested fleet, excluding surplus retiring slots. `transport_remove` now also closes an offered/active agreement immediately at current simulation time, including while paused.

## Operator capital and shifts (supersedes bundled capacity above)

Existing numeric fields remain in place. Group 10 field 5 now reads the responsible company's spendable cash, never a line balance. New fields 32 company, 33 window (0 all day, 1 06:00–22:00), 34 empty-slot dispatch blocker (0 ready, 1 off hours, 2 no cash, 3 no vehicle, 4 no driver). This diagnostic can say no vehicle when the entire requested fleet is already running; use fields 10–14 for actual live states.

Group 12 adds 11 original bus operator, 12 retiring, 13 current driver cohort (1 day, 0 night). Cars have no operator semantics.

Group 14 retains 0 owned vehicles, 1 committed daytime buses (now includes private lines), 2 cumulative agreement receipts. Adds 3 opening capital, 4 cash, 5 cumulative fares, 6 subsidies, 7 vehicle/clearance expenses, 8 labour expenses, 9 on-duty drivers, 10 day cohort size, 11 night cohort size, 12 committed night buses, 13 occupied physical buses/drivers including clearing, 14 currently available on-duty drivers. Expense accrual retains sub-penny precision.

Groups 13/17 add 21 agreed window and 22 total contracted bus-second target, fixed at acceptance. Closure snapshots preserve both.

`service_window_quote(line,company,fleet,days,price,window,field)` and `service_window_offer(line,company,fleet,days,price,window)` add explicit line replacement and hours. Quote fields 0 minimum price, 1 refusal, 2 available owned fleet excluding replaced line, 3 minimum company cash buffer including other commitments. Refusals: 0 eligible, 1 vehicles, 2 price, 3 invalid terms, 4 driver coverage, 5 cash. Days must be whole, 1–7. Legacy offer uses all-day; legacy quote uses all-day without excluding a line. Policy fares/subsidies now round to pennies.

## Stop-arrival observations

Groups 18 (current) and 19 (most recent retired route/window) use ID = line ID × 16 + ordered stop index. Missing line/stop/record/field returns -1. Existing field numbers are unchanged.

| Field | Value |
| --- | --- |
| 0 | Route version |
| 1 | Coverage window: 0 all day, 1 daytime |
| 2 | Stable stop node ID |
| 3 | Visit count, 0 before observation |
| 4 | Latest absolute simulation time, -1 before observation |
| 5 | Eligible interval count |
| 6 | Last eligible interval in simulation seconds, -1 without samples |
| 7 | Mean eligible interval, -1 without samples |
| 8 / 9 | Minimum / maximum eligible interval, -1 without samples |
| 10 | Current physically waiting residents for this line/version/node; -1 for retired records |
| 11 | Wait starts recorded during this route version |
| 12 | Completed waits (actual boardings after waiting) |
| 13 | Mean completed wait in simulation seconds, -1 without completed waits |
| 14 / 15 | Minimum / maximum completed wait, -1 without completed waits |
| 16 | Capacity denials: full in-service bus encounters while an eligible resident waited |
| 17 | Abandoned waits: scheduled timeout |
| 18 | Abandoned waits: timeout during closed hours |
| 19 | Abandoned waits: fare no longer affordable |
| 20 | Abandoned waits: route changed or service removed |
| 21 | Abandoned waits that had already seen a full bus |
| 22 | Total completed wait seconds |

Group 22 uses the district ID as `id`:

| Field | Value |
| --- | --- |
| 0 | Observed wait starts by residents whose home is in this district |
| 1 | Completed waits |
| 2 | Mean completed wait in simulation seconds, -1 without completed waits |
| 3 | Capacity denials |
| 4 | Abandoned waits |
| 5 | Abandoned waits that had already seen a full bus |
| 6 | Current waiting residents in this district |
| 7 | Completed share of finished waits (completed / completed+abandoned), -1 with no finished waits |

focus(11,node) locates a valid street node. Records are bounded to current plus most recent retired per line, each at most 16 stops. Route edits/withdrawal update immediately; coverage changes synchronize before arrivals on the next transport step. Daytime pairs across closed hours are omitted. Zero intervals mean genuine simultaneous visits, not missing data. Detailed event and retention semantics are in stop-regularity-slice.md.

## Agreement regularity targets

New service_target_offer(line,company,fleet,days,price,window,max_interval) validates the whole offer before any mutation. max_interval must be finite and either 0 (disabled) or an integer 30–600 simulation seconds. service_target_valid(max_interval) exposes that Zig validation for the form. Existing offer commands remain compatible and set target 0. Quotes, refusal reasons, delivery and money fields are unchanged; financial eligibility does not certify a target is achievable.

Groups 13/17 add:

| Field | Value |
| --- | --- |
| 23 | Maximum interarrival target, 0 disabled |
| 24 | Total eligible completed interval pairs during this agreement |
| 25 | Pairs exceeding the agreed interval |
| 26 | Offered stops with at least one eligible pair |
| 27 | Regularity review permanently suspended by route/window/operator mismatch |
| 28 | Assessment timestamp, clipped at expiry; frozen on closure |

Groups 20 (current agreement by line) / 21 (closed agreement newest-first record) use ID = record × 16 + offered stop index. Missing records/stops/fields return -1. Closed results belong to the same newest-64 ring as group 17, so use the agreement number to retain UI selection across insertions.

| Field | Value |
| --- | --- |
| 0 | Original offered stop-node ID |
| 1 | Qualifying post-acceptance visit count |
| 2 / 3 | Eligible interval pairs / exceeded pairs |
| 4 | Latest qualifying arrival timestamp, -1 without visits |
| 5 | Worst eligible interval, -1 without pairs |
| 6 | Gap state: 0 disabled, 1 not accepted, 2 suspended, 3 off-hours, 4 first-arrival grace, 5 first arrival overdue, 6 within current gap allowance, 7 arrival gap overdue |
| 7 | Current gap age in simulation seconds, -1 for states 0–3 |
| 8 | Last eligible interval, -1 without pairs |

Gap age uses acceptance or the current coverage-window opening until its first real arrival; then uses the latest real arrival. First-arrival grace is one target-length. An interval/age must exceed the target by more than 0.00001 seconds to ignore floating-point noise at equality. Groups 18/19 remain route/session observations independent of agreement review. Internally transport publishes at most 24 arrival events per fixed step, consumed once by agreement measurement; there is no persistent event log.


## Manual town persistence

`save_capacity() -> usize` returns 16 MiB. `save_pointer() -> usize` addresses the shared UTF-8 input/output buffer. `save_write() -> usize` writes versioned JSON and returns its byte length (0 on failure); copy those bytes before another persistence call. The buffer is scratch space, not a live-state view.

To import, size-check the file, copy its bytes to that buffer, then call `save_load(length) -> u32`. Results: 0 success, 1 empty/oversized input, 2 malformed JSON/schema or parse-budget exhaustion, 3 unsupported format/version/rules, 4 inconsistent state. Parsing uses a separate bounded 64 MiB arena. All validation precedes live mutation. Unknown/duplicate fields and invalid enum tags are rejected. A failed import leaves the town unchanged.

Successful load restores simulation speed and fixed-step remainder. `saved_resume_speed() -> f32` supplies the previous nonzero speed for Space after paused import. The browser clears UI drafts and refreshes report metadata only after success. `format = "Common Ground town"`, `version = 2`, `rules = "bellwether-2026-09-v2"`. Version 1 and other incompatible files are rejected with result 3; there is no migration layer. See `save-load-slice.md` and the explicit `State` contract in `src/simulation/persistence.zig`.

## Slice 4 — fleet units and recruited staff

Group 14 keeps every existing field number. Field 0 is now the number of owned
units in that operator's pool (was the fixed fleet capacity). New fields:

| Field | Value |
| --- | --- |
| 15 | Depot/yard capacity, the maximum owned units |
| 16 | Units currently unavailable for maintenance |
| 17 | Serviceable units (owned − under maintenance) |
| 18 | Free units: serviceable and attached to no bus |
| 19 | Units attached to a running or clearing bus |
| 20 | Mean unit condition, 0–100 |
| 21 / 22 | Lifetime bus purchases / sale receipts |
| 23 / 24 | Lifetime recruitment / severance payments |
| 25 | Lifetime maintenance payments |
| 26 | Purchase refusal (see codes below) |
| 27 / 28 | Day / night recruitment refusal |
| 29 / 30 | Day / night dismissal refusal |
| 31 | Bus purchase price |
| 32 | Maintenance charge per repair |
| 33 / 34 | Day / night recruitment fee |
| 35 | Severance payment |
| 36 | Free depot slots |
| 37 / 38 | Drivers able to cover daytime / the night window |

Refusal codes for fields 26–30: 0 eligible, 1 insufficient cash, 2 no depot
space, 3 a day-qualified driver is required first, 4 night coverage gap,
5 the unit is under maintenance, 6 the unit is still committed to a live
service, 7 invalid selection.

Group 23 reads one owned unit. ID = operator × 8 + unit index; an absent unit
returns -1 for every field.

| Field | Value |
| --- | --- |
| 0 | Present in the pool |
| 1 | Condition, 0–100 |
| 2 | Under maintenance |
| 3 | Attached to a running or clearing bus |
| 4 | Attached vehicle slot, -1 when free |
| 5 | Repair funded |
| 6 | Repair completion time, 0 before the window starts |
| 7 | Current resale value at this condition |
| 8 | Sale refusal (same codes as above) |
| 9 | Repair charge at this condition |

Group 12 field 14 is the owning unit of a bus, -1 for cars and idle slots.
Group 10 field 34 adds dispatch states 5 (depot capacity), 6 (every remaining
unit is under maintenance) and 7 (every serviceable unit is committed to a
running or clearing bus).

Service-quote refusals (group 13 field 8, `service_window_quote` field 1) now
run to 8: 0 eligible, 1 insufficient owned buses, 2 price below cost and
margin, 3 invalid terms, 4 insufficient drivers, 5 working capital below the
operating buffer, 6 no night-qualified driver for the all-day window, 7 owned
buses are under maintenance, 8 serviceable buses are committed elsewhere.

Commands: `fleet_buy(company)`, `fleet_sell(company, unit)`,
`fleet_maintain(company, unit)`, `staff_recruit(company, night)`,
`staff_dismiss(company, night)`. All validate in Zig and return a boolean;
a refused action never moves money. `fleet_maintain` marks the occupying bus
for safe retirement before the unit leaves service, so riders still alight at
a stop.

Persistence is now `version: 3`, `rules: "bellwether-2026-09-v3"`. Every unit,
roster count and lifetime flow is serialized and validated; version 2 and
older files are rejected with result 3 and no migration layer.


## Transport contract enforcement (slice 5)

Groups 13 and 17 retain fields 0-28 and add:

| Field | Value |
| --- | --- |
| 29 | Enforcement state: 0 none, 1 curing, 2 breached after cure, 3 credit capped, 4 closed while breached, 5 suspended by route/service change |
| 30 | Credit accrued to date |
| 31 | Credit paid to the municipality |
| 48 | Credit waived because the operator was at or below the GBP 2.18 floor |
| 49 | Credit cap (25% of agreement price) |
| 50 | Breach start time, 0 while none |
| 51 | Cure deadline, 0 while none |
| 52 | Breach/accrual observation counter |
| 53 | 1 while an active agreement is below the breach floor and enforcement is not suspended |
| 54 | Outstanding credit (accrued - paid - waived, rounded to pennies) |

Group 14 adds field 39: lifetime operator service credits paid to the municipality.
The account identity is now
cash = opening + fares + subsidies + receipts + sales - purchases - recruitment -
severance - maintenance - vehicle - labour - credits.

Ledger kind 10 is a service credit: party is the operator (0-2) and order is the
one-based agreement number. The reports label it "Service credit".

Save schema is version 4, rules "bellwether-2026-10-v4"; version 3 and older are
rejected with result 3.


## Civic calendar and routines (slice 6)

Group 0 adds: 29 weekday (0 Mon .. 6 Sun), 30 weekend flag, 31 routine phase
(0 sleep, 1 morning commute, 2 work, 3 evening, 4 leisure, 5 night), 32 week
index, 33 next weekly-period boundary (simulation seconds), 34 retained weekly
period count. Group 3 adds: 32 resident shift (0 day 06-14, 1 evening 14-22,
2 night 22-06), 33 resident routine phase.

One day remains 480 simulation seconds, one hour 20 seconds and one week 3360
seconds. Daytime service remains 06:00-22:00 and all-day remains 00:00-24:00.

Save schema is version 5, rules "bellwether-2026-11-v5"; version 4 and older are
rejected with result 3.


## Households and budgets (slice 7)

Group 0 adds: 35 households in arrears, 36 total household arrears, 37
household count. Group 3 adds: 34 home building / household ID. Group 25
is household records by home building index: 0 present, 1 members, 2 shared
balance, 3 daily employed income, 4 daily essential expense, 5 arrears,
6 lifetime essentials paid, 7 unpaid (equal to arrears).

One household exists per home building. Members share the balance and daily
budget; fares, car running costs and car purchase spend from that balance.
Essential expenses are billed daily; any shortfall becomes explicit arrears,
never hidden debt. Walking remains the safe fallback. Save schema is version 6,
rules "bellwether-2027-01-v6"; version 5 and older are rejected with result 3.


## Households and budgets (slice 7)

Group 0 adds: 35 households in arrears, 36 total household arrears, 37
household count. Group 3 adds: 34 home-building household ID. Group 25 reads
household records by home building index: 0 present, 1 members, 2 shared
balance, 3 daily employed income, 4 daily essential expense, 5 arrears, 6
lifetime essentials paid, 7 unpaid (equal to arrears).

One bounded household exists per home building. Members share a balance and a
daily budget; fares, car running costs and car purchase spend from that shared
balance. Essential expenses are billed daily and any shortfall becomes explicit
arrears, never hidden debt. Walking remains the safe fallback. Save schema is
version 6, rules "bellwether-2027-01-v6"; version 5 and older are rejected with
result 3.

## Employment and hiring (slice 8)

Group 0 adds: 38 jobseekers, 39 open posts (total vacancies), 40 hires on the
last day rollover, 41 dismissals on the last rollover, 42 wages paid on the last
rollover, 43 wage arrears left unpaid on the last rollover. Group 3 adds: 35
resident skill (0 general, 1 clerical, 2 professional). Group 27 reads the
employment view per employer (id = company index):

| Field | Value |
| --- | --- |
| 0 | Open posts (capacity − employees) |
| 1 | Posted daily wage per employee |
| 2 | Minimum skill (0 general, 1 clerical, 2 professional) |
| 3 | Wage arrears not yet paid |
| 4 | Staffing pressure (unpaid share of the last wage bill, 0–1) |
| 5 | Employees |
| 6 | Capacity |
| 7 | Operating cash |
| 8 | 1 for street contractors, 0 otherwise |

One bounded rollover per day: qualified jobseekers fill up to 64 posts
preferring the closest home-to-work trip, an employer carrying wage arrears
dismisses up to two lowest-skill ordinary employees (never crew members or
workers bound to an active order), then each employer pays the wages its cash
covers. Only paid wages reach household balances; unpaid amounts stay as that
employer's explicit wage arrears, never municipal or hidden debt. Household
group 25 field 8 adds the wages actually paid last rollover; field 3 remains the
posted daily wage of employed members. Save schema is version 7, rules
"bellwether-2027-02-v7"; version 6 and older are rejected with result 3.


## Street types, parking and learned travel (slice 10)

Group 0 adds: 55 parking facilities, 56 total spaces, 57 occupied spaces,
58 parking attempts, 59 successful first choices, 60 fallbacks after a full
first choice, 61 travellers who found no space, 62 lifetime parking revenue,
63/64 bicycle spaces and their use, 65/66 car and kerbside spaces and their use,
67 kerbside spaces currently occupied, 68/69 learned arrival batches applied and
dropped.

Group 3 adds: 36 car preference, 37 current parking facility (-1 at home),
38 parked vehicle (0 none, 1 bicycle, 2 car), 39 planned mode, 40 walking to the
vehicle, 41 crossing waits, 42 admitted crossings, 43 seconds waited at the
current crossing, 44-47 parking attempts/taken/searched/refused, 48 departure
bucket, 49 learned trip seconds for the current mode and bucket (-1 unknown),
50 first remembered parking facility (-1 none).

Group 5 adds: 17 street class (0 lane, 1 street, 2 avenue), 18 smoothed
movement, 19 kerbside price band, 20 kerbside price per stay.

Group 28 reads one parking facility by index: 0 kind (0 bicycle, 1 car),
1 building (-1 for kerbside), 2 road (-1 for a lot), 3 node, 4 slots,
5 occupied, 6 free, 7 price, 8-11 aggregate observed availability for the four
daily buckets, each updated from the bucket a traveller arrived in. Field 49
above is the departure-bucket trip average for the resident's current mode; the
parking estimate is likewise per arrival bucket, so the two halves of the model
key on different times of day.

Commands: `road_class(value)` sets the class (0-2) used by the next
`road_begin`; `parking_rebuild()` re-seeds facilities after a road is built and
reposts kerbside prices.

Save schema is version 13, rules `bellwether-2027-11-v13`; version 12 and older are
rejected with result 3. The bounded development queue, its counters and its
district rotation are serialized and validated field by field. Parking facilities, occupancy, prices, aggregate
availability, movement, counters and every learned resident field are
serialized and validated.
