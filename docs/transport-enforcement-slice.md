# Transport contract enforcement (slice 5)

Bounded plan: add an explicit, reproducible consequence for persistent
under-delivery on an agreed service, without changing how agreements are
priced, reserved or paid for work actually delivered, and without turning the
review-only regularity targets from slices 1–3 into penalties.

This note is written before the code, as the kickoff requires.

## What is enforceable, and from what evidence

Exactly one contractual outcome is enforceable: **delivered bus-seconds against
the windowed target integral**. That is the same figure that already earns
payment, computed from real movement and scheduled dwell of the contracted
operator on the contracted route inside the agreed hours, prorated on the final
step and clipped at expiry. It is the only measurement this slice can move
money with.

Everything else stays diagnostic:

- Interarrival regularity targets remain review-only. A missed stop interval,
  a suspended target after a route edit, an off-hours gap and an
  unobserved stop can never produce a charge. The report says so explicitly.
- Route, window or operator mismatch permanently suspends *target review* as
  before. It does not create an enforceable failure, and it does not extend or
  restart the agreement clock.
- Cancellation, expiry and line withdrawal close the record with the existing
  semantics. Cancellation continues to settle earned pennies exactly once and
  release the remainder; it is not a penalty.

## Remedy: a capped, cure-first service credit

A shortfall becomes enforceable only after a cure period, and the remedy is a
public service credit rather than a retrospective fine.

- **Breach**: measured `delivered < 0.85 × expected` to date, with at least one
  whole day of expected service elapsed. Expected is the same windowed target
  integral already shown in the report.
- **Cure**: the first time a breach is observed, a cure window of one whole day
  (480 simulation seconds) opens. While curing, no credit accrues and the
  report shows the remaining cure time and the evidence.
- **Accrual**: after the cure window ends with the shortfall still present,
  each fixed step accrues `(expected_delta − delivered_delta) × £0.18`, the same
  rate as the operator's own vehicle and labour cost. The credit is a refund of
  service the public paid to have run and did not receive.
- **Cap**: accrual stops at 25% of the agreement price. The remedy can never
  approach the value of the contract, and it can never exceed what the
  agreement could have paid.
- **Cash floor**: the credit is payable only from the operator's own cash above
  the existing £2.18 dispatch floor, in whole pennies, in one transaction.
  Anything unpaid because the operator has no cash is recorded as **waived**
  with the amount and the reason. A waiver is not debt, not a receivable, and
  never negative cash.
- **Ledger**: a new explicit municipal ledger category, kind 10, records money
  actually received, with party = operator and order = agreement number. The
  report reconciles accrued = paid + waived + outstanding.

## Cancellation right

If the cure window has expired and the breach still holds, the report states
that the municipality may cancel the agreement at any time using the ordinary
cancellation semantics. Nothing auto-cancels: there is no adjudication, no
discretionary ruling and no automatic termination. This is a stated right, not
an action.

## Boundaries this slice does not cross

No court or legal system, no discretionary adjudication, no policing or courts
content, no change to the price formula, the cash buffer, the clearance fee,
the reserve behaviour or the earned-payment formula. Regularity targets remain
advisory. No remedy can create negative operator cash or hidden municipal debt.

## Persistence

Every new obligation and settlement field is serialized and validated: breach
start, cure deadline, accrued credit, paid credit, waived credit, breach
counter and enforcement state. The schema becomes `version: 4`,
`rules: "bellwether-2026-10-v4"`; version 3 and older files are rejected
explicitly with result 3. No migration layer.

## Verification required

Evidence boundaries (breach only from delivered seconds, never from regularity
or off-hours), cure expiry, expiry and closure behaviour, route changes,
paused operation, simultaneous arrivals, atomic rejection, the operator cash
floor and waiver reporting, ledger and account reconciliation, protected
municipal reserves, passenger conservation, and save/load continuation of every
new field.

## Implementation record

Implemented in `src/simulation/agreements.zig`, `src/simulation/persistence.zig`,
`src/main.zig`, `web/agreements.js`, `web/reports.js` and `web/index.html`.

The enforceable figure is the same windowed integral that earns payment:
`operators.hours(window, start, end) * fleet` compared with the line's measured
delivered bus-seconds. Regularity totals, gap states, off-hours periods,
route-version mismatches and unobserved stops cannot move money.

`enforce()` opens a 480-simulation-second cure the first time
`expected >= 480` and `delivered < 0.85 * expected`. While the cure is open the
settled integrals track the live figures and no credit accrues. After the cure,
each measured step adds `max(0, expected_delta - delivered_delta) * 0.18` to
`credit_accrued`, capped at 25% of the agreement price. Accrual stays unrounded
and is rounded only when collected, so sub-penny steps cannot inflate the
remedy.

`collectCredit()` pays from the operator's own cash above the existing £2.18
dispatch floor, in whole pennies and in one transaction. The payment debits the
operator account, increments its lifetime `credits` total, and records
municipal ledger kind 10 with `party = operator` and `order = agreement number`.
Any unpaid remainder is recorded as waived; it is not a receivable, never
becomes negative cash and never creates hidden municipal debt.

A route, window or operator change permanently suspends enforcement for that
agreement, clearing any open breach without charge; previously collected credit
is retained and settled at closure. Cancellation, expiry and line withdrawal
keep their existing settlement semantics and are not penalties. Expiry during
an open cure closes as a cure state without a charge; expiry after a settled
breach closes as a breached record.

Persistence is schema `version: 4`, `rules: "bellwether-2026-10-v4"`. Version 3
and older files are rejected with result 3. Every new field is bounded and
validated, the operator identity subtracts `credits`, retained kind-10 ledger
entries must match an agreement's paid credit, and an over-cap credit field is
rejected as inconsistent.

## Verification — 22 September 2026

Docker Compose Zig 0.14.1 ReleaseSafe build passed and the served
`/build/city.wasm` hash matched the build volume byte-for-byte
(`4ee8a7651f7d4225f1457379faff52b0a0b2729071a53e5adcc6e07858371c3a`).
JavaScript syntax checks passed for the changed report modules. No permanent
test suite was added.

A temporary native Zig probe (`src/slice5_probe.zig`, deleted before commit)
drove the published rules directly and passed with 0 failures. It covered:

- initial zero credit state and no enforcement on empty records;
- offer publication below the operator minimum, with atomic cancellation of the reserved offer;
- pre-breach grace below one whole day of expected service;
- first-breach cure opening, a full 480-second cure with no accrual, and the exact cure deadline;
- post-cure accrual at £0.18 per missing bus-second, penny settlement, the 25% cap and cap stability;
- operator cash debit, lifetime `credits`, the account identity including credits, and municipal receipts reconciling to credit paid;
- ledger kind 10 `(party = operator, order = agreement number)`;
- the £2.18 cash floor: unpaid credit waived, zero paid, zero outstanding, cash never negative;
- route-version change suspending enforcement with no charge and no later accrual;
- off-hours adding no target, expiry releasing the reserve and settling the price, and cancellation retaining settled credit;
- schema v4 save/load preserving accrued/paid/waived credit and operator credits, over-cap credit rejected as inconsistent (4), and version 3 rejected as incompatible (3);
- passenger conservation, non-negative operator cash and protected reserves across 600 live simulation steps.

The probe also caught and fixed a measurement-share defect: `measure()` is now
called once per update, so the last-step share is applied once instead of being
squared across two calls. Payment and enforcement therefore read the same
integral.

## Remaining limits

The remedy is a single capped service credit; there is no adjudication, dispute
register, cure extension, replacement-service obligation, escrow or automatic
cancellation. `breach_days` is an accrual-observation counter, not a calendar
day count. Waived credit is final and is not retried if the operator later has
cash. The last 1,024 ledger entries are retained, so per-agreement
reconciliation is complete only while those records remain; older paid credit is
verified through the agreement and account totals. Municipal budget text labels
`collected` as taxes, so service-credit receipts are reconciled through the
ledger and the operator report rather than that figure. No court, legal,
policing or courts slice was added.
