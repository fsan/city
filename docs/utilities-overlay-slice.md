# Water and lighting overlays, and the Water & waste window

Bounded UI batch: the water, drainage and waste slice and the streetlighting
slice both published per-segment state to the browser but had no map layer and,
for water, no window of its own. This batch adds the two layers the previous
note said were missing and the menu that makes the water account readable.

Everything is presentation. `web/water.js`, `web/transport.js`,
`web/index.html` and `web/style.css` only read the ABI the simulation already
publishes; no rule, price or threshold moves out of Zig.

## Overlay modes

`set_overlay(value)` now clamps to 0-6:

- 0 off
- 1 street condition
- 2 traffic intensity and queues
- 3 pedestrian density
- 4 park condition
- 5 water, drainage and flooding (new)
- 6 street lighting (new)

Group 0 field 182 returns the mode the renderer is painting, so a probe can
confirm the clamp rather than infer it.

### Mode 5: water and drainage

Every eligible carriageway is painted by the share of its own drain capacity
that is working, then pulled towards a standing-water red by how much of the
day's rain it cannot drain. The layer also draws, as a diagram over the real
town, the intake's own structure, a pipe run from the intake node to each (updated: pipes now follow the real walk-graph run hop by hop and carry animated flow pulses on served runs; unserved districts keep the straight red diagram line)
district node, and a column at each district node whose height and colour are
that district's measured supply coverage. Water is a bounded graph-distance
pipe run, not drawn pipe geometry, so the run is a diagram rather than a
surveyed route. The intake is the one water structure with an authored
position; before this batch nothing in the renderer drew it.

### Mode 6: street lighting

Every carriageway is painted by its current night illumination after coverage.
A segment holding a failed column keeps an alarm tint, so a fault is readable
even in daylight when illumination itself is uneventful.

## The Water & waste window

`web/water.js` renders the **Water & waste** window (04 / UTILITIES, `U`):

- the intake: whether it is installed, its published position and nearest
  walk-graph node, whether it is lifting, faults and repairs, and today's rain;
- the running totals: districts served, mean coverage, the day's demand, served
  units and shortfall, pumping need/paid/lifetime, works today/lifetime;
- group 37 one row per district: demand, working units, coverage, the measured
  pipe run (or "unreachable"), residents and workplaces, with a locate button
  that focuses the district's own node;
- group 38 one row per street: drains installed against class capacity, working,
  blocked, coverage, today's flood factor and recorded clears;
- the drain control, which writes `water_set_drains(road, drains)` for the
  selected street and reports the works cost or the refusal;
- the waste account: the day's waste, collected, backlog, tipping today and
  lifetime, and the collection-round, blocked and cleared counters.

## ABI additions

Group 0 fields 178-181 add the intake's own published position: 178 whether it
is installed, 179/180 its world x/z, and 181 its nearest walk-graph node. Field
182 adds the overlay mode the renderer currently holds.

## Verification required

Docker ReleaseSafe build and served-asset identity; every served browser module
passes `node --check`; a focused probe outside the repository confirms that
`set_overlay(9)` lands on 6, that fields 178-181 name a real intake position and
node, that group 37 returns twelve districts whose demand sums to the published
total, and that group 38 returns a drain-eligible, drained and undrained mix.
No permanent test suite.
