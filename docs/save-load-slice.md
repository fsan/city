# Manual local save/load — complete

Management → Save / load town opens the file controls (also available under Controls). Save downloads a JSON town file; Load reads a selected file and replaces the live town only after successful validation. Export first to retain the current town. A running save resumes at its saved speed; a paused save remains paused, and Space restores its previous nonzero speed.

The gameplay loop runs in Zig WebAssembly inside the browser. Docker builds the module and nginx serves static assets; neither owns a live simulation or stores towns. There is no backend, account, cloud sync, autosave, automatic import or offline catch-up. Refresh/Restart starts a fresh town until a file is explicitly imported. Download location and retention are controlled by the browser/user.

## Preserved state

- Simulation clock, speed, remembered resume speed, fixed-step remainder and future sample/routing/operating/weekly budget deadlines; camera.
- Graph nodes/roads, IDs/revisions, road condition and lane allocation, parcels/zoning/buildings, routing and distance tables.
- Residents, companies/employment, trips and walking progress, cars/buses, passenger links, clearing/driver cohorts, operator accounts and line attribution.
- Tax/funding policies, treasury, protected reserves, arrears, latest 1,024 ledger entries and counters; work orders, company crews and review schedule.
- Bus lines, current/previous route observations, passenger wait starts/completed waits/capacity denials/abandonment causes, district access counters, current agreements, review targets/results, breach/cure state, accrued/paid/waived service credit, resident shifts/routines, weekly budget-period summaries, the next week boundary, newest 64 closed agreements and next agreement ID.
- Trust and latest 96 history samples with their counters.

Only initialized live prefixes and physical ring contents are serialized. Existing retention limits remain. Restoring repeatedly does not append records or replay payments. Routing tables and deadlines are retained because immediately recomputing a scheduled cache could alter the next journey. Graph lookup and parcel-block caches are rebuilt; transient per-step arrival events, pending subsidy coordination, renderer buffers and selection are cleared. Vehicle queues rebuild at the next simulation step.

Unapplied road/route/offer/work-order drafts, selected records, overlays and window positions are not saved. Successful import cancels drafts, refreshes metadata and repopulates policy fields; rejected imports leave the live town and drafts intact. Window arrangement remains a browser UI concern.

## Contract and rejection

`src/simulation/persistence.zig` defines an explicit typed JSON State; this is not a WASM memory dump and JavaScript does not infer native struct layouts. Metadata is `format: "Common Ground town"`, now `version: 5`, `rules: "bellwether-2026-11-v5"` after slice 6. Schema or incompatible rules changes require an identifier bump. No migration layer is included; version 4 and older files are rejected with result 3.

Maximum file size is 16 MiB; parsing has a separate fixed 64 MiB arena. Save/load is synchronous after the browser has read the file, so large operations can briefly pause rendering. Typical tested towns are about 9.6–10.0 MB; routing matrices dominate. A 640-node capacity fixture exported at 14,694,433 bytes. Export reports failure if it cannot fit; there is no silent truncation.

Before committing, validate metadata, schema, finite/bounded numbers, lengths/enums, graph references and terminating adjacent next-hop paths, resident/company/vehicle links, rider counts, operator account identities, in-progress wait timestamps, passenger counter accounting, district outcome accounting, work/crew/reserve consistency, agreement IDs/history/targets and ledger continuity. Reject unknown/duplicate fields, malformed/truncated input, unsupported versions, excessive allocation and inconsistent state. Parsing and validation touch staging/scratch storage only. A successful commit copies validated state into live storage without allocating; failure does not partly replace it. This is consistency checking, not tamper-proof authentication of user-edited towns.

ABI: `save_capacity`, `save_pointer`, `save_write`, `save_load`, `saved_resume_speed`; see `abi.md` for the buffer protocol and error codes.

## Verification

Docker Zig 0.14.1 ReleaseSafe build and static-server startup passed; JavaScript syntax and whitespace checks passed. Focused scripts remain outside the repository, with no permanent test suite:

- Initial and active snapshots imported into fresh WASM instances and re-exported byte-identically.
- `/tmp/city-save-check.mjs`: construction/zoning, an active physical repair and targeted service agreement, live journeys, nine byte-identical continuation checkpoints over 720 simulation seconds through daytime closure/reopening, repair completion and settlement; rider conservation, nonnegative operator accounts, accounting identities and protected reserves. Route-clearing/handover, paused fixed-step remainder, remembered 4× resume and post-load continuation also matched.
- Rejected malformed, incompatible and inconsistent fixtures without changing a byte of the exported live state: graph hops/references, riders, cash, ledger, reserves, crew counts, agreement IDs/history, capacity, clock remainder, resident income/trust, missing/unknown fields, truncation, duplicate keys, empty and oversize lengths.
- `/tmp/city-save-extra.mjs`: pending refused offer, 64-record closed-history rollover, repeated imports and deterministic continuation, zero-fare service through night and morning reopening.
- Passenger-outcome save/load checks: an in-progress wait survived export/import, resumed at the same simulation clock, and later settled without duplicate counting. Wait-start accounting and district counters were preserved. Version 1 files are rejected as incompatible.
- `/tmp/city-save-limits.mjs`: 640-node graph validated, exported within the cap and imported again. Rendering after import produced finite vertices.
- Existing capital and regularity-target focused checks passed with persistence present, including target-on/off financial parity.
- Isolated browser: Save export status, real file-chooser import of a paused town, 4× Space resume, malformed-file rejection, clear control layout and no captured console warnings/errors. The user's town was not reset.

Manual file management, bounded history and the current authored population/graph limits remain. Full backend persistence, browser autosave slots, compression, replay and version migrations are deferred. Agreement payment and simulation rules are unchanged. Slice 3 passenger service outcomes are complete; see `passenger-outcomes-slice.md`, the roadmap and root kickoff.
