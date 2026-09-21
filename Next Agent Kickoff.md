# Next agent kickoff — observed regularity complete

Continue Common Ground in /Users/fox/Documents/ChatGPT/city. The **measured stop arrivals and service regularity reporting slice is complete**, alongside the prior operator-capital and driver-shift baseline. Read docs/stop-regularity-slice.md for exact measurement semantics, verification and limits.

Inspect current code, git status and recent commits before editing. At the start of this slice three files were staged (this kickoff, docs/operator-capital-slice.md and web/agreements.js); an external commit 64a7dbc (temp) landed during initial inspection and included that work. It was preserved. This slice's implementation and documentation were left uncommitted; do not assume that is still current. Do not reset, rewrite history or push without a request.

## Read first

Read docs/stop-regularity-slice.md first.

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
- Off-hours add no delivery target. Contracts retain window and target. Private service continues with the last operator/fleet/window after closure. Refresh/Restart clears the session.

## Completed stop-regularity slice

- Zig records a visit exactly at physical approach completion into target-stop dwell, only for current, scheduled, non-retiring service. Deployment, clearance and relief-only stops are excluded; a full bus still counts.
- Each line keeps current and most recent retired route/window records, with stable route version and stop nodes. Up to 16 stop records hold visits, latest timestamp, eligible interval count and last/mean/min/max. No observations and no intervals have explicit missing values.
- Applying a route archives the prior record immediately (even paused / same draft). Withdrawal archives and empties current; reuse starts fresh. Window changes synchronize before the next transport step's arrivals. Company/fleet/lane changes alone retain the same route/window measurements.
- Daytime pairs spanning closed hours are omitted. The new day's first visit updates latest time without inventing an overnight interval; older eligible statistics remain. All-day intervals cross midnight normally.
- Transport Authority offers current/retired selection, coverage/off-hours labels, session clock, live waiting counts, stop locate, unobserved/insufficient states and completed eligible interval statistics.
- Payments, dispatch, boarding, account rules and resident routing were not changed. No permanent tests added.

## Following agent: scope must be explicitly chosen

The natural follow-on is to **design explicit contractual regularity targets** using these observations, but no such rules are implemented or authorized by this completed slice. Before implementing a future request, settle the metric and unit, minimum evidence, grace for deployment/route edits, closed-window handling, attribution across operator changes, and any effect on payment/reserves. Do not silently use min/max or the current lifetime mean as a compliance threshold. Keep existing earned movement/dwell payments unchanged unless the next user request explicitly authorizes a change.

Other deferred features (timetable, optimizer, event log/rolling trends, transfers, save/load, purchases/recruitment, individual payroll, expansion) remain outside this slice. Do not begin them merely because they appear here. Follow the next user's bounded request and write a short slice note before implementation.

## Code map and cautions

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

See docs/stop-regularity-slice.md for this slice's checks. Docker ReleaseSafe build/startup, JS syntax/diff checks and fresh browser inspection passed. Temporary /tmp/city-stop-check.mjs matched 29 physical arrivals over 24,000 steps, omitted seven closed-window pairs and observed three all-day midnight pairs. /tmp/city-stop-stats.mjs independently recomputed last/mean/min/max and reconciled stop waiting counts over 21,000 steps (six visits per stop on a two-stop route), including live bus-lane changes. Existing /tmp/city-capital-check.mjs and /tmp/city-capital-extra.mjs passed accounts, reserve/ledger, rider, cash exhaustion, shift/expiry and physical repair checks. Temporary scripts are not repository dependencies and may disappear.

See `docs/operator-capital-slice.md` for completed checks: cash exhaustion without rescue, shared company capacity, shift/midnight/expiry, quote/refusal/revision, handover, ledger/account reconciliation, passenger conservation, route editing/reuse/paused withdrawal, physical repair, road construction/zoning and finite rendering. No permanent tests were added.

Use a fresh temporary tab at `http://localhost:8080/`; never reset the user's town. Confirm compiler success before refreshing: failed builds retain the last good WASM. Keep accounting/reserve checks in temporary scripts outside the repository.

Driver staff are aggregate cohorts, empty deployment is abstracted, clearance/relief uses a fixed prepaid fee, and operating buffers are acceptance thresholds rather than escrow. No resident employment/payroll link, purchases/recruitment, transfers, full timetable, collisions, new service domains or city expansion. Save/load remains later work. Observed regularity remains descriptive, with one retired record per line and no historical waiting-duration distribution or compliance score.
