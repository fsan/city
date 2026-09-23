import {createAgreements} from "./agreements.js";
import {streetName} from "./data.js";
// Game windows and map gestures; all traffic, fares and passengers live in Zig.
export function createTransport(game, ui) {
  const $ = (id) => document.getElementById(id);
  const r = (group, id, field) => game.read(group, id, field);
  const money = (n) => `£${n.toFixed(2)}`;
  const decoder = new TextDecoder();
  const districtName = (id) => decoder.decode(new Uint8Array(game.memory.buffer, game.name_pointer(id), game.name_length(id)));
  let nodes = Array.from({ length: r(9, 0, 4) }, (_, id) => ({
    id,
    x: r(11, id, 0),
    z: r(11, id, 1),
  }));
  const validStop = id => r(11,id,9) === 1;
  let stopNodes = nodes.filter((n) => validStop(n.id));
  const address = id => `${r(11,id,6)} ${streetName(r(11,id,5))} · stop ${id+1}`;
  let roads = Array.from({ length: r(0, 0, 15) }, (_, id) => ({
    id,
    a: r(5, id, 0),
    b: r(5, id, 1),
  }));
  const heat = document.createElementNS("http://www.w3.org/2000/svg","svg");
  heat.setAttribute("aria-label","Traffic intensity and zones of influence");
  heat.style.cssText = "position:fixed;inset:0;width:100%;height:100%;pointer-events:none;z-index:1";
  document.body.append(heat);
  let heatFrame = 0;
  let selected = -1,
    draft = null,
    gesture = null,
    overlay = 0,
    tool = null,
    signal = -1;
  const message = (text) => ($("transport-message").textContent = text);
  // Slice 11: traffic-signal placement tools and the selected-light inspector.
  const signalButton = $("signal-place"), crosswalkButton = $("crosswalk-place"), crosswalkRemoveButton = $("crosswalk-remove");
  const inspector = $("signal-inspector"), greenInput = $("signal-green"), yellowInput = $("signal-yellow");
  const arm = (next) => {
    tool = tool === next ? null : next;
    signalButton.setAttribute("aria-pressed", tool === "signal" ? "true" : "false");
    crosswalkButton.setAttribute("aria-pressed", tool === "crosswalk" ? "true" : "false");
    crosswalkRemoveButton.setAttribute("aria-pressed", tool === "crosswalk-remove" ? "true" : "false");
    message(tool === "signal" ? "Click a junction arm to place a traffic light."
      : tool === "crosswalk" ? "Click a street to add a crosswalk."
      : tool === "crosswalk-remove" ? "Click a street to remove its crosswalk."
      : "");
    return tool;
  };
  signalButton.onclick = () => arm("signal");
  crosswalkButton.onclick = () => arm("crosswalk");
  crosswalkRemoveButton.onclick = () => arm("crosswalk-remove");
  function showSignal(head) {
    signal = head;
    if (head < 0) { inspector.hidden = true; return; }
    inspector.hidden = false;
    const node = r(29, head, 1), road = r(29, head, 2), state = r(29, head, 5);
    const names = ["red", "amber", "green"];
    const simSeconds = (value) => `${value.toFixed(1)} s (${(value * 3).toFixed(0)} sim min)`;
    $("signal-summary").textContent =
      `Junction at node ${node + 1} · arm on street #${road + 1} · phase ${r(29,head,3) + 1} of ${r(29,head,4)} · currently ${names[state] ?? "?"}. ` +
      `One branch runs at a time; the others wait. ${r(29,head,12)} junctions are signalised.`;
    greenInput.min = r(29, head, 13); greenInput.max = r(29, head, 14);
    if (document.activeElement !== greenInput) greenInput.value = r(29, head, 6).toFixed(1);
    if (document.activeElement !== yellowInput) yellowInput.value = r(29, head, 7).toFixed(1);
    const left = r(29, head, 9);
    $("signal-clock").textContent =
      `Green ${simSeconds(r(29,head,6))} · amber ${simSeconds(r(29,head,7))} · full cycle ${simSeconds(r(29,head,8))}. ` +
      `This branch changes in ${simSeconds(left)}. Timings are simulation time, not real time.`;
  }
  $("signal-apply").onclick = () => {
    if (signal < 0) return;
    const node = r(29, signal, 1);
    const green = game.signal_set_green(node, Number(greenInput.value));
    const yellow = game.signal_set_yellow(node, Number(yellowInput.value));
    message(green < 0 || yellow < 0 ? "That junction has no signal." : `Timing set: green ${green.toFixed(1)} s, amber ${yellow.toFixed(1)} s (simulation time).`);
    showSignal(signal);
  };
  $("signal-remove").onclick = () => {
    if (signal < 0) return;
    if (game.signal_remove(r(29, signal, 1))) { message("Signal removed."); showSignal(-1); }
  };
  const option = (value, text) => {
    const o = document.createElement("option");
    o.value = value;
    o.textContent = text;
    return o;
  };
  let networkRevision=-1;
  function syncNetwork(){
    if(networkRevision===r(0,0,28))return;
    networkRevision=r(0,0,28);
    const stop=$('stop-address').value,road=$('traffic-road').value;
    nodes=Array.from({length:r(9,0,4)},(_,id)=>({id,x:r(11,id,0),z:r(11,id,1)}));
    stopNodes=nodes.filter(n=>validStop(n.id));
    roads=Array.from({length:r(0,0,15)},(_,id)=>({id,a:r(5,id,0),b:r(5,id,1)}));
    $('stop-address').replaceChildren(...stopNodes.map(n=>option(n.id,address(n.id))));
    $('traffic-road').replaceChildren(...roads.map(n=>option(n.id,`${streetName(r(5,n.id,15))} · segment ${n.id+1} · stops ${n.a+1}–${n.b+1}`)));
    if(stop&&stopNodes.some(n=>n.id===Number(stop)))$('stop-address').value=stop;
    if(road&&Number(road)<roads.length)$('traffic-road').value=road;
  }
  syncNetwork();
  function syncLines() {
    const ids = Array.from({ length: 8 }, (_, i) => i).filter(
      (i) => r(10, i, 0) || i === selected,
    );
    $("bus-line").replaceChildren(
      ...ids.map((id) =>
        option(
          id,
          `Line ${id + 1}${r(10, id, 0) ? "" : " · draft / withdrawn"}`,
        ),
      ),
    );
    if (!ids.includes(selected)) selected = ids[0] ?? -1;
    $("bus-line").value = selected;
    game.transport_select(selected);
    $("line-edit").disabled = selected < 0;
    $("line-remove").disabled = selected < 0 || !r(10, selected, 0);
  }
  function syncDraft() {
    if (!draft) {
      game.transport_edit_end();
      $("route-tools").hidden = true;
      $("route-form").hidden = true;
      return;
    }
    game.transport_draft(draft.length);
    draft.forEach((n, i) => game.transport_stop(i, n));
    $("route-tools").hidden = false;
    $("route-form").hidden = false;
    $("stop-list").replaceChildren(
      ...draft.map((n, i) => {
        const li = document.createElement("li");
        const label = document.createElement("span");
        label.textContent = address(n);
        li.append(label);
        for (const [text, action] of [
          [
            "↑",
            () => {
              if (i) {
                [draft[i - 1], draft[i]] = [draft[i], draft[i - 1]];
                syncDraft();
              }
            },
          ],
          [
            "×",
            () => {
              draft.splice(i, 1);
              syncDraft();
            },
          ],
        ]) {
          const b = document.createElement("button");
          b.textContent = text;
          b.setAttribute(
            "aria-label",
            `${text === "↑" ? "Move earlier" : "Remove stop"} ${i + 1}`,
          );
          b.onclick = action;
          li.append(b);
        }
        return li;
      }),
    );
  }
  function cancel() {
    if (!draft) return false;
    draft = null;
    gesture = null;
    syncDraft();
    message("Route changes discarded.");
    return true;
  }
  function save() {
    if (!draft) return;
    syncDraft();
    if (!game.transport_apply(selected)) {
      message("Choose two to sixteen unique valid kerbside stops.");
      ui.open("transport");
      return;
    }
    draft = null;
    syncDraft();
    syncLines();
    message(
      `Line ${selected + 1} route applied. Existing riders unload safely before the new service starts.`,
    );
  }
  function edit() {
    if (selected < 0) return;
    draft = Array.from({ length: r(10, selected, 1) }, (_, i) =>
      r(10, selected, 16 + i),
    );
    syncDraft();
    message(
      "Route draft active. Move this window aside or close it to edit on the map.",
    );
  }
  $("bus-line").onchange = () => {
    cancel();
    selected = Number($("bus-line").value);
    game.transport_select(selected);
    update();
  };
  $("line-new").onclick = () => {
    const id = Array.from({ length: 8 }, (_, i) => i).find((i) => !r(10, i, 0));
    if (id === undefined) {
      message("All eight line slots are in use.");
      return;
    }
    selected = id;
    draft = [];
    syncLines();
    syncDraft();
    message(
      "Choose street addresses or click streets on the map, then apply the route.",
    );
  };
  $("line-edit").onclick = edit;
  $("line-remove").onclick = () => {
    cancel();
    game.transport_remove(selected);
    syncLines();
    message(
      "Line withdrawn. On-board riders leave at the next junction and continue on foot.",
    );
  };
  $("line-clear").onclick = () => {
    cancel();
    game.transport_select(-1);
    $("route-map").replaceChildren();
  };
  $("stop-add").onclick = () => {
    const n = Number($("stop-address").value);
    if (!draft) return;
    if (draft.length === 16 || draft.includes(n)) {
      message("Stops must be unique valid kerbside locations, with a maximum of sixteen.");
      return;
    }
    draft.push(n);
    syncDraft();
  };
  $("route-save").onclick = $("route-save-map").onclick = save;
  $("route-cancel").onclick = $("route-cancel-map").onclick = cancel;
  $("transport-policy").onclick = () => {
    const cap = Number($("fare-cap").value),
      sub = Number($("bus-subsidy").value);
    message(
      game.transport_policy(cap, sub)
        ? "Fare cap and boarding subsidy applied."
        : "Enter amounts from £0 to £10.",
    );
  };
  const chooseRoad = (id) => {
    $("traffic-road").value = id;
    $("traffic-lane").value = r(5, id, 13);
    update();
  };
  $("traffic-road").onchange = () =>
    chooseRoad(Number($("traffic-road").value));
  $("lane-apply").onclick = () => {
    game.transport_lane(
      Number($("traffic-road").value),
      Number($("traffic-lane").value),
    );
    message("Street allocation applied in both directions.");
  };
  const crossing = document.createElement("button");
  $("lane-apply").after(crossing);
  crossing.onclick = () => {
    const id = Number($("traffic-road").value);
    game.set_crosswalk(id, r(5,id,14) ? 0 : 1);
    update();
  };
  $("road-locate").onclick = () =>
    game.focus(5, Number($("traffic-road").value));
  function syncParking() {
    const facilities = r(0, 0, 55);
    const slots = r(0, 0, 56);
    const used = r(0, 0, 57);
    const bikeSlots = r(0, 0, 63);
    const bikeUsed = r(0, 0, 64);
    const carSlots = r(0, 0, 65);
    const carUsed = r(0, 0, 66);
    $("parking-summary").textContent = [
      `${facilities} parking places · ${used}/${slots} spaces in use`,
      `bicycles ${bikeUsed}/${bikeSlots} · cars and kerbside ${carUsed}/${carSlots}`,
      `attempts ${r(0,0,58)} · parked ${r(0,0,59)} · searched on ${r(0,0,60)} · no space ${r(0,0,61)}`,
      `kerbside spaces in use ${r(0,0,67)} · parking receipts £${r(0,0,62).toFixed(2)}`,
      `learned arrivals folded in ${r(0,0,68)} (${r(0,0,69)} dropped)`,
    ].join(" · ");
  }

  function setOverlay(mode) {
    overlay = mode;
    game.set_overlay(mode);
    $("pedestrian-overlay").setAttribute("aria-pressed", mode === 3);
    $("traffic-overlay").setAttribute("aria-pressed", mode === 2);
    $("overlay").setAttribute("aria-pressed", mode === 1);
    $("overlay-key").hidden = !mode;
    $("overlay-key").querySelector("strong").textContent =
      mode === 3 ? "PEDESTRIAN DENSITY" : mode === 2 ? "TRAFFIC · INTENSITY & QUEUES" : "STREET CONDITION";
    $("overlay-key").querySelector("small").innerHTML =
      mode === 3 ? "Busy <span>Quiet</span><br>People walking or waiting outside; street intensity per 100 m² of sidewalk" : mode === 2
        ? "Queued <span>Flowing</span><br>Amber clouds: vehicle density; wider areas at city scale"
        : "Worn <span>Maintained</span>";
  }
  $("pedestrian-overlay").onclick = () => setOverlay(overlay === 3 ? 0 : 3);
  $("traffic-overlay").onclick = () => setOverlay(overlay === 2 ? 0 : 2);
  function points() {
    return nodes.map((n) => ({ x: r(11, n.id, 3), y: r(11, n.id, 4) }));
  }
  function stopPoints() {
    return nodes.map((n) => ({ x: r(11, n.id, 10), y: r(11, n.id, 11) }));
  }
  function nearestStop(p) {
    let best = stopNodes[0] ?? nodes[0];
    for (const n of stopNodes) {
      if (Math.hypot(r(11,n.id,10)-p.x, r(11,n.id,11)-p.y) < Math.hypot(r(11,best.id,10)-p.x, r(11,best.id,11)-p.y)) best = n;
    }
    return best.id;
  }
  function path(stops) {
    const pieces = [];
    for (let i = 0; i < stops.length; i++) {
      let n = stops[i],
        to = stops[(i + 1) % stops.length];
      for (let k = 0; n !== to && k < nodes.length; k++) {
        const next = game.route_next(n, to);
        pieces.push({ a: n, b: next, index: i });
        n = next;
      }
    }
    return pieces;
  }
  function distance(p, a, b) {
    const dx = b.x - a.x,
      dy = b.y - a.y;
    const t = Math.max(
      0,
      Math.min(
        1,
        ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy || 1),
      ),
    );
    return Math.hypot(p.x - a.x - t * dx, p.y - a.y - t * dy);
  }
  function pointerDown(event) {
    const p = { x: event.clientX, y: event.clientY },
      pts = points(),
      stopPts = stopPoints();
    if (tool === "signal") {
      const head = game.signal_place_screen(p.x, p.y);
      message(head < 0 ? "No junction there. Click nearer an arm of the street network." : "Traffic light placed. Click it to set its timing.");
      if (head >= 0) { arm(null); showSignal(head); }
      return true;
    }
    if (tool === "crosswalk") {
      const road = game.crosswalk_place_screen(p.x, p.y);
      message(road < 0 ? "No street there." : "Crosswalk added; its junction is signalised.");
      if (road >= 0) { arm(null); chooseRoad(road); $("traffic-road").value = String(road); }
      return true;
    }
    if (tool === "crosswalk-remove") {
      const road = game.crosswalk_remove_screen(p.x, p.y);
      if (road >= 0) arm(null);
      return true;
    }
    const picked = game.signal_pick(p.x, p.y);
    if (picked >= 0) { showSignal(picked); return true; }
    if (draft) {
      let index = draft.findIndex(
        (n) => Math.hypot(stopPts[n].x - p.x, stopPts[n].y - p.y) < 15,
      );
      if (index < 0) {
        const segment = path(draft).find(
          (e) => distance(p, pts[e.a], pts[e.b]) < 8,
        );
        if (draft.length >= 16) return true;
        index = segment ? segment.index + 1 : draft.length;
        draft.splice(index, 0, nearestStop(p));
      }
      gesture = { index };
      return true;
    }
    if (overlay === 2 || overlay === 3) {
      let best = null,
        min = 10;
      for (const road of roads) {
        const d = distance(p, pts[road.a], pts[road.b]);
        if (d < min) {
          min = d;
          best = road.id;
        }
      }
      if (best !== null) {
        chooseRoad(best);
        ui.open("transport");
        return true;
      }
    }
    return false;
  }
  function pointerMove(event) {
    if (!gesture || !draft) return false;
    draft[gesture.index] = nearestStop({
      x: event.clientX,
      y: event.clientY,
    });
    game.transport_draft(draft.length);
    draft.forEach((n, i) => game.transport_stop(i, n));
    return true;
  }
  function pointerUp() {
    if (!gesture) return false;
    gesture = null;
    syncDraft();
    return true;
  }
  function paint() {
    const svg = $("route-map");
    heat.hidden = overlay < 2;
    heat.style.display = overlay >= 2 ? "block" : "none";
    if (overlay >= 2 && ++heatFrame % 12 === 0) {
      const pts = points();
      const zoom = r(0,0,27);
      const groups = new Map();
      const cell = zoom < 2 ? 55 : 18;
      roads.forEach(road => {
        const weight = r(5,road.id,overlay===3?16:10);
        if (!weight) return;
        const key = `${Math.floor((nodes[road.a].x+nodes[road.b].x)/2/cell)},${Math.floor((nodes[road.a].z+nodes[road.b].z)/2/cell)}`;
        const g = groups.get(key) || {x:0,y:0,w:0};
        g.x += (pts[road.a].x+pts[road.b].x)/2*weight;
        g.y += (pts[road.a].y+pts[road.b].y)/2*weight;
        g.w += weight;
        groups.set(key,g);
      });
      heat.innerHTML = '<defs><radialGradient id="traffic-density"><stop stop-color="#ed632f" stop-opacity=".65"/><stop offset=".4" stop-color="#eda64c" stop-opacity=".35"/><stop offset="1" stop-color="#edbd57" stop-opacity="0"/></radialGradient></defs>' + [...groups.values()].map(g => `<circle cx="${g.x/g.w}" cy="${g.y/g.w}" r="${Math.min(150,25+Math.sqrt(g.w)*9)*(zoom<2?1.3:1)}" fill="url(#traffic-density)"/>`).join('');
    }
    if (!draft) {
      if (svg.childElementCount) svg.replaceChildren();
      return;
    }
    const stops = draft;
    const pts = points(), stopPts = stopPoints();
    svg.innerHTML =
      path(stops)
        .map(
          (e) =>
            `<line x1="${pts[e.a].x}" y1="${pts[e.a].y}" x2="${pts[e.b].x}" y2="${pts[e.b].y}"/>`,
        )
        .join("") +
      stops
        .map(
          (n, i) =>
            `<circle cx="${stopPts[n].x}" cy="${stopPts[n].y}" r="10"/><text x="${stopPts[n].x}" y="${stopPts[n].y + 4}">${i + 1}</text>`,
        )
        .join("");
  }
  const agreements = createAgreements(game, () => selected, message);
  const fleetButtons = Array.from({ length: 3 }, (_, slot) => {
    const button = document.createElement("button");
    button.onclick = () => game.focus(12, r(0, 0, 7) + selected * 3 + slot);
    $("bus-fleet").append(button);
    return button;
  });
  const observationRows = Array.from({length:16}, (_, stop) => {
    const row = document.createElement("tr");
    const cells = Array.from({length:7}, () => row.appendChild(document.createElement("td")));
    const locate = document.createElement("button");
    cells[0].append(locate);
    locate.onclick = () => {
      const node = r(Number($("stop-record").value), selected * 16 + stop, 2);
      if (node >= 0) game.focus(11, node);
    };
    $("stop-observation-rows").append(row);
    return {row,cells,locate};
  });
  $("stop-record").onchange = update;
  const passengerRows = Array.from({length:16}, (_, stop) => {
    const row = document.createElement("tr");
    const cells = Array.from({length:7}, () => row.appendChild(document.createElement("td")));
    const locate = document.createElement("button");
    cells[0].append(locate);
    locate.onclick = () => {
      const node = r(Number($("stop-record").value), selected * 16 + stop, 2);
      if (node >= 0) game.focus(11, node);
    };
    $("passenger-outcome-rows").append(row);
    return {row,cells,locate};
  });
  const districtRows = Array.from({length:r(0,0,16)}, (_, id) => {
    const row = document.createElement("tr");
    const cells = Array.from({length:7}, () => row.appendChild(document.createElement("td")));
    $("district-access-rows").append(row);
    return {row,cells};
  });
  function updateObservations() {
    const group = Number($("stop-record").value);
    const version = selected < 0 ? -1 : r(group,selected * 16,0);
    const window = selected < 0 ? -1 : r(group,selected * 16,1);
    const clock = r(0,0,0);
    const offHours = selected >= 0 && r(10,selected,34) === 1;
    $("stop-record-status").textContent = version < 0
      ? "No observation record available."
      : `Route v${version} · ${window === 0 ? "all day" : "06:00–22:00"} · ${group === 19 ? "retired record; waiting counts unavailable" : `current record; ${offHours ? "off hours" : "within coverage hours"}; waiting counts are live`}. Only the most recent retired record is retained. Session clock: ${clock.toFixed(1)} s.`;
    const seconds = n => n < 0 ? "—" : `${n.toFixed(1)} s`;
    observationRows.forEach(({row,cells,locate}, stop) => {
      const id = selected * 16 + stop;
      const node = version < 0 ? -1 : r(group,id,2);
      row.hidden = node < 0;
      if (node < 0) return;
      locate.textContent = address(node);
      const visits = r(group,id,3), samples = r(group,id,5);
      cells[1].textContent = group === 19 ? "—" : r(group,id,10);
      cells[2].textContent = visits;
      cells[3].textContent = visits ? `t=${r(group,id,4).toFixed(1)} s` : "Not yet observed";
      cells[4].textContent = samples || "Insufficient samples";
      cells[5].textContent = samples ? `${seconds(r(group,id,6))} / ${seconds(r(group,id,7))}` : "—";
      cells[6].textContent = samples ? `${seconds(r(group,id,8))}–${seconds(r(group,id,9))}` : "—";
    });
  }
  function updatePassengerOutcomes() {
    const group = Number($("stop-record").value);
    const version = selected < 0 ? -1 : r(group,selected * 16,0);
    const seconds = n => n < 0 ? "—" : `${n.toFixed(1)} s`;
    let starts = 0, completed = 0, abandoned = 0, capacity = 0, after = 0, waitTotal = 0, waiting = 0;
    passengerRows.forEach(({row,cells,locate}, stop) => {
      const id = selected * 16 + stop;
      const node = version < 0 ? -1 : r(group,id,2);
      row.hidden = node < 0;
      if (node < 0) return;
      locate.textContent = address(node);
      const current = group === 19 ? -1 : r(group,id,10);
      const comp = r(group,id,12);
      const gone = r(group,id,17) + r(group,id,18) + r(group,id,19) + r(group,id,20);
      starts += r(group,id,11);
      completed += comp;
      abandoned += gone;
      capacity += r(group,id,16);
      after += r(group,id,21);
      waitTotal += r(group,id,22);
      waiting += current < 0 ? 0 : current;
      cells[1].textContent = current < 0 ? "—" : current;
      cells[2].textContent = comp || "No completed waits";
      cells[3].textContent = comp ? seconds(r(group,id,22) / comp) : "—";
      cells[4].textContent = comp ? `${seconds(r(group,id,14))}–${seconds(r(group,id,15))}` : "—";
      cells[5].textContent = r(group,id,16) || "—";
      cells[6].textContent = gone || "—";
    });
    $("passenger-outcome-summary").textContent = version < 0
      ? "No passenger record available; create or select a service line."
      : `${group === 19 ? "Retired" : "Current"} route v${version}: ${starts} wait starts · ${completed} completed · ${abandoned} abandoned${group === 18 ? ` · ${waiting} still waiting` : ""} · ${capacity} capacity denials · ${after} abandoned after a full bus. ${completed ? `Mean completed wait ${(waitTotal / completed).toFixed(1)} s across completed waits only.` : "No completed waits yet; wait starts are not evidence of good service."}`;
    districtRows.forEach(({cells}, id) => {
      const observed = r(22,id,0), done = r(22,id,1), mean = r(22,id,2), denials = r(22,id,3), gone = r(22,id,4), afterCapacity = r(22,id,5);
      cells[0].textContent = districtName(id);
      cells[1].textContent = observed || "No observed waits";
      cells[2].textContent = done || "—";
      cells[3].textContent = mean < 0 ? "—" : seconds(mean);
      cells[4].textContent = denials || "—";
      cells[5].textContent = gone || "—";
      cells[6].textContent = afterCapacity || "—";
    });
  }
  let hotspotIds = "";
  function update() {
    syncNetwork();
    agreements.update();
    updateObservations();
    updatePassengerOutcomes();
    $("transport-summary").textContent =
      `Trips in progress: ${r(9, 0, 5)} walk · ${r(9, 0, 6)} cycle · ${r(9, 0, 7)} car · ${r(9, 0, 8)} bus. Waiting at stops: ${r(9, 0, 9)}. City subsidies paid: ${money(r(9, 0, 2))}.`;
    $("line-stats").textContent =
      selected < 0
        ? "No bus lines. Create a line to begin service."
        : `Line ${selected + 1}: ${r(10, selected, 1)} stops · ${r(10, selected, 7)} aboard · ${r(10, selected, 2)} boardings · ${r(10,selected,36)} completed waits · ${r(10,selected,38)} abandoned · ${r(10,selected,37)} capacity denials · income ${money(r(10, selected, 3))} · costs ${money(r(10, selected, 4))} · operator cash ${money(r(10, selected, 5))}${r(10, selected, 5) <= 0 ? " · SERVICE SUSPENDED" : ""}`;
    fleetButtons.forEach((button, slot) => {
      const id = r(0, 0, 7) + selected * 3 + slot;
      const active = selected >= 0 && r(12, id, 0) === 1;
      button.disabled = !active;
      button.textContent = `Bus ${slot + 1} · ${active ? `${r(12, id, 4)}/24 aboard · ${r(12, id, 3).toFixed(1)} m/s · locate` : "Out of service"}`;
    });
    if (signal >= 0) showSignal(signal);
    const road = Number($("traffic-road").value);
    crossing.textContent = r(5,road,14) ? "Remove crosswalk" : "Add crosswalk";
    $("traffic-road-stats").textContent =
      `${r(5, road, 10)} vehicles on segment · ${r(5,road,16)} pedestrians (${(r(5,road,16)/Math.max(1,r(5,road,2)*1.9)*100).toFixed(1)} / 100 m² sidewalk) · ${r(5, road, 11)} queued · ${(r(5, road, 12) * 100).toFixed(0)}% queue pressure · ${(r(5, road, 3) * 100).toFixed(0)}% grade`;
    const top = roads
      .filter((road) => r(5, road.id, 11) > 0)
      .sort((a, b) => r(5, b.id, 11) - r(5, a.id, 11))
      .slice(0, 5);
    const ids = top.map((road) => road.id).join(",");
    if (ids !== hotspotIds) {
      hotspotIds = ids;
      $("traffic-hotspots").replaceChildren(
        ...top.map((road) => {
          const b = document.createElement("button");
          b.textContent = `Street #${road.id + 1} · ${r(5, road.id, 11)} queued`;
          b.onclick = () => {
            chooseRoad(road.id);
            game.focus(5, road.id);
          };
          return b;
        }),
      );
    }
    [...$("traffic-hotspots").children].forEach((button, i) => {
      button.textContent = `Street #${top[i].id + 1} · ${r(5, top[i].id, 11)} queued`;
    });
  }
  syncLines();
  game.transport_select(-1);
  syncParking();
  update();
  return {
    update,
    syncNetwork,
    paint,
    pointerDown,
    pointerMove,
    pointerUp,
    cancel,
    inspectLine(id) {
      cancel();
      selected = id;
      syncLines();
      update();
      ui.open("transport");
    },
    inspectRoad(id) {
      chooseRoad(id);
      ui.open("transport");
    },
    togglePedestrians: () => setOverlay(overlay === 3 ? 0 : 3),
    toggleTraffic: () => setOverlay(overlay === 2 ? 0 : 2),
    toggleCondition: () => setOverlay(overlay === 1 ? 0 : 1),
    reset() {
      tool = null;
      showSignal(-1);
      signalButton.setAttribute("aria-pressed", "false");
      crosswalkButton.setAttribute("aria-pressed", "false");
      crosswalkRemoveButton.setAttribute("aria-pressed", "false");
      networkRevision = -1;
      syncNetwork();
      $("stop-record").value = "18";
      $("traffic-road").value = "0";
      $("traffic-lane").value = r(5,0,13);
      draft = null;
      gesture = null;
      selected = -1;
      syncDraft();
      syncLines();
      game.transport_select(-1);
      agreements.reset();
      setOverlay(0);
      $("fare-cap").value = r(9, 0, 0);
      $("bus-subsidy").value = r(9, 0, 1);
      update();
    },
  };
}
