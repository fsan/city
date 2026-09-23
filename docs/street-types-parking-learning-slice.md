# Street types, parking and learned travel (slice 10)

Bounded plan: give the road tool explicit street classes, add bike and car
parking as real facilities with bounded capacity, make walking, cycling and
driving obey the same signals and crosswalks, and let every resident keep a
very small learned model of trip time and parking availability that feeds the
mode and departure-time decision. No freight, delivery or logistics model is
added.

This note is written before the slice code, as the kickoff requires.

## Street types

Each street segment gains a class: `lane`, `street` or `avenue`. The road tool
chooses the class, which sets the width used for rendering, the free-flow speed
limit, whether kerbside parking is allowed, and the construction price per
metre. Seeded streets are classified from their position: the two central axes
are avenues, the outer ring is lanes, and the rest are ordinary streets. A
segment can still carry a bus or cycle allocation independently of its class.

## Speeds

The simulation uses proportionally realistic free-flow speeds: pedestrians are
slowest at about 1.3 m/s, cyclists at about 4.4 m/s, and cars between 5.5 and
9 m/s depending on the street class, both reduced by grade, works and road
condition. Cyclists stay below cars on every class and pedestrians stay below
cyclists. A protected cycle lane raises the bicycle speed; bus speeds are
unchanged so existing agreements keep their meaning.

## Signals and crosswalks

Cars already stop at red. Pedestrians and cyclists now stop as well. At a
signalled junction, a walker or rider crossing an arm of the junction is
admitted only while the pedestrian phase for that crossing is green, which is
the phase parallel to the traffic that is moving. Where no crosswalk is marked
at the junction, the crosser must instead wait for a gap in the crossing
traffic. A bounded patience limit stops a crosser from being stuck forever: a
very long wait is recorded and then the crosser proceeds with care. Waiting is
observable per resident.

## Parking facilities

`parking.zig` owns the facilities. Two new building kinds are seeded:
`bike_park` and `parking_lot`. Bicycle parking is concentrated where the
district has employers and housing density, with a small slot count in quiet
districts and a larger one in busy districts; each facility has a maximum
number of slots. Car parks are larger and fewer.

Kerbside car parking exists on avenues and busy streets only. Its price is
banded by the observed movement of that segment and capped at a documented
maximum; quiet segments are free but still bounded. Every parking area has a
hard capacity, so parking can genuinely fail.

## Parking search and the walk leg

A cyclist rides to a bike-parking facility near the destination, parks there and
walks the rest of the way. A driver does the same with a car park or a kerbside
space. If the first choice is full the traveller falls back to the nearest
facility with a free slot, and the search is recorded. A bicycle stored at home
is taken inside the home; a journey that ends at home parks on the street in
this slice, as requested.

## The learned model

Each resident keeps a deliberately tiny model:

- mean observed trip time per mode and per departure-time bucket (four buckets
  per day), used for the mode choice and for choosing when to leave home.
- an estimated chance of finding a free slot per facility and per arrival-time
  bucket, updated as a simple exponential Markov estimate from the resident's
  own attempts.

Both are updated in batches when residents arrive at work or home, and neither
needs more than a handful of numbers per resident. The mode choice uses the
learned time where the resident has one and falls back to the analytic estimate
otherwise, plus the cost, the expected parking search and the learned
availability. A car-owning resident with a car preference therefore drives when
that is genuinely the best option for their own observed experience.

## Ownership

Residents may own a bicycle, own a car, own both or own neither. Households own
or rent their home. Tenure changes the municipal assessment: an owned home is
billed to its household at the residential rate, and a rented home is billed to
the property owner from the rent the owner has actually collected. Unpaid
assessment becomes explicit municipal arrears, never hidden debt.

## Persistence

Street classes, parking facilities, slot occupancy, kerbside prices, per-resident
learned times and parking estimates, and tenure-driven tax state are serialized
and validated. Save schema becomes `version: 9`,
`rules: "bellwether-2027-04-v9"`; version 8 and older files are rejected
explicitly with result 3. No migration layer is added. (Slice 11 later moved the
schema to version 10 / `bellwether-2027-05-v10` in that slice; slice 12 moves
it to version 11 / `bellwether-2027-09-v11`; see
[traffic signals](traffic-signals-slice.md).)

## Verification required

Street-class construction and rejection, proportional speeds, signal and
crosswalk compliance for cars, cyclists and pedestrians, bike and car parking
capacity, fallback to the nearest free facility, learned availability updating
after a full or successful attempt, batch learning of trip times, departure-time
choice, ownership and tenure tax effects, parking search effects on mode choice,
car owners driving to work, passenger conservation, ledger and account
reconciliation, save/load of every new field, and browser/report behaviour.
Docker ReleaseSafe build and served-asset identity; temporary focused checks
outside the repository; no permanent test suite.

## Implementation record

Implemented across `src/simulation/travel.zig` (new), `src/simulation/parking.zig`
(new), `src/scene/city.zig`, `src/simulation/transport.zig`,
`src/simulation/residents.zig`, `src/simulation/roads.zig`,
`src/simulation/finance.zig`, `src/simulation/game.zig`, `src/main.zig`,
`src/simulation/persistence.zig` and `web/`.

**Street types.** `Road.class` is 0 lane, 1 street, 2 avenue. The seeded
network classifies the two central axes as avenues, the outer ring as lanes and
everything else as a street. The road tool offers the class and prices it at
£18/£25/£40 per metre. Class sets the car limit through
`travel.classSpeed` (0.82/1.0/1.18 of the 7 m/s base) and a lane never allows
kerbside parking.

**Speeds.** Walk 1.4 m/s, cycle 4.2 m/s (5.0 in a protected cycle lane), car
7 m/s scaled by class and reduced by grade, works and condition, bus 5.5 m/s.
Pedestrians are slowest and cyclists stay below cars on every class.

**Signals and crosswalks.** Cars already stopped at red; walkers and cyclists
now wait as well. `residents.crossingWait` admits a turn across a junction only
while the marked crossing's parallel phase is green, or else while no vehicle is
within 14 m of the junction, with a 30-second bounded patience. Waiting is
recorded per resident (`cross_waits`, `crossings`) and cars yield at a crosswalk
while somebody is actually on it (`transport.crossing_active`).

**Parking.** `parking.zig` seeds bicycle parks and car parks from converted
park/vacant buildings, by district density, with a per-facility slot count and
a lifetime identity across rebuilds. Streets and avenues add kerbside car
spaces; their price is banded by the segment's smoothed movement
(`transport.movement`, a class baseline plus measured occupancy) and capped at
£1.20. Fees are paid from the household and recorded as municipal ledger kind
11, so parking revenue reconciles with the treasury.

**Search and the walk leg.** `residents.parkChoice` scores each place by the
walk to the destination plus an expected search caused by the resident's
remembered chance of a free slot; `settleParking` takes the planned space, or
falls back to the nearest place with a free slot, or keeps the vehicle and walks
on when nothing is free. A cyclist rides the kerb-side lane of their own
direction of travel, parks, then walks the rest; a driver does the same via a
car park or kerbside space. The access walk to a vehicle parked elsewhere is an
ordinary walking leg before the vehicle leg.

**The learned model.** Each resident stores mean observed trip seconds per mode
and per departure bucket (two-second units, eight samples) plus a three-place
memory of parking probabilities per arrival bucket. A trip records two separate
buckets: the departure bucket averages the trip time, and the arrival bucket
updates the chance of finding a space, so availability reflects the time the
traveller is actually near the facility rather than when they set out. `travel.observeChance`
moves the remembered chance a fixed share toward the last outcome. Both models
are folded in by `residents.flushBatch()` once per fixed step for the arrivals
that just completed, never inside the movement loop. Mode choice uses the
learned mean where the resident has one, plus money cost, expected parking
search and learned availability; a car-owning household that bought a car
carries a bounded preference bonus. Departure time is planned from the learned
commute time, scaled into the bounded pre-shift window because a day is
compressed into 480 seconds.

**Departure time.** A resident leaving home for work plans the departure from
their own learned commute: `departureLead` takes the fastest mode they could
actually use (walking, or cycling and driving where they own the vehicle), reads
that mode's mean for the departure bucket, and scales it into the pre-shift
window. A longer learned commute therefore produces an earlier departure, and
a resident with a car gets the shorter car estimate.

**Ownership and tax.** A resident may own a bicycle, a car, both or neither.
Housing tenure now drives the municipal assessment in `finance.daily`: an
owner-occupier pays the residential rate from the shared household balance; a
rented home is paid by its property owner out of rent actually collected.
Unpaid assessment stays as explicit municipal arrears.

## Verification — 22 September 2026

Docker Compose Zig 0.14.1 ReleaseSafe build passed and the served
`/build/city.wasm` hash matched the build volume byte-for-byte. JavaScript
syntax checks passed for every module. No permanent test suite was added;
temporary node probes against the served WASM live in `/tmp/cityprobe`.

Measured on the served build:

- 396 parking facilities, 1,918 spaces (1,078 bicycle, 840 cars/kerbside);
  3,480 attempts with 2,283 parked, 2,510 searched after a full first choice
  and 1,197 walked on when nothing was free.
- Car mode share rose from a handful of active trips to 230 after a route
  reachability defect was fixed (`walkSeconds`/`rideSeconds`/`driveSeconds`
  treated an unreachable pair as a short walk, parking cars across town).
- 3,827 residents held a learned trip time and 363 car owners all carried the
  car preference; `plan_mode` showed 1,488 walk / 1,477 cycle / 360 car plans in
  the morning peak.
- 2,061 residents waited at a crossing and 2,073 crossed; street classes seeded
  139 lanes / 286 streets / 78 avenues.
- Tenure tax: after one day £9,886.47 of residential assessment was recorded,
  a rented home's owner reserve paid its assessment and municipal cash
  reconciled; rent collected that day was £3,496.20.
- Save schema v9 (history; the current schema is v10) round-tripped
  byte-identically at 12.35 MB after 200 simulated
  seconds, and a 22-road expanded graph still fitted the 16 MiB cap at
  13.48 MB.

## Remaining limits

Kerbside spaces are one facility per eligible segment anchored at its first
node, not per-metre bay geometry. Building bike parks and car parks are
converted green/vacant parcels, not player-built; the road tool builds street
classes but there is no parking-construction tool yet. The learned model is
per-resident, but parking probability is remembered only for the few places the
resident actually used, and the aggregate observation is a simple exponential
estimate, not a calibrated occupancy model. Departure-time scaling (a fifth of
the learned time, bounded to 2-45 seconds) is a deliberate fit to the compressed
480-second day: the ordering by mode and by learned duration is preserved, but
a real-time commute cannot be expressed as a clock time in a day that is only
480 seconds long. Bus mode keeps its existing direct-journey estimate. Cars still
select a parking place before departure rather than searching while driving.
