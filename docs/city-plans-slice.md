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
  development plan will use to switch every authored feature on; and
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

- `forceAllFeatures` gives every district green space, taking the largest
  vacant lot where the authored search found none, so no ward is without a
  park.
- It guarantees one depot to staff, so the operator, employment and contract
  paths have somewhere to run.
- Every junction arm carries a crosswalk, so the crossing paint, the signals
  and the pedestrian overlay all meet at the same corners.
- Two streets within 220 m of the centre carry an active work order, so the
  works surface, the works colours and the junction join all render live.

Verified in the served page: the whole board with the river and its four
bridges, parks visible in every district and the works strip along a central
street.

## Limits carried forward

- The population stays 3,840 under every plan, because the residents array is
  sized from `city.population`; the smaller plan is therefore denser, not
  emptier. A plan that should hold fewer people needs a runtime population
  target and a residents init that honours it.
- Save/load does not record the plan yet: a snapshot reloads into whatever plan
  the page selected, and its node positions are validated against the live
  window. A saved town should carry its plan.
