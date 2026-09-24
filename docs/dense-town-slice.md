# Dense authored town, downtown quarter and green space (slice 17)

Bounded batch: finish the dense-street-wall town that the slice 15/16 commits
introduced but left internally inconsistent, so that it builds, runs and can be
saved and reloaded. No new simulation system is added; the batch repairs and
completes the authored plan, the graph and the snapshot contract.

The numbers below come from a throwaway probe outside the repository
(`/tmp/cityprobe_s15`), compiled with the Docker Compose Zig 0.14.1 toolchain,
plus a Docker ReleaseSafe build of the real artefact.

## What was wrong

The committed batch built and rendered, but three things were inconsistent:

- **The street wall filled a quarter of its target.** 391 of the 820 intended
  lots were placed. Instrumentation showed why: of 7,020 candidate frontage
  slots the dice rejected 6,174 and, of the roughly 846 it accepted, the
  geometry rejected 462 (17 in water, 121 overlapping another lot, 324 over a
  carriageway). A single draw against `building_target` could never reach it.
- **Green space missed a district.** Only 7 of the 12 authored park anchors
  found a clear rectangle, and Garden Ward had no green lot at all.
- **A saved town could not be reloaded.** `persistence.load` returned 4
  (inconsistent) for its own freshly written v12 file. Chasing the first
  failing clause in turn found:
  1. bridge-deck nodes were created before their span was registered, so they
     stored the carved river-bed height while `elevation` returned the deck
     level (`id=856 … y=16.7257 want=20.0000 street=12`);
  2. a duplicate graph edge (`ROADFAIL i=605 a=159 b=887 dup=true street=8`);
  3. the housing validator demanded `kind == .home`, so an apartment unit —
     which the housing, household and finance modules all treat as a dwelling
     via `city.isHome` — was rejected.

## Rules now in force

- **Measured street wall.** `seedBuildings` sweeps frontages through
  `frontageSweep(first_free, share)` and corrects the share against the yield
  the previous pass actually placed, up to five passes. Geometry, not the dice,
  decides how many candidates survive, so the target is reached
  deterministically at 820 lots in 900 storage slots.
- **Green space per district.** Sixteen park anchors, one or more per district,
  each searched with nine lateral nudges and a shrink from full size to 14% of
  it, so a park fits the tighter mesh blocks. The renderer plants each green lot
  from the lot's own identity, so no second list of positions enters the save.
- **Deck heights are derived, and derived data is refreshed.** `seedBridges`
  registers the span before its own nodes exist, and the new
  `city.refreshElevations()` recomputes every node height and every road length
  and slope from the completed spans. It runs at the end of `init` and inside
  `restoreGraph`, so a node can never disagree with `elevation`.
- **No duplicate edges.** `splitRoad` and `splitAtNode` reuse or repoint an
  existing link (`duplicates`, `repoint`) instead of creating a second road
  between the same pair of nodes, which the snapshot validator rejects.
- **One dwelling predicate.** The snapshot validator asks `city.isHome`, the
  same question the simulation asks, so apartments are saveable.

## Verified

Focused probe, ReleaseSafe, outside the repository:

| check | result |
|-------|--------|
| lots placed | 820 of 900 storage, target reached |
| graph size | 1,328 nodes of 1,600, 1,624 roads of 3,200 |
| composition | 265 homes, 93 apartments, 6 markets, 43 playgrounds, 11 plazas, 10 parks, 130 shops, 105 offices |
| placement | 0 out of bounds, 0 in water, 0 over a carriageway, 0 overlapping |
| downtown | 207 lots, 160 of them business or apartments |
| green by district | 4 2 1 2 7 10 8 8 12 3 3 4 — every district has green space |
| routing | 0 unreachable pairs, 0 asymmetric distances, 0 bad next hops |
| render | 864,516 vertices of 1,400,000, all finite |
| snapshot | fresh v12 file, 7,478,151 bytes of 16,777,216, `load result=0` |
| six simulated days | peak 3,279 moving people, 1,120 cars, 4 buses; green-space visits observed |

Docker ReleaseSafe build of the artefact succeeds, and `make build` publishes a
fresh `/output/city.wasm`.

## Limits

- The probe's *combined* run still reports `load result=4` when the save is
  taken after the renderer has drawn a frame, although saving and loading the
  same town immediately after `init` round-trips with result 0. The renderer is
  therefore touching state that the snapshot captures; the next agent should
  treat that as an open defect rather than a passing check.
- Bus ridership remains in single figures to low double figures, the structural
  limit recorded in the slice-14 note: the town is about 1.3 km across with
  free-flowing traffic, so a bus cannot beat a car on time.
- The authored plan is still a fixed town; there is no generator, no growth and
  no construction. `max_nodes` is at 1,328 of 1,600, so further street density
  needs either a larger ceiling or a cheaper route rebuild.
- The slice numbers 15 and 16 are already used by the committed batch, so this
  repair batch is labelled slice 17 in its own note.
