# Road-surface rendering follow-up: per-road joins, one pavement plane

**Status: complete.** The four leftovers of `2520208` are drawn and verified;
`docs/scene.md` carries the rules.

## What was wrong and what changed

1. **An overlay stopped at the junction.** `junctionFans` painted the surface
   join in one neutral dark colour, so `O` (streets), `G` (traffic) and `F`
   (pedestrian) recoloured the streets while every junction kept base pavement,
   and a work order's orange never reached the join. Each wedge is now split on
   the bisector of its road pair and each half takes that road's own colour and
   layer, through the same `surfaceColor`/`surfaceOffset` the street strip uses.
2. **Actors sat below the pavement.** A vehicle started at
   `city.elevation + 0.2` and a resident quad at `p.y`, up to 0.14 m under the
   carriageway and off by a different amount on a deck. One shared offset is now
   named with the road layers, and cars, buses, residents, cyclists and crew
   quads are drawn at `@max(standing, city.elevation + 0.26)`. `city.elevation`
   itself is untouched: it is the surface the simulation walks on.
3. **The works ribbon went under the paint, and the other ribbons left wedges.**
   The layer order is now stated where the offsets live - kerb 0.22, carriageway
   0.26, lane 0.30, centre dash 0.31, crossing 0.34, works 0.38, selection ribbon
   0.40 - so an active or drafted work order covers the dash and crossing instead
   of being cut by them. Route, stop and drafted-crew ribbons are mitered at a
   turn with the same wedge fill the roads use.
4. **The join pass was quadratic.** It scanned every road for every node once per
   layer, about 2.2 M comparisons a layer. A node-incidence list is built once a
   frame in `city.buildIncidence`, so a frame pays O(nodes + roads) once.

## Verification

Host rasteriser of the renderer's own vertex stream (harness in `src/`, built in
the compiler container, deleted before committing): a degree-8 junction under
the base, streets, traffic, pedestrian and active-works views; a selected
resident's route; a bridge deck carrying a car, a bus and walkers; and a curved
work order drafted during the session and then committed as roads so the join
pass ran over a topology that changed mid-session. The work-order frame shows
the orange reaching the join, and the curve draws as one ribbon rather than
breaking at its bends. Frame output is about 1,009,000 vertices of the 1.4 M
budget, drawn in 21-23 ms on the harness.

ReleaseSafe Docker build (`city.wasm` 4,143,261 bytes) and the served page in a
browser: the streets overlay recolours the network through the junctions and the
canvas zooms with a wheel over it.

## Limits carried forward

- The kerb fan is still one uniform colour, which is intended: the kerb band is
  a single surface either side of the coloured carriageway.
- Geometry is still rebuilt each frame; cached static world meshes and GPU camera
  transforms remain the next rendering optimisations.
