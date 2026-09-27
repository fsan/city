# Streetlighting (slice 25, numbered item 17)

Bounded plan: give every eligible carriageway a real lighting column count. The
authored town already has streetlights, so the layer is live from the first
frame; the player extends or upgrades coverage segment by segment. A lit segment
draws electricity every day, columns fail over time, and a failed column is
repaired for municipal money. Unlit road at night runs slower and is measurably
more likely to raise a collision. No mast arm, cable, photocell or electricity
market is modelled, and no money is created: electricity and works are city
expenses booked through the ordinary ledger.

This note is written before the slice code, as the kickoff requires.

## Columns and coverage

`src/simulation/lighting.zig` keys a column count to each real road segment.
Only a segment that carries vehicles and pedestrians, is not a lane and is not
under works can take columns. Capacity is bounded by street class: an avenue
takes four columns, a street takes two. `lighting_set(road, lamps)` designates
0 up to that capacity, and each newly installed column is charged to the
municipal ledger as a bounded capital cost.

Coverage is `working / required`, so a street with one of its two columns is
half lit. A column is either working or failed; a failed column still stands but
lights nothing.

The authored town seeds itself: a segment fronted by several lots is lit to
capacity, a segment with a few frontages gets a single column, and an empty
outer link gets none. That gives the day-one town a real mix of lit, partly lit
and dark segments instead of an inert layer that only exists once the player
acts.

## Electricity

Each working column draws a bounded daily amount, published as
`electricity_per_lamp_day`. A day's need is the working column count times that
rate; the ordinary thirty-second operating pass pays it in bounded instalments,
capped by the municipal cash actually available, and books the payment as ledger
**kind 16**. A town that cannot pay simply lights less next round through the
same cap; nothing goes into arrears and no money is created.

## Faults and repair

At each daily rollover a deterministic function of the segment and the day index
fails a bounded share of the working columns, so a saved town replays the same
faults. A failed column is counted once and stays failed until a crew reaches
it. The operating pass repairs at most a bounded number of columns per pass, in
segment order, each for a published repair cost booked as ledger **kind 17**
together with the capital cost of new columns. Repair spend is capped by
available municipal cash for the same reason electricity is.

## Night-time conditions

`darkness(time)` is a bounded function of the civic calendar: full night before
05:00 and after 21:00, zero between 07:00 and 19:00, and a linear dusk and dawn
ramp in between. `illumination(road)` is `coverage x darkness`, so a lit segment
is lit only when the sun is down and a dark segment is dark all night.

Two measured consequences follow. A driver on a dark segment runs under a
bounded night penalty, so an unlit street is genuinely slower after dusk. A
congested dark segment also raises a collision under a bounded risk multiplier,
so the incident layer sees more collisions where lighting is missing. Both
effects vanish at full coverage and in daylight.

## Reports

The ABI exposes lighting at segment, town and world level:

- **Group 0 fields 137-152** are the running totals: lit segments, columns
  installed, columns working, columns failed, mean coverage, mean night
  illumination, the day's electricity need and paid amount, lifetime
  electricity, faults today, repairs today, works paid today and lifetime,
  the column install total, the current darkness and the mean night collision
  risk multiplier.
- **New group 36** reads one segment's lighting record by road index: its
  district, street, class, length, eligibility, columns installed and required,
  columns working, columns failed, coverage, current illumination, its own
  daily electricity, its repair count and the current darkness.
- `lighting_set(road, lamps)` is the player command. The Streets tab gains a
  **Street lighting** block with the town totals, the selected segment's
  coverage and a column control.

## Persistence

Schema moves to **v20 / `bellwether-2028-06-v20`**; v19 and older files are
rejected with result 3. The installed column count, the working count, the
per-segment repair counters and every running total are serialized and
validated field by field: a segment may not hold more columns than its class
allows, more working columns than installed ones, or any column at all where
lighting is not eligible. Coverage, illumination and the collision multiplier
are derived each step and never trusted from a file. The ledger kind ceiling
rises to 17.

## Verification required

Seeded coverage on the authored town, capacity and eligibility refusal, capital
being charged once per new column, electricity accruing with the working count
and being paid as kind 16, deterministic faults, repair as kind 17, illumination
tracking darkness and coverage, the night speed penalty and collision multiplier
both vanishing at full coverage and in daylight, and a v20 round trip returning 0
with a v19 file returning 3. Docker ReleaseSafe build and served-asset identity;
temporary focused checks outside the repository; no permanent test suite.
