# River and the Rome-inspired seeded town (slice 13)

Bounded plan: replace the authored seeded town with a larger, irregular street
plan modelled on the attached slice of Rome, add a flowing river that is an
obstacle today but is shaped for a future water-flow simulation, and tune the
map scale and the travel economics so that residents who live far from the
centre genuinely consider a car or a bus instead of a bicycle or their feet.
No trains, no ferry, no weather system and no bridge-building tool are added.

## What was wrong with the first attempt

The first implementation of this slice produced a *smaller* car share than the
lattice it replaced, not a larger one. Reading the actual graph rather than the
prose found the cause, and it was not the travel constants:

- `chain()` connected only consecutive samples of the *same* street run, and
  two runs merged only when a sample happened to land within 9 m of an existing
  node. Cross streets therefore passed over the arterials without ever forming
  a junction, and the river trim cut each run into a further west piece and
  east piece.
- Measured on that tree: 492 nodes in **18 disconnected components**, largest
  105 nodes, 50 dead ends, and **213,806 of 241,572 node pairs unreachable**
  (88%).
- **2,899 of 3,240 commuters had no home-to-work route at all**, so they could
  never drive or ride anywhere and fell back to walking locally. Buses were
  "active" but carried nobody.

The travel-cost tuning below is real and necessary, but on its own it changed
nothing, because most residents had nowhere to travel to.

## The town

- World grows to 1,320 x 1,040 m (about six times the seeded area) with 288
  authored buildings and the same 3,840 adult residents, so dwellings are much
  further apart and outer districts are 600-1,000 m from the centre.
- The ground-tile grid (`spacing`, `cols`, `rows`) is re-derived from the new
  size so the renderer does not multiply its vertex count.
- Twelve districts and the existing district ids and names are kept.
- `resolveJunctions()` turns every true segment crossing into one shared
  junction node (`crossing`, `splitAtNode`), and `linkFragments()` gives any
  remaining fragment one bounded link. The authored plan is now **one connected
  component** with **zero unreachable pairs** and is walkable and drivable end
  to end.

## The river

`src/scene/river.zig` owns the water. It is deliberately dependency-free and
data-first:

- an authored centreline polyline with a pronounced bend, a half-width, a bed
  depth and a per-point water level and discharge,
- `inside`, `bedAt`, `surfaceAt`, `nearest` and `crosses(a, b)` geometry
  helpers used by the scene, the road tool, parcels and the renderer,
- an explicit `flow_factor` and `discharge` array that nothing drives yet.

Today the only gameplay effect is impassability: the channel is carved into the
terrain so the ground dips to the bed, no building or street may stand in the
water, and the only roads that cross are the seeded bridges. The extension
point for the weather and water-flow work is documented in the module: a
weather system will drive `flow_factor`, the per-point `levels` and
`discharge`, and may then flood the low bank or close a bridge. Nothing reads
the flow today, so the behaviour is unchanged by adding it.

Bridges are ordinary road segments whose endpoints stand on opposite banks.
`city.elevation` returns the bridge deck inside their corridor, so walkers,
vehicles and the renderer all rise over the water without a separate system.

## The street plan

Modelled on the attached Trastevere/Testaccio slice:

- two riverside roads (a Lungotevere on each bank) generated as offsets of the
  centreline,
- two long arterials, one per bank (Viale di Trastevere west, Viale Aventino
  east), with Viale dei Quattro Venti, Via Ostiense and a central avenue,
- a dense irregular local mesh in the historic core and a sparser one in the
  suburbs, each line jittered deterministically and trimmed wherever it would
  enter the water, which is what produces the bank-hugging shapes,
- four seeded bridges (Ponte Emilio, Ponte Sisto, Ponte Testaccio and Ponte
  della Scienza) that are the only crossings,
- an outer lane ring.

Streets keep the lane/street/avenue classes from slice 10. Both seeded bus
services are re-laid by world position and snapped to the nearest valid
kerbside stop, so a change of layout can no longer silently disable them.

## Travel and ownership tuning

- Per-trip motoring cost falls from `0.014 x distance + 0.30` to
  `0.002 x distance + 0.20`, so the money cost of a trip no longer grows faster
  than the time it saves. Parking prices, the fare, the subsidy and the
  household ledger are untouched.
- Ownership compares the resident's own realistic alternative (their bicycle
  where they own one, walking where they do not) with a car average that
  includes junctions, and charges a bounded daily ownership cost of **12**.
  The bar is set so a household on the edge of the plan reaches the point where
  a car pays and a household beside its work does not.
- The car-owning tie-break in the trip choice falls from a blanket 18% discount
  to 6%, so a genuinely faster bicycle or bus still wins its own trip.
- Bicycle and car park supply is scaled with the new area (`max_bike_parks`
  44 -> 132, `max_car_parks` 16 -> 40). At the old supply the bicycle was
  unavailable at most destinations and riders fell back to walking.
- `transport.journey` estimates a bus ride from the bus limit and its dwells
  instead of `distance/3 + 5` per leg, and reaches stops within a wider
  catchment than the old 45 m, so a long direct ride competes honestly.

Everything else stays: walking is still the safe fallback, fares and subsidies
are unchanged, no money is created, and passenger conservation is untouched.

## Persistence

Manual save files become `version: 12`, `rules: "bellwether-2027-10-v12"`.
Version 11 and older files are rejected explicitly with result 3, as every
earlier layout change has done; there is no migration layer. The river is
derived from authored constants and is validated through the terrain and node
checks that already exist, so it adds no serialised fields.

## Verification

Docker Compose Zig 0.14.1 ReleaseSafe build and startup; JavaScript syntax
checks. A headless probe (outside the repository, `/tmp/cityprobe4`) stepped
1/30 s for eight simulated days and sampled hourly.

Graph: one connected component, 569 nodes, 633 roads, 4 bridge spans, 0 water
nodes, 0 water buildings, 0 unreachable node pairs. Commuter home-to-work cost
spreads across the 200-1,400 m bands rather than collapsing to "unreachable".

Mode split at the morning peak, before this slice and after:

| day | walk | bike | car | bus | (baseline car) |
|-----|------|------|-----|-----|----------------|
| 0 | 69 | 1261 | 1379 | 0 | 363 |
| 1 | 585 | 878 | 965 | 7 | 144 |
| 3 | 1040 | 694 | 746 | 6 | 84 |
| 5 | 1189 | 693 | 502 | 5 | 46 |
| 7 | 1354 | 586 | 377 | 5 | 48 |

Peak car 1,463 and peak bicycle 1,621 on the first day; settled car 380-500 and
bicycle 590-690 over a week. Car ownership settles at 1,572 of 3,812 adults and
is stable from day 1, with no household below the cash reserve. The road tool
refuses a river crossing and a stop in the water; four bridges carry both
walkers and vehicles. Render vertex count stays inside the buffer. No permanent
test suite is added.

## Remaining limits

- The bus carries only single figures. This is a size limit, not a routing
  fault: the seeded town is about 1.3 km across, and a bicycle at 4.2 m/s is
  honestly competitive over that distance, so a bus cannot win the trip on
  time. Making buses matter needs a larger city (`max_nodes` is already at
  569 of 640, so that is a deliberate budget decision) or a bus-priority
  measure. The travel model is left honest rather than tuned to a target share.
- The renderer draws the water surface and samples the channel inside the
  ground grid and road ribbons near the river. It is verified by build and by
  geometry inspection, not by a rendered screenshot: this environment has no
  browser and lacks WebGL.

## Out of scope

Trains, trams, ferries, tunnels, a bridge-building tool, weather, rainfall,
flood damage, water quality, drainage, and any change to the economy beyond the
documented travel-cost constants and the ownership comparison.
