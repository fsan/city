# Employment and hiring (slice 8)

Bounded plan: replace the fixed round-robin employer assignment with explicit
vacancies, unemployment, skills, wage offers and bounded business staffing,
while preserving household budgets, transport, routines, operators and
municipal accounting. No regional trade, production inputs, business credit or
national labour market is added.

This note was written before the slice code, as the kickoff requires.

## Jobs and employers

Each employer keeps its existing building, capacity and operating cash. It adds:

- a posted wage per employee per day;
- a minimum skill requirement (0 general, 1 clerical, 2 professional);
- vacancies = capacity - employees;
- a wage-arrears total when daily wages cannot be paid in full;
- a bounded staffing-pressure measure used only for reporting and firing.

Residents get a deterministic skill 0-2 and an employment state. Hiring fills
vacancies only when the resident's skill meets the requirement; a mismatch is a
distinct refusal and never silently fills the post. Unemployed residents have
no employer link and therefore keep the existing safe walking/home fallback.

## Daily staffing

On each day rollover, bounded and in this order:

1. Employers pay the wages they can afford. Paid wages debit employer cash and
   credit the appropriate household balances; any unpaid amount is recorded as
   employer wage arrears, not hidden debt and never municipal debt.
2. Household income is recomputed from actually paid wages, so household
   spending and affordability respond to real staffing.
3. A bounded number of vacancies are filled from unemployed residents whose
   skills meet the requirement, preferring the closest home-to-work trip.
4. An employer that still carries wage arrears dismisses a bounded number of
   lower-skilled employees; dismissed residents become unemployed and their
   commute ends, which reduces transport demand through real transitions.

No money is created or destroyed: the sum of daily wages paid by employers
equals the sum credited to households, and employer cash never goes negative.

## Persistence

Every employer wage, skill requirement, vacancy, wage-arrears and staffing
field, and every resident skill/employment field, is serialized and validated.
The save schema becomes `version: 7`, `rules: "bellwether-2027-02-v7"`;
version 6 and older files are rejected explicitly with result 3. No migration
layer is added.

## Verified behaviour (Docker ReleaseSafe probe, 24 checks, 0 failures)

A temporary probe called `city.init()`, `game.init()`, then advanced real
30 Hz simulation steps. It confirmed: no skill mismatch or wage inconsistency
at init; jobseekers and open posts both exist; hiring on a day rollover fills
qualified vacancies (unemployment fell, employer totals equal the live links);
wage conservation (paid wages equal the sum credited to households); employer
cash floors (never negative); household balances do not vanish; a skill-0
resident is refused a skill-2 post; a drained employer with wage arrears sheds a
bounded number of staff and never goes negative; crew members are never
dismissed; paid wages never exceed posted income; the v7 snapshot declares
`"version":7`, round-trips, and preserves employment links and skills; walking
stays bounded and riders stay sane after further steps.

Observed probe figures: `unemployed=859 vacancies=1436 hires=47 on the first
rollover dismissals=2 wages=163715 arrears=0`.

## Remaining limits

One adult in eight starts out of work; posting wages are fixed authored values
(£40/£55/£70). Employers trade in a single simplified daily surplus, so a firm
survives unless taxes or cash actually exhaust it; there is no demand market,
business credit, regional trade or national labour market. Crew members and
workers on an active order can never be made redundant. Hiring is capped at 64
posts per day. Reports are verified through the scalar ABI, served markup and
the served-WASM identity rather than a rendered screenshot, because this
environment has no WebGL browser.

## Verification required

Vacancy filling, skill mismatch, wage payment conservation, employer cash
floors, wage arrears and firing, unemployment transitions, household income
reconciliation, routine/transport demand change, passenger conservation,
transport dispatch, save/load continuation of every new field and browser
reports. Docker ReleaseSafe build and served-asset identity; no permanent test
suite. Do not add regional trade, production inputs, business credit or
national labour markets.
