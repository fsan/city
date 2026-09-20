# Management slice: governing a working town

Implemented baseline: 288 lots, 12 districts, 3,840 residents, terrain and connected routes, reports, property taxes, a municipal ledger and company-delivered street orders. This document records the agreed scope; `scene.md` and `economy.md` describe current mechanics and limits.

## Agreed direction
The player governs through information, policy, budgets and institutions. A click must not guarantee a timed reward. Outcomes follow resources, people, incentives and the work actually performed. The automatic repair action has been replaced by the work-order system.

## Interface contract
The city occupies the full viewport. Keep only a compact resource/time HUD and tool strip permanently visible. Reports, treasury, public works and inspectors open as non-modal game windows, with consistent headers, close buttons, keyboard shortcuts and movable positions. Multiple reports can coexist. Opening a window does not implicitly pause simulation.

Use dense, readable tables, tabs, breakdowns and contextual links. City totals should lead to neighbourhoods, buildings, companies and individual people. Where a system is absent, state that limitation; do not invent report data. Never add a dashboard tile solely to imply an unimplemented feature exists.

Right-click on the map belongs to the game and opens contextual tools. Context actions should reflect the selected object and current mode. Escape closes the foremost transient menu, then the foremost window. UI input must not fall through into map movement. Mouse alternatives and shortcut hints accompany commands; text fields and native selectors retain their normal keys.

The supplied Songs of Syx screenshots establish interaction references: full-world backdrop, closable information windows, report tabs, adjacent comparisons and nested tool menus. They are not assets to reproduce. Use an original modern municipal interface with charcoal / steel panels, restrained warm accents and legible typography.

## Larger authored scene
Target the next playable town at roughly 12 neighbourhoods, 250–400 buildings and 3,000–5,000 residents. These are content targets subject to profiling, not measured supported capacities. Keep scene data hand-editable and fixed; no city generator is required.

Replace implicit grid assumptions with explicit street nodes and segments. Each segment carries endpoints, length, slope, condition and travel permissions. Terrain supplies elevation; buildings have ground elevation and entry points connected to streets. Roads must connect across grades without people walking through slopes or floating over them. Begin with a few authored terraces and connecting slopes. Pedestrian route cost should include distance and grade; leave vehicle-specific behaviour for its own increment.

Separate terrain, parcels, buildings, street network, resident positions and render instances. Keep stable identifiers across reports and selection. Larger scene bounds must drive camera limits, clipping and render capacities rather than today's hardcoded 48-unit map.

## Reports before interventions
First reporting domains: residents / employment, local mobility, infrastructure condition and municipal finance. Show actual versus projected values separately. Include units, time period, filters, and an explanation for each important derived measure. Capture periodic snapshots for trends; never manufacture a historical chart on first load.

A resident inspector should identify home, employer, current destination, route and current activity. Company inspection should show employees, available crews, relevant capabilities, current jobs, cash and reasons for declining work. Employment counts must come from assignments and capacity, not decorative counters.

## Municipal finance
Start with separate residential-property and commercial-property taxes, each with an explicit assessed base and rate. Keep recurrent operating budgets distinct from capital investment. All cash changes create ledger entries with time, category, amount, source / recipient and any associated order ID.

Track cash, reserved commitments and uncommitted funds separately. A tax rate changes projected receipts; actual collection credits the treasury on a defined calendar. State the collection cadence in the UI. Show household / business obligations before introducing more elaborate tax responses. Avoid multiplying a generic revenue constant by a slider.

Draft policy changes show their estimated impact and take effect only when the player applies them. Reject commitments above available funding with an explanation; do not silently create money or debt.

## Work-order lifecycle
1. Draft: choose work type, scope, location, offered price and reserved budget; see estimated need.
2. Offered: qualified local companies evaluate expected cost, available crews and acceptable margin. An offer may remain unaccepted. Record reasons such as insufficient capacity, missing capability, inaccessible site or unattractive price.
3. Accepted: reserve the contract value and assign a contractor and crew. Prevent double-booked crews. Funding and contractual scope can no longer change silently.
4. Mobilising: workers travel to the connected site. Travel delay is visible.
5. In progress: work units accumulate only while the required crew is present and prerequisites hold. Disruption applies where works are active. Paused or blocked work exposes a reason.
6. Completed: apply the improvement from delivered work, settle payment, release any remaining reservation and return the crew to availability.
7. Cancelled: withdraw unaccepted offers freely; cancellation after acceptance follows explicit compensation / payment for completed work. Preserve the ledger and audit trail.

Allow revising an unaccepted price, comparing companies, tracking delivery and inspecting blockers. Begin with one work type (street repair) and a few local contractors. Construction materials, subcontracting, legal disputes and competitive tender rounds are later extensions.

## Visual direction
Retain placeholder geometry for now. Future cities should use restrained urban materials: asphalt, concrete, brick, painted render, glass and metal, with modest variation within each category. Distinguish building uses through massing, height, roof form, frontage and material combinations. Avoid both uniformly monochrome cities and one bright pastel colour per use. Reserve strong colour for selections, warnings and analytical overlays. Terrain height must be visible in the scene, not only stored in data.

## Implementation order and completion
First establish the interface and interaction baseline; then expand scene / terrain / routes, expose resident and company reports, add the budget ledger and tax bases, and finally connect companies and crews to work orders. Keep each stage playable.

The management slice is complete when the player can diagnose an underserved area, inspect affected residents and routes, adjust a specific financing policy, offer repair work, observe acceptance or an explained refusal, and follow workers and money through delivery. Current UI work alone does not meet this milestone. No test suite is requested yet; use builds and focused manual gameplay checks while implementing.


## Follow-on phases after September visual / mobility repairs

The first bus-operator agreement increment is now playable; see `service-agreements.md`. Next extend this with persistent agreement history, explicit working capital and driver shifts, headway/stop-completion targets, procurement comparison and service failure remedies. Keep route demand and rider continuity visible.

Preserve the new 360×320 land area, vacant parcels and low-rise suburbs when introducing player-built streets and parks. Add construction access, terrain grading and foundation costs for buildings while allowing slope parks. Then introduce schools, hospitals and other civic services with physical staff and catchments. Keep population near 3,840 until these systems justify growth.

Traffic safety follows explicit crossing/turn geometry: driver yielding, pedestrian signal phases, swept vehicle footprints, collisions/accidents, incident clearance and blocked-lane queues. Night safety needs streetlight coverage, visibility, pedestrian/car risk, power and maintenance budgets. These are future simulation policies, not random cosmetic events. Refine solar assessment from the current height proxy to sampled seasonal obstruction and construction-company valuation decisions. Save/load should precede longer planning sessions.
