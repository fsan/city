# Simulation
`game.zig` advances time, maintenance, trust and real history snapshots. `residents.zig` owns residents, employer assignments, company capacity and movement. `finance.zig` owns tax assessments, collections, protected reserves and the municipal ledger. `contracts.zig` validates work orders, evaluates companies and settles delivered/cancelled work.

Keep rules in Zig and reports read-only. IDs link these modules; neither simulation nor finance depends on rendering or the browser. See `docs/economy.md` for assumptions and formulas. No test suite is added in this slice.
