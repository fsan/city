# Next agent kickoff — Common Ground

Continue the project in `/Users/fox/Documents/ChatGPT/city`. Read `Development Agent Kickoff.md`, `Modern City Management Game Scope Specification.md`, `README.md`, and `docs/transport.md` first. Treat the long-term scope as design context, not a request to implement every domain at once. Follow the user's latest instruction if it changes this handoff.

## Product direction and constraints

This is a modern city-management simulation inspired by Songs of Syx. The player is mayor of an existing city, with reports and policy levers, not an idle game or a sequence of guaranteed timed rewards. Residents and firms make constrained decisions. The whole viewport is the isometric city; reports are movable, closable in-game windows. Keep the current restrained municipal UI and urban colours. Placeholder cuboids and cheap resident sprites are intentional.

Use Zig for simulation, rules and geometry. Browser JavaScript is the small WebGL/input/UI adapter. Build and run with Docker Compose (`make build`, `make run`) and Zig 0.14.1 inside the compiler container. Do not install host compilers, bundlers or game engines. Do not add a test suite now: the user wants development time spent on the playable slice. Compile and perform focused gameplay/smoke checks. Keep names straightforward, modules small, documentation brief and current. Do not replace the architecture with a framework.

## Existing game

Bellwether has 288 fixed lots, 12 districts, 3,840 adult placeholder residents, 60 employers, 323 street junctions and 610 segments. Elevation ranges from 0 to 24 abstract metres. Buildings have explicit street/frontage links. A day lasts eight real minutes. There is no generated city or persistence; refreshing starts a fresh simulation.

The management baseline has population/company/street reports, resident and property inspection, separate property taxes, actual tax collection and arrears, an auditable municipal ledger, recurring service and road budgets, and company-delivered street repairs. Offers can be refused; actual crews must travel and perform work before payment. Reservations protect committed work-order money. Do not break this loop when extending transport.

The completed transport slice adds:

- Walking, cycling, cars leaving/entering buildings, and buses with real riders. Residents compare estimated time and out-of-pocket cost weighted by income, and can only use their bicycle/car where it is parked.
- Savings-based car purchase decisions, mobility wallets, income/operating costs and inspectable departure scores. These are explicitly simplified, not a complete household economy.
- Directional vehicle queues, acceleration, body-length following gaps, staggered signals, downstream admission and queues that remain on approach links. Terrain, condition and works affect speed.
- Traffic pressure map (G), street inspection from the map, queue hotspots, and mixed/bus/cycle street allocation. Vehicles finish their current link in their old lane when allocation changes.
- Two initial circular bus lines. Up to eight lines, two buses per line, 24 passengers per bus, 2–16 stops. Stops have street addresses; the route editor supports moving stops and inserting stops by dragging route segments. Changes are drafted then applied. New/withdrawn lines work.
- Fare caps and per-boarding subsidies, operator capital, fare/subsidy income and bus running costs. Subsidies debit uncommitted municipal funds through the ledger. Removing or changing a line unloads existing riders safely at a junction; service also suspends if operator cash runs out.

T opens Transport Authority. Bus buttons locate vehicles. Resident and street inspectors link to transport controls. Escape first cancels a route draft. Read `docs/transport.md` for exact formulas and acknowledged limits rather than assuming full traffic realism.

## Code map

- `src/scene/city.zig`: authored town, heights, street graph, shared next-hop paths.
- `src/simulation/game.zig`: fixed-step orchestration, daily/periodic updates, subsidy settlement and history.
- `residents.zig`: people, employers, ordinary/crew travel, ownership, mode choice, bus boarding/alighting.
- `transport.zig`: vehicles, lane queues and reservations, bus service lifecycle, policies, route draft.
- `finance.zig`: municipal cash, tax, ledger and protected reservations.
- `contracts.zig`: repair offers, firm acceptance, crew mobilisation, progress and settlement.
- `src/main.zig`: validated command exports and scalar read API. `docs/abi.md` lists groups/fields.
- `src/render/scene.zig`: CPU projection, world geometry, vehicles, route overlays, camera/picking.
- `web/main.js`: loading, input, frame loop; `ui.js`: window stack; `reports.js`: reports/inspectors; `transport.js`: route editor/transport presentation; `index.html`: markup; `style.css`: visual style.

Keep transport independent of finance and residents to avoid circular imports; the game module coordinates money. IDs are fixed array slots. Avoid iterating large global arrays by value: the expanded resident record exposed WASM stack exhaustion in reporting, fixed by reference iteration. Do not work around this by simply inflating stack limits.

## Recommended next slice, subject to the user's direction

Develop **bus operators and service agreements** as an extension of the existing management loop. The user explicitly wants eventual control of payments to companies managing buses. Keep this separate from street-repair orders, while reusing protected municipal commitments and the ledger.

A bounded playable increment should let the mayor inspect a route's demand, delivered service and finances; offer a service agreement with defined duration, required fleet and payment; let eligible companies accept or decline based on resources and profitability; and pay for service actually delivered. Expose why service fails, what a company lacks, and the consequences of an underfunded fare cap. Preserve route editing and existing riders during operator changes. Start with a few authored operators and simple labour/fleet capacity. Do not simulate full procurement law or every transport mode.

Before implementing, review the current data structures and write a short slice note with acceptance criteria. If the user's next task is different, retain this only as a recommendation. Useful later increments include proper daily schedules, transfers, observed headways, FIFO stop queues, persistence, construction costs for lane changes, and vehicle-specific routing. Avoid mixing all of these into one increment.

## Practical start and verification

1. Inspect `git status` and `git log -5`; preserve user changes and commits. The pre-transport baseline is `3242e9a`. The user also committed an intermediate transport draft as `d429242` (`update`); the completion work follows it. Do not rewrite that history or push without a request.
2. Run `make run`, check compiler health and open `http://localhost:8080/`. Each browser tab has an independent world. A failed Zig rebuild retains the last good WASM; confirm compiler output before refreshing.
3. Verify the scenario relevant to your change. Current transport checks cover new/removed lines, address selection, stop dragging, segment dragging, policy/lane changes and passenger lifecycle. Ephemeral WASM runs checked capacity, lane spacing, passenger conservation, trip completion and invalid input rejection without adding test files.
4. Update the short module docs and mechanics notes. State modelling limits honestly. Leave the requested next slice playable, with a concise report of changes and verification.

Browser checks should use a temporary local tab so the user's running town is not reset. The previous browser sample ran near 120 FPS at 1280×720; this is an observation, not a performance guarantee. Geometry still rebuilds each frame, with a 600,000-vertex capacity. Optimise based on profiling, not speculative complexity.
