# Agreement review and procurement slice

Next bounded increment after the first bus agreements and road/zoning work. The mayor compares the same draft against all three operators, sees delivery against elapsed contracted time and current service blockers, then can end the agreement and re-offer without losing the previous record.

Acceptance criteria:
- Zig supplies minimum prices and eligibility using the same rules as acceptance; previews do not reserve money. Invalid offers leave state unchanged.
- Every published offer has a unique agreement number. Revisions, expiry, cancellation and line withdrawal retain immutable terms, route stops, delivery, paid and released amounts in a newest-first register of the last 64 closed records for this session.
- Active agreements expose expected-to-date bus-seconds, delivery percentage, withheld payment and current bus states; selected-line waiting riders remain visible. No headway or timetable compliance is implied.
- Cancellation settles earned pennies exactly once, releases the unused reserve immediately, and allows a new operator without changing the route or teleporting riders. Ledger payments identify the agreement. Withdrawal settles even while paused.
- Expiry cannot earn beyond the contracted end. Operator capacity and treasury reservations reconcile through revision, cancellation, expiry and line-slot reuse.
- Docker ReleaseSafe compilation and temporary WASM/browser smoke checks cover these decisions and existing rider/repair continuity. No permanent test suite.

Working capital and driver shifts are now implemented in `operator-capital-slice.md`; headway/stop targets and save/load remain separate increments. History survives later agreements within a session, not refresh. Uncontracted lines retain the existing private operation model.
