# Browser adapter
`main.js` loads WASM, forwards input and advances/draws frames. `renderer.js` uploads and draws the vertex batch. `ui.js` owns draggable window stacks, report tabs and context menus. `data.js` labels the scalar Zig ABI; `reports.js` renders live records and forwards validated commands. `transport.js` handles the transport window, street address selectors and stop/route dragging; its markup stays in `index.html`.

Simulation rules and geometry belong in Zig. HTML/CSS supply accessible overlays on the full-screen game canvas; there is no permanent side dashboard. Reports remain live without pausing and UI input does not move the map. No bundler or npm runtime dependencies. Refresh to load rebuilt WASM; each tab is an independent session.
