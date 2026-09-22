# Housing and occupancy (slice 9)

Bounded plan: make each home an inspectable housing unit with explicit tenure,
daily rent or ownership cost, a property-owner reserve, affordability arrears
and bounded moves/displacements on the existing daily rollover. No construction,
permits, property development, valuation, parks or demolition is added.

This note is written before the slice code, as the kickoff requires.

## Housing model

Every authored `home` building is one housing unit. A unit records:

- tenure (owned or rented);
- daily rent or ownership cost;
- a separate property-owner cash reserve;
- explicit housing arrears;
- occupancy and lifetime collections;
- the current application target and move state.

Vacant units can be created by moves. Rent and ownership payments are charged
from the household balance after household essentials; a shortfall becomes
unit arrears, never hidden debt or municipal debt. The property-owner reserve
receives the paid housing cost and remains private state.

## Moves and displacement

A bounded number of households may move each day. A move is considered when the
household carries housing arrears, when its housing charge exceeds an explicit
affordability share, or when its commute is materially worse than another
available unit. A move is accepted only into a genuinely vacant unit with a
lower charge and a shorter home-to-work route. Moving residents keeps the
existing simulation transitions: tenancy and household records move first, then
each resident is sent to the new address and walks the route. Crew members and
workers bound to an active order are not moved in this batch.

No household is made homeless here; if no suitable vacant unit exists, the
household stays in place with explicit arrears and a failed/refused application
state.

## Municipal and operator interaction

Housing payments are private money movements. Municipal property assessments,
operator accounts and passenger rules are unchanged. A household that cannot pay
housing may also struggle with transport affordability through the existing
household balance.

## Persistence

Housing units, tenure, rents, ownership costs, owner reserves, arrears,
applications, move state, occupancy and lifetime housing payments are
serialized and validated. Save schema becomes
`version: 8`, `rules: "bellwether-2027-03-v8"`; version 7 and older are rejected
explicitly with result 3. No migration layer is added.

## Verification required

Housing unit/occupancy consistency, rent/ownership conservation, arrears, moves,
displacement, vacancy, affordability, commute changes, passenger conservation,
transport dispatch, ledger/account reconciliation, save/load of every new field
and browser/report behaviour. Docker ReleaseSafe build and served-asset identity;
temporary focused checks outside the repository; no permanent test suite.
