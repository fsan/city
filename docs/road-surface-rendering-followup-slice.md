# Road-surface rendering follow-up (slice draft)

The street-surface batch is complete: `2520208` fixed the junction wedges, the
pavement lift and the bridge deck corridor; `bae8db9` records the rules in
`docs/scene.md`. Vertex output is 886,452 of the 1.4 M budget, the ReleaseSafe
build passes, and the served page was checked in a browser at four zoom levels.

Four things that batch deliberately left are worth one more pass.

## 1. Overlay colour does not reach junctions

`junctionFans(1.75, 0.26, .{ 0.23, 0.25, 0.25 })` paints every junction in one
neutral dark colour. With the streets (`O`), traffic (`G`) or pedestrian (`F`)
overlay on, the streets around a junction recolour by condition, congestion or
pedestrian density while the junction stays base pavement. An active work order
(`r.works`, drawn `.{ 0.66, 0.46, 0.18 }`) has the same gap. The fill has to be
per road, in that road's own colour, so a junction reads as the roads that meet
there. The kerb fan is uniform and unaffected.

## 2. Actors were not lifted with the pavement

Road layers moved up to 0.22 (kerb), 0.26 (surface), 0.30 (lane), 0.31 (dashes)
and 0.34 (crossing), but the surfaces actors stand on did not move:

- a vehicle body still starts at `city.elevation(x, z) + 0.2` (the `y` computed
  from the highest of its four corners in `scene.draw`), and
- residents and crews are quads from `p.y` to `p.y + 0.9`.

So a car or a walker can be drawn up to 0.14 m under the pavement it is meant to
be on, and the gap differs between land and a bridge deck. One shared pavement
offset used by both the road layers and the actors would keep them together;
the walkable `city.elevation` stays as it is, because the simulation is entitled
to it.

## 3. The works ribbon now sits under the dashes and the crossing

The works overlay is drawn at 0.30 and the centre dashes at 0.31, with the
crosswalk stripes at 0.34, so orange work-order surface can be cut by dash and
crossing geometry. Either the works ribbon belongs above them, or the ordering
needs a deliberate reason. Worth a look with `J` (works) and a live order.

## 4. The join pass costs a full scan per frame

`junctionFans` loops every node and, inside it, every road, once per layer:
1,328 nodes x 1,624 roads x 2 layers is about 4.3 M iterations per frame, on top
of the geometry build. `city.degree`, `road_between` and the node lists already
exist, so an incidence list built once per frame would turn this into O(roads).

## Suggested verification

- Host rasteriser of the renderer's own vertex stream for a junction under each
  overlay, a bridge deck carrying vehicles, and a road the player draws in the
  session; then the ReleaseSafe Docker build and a browser check at zoom.
- Confirm the vertex count, the frame's own cost, and that picking still agrees
  with the drawn surface (the inspector opens the street under the cursor).
