# Road surface rendering: joins, pavement lift and deck corridor

Status: complete and committed. `2520208` fixes the drawing; `bae8db9` records
the rules in `docs/scene.md`.

## The three faults

All three were in the drawn surface, not in the model. The simulation walked on
the correct ground the whole time.

1. **Splits at curves and connections.** A road was drawn as one strip per graph
   segment with a perpendicular end edge, so two segments meeting at a bend or a
   junction left a wedge between their end edges and the ground below showed
   through it. Every node now fills one triangle per neighbouring pair of roads,
   using those two roads' own edge corners and their bearings around the node,
   so the wedge is covered and nothing is painted outside the carriageway.
2. **Terrain cropping through the pavement.** Road layers sat 0.08-0.12 m over
   `city.elevation` while the ground mesh was drawn at `city.carved` from 40 m
   tiles (4 m near the river), so the two surfaces disagreed between samples and
   the carved bank rose through the road. Strips beside the river now use the
   ground mesh's own four-metre step and every road layer sits above the mesh's
   chord error there: 0.22 kerb, 0.26 surface, 0.30 lane, 0.31 dashes, 0.34
   crossing.
3. **Bridge and street.** The deck corridor was a 3.2 m half-width against a
   5.4 m carriageway and stopped at the span ends, so the bridge street and the
   junction with the bank street fell to the carved bed. The corridor is now
   4.3 m, matching the drawn slab, and continues eight metres past each end of
   the span.

## Verification

- A host rasteriser of the renderer's own vertex stream (built with
  `zig build-exe -Mroot=src/probe.zig` inside the compiler container; the module
  root is `src`, so a harness placed there may import `render/scene.zig`) drew
  the frame at the river bend and across each bridge before and after. The
  wedges and the sawtooth of bank through pavement are gone.
- ReleaseSafe Docker build: `city.wasm` 4,130,263 bytes, exit 0, published to
  `/output`.
- The served page was checked in a browser at four zoom levels: junctions solid,
  riverside streets clean, bridge street continuous onto both banks.
- Vertex output rises from 861,426 to 886,452 of the 1.4 M budget.

## Limits left open

- The junction triangles for the *surface* layer use one neutral dark colour, so
  with an overlay on (`O` streets, `G` traffic, `F` pedestrians) junctions stay
  the base pavement colour while the streets around them change. The kerb layer
  is uniform, so it is unaffected.
- Raised pavement versus actors: road layers moved up to 0.22-0.34 m but vehicle
  bodies still start at `elevation + 0.2` and residents at `p.y`, so cars and
  walkers now sit a few centimetres into the pavement instead of on it.
- The works ribbon (0.30) is now below the centre dashes (0.31), so dashes can
  cut through an active work-order overlay.
- `junctionFans` runs one pass over every node and every road for each of the two
  layers, about 4.3 M iterations per frame. The scene already has node adjacency
  helpers; an incidence list would remove the inner scan.
- Roads added by the player after a rebuild take the same path, but no browser
  check was done on a freshly drawn curve or on a road that crosses an existing
  one, so the join rule is only verified on the authored town.

## Kickoff prompt for the next agent

> Goal: finish the road-surface rendering work so overlays, works and actors all
> agree with the new pavement geometry, and so the join pass stops costing a
> scan of every road at every node.
>
> Context: `2520208` fixed the joins, the pavement lift and the bridge deck
> corridor; `docs/road-surface-rendering-slice.md` and the rendering paragraph in
> `docs/scene.md` describe the rules. Three things were left open.
>
> 1. Junction fills use one neutral colour, so with the streets, traffic or
>    pedestrian overlay on, every junction keeps the base pavement colour while
>    the streets around it recolour. Draw the surface join in the colour of the
>    roads that meet there, and make the works colour appear at junctions too
>    while a work order is active.
> 2. Road layers now sit 0.22-0.34 m over the ground but vehicle bodies still
>    start at `elevation + 0.2` and residents keep `p.y`, so cars and walkers sit
>    slightly inside the pavement. Introduce one pavement-offset constant that
>    the road layers, the cars, the buses and the walkers share, so actors stand
>    on the surface they are drawn on, on bridges as well as on land.
> 3. `junctionFans` scans every road for every node once per layer. Build the
>    node incidence list once per frame (or keep it from the scene) and iterate
>    the incident roads only.
>
> Also check the works ribbon offset against the centre dashes, because the
> dashes now sit above the works overlay.
>
> Verification expected: a host rasteriser of the renderer's own vertex stream
> (the harness pattern above) with frames for a junction under each overlay, a
> bridge deck with vehicles on it, and a player-drawn curve; a ReleaseSafe Docker
> build; and the served page checked in a browser at several zoom levels,
> including a road built during the session. Delete the harness and any frame
> files before committing, and keep the docs paragraph in step with the rules.
