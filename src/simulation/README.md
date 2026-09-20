# Simulation
`game.zig` advances time, maintenance, trust and real history snapshots. `residents.zig` owns residents, employer assignments, company capacity and movement. `transport.zig` owns vehicle queues, bus routes, capacity, fares and lane policies; residents choose modes and board/leave vehicles. `game.zig` settles transport subsidies without coupling transport to finance. `finance.zig` owns tax assessments, collections, protected reserves and the municipal ledger. `contracts.zig` validates work orders, evaluates companies and settles delivered/cancelled work.

`agreements.zig` owns operator quotes, protected bus commitments, delivery settlement and the 64-record closed agreement register. It reads transport delivery without introducing a transport-to-finance dependency.

Keep rules in Zig and reports read-only. IDs link these modules; neither simulation nor finance depends on rendering or the browser. See `docs/transport.md` and `docs/economy.md` for assumptions and formulas. No test suite is added in this slice.

Operator working capital and driver coverage are implemented; see [mechanics](../../docs/service-agreements.md) and `docs/operator-capital-slice.md` at the repository root. Accounts reconcile opening capital, fares, subsidies, agreement receipts, vehicle costs and labour. Offers choose daytime or all-day coverage.
