# Traffic incidents (slice 23, numbered item 15)

Bounded batch: give the road network explicit incidents - collisions,
breakdowns, obstructions and roadworks - with a reported, responding, clearing
and cleared life cycle, a real blocked lane, a bounded recovery cost and a
measured delay. No emergency-dispatch model, no insurance or liability and no
vehicle damage are added.

This note is written after the slice code, as the kickoff requires.

## The incident record

`src/simulation/incidents.zig` keys a bounded ring of 64 records to the real
road network. Each record names the segment, the junction node it sits at, the
lane, a severity 0-3, the kind and the four life-cycle times. Nothing creates a
second map: the renderer, the traffic panel and the snapshot all read the same
rows.

| Field | Meaning |
| --- | --- |
| number | one-based incident number, assigned once and never reused |
| kind | 0 collision, 1 breakdown, 2 obstruction, 3 roadworks |
| phase | 0 reported, 1 responding, 2 clearing, 3 cleared |
| road, node, lane | where the incident physically is |
| severity | 0-3, derived from the congestion that raised it |
| reported/responded/arrived/cleared | absolute simulation times of each transition |
| blocked_seconds | how long this incident held its lane |
| delay_total | the vehicle-delay it has cost the segment |
| responders | people on scene; two for a collision, one otherwise |
| cost | recovery money this incident has booked |

Response is 24 s plus 4 s per severity, clamped to 6-120 s; clearance is 40 s
plus 12 s per severity, clamped to 6-240 s. A cleared record keeps its counters
so the panel and the ledger can still explain what happened.

## Raising incidents

A collision is raised only when the segment is genuinely busy: at least two
vehicles on it and a measured queue pressure of at least 0.35. The decision is a
pure function of the live congestion and an integer hash of (road, node, step),
so a saved town replays the same sequence instead of depending on a
floating-point random stream. A town-wide cooldown of 45 simulation seconds
stops a burst of collisions on one step.

The player can raise any of the four kinds on the segment currently selected in
the Streets view with `incident_raise(kind, road, node, lane, severity)`, which
returns the expected recovery cost or -1. Severity is derived from the same
measured queue pressure the automatic rule uses.

## What a blocked lane does

While a responder or the recovery crew is on scene the incident holds its lane,
and every driver routed through that segment runs under the incident's speed
penalty: `1 / (1 + penalty(road) * 0.12)`, where the penalty scales with severity
and with whether the whole carriageway or one lane is held. The blocked lane and
its cost are visible per record, so the delay is attributable rather than a
blanket slowdown.

Recovery is a real municipal expense. The crew's bounded spend is accumulated
each step and booked through the ordinary ledger as **kind 15**, with no party
and no order. Recovery cost is GBP 900 for a collision, 320 for a breakdown, 240
for an obstruction and 480 for roadworks, times `1 + severity * 0.6`.

## ABI

**Group 0 fields 106-122**: 106 recorded, 107 active, 108 holding a lane, 109
raised, 110 cleared, 111 collisions, 112 responders on scene, 113 recovery
spend, 114 blocked lane-seconds, 115 measured vehicle-delay seconds, 116-118 the
newest incident's kind/phase/severity, and 119-122 the published response and
clearance bounds.

**New group 34** reads one incident, newest first: 0 number, 1 kind, 2 phase,
3 road, 4 node, 5 lane, 6 severity, 7-10 the reported/responded/arrived/cleared
times, 11 blocked lane-seconds, 12 measured delay, 13 responders, 14 recovery
cost, 15 whether the lane is blocked now and 16 the road class.

`web/transport.js` and `web/index.html` gain an **Incidents** tab with a live
view of every lane currently held, the full recorded ring, the running totals
and a report button for each kind.

## Persistence

Schema moves to **v18 / `bellwether-2028-04-v18`**; v17 and older files are
rejected with result 3. The incident ring, its numbering and its running totals
are serialized and validated field by field: a record must name a real segment
and node, the phases must be ordered in time and no number may repeat. Lane
penalties and the blocking state are derived each step and never trusted from a
file.

The ledger's kind ceiling rises to 15 with kind 15 named to its own party/order
rule (a city expense with no party and no order).

## Verification - 27 September 2026

Measured with a headless probe outside the repository, built with Docker Zig
0.14.1 ReleaseSafe and run against the authored town, plus a Docker ReleaseSafe
build of the game and a JavaScript syntax check. The probe reports
`checks=46 failures=0`:

- The ring starts empty; `max_incidents` is 64 and the response and clearance
  bounds are 6-120 s and 6-240 s.
- Recovery cost is monotonic in severity and a collision costs more than a
  breakdown.
- Raising a collision records one incident, does not block its lane while
  merely reported, and then walks reported -> responding -> clearing -> cleared.
  While a responder is on scene the lane is blocked, the penalty is positive and
  the other lane stays open; after clearing the penalty returns to zero, with
  non-zero blocked seconds and a booked cost.
- The collision decision is deterministic in the step, and a quiet segment never
  raises one.
- One simulated day of the real town raises 11 incidents, clears 8, all 11
  collisions, with GBP 5,124.48 of recovery spend, 643 blocked lane-seconds and
  152 vehicle-seconds of measured delay; 347 people and 776 vehicles are still
  moving at the end, and the counters never exceed their totals.
- ABI-visible incident state is readable and bounded.
- A v18 round trip writes 7,716,031 bytes and loads back with result 0; a file
  tagged `bellwether-2028-03-v17` is rejected with result 3.

## Limits

Incidents are a bounded queue and a life-cycle clock, not a dispatch model:
there is no ambulance, police or tow-truck journey, no queue that forms behind a
specific blocked lane, and no insurance, liability or vehicle damage. Severity
is derived from measured queue pressure rather than from an impact model. A
blocked lane slows every driver on its segment through the published penalty
instead of routing them around it, so a closed carriageway is not re-routed.
Recovery cost is a bounded policy number, not a contractor tender. Nothing here
creates or removes a vehicle, and pedestrians and cyclists are unaffected.
