# Civic calendar and realistic routines (slice 6)

Bounded plan: introduce one shared simulation calendar for weekdays,
weekends, shifts, routine phases and a weekly municipal budget period, and
make resident travel respond to it through real transitions. Preserve fares,
passenger accounting, dispatch, agreement windows, ledger categories, protected
reserves and the existing 480-second day.

This note is written before the slice code, as the kickoff requires.

## Calendar contract

One day stays 480 simulation seconds, so one hour is 20 seconds and 00:00 is
`mod(time, 480) == 0`. A week is seven days (3,360 seconds). Day 1 is Monday,
so `weekday = floor(time / 480) % 7` with 0 Monday, 5 Saturday and 6 Sunday.
The existing daytime window stays 06:00-22:00 (seconds 120-440) and the
existing all-day window stays 00:00-24:00. No national holidays, seasons,
elections or political calendar are added.

Routine phases, all derived from the clock:

- 00:00-06:00 sleep: residents stay home except night-shift workers.
- 06:00-09:00 morning commute: day-shift workers travel to work; a bounded
  subset of non-workers makes a local errand on weekdays.
- 09:00-17:00 work/errand: day-shift workers remain at their employer; night
  workers sleep; evening-shift workers prepare or travel locally.
- 17:00-20:00 evening commute/errand: day-shift workers return home; evening
  workers travel to work; errands remain local.
- 20:00-22:00 leisure: residents stay home or take a short local trip.
- 22:00-24:00 night: night-shift workers travel to work; everyone else sleeps.

Employed residents receive a deterministic shift from their index: day
(06:00-14:00), evening (14:00-22:00) or night (22:00-06:00). Shifts are a
resident attribute, not a new labour market. Weekends suppress work commutes
and run a bounded local errand/leisure pattern instead. Every trip still uses
the existing mode choice, boarding, walking fallback and passenger accounting;
calendar changes must not teleport residents or alter conservation.

## Transport and operators

Transport demand, congestion and waiting outcomes respond to the phases through
the same resident transitions. Operator windows are unchanged: daytime service
is 06:00-22:00, all-day includes midnight, and the night endorsement covers
22:00-06:00. Contract target integrals continue to use the existing window
abstraction. A shift helper exposes the current operator shift for diagnostics.

## Municipal budget period

The bounded longer period is one week (3,360 simulation seconds). At each week
boundary the finance module closes a period summary from the ledger entries
recorded during that period: opening cash, receipts, expenses, closing cash and
the number of entries, retained for the newest 12 periods. Summaries are
derived from recorded transactions, not a second money path; weekly boundaries
never create, destroy or move money. A `next_week` deadline is explicit and
saved.

## Persistence

Calendar state, each resident's shift and routine phase, the week index, weekly
budget summaries and the `next_week` deadline are serialized and validated.
The schema becomes `version: 5`, `rules: "bellwether-2026-11-v5"`; version 4
and older files are rejected explicitly with result 3. No migration layer is
added.

## Verification required

Weekday and weekend routine transitions, shift boundaries, off-hours, day
rollover, week rollover, long-period ledger reconciliation, passenger
conservation, transport dispatch, agreement windows, accounting identities,
save/load continuation of every new field and browser/report markup. Docker
ReleaseSafe build and served-asset identity; no permanent test suite and no
elections, holidays, weather or life-stage systems.
