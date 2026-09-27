# Parking and freight (slice 24, numbered item 16)

Bounded plan: give the parking supply a real freight counterpart. Depots
dispatch bounded delivery runs to staffed businesses; a run occupies a kerbside
loading bay at the destination for a bounded dwell, and the player can convert
kerbside car spaces into loading bays on any eligible segment. A delivered
business keeps its full daily trading surplus, while a business that could not
be reached loses a bounded share of it. No regional trade, input markets,
warehousing, lorry fleet or shipping model is added, and no money is created:
every freight fee is a private transfer between two companies.

This note is written before the slice code, as the kickoff requires.

## Deliveries

`src/simulation/freight.zig` keys a bounded ring of 48 runs to the real road
network. A depot is an existing contractor company whose premises are a depot
lot; each depot has its own lorry count and works from its own cash. A run names
the depot, the customer, the delivery lot and its frontage node, the kerbside
road the lorry parks on, the goods carried and the fee paid.

Every non-contractor business is a customer. Daily demand is a bounded function
of its staffed headcount and its kind - a market and an industrial lot take more
than a shop or an office - floored at one unit so even a small business still
receives a delivery. Once per simulated day each depot with cash dispatches
bounded runs, nearest customers first, up to its lorry count. A depot with no
cash, no reachable customer or no free bay dispatches nothing.

A dispatched run travels from its depot node to the customer's frontage node at
a bounded lorry speed, holds its loading bay for a dwell of 20-90 simulation
seconds that scales with the goods carried, then departs. The fee is
`goods x GBP 6`, paid privately from the customer's cash to the depot's cash, so
both company balances reconcile and the municipal ledger never sees it.

## Loading

A lorry loads at the kerbside bay in front of its customer. Loading bays are
player-set: `freight_set_bays(road, count)` designates 0-6 of an eligible
segment's kerbside spaces as loading bays, and the same count comes out of the
car parking available there. Only a segment that already allows kerbside parking
- an avenue or street carrying vehicles, with a pavement, not under works - can
take bays. A customer fronting such a segment is served there; a customer on a
lane or a works segment is served from the nearest eligible segment within a
bounded walk.

While a lorry is loading, `freight.bayHeld(road)` is true and that segment's car
parking capacity is reduced accordingly, so the same kerbside space is never
sold twice. Every held bay-second is counted, so the trade-off between parking
supply and freight access is measurable rather than a slogan.

## Parking demand

`parking.demand(road)` publishes the kerbside pressure the town is actually
facing on a segment: the day's failed kerbside attempts there relative to its
spaces, combined with current occupancy. It is a measured demand signal, not a
survey - the counters come from the same parking search the residents already
run. Loading bays take car supply out of a segment, so a street under heavy
demand shows the cost of that conversion directly.

## Business access

A business is served for the day when its deliveries have arrived. The daily
trading step multiplies the documented GBP 12-per-employee surplus by a bounded
access factor: `access_floor` (0.5) when nothing was delivered, rising to 1.0
when the day's demand was met in full. A business with no depot, no reachable
route or a blocked frontage therefore trades at a real, inspectable loss.
Contractor depots earn freight fees rather than the ordinary trading surplus.

## Persistence

Schema moves to **v19 / `bellwether-2028-05-v19`**; v18 and older files are
rejected with result 3. Loading-bay designations, the run ring, its numbering
and its running counters are serialized and validated field by field: a run must
name a real depot, a real customer and a real frontage road, and goods and fee
must stay inside the published bounds. Bay occupancy and access scores are
derived each step and never trusted from a file.

## Verification required

Delivery demand scaling with staff and kind, bounded dispatch, the
dispatch-travel-load-deliver life cycle, a bay held only while loading, bays
refused on ineligible segments, loading bays coming out of car supply, parking
demand reflecting real refusals, business access scaling the daily surplus, the
private fee reconciling between the two companies, and a v19 round trip
returning 0 with a v18 file returning 3. Docker ReleaseSafe build and
served-asset identity; temporary focused checks outside the repository; no
permanent test suite.
