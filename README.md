# Common Ground — Bellwether prototype

A fixed, populated town with a Zig simulation and isometric 3D geometry, compiled to WebAssembly and drawn by a small WebGL browser adapter. No JavaScript package manager or game engine dependency.

## Run

Install nothing beyond an existing Docker / Docker Compose setup:

```sh
make run
```

Use `make build` to compile without starting the web server, `make stop` to stop the services, and `make logs` to follow rebuilds. These commands use Docker, not the host Zig installation.

Open http://localhost:8080. Initial startup downloads the compiler image and waits for the first successful build. Zig 0.14.1 and its caches live in containers / Docker volumes. Both Apple Silicon and x86-64 are supported. The server binds only to localhost.

```sh
docker compose logs -f compiler        # build output
docker compose exec compiler zig fmt build.zig src
docker compose exec compiler zig build -Doptimize=ReleaseSafe
docker compose down                    # stop; retain compiler caches
```

Zig edits rebuild automatically; refresh the page after a successful build. HTML/CSS/JS edits are served immediately on refresh. Failed builds keep the last working WASM. The watch loop and `make build` use a disposable Zig cache for each build so host edits cannot be hidden by a stale Docker cache. Restart the compiler if file notifications are unavailable on your Docker filesystem: `docker compose restart compiler`.

## Play

- N: draw straight or curved roads. Z: parcel/block zoning. F: pedestrian density. See `docs/city-planning.md`.
- Drag or WASD / arrow keys: pan. Wheel: zoom. Q/E: rotate. R: recenter.
- Click a building, pedestrian or car: open the inspector. Selected trips mark their origin blue and destination amber. Right-click the map: contextual tools.
- P: reports, B: treasury, J: public works, I: inspector, H: controls. O: street overlay. T: transport, G: traffic queues.
- Escape discards an active route draft, otherwise closes a menu or the top window. Drag window headers to arrange reports.
- The bottom Management menu opens report submenus. All windows can be closed for a full city view.
- Space: pause/resume; 1/2/3: 1×/4×/16×. Time controls are in the top HUD.
- Open Reports → Streets, inspect a worn segment and prepare a repair offer. Review contractor prices, publish an offer, and follow assigned workers through mobilisation and delivery.
- Treasury separates residential/commercial tax policy, actual cash, committed funds, projected receipts and the transaction ledger. Apply tax drafts explicitly; collections occur at midnight.
- Reports include all 12 districts, paged resident/street registers, companies and recorded history. Click entries to inspect and locate them.
- Transport supports address-based bus stops, route dragging, line creation/withdrawal, fare caps, boarding subsidies, street bus/cycle allocations, crosswalk controls and bus service agreements with operator comparisons, delivery review and a session history. Transport Authority also reports real passenger wait starts, completed waits, full-bus capacity denials, abandonment causes and district comparison. Read `docs/transport.md` and `docs/passenger-outcomes-slice.md` for controls and assumptions.
- One day is eight real minutes at 1×. Hidden tabs do not catch up. Refresh / Restart town starts a new session. Use Management → Save / load town to export a local file or restore one. The simulation runs in browser WebAssembly; nginx serves files and holds no town state. No autosave or cloud storage.

## Structure

| Location | Responsibility |
| --- | --- |
| `src/main.zig` | WASM entry points, fixed-step clock, explicit browser ABI |
| `src/scene` | Fixed town layout, building kinds and world dimensions |
| `src/simulation` | Residents, multimodal trips, traffic, buses, municipal budget and maintenance |
| `src/render` | Camera, isometric projection, cuboids, NPC quads, picking |
| `web` | Browser input, WebGL upload and game-window presentation |
| `docker` | Compiler watch loop and static server configuration |
| `docs` | Slice, scene model and extension decisions |

Each folder has a short responsibility note. Read `docs/scene.md` before changing world coordinates or routes.

## Scope

3,840 residents, 288 seeded parcels, 12 neighbourhoods, 60 employers (including three street contractors), about 90 enclosed street blocks served by roughly 725 street segments, and terrain from 0–24 metres. Stable home/work assignments respect employer capacity. Residents travel through a slope-weighted graph and along front paths and supported steps. Crew assignments interrupt normal routines.

The management loop supports specific property taxes, a cash ledger, operating disbursements, protected work-order reserves, company acceptance/refusal, physical crew travel, delivered work, cancellations and settlement. Read `docs/economy.md` for the explicit economic assumptions and tuning rules. No automatic repair timer remains.

The renderer batches geometry into one depth-tested draw call. NPCs use six vertices each. Static geometry currently rebuilds each frame; caching / GPU camera projection / instancing are future profiling-led optimisations. The buffer holds 600,000 vertices (about 435,000 in the current smoke check in this slice).

The map now spans 1,320 × 1,040 metres with low-rise suburbs and room within blocks for future construction. Daylight shading and ground shadows are illustrative; property assessments use a simple neighbouring-height exposure proxy.

No complete household finances, intersection collision physics, elections, full service simulation, procedural generation or backend authority yet. Manual versioned save/load is available (town format version 7); see `docs/save-load-slice.md`. Routines are shortened and all residents are adult placeholders. Refreshed tabs restart the town. Contracts retain 64 orders per session; the ledger retains 1,024 entries and history retains 96 samples.

The HTTP container is a static server. Zig compilation stays inside Docker; no additional host toolchains are required. No test suite is included, as requested. The accepted design is in `docs/next-slice.md`; current implementation details are in `docs/scene.md`, `docs/economy.md`, `docs/transport.md` and `docs/abi.md`.

Operator working capital, driver coverage, fleet ownership and staffing are implemented; see [mechanics](docs/service-agreements.md), `docs/operator-capital-slice.md` and [fleet and staffing](docs/operator-workforce-slice.md). Accounts reconcile opening capital, fares, subsidies, agreement receipts, bus sales, purchases, recruitment, severance, maintenance, vehicle costs and wages. Offers choose daytime or all-day coverage. Transport Authority → Fleet & staff investment buys, sells and maintains individual buses and recruits or dismisses day and night drivers; quotes and acceptance read the same live pool, so a bus under maintenance or committed to another line is refused rather than double-booked.

Transport Authority also reports measured stop arrivals, eligible interarrival intervals and live waiting counts, with separate current/retired route records. See [stop regularity mechanics and verification](docs/stop-regularity-slice.md). These observations introduce no timetable or payment penalties.

Bus offers can optionally include a maximum interarrival review target, with agreement-specific evidence, overdue diagnostics and archived results. This does not change price or payment. See [target mechanics](docs/regularity-target-slice.md) and the [proposed numbered roadmap](docs/development-roadmap.md).


## Street types, parking and learned travel

Streets carry a class — lane, street or avenue — chosen in the road tool
(N) and priced at £18/£25/£40 per metre; class sets the car speed limit.
Free-flow speeds are proportional, with pedestrians slowest at 1.4 m/s,
cyclists at 4.2 m/s (5.0 in a protected cycle lane) and cars faster than both.
Walkers and cyclists now obey the same signals as cars: a turn across a junction
is admitted on the marked crossing's pedestrian phase, or on a gap when no
crossing is marked, with a bounded patience so nobody is stuck.

Bicycle parks and car parks are seeded where districts are busy, each with a
hard slot count; streets and avenues add kerbside car spaces priced in bands by
the movement actually observed on that segment, capped at £1.20. A traveller
aims for the place they expect to be free, falls back to the nearest free space
when it is full, and walks the rest of the way. Each resident keeps a very small
learned model of trip time per mode and time of day and of the chance of finding
a space, updated in batches when they arrive at work or home; mode choice and
the time to leave home read it. Ownership now decides the municipal assessment:
owners pay from the household, rented homes pay from the owner's collected
rent. Traffic lights and crosswalks are player-placed from the traffic panel;
each signal gives one branch green at a time and its green and amber times are
set in simulation seconds by clicking the light. Manual save files use schema
version 11, bellwether-2027-09-v11; older files are rejected. See [street types and parking](docs/street-types-parking-learning-slice.md).


## Housing and occupancy

Every authored home is one bounded housing unit with explicit tenure, daily
rent or ownership cost, occupancy, a property-owner reserve, arrears, a move
state and an application target. Housing payments are private money movements:
a household pays its unit after essentials, and any shortfall becomes explicit
unit arrears. A bounded daily rollover can move or displace households into
vacant units with a lower charge and a shorter commute; residents then travel
to the new address rather than teleporting. Manual save files now use schema
version 8, bellwether-2027-03-v8; older files are rejected. See
[housing mechanics](docs/housing-occupancy-slice.md).


## Transport contract enforcement

Agreed service can carry one bounded remedy. Delivery below 85% of the windowed
target after a whole day of expected service opens a 480-second cure; an
unresolved shortfall then accrues a service credit at GBP 0.18 per missing
bus-second, capped at 25% of the agreement price. The credit is paid only from
the operator's cash above the GBP 2.18 dispatch floor, and unpaid credit is
waived rather than turned into debt. Route, window or operator changes suspend
enforcement. Regularity intervals remain review-only. Ledger category 10
records credits received. Manual save files now use schema version 4,
bellwether-2026-10-v4; older files are rejected.


## Civic calendar and routine time

The shared clock now drives a bounded civic calendar: Monday-to-Sunday
weekdays, weekday/weekend routine phases, three resident shifts (day 06-14,
evening 14-22, night 22-06), local weekend errands and a weekly municipal
budget period. One day is still 480 simulation seconds and the transport
windows are unchanged (daytime 06:00-22:00, all-day 00:00-24:00). Weekly
budget summaries reconcile recorded ledger movements only and cannot create or
destroy money. Manual save files use schema version 5,
bellwether-2026-11-v5; older files are rejected.


## Households and shared budgets

Residents now belong to one bounded household per home. Members share a
balance and a daily budget: employed income is credited to the household, a
bounded essential expense is billed, and any unpaid essentials become visible
arrears rather than hidden debt. Fares, car running costs and car purchase
spend from the shared balance; the walking fallback is never blocked. Household
state is saved with schema version 6, bellwether-2027-01-v6; older files are
rejected.
