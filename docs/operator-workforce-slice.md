# Bus staffing and fleet investment (slice 4)

Bounded plan: replace the fixed aggregate driver cohorts and owned-vehicle numbers with explicit operating commitments while preserving fares, boarding, passenger outcomes, route/stop behaviour, agreement payments, protected reserves, ledger categories, municipal funds and safe retirement.

## Intended rules

**Driver roster.** Each operator holds contracted day-qualified and night-qualified drivers and a lifetime wage/recruitment/severance record. Recruiting a day driver pays a training and onboarding fee from that operator's cash. Recruiting a night driver requires an existing day-qualified driver, who then takes the night endorsement; it does not create a new person. Dismissal pays severance and reduces the cohort. On-duty drivers keep the existing £0.12 per bus-second wage charged only while a bus is actually in service, so wage cash leaves the account exactly as it did before. Recruitment and severance are additional explicit outflows. A cohort is never filled for free.

**Fleet asset pool.** Each operator owns individual units up to a depot capacity. A unit records its condition (0–100), whether it is unavailable for maintenance, and which physical bus currently occupies it. Purchase changes cash and the pool only if cash and depot space allow. Sale returns a condition-scaled price and is refused while the unit is attached to a live or clearing bus. Condition falls only while the bus is in service; clearing earns nothing and causes no wear. An exhausted unit enters maintenance: a bounded duration and a charge, paid when it can be, otherwise the unit stays unavailable with an explicit unpaid state. Maintenance never creates cash or hidden debt.

**Dispatch and acceptance share the pool.** A line slot dispatches a specific free unit and keeps it attached while the bus clears, so clearing physically blocks replacement dispatch. Quotes and acceptance read the live owned/maintenance/committed split and the recruited cohorts. All-day service still needs both cohorts. The nominal cash buffer, clearance fee and price formula are unchanged.

**Refusals.** Distinct codes for: eligible; insufficient owned vehicles; price below cost and margin; invalid terms; insufficient drivers; working capital below the buffer; off-hours night-coverage gap; shortfall caused by units under maintenance; depot full; unit still committed to a live service.

**Retirement and depreciation.** Condition is the depreciation record; the resale price scales with it. A line that cannot dispatch because its operator is short of cash, drivers or serviceable units keeps running privately with the buses it still has and simply delivers less; it is not silently cancelled. Exhausted or unmaintained units are unavailable rather than free. A withdrawn line releases its units as its buses clear.

**Persistence.** Every new field is serialized and validated, with account identities recomputed from opening capital and explicit flows. The schema becomes `version: 3`, `rules: "bellwether-2026-09-v3"`; version 2 and older files are rejected explicitly with result 3. No migration layer.

## Verification required

Atomic purchase, recruitment, dismissal, sale and maintenance; refusals for cash, depot space, qualification, coverage, maintenance and commitment; cash exhaustion without negative balances; day and night shift coverage including off-hours; purchase/sale/maintenance lifecycle and wear; agreement acceptance and dispatch against shared capacity; safe handover with clearing buses; passenger conservation; ledger and operator account reconciliation; protected municipal reserves; unchanged route/stop and movement behaviour; save/load round trips of every new counter and an attached unit; browser and report behaviour. Docker ReleaseSafe build and startup; temporary focused scripts outside the repository; no permanent test suite.

## Implemented behaviour

`operators.zig` now holds, per operator, a depot capacity, a recruited day and
night roster and eight owned units. Each unit tracks its condition, whether it
is under maintenance, whether that repair is funded, its completion time and
which physical bus currently occupies it. The account keeps lifetime fares,
subsidies, agreement receipts, sales, purchases, recruitment, severance,
maintenance, vehicle, labour and slice-5 service-credit totals, so

    cash = opening + fares + subsidies + receipts + sales
         - purchases - recruitment - severance - maintenance - vehicle - labour
         - credits

holds for every operator at every step. A refused action never partly mutates
the account or the pool.

Recruitment and dismissal are explicit cash movements: a day driver costs £150
to train, a night endorsement costs £260, dismissal pays £60 severance, and
each decision needs a £60 float above its fee. A night endorsement requires a
day-qualified driver already on the roster; while the two cohorts are equal
there is no spare driver to endorse, which is a distinct refusal from cash.
On-duty drivers still earn the existing £0.12 per bus-second wage, and night
coverage remains `min(night, day)` so the authored 2/1/0 cohorts behave exactly
as before.

Fleet: a bus costs £520, is priced against the authored opening capital so the
first investment decision is reachable in a fresh town, and sells for 55% of
its condition-scaled value. A depots holds six, five or three units for the
three operators; the authored 4/3/2 starting pools are unchanged, so the
documented Bellwether capacity refusal still reproduces. Condition falls by
0.05 only while a bus is moving, dwelling or held in traffic. A unit that
reaches zero enters maintenance; a funded repair costs £160 and takes 240
simulation seconds, and an unfunded one stays unavailable until cash allows
instead of creating hidden debt.

Dispatch and acceptance share this pool. A line slot takes a specific free
unit; that unit stays attached while the bus clears, so a clearing bus
physically blocks replacement and can delay an accepted commitment. Quotes
refuse on distinct codes: 1 insufficient owned buses, 2 price, 3 terms,
4 drivers, 5 cash buffer, 6 off-hours coverage gap, 7 units under maintenance,
8 serviceable units committed elsewhere. `fleet_maintain` marks the occupying
bus for safe retirement first, so riders still alight at a stop.

## Verification — 22 September 2026

Docker Compose Zig 0.14.1 ReleaseSafe build, `make build` publication and
JavaScript syntax checks passed; temporary scripts live in `/tmp` and no
permanent test suite was added.

- `/tmp/city-slice4-check.mjs` exercised, against the published WASM: initial
  pool partition, account identities after purchase, sale, maintenance,
  recruitment, dismissal and funding; every refusal leaving cash and units
  untouched; resale scaling; the maintenance lifecycle from scheduling to
  restored condition and released depot slot; roster rules; shared-capacity
  acceptance; a subsidy-funded operator reaching the depot-full and
  qualification refusals; cash exhaustion with no negative balances; passenger
  conservation; finite rendering; and a save/load round trip.
- Save/load defect found and fixed during verification: `validate()` had lost
  the maintenance-duration term, so any town with a repair completing in the
  future was rejected as inconsistent. The bound is now
  `c.elapsed + operators.maintenance_seconds + 0.001`. Targeted probes confirm
  pristine, 45-second, just-scheduled, in-progress, completed-repair, purchase,
  recruitment and sale towns all round-trip with result 0.
- Save evidence: version 3 with the v3 rules tag and fleet-unit fields,
  byte-identical re-export (10,049,389 bytes at the sampled town), version 2
  rejected as incompatible (3), truncation reported malformed (2), an
  out-of-range unit condition rejected as inconsistent (4), a rejected import
  leaving the live town untouched, and render vertices finite across twelve
  samples (maximum 417,438).
- Final run: 94 checks, 0 failures. Operator cash stayed non-negative through
  exhaustion (£137.61, £0.00598 and £5.00) with every account identity intact;
  passenger conservation held at 27 riders in the sampled fleet; the funded
  operator reached a full depot (6/6) and a fully endorsed night roster before
  both were refused on their own codes.

## Remaining limits

Driver cohorts are per-operator totals, not named residents, and the daily wage
is the existing per-second labour charge rather than a separate payroll run.
Depots are a slot count with no physical yard geometry. Wear is uniform and
does not model mileage, part failures or vehicle age. Maintenance is one
bounded repair of fixed duration and cost. Bus prices are bounded design
constants, not a vehicle market. A bus under maintenance leaves its line
under-dispatched rather than being substituted from another operator.
Browser verification of the new Fleet & staff panel is recorded in
`README.md` and the refreshed kickoff.
