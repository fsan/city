# Browser / Zig boundary

`src/main.zig` exports commands and a read-only scalar accessor `read(group, id, field)`. It returns f64 values, using -1 for missing records. JavaScript presentation helpers live in `web/data.js` and `web/reports.js`; Zig retains all rule validation. Do not infer Zig struct packing in JavaScript.

Groups: 0 city metrics; 1 properties; 2 districts; 3 residents; 4 companies; 5 streets; 6 orders; 7 ledger (newest first); 8 history (oldest retained first). The corresponding switches in `main.zig` are the field contract. Keep field numbers stable when extending it. District names use a UTF-8 pointer plus length.

Commands: init, update, set_speed, set_funding, apply_taxes, offer, revise, cancel_order; camera pan/rotate/zoom_at/reset_camera/focus/pick; select_resident and set_overlay. `quote` exposes each company's current estimated minimum and refusal reason for a draft. Money and order commands return success or an explicit validation result; errors never partly mutate a transaction.

`draw` fills a reusable vertex buffer and returns vertex count. `vertex_pointer` plus memory exposes interleaved clip XYZ/RGB floats. UI refreshes twice per real-time second and only builds visible reports. Table cells are reused so refreshing a report does not steal keyboard focus. Snapshot history is recorded every 30 simulation seconds, up to 96 records; no invented pre-session history.
