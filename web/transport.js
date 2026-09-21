import {createAgreements} from "./agreements.js";
import {streetName} from "./data.js";
// Game windows and map gestures; all traffic, fares and passengers live in Zig.
export function createTransport(game, ui) {
  const $ = (id) => document.getElementById(id);
  const r = (group, id, field) => game.read(group, id, field);
  const money = (n) => `£${n.toFixed(2)}`;
  let nodes = Array.from({ length: r(9, 0, 4) }, (_, id) => ({
    id,
    x: r(11, id, 0),
    z: r(11, id, 1),
  }));
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
    overlay = 0;
  const message = (text) => ($("transport-message").textContent = text);
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
    roads=Array.from({length:r(0,0,15)},(_,id)=>({id,a:r(5,id,0),b:r(5,id,1)}));
    $('stop-address').replaceChildren(...nodes.map(n=>option(n.id,address(n.id))));
    $('traffic-road').replaceChildren(...roads.map(n=>option(n.id,`${streetName(r(5,n.id,15))} · segment ${n.id+1} · stops ${n.a+1}–${n.b+1}`)));
    if(stop&&Number(stop)<nodes.length)$('stop-address').value=stop;
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
      message("Choose two to sixteen unique street addresses.");
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
      message("Stops must be unique, with a maximum of sixteen.");
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
  function nearest(p, pts) {
    return nodes.reduce(
      (best, n) =>
        Math.hypot(pts[n.id].x - p.x, pts[n.id].y - p.y) <
        Math.hypot(pts[best].x - p.x, pts[best].y - p.y)
          ? n.id
          : best,
      0,
    );
  }
  function pointerDown(event) {
    const p = { x: event.clientX, y: event.clientY },
      pts = points();
    if (draft) {
      let index = draft.findIndex(
        (n) => Math.hypot(pts[n].x - p.x, pts[n].y - p.y) < 15,
      );
      if (index < 0) {
        const segment = path(draft).find(
          (e) => distance(p, pts[e.a], pts[e.b]) < 8,
        );
        if (draft.length >= 16) return true;
        index = segment ? segment.index + 1 : draft.length;
        draft.splice(index, 0, nearest(p, pts));
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
    draft[gesture.index] = nearest(
      { x: event.clientX, y: event.clientY },
      points(),
    );
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
    const pts = points();
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
            `<circle cx="${pts[n].x}" cy="${pts[n].y}" r="10"/><text x="${pts[n].x}" y="${pts[n].y + 4}">${i + 1}</text>`,
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
  let hotspotIds = "";
  function update() {
    syncNetwork();
    agreements.update();
    updateObservations();
    $("transport-summary").textContent =
      `Trips in progress: ${r(9, 0, 5)} walk · ${r(9, 0, 6)} cycle · ${r(9, 0, 7)} car · ${r(9, 0, 8)} bus. Waiting at stops: ${r(9, 0, 9)}. City subsidies paid: ${money(r(9, 0, 2))}.`;
    $("line-stats").textContent =
      selected < 0
        ? "No bus lines. Create a line to begin service."
        : `Line ${selected + 1}: ${r(10, selected, 1)} stops · ${r(10, selected, 7)} aboard · ${r(10, selected, 2)} boardings · income ${money(r(10, selected, 3))} · costs ${money(r(10, selected, 4))} · operator cash ${money(r(10, selected, 5))}${r(10, selected, 5) <= 0 ? " · SERVICE SUSPENDED" : ""}`;
    fleetButtons.forEach((button, slot) => {
      const id = r(0, 0, 7) + selected * 3 + slot;
      const active = selected >= 0 && r(12, id, 0) === 1;
      button.disabled = !active;
      button.textContent = `Bus ${slot + 1} · ${active ? `${r(12, id, 4)}/24 aboard · ${r(12, id, 3).toFixed(1)} m/s · locate` : "Out of service"}`;
    });
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
