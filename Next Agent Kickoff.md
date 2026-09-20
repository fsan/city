# Next agent kickoff — operator finances and driver coverage

Continue Common Ground in `/Users/fox/Documents/ChatGPT/city`. Implement the next bounded playable slice: **bus operator working capital and driver shifts**. Work through implementation, focused verification and documentation until this slice is complete. The earlier first-agreement and agreement-review recommendations are already implemented; do not repeat them.

This handoff was updated on 20 September 2026 after the agreement-review slice. Other work may follow it. Inspect the actual code, `git status --short` and recent commits first; reconcile this note against newer changes. At handoff, the completed agreement-review work is still uncommitted, including new `web/agreements.js` and `docs/agreement-review-slice.md`. Preserve it and any later user changes. Do not reset, rewrite history or push without a request.

## Read first

1. `README.md`, `docs/service-agreements.md`, `docs/agreement-review-slice.md` and `docs/abi.md` for the implemented baseline.
2. `docs/city-planning.md` for current roads, parcels and dynamic graph assumptions.
3. `docs/transport.md`, `docs/economy.md` and the relevant simulation/browser modules.
4. `Development Agent Kickoff.md` and `Modern City Management Game Scope Specification.md` for product direction. Their initial planning-only instructions describe an earlier stage; the current request authorizes implementing this next slice.

Before coding, write a short slice note with the chosen accounting, driver-coverage rules and acceptance criteria. Resolve routine choices autonomously from the current code and this scope; this is not a request to stop after producing another plan.

## Product and development constraints

The player is mayor of an existing city. Firms and residents have resources and constraints; outcomes follow actual service and spending. Keep failures inspectable and decisions consequential. Preserve the full-viewport isometric city and movable, closable municipal report windows. Placeholder geometry and resident sprites are intentional.

Use Zig for rules, simulation and geometry; JavaScript remains the WebGL/input/report adapter. Use Docker Compose and Zig 0.14.1 in the compiler container (`make build`, `make run`). Do not install a host compiler, bundler, engine or framework. Keep modules small and names straightforward. Do not add a permanent test suite: compile and run focused temporary WASM/gameplay checks. Do not create parallel agent work unless the user explicitly requests it.

## Current baseline to preserve

- 3,840 adult placeholder residents, 12 districts, 60 employers and 288 seeded parcels across 34 irregular street blocks. The map is **520 × 440**; older 360 × 320/grid descriptions are historical. Node/road counts are dynamic. Buildings and parcels have separate street/frontage links.
- Straight/curved player-built roads, automatic junction splitting, construction debits, parcel/block zoning and pedestrian-density overlay are implemented. Do not revert these while extending transport.
- Property taxes, a municipal cash ledger, operating expenses, protected commitments and company-delivered street repairs work. Contractors travel and perform work before settlement.
- Walking, cycling, cars and real bus passengers; directional queues, signals, bus/cycle allocations, route editing and safe retirement of old buses work. Up to eight lines, one to three buses per agreement, 24 seats per bus and 2–16 stops.
- Operator comparisons use Zig quotes. Offers reserve their entire maximum price; companies accept or explain capacity/price refusals. Active agreements earn payment from movement and scheduled dwell, not held traffic or unavailable service.
- Agreements have unique numbers and immutable closed records, newest 64 per session. Revision, cancellation, expiry and withdrawal preserve original terms, offered route, delivery, paid and released amounts. Ledger category 8 identifies operator and agreement number.
- Cancellation/withdrawal settle earned pennies and release reserves immediately, including while paused. Capacity is released once. Operator replacement preserves riders. Live service states, waiting passengers and elapsed delivery shortfall are visible.
- A day is 480 simulation seconds. Refresh/Restart town clears the session; save/load is not implemented.

The limitation this slice addresses: operator `cash` currently means **cumulative agreement receipts**, while each line separately starts with £3,000 and pays £0.18 per active bus-second. Fleet and drivers are one bundled capacity number. Companies do not yet have real working-capital constraints or driver coverage that changes over the day.

## Next playable slice

The mayor should be able to diagnose whether a line lacks money, buses or on-duty drivers; inspect the responsible company's accounts and coverage; change an explicit service offer; and observe acceptance, actual dispatch and earned payments respond.

### Real operator finances

Introduce one authoritative working-capital balance per authored bus operator, with documented seed balances. Keep cumulative receipts distinct from spendable cash. Attribute fares, funded boarding subsidies, earned agreement payments and operating costs exactly once to the responsible account. Retain per-line income/cost reporting as attribution rather than a second spendable balance.

Give each operating line a clear operator, including the initial/private services. Define who funds a line before, during and after an agreement, and who pays for old buses while they finish a segment or unload after a handover. Route editing, line reuse, cancellation, expiry and operator changes must not reset a company's cash, create free capital, duplicate revenue or erase losses. Do not silently transfer an outgoing company's money to its replacement.

Acceptance should consider available working capital as well as fleet, coverage and a legible cost/margin estimate. Show the minimum operating buffer and why an offer is declined. A larger promised future payment is not cash already in hand. Keep procurement quotes and acceptance driven by the same Zig rules.

Expose actual opening balance, receipts, expenses and available cash with enough detail to reconcile them. Keep the municipal ledger for municipal transactions; use a small bounded operator account record or equivalent reconciled breakdown for private fares/costs. Never pay an unfunded subsidy or spend protected municipal reserves to mask company insolvency.

### Driver shifts and contracted coverage

Separate owned buses from available drivers. Start with a small authored driver roster or explicit shift cohorts per operator, tied to the 480-second day. Drivers may be abstract staff records for this slice; a new resident employment/payroll simulation is out of scope. Make that abstraction explicit.

Add a bounded service-window choice to the offer, such as daytime versus all-day coverage, with stated hours. Show on-duty, committed and available drivers, including coverage across midnight. Reserve capacity across all of an operator's commitments; overlapping services cannot double-book the same driver. Distinguish an off-duty driver from an unavailable vehicle and an exhausted account.

Only funded, staffed buses dispatch. Model shift change/relief at a safe stopping point; riders must remain accounted for, with no disappearance or teleportation when coverage ends. Charge driver labour once. If splitting the old £0.18 operating rate into wages and vehicle costs, remove the old combined debit rather than charging both.

Delivery targets, quotes, expiry and payment must agree on contracted service hours. Off-hours are not missed contracted service; a missing driver during promised hours is. Route edits must not restart the agreement clock or alter archived terms. Snapshots should retain the agreed service window and relevant final delivery figures.

### Mayor-facing loop

Extend the existing Transport Authority and agreement review, keeping the current visual style. Present company balances, cost components and shift coverage alongside draft comparisons. Clearly distinguish live status (off hours, no driver, no bus, no cash, held traffic) from measured delivery history.

The mayor controls service requirements and public payment, not a company's private money or an individual's work assignment. A feasible response can be reducing fleet/hours, offering an adequate payment to a viable company, or changing operator. Retain existing cancellation/re-offer controls and explain their consequences. No unconditional bailout, free balance reset or guaranteed rescue button.

## Completion criteria

1. The initial town has operating bus services with inspectable operator cash and driver coverage, and remains playable.
2. Fare/subsidy/agreement income and vehicle/driver costs reconcile to company balances; municipal payments reconcile to the ledger. No transaction is credited or charged twice.
3. Draft comparison and acceptance explain distinct cash, vehicle, driver-coverage and price refusals. Concurrent commitments cannot overbook resources.
4. At least one reproducible scenario demonstrates a resource refusal and a feasible revised offer or alternate operator that actually delivers service. Time passing alone does not guarantee recovery.
5. Shift boundaries, overnight coverage and contract expiry produce the documented bus/driver behaviour. Off-hours do not accumulate delivery shortfall; unstaffed promised hours do not earn payment.
6. Low funds suspend service without negative spendable cash or disappearing passengers. Any limited costs needed to clear a bus safely are explicitly funded/accounted for, not hidden debt.
7. Route edits, fleet reductions, cancellation, paused withdrawal and operator replacement preserve riders, accounting, protected reserves and closed agreement history.
8. Existing road construction/zoning and physical street-repair delivery still work. Builds, focused smoke checks and documentation are complete.

## Keep outside this slice

No save/load, fleet purchases, driver recruitment, individual driver travel, full household payroll, headway/stop-completion targets, transfers, full timetables, legal procurement, accidents, new civic-service domains or city expansion. Do not mix these into this increment. Save/load and measured service regularity remain later work.

## Code map and implementation cautions

- `src/simulation/agreements.zig`: quotes, operator resources, protected service commitments, earned settlement and closed history.
- `src/simulation/transport.zig`: fleet lifecycle, service accounts/counters, vehicle movement, boarding income and running costs.
- `src/simulation/residents.zig`: trip decisions, boarding/alighting and safe walking fallback.
- `src/simulation/game.zig`: update ordering and coordination across transport, residents, agreements and finance.
- `src/simulation/finance.zig`: public cash, commitments and ledger. `contracts.zig`: street orders.
- `src/main.zig`: validated commands and scalar read ABI; retain existing field numbers when extending.
- `web/agreements.js`: draft comparison, delivery review and closed register. `web/transport.js`: routes and transport controls. `web/reports.js`: municipal ledger/operator labels. HTML/CSS remain in `web/index.html` and `web/style.css`.
- `src/simulation/roads.zig`, `src/scene/parcels.zig`, `web/planning.js`: current planning slice.

Keep transport independent of finance/residents to avoid circular imports; use game-level coordination or a small independent operator module if needed. Do not iterate large resident arrays by value: previous WASM stack exhaustion was fixed by reference iteration, not a larger stack. Use stable IDs and scalar read access; the browser must not infer Zig struct layouts.

## Verification and handoff

Use a fresh temporary browser tab at `http://localhost:8080/`; do not reset the user's running town. Check compiler output before refreshing: a failed rebuild retains the last good WASM. Browser tabs have independent simulations.

Temporary checks should cover multiple lines sharing an operator, midnight/shift boundaries, cash exhaustion, quotes versus acceptance, earned settlement and reserve reconciliation, cancellation/expiry/paused withdrawal, line reuse, route editing, passenger conservation and one completed street repair. Sample rendering for finite vertices and capacity rather than adding a performance project. No permanent test files are requested.

Previous agreement-review checks passed: a 611-second simulation exercise closed 76 records with 64 retained; rider conservation and finite rendering held. A separate shared-budget run completed a £9,588.81 physical repair alongside a £211.50 service settlement and reconciled 212 agreement payment entries. These are baseline observations, not substitutes for checking the new model.

Update the mechanics docs, ABI and this kickoff when finished. Report the playable changes, verification and remaining modelling limits concisely. Leave the next slice concrete and reviewable; do not stop at a plan or partially connected UI.
