# Households and household budgets (slice 7)

Bounded plan: replace individual placeholder wallets with a bounded shared
household budget while preserving transport, employment, agreement and
municipal accounting behaviour. No banking, credit, retail purchasing or
housing market is added in this slice.

This note is written before the slice code, as the kickoff requires.

## Household model

Each home building is one household. Residents living in the same home share:

- a household balance, which is the sum of its members' starting wallets;
- a household daily income, the sum of employed members' income;
- essential daily expenses (food, utilities and a housing-placeholder charge);
- discretionary spending, which remains the existing travel, car-running and
  fare spending;
- an arrears balance when essential expenses cannot be paid in full.

Essential expenses are explicit and bounded. A household pays the lesser of its
available balance and the daily essential bill; any shortfall becomes arrears.
Arrears are never hidden debt: they are visible per household, reduce
affordability, and can be cleared in a later period when income exceeds
essentials. No money is created or destroyed by the household layer.

## Resident interaction

- Residents keep their existing per-person spending interface, but the wallet
  is drawn from the household balance.
- Bus fares, car running costs and mode-choice affordability read the shared
  household balance. A household in arrears is treated as financially
  constrained and prefers the safe walking fallback when a paid mode would
  otherwise be chosen; walking is never blocked.
- Income credited on day rollover goes to the household, not to an individual
  wallet.
- Car purchase remains a bounded household decision with the existing cash
  buffer, and is refused when the household cannot afford it.
- Passenger conservation, boarding order, movement smoothing and dispatch are
  unchanged.

## Municipal and operator interaction

Household spending does not bypass existing interfaces. Fares still credit the
operator account and subsidy ledger as before. Municipal taxes remain building
and business assessments in `finance.zig`; household essentials and arrears are
private household state, not municipal revenue. No municipal transfer is
created by household arrears.

## Persistence

Household id, shared balance, daily income, essential expense, arrears and
member count are serialized and validated. The save schema becomes
`version: 6`, `rules: "bellwether-2027-01-v6"`; version 5 and older files are
rejected explicitly with result 3. No migration layer is added.

## Verification required

Income/expense conservation, shared household accounting, affordability
transitions, walking fallback, fare/operator reconciliation, tax/ledger
reconciliation, passenger conservation, transport dispatch, save/load
continuation and browser reports. Docker ReleaseSafe build and served-asset
identity; no permanent test suite.
