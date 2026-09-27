# Service overlay: traffic incidents and freight (overlay mode 7)

The water and lighting batch added modes 5 and 6 and left two earlier slices
without any map layer. Incidents (slice 23) and freight (slice 24) both published
per-segment state to the browser and both had working panels, but nothing on the
map said where an incident was holding a lane or where the town's delivery fleet
actually stood. This batch closes that gap.

## The layer

`set_overlay` now clamps to **0-7**. Mode 7 is the service layer:

- `serviceColor(road)` paints a carriageway warmer the more of it is held - by
  `incidents.penalty(road)`, which sums the live severity of that segment's
  incidents, and by a lorry holding one of its loading bays. A clear segment
  stays a neutral slate, so the layer reads as "something is happening here"
  only where something is.
- `serviceOverlay()` stands the markers: one post per incident that has not
  cleared, as tall as its severity and coloured by kind (red collision, amber
  breakdown, violet obstruction, blue roadworks), with a lane bar across the
  held lane while a responder or the recovery crew is on scene; a badge on the
  apron of every contractor depot; a lorry for each delivery run in transit or
  unloading, offset to the side of the carriageway it parks on; and a kerbside
  bar on every segment whose bay a lorry currently holds.

Both layers read the same bounded rings the panels read, so the map and the
Incidents and Freight tabs always agree. This is a diagram over the real town,
not surveyed geometry: a lorry is drawn from its run's frontage road rather than
a tracked coordinate, and an incident post stands at its own segment node.

## The panels

- **Incidents and freight map** in the toolbar, `Y`, with a legend gradient from
  a clear kerb to a held segment and a Controls-window help row.
- The Freight and loading panel gains a **Delivery runs** table reading group 35
  newest first: run number, depot, customer, phase, goods, fee and a locate
  action per row. A run holding a bay shows "held now" instead of a locate
  button. Locate jumps to the customer's node, falling back to the frontage road.
- The Parking and street types panel gains a **Locate this street** button, so
  the parking readout can jump the camera to the street selected above it. The
  Reports -> Parking table already carried per-row locate links; this closes the
  same gap in the Transport tab.

## ABI

Group 0 field 182 already returned the overlay mode, so the clamp is verifiable
rather than inferred. Group 34 (incidents) and group 35 (freight runs) are
unchanged; this batch only reads them. `docs/abi.md` records mode 7.

## Verification required

The clamp to 7, group 0 field 182 reporting 7, the mode-7 surface colour and the
marker pass building without exceeding the vertex budget, the delivery-run table
reading real group-35 rows, a bay designation accepted on an eligible segment and
refused over the class capacity, and served-asset identity. Docker ReleaseSafe
build and `node --check`; temporary focused checks outside the repository; no
permanent test suite.
