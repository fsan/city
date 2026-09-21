# Browser / Zig boundary

`src/main.zig` exports commands and a read-only scalar accessor `read(group, id, field)`. It returns f64 values, using -1 for missing records. JavaScript presentation helpers live in `web/data.js` and `web/reports.js`; Zig retains all rule validation. Do not infer Zig struct packing in JavaScript.

Groups: 0 city metrics; 1 properties; 2 districts; 3 residents; 4 companies; 5 streets; 6 orders; 7 ledger (newest first); 8 history (oldest retained first). The corresponding switches in `main.zig` are the field contract. Keep field numbers stable when extending it. District names use a UTF-8 pointer plus length.

Commands: init, update, set_speed, set_funding, apply_taxes, offer, revise, cancel_order; camera pan/rotate/zoom_at/reset_camera/focus/pick; select_resident and set_overlay. `quote` exposes each company's current estimated minimum and refusal reason for a draft. Money and order commands return success or an explicit validation result; errors never partly mutate a transaction.

`draw` fills a reusable vertex buffer and returns vertex count. `vertex_pointer` plus memory exposes interleaved clip XYZ/RGB floats. UI refreshes twice per real-time second and only builds visible reports. Table cells are reused so refreshing a report does not steal keyboard focus. Snapshot history is recorded every 30 simulation seconds, up to 96 records; no invented pre-session history.

## Transport extension

Groups 9–12 are transport policy/counters, bus lines, street nodes and vehicles. Existing group numbers remain stable. Resident fields 13–26 add mode (0 walk, 1 cycle, 2 car, 3 bus), wallet, income, car/bike ownership, bus wait, bus vehicle ID, parked car node, four departure scores (-1 unavailable), chosen bus line and parked bike node. Street fields 10–13 are vehicle count, queue count, smoothed pressure and allocation (0 mixed, 1 bus, 2 cycle).

Group 9 fields 0–4: fare cap, boarding subsidy, total paid subsidy, actual fare, node count; 5–8: active trips per mode; 9: people waiting at stops. Group 10 fields 0–8: active, stop count, boardings, cumulative revenue, costs, operator cash, fleet count, aboard, route version. Fields 16–31 are ordered stop node IDs. Group 11 fields 0–4: world x/z/elevation, screen x/y. Group 12 fields 0–10: active, x/z, speed, passengers, node/next, segment progress, line ID (-1 car), dwell, current lane.

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


## Planning additions

Group 0 field 28 is graph revision. Node and road counts are now live counts. Group 1 fields 13/14 are street ID and property number. Group 3 fields 28/29 are destination/origin building IDs (multiple buildings may share a node). Group 5 fields 15/16 are street ID and pedestrian count. Group 11 fields 5/6 are the stop's street ID and number.

Group 15 fields 0–5: road preview error, price, length, parcel count, selected parcel, enclosed-block count. Group 16 by parcel: x, z, zone, existing building (-1 vacant), block (-1 open frontage), street ID, address number.

Commands: `road_begin(curved)`, `road_point(index,x,z)`, `road_screen_point(index,x,y)`, `road_build()`, `road_cancel()`, `zoning_show(enabled)`, `zoning_pick(screenX,screenY)`, `zoning_apply(parcel,zone,wholeBlock)`. Overlay 3 is pedestrian density.

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

focus(11,node) locates a valid street node. Records are bounded to current plus most recent retired per line, each at most 16 stops. Route edits/withdrawal update immediately; coverage changes synchronize before arrivals on the next transport step. Daytime pairs across closed hours are omitted. Zero intervals mean genuine simultaneous visits, not missing data. Detailed event and retention semantics are in stop-regularity-slice.md.
