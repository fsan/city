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
