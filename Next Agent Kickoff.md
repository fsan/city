# Next agent kickoff — slice 19 (numbered item 11) complete in the worktree; item 12 is next

Continue Common Ground in /Users/fox/Documents/ChatGPT/city. Read this note before editing. Slices 1–18 and the dense-town/signals batches remain as recorded below; do not reset, rewrite history or push.

**Slice 19 (numbered item 11, physical building construction) is complete, built, probed and documented in the worktree; it is not committed.** The batch gives an approved private-development permit a physical construction path instead of the abstract item-10 timer:

- `src/simulation/development.zig` now measures road access and terrain slope across the proposed footprint, computes access, grading, foundation, material and labour costs, and gives each proposal a private construction budget. A site beyond the access limit or above the slope limit is refused.
- An approved job reserves one free four-person contractor crew. The crew uses the ordinary resident movement path and an existing work-order field (`work_order_base + application number`) outside the road-contract index range. The job phases are mobilising, delivering materials, building, blocked and complete.
- Materials are staged over the construction window and paid from the private budget as they arrive. Progress advances only in proportion to delivered materials. The municipal ledger still records only the levy as kind 12; there is no hidden municipal construction cost.
- Completion still redevelops the authored lot in place through the existing `housing.enroll` / `residents.addEmployer` paths. Refusals and blocks carry their own reason codes. A visible site/material marker and the amber crew colour make the job inspectable.
- Schema moves to **v14 / `bellwether-2027-12-v14`**; v13 and older files are rejected with result 3. Group 31 fields 0–19 are unchanged; fields 20–36 carry access, slope, access/grade/foundation/material/labour costs, private budget/spend, material requirement/delivery, contractor, crew, phase, blocked reason and progress. Group 0 fields 79–85 carry construction spend, material delivered, crew counts, blocked jobs and committed private budget.
- `web/planning.js` and `web/index.html` show access/terrain/cost estimates for open applications and phase, progress, materials and private spend for approved or completed jobs. `docs/physical-construction-slice.md` is the slice note.

**Verified.** The focused ReleaseSafe probe outside the repository reports `checks failed: 0`: the dense town remains 820 lots / 1,328 nodes / 1,624 roads with 10 vacant sites; the first application lands on parcel 29 with access 1, slope 0.000, a £416,000.00 private budget, a £17,308.80 estimate and 111.3 material units; granting it assigns company 5, a four-person crew and work order 1000001, moves the £1,300.00 levy as ledger kind 12 and starts £5,624.00 of private groundwork; all four crew arrive after 13,632 fixed steps; the dwelling completes in place with £17,619.39 private spend, 111.30/111.30 materials and progress 1.00; the v14 round trip returns 0 at 7,749,309 bytes with the built count and private spend preserved; a vacant lot moved beyond the access limit attracts no application; and a v13 file returns 3. Docker ReleaseSafe builds and `node --check` pass, and the served `/build/city.wasm` matches the published `/output/city.wasm` byte for byte during the final publication check. Independent Zig builds can carry different metadata, so publication is checked as served-versus-published rather than by comparing two independent build hashes.

**Limits.** Access, grading, foundation, material and labour costs are bounded policy numbers, not tendered or market prices. Construction crews are the existing contractor rosters; supplier firms, heavy equipment, foundation engineering, regional trade and parcel subdivision remain future work. The proposal ring remains 24 records, at most 8 pending and at most 2 new applications per day. Demand remains a structural ratio rather than a price model. The old slice-17 save-after-render defect remains a separate open issue.

**Authorized goal:** the user's "finish the next missing slice" authorized item 11, and that slice is now implemented, built, probed and documented in the worktree. No further slice is authorized. **Numbered item 12, property valuation and sunlight, is the next candidate**, but it must not start until the user names it. Confirm the numbering if the request says only "slice 12", because the traffic-signal note also uses that label. Each new slice still needs its own short note, Docker ReleaseSafe build, focused simulation checks, browser/report verification where applicable, documentation and a refreshed kickoff before the following slice starts.

Slice 19 is uncommitted. `git status` should show modified `src/main.zig`, `src/simulation/development.zig`, `src/simulation/game.zig`, `src/simulation/persistence.zig`, `src/render/scene.zig`, `web/data.js`, `web/index.html`, `web/planning.js`, `docs/abi.md`, `docs/city-planning.md`, `docs/development-proposals-slice.md`, `docs/README.md`, `Next Agent Kickoff.md`, and new `docs/physical-construction-slice.md`. Do not commit, reset, rewrite history or push without a request.

**Slice 18 is complete in the worktree (not yet committed).** It is the next
entry in the numbered list below — development proposals and permits, private
construction responding to zoning and demand. The inherited state had zoning
with no consequence: `docs/city-planning.md` recorded that automatic
development was not simulated, every authored vacant lot stayed vacant for the
whole session, and the parking pass had in fact converted all of them, so there
was no developable site anywhere in the town. Slice 18 adds a bounded private
development queue:

- `src/simulation/development.zig` (new) holds the proposal ring. A private
  developer reads the settled day once per rollover, measures each district's
  residents per dwelling and residents per commercial premises against the
  same ratio for the whole city, and lodges an application only where a
  district stands at or above 1.35x and still has a zoned vacant site. At most
  two applications a day, one undecided per district and eight pending in all.
  An application nobody answers lapses after five simulated days.
- Use follows the zone: residential proposes a home (an apartment at 2x
  pressure), commercial proposes a shop (an office at 2x), industrial proposes
  a works depot, mixed use takes whichever pressure is higher, and unzoned or
  civic-reserve land is never a site.
- **A proposal redevelops an authored vacant lot in place.** The lot keeps its
  identity, position, frontage, node, street and address number; only its use,
  height, value and capacity change and the parcel's `building` link is filled
  in. Nothing grows, so the snapshot, the renderer, the assessment roll and
  every report agree by construction. `housing.enroll` gives a completed
  dwelling the same rent and ownership formulas `housing.init` uses, and
  `residents.addEmployer` gives a completed workplace the same capacity, wage,
  skill and contractor rules `residents.init` derives from the same kind.
- Granting a permit takes `levy_rate` (0.0005) of the assessed value, rounded to
  pennies, into the municipal ledger as **kind 12** under the application's own
  one-based number. Construction is the applicant's own cost and takes two to
  six simulated days. Refusals and lapses move no money and carry their own
  reason codes.
- `seedParking` now reserves a deterministic share of each district's vacant
  lots, because the parking pass had taken every one of them and left the town
  with no developable land at all. The authored plan keeps 10 vacant sites
  across seven districts.
- Schema moves to **v13 / `bellwether-2027-11-v13`**; v12 and older are rejected
  with result 3. The validator checks the queue field by field, raises the
  ledger's kind ceiling to 12, and names the kind-12 party/order rule.
- ABI: **group 31** reads one application (0 number, 1 parcel, 2 building,
  3 district, 4 zone, 5 kind, 6 height, 7 value, 8 capacity, 9 levy,
  10 offered, 11 deadline, 12 decided, 13 complete, 14 decision, 15 reason,
  16 pressure, 17 ever lodged, 18 pending, 19 retained). **Group 0 fields
  70-78** are the running totals. **Group 16 field 7** is the pending
  application on that parcel. Commands `development_accept(id)` and
  `development_refuse(id)`. `web/planning.js` gains a Permits mode on P with a
  cell-reusing row builder that only reports back what Zig accepted.

See `docs/development-proposals-slice.md` for the rules, the measured table and
the limits. The limits are that construction is abstract (no crews, materials,
terrain grading or foundation costs — those are numbered item 11), a proposal
never redevelops an occupied lot, demand is a structural ratio rather than a
price model, and the levy is a flat share of assessed value with no tender.

**Verified.** A throwaway ReleaseSafe probe outside the repository reports
`checks failed: 0`: 820 lots of 900 storage, 1,328 nodes, 1,624 roads; ten
vacant sites and no eligible site until the player zones one; seven districts
holding a site with the busiest at 2.058x; the first application landing on the
engine's own chosen parcel with zone 1, a residential kind and a £1,300.00
levy; the cash delta and the ledger kind-12 delta both equal to that levy; a
completed dwelling enrolled at £117.00 rent and £57.20 ownership cost with its
parcel link filled; a completed office of capacity 95 appending company 295 to
296 with the employer link correct; refusal and lapse moving no money; no
application ever on zone 0 or 5; a v13 round trip returning 0 with count 9,
next_number 10, built 2, levies £2,500.00 and pending 3; staged round trips
returning 0 at init, offer, accept, built, refuse, lapse and shop; a v12 file
returning 3; and one further simulated day at 1,126 peak cars with 11
applications lodged. `make build` publishes a fresh `/output/city.wasm` whose
sha256 matches the served `/build/city.wasm` byte for byte
(`96618d92…`), and the served markup, `planning.js`, `data.js` and `reports.js`
carry the Permits panel, the permit commands, the decision labels and the new
ledger category.

**The slice 17 defect is still open.** Saving after the renderer has drawn a
frame still returns `load result=4` while saving immediately after `init`
returns 0, as recorded in `docs/dense-town-slice.md`. Slice 18 did not change
that path; it remains the first thing to chase when a later slice touches the
snapshot or the renderer.

**Authorized goal:** none is outstanding. Slice 18 (numbered item 10, development proposals and permits) was authorized by the user's "finish the next missing slice" and is now implemented, built, verified and documented in the worktree. No further slice is authorized until the user names one; the next candidate and the numbering conflict are recorded under the numbered development sequence below. Each new slice must have its own short slice note, Docker ReleaseSafe build, focused simulation checks, browser/report verification where applicable, documentation, and this kickoff refreshed before the following slice starts.

Slice 18 is uncommitted. `git status` shows modified `docs/abi.md`, `docs/city-planning.md`, `src/main.zig`, `src/scene/city.zig`, `src/simulation/{game,housing,persistence,residents}.zig`, `web/{data,index.html,main,planning,reports}.js`, and new `docs/development-proposals-slice.md` and `src/simulation/development.zig`. Do not commit, reset, rewrite history or push without a request.

Inspect current code, git status and recent commits before editing. The `.tmp_degrees.zig` cleanup item is done: the temporary file was removed in `60a000a`. Do not reset, rewrite history or push without a request.

## Read first

Start with `docs/development-roadmap.md`, then `docs/development-proposals-slice.md` (the most recent batch), `docs/dense-town-slice.md`, `docs/passenger-outcomes-slice.md`, `docs/save-load-slice.md`, `docs/regularity-target-slice.md` and `docs/stop-regularity-slice.md`.

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
- Manual save/load is local and browser-owned. The current schema is `version: 11`, `rules: "bellwether-2027-09-v11"` after slice 12. Version 10 and older files are rejected explicitly with result 3; there is no migration layer.
- Private development (slice 18): zoned vacant land attracts bounded permit applications driven by measured per-district demand; the player grants or refuses each one; a granted permit books a 0.0005 levy as ledger kind 12 and builds in place over 2–6 simulated days. Unzoned and civic-reserve land is never a site. Granting is `development_accept(id)`, refusing is `development_refuse(id)`, and P opens the Permits list. The authored plan keeps 10 vacant sites because `seedParking` now reserves a deterministic share of them.
- Save schema is now `version: 13`, `rules: "bellwether-2027-11-v13"` after slice 18. Version 12 and older files are rejected explicitly with result 3; there is still no migration layer.

## Completed work relevant to the recent slices

- **Regularity targets:** offers accept 0 or a whole 30–600 simulation seconds. Review is advisory and agreement-specific; no payment penalty. Retired/current stop records are bounded.
- **Save/load:** typed JSON snapshots preserve clock, speed, graph, routing tables, zoning, residents, journeys, riders, operators, vehicles, shifts, taxes, ledger, reserves, orders, crews, routes, observations, agreements, targets, history, next IDs, and every slice-4 fleet unit, roster count and lifetime flow. Parsing is bounded and staged; invalid imports leave the live town unchanged.
- **Passenger outcomes:** Zig records actual wait starts, boardings, completed wait statistics, capacity denials, timeout/off-hours/fare/service abandonment and district comparison. Route edits close old-version waits before archiving. Save version 3 preserves every new counter and in-progress wait.
- **Transport polish:** stop validity and kerbside markers are in `city.zig`, `render/scene.zig`, `main.zig` and `web/transport.js`. Movement smoothing is in `transport.zig`; the measured old/new comparison showed per-step skips falling from 79 to 4 and mean moving speed rising from 1.54 to 2.73 m/s.
- **Civic calendar and realistic routines (slice 6):** bounded weekday/weekend calendar, day/evening/night resident shifts, routine phases and local errands, weekly municipal budget periods from ledger movements only, schema version 5. See `docs/civic-calendar-slice.md`.
- **Transport contract enforcement (slice 5):** cure-first service credit on delivered bus-seconds only; 480-second cure, GBP 0.18 per missing bus-second, 25% price cap, GBP 2.18 cash floor with waiver instead of debt, route/service-change suspension, ledger kind 10. See `docs/transport-enforcement-slice.md`.
- **Housing and occupancy (slice 9):** one housing unit per authored home with tenure, rent or ownership cost, a property-owner reserve, explicit arrears, occupancy, a move state and an application target; a bounded daily rollover moves or displaces households into a cheaper, shorter-commute vacant unit and residents walk to the new address. Schema v8. See `docs/housing-occupancy-slice.md`.
- **Street types, parking and learned travel (slice 10):** per-segment street class, proportional free-flow speeds, signal and crosswalk compliance for walkers and cyclists, seeded bicycle and car parking with hard slot counts and banded kerbside prices (municipal ledger kind 11), expectation-based parking choice, and a tiny per-resident learned trip-time and parking-availability model. Schema v9. See `docs/street-types-parking-learning-slice.md`.
- **Traffic signals and crosswalks:** player-placed per-junction signals with one branch green at a time, set-back heads, click-to-edit green and amber in simulation seconds, and placement snapping from the traffic panel. Schema v10. See `docs/traffic-signals-slice.md`.
- **Traffic signals, part two:** per-light off time, a three-position flashing-yellow switch with a daily window, a coordination map with per-link delays, bulk edits scoped to every light / one street / one junction, and a dispatcher hook for police and fire preemption. Schema v11. See `docs/traffic-signals-slice.md`.
- **Development proposals and permits (slice 18, numbered item 10):** a bounded private development queue in `src/simulation/development.zig` driven by measured per-district demand over zoned vacant land; player grant/refuse; a 0.0005 levy booked as ledger kind 12; in-place redevelopment over 2-6 simulated days that enrols a dwelling or appends an employer; the parking pass now reserves a share of each district's vacant lots. ABI group 31 plus group 0 fields 70-78 and group 16 field 7; commands `development_accept`/`development_refuse`; P opens the Permits panel. Schema v13. See `docs/development-proposals-slice.md`.
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

Complete and committed at `fd1a3a4`. `docs/housing-occupancy-slice.md`
records the rules, verification and limits. Every authored home is one housing
unit with tenure, rent or ownership cost, a property-owner reserve, explicit
arrears, occupancy, a move state and an application target. A bounded daily
rollover can move or displace households into a cheaper, shorter-commute vacant
unit; residents walk to the new address. Save schema is version 8,
`bellwether-2027-03-v8`.

## Completed slice 10 — street types, parking and learned travel

Complete and committed at `fd1a3a4`. `docs/street-types-parking-learning-slice.md`
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
- Save schema is version 11, `bellwether-2027-09-v11` after the second
  traffic-signal batch; version 10 and older are rejected with result 3. A
  22-road expanded graph still fits the 16 MiB cap. The traffic-signal batches
  serialise player-placed signals, their per-light timing, flash windows and
  coordination links alongside it.

## Completed slice 11 — traffic signals and crosswalks

Complete and committed at `935cfb6`. `docs/traffic-signals-slice.md` records
the implemented rules, verification and limits. This batch replaced the old
global horizontal/vertical light model:

- Each signalised junction holds one record: its node, its incident arms, a
  green duration, an amber duration, a phase offset and whether it is active.
  Every incident arm is its own phase, so exactly one branch is green at a time;
  a junction with no record is uncontrolled and never gated.
- Signal heads are drawn 3.4 m along their own arm and 2.6 m across it, and
  crosswalk stripes are set back 3.6 m from the junction, so nothing sits on the
  corner.
- The traffic panel arms a placement tool; a click snaps to the nearest junction
  arm within 9 m (signal) or street segment within 9 m (crosswalk). A crosswalk
  also signalises a junction end whose degree is 3 or more.
- Clicking a placed light selects it and shows its junction, arm, current phase,
  arm count, green, amber, full cycle and time until that branch changes;
  `signal_set_green` and `signal_set_yellow` clamp to 0.5–60 s and 0.5–10 s and
  write back through the ABI.
- Walkers and cyclists wait at a marked crossing unless a parallel arm holds
  green; unmarked crossings keep the existing gap-based rule.
- Placed signals are serialised and validated (junction count, node bounds, arm
  count, green and amber bounds, phase offset and each arm's road identity).
  Schema moved to v10 / `bellwether-2027-05-v10`; loading clears any selected
  head.

## Completed slice 12 — traffic signals, part two

Complete and committed at `92d1846`. `docs/traffic-signals-slice.md` records the
implemented rules, verification and limits.

- A junction now holds an all-red "off" time as well as green and amber, so a
  phase is green, amber, then a short clearance. Off time clamps to 0–6 s, amber
  to 0.5–10 s and green to 0.5–60 s; `signal_set_red` returns the applied value
  or -1 when the junction has no signal.
- A junction can blink yellow instead of cycling. The manual switch has three
  positions (forced on, follow the daily window, forced onto the normal cycle).
  `signal_flash_manual(node, mode)` sets one light and
  `signal_flash_bulk(scope, key, mode)` sets a whole street, one junction or
  every light. A forced setting beats the window; an emergency preemption beats
  both. While blinking, every approach may go slowly and yielding, and
  pedestrians and cyclists keep priority.
- The daily window is a start and end hour of the simulation day; a start later
  than the end runs overnight. `signal_set_flash_schedule(node, start, end,
  enabled)` stores it and turns it on.
- `signal_link(from, to, delay)` makes the follower run its leader's cycle held
  back by that many simulation seconds and joins them into one coordination
  group; `signal_unlink` reverses it. Group 30 exposes each link and the
  traffic-lights tab draws them with the delay labelled.
- The traffic-lights tab lists every signalised junction and applies one property
  across a scope through `signal_apply_bulk(scope, key, field, value)` (green,
  amber, off time, the two window hours, the window switch and the manual flash
  mode).
- `signal_alert(node, kind, seconds)` is the dispatcher hook: kind 1 holds the
  cross traffic, 2 opens on flashing yellow, 3 releases back to the normal
  cycle. Police and firefighters are not simulated, so today the player's own
  controls raise the alerts.
- Clicking a light on the map opens the traffic drawer before showing the
  inspector, and the drawer and works panel scroll only their own window body so
  a light click no longer drags the map. Schema moved to v11 /
  `bellwether-2027-09-v11`; version 10 and older are rejected with result 3.

## Completed slice 13 - work routines and signal control

Complete in the worktree (not yet committed). `docs/routines-signals-slice.md`
records the rules, verification and limits. Two reported faults were fixed:

- **The four lamps were unreadable and jams were constant.** The gate tested the
  arm a driver was *turning into* instead of the arm they were standing on, so a
  green lamp held the queue beside it while traffic from elsewhere was admitted.
  `signals.greenForApproach` now tests the approach road, and `entryAllowed` /
  `enter` carry that road through from the movement loop. One arm is still green
  at a time.
- **Cars appeared to stop past the light.** The brake point was 1.0 m short of
  the node while the head is drawn `signals.head_setback` (3.4 m) down the arm.
  The stop point is now the head setback, so queues stand before their light.
- **The streets emptied after the first day.** `departureLead` stepped its target
  forward until it was strictly later than now, so a resident at home during
  their own shift waited for *tomorrow's* shift start and never left. It now
  returns zero when the governing window is already running.
- **Working hours belong to the workplace.** `calendar.zig` gained a bounded
  `Facility` schedule table (`inSchedule`, `facilityWindow`, `onFacilityShift`):
  office 09:00-17:00, hall 08:30-17:30, shop 09:00-17:00 or 12:00-20:00, clinic
  07:00-15:00 / 09:00-17:00 / 14:00-22:00, depot 06:00-14:00 / 14:00-22:00 /
  22:00-06:00. A resident's existing `shift` byte picks the slot, so no new
  persistent field and no schema bump; the save contract stays version 11.

Measured with a headless probe stepping 1/30 s and sampling hourly for eight
simulated days. Peak people moving / active cars per day, before and after:

| day | before | after |
|-----|--------|-------|
| 0 | 2864 / 363 | 2864 / 363 |
| 1 | 1528 / 235 | 2218 / 144 |
| 2 | 283 / 68 | 2193 / 100 |
| 3 | 228 / 17 | 2214 / 84 |
| 4 | 227 / 3 | 2258 / 57 |
| 5 | 124 / 2 | 2264 / 46 |
| 6 | 41 / 0 | 2303 / 51 |
| 7 | 245 / 4 | 2346 / 48 |

Before, active cars hit zero on day 3 and stayed there; after, cars run every day
and roughly 2,200 people move at the peak. Traces are kept outside the repository
at `/tmp/city_probe/BASELINE-trace.txt` and `/tmp/city_probe/after.txt`.

## Completed slice 14 - river and the Rome-inspired seeded town

Complete and committed (the bus-speed follow-up is the head commit on top of the
seeded-town commit). This batch is labelled slice 14 because the previous
agent had already used the label slice 13 for the work-routines batch.
`docs/river-rome-layout-slice.md`
records the rules, verification and limits.

The first attempt at this slice made the car share *smaller*, not larger. The
fault was in the plan, not the travel constants: `chain()` connected only
consecutive samples of the same street run, so cross streets passed over the
arterials without forming junctions and the river trim cut every run in two.
The inherited tree measured 492 nodes in 18 disconnected components with
213,806 of 241,572 node pairs unreachable, and 2,899 of 3,240 commuters had no
home-to-work route at all. Residents could not drive or ride anywhere, so they
walked locally and the buses carried nobody.

- `resolveJunctions()` turns every true segment crossing into one shared
  junction node and `linkFragments()` gives any leftover fragment one bounded
  link, so the seeded plan is a single component. `crossing` and `splitAtNode`
  are the new helpers.
- The town is 1,320 x 1,040 m with 288 buildings and the same 3,840 adults, so
  outer districts sit 600-1,000 m from the centre.
- `src/scene/river.zig` owns the authored centreline, half-width, bed depth and
  per-point level and discharge, with `flow_factor` reserved for the future
  weather-driven water model. Nothing reads the flow yet; the only effect today
  is impassability and the four seeded bridges.
- The renderer draws the water surface as its own geometry and samples the
  channel inside the ground grid and road ribbons near the river, so the carve
  is not aliased away between tile corners.
- Motoring costs `0.002 x distance + 0.20` per trip, ownership charges a daily
  cost of 12 so only a genuinely distant commute pays for a car, the
  car-owning tie-break falls from 18% to 6%, and bicycle and car park supply is
  scaled to the new area (44 -> 132 and 16 -> 40).
- Schema moves to v12 / `bellwether-2027-10-v12`; v11 and older are rejected.

Measured with a headless probe stepping 1/30 s over eight simulated days
(`/tmp/cityprobe4`). Morning-peak car trips per day, before this slice and
after:

| day | baseline car | after car | after walk | after bike | after bus |
|-----|--------------|-----------|------------|------------|-----------|
| 0 | 363 | 1379 | 68 | 1257 | 5 |
| 1 | 144 | 966 | 586 | 874 | 7 |
| 3 | 84 | 737 | 1032 | 700 | 15 |
| 5 | 46 | 504 | 1211 | 692 | 17 |
| 7 | 48 | 366 | 1400 | 579 | 15 |

Peak car 1,463, peak bicycle 1,617, peak bus 22. Distance decides the mode:
walking and cycling own trips under 400 m and beyond 600 m the car takes
85-93% of them, which is the requested behaviour. Car ownership settles at
1,572 of 3,812 adults and is stable from day 1 with no household below the
cash reserve. The graph has one component, zero unreachable pairs, zero water
nodes and zero water buildings, and both seeded bus lines stay active with 16
valid stops.

A bus now takes the street's own class speed less a small load penalty instead
of the flat `bus_limit` of 5.5 m/s; the old constant let a car do 9.8 m/s on an
avenue while a bus did 5.5, so no trip could ever be won by the bus. That
change roughly doubled the bus share.

Known limit: the bus still carries only single figures to low double figures.
This is structural. With a town about 1.3 km across, free-flowing traffic and
41% car ownership, a bus loses on time to both the car (170 s against 438 s for
a 1 km trip) and, under 600 m, to the bicycle. Closing the gap needs a larger
city (`max_nodes` is at 569 of 640), real congestion, or a bus-priority
measure; the model is left honest rather than tuned to a target share. The
renderer draws the water and samples the carve, verified by build and geometry
inspection only because this environment has no browser.

## Superseded slice 9 plan text (historical)

This slice follows slice 8. It adds renting, ownership, affordability, moves and displacement on top of the household and employment models.

- Define housing units, occupancy, rent/ownership costs, affordability thresholds, moves, vacancies and displacement.
- Households may move or be displaced based on affordability, employment/commute changes or housing availability. Moves must use actual resident transitions, not teleportation.
- Housing costs interact with household budgets, wages, municipal taxes/benefits and transport access. No silent money creation or unexplained occupancy changes.
- Property ownership, rent collection and municipal assessments must reconcile with the existing ledger, arrears and building data.
- Save/load must preserve housing units, tenure, occupancy, rents, arrears, applications and move state.
- Verification must cover moves, displacement, affordability, vacancy, rent/income conservation, tax/ledger reconciliation, commuting/transport effects, passenger conservation, save/load and reports.

Do not add physical building construction, property development permits, valuation/sunlight modelling, parks or demolition here; those are later slices.

## Code map and cautions

- `src/simulation/operators.zig`: independent accounts, day/night cohorts, service-window integrals. Slice 4 replaced the fixed cohort/asset numbers here with recruited rosters and owned units; see `docs/operator-workforce-slice.md`.
- `src/simulation/transport.zig`: physical fleet, original bus ownership, clearance, drivers, fares/costs, delivered seconds, dispatch blockers and service-state counts. Keep it independent of finance/residents except through explicit interfaces. Movement smoothing lives here; do not reintroduce per-segment hard brakes.
- `src/simulation/agreements.zig`: quote/acceptance, settlement, window-aware targets, history. Slice 5 defined enforcement without silently changing slices 1–4 payment semantics; see `docs/transport-enforcement-slice.md`.
- `src/simulation/residents.zig`: actual boarding/alighting, walking fallback, passenger wait transitions and district outcomes. Slices 6–12 extended routines, households, employment, housing, parking and learned travel here or in adjacent modules (`calendar.zig`, `households.zig`, `employment.zig`, `housing.zig`, `parking.zig`, `travel.zig`, `signals.zig`). Do not change boarding order without an explicit request.
- `src/simulation/persistence.zig`: explicit typed JSON snapshot, bounded validation/commit. Every persistent field added since slice 4 is represented and validated, and the identifier is bumped and older files rejected at each change; the current contract is v11.
- `src/main.zig`: validated exports and scalar ABI. Preserve field numbers. Existing groups include 10 fields 32–40, 13/17 agreement fields, 14 operator accounts/drivers, 18/19 stop/passenger observations, 20/21 agreement stop results and group 22 district passenger outcomes.
- `src/scene/city.zig`: `validStop`, `stopPoint`, `sidewalk`, graph/routing data.
- `src/simulation/development.zig`: the bounded private development queue — measured demand, site search over zoned vacant lots, lodging, lapse, the permit decision, the levy and in-place construction. `construct` is the only place a lot's use changes; there is no cached per-kind table to refresh.
- `web/planning.js`: roads, zoning and now the Permits mode. The permit buttons only report back what Zig accepted.
- `src/render/scene.zig`: kerbside stop markers drawn for all active lines; selected lines add a larger highlight. Keep finite vertex output.
- `web/transport.js`: routes/map gestures, stop-address filtering, kerbside projections, passenger and stop reports. `web/agreements.js`: quotes, accounts, coverage, current/closed delivery. `web/reports.js`: municipal ledger. `web/index.html` owns the report controls.
- `Makefile`, `docker/watch.sh`: build the WASM with disposable local/global Zig caches. Verify the served `/build/city.wasm` hash or behavior after a rebuild; a failed build retains the last good artifact.

Never iterate the large resident array by value; it previously exhausted the WASM stack. Read through scalar ABI, not inferred struct layouts. Existing operator totals retain sub-penny operating accrual; municipal transactions and policy fares/subsidies round at penny boundaries.

## Verification and remaining limits

Slice 8's probe (24 checks, 0 failures) covered init skill/wage consistency, jobseekers and vacancies, hiring on a rollover, unemployment transition, employer totals against live links, wage conservation, employer cash floors, household balance conservation, skill-mismatch refusal, arrears and firing with crew preservation, paid-vs-posted income, v7 save/load of every new field, walking bounds and rider sanity; the served `/build/city.wasm` matched the fresh Docker build (`d03289a4…`).

Slices 9–12 each passed a Docker Compose Zig 0.14.1 ReleaseSafe build and startup with a JavaScript syntax check and a focused simulation probe run outside the repository: slice 9 covered housing moves, displacement, affordability and rent/arrears conservation; slice 10 street classes, parking slots, banded fees and learned mode choice; slice 11 one-branch-green-at-a-time across 29 junctions, head setback and pedestrians waiting at marked crossings; slice 12 manual flashing, the daily window, emergency alerts, bulk edits, coordination links and the v11 save round trip. Where a slice changed the browser panel, verification used served markup, a module parse, a scalar-ABI contract and served-WASM identity instead of a rendered screenshot, because this environment has no browser and lacks WebGL.

Slice 18's probe (0 failures) covered the authored-town baseline, the empty eligible-site set before zoning, per-district demand, lodgement on the engine's own chosen site, the levy against both cash and the kind-12 ledger entry, refusal and lapse with no money moved, a completed dwelling and a completed workplace, the zoning rule that unzoned and civic land never attracts an application, a v13 round trip, staged round trips at seven points, a v12 file rejected with result 3, and a further simulated day at 1,126 peak cars. The served `/build/city.wasm` sha256 matched the freshly built `/output/city.wasm` byte for byte, and the Permits panel was verified through served markup, the served modules and `node --check`.

Current completed checks include Docker ReleaseSafe builds, passenger wait/capacity/abandonment accounting, save/load of in-progress waits, route-edit attribution, passenger/rider conservation, operator account identities, off-hours/timeout abandonment, kerbside stop validity, old/new movement comparisons, the slice-4 fleet and staffing batch (94 focused checks, 0 failures, plus a scalar-ABI panel contract and a served-asset identity check), and the slice-5 enforcement probe (0 failures: cure/cap/waiver/suspension/expiry/cancel/schema-v4 save-load/tamper rejection/passenger conservation, plus a served-WASM hash match). This environment has no browser and lacks WebGL, so report population is verified through the scalar ABI, served markup and served-asset hashes rather than a rendered screenshot.

Manual save/load, bounded history, fixed clearance fees, authored population and graph limits remain until their authorized slice changes them. Review-only regularity targets remain review-only by design; slice 5 added a separate delivered-bus-second remedy. Aggregate driver cohorts and fixed owned-fleet numbers were replaced in slice 4; `docs/operator-workforce-slice.md` lists what that model still abstracts. Each remaining slice must add its own verification evidence and limitations; do not claim later slices work merely because earlier hooks exist. Keep save/load compatible or bump and reject explicitly at each schema change.

## Numbered development sequence

The numbers below keep the original order so requests such as “work on slice 5” stay unambiguous, but later batches were inserted outside that order. The most recent batch, work routines and signal control, is labelled slice 13 in its own note and is not part of this list either. **Slices 1–9 of this list are complete and committed.** Two further batches are also complete and committed but are not part of this numbering: street types, parking and learned travel (committed at `fd1a3a4` alongside slice 9) and the two traffic-signal batches, which `docs/traffic-signals-slice.md` labels slices 11 and 12. Because of those insertions the roadmap and this list disagree: `docs/development-roadmap.md` numbers street types as 10 and then prints “11” twice, while this list keeps 10 as development proposals. Treat a “slice” request as ambiguous until the user says whether they mean this list's number or a label from a slice note. **Items 10–39 remain proposed work, not authorization to implement them. Nothing is authorized right now, so the next slice is the user's to name.**

1. **Agreement regularity targets — complete:** optional targets, overdue diagnostics and retained agreement results; no financial penalties.
2. **Save/load — complete:** versioned manual local files preserve towns, accounts, agreements, routes, observations and live journeys.
3. **Passenger service outcomes — complete:** real wait starts/boardings, capacity denials, abandonment causes, district comparison and save/load.
4. **Bus staffing and fleet investment — complete:** recruited day and night driver rosters, purchased and maintained owned buses, depot capacity, and shared dispatch and acceptance commitments. See `docs/operator-workforce-slice.md`.
5. **Transport contract enforcement — complete:** cure-first capped service credit, cash-floor waiver, route-change suspension, ledger kind 10, schema v4.
6. **Civic calendar and realistic routines — complete:** weekdays, shifts, weekends and a weekly budget period. See `docs/civic-calendar-slice.md`.
7. **Households and household budgets — complete:** shared income, essential expenses and financial pressure.
8. **Employment and hiring — complete:** vacancies, unemployment, skills, wages and business staffing. See `docs/employment-hiring-slice.md`.
9. **Housing and occupancy — complete:** renting, ownership, affordability, moves and displacement. See `docs/housing-occupancy-slice.md`.
10. **Development proposals and permits — complete:** private construction responding to zoning and demand. See `docs/development-proposals-slice.md`. Item 11 is now the next entry in this list, but the user names the next slice.
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

Slices 1–14 are committed, the slice 15/16 dense-town batch and the slice 17 repair are committed, and slice 18 (numbered item 10) is complete, verified and documented in the uncommitted worktree. This kickoff authorizes no new slice by itself. If the user names the next slice, confirm which numbering they mean when the request is ambiguous, then for that slice: inspect the actual code, write a short slice note, implement the bounded batch, run Docker ReleaseSafe build/startup, run focused simulation checks outside the repository, verify browser/report behavior where applicable, update documentation and refresh this kickoff before starting the following slice. Preserve existing work and do not stop at a plan. Do not add a permanent test suite or expand into the proposed sequence without authorization. Finish each slice with what changed, what was verified and remaining limitations.

## Historical state before slice 19

### Historical pre-slice-19 kickoff

Continue Common Ground in /Users/fox/Documents/ChatGPT/city. Slices 1–3 are complete and committed at `704a918`; slice 4 at `60a000a`; slice 5 at `4e29f2f`; slice 6 at `cfa432d`; slice 7 at `dcc2577`; slice 8 at `e71fa0b`. Slices 9 (housing and occupancy) and 10 (street types, parking and learned travel) are complete and committed at `fd1a3a4`. Two further batches are also committed: player-placed traffic signals and crosswalks at `935cfb6`, and per-light timing, flashing yellow, coordination and bulk editing at `92d1846`; their own note labels those two batches slices 11 and 12. The worktree is clean, so nothing is left to commit before the next slice. Those batches added optional agreement regularity targets, manual local save/load, measured passenger service outcomes, kerbside bus-stop placement/markers, smoother inter-segment vehicle movement, explicit bus fleet and staffing commitments, and cure-first transport contract enforcement.

**Slice 17 is complete and committed.** The committed dense-town batch
(slice 15/16, commit `56f948c`) built and rendered but was internally
inconsistent: the street wall placed 391 of its 820 target lots, only 7 of 12
park anchors found a clear rectangle, Garden Ward had no green space, and
`persistence.load` returned 4 for its own freshly written v12 file. Slice 17
repairs and completes it — measured street-wall calibration, a per-district
park search, deck heights registered before their nodes and refreshed by
`city.refreshElevations`, no duplicate graph edges, and the snapshot validator
using `city.isHome` so apartments round-trip. See
`docs/dense-town-slice.md` for the rules, the measured table and the limits,
including the one open defect: saving *after* the renderer has drawn a frame
still returns 4, while saving immediately after `init` returns 0.
