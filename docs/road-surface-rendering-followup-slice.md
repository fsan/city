# Road-surface rendering follow-up (slice draft)

The road-surface batch is committed: `2520208` fixed the junction wedges, the
pavement lift and the bridge deck corridor, and `bae8db9` records the rules in
`docs/scene.md`. Vertex output is 886,452 of the 1.4 M budget, the ReleaseSafe
build passes, and the served page was checked in a browser at four zoom levels.

Four things that batch did not finish, in the order they matter.

## 1. An overlay does not reach junctions

`junctionFans(1.75, 0.26, ...)` paints the surface join in one neutral colour,
so with the streets (`O`), traffic (`G`) or pedestrian (`F`) overlay on, the
streets recolour while the junctions stay base pavement. An active work order is
the same: `r.works` draws `.{ 0.66, 0.46, 0.18 }` per segment, but the junction
under it keeps the neutral colour. This is the most visible leftover of the fix,
because the whole point of the fan is that a junction reads as the roads meeting
there.

## 2. Actors were not lifted with the pavement

Road layers now sit 0.22 (kerb), 0.26 (surface), 0.30 (lane), 0.31 (dashes) and
0.34 (crossing) above the ground. The vehicle body still starts at
`city.elevation(x, z) + 0.2` and the resident quad still spans `p.y` to
`p.y + 0.9`, so a car or a walker can be drawn up to 0.14 m below the pavement
it is standing on, and the error differs between land and a deck. One pavement
offset shared by the road layers and the actors would settle it. `city.elevation`
itself should not change: the simulation is entitled to the ground height.

## 3. The works ribbon now sits under the dashes and the crossing

Works are drawn at 0.30, centre dashes at 0.31 and crossings at 0.34, so orange
work-order surface is cut by dash and crossing geometry. Decide the intended
order and make it explicit next to the offsets.

## 4. The join pass costs a full scan a frame

`junctionFans` loops every node and every road inside it, once per layer:
1,328 nodes against 1,624 roads is about 2.2 M iterations per layer. A node
incidence list built once, or the existing `degree` helpers, would make it
O(roads).

## Verification for the follow-up

- Host rasteriser of the renderer's own vertex stream: a junction under each
  overlay, a bridge deck carrying vehicles, and a road drawn by the player during
  the session (the harness pattern that worked: put the harness inside `src/`,
  build it in the compiler container with
  `zig build-exe -OReleaseSafe -Mroot=src/<harness>.zig`, delete it afterwards).
- ReleaseSafe Docker build, then the served page in a browser. The in-app
  browser zooms the game with a wheel over the canvas, which `tab.scroll` on the
  canvas element produces.
- Keep the rendering paragraph in `docs/scene.md` in step with the offsets and
  the join rule.
