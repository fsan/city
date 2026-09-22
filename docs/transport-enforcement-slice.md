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

_Pending._
