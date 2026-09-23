# Traffic signals and crosswalks (slice 11)

Bounded plan: replace the old global horizontal/vertical light model with a
per-junction, per-arm signal that gives exactly one branch green at a time, set
the heads back from the corner like real life, let the traffic submenu place and
remove crosswalks and traffic lights by clicking the map, and let clicking a
light show and change its green and amber times in simulation seconds. No
timetable, coordination between junctions, pedestrian-only phase or signal
priority is added.

This note is written after the slice code, as the kickoff requires.

## Signal model

Each signalised junction holds one record: its node, its incident arms (the
streets that meet there), a green duration, an amber duration, a phase offset and
whether it is active. Every incident arm is its own phase, so a junction releases
one branch at a time and all the others wait. A junction with no record is
uncontrolled and its vehicles are never gated.

Green and amber are simulation seconds, and one simulation second is three
simulation minutes of city time. `signal_set_green(node, seconds)` and
`signal_set_yellow(node, seconds)` clamp to the minimum and maximum (green
0.5-60 s, amber 0.5-10 s) and return the applied value, or -1 when that junction
has no signal. The floor is half a simulation second, one and a half simulation
minutes of city time, so every value the player can type in the timing fields is
accepted instead of being quietly replaced.

Signal heads are drawn 3.4 m along their own arm and 2.6 m across it, so a light
stands back from the corner rather than on it. Every head renders its own lamp
colour and the selected head is highlighted. Crosswalk stripes are set back 3.6 m
from the junction.

## Walking and driving

Vehicles entering a signalised junction are gated by the state of the arm they
are about to take: green moves, amber clears, red holds. Vehicles also continue
to yield while a crosswalk on their path is occupied, as before.

Walkers and cyclists wait at a marked crossing unless a parallel arm of that
junction holds green - that is, unless the traffic they would cross is stopped.
Unmarked crossings keep the existing gap-based rule.

## Placement

The traffic panel arms a tool, then the player clicks the map. Placement snaps to
the nearest junction arm within 9 m for a signal, and to the nearest street
segment within 9 m for a crosswalk. A crosswalk also signalises a junction end
whose degree is 3 or more. While a tool is armed, moving the pointer previews the
snap target so the click lands where the player expects, and a tool disarms itself
after a successful placement.

Clicking a placed light selects it and shows its junction, arm, current phase,
arm count, green time, amber time, full cycle and the time until that branch
changes, in simulation seconds with a simulation-minutes reading alongside. The
green and amber inputs write back through the ABI, so the player sets the timing
by hand.

## Persistence

Placed signals are serialised and validated: junction count, node bounds, arm
count, green and amber bounds, the phase offset and each arm's road identity. The
save schema moves to version 10 / `bellwether-2027-05-v10` for this slice; slice 12
later moves it to version 11 / `bellwether-2027-09-v11`; version 9 and older
files are rejected with result 3. No migration layer is added. Loading clears any
selected head.

## Verification - 23 September 2026

- Docker Compose Zig 0.14.1 ReleaseSafe build and startup passed (`zig exit=0`);
  the JavaScript syntax check passed. No permanent tests or dependencies added.
- One branch green at a time held across 40 samples of all 29 signalised
  junctions: zero samples showed more than one green arm at a junction, and the
  maximum simultaneous green arms seen was 1.
- Setback: all 101 heads measured 4.28 m from their junction node (minimum, mean
  and maximum all 4.28 m), with zero heads inside 1 m of the corner.
- Cars obey the light: across 1383 car/junction samples, 267 vehicles were held
  while their arm was red and 202 drove while it was green. The 17 samples that
  moved without a green on their own arm were 12 distinct vehicles whose junction
  showed amber or a green on another arm, that is, vehicles clearing the junction
  rather than running a red.
- Timing: applying green 14.5 s returned 14.5 and moved the full cycle from 30 s
  to 49.5 s, read back through group 29.
- Placement snapping: 40 of 40 attempts to place a signal on a road that does not
  touch the requested node were refused and none were wrongly accepted; two
  legitimate placements were accepted with the node and street echoed back, and
  20 of 20 crosswalk flag toggles read back cleanly.
- Pedestrians wait: 1786 walkers and cyclists had stopped at a crossing
  (8361 cumulative waits) and 974 sampled instants caught someone waiting at a
  marked crossing whose junction is signalised. In every one of those 974
  samples no parallel arm held green, so the traffic the walker would cross was
  stopped; zero samples showed a walker waiting while their parallel arm had
  green.

## Limits / next work

Pedestrian waiting is now asserted directly (see the 974-sample check above), but
only for the current town's authored set of 50 crosswalk streets and 29
signalised junctions; unmarked crossings still use the pre-existing gap rule and
are not covered by that check. Signals are independent: there is no coordination between adjacent junctions,
no pedestrian-only phase, no turn arrows and no priority for buses or emergency
vehicles. Removing a signal leaves its crosswalk markings in place. Placement
previews are reported as text under the cursor; no ghost model is drawn on the
street.

# Traffic signals, part two (slice 12)

Bounded plan: make each individual light editable in detail (time on, time off,
and periods of the day when it blinks yellow, which means cars may cross slowly
as long as it is safe), give the player a manual switch for the blinking cross,
add a traffic-lights tab that lists every light and can apply one value to a
whole street or one junction, draw a map of which lights are coordinated with
each other and by how much delay, and leave a hook a police or firefighter
dispatcher can one day call to open or close the cross traffic. Police and
firefighters themselves are not simulated.

This note is written after the slice code, as the kickoff requires.

## Per-light timing

A junction now holds an all-red "off" time as well as green and amber, so a phase
is green, then amber, then a short all-red clearance before the next branch is
released. Off time clamps to 0-6 s, amber to 0.5-10 s and green to 0.5-60 s.
`signal_set_red(node, seconds)` returns the applied value or -1 when the junction
has no signal. The inspector shows green, amber, off and the full cycle, each as
simulation seconds with a simulation-minutes reading beside it, and the per-branch
lamp states for the selected light.

## Blinking yellow

A junction can blink yellow instead of cycling. The manual switch has three
positions: forced on, following the daily window, and forced onto the normal
cycle. `signal_flash_manual(node, mode)` sets one light and
`signal_flash_bulk(scope, key, mode)` sets a whole street (scope 1), one junction
(scope 2) or every light (scope 0), returning how many lights changed. A forced
setting beats the window, and an emergency preemption beats both.

The daily window is a start hour and an end hour of the simulation day; a start
later than the end runs overnight, which is what quiet-hour windows usually do.
`signal_set_flash_schedule(node, start_hour, end_hour, enabled)` stores it and
turns it on, and the inspector writes the same two hours.

While a light blinks yellow every approach may go, slowly and yielding. A driver
is admitted only when the junction box is clear of whoever went in ahead of them,
and approaching drivers are held to half their normal speed. Pedestrians and
cyclists keep priority at a yielding junction, because the traffic they would
cross is the traffic that must yield.

## Coordination map

`signal_link(from, to, delay)` makes the follower run its leader's cycle, held
back by that many simulation seconds, and joins the two into one coordination
group; `signal_unlink(from, to)` removes it and returns the follower to its own
phase. Group 30 exposes each link (leader, follower, delay, group ids) and the
traffic-lights tab draws them on a map with the delay labelled on the line, so the
player can see which lights act together and how far apart their actions are.

## Bulk editing

The traffic-lights tab lists every signalised junction with its green, amber, off
and flash state, and a click selects that light in the panel above. The
apply-to-many controls write one property across a scope: every light, every light
along one street, or one junction. `signal_apply_bulk(scope, key, field, value)`
covers green, amber, off time, the two window hours, the window switch and the
manual flash mode, and returns how many lights took the value. "Flash every
light" and "Restore every light" are the same call for the manual switch.

## Emergency alerts

`signal_alert(node, kind, seconds)` is the hook a real dispatcher will use. Kind
1 holds the cross traffic so an emergency vehicle can pass, 2 opens the junction
on flashing yellow, and 3 releases it back to its normal cycle. Alerts are queued
and applied at the next update, a timed hold expires by itself, and
`signal_alerts_pending()`, `signal_alerts_handled()` and `signal_alerts_pushed()`
report the queue. Police and firefighters are not simulated, so today the
player's own controls raise the alerts and the manual hold is what stops the other
traffic.

## Opening the inspector

Clicking a light on the map opens the traffic drawer before showing the
inspector. The inspector lives inside that drawer, so without bringing the drawer
forward the click appeared to do nothing at all; that was the reported fault.

## Verification - 23 September 2026

- Docker Compose Zig 0.14.1 ReleaseSafe build passed (`zig exit=0`) after every
  step of the slice, and the JavaScript syntax check passed. No permanent tests or
  dependencies were added.
- Manual flashing: forcing a light on returned flashing state 1 with mode 1 and
  every arm state 3, and following the window returned flashing 0 with mode 0.
- Daily window at hour 8 of the simulation day: window 22-6 did not flash,
  window 6-12 did flash, and disabling the window stopped it.
- Emergency alerts: a queued hold reported preempt 1 with all four arm states red,
  releasing cleared it back to 0, and an open alert put the junction on flashing
  yellow; four alerts were pushed and four handled.
- Bulk editing: applying an off time of 3.5 s to every light changed all 29
  junctions, the same edit scoped to one street changed 1, and scoped to one
  junction changed 1.
- Coordination: linking two junctions produced one link with a delay of 6 s read
  back from group 30, both junctions reported the same group, and unlinking
  removed the link and returned the follower's group to -1.
- Drivers at a flashing junction: over 1200 ticks at the busiest signalised node,
  cars still entered and left the junction, and the most vehicles committed at
  once was 1, the same as a normally cycling junction. Over 3000 ticks the three
  busiest junctions passed 3, 3 and 7 cars while blinking against 6, 8 and 4 while
  cycling, and the junctions left alone passed 60 cars against 44 while the three
  busiest blinked.
- Emergency hold: no car entered the held junction during 600 ticks.
- One branch at a time still holds: 900 samples of normal cycling at one junction
  showed zero instants with more than one green branch.
- Walkers keep crossing a blinking junction: 63878 cumulative walker crossings
  were logged during a flashing window against 39075 during a comparable normal
  window.
- Clicking a light still resolves after the slice: a screen-space sweep over the
  focus area returned 87 hits, and the whole-viewport sweep still hit an
  authored head.
- Timing fields keep what the player types: the inspector refreshes twice a real
  second, but a half-typed green, amber or off value survives the refresh and is
  applied on Apply; the floors are 0.5 s for green and amber and 0 s for the off
  time, so 1.0 and 0.5 are stored as typed instead of being replaced by 2 s.
- Windows open clear of the click: clicks on the map, the toolbar buttons and the
  report rows opened the building inspector, the traffic drawer, the reports,
  treasury, works and help windows, and the clicked point stayed visible under
  every one of them. Four viewport sweeps (900x650, 1024x700, 1280x800 and
  1440x900) opened 27 windows from map clicks without covering the click, and a
  click on a light at 624,430 opened the traffic drawer with its timing inspector
  while the light itself stayed on top at the click point.
- Clicking a light no longer drags the map: revealing the timing inspector used to
  call scrollIntoView, which scrolled the map container too (overflow: hidden is
  still programmatically scrollable), so the whole view slid sideways and the
  drawer landed over the light. The traffic drawer and the works panel now scroll
  only their own window body, and a light click leaves the map at scroll zero.
- Save schema: the round trip writes version 11 / `bellwether-2027-09-v11`,
  serialises the new junction fields and loads back cleanly with all 29 junctions
  and 101 heads intact; version 10 and older files are rejected with result 3.

## Limits / next work

The coordination map shows the links the player creates; it does not infer
coordination from geometry, and there is still no offset search that finds a green
wave on its own. A hold is a blanket stop of the cross traffic rather than a
signal given to one approach, because the emergency vehicle that would need that
signal is not simulated. Flashing yellow reduces junction throughput on purpose
(one driver at a time, at half speed), so a street left blinking all day will
carry less traffic than one that cycles. Bulk edits write one property at a time,
so setting every property of a street takes one pass per property.
