# Passenger service outcomes — complete

Implemented slice: measure what happens to residents who actually wait for a bus. Counts come from the fixed-step transitions in `residents.zig`, never from report polling. Every measurement is tied to a stable line route version and ordered stop index, using the existing current/previous stop observation records. This slice changes no fare, dispatch, routing, boarding-order or agreement-payment rule. The Transport Authority report and scalar ABI expose the measurements; no regularity score, penalty or payment link was added.

## Measurement rules

A wait starts on the first fixed step where the resident is at the boarding node with `mode == bus`, has not boarded, is not retiring with the line, and begins accumulating waiting time. The start timestamp and the set of full buses already seen are stored on the resident.

A wait completes only when `transport.board` succeeds. Completed wait seconds are current simulation time minus the start timestamp. Mean, minimum and maximum are computed only from completed waits; a completed wait is one observed journey, not a reliability promise.

A capacity denial is recorded once for each full, in-service bus encountered at the stop while an eligible resident is waiting. A per-resident bit mask prevents repeated fixed steps during the same dwell from counting the same bus more than once. A bus that leaves and later returns is a new encounter. Boarding a later bus does not erase the denial.

Abandonment reasons are distinguishable only where the simulation identifies them:

- `timeout`: the resident exceeded the existing 180-second wait limit while the line is scheduled.
- `off hours`: the same timeout limit was reached while the line's coverage window is closed.
- `fare`: the resident can no longer afford the fare.
- `route/service removal`: the waiting route version is withdrawn or replaced before boarding.

A wait that had already seen a full bus retains an `abandoned after capacity` flag. This is factual context; it does not prove that capacity alone caused the abandonment.

Current waiting is live and is not a stored counter. Completed and abandoned waits are stored counters. For a current record, `wait starts = completed + abandoned + currently waiting` is expected to reconcile for waits started after this slice is loaded.

## Route versions and resets

Passenger counters live in the bounded current and most recent retired stop observation records, so they carry the same route version, coverage window, stable node IDs and retirement rules as existing arrival observations. A route apply or withdrawal closes any wait still attached to the old route version before archiving, then the resident continues on the existing walking fallback. Company/fleet/lane changes alone do not create a new measurement record because they do not change the resident's route version. Refresh/Restart clears all records. Daytime closure/reopening does not discard completed evidence.

District comparison groups waits by the resident's stable home district. It counts observed bus waits, not every trip or every resident, and is session-level because the home district is stable across route versions. Districts with no observed waits show an explicit no-observation state.

## Save/load

In-progress waits (`bus_wait_start`, `bus_full_mask`) and every completed/passenger counter are included in the typed save state. The schema is bumped to version 2 with rules `bellwether-2026-09-v2`; version 1 files are rejected explicitly rather than migrated.

## Verification — 21 September 2026

- Docker Zig 0.14.1 ReleaseSafe build and static-server startup passed. The watch loop now builds with disposable local/global caches; an earlier shared-cache path could publish an old WASM while reporting success. JavaScript syntax checks passed.
- An isolated temporary Zig test forced a full bus at a stop and ran repeated fixed steps: one capacity denial was retained for that dwell, and district counts matched. It also checked route-removal, closed-hours, scheduled-timeout and fare-abandonment buckets and exact boarding completion.
- Served-WASM checks over real simulation transitions confirmed per-line `boardings == completed waits` where no retired history exists, `wait starts = completed + abandoned + current waiting`, passenger/rider conservation, operator account identities, route-edit attribution to the retired record, daytime closure/reopening abandonment, and save/load continuation of a live wait without duplicate counting.
- Save format version 2 preserves every new counter and in-progress wait. Version 1 files are rejected as incompatible.
- A fresh headless browser DOM probe loaded `http://localhost:8080/` and confirmed the passenger and district report controls are present with no JavaScript syntax/load error. That headless environment had no WebGL context, so live report population was verified through the scalar ABI and Node checks rather than a rendered screenshot.
- No permanent test suite, timetable, transfer policy, fleet purchase, contract penalty, autosave or backend work was added.
