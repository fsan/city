# Work routines and signal control (slice 13)

Bounded batch: make the traffic signals control the movement the player actually
sees, hold cars at their own stop line, and give each place of work its own
opening hours instead of one global three-shift rotation. No timetable, no
junction coordination search and no new facility types are added.

This note is written after the slice code, as the kickoff requires.

## Signals govern their own approach

A junction still greens exactly one arm at a time, but the gate now reads the
arm the driver is standing on rather than the arm they are about to take.
`signals.greenForApproach(node, approach, exit, elapsed)` tests the approach road
and falls back to the outgoing arm only when a driver is already at the node with
no approach (a bus leaving a stop). `transport.entryAllowed` and `transport.enter`
carry that approach road through from the movement loop, where the vehicle's
current segment is exactly its approach.

That is the whole reason the four lamps were unreadable: the head over an
approach was being checked against the cars *turning into* that arm, so the queue
beside a green lamp was held while traffic from elsewhere was admitted, and three
approaches could converge on one exit at once. Now the lamp over an approach
releases that approach, which is what a driver standing at it expects.

## The stop line is the head

Cars used to brake 1.0 m short of the node while the head was drawn 3.4 m back
down the arm, so a stopped car sat past its own light. The stop point is now the
head setback (`signals.head_setback` plus a small bus allowance), clamped so it
never collapses onto a very short segment. Queues stand before the light.

## Working hours belong to the workplace

`calendar.zig` gains a bounded `Facility` schedule table and
`inSchedule`/`facilityWindow`/`onFacilityShift`. Residents read the kind of the
building they actually work in:

- office 09:00-17:00 (the 9-5 the user asked for);
- hall 08:30-17:30;
- shop 09:00-17:00 or 12:00-20:00;
- clinic 07:00-15:00, 09:00-17:00 or 14:00-22:00;
- depot 06:00-14:00, 14:00-22:00 or 22:00-06:00 overnight.

A resident's existing `shift` byte selects the slot within their employer's
schedule, so no new persistent field and no schema bump were needed; the save
contract stays version 11. Overnight windows run across midnight, which is what
the depot's third slot needs.

## The departure bug that emptied the streets

`departureLead` computed the resident's shift start and then, in a loop, pushed
the target forward until it was strictly later than the current time. Every time
a resident sat at home during their own shift, the target became *tomorrow's*
shift start, so the function returned a positive wait and the resident waited a
full day. After the first day, when everybody had already finished their initial
trip, literally nobody departed again: the town drained to about 3,820 of 3,840
residents parked at home with zero cars on the road.

The fix is one branch: if the window that governs this resident is already
running, they leave now (`return 0`). The forward-stepping loop is only used when
they are genuinely early for an upcoming window.

## Verification - 23 September 2026

Measured with a headless probe (`/tmp/city_probe/main.zig`, a real copy of `src`,
compiled and run inside `city-compiler:latest`) stepping `dt = 1/30` and reporting
once per simulated hour for eight simulated days. Baseline and after traces are
kept at `/tmp/city_probe/BASELINE-trace.txt` and `/tmp/city_probe/after.txt`.

Peak people moving and peak active cars per day:

| day | before moving / cars | after moving / cars |
|-----|----------------------|---------------------|
| 0   | 2864 / 363           | 2864 / 363          |
| 1   | 1528 / 235           | 2218 / 144          |
| 2   | 283 / 68             | 2193 / 100          |
| 3   | 228 / 17             | 2214 / 84           |
| 4   | 227 / 3              | 2258 / 57           |
| 5   | 124 / 2              | 2264 / 46           |
| 6   | 41 / 0               | 2303 / 51           |
| 7   | 245 / 4              | 2346 / 48           |

Before, active cars reached zero on day 3 and stayed there; after, cars are on the
road every day and about 2,200 people are moving at the peak instead of decaying
to single digits. The 14:00 sample now shows a real working day: for example day 3
at 14:00 reports 1328 walking, 279 cycling and 962 at work, against 20 / 8 / 1
before.

- Docker Compose Zig 0.14.1 ReleaseSafe build and startup passed (`exit=0`) after
  every step of the slice; the JavaScript syntax check passed. No permanent tests
  or dependencies were added.
- One branch green at a time is unchanged; the change is which arm the gate reads,
  not how many may be green.

## Limits / next work

The first day still opens with one large simultaneous departure, because the
authored town starts everyone at home at 08:00 with a work destination already
assigned. It is left as-is: the user said a day-one jam is acceptable if the
network genuinely lacks capacity, and the authored town is the same one the
earlier slices were balanced against. Cars decline across the week (363 on day 0
against roughly 50 later) as residents learn the network and mode and affordability
settle; walking and cycling carry most of the load. Signals remain independent:
there is still no coordination search, no pedestrian-only phase and no bus
priority. Facilities without a listed schedule fall back to 09:00-17:00, and the
authored town has no night-shift shop, so that combination is untested.
