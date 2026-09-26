# UI navigation and info-tip batch

Not a numbered development item: a browser-side consolidation requested
directly by the user. No simulation rules change.

## What changed

- **Transport authority reorganised into tabs**: Lines (fares, bus lines,
  route editing), Agreements (offers, comparison, regularity, closed
  register), Fleet & staff (purchase/sale/maintenance, roster), Stops &
  riders (arrival observations, waiting outcomes, district comparison),
  Streets (lane allocation, parking summary, queue hotspots), Signals
  (placement tools plus the existing three signal views). The window keeps
  every element id; panels toggle visibility and `update()` refreshes only
  the visible panel so hidden tables stop rebuilding twice a second.
- **Treasury tabs**: Policy (tax drafts, funding, projections, weekly period,
  household and employment notes) and Ledger (bounded retained ledger). The
  ledger table stops rebuilding while the Policy tab is shown.
- **Reports gains Households and Parking tabs.** Households reads group 25
  per home (balance, income, essentials, arrears, last-day pay). Parking
  reads group 28 per facility (kind, slots, occupancy, price, four learned
  availability buckets; chances are on the simulation's u8 scale: 255 means a
  space was found, 140 is the untried default).
- **A park condition overlay is now reachable**: K in the toolbar and the
  "Parks K" toggle call `toggleParkCondition()`; the park planner's address
  cells now locate the green lot on the map.
- **Explanatory prose moved into info tips**: a small "?" control with
  hover/focus tooltips next to the heading or field it explains. Live status
  text (summaries, refusals, state lines) stays on the page.
- **Long registries scroll**: district, resident, company, housing,
  household, parking, history and ledger tables sit in `.table-scroll tall`
  panes with themed scrollbars; number inputs step with the mouse wheel and
  focused selects cycle.
- **Inspector fixes**: housing rows now appear only on actual homes (the
  record's present flag, so apartments are covered too); green lots show a
  parks block (condition, visits, catchment, care) read from group 32;
  "sun exposure (assessment proxy)" is now labelled measured sunlight.
- **New read-only command** `parks_quote(parcel, kind)`: the exact cost
  `parks_create` would charge, so the planner displays the conversion price
  before the player commits. Verified parity with `parks_create` for all
  three kinds over the container-built WASM.
- **Key remap**: planning kept N/Z/P/G (roads, zoning, permits, parks);
  Reports moved to C, the traffic overlay to V, park condition to K. The
  previous documentation said P opened Reports, but planning's P (permits)
  consumed the key first, so Reports had no working shortcut.

## Verification

Docker build publishes the new WASM; `node --check` passes for every web
module; a Node probe exercised `parks_quote` against `parks_create` on all
three kinds and all three city plans, including refusal cases (built lot,
unzoned lot, invalid kind). Browser walkthrough (in-app browser on the local
server): every window opens, every tab switches and refreshes, the park
overlay colours the map, wheel scrubbing changes the fare cap and select
wheel-cycling works only while focused.
