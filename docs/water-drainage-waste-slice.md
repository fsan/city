# Water, drainage and waste (slice 26, numbered item 18)

Bounded batch: give the authored river a real service layer. The town already
draws the river and makes it impassable; this slice makes it a utility. A water
works abstracts from the river, serves every district through a bounded pipe
network, and pays an electricity bill for pumping. Two drains carry surface
water off the streets and are cleared by a crew; when a drain is blocked the
segment floods after rain and slows traffic. The town also makes solid waste,
and a bounded collection round takes it away for a tipping fee. No sewer
chemistry, no treatment plant process model and no flood hydrology are added.

This note is written before the slice code, as the kickoff requires.

## The water works

`src/simulation/water.zig` keys one intake to the authored river and one supply
record to every district. The intake is placed on the real centreline, so it
moves with the river the renderer already draws. Each district's demand is the
published `demand_per_capita` rate times the residents the district actually
houses, plus a bounded share for its staffed workplaces, so a district only
draws what the town has built there.

Supply is `served / demand`. A district is served when the intake is working and
the pipe from the intake to the district's own node through the real walk graph
is within the published `max_pipe_run`. A district across the river with no
crossing, or beyond the pipe bound, is unserved and its residents show a real
service shortfall.

The intake loses pressure at most once per day from a deterministic function of
the day index, so a saved town replays the same outages. A repair is a bounded
municipal works cost booked through the ordinary ledger.

## Pumping and money

Every served unit draws a bounded amount of pumping electricity, published as
`electricity_per_unit`, billed daily and paid in bounded instalments by the
ordinary thirty-second operating pass, capped by the municipal cash actually
available. Water electricity is ledger **kind 18**; intake capital, repairs and
drain works are **kind 19**. Nothing goes into arrears and no money is created.

## Drains and flooding

Two drains are keyed to every eligible carriageway - the same "carries vehicles
and pedestrians, not a lane, not under works" rule the lighting layer uses.
`drain_set(road, drains)` designates 0-2 drains per segment and charges a
bounded capital cost for each new drain. A drain blocks at most once per segment
per day from a deterministic function of the segment and the day, exactly like a
lighting fault, and a crew clears at most a bounded number per operating pass.

Rain is a bounded function of the civic calendar: a deterministic daily wetness
in 0..1 driven by the day index. A blocked segment floods when the day's rain
exceeds the segment's drain coverage, and `flood_factor` raises driver travel
time on a flooded segment under the same bounded-penalty shape the incidents
layer uses. Flooding vanishes when the drains are clear or the day is dry.

## Solid waste

Every occupied home and staffed workplace makes a bounded daily amount of waste,
published per resident and per employee day. One collection round per day
crosses the town; each district's waste is either collected, tipping at the
published fee, or left as `uncollected` when the round's bounded capacity is
exhausted. Tipping fees are paid by the municipality as **kind 18** with the
pumping bill so the ledger keeps one utility account per day, and the fee is a
published policy number rather than a tender. Missed waste accumulates as a
visible backlog that a later day's round can clear.

## Reports

- **Group 0 fields 153-170** are the running totals: intake working, districts
  served, mean district coverage, the day's demand, served units and shortfall,
  the day's pumping electricity need and paid amount, lifetime pumping, intake
  faults and repairs today, works paid today and lifetime, mean drain coverage,
  drains installed, drains blocked now, the day's rain, the day's waste and
  collected amounts, and the waste backlog.
- **New group 37** reads one district's supply record by district index.
- **New group 38** reads one segment's drainage by road index.
- `water_set_drains(road, drains)` is the player command. The Streets tab gains
  a **Water, drainage and waste** block with the town totals, the selected
  segment's drains and a drain control.

## Persistence

Schema moves to **v21 / `bellwether-2028-07-v21`**; v20 and older files are
rejected with result 3. The district served/working counters, the drain counts
per segment, the per-segment clear counters and every running total are
serialized and validated field by field: a segment may not hold more drains than
its class allows, a district's served units may not exceed its demand, and a
drain may not exist where drainage is not eligible. Coverage, flooding and the
rain function are derived each step and never trusted from a file. The ledger
kind ceiling rises to 19.

## Verification required

Seeded district coverage on the authored town with a real mix of served and
short districts, intake working, capacity and eligibility refusal (including an
out-of-range road), capital charged once per new drain and nothing for a no-op,
demand matching the town's real residents and staff, pumping electricity
accruing with the served units and paid as kind 18, deterministic intake faults
and drain blockages, repair and clearing as kind 19, flood factor following rain
and drain coverage and vanishing when dry or drained, waste demand matching
residents and employees, collection with tipping as kind 18 and a bounded
backlog when capacity is short, and a v21 round trip returning 0 with a v20 file
returning 3. Docker ReleaseSafe build and served-asset identity; temporary
focused checks outside the repository; no permanent test suite.
