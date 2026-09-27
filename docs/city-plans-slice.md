# City plans: a window into the authored board

**Status: complete.** The plan mechanism, the smaller default city and the
development city are implemented, served and checked in the browser.

## What was wrong

The authored town is one 1,320 x 1,040 m board with 3,840 residents and a
river running north-south through it, so an outer home-to-work trip is
600-1,000 m. Every session laid out that whole board, and the report was that
the town is too big to develop at the start.

## What a plan is

A plan is a **window** into the authored board, not a second hand-drawn layout.
The same streets, river, bridges, parks and lots are laid out every time; the
plan decides how much of the board a city occupies. That is what lets a smaller
city keep the river and the crossings the authored plan is built around without
maintaining a second plan.

`src/scene/city.zig` now holds:

- `Plan`: `bellwether`, `compact`, `development`.
- `origin_x`/`origin_z`, `size_x`/`size_z`, `cols`/`rows`/`spacing` as plan
  values rather than fixed constants.
- `setPlan(plan)`, which selects the window; `insideWindow(x, z, margin)`,
  which every seeding pass uses for its bounds; `developmentPlan()`, which the
  development plan uses to switch every authored feature on; and
  `planName`/`planCount` for the UI and the ABI.
- Every bound check in the street, river-setback, ring, park, building, parcel
  and stop passes now tests the window instead of `0..size`, and the renderer's
  ground grid, edge strips, camera and pan/zoom clamps start at the window
  origin.

Windows:

| plan | origin | size | use |
|------|--------|------|-----|
| `bellwether` | 0, 0 | 1,320 x 1,040 | the whole authored board |
| `compact` | 330, 0 | 660 x 1,040 | the default: the river and its bridges, both banks, a shorter walk |
| `development` | 0, 0 | 1,320 x 1,040 | the whole board, every feature switched on |

The window is chosen before `init()` lays the town out: `set_city(plan)` in
`src/main.zig`, called from `web/main.js` from the stored choice, with a plan
selector in the city tools bar. Changing the plan stores the choice and reloads,
because the town is laid out once in `init`.

## Verification so far

ReleaseSafe Docker build (`city.wasm` 4,110,069 bytes, down from 4,143,261 for
the full board) published and served. The served page at 127.0.0.1:8080 loads
the smaller default: the board is visibly narrower, the river still crosses it
whole with its bridges, and the plan selector shows Camden Quarter with
Bellwether and Integration Yard available. `node --check` passes on
`web/main.js`.

## The development city

`development` keeps the whole board and switches every authored feature on in
place, so one session exercises the features and the integrations between them.
Everything it does is an ordinary authored record, so the snapshot, the
renderer and every report agree by construction:

- `forceAllFeatures` (in `src/scene/city.zig`) gives every district green
  space, taking the largest vacant lot where the authored search found none, so
  no ward is without a park; it guarantees one depot to staff, so the operator,
  employment and contract paths have somewhere to run; and every junction arm
  carries a crosswalk, so the crossing paint, the signals and the pedestrian
  overlay all meet at the same corners.
- `seedIntegrationTown` (in `src/simulation/game.zig`) then switches the
  remaining feature layers on with ordinary records: it zones every vacant
  parcel residential, commercial, industrial or mixed so the permit queue has
  buildable sites, designates loading bays on the central streets so freight
  holds a real kerbside bay and the parking supply pays for it, and lodges two
  work orders on central streets through the ordinary offer and review path.
- `lighting.seed` lights every eligible segment to its street-class capacity
  when the development plan is selected, instead of only the segments that
  carry frontage.

The works surface is deliberately **not** forced directly. A `road.works` flag
must be owned by a live contract order - the snapshot validator enforces the
pairing and `game.init` clears an orphan flag - so the development town lodges
a real order instead. A contractor is genuinely assigned, its four-person crew
genuinely travels to the site, the road carries works while the crew builds,
and the flag clears when the contract settles.

**Measured.** A focused ReleaseSafe probe outside the repository boots each
plan in its own process and reports the feature layers. The default Camden
Quarter is unchanged: 817 lots, 928 roads, 234 lit segments at 0.947 mean
coverage, no loading bays, no works streets, no eligible development sites, 8
of 12 districts with green space. Integration Yard now carries 820 lots across
1,624 roads and 416 junctions with 64 signals, **full lighting coverage**
(320 lit segments, 846 columns), **16 loading bays**, **10 eligible development
sites**, green space in **all 12 districts**, 1,324 crosswalks, and both seeded
work orders running to completion - the works surface is live for 1,124
simulation steps and both contracts settle at progress 1.00. `make build`
publishes `/output/city.wasm` (sha256 `82d714344a042ab491b2ba079cda199af02cfd17965df66b36bc3a29ef422819`),
byte-identical to the served `/build/city.wasm`.

## Limits carried forward

- The population stays 3,840 under every plan, because the residents array is
  sized from `city.population`; the smaller plan is therefore denser, not
  emptier. A plan that should hold fewer people needs a runtime population
  target and a residents init that honours it.
- Save/load does not record the plan yet: a snapshot reloads into whatever plan
  the page selected, and its node positions are validated against the live
  window. A saved town should carry its plan.
