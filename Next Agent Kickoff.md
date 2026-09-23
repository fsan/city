# Next agent kickoff — slices 8, 9 and 10 complete in the worktree

Continue Common Ground in /Users/fox/Documents/ChatGPT/city. Slices 1–3 are complete and committed at `704a918`; slice 4 at `60a000a`; slice 5 at `4e29f2f`; slice 6 at `cfa432d`; slice 7 at `dcc2577`; slice 8 at `e71fa0b`. Slices 9 (housing and occupancy) and 10 (street types, parking and learned travel) are complete in the worktree and are **not yet committed**; commit them before starting slice 11. Those batches added optional agreement regularity targets, manual local save/load, measured passenger service outcomes, kerbside bus-stop placement/markers, smoother inter-segment vehicle movement, explicit bus fleet and staffing commitments, and cure-first transport contract enforcement.

**Authorized goal:** implement slice 9 of the numbered development sequence as a bounded batch; slices 5, 6, 7 and 8 are complete. Each slice must have its own short slice note, Docker ReleaseSafe build, focused simulation checks, browser/report verification where applicable, documentation, and a refreshed kickoff before the next slice starts. This authorizes slice 9 only; it does not authorize slices 10–39 or a single unbounded rewrite.

Inspect current code, git status and recent commits before editing. The `.tmp_degrees.zig` cleanup item is done: the temporary file was removed in `60a000a`. Do not reset, rewrite history or push without a request.

## Read first

Start with `docs/development-roadmap.md`, then `docs/passenger-outcomes-slice.md`, `docs/save-load-slice.md`, `docs/regularity-target-slice.md` and `docs/stop-regularity-slice.md`.

Read `README.md`, `docs/operator-capital-slice.md`, `docs/service-agreements.md`, `docs/transport.md`, `docs/abi.md` and `docs/city-planning.md`. The operator-capital note contains the exact accounting rules, limitations, refusal/remedy scenarios and verification history. The Development Agent Kickoff and Modern City Management Game Scope Specification provide product direction; their old planning-only phase does not replace a new implementation request.

Use Zig for rules and measurements, JavaScript for WebGL/input/reports. Compile with Docker Compose and Zig 0.14.1 (`make build`, `make run`), but confirm the container build actually publishes the current source. The watch loop and `make build` use disposable Zig caches because a stale shared cache previously published an old WASM while reporting success. No host compiler, bundler, framework, permanent test suite or parallel agent work unless specifically requested. Before coding each slice, write a short slice note and then carry that slice through verification and documentation.

## Preserve this baseline

- Full-viewport isometric 520 × 440 town, 3,840 adult placeholders, 12 districts, 60 employers, 288 seeded parcels; dynamic road/node counts and separate frontage links.
- Player-built straight/curved streets, splitting/junctions, construction debits, parcel/block zoning and pedestrian overlay.
- Protected municipal commitments and penny ledger; company crews must physically travel and perform street repairs before payment.
- Walking, cycles, cars and real bus passengers; directional queues/signals/lane allocation, route editing and safe bus retirement. Eight line slots, 1–3 buses, 24 seats, 2–16 stops.
- Bus stops are validated against `city.validStop`, rendered at kerbside `city.stopPoint` positions, and active lines keep visible stop markers even when the Transport Authority window is closed. Route-editor stop selection uses valid kerbside projections.
- Vehicles carry momentum across ordinary street segments. They brake for target stops, red signals, blocked downstream lanes and following gaps instead of stopping at every node. Keep this behavior unless a later slice explicitly changes it.
- Authoritative operator accounts in `operators.zig`: opening £600/£300/£5, independent fares/subsidies/agreement receipts, £0.06 vehicle + £0.12 driver labour per bus-second, £2 prepaid dispatch clearance fee. Line totals are attribution only.
- Owned buses 4/3/2 in depots of 6/5/3, recruited day/night driver rosters 4/2, 3/1, 2/0. Daytime 06:00–22:00 (seconds 120–440); all-day includes midnight. One day is 480 seconds. Acceptance accounts for private lines as well as contracts, with cash buffer, vehicle, depot, maintenance, driver, coverage and price refusals.
- Each vehicle retains its operator while clearing. No money transfers on handover and no cash resets on reuse. Clearing is paid by the already-expensed flat fee, occupies physical resources and earns no delivery. Low cash retires safely without negative balances. All-day driver relief occurs at a junction.
- Employment (slice 8): one adult in eight starts out of work; employers post £40/£55/£70 per day and a minimum skill (0 general, 1 clerical, 2 professional); a daily rollover hires up to 64 qualified jobseekers (closest home-to-work first), dismisses up to two lowest-skill ordinary staff at any employer carrying arrears (never crew members or workers on an active order), then pays the wages its cash covers. Unpaid amounts stay as explicit employer wage arrears. Household `income` is the posted wage of employed members; `paid_wages` is what was actually credited. Schema v7 (`bellwether-2027-02-v7`); v6 and older are rejected with result 3.
- Off-hours add no delivery target. Contracts retain window and target. Private service continues with the last operator/fleet/window after closure. Refresh/Restart clears the live session; manual import restores an exported town.
- Passenger outcomes are measured from real transitions, not report polling: wait starts, completed waits with mean/min/max, per-dwell full-bus denials, abandonment causes, and home-district comparison. Existing data stays tied to stable route versions.
- Manual save/load is local and browser-owned. The current schema is `version: 6`, `rules: "bellwether-2027-01-v6"` after slice 7. Version 5 and older files are rejected explicitly; there is no migration layer.

## Completed work relevant to the authorized goal

- **Regularity targets:** offers accept 0 or a whole 30–600 simulation seconds. Review is advisory and agreement-specific; no payment penalty. Retired/current stop records are bounded.
- **Save/load:** typed JSON snapshots preserve clock, speed, graph, routing tables, zoning, residents, journeys, riders, operators, vehicles, shifts, taxes, ledger, reserves, orders, crews, routes, observations, agreements, targets, history, next IDs, and every slice-4 fleet unit, roster count and lifetime flow. Parsing is bounded and staged; invalid imports leave the live town unchanged.
- **Passenger outcomes:** Zig records actual wait starts, boardings, completed wait statistics, capacity denials, timeout/off-hours/fare/service abandonment and district comparison. Route edits close old-version waits before archiving. Save version 3 preserves every new counter and in-progress wait.
- **Transport polish:** stop validity and kerbside markers are in `city.zig`, `render/scene.zig`, `main.zig` and `web/transport.js`. Movement smoothing is in `transport.zig`; the measured old/new comparison showed per-step skips falling from 79 to 4 and mean moving speed rising from 1.54 to 2.73 m/s.
- **Civic calendar and realistic routines (slice 6):** bounded weekday/weekend calendar, day/evening/night resident shifts, routine phases and local errands, weekly municipal budget periods from ledger movements only, schema version 5. See `docs/civic-calendar-slice.md`.
- **Transport contract enforcement (slice 5):** cure-first service credit on delivered bus-seconds only; 480-second cure, GBP 0.18 per missing bus-second, 25% price cap, GBP 2.18 cash floor with waiver instead of debt, route/service-change suspension, ledger kind 10. See `docs/transport-enforcement-slice.md`.
- **Bus staffing and fleet investment (slice 4):** `operators.zig` holds a depot capacity, a recruited day and night roster and eight tracked units per operator. Units carry condition, a maintenance state and the physical bus occupying them. Recruiting a day driver costs £150, a night endorsement £260 and requires a day-qualified driver already on the roster; dismissal pays £60. A bus costs £520, sells for 55% of its condition-scaled value, wears only while a service bus is moving, dwelling or held in traffic, and enters a £160/240-second repair when exhausted. Clearing buses hold their unit until every rider has left, so they physically block replacement dispatch. Quotes and acceptance read the same live owned/serviceable/committed split and the recruited cohorts. Save schema is version 3. See `docs/operator-workforce-slice.md` for rules, verification and limits. Browser verification of the new Fleet & staff panel was limited to served-markup, module parse, scalar-ABI contract and served-WASM identity checks because no headless browser was available.

## Completed slice 4 — bus staffing and fleet investment

Implemented, verified and committed in `60a000a`, with its short note at `docs/operator-workforce-slice.md`. This batch replaced the fixed aggregate driver cohorts and owned-fleet numbers with explicit operating commitments, as originally specified:

- Driver cohorts become recruit/dismiss decisions with explicit wages, availability, shift coverage and qualification/training prerequisites.
- Fleet becomes an owned asset pool with explicit purchase/sale, depot/yard capacity, maintenance condition and operating availability.
- Line dispatch and agreement acceptance use the same live fleet/driver commitments, including clearing vehicles and off-hours coverage.
- Operator accounts remain independent. Purchases, sales, wages, maintenance and recruitment reconcile with opening capital, fares, subsidies, agreement receipts and existing expenses. No hidden cash creation.
- Refusals and remedies must be explicit: insufficient cash, no depot space, no qualified drivers, off-hours coverage gap, vehicle under maintenance, full commitment elsewhere.
- Preserve fares, passenger boarding, passenger outcomes, route/stop behavior, agreement payments, reserves, ledger categories, municipal funds and safe retirement behavior.
- Define retirement/depreciation/maintenance semantics, including what happens when an operator has insufficient cash or a line is withdrawn.
- Extend save/load if the schema changes. Bump version/rules, validate every new field and reject incompatible files explicitly.

Likely ABI/UI additions: operator fleet/driver breakdown, owned/available/committed/maintenance vehicles, recruitment quotes and blockers, purchase/sale quotes, depot capacity, wages and maintenance costs. Reports use usable units/denominators and explicit unavailable states. Do not infer availability from a line simply being active.

Verification must cover atomic purchase/recruitment/refusal, cash exhaustion without negative balances, shift and off-hours coverage, vehicle purchase/sale/maintenance lifecycle, agreement acceptance/dispatch with shared capacity, safe handover/clearing, passenger conservation, ledger/account reconciliation, protected reserves, route/stop behavior, movement continuity, save/load round trips with every new counter and in-progress commitment, and browser/report behavior.

## Completed slice 5 — transport contract enforcement

Complete. `docs/transport-enforcement-slice.md` records the implemented rules, verification and limits. The enforceable figure is the delivered bus-second integral; regularity remains review-only; route/service changes suspend enforcement; unpaid credit is waived. It may add financial consequences or remedies for agreed service failures, but it must not silently change existing agreement payments or turn the review-only regularity targets from slices 1–3 into penalties.

- Define which contractual outcomes are enforceable and from which evidence: delivered bus-seconds, target-stop arrivals, missed windows, suspended review after a route change, cancellation, expiry or withdrawal.
- Distinguish review-only regularity evidence from enforceable contract performance. Route edits suspend target review; decide explicitly whether they suspend, terminate, or renegotiate enforcement.
- Define remedies: deductions, refunds, service credits, cure periods, replacement obligations, escrow/release changes, or cancellation rights. No remedy may create negative operator cash or hidden municipal debt.
- Preserve protected municipal reserves and ledger categories, or add a new explicit category with validation and UI reconciliation.
- Refusals and remedies must be reproducible and explainable in reports: why money moved, what evidence was used, and what remains disputed or unobserved.
- Extend save/load for every new obligation, remedy, penalty, cure period and settlement field.
- Verification must cover evidence boundaries, expiry/closure, route changes, paused actions, simultaneous arrivals, off-hours, atomic rejection, cash floors, ledger/account reconciliation, passenger conservation and save/load continuation.

Do not add a full court/legal system, discretionary adjudication, or later policing/courts slices here.

## Completed slice 6 — civic calendar and realistic routines

Complete. See `docs/civic-calendar-slice.md`.

Complete. `docs/civic-calendar-slice.md` records the implemented rules, verification and limits. The shared calendar keeps the 480-second day and 06:00–22:00 / all-day transport windows, adds bounded weekday/weekend routines and shifts, and closes a weekly budget period from recorded ledger movements only.

- Define weekdays, weekends, shifts, holidays or longer budget periods only as far as they affect existing simulation systems. Do not create a full national calendar or political system.
- Residents get realistic routine phases beyond the current shortened work/home loop: sleep, commute windows, shifts, school/errand placeholders if already supported, and recovery/leisure time.
- Transport demand, road congestion and passenger wait outcomes must respond to the calendar through actual resident transitions, not report polling.
- Contract windows and operator staffing must use the same calendar/time abstraction. Preserve all-day and 06:00–22:00 semantics or extend them explicitly.
- Municipal budget periods, taxes, operating disbursements and ledger/history sampling may gain longer periods, but every recurring transaction must be explicit, bounded and reconciled.
- Save/load must preserve calendar state, routine phase, shift membership, pending events and next-deadline scheduling.
- Verification must cover ordinary weekdays, weekends, shift boundaries, off-hours, day rollover, long budget periods, passenger conservation, transport dispatch, agreement windows, accounting identities, save/load continuation and browser reports.

Do not add elections, national holidays, seasonal weather or demographic life stages here.

## Completed slice 7 — households and household budgets

Complete. `docs/households-budgets-slice.md` records the implemented rules, verification and limits. One bounded household per home shares a daily budget: employed income is credited, a bounded essential expense is billed, and unpaid essentials become visible arrears. Fares, car costs and car purchase spend from the shared balance; walking remains safe. Schema v6.

- Define households, shared income, essential expenses, discretionary spending, savings or arrears, and how household members share resources.
- Existing resident income/employment placeholders must map into household income. Do not create a complete macroeconomy or banking system.
- Essential expenses may include housing, food, utilities, transport and other bounded categories. Spending must be explicit and reconciled; no silent money creation.
- Financial pressure should affect travel choices, bus affordability, household arrears or savings, and potentially housing later. It must not break safe walking fallback or passenger conservation.
- Household budgets must interact with taxes, subsidies, fares, wages and operator receipts through existing municipal/operator interfaces.
- Save/load must preserve household membership, budgets, arrears, shared balances and any pending transfers.
- Verification must cover income/expense conservation, shared household accounting, affordability transitions, transport fallback, tax/ledger reconciliation, operator accounts, save/load and browser reports.

Do not add retail purchasing, banking/credit or housing markets in this slice; those belong to later batches.

## Completed slice 8 — employment and hiring

Complete. `docs/employment-hiring-slice.md` records the implemented rules, verification and limits. One adult in eight starts out of work; employers post a wage and a minimum skill; a daily rollover hires up to 64 qualified jobseekers, dismisses a bounded number of ordinary staff at any employer carrying wage arrears, then pays the wages its cash covers. Unpaid amounts stay as explicit employer arrears. Schema v7. This slice turned the previous fixed employer assignment into bounded vacancies, unemployment, skills, wages and business staffing.

- Employers have vacancies/capacity, wage offers, skill requirements and staffing pressure. Residents have skills or qualifications and job-search/commuting decisions.
- Hiring, firing, vacancies and unemployment must reconcile with existing employer counts, household income, routines and transport demand.
- Business staffing affects openings/closures or service capacity only within an explicitly bounded model. No full production/trade economy yet.
- Wage payments must reconcile with employer cash and household income without hidden transfers.
- Save/load must preserve vacancies, applications, employment links, skills, wages and hiring state.
- Verification must cover vacancy filling, unemployment, skill mismatch, wage changes, employer cash, household income, routine changes, passenger demand, transport dispatch, accounting identities, save/load and reports.

Do not add regional trade, production inputs, business credit or national labour markets here.

## Completed slice 9 — housing and occupancy

Complete in the worktree (not yet committed). `docs/housing-occupancy-slice.md`
records the rules, verification and limits. Every authored home is one housing
unit with tenure, rent or ownership cost, a property-owner reserve, explicit
arrears, occupancy, a move state and an application target. A bounded daily
rollover can move or displace households into a cheaper, shorter-commute vacant
unit; residents walk to the new address. Save schema is version 8,
`bellwether-2027-03-v8`.

## Completed slice 10 — street types, parking and learned travel (current batch)

Complete in the worktree (not yet committed). `docs/street-types-parking-learning-slice.md`
records the implemented rules, verification and limits.

- Street segments carry a class (0 lane, 1 street, 2 avenue) chosen in the road
  tool and priced at £18/£25/£40 per metre; class sets the car speed limit.
- Proportional free-flow speeds: walk 1.4 m/s, cycle 4.2 m/s (5.0 protected),
  car 7 m/s scaled by class, bus 5.5 m/s.
- Walkers and cyclists obey signals and crosswalks (`residents.crossingWait`,
  bounded 30-second patience); cars yield while somebody is on a crossing.
- `parking.zig` seeds bicycle parks and car parks by district density with hard
  slot counts, plus kerbside car spaces on streets/avenues priced in bands by
  the segment's smoothed movement and capped at £1.20; fees are municipal
  ledger kind 11.
- Travellers aim for the place they expect to be free, fall back to the nearest
  free one, then walk the rest; cyclists ride the kerb-side lane of their own
  direction of travel and park before entering a building.
- Every resident keeps a tiny learned model (mean trip seconds per mode and
  departure bucket; remembered parking chance per place and bucket), folded in
  as one bounded batch on arrival at work or home; mode choice and departure
  time read it. Car-owning households with the car preference drive.
- Tenure drives the municipal assessment: owners pay from the household, rented
  homes pay from the owner's collected rent; unpaid assessment stays arrears.
- Save schema is version 11, `bellwether-2027-09-v11` (slice 12); version 10 and
  older are
  rejected with result 3. A 22-road expanded graph still fits the 16 MiB cap.
  Slice 11 serialises player-placed traffic signals alongside it.

## Superseded slice 9 plan text (historical)

This slice follows slice 8 and is the current batch. It adds renting, ownership, affordability, moves and displacement on top of the household and employment models.

- Define housing units, occupancy, rent/ownership costs, affordability thresholds, moves, vacancies and displacement.
- Households may move or be displaced based on affordability, employment/commute changes or housing availability. Moves must use actual resident transitions, not teleportation.
- Housing costs interact with household budgets, wages, municipal taxes/benefits and transport access. No silent money creation or unexplained occupancy changes.
- Property ownership, rent collection and municipal assessments must reconcile with the existing ledger, arrears and building data.
- Save/load must preserve housing units, tenure, occupancy, rents, arrears, applications and move state.
- Verification must cover moves, displacement, affordability, vacancy, rent/income conservation, tax/ledger reconciliation, commuting/transport effects, passenger conservation, save/load and reports.

Do not add physical building construction, property development permits, valuation/sunlight modelling, parks or demolition here; those are later slices.

## Code map and cautions

- `src/simulation/operators.zig`: independent accounts, day/night cohorts, service-window integrals. Slice 4 will likely replace or extend the fixed cohort/asset numbers here.
- `src/simulation/transport.zig`: physical fleet, original bus ownership, clearance, drivers, fares/costs, delivered seconds, dispatch blockers and service-state counts. Keep it independent of finance/residents except through explicit interfaces. Movement smoothing lives here; do not reintroduce per-segment hard brakes.
- `src/simulation/agreements.zig`: quote/acceptance, settlement, window-aware targets, history. Slice 5 must define enforcement without silently changing slices 1–4 payment semantics.
- `src/simulation/residents.zig`: actual boarding/alighting, walking fallback, passenger wait transitions and district outcomes. Slices 6–9 will extend routines, households and employment here or in adjacent modules. Do not change boarding order without an explicit request.
- `src/simulation/persistence.zig`: explicit typed JSON snapshot, bounded validation/commit. Every new persistent field in slices 4–9 must be represented and validated; bump compatibility identifiers when the schema changes.
- `src/main.zig`: validated exports and scalar ABI. Preserve field numbers. Existing groups include 10 fields 32–40, 13/17 agreement fields, 14 operator accounts/drivers, 18/19 stop/passenger observations, 20/21 agreement stop results and group 22 district passenger outcomes.
- `src/scene/city.zig`: `validStop`, `stopPoint`, `sidewalk`, graph/routing data.
- `src/render/scene.zig`: kerbside stop markers drawn for all active lines; selected lines add a larger highlight. Keep finite vertex output.
- `web/transport.js`: routes/map gestures, stop-address filtering, kerbside projections, passenger and stop reports. `web/agreements.js`: quotes, accounts, coverage, current/closed delivery. `web/reports.js`: municipal ledger. `web/index.html` owns the report controls.
- `Makefile`, `docker/watch.sh`: build the WASM with disposable local/global Zig caches. Verify the served `/build/city.wasm` hash or behavior after a rebuild; a failed build retains the last good artifact.

Never iterate the large resident array by value; it previously exhausted the WASM stack. Read through scalar ABI, not inferred struct layouts. Existing operator totals retain sub-penny operating accrual; municipal transactions and policy fares/subsidies round at penny boundaries.

## Verification and remaining limits

Slice 8's probe (24 checks, 0 failures) covered init skill/wage consistency, jobseekers and vacancies, hiring on a rollover, unemployment transition, employer totals against live links, wage conservation, employer cash floors, household balance conservation, skill-mismatch refusal, arrears and firing with crew preservation, paid-vs-posted income, v7 save/load of every new field, walking bounds and rider sanity; the served `/build/city.wasm` matched the fresh Docker build (`d03289a4…`).

Current completed checks include Docker ReleaseSafe builds, passenger wait/capacity/abandonment accounting, save/load of in-progress waits, route-edit attribution, passenger/rider conservation, operator account identities, off-hours/timeout abandonment, kerbside stop validity, old/new movement comparisons, the slice-4 fleet and staffing batch (94 focused checks, 0 failures, plus a scalar-ABI panel contract and a served-asset identity check), and the slice-5 enforcement probe (0 failures: cure/cap/waiver/suspension/expiry/cancel/schema-v4 save-load/tamper rejection/passenger conservation, plus a served-WASM hash match). This environment has no browser and lacks WebGL, so report population is verified through the scalar ABI, served markup and served-asset hashes rather than a rendered screenshot.

Manual save/load, bounded history, fixed clearance fees, authored population and graph limits remain until their authorized slice changes them. Review-only regularity targets remain review-only by design; slice 5 added a separate delivered-bus-second remedy. Aggregate driver cohorts and fixed owned-fleet numbers were replaced in slice 4; `docs/operator-workforce-slice.md` lists what that model still abstracts. Each remaining slice must add its own verification evidence and limitations; do not claim later slices work merely because earlier hooks exist. Keep save/load compatible or bump and reject explicitly at each schema change.

## Numbered development sequence

The original numbering is retained so requests such as “work on slice 5” or “slices 5–9” are unambiguous. Slices 1–8 are complete. **Slice 9 is the authorized goal. Slices 10–39 remain proposed work, not authorization to implement them.**

1. **Agreement regularity targets — complete:** optional targets, overdue diagnostics and retained agreement results; no financial penalties.
2. **Save/load — complete:** versioned manual local files preserve towns, accounts, agreements, routes, observations and live journeys.
3. **Passenger service outcomes — complete:** real wait starts/boardings, capacity denials, abandonment causes, district comparison and save/load.
4. **Bus staffing and fleet investment — complete:** recruited day and night driver rosters, purchased and maintained owned buses, depot capacity, and shared dispatch and acceptance commitments. See `docs/operator-workforce-slice.md`.
5. **Transport contract enforcement — complete:** cure-first capped service credit, cash-floor waiver, route-change suspension, ledger kind 10, schema v4.
6. **Civic calendar and realistic routines — complete:** weekdays, shifts, weekends and a weekly budget period. See `docs/civic-calendar-slice.md`.
7. **Households and household budgets — complete:** shared income, essential expenses and financial pressure.
8. **Employment and hiring — complete:** vacancies, unemployment, skills, wages and business staffing. See `docs/employment-hiring-slice.md`.
9. **Housing and occupancy — authorized:** renting, ownership, affordability, moves and displacement.
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

If the next user asks to continue from this kickoff, carry slice 9 through implementation; slices 5, 6, 7 and 8 are complete. For each slice: inspect the actual code, write a short slice note, implement the bounded batch, run Docker ReleaseSafe build/startup, run focused simulation checks outside the repository, verify browser/report behavior where applicable, update documentation and refresh this kickoff before starting the next slice. Preserve existing work and do not stop at a plan. Do not add a permanent test suite or expand into slices 10–39 without authorization. Finish each slice with what changed, what was verified and remaining limitations.
