# Next agent kickoff — save/load complete; passenger outcomes next

Continue Common Ground in /Users/fox/Documents/ChatGPT/city. Measured arrivals, optional agreement regularity targets and **manual local save/load (slice 2) are complete**. Read docs/save-load-slice.md, docs/regularity-target-slice.md and docs/development-roadmap.md. The roadmap lists 39 proposed batches; slice 3 (passenger service outcomes) is next. The list is not authorization to implement all batches.

Inspect current code, git status and recent commits before editing. Save/load started at e8f1a31 with uncommitted regularity-target work already present. Both slices remain uncommitted; preserve them and any subsequent work. Do not reset, rewrite history or push without a request.

## Read first

Start with `docs/save-load-slice.md`, then `docs/regularity-target-slice.md` and `docs/stop-regularity-slice.md`.

Read `README.md`, `docs/operator-capital-slice.md`, `docs/service-agreements.md`, `docs/transport.md`, `docs/abi.md`, and `docs/city-planning.md`. The operator slice note contains exact accounting rules, limitations, reproducible refusal/remedy scenarios and verification results. The Development Agent Kickoff and Modern City Management Game Scope Specification provide product direction; their old planning-only phase does not replace a new implementation request.

Use Zig for rules and measurements, JavaScript for WebGL/input/reports. Compile with Docker Compose and Zig 0.14.1 (`make build`, `make run`). No host compiler, bundler, framework, permanent test suite or parallel agent work unless specifically requested. Before coding, write a short slice note and then carry authorized implementation through verification and documentation.

## Preserve this baseline

- Full-viewport isometric 520 × 440 town, 3,840 adult placeholders, 12 districts, 60 employers, 288 seeded parcels; dynamic road/node counts and separate frontage links.
- Player-built straight/curved streets, splitting/junctions, construction debits, parcel/block zoning and pedestrian overlay.
- Protected municipal commitments and penny ledger; company crews must physically travel and perform street repairs before payment.
- Walking, cycles, cars and real bus passengers; directional queues/signals/lane allocation, route editing and safe bus retirement. Eight line slots, 1–3 buses, 24 seats, 2–16 stops.
- Quotes, offer/revision/cancellation/expiry/paused withdrawal, earned movement/dwell payments and immutable newest-64 closed agreement history. Unique agreement IDs link ledger category 8.
- Authoritative operator accounts in `operators.zig`: opening £600/£300/£5, independent fares/subsidies/agreement receipts, £0.06 vehicle + £0.12 driver labour per bus-second, £2 prepaid dispatch clearance fee. Line totals are attribution only.
- Owned buses 4/3/2, abstract day/night driver cohorts 4/2, 3/1, 2/0. Daytime 06:00–22:00 (seconds 120–440); all-day includes midnight. One day is 480 seconds. Acceptance accounts for private lines as well as contracts, with cash buffer, vehicle, coverage and price refusals.
- Each vehicle retains its operator while clearing. No money transfers on handover and no cash resets on reuse. Clearing is paid by the already-expensed flat fee, occupies physical resources and earns no delivery. Low cash retires safely without negative balances. All-day driver relief occurs at a junction.
- Off-hours add no delivery target. Contracts retain window and target. Private service continues with the last operator/fleet/window after closure. Refresh/Restart clears the live session; manual import restores an exported town.

## Completed stop-regularity slice

- Zig records a visit exactly at physical approach completion into target-stop dwell, only for current, scheduled, non-retiring service. Deployment, clearance and relief-only stops are excluded; a full bus still counts.
- Each line keeps current and most recent retired route/window records, with stable route version and stop nodes. Up to 16 stop records hold visits, latest timestamp, eligible interval count and last/mean/min/max. No observations and no intervals have explicit missing values.
- Applying a route archives the prior record immediately (even paused / same draft). Withdrawal archives and empties current; reuse starts fresh. Window changes synchronize before the next transport step's arrivals. Company/fleet/lane changes alone retain the same route/window measurements.
- Daytime pairs spanning closed hours are omitted. The new day's first visit updates latest time without inventing an overnight interval; older eligible statistics remain. All-day intervals cross midnight normally.
- Transport Authority offers current/retired selection, coverage/off-hours labels, session clock, live waiting counts, stop locate, unobserved/insufficient states and completed eligible interval statistics.
- Payments, dispatch, boarding, account rules and resident routing were not changed. No permanent tests added.

## Completed agreement-target slice

- Offers accept target 0 (disabled) or a whole 30–600 simulation seconds. Zig validates before mutation; legacy offer commands disable the target.
- Financial/resource quote, acceptance, earned movement/dwell payment, reserves and settlement are unchanged. Review targets do not guarantee feasible headways and incur no deductions.
- Transport emits at most 24 actual arrival events per step. Agreement-specific evidence excludes arrivals at/before acceptance, after expiry, on other versions or by other operators. Simultaneous arrivals are retained individually.
- Each originally offered stop retains visits, latest arrival, eligible/exceeded pairs, last and worst intervals. Counts describe observed pairs, never a blanket pass.
- Gap diagnostics distinguish not accepted, first-arrival grace, first arrival overdue, within current gap allowance, arrival gap overdue, off-hours and suspended. Each open window starts with one target-length grace period; no historical overdue-episode log.
- Daytime cross-closure pairs are omitted; all-day midnight pairs remain eligible. Equality is not exceeded, with 0.00001 s tolerance for fixed-step drift.
- Route edits immediately and permanently suspend target review, including paused edits. Existing results and agreement clocks remain. Changed routes before acceptance also suspend; cancel/re-offer to define a new target. No automatic renegotiation.
- Targets/results/gap state at closure remain in the immutable newest-64 agreement ring, separate from current/previous route observations.
- UI includes target validation, current/closed per-stop tables, locate actions and explicit no-payment-effect/insufficient-evidence wording.

## Completed save/load slice

Management → Save / load town (also Controls) exports or imports explicit versioned JSON. The simulation is browser-owned Zig WASM; Docker compiles it and nginx serves static files. There is no backend authority. Preserve the local/manual scope unless the user requests a different persistence architecture.

Snapshots preserve clock, speed/resume/remainder/deadlines, camera, graph and stable IDs/routing tables, zoning, residents/journeys/riders, operators/vehicles/shifts, taxes/ledger/reserves, orders/crews, routes/observations/agreements/targets/history/next IDs. Parsing is bounded (16 MiB file, 64 MiB arena), staged and validated before commit. Invalid imports leave the live town unchanged. UI drafts/selections are excluded and cleared on success. See docs/save-load-slice.md for verification and limits.

## Next bounded slice — passenger service outcomes (slice 3)

When authorized to continue, implement measured passenger outcomes: actual completed waiting times, full-bus encounters and abandoned waits, with a bounded per-line/stop report and district access comparison where existing trip evidence supports it. Inspect residents.zig boarding, waiting and walking-fallback transitions before writing the short slice note. Define denominators and missing/insufficient evidence explicitly; do not infer good passenger service from vehicle arrivals alone.

Count from real simulation transitions, not UI polling. Specify when a wait starts/ends, distinguish still waiting from completed waits, and avoid counting the same full bus every fixed step. Distinguish capacity denial, route/service removal, off-hours and existing timeout/fallback causes where those causes are actually identifiable. Keep statistics tied to stable route versions; retired-route handling and reset semantics must be explicit. Preserve current boarding order, fares, dispatch, routing, agreement acceptance and payment rules.

Completion: Zig-owned bounded measurements and scalar ABI, clear Transport Authority reports with usable labels/units/denominators, current waiting versus completed evidence, no-observation states, and save/load support for every new counter and in-progress wait. Update save version/rules if the schema changes; reject incompatible files explicitly. Verify actual boarding/alighting, full buses without repeated duplicate denials, walking fallback, route edits/withdrawal, daytime closure/reopening, restored in-progress waits and accounting/passenger conservation. Use Docker builds, temporary focused simulation checks and a fresh browser tab. Update documentation and this kickoff.

No new timetable, FIFO boarding policy, transfers, fleet/staff purchases, contract penalties, demographic model, backend/cloud/autosave or permanent test suite. Do not expand into other roadmap slices without authorization.

## Code map and cautions

- `src/simulation/persistence.zig`: explicit typed JSON snapshot, bounded validation/commit; graph lookup restoration in city.zig. Keep any new persistent fields represented and validated.
- `main.zig`: save buffer/write/load exports and remembered resume speed. `web/main.js`: file export/import and successful-load reset coordination. Reports/transport/agreements reset cached metadata and unapplied drafts.

- agreements.zig: offerTarget/validInterval, measureRegularity, checkRoute, readStop and regularity fields in Agreement. No financial changes.
- transport.zig: per-step Arrival list resets each update; recordArrival also feeds existing route observations.
- main.zig: service_target_offer/service_target_valid; groups 13/17 fields 23–28; groups 20/21 ID = agreement line/history index × 16 + stop index.
- web/agreements.js and web/index.html: target input plus persistent current/history table rows.

- transport.zig: Observation / StopObservation, syncObservation and recordArrival own bounded stop measurements. Current/previous records are independent of agreement history.
- main.zig: groups 18/19 expose stop records (ID = line × 16 + stop index); focus(11,node) locates stops. web/transport.js and web/index.html own the compact stop report.

- `src/simulation/operators.zig`: independent accounts, day/night cohorts, service-window integral.
- `transport.zig`: physical fleet, original bus ownership, clearance, drivers, fares/costs, delivered seconds. Keep independent of finance/residents.
- `agreements.zig`: quote/acceptance, settlement, window-aware targets and history.
- `residents.zig`: actual boarding/alighting and safe walking fallback.
- `game.zig`: transport → residents → agreement settlement, then subsidy ledger coordination.
- `main.zig`: validated exports and scalar ABI. Preserve field numbers. Group 10 fields 32–34 expose company/window/dispatch blocker; groups 13/17 fields 21–22 window/target; group 14 account/driver breakdown; group 12 fields 11–13 bus owner/retirement/cohort.
- `web/agreements.js`: quotes, accounts, coverage, current/closed delivery. `web/transport.js`: routes/map gestures. `web/reports.js`: municipal ledger.
- `roads.zig`, `parcels.zig`, `web/planning.js`: planning baseline.

Never iterate the large resident array by value; it previously exhausted the WASM stack. Read through scalar ABI, not inferred struct layouts. Existing operator totals retain sub-penny operating accrual; municipal transactions and policy fares/subsidies round at penny boundaries.

## Verification and remaining limits

Save/load: Docker ReleaseSafe build, initial/active/paused round trips, nine byte-identical continuation checkpoints over 720 simulated seconds, active repair completion, construction/zoning, clearing/handover, payment/reserve/rider identity checks and invalid-file atomicity passed. A 640-node fixture exports within 16 MiB. Browser import restores pause and 4× resume; malformed import preserves the live town. See docs/save-load-slice.md for full current results. Temporary scripts live outside the repo and may disappear.

Previous regularity-target batch: Docker ReleaseSafe build/startup, JS syntax/diff and fresh-browser checks passed. /tmp/city-regularity-target-check.mjs reconstructed 28 post-acceptance visits and 20 eligible pairs, including four daytime omissions and four all-day midnight pairs, checked atomic invalid terms, paused suspension, grace/overdue, expiry, reset and history rollover. Paired target-on/off simulations were financially and physically identical over 720 simulation seconds. Docker-compiled /tmp/city-regularity-edge/edge.zig (outside repo, copied sources) checked simultaneous events, exact thresholds, wrong operator, same-time duplicate prevention, expiry clipping and sticky suspension. Capital and original stop checks still passed, including physical repair, protected reserves and 241 passenger samples. Browser checks covered invalid input, offer, expiry, archived exceeded intervals, locate, paused route suspension and cancellation; no warnings/errors captured. Temporary fixtures may disappear.


See docs/stop-regularity-slice.md for this slice's checks. Docker ReleaseSafe build/startup, JS syntax/diff checks and fresh browser inspection passed. Temporary /tmp/city-stop-check.mjs matched 29 physical arrivals over 24,000 steps, omitted seven closed-window pairs and observed three all-day midnight pairs. /tmp/city-stop-stats.mjs independently recomputed last/mean/min/max and reconciled stop waiting counts over 21,000 steps (six visits per stop on a two-stop route), including live bus-lane changes. Existing /tmp/city-capital-check.mjs and /tmp/city-capital-extra.mjs passed accounts, reserve/ledger, rider, cash exhaustion, shift/expiry and physical repair checks. Temporary scripts are not repository dependencies and may disappear.

See `docs/operator-capital-slice.md` for completed checks: cash exhaustion without rescue, shared company capacity, shift/midnight/expiry, quote/refusal/revision, handover, ledger/account reconciliation, passenger conservation, route editing/reuse/paused withdrawal, physical repair, road construction/zoning and finite rendering. No permanent tests were added.

Use a fresh temporary tab at `http://localhost:8080/`; never reset the user's town. Confirm compiler success before refreshing: failed builds retain the last good WASM. Keep accounting/reserve checks in temporary scripts outside the repository.

Driver staff are aggregate cohorts, empty deployment is abstracted, clearance/relief uses a fixed prepaid fee, and operating buffers are acceptance thresholds rather than escrow. No resident employment/payroll link, purchases/recruitment, transfers, full timetable, collisions, new service domains or city expansion. Manual local save/load is complete; autosave, backend storage and migrations remain deferred. Route observations retain one retired record per line. Agreement targets are review-only and newest-64 closed records retain their own evidence. No historical waiting-duration distribution, overall compliance score or financial regularity penalties.


## Numbered development sequence and follow-up slices

The original numbering is retained so requests such as “work on slice 3” are unambiguous. Slices 1–2 are complete; **slice 3 is next**. Later slices are proposed work, not authorization to implement the whole list. Inspect the actual code and write a bounded slice note before starting each one; later entries may need subdivision. Keep `docs/development-roadmap.md` and this list consistent when priorities change.

1. **Agreement regularity targets — complete:** optional targets, overdue diagnostics and retained agreement results; no financial penalties in this slice.
2. **Save/load — complete:** versioned manual local files preserve towns, accounts, agreements, routes, observations and live journeys across sessions; no backend or autosave.
3. **Passenger service outcomes:** actual waiting, full-bus rejections, abandoned waits and unequal access.
4. **Bus staffing and fleet investment:** recruitment, vehicle purchases and operating commitments.
5. **Transport contract enforcement:** explicitly designed remedies and financial consequences, if authorized.
6. **Civic calendar and realistic routines:** weekdays, shifts, weekends and longer budget periods.
7. **Households and household budgets:** shared income, essential expenses and financial pressure.
8. **Employment and hiring:** vacancies, unemployment, skills, wages and business staffing.
9. **Housing and occupancy:** renting, ownership, affordability, moves and displacement.
10. **Development proposals and permits:** private construction responding to zoning and demand.
11. **Physical building construction:** access, crews, materials, terrain and foundation costs.
12. **Property valuation and sunlight:** obstruction assessment and development trade-offs.
13. **Parks and public spaces:** access, maintenance and neighbourhood benefits.
14. **Crossings and junction behaviour:** pedestrian phases, yielding and turning geometry.
15. **Traffic incidents:** collisions, blocked lanes, response and clearance.
16. **Parking and freight:** deliveries, loading, parking demand and business access.
17. **Streetlighting:** coverage, electricity costs, faults and nighttime conditions.
18. **Water, drainage and waste:** networks, capacity, maintenance and failures.
19. **Municipal financial planning:** recurring departmental budgets, forecasts, debt and reserves.
20. **Population life stages:** children, students, caregivers, retirees and demographic change.
21. **Schools and skills:** catchments, staff, capacity, attendance and outcomes.
22. **Clinics and healthcare:** access, staffing, treatment capacity and patient journeys.
23. **Emergency medical response:** dispatch, travel, treatment and hospital capacity.
24. **Social care and support:** disability, housing insecurity, mental health and addiction services.
25. **Retail and household purchasing:** shops, essential goods and local spending.
26. **Production and regional trade:** inputs, freight, imports, exports and business survival.
27. **Banking and financial access:** household and business credit within a bounded economy.
28. **Neighbourhood identity and civic groups:** local priorities, associations and collective action.
29. **Culture and community institutions:** gathering places, fictional faith centres and events.
30. **Crime and prevention:** inspectable causes, victim impacts and reporting.
31. **Policing and investigation:** staffing, response, evidence, enforcement and trust.
32. **Courts and rehabilitation:** backlogs, due process, sentencing and repeat offending.
33. **Institutional oversight:** audits, conflicts of interest, corruption and reform.
34. **Local media and public communication:** reporting, editorial interests and credibility.
35. **Consultation, lobbying and protest:** organised responses to mayoral decisions.
36. **Elections and political legitimacy:** constituencies, promises, opponents, turnout and defeat.
37. **Emergencies and resilience:** infrastructure failures, economic shocks and recovery.
38. **Generated starting towns and scenarios:** varied populations, economies and inherited problems.
39. **Larger-city scaling:** population growth, performance and tools for governing greater complexity.

Timetables, transfers and automatic route optimisation need separate transport specifications. National politics, military conflict and empire systems remain outside the municipal scope. Backend persistence is not an implied follow-up to manual file saves; discuss a changed architecture only if requested.

## Continuation instruction

If the next user asks to continue from this kickoff, carry slice 3 through implementation, Docker build/startup, focused simulation and browser verification, documentation and a refreshed kickoff. Preserve existing uncommitted work. Do not stop at a plan, add a permanent test suite, alter agreement payments or expand into later slices. Finish with what changed, what was verified and remaining limitations. If the user requests another numbered slice or changes the scope, follow that instruction instead.
