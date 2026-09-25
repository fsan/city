# Road-surface rendering: joins, pavement lift and the deck corridor

**Status: complete and committed.** `2520208` fixes the drawing, `bae8db9`
records the rules in `docs/scene.md`.

## What was wrong and what changed

All three faults were in the drawn surface, not in the simulation. The model
already agreed with the walkable ground.

1. **Splits at curves and connections.** A road was one strip per graph segment
   with a perpendicular end edge, so two roads meeting at a bend or a junction
   left a wedge between their end edges and the ground showed through. Every
   node now fills one triangle per neighbouring pair of roads, from those two
   roads' own edge corners, with the roads ordered by bearing around the node
   (`junctionFans` in `src/render/scene.zig`).
2. **Terrain cropping through the pavement.** Road layers sat 0.08–0.12 m over
   `city.elevation` while the ground mesh was drawn at `city.carved` from 40 m
   tiles, refined to 4 m near the river, so the two surfaces disagreed between
   samples and the carved bank rose through the road. Strips beside the river
   now use the ground mesh's own four-metre step and every road layer clears the
   mesh's chord error: 0.22 kerb, 0.26 surface, 0.30 lane, 0.31 dashes, 0.34
   crossing.
3. **Bridge and street.** The deck corridor was a 3.2 m half-width against a
   5.4 m carriageway and stopped at the span ends, so the bridge street and its
   junction with the bank street dropped to the carved bed. The corridor is now
   4.3 m, matching the drawn slab, and continues eight metres past each end.

## Verification

Host rasteriser of the renderer's own vertex stream, frames at the river bend
and across each bridge; ReleaseSafe Docker build (`city.wasm` 4,130,263 bytes);
the served page in a browser at four zoom levels. Vertex output rose from
861,426 to 886,452 of the 1.4 M budget.

## Limits carried forward

- The **surface** junction fan paints one neutral dark colour, so with the
  streets, traffic or pedestrian overlay on, junctions keep the base pavement
  colour while the streets around them recolour. The kerb fan is uniform and
  unaffected.
- Actors were not lifted with the pavement. Vehicles still start at
  `city.elevation + 0.2` and resident and crew quads still use `p.y + 0.2`, so a
  car or a walker can be drawn up to 0.14 m below the surface it stands on.
- The works ribbon sits at 0.30, now *below* the centre dashes at 0.31 and the
  crossing at 0.34, so a work order's orange can be cut by dash and crossing
  geometry. Route, stop and crew ribbons are drawn by the old single-quad
  `ribbon` and still leave their own wedges at a junction.
- `junctionFans` scans every node against every road once per layer: about
  2.2 M iterations per layer, 4.3 M for a frame, on top of the geometry build.
- No browser check was made of a curve or crossing the player draws during a
  session, or of the pedestrian, traffic and works overlays at a junction.

## Kickoff prompt for the next agent

> Goal: finish the road-surface rendering so the overlays, the actors and the
> frame budget all agree with the lifted pavement that `2520208` introduced.
>
> Context: `2520208` fixed the junction wedges, the pavement lift and the bridge
> deck corridor; `bae8db9` and `docs/road-surface-rendering-slice.md` describe
> the rules. Four things are left open.
>
> 1. The surface junction fan paints a single neutral colour, so with the
>    streets (`O`), traffic (`G`) or pedestrian (`F`) overlay on, every junction
>    stays base pavement while the streets around it recolour, and an active
>    work order's orange never reaches a junction. Draw the surface join in the
>    colour of the roads meeting there, including the works colour.
> 2. Actors were not lifted with the pavement, so cars and walkers can be drawn
>    slightly below the surface they stand on. Give the road layers and the
>    actors one shared pavement offset and use it for cars, buses, residents and
>    crew quads, on decks as well as on land.
> 3. The works ribbon at 0.30 now sits below the centre dashes at 0.31 and the
>    crossing at 0.34, so dash and crossing geometry cuts through it; check the
>    layering order and fix it. The route, stop and crew ribbons still use the
>    old single-quad `ribbon` and leave wedges at junctions.
> 4. `junctionFans` scans every node against every road once per layer. Build a
>    node incidence list once and iterate the incident roads, so a frame does not
>    pay 4.3 M iterations for the joins.
>
> Verify with a host rasteriser of the renderer's own vertex stream: build a
> harness inside `src/` and compile it in the compiler container with
> `zig build-exe -OReleaseSafe -Mroot=src/<harness>.zig` (the module root is the
> harness's directory, so `@import("render/scene.zig")` works there), with frames
> of a junction under each overlay, a bridge deck carrying vehicles, and a curve
> drawn during the session. Then a ReleaseSafe Docker build and the served page
> in a browser at several zooms; the in-app browser can zoom the canvas by
> scrolling the canvas element. Delete the harness and every frame file before
> committing, and keep the rendering paragraph in `docs/scene.md` in step.
