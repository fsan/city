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

Zig edits rebuild automatically; refresh the page after a successful build. HTML/CSS/JS edits are served immediately on refresh. Failed builds keep the last working WASM. Restart the compiler if file notifications are unavailable on your Docker filesystem: `docker compose restart compiler`.

## Play

- Drag or WASD / arrow keys: pan. Wheel: zoom. Q/E: rotate. R: recenter.
- Click a building: open the inspector. Right-click the map: contextual tools.
- P: reports, B: treasury, J: public works, I: inspector, H: controls. O: street overlay. T: transport, G: traffic queues.
- Escape discards an active route draft, otherwise closes a menu or the top window. Drag window headers to arrange reports.
- The bottom Management menu opens report submenus. All windows can be closed for a full city view.
- Space: pause/resume; 1/2/3: 1×/4×/16×. Time controls are in the top HUD.
- Open Reports → Streets, inspect a worn segment and prepare a repair offer. Review contractor prices, publish an offer, and follow assigned workers through mobilisation and delivery.
- Treasury separates residential/commercial tax policy, actual cash, committed funds, projected receipts and the transaction ledger. Apply tax drafts explicitly; collections occur at midnight.
- Reports include all 12 districts, paged resident/street registers, companies and recorded history. Click entries to inspect and locate them.
- Transport supports address-based bus stops, route dragging, line creation/withdrawal, fare caps, boarding subsidies, and street bus/cycle allocations. Read `docs/transport.md` for controls and assumptions.
- One day is eight real minutes at 1×. Hidden tabs do not catch up. Refresh / Restart town starts a new session; there is no persistence yet.

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

3,840 residents, 288 authored lots, 12 neighbourhoods, 60 employers (including three street contractors), 610 street segments, and terrain from 0–24 metres. Stable home/work assignments respect employer capacity. Residents travel through a slope-weighted graph and along entrance ramps. Crew assignments interrupt normal routines.

The management loop supports specific property taxes, a cash ledger, operating disbursements, protected work-order reserves, company acceptance/refusal, physical crew travel, delivered work, cancellations and settlement. Read `docs/economy.md` for the explicit economic assumptions and tuning rules. No automatic repair timer remains.

The renderer batches geometry into one depth-tested draw call. NPCs use six vertices each. Static geometry currently rebuilds each frame; caching / GPU camera projection / instancing are future profiling-led optimisations. The buffer holds 600,000 vertices (typically about 223,000–275,000 in this slice).

No complete household finances, intersection collision physics, elections, full service simulation, procedural generation, save/load or backend authority yet. Routines are shortened and all residents are adult placeholders. Refreshed tabs restart the town. Contracts retain 64 orders per session; the ledger retains 1,024 entries and history retains 96 samples.

The HTTP container is a static server. Zig compilation stays inside Docker; no additional host toolchains are required. No test suite is included, as requested. The accepted design is in `docs/next-slice.md`; current implementation details are in `docs/scene.md`, `docs/economy.md`, `docs/transport.md` and `docs/abi.md`.
