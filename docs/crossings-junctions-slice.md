# Crossings and junction behaviour (slice 22, numbered item 14)

Bounded batch: give each signalised junction a pedestrian-only stage, make
turning traffic yield to the crosswalk it actually drives over and to the traffic
already in the box, and give every movement real turning geometry. No timetable,
no junction-coordination search and no new facility types are added.

This note is written after the slice code, as the kickoff requires.

## The pedestrian stage

Each junction now runs its vehicle branches, then a pedestrian walk and an
all-red clearance before the first branch is released again. During the walk
every vehicle arm is red and every crossing is admitted; during the clearance
nobody is admitted, so whoever started walking has a bounded interval to finish
before the vehicles move. The walk is 4 simulation seconds and the clearance
1.5 by default; walk and clearance are editable and clamp to 0-30 s and 0-10 s.
A walk time of zero removes the stage entirely and returns the junction to its
exact pre-item-14 vehicle-only cycle.

`signal_set_ped_walk(node, seconds)` and `signal_set_ped_clear(node, seconds)`
return the applied value, or -1 when that junction has no signal, and
`signal_set_ped_enabled(node, enabled)` turns the stage on or off. The traffic
panel shows the live stage, how long it has left, and the same walk, clearance
and switch controls, and the bulk editor can write walk, clearance and the switch
across every light, one street or one junction.

## Yielding

Two defects and two rules are fixed here.

- Pedestrians incremented `crossing_active[p.back]`, the node *before* the
  junction, while vehicles checked `crossing_active[v.next]`, the junction
  itself, so the old "cars yield at a crosswalk while somebody is crossing"
  test almost never matched. The count now belongs to the junction the walker is
  crossing at, and to the one painted arm that lies across the path
  (`city.crossedArm`), so the two sides finally agree.
- A car yields to the crosswalk painted on its **own approach**, which is the one
  physically in its path, rather than to any pedestrian anywhere at the
  junction.
- A turning driver yields to the crosswalk it turns into.
- A left turn yields while another vehicle is still in the junction box.

`city.markedCrossing` now takes the walker's movement and resolves the crossed
arm instead of returning true for any crosswalk at the node.

## Turning geometry

Every movement from one arm of a junction to another is classified straight,
left, right or u-turn from the codebase's own right-hand side rule: the right of
a driver travelling along `d` is `(-d.z, d.x)`, which is exactly the offset the
signal head already uses, so an exit with a positive component along that side is
a right turn and a negative one a left. The classification is derived from the
node's own arm directions and never stored.

A turning movement also has a measured radius: the two signal-head points sit a
setback down their own arms, their chord is the hypotenuse of the corner, and the
radius is that chord over the square root of two, bounded to 3-16 m. Approach
drivers slide from their ordinary lane offset into the offset their turn needs
over the last 12 m of approach - kerb side for a right turn, centre for a left -
so the turn is prepared before the corner instead of cut at it. The selected
junction draws a bounded arc for each left and right movement, six segments per
arc, so the path is visible without unbounded vertex output.

## Persistence

Schema moves to **v17 / `bellwether-2028-03-v17`**; v16 and older files are
rejected with result 3. The pedestrian walk, clearance and switch are validated
inside the published bounds on load, like every other timing. Turning geometry is
derived and never saved.

## Verification - 26 September 2026

Measured with a headless probe outside the repository, built with Docker Zig
0.14.1 ReleaseSafe and run against the authored town, plus a Docker ReleaseSafe
build of the game and a JavaScript syntax check. The probe reports
`checks=20 failures=0`:

- 64 signalised junctions, and every one of them carries the default pedestrian
  stage.
- At junction 0 (3 arms) the cycle is 38.50 s with the stage and 33.00 s with it
  disabled, and the walk time round-trips at 9.5 s and clamps at both ends.
- Sampling a whole cycle: at most one arm is green at any instant, all 80 walk
  samples have every vehicle arm red, and 30 clearance samples appear. All 80
  walk samples admit the crossing and no clearance sample does.
- Movements across the 64 junctions: 260 straight, 200 left, 200 right, 287
  u-turn, and all 400 left and right turns carry a measured radius in range.
- A left turn is held while a vehicle is in the box and a right turn is not; a
  turning movement is held when somebody is on the crosswalk it turns into.
- After a simulated day the town still moves (2,451 people moving, 858 cars),
  with the pedestrian stage appearing every step it should.
- A v17 round trip writes 7,942,960 bytes and loads back with result 0 with all
  64 junctions and their pedestrian fields intact; a file tagged
  `bellwether-2028-02-v16` is rejected with result 3.

## Limits

The pedestrian stage is a cycle stage, not a per-crossing phase: all crossings
open together during the walk. There is no pedestrian countdown display, no
push-button request and no adaptive walk extension for slower walkers. Turning
geometry is a classification, a bounded radius and an approach lane offset; the
junction box itself is still traversed by transferring the vehicle from the
approach to the exit, so there is no swept path or turn-conflict matrix. A left
turn yields to any vehicle already in the box rather than to a specific oncoming
stream. Buses keep their own stop-line allowance and are not re-routed by a turn
lane. Crosswalk yielding depends on the walker's recorded crossing state, which
is recomputed each step from the movement rather than stored.
