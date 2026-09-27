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
  // Top-level tabs: lines / agreements / fleet / stops / streets / signals.
  // Panels keep their ids; switching only changes visibility, and update()
  // refreshes the visible panel so hidden tables do not rebuild twice a second.
  const transportTabs = {};
  let transportTab = "lines";
  for (const button of document.querySelectorAll("[data-transport-tab]"))
    transportTabs[button.dataset.transportTab] = button;
  function showTransportTab(name) {
    if (!transportTabs[name]) return;
    transportTab = name;
    for (const [key, button] of Object.entries(transportTabs)) {
      const on = key === name;
      button.setAttribute("aria-selected", String(on));
      button.tabIndex = on ? 0 : -1;
      $(`tpanel-${key}`).hidden = !on;
    }
    update();
  }
  const transportTabList = Object.values(transportTabs);
  transportTabList.forEach((button, index) => {
    button.onclick = () => showTransportTab(button.dataset.transportTab);
    button.onkeydown = (event) => {
      let next;
      if (event.key === "ArrowRight") next = (index + 1) % transportTabList.length;
      else if (event.key === "ArrowLeft") next = (index + transportTabList.length - 1) % transportTabList.length;
      else if (event.key === "Home") next = 0;
      else if (event.key === "End") next = transportTabList.length - 1;
      else return;
      event.preventDefault();
      event.stopPropagation();
      showTransportTab(transportTabList[next].dataset.transportTab);
      transportTabList[next].focus();
    };
  });
  // Slice 11: traffic-signal placement tools and the selected-light inspector.
  const signalButton = $("signal-place"), crosswalkButton = $("crosswalk-place"), crosswalkRemoveButton = $("crosswalk-remove");
  const inspector = $("signal-inspector"), greenInput = $("signal-green"), yellowInput = $("signal-yellow");
  // Slice 12: the granular per-light controls, the traffic-lights tab and the
  // coordination map.
  const redInput = $("signal-red"), flashStartInput = $("signal-flash-start"), flashEndInput = $("signal-flash-end"), flashEnabledInput = $("signal-flash-enabled");
  // Item 14: the pedestrian-only stage and its clearance.
  const pedWalkInput = $("signal-ped-walk"), pedClearInput = $("signal-ped-clear"), pedEnabledInput = $("signal-ped-enabled");
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
  function reveal(element) {
    const body = element.closest(".window-body");
    if (!body) return;
    const outer = body.getBoundingClientRect(), inner = element.getBoundingClientRect();
    if (inner.bottom > outer.bottom) body.scrollTop += inner.bottom - outer.bottom + 8;
    else if (inner.top < outer.top) body.scrollTop -= outer.top - inner.top + 8;
  }
  signalButton.onclick = () => arm("signal");
  crosswalkButton.onclick = () => arm("crosswalk");
  crosswalkRemoveButton.onclick = () => arm("crosswalk-remove");
  // The panel refreshes twice a real second, so the timing fields are only
  // refilled when the player changes the selected light, applies an edit, or
  // is not part-way through typing one. Otherwise a live refresh writes the
  // stored value back over the number being entered and the edit is replaced.
  let signalFieldsHead = -1, signalFieldsEdited = false;
  const signalFieldInputs = [greenInput, yellowInput, redInput, flashStartInput, flashEndInput, pedWalkInput, pedClearInput];
  for (const input of signalFieldInputs) input.addEventListener("input", () => { signalFieldsEdited = true; });
  function fillSignalFields(head, force) {
    const changed = head !== signalFieldsHead;
    if (!changed && !force && signalFieldsEdited) return; // keep the half-typed edit
    const fields = [
      [greenInput, 6], [yellowInput, 7], [redInput, 15],
      [flashStartInput, 19], [flashEndInput, 20],
      [pedWalkInput, 39], [pedClearInput, 40],
    ];
    for (const [input, field] of fields) {
      if (!changed && !force && document.activeElement === input) continue;
      input.value = r(29, head, field).toFixed(1);
    }
    signalFieldsHead = head;
    signalFieldsEdited = false;
  }
  // An empty or unreadable box keeps the stored value rather than sending NaN.
  function timingInput(input, head, field) {
    const value = Number(input.value);
    return input.value.trim() !== "" && Number.isFinite(value) ? value : r(29, head, field);
  }
  function showSignal(head, force) {
    signal = head;
    if (head < 0) { inspector.hidden = true; signalFieldsHead = -1; signalFieldsEdited = false; return; }
    inspector.hidden = false;
    const node = r(29, head, 1), road = r(29, head, 2), state = r(29, head, 5);
    const names = ["red", "amber", "green", "flashing yellow"];
    const simSeconds = (value) => `${value.toFixed(1)} s (${(value * 3).toFixed(0)} sim min)`;
    const flashingNow = r(29, head, 17) === 1;
    const mode = r(29, head, 16);
    $("signal-summary").textContent =
      `Junction at node ${node + 1} · arm on street #${road + 1} · phase ${r(29,head,3) + 1} of ${r(29,head,4)} · currently ${names[state] ?? "?"}. ` +
      `One branch runs at a time; the others wait. ${r(29,head,12)} junctions are signalised.`;
    greenInput.min = r(29, head, 13); greenInput.max = r(29, head, 14);
    yellowInput.min = r(29, head, 26); yellowInput.max = r(29, head, 27);
    redInput.min = r(29, head, 24); redInput.max = r(29, head, 25);
    fillSignalFields(head, force === true);
    flashEnabledInput.checked = r(29, head, 18) === 1;
    pedWalkInput.min = r(29, head, 45); pedWalkInput.max = r(29, head, 46);
    pedClearInput.min = r(29, head, 47); pedClearInput.max = r(29, head, 48);
    pedEnabledInput.checked = r(29, head, 41) === 1;
    const stageNames = ["vehicle branches", "pedestrian walk", "clearance"];
    const stage = r(29, head, 42);
    const pedLeft = r(29, head, 43);
    $("signal-ped-state").textContent =
      stage === 0 ? `No pedestrian stage running now. Walk ${r(29,head,39).toFixed(1)} s, clearance ${r(29,head,40).toFixed(1)} s.`
      : stage === 1 ? `Pedestrian walk now: every vehicle arm is red and the crossings are open. ${simSeconds(pedLeft)} left.`
      : `Clearance after the walk: nobody is admitted until the box empties. ${simSeconds(pedLeft)} left.`;
    $("signal-turn-list").innerHTML = turnSummary(head);
    $("signal-flash-state").textContent = flashingNow
      ? "Blinking yellow right now: cars may cross slowly, and only when the junction is clear."
      : mode > 0.5 ? "Flashing yellow by hand. Follow the window hands it back to the daily window."
      : mode < -0.5 ? "Forced onto the normal cycle; the daily window is ignored until Follow the window."
      : r(29, head, 18) === 1 ? "Following the daily window: outside it the branches cycle as usual." : "Cycling normally; no daily window is set.";
    $("signal-flash-on").setAttribute("aria-pressed", mode > 0.5 ? "true" : "false");
    $("signal-flash-auto").setAttribute("aria-pressed", mode === 0 ? "true" : "false");
    $("signal-flash-off").setAttribute("aria-pressed", mode < -0.5 ? "true" : "false");
    const preempt = r(29, head, 23);
    $("signal-hold").setAttribute("aria-pressed", preempt === 1 ? "true" : "false");
    $("signal-open").setAttribute("aria-pressed", preempt === 2 ? "true" : "false");
    $("signal-arms").textContent = `Branches — ${armSummary(head)}.`;
    const group = r(29, head, 21), delay = r(29, head, 22);
    const left = r(29, head, 9);
    $("signal-clock").textContent =
      `Green ${simSeconds(r(29, head, 6))} · amber ${simSeconds(r(29, head, 7))} · off ${simSeconds(r(29, head, 15))} · full cycle ${simSeconds(r(29, head, 8))}. ` +
      (flashingNow ? "No branch is committed while the light blinks yellow. " : `This branch changes in ${simSeconds(left)}. `) +
      `Timings are simulation time, not real time. Coordination: ${group < 0 ? "not grouped" : `group ${group + 1}, held back ${simSeconds(delay)}`}` +
      `${preempt === 1 ? ", and the cross traffic is held for an emergency" : preempt === 2 ? ", and the junction is opened for an emergency" : ""}.`;
  }
  $("signal-apply").onclick = () => {
    if (signal < 0) return;
    const node = r(29, signal, 1);
    const green = game.signal_set_green(node, timingInput(greenInput, signal, 6));
    const yellow = game.signal_set_yellow(node, timingInput(yellowInput, signal, 7));
    const red = game.signal_set_red(node, timingInput(redInput, signal, 15));
    message(green < 0 || yellow < 0 || red < 0 ? "That junction has no signal." : `Timing set: green ${green.toFixed(1)} s, amber ${yellow.toFixed(1)} s, off ${red.toFixed(1)} s (simulation time).`);
    showSignal(signal, true);
  };
  $("signal-ped-save").onclick = () => {
    if (signal < 0) return;
    const node = r(29, signal, 1);
    const walk = game.signal_set_ped_walk(node, timingInput(pedWalkInput, signal, 39));
    const clear = game.signal_set_ped_clear(node, timingInput(pedClearInput, signal, 40));
    if (walk < 0 || clear < 0) { message("That junction has no signal."); return; }
    game.signal_set_ped_enabled(node, pedEnabledInput.checked ? 1 : 0);
    message(pedEnabledInput.checked
      ? `Pedestrian stage set: walk ${walk.toFixed(1)} s, clearance ${clear.toFixed(1)} s (simulation time).`
      : "Pedestrian-only stage off; the junction returns to its vehicle-only cycle.");
    showSignal(signal, true);
  };
  $("signal-remove").onclick = () => {
    if (signal < 0) return;
    if (game.signal_remove(r(29, signal, 1))) { message("Signal removed."); showSignal(-1); }
  };
  // Slice 12: the traffic-lights tab. One row per signalised junction, with the
  // same values the panel above edits one light at a time.
  const signalTabButtons = { one: $("signal-tab-one"), all: $("signal-tab-all"), map: $("signal-tab-map") };
  const signalTabViews = { one: $("signal-view-one"), all: $("signal-view-all"), map: $("signal-view-map") };
  function showSignalTab(name) {
    for (const key of Object.keys(signalTabViews)) {
      const on = key === name;
      signalTabButtons[key].setAttribute("aria-selected", on ? "true" : "false");
      signalTabViews[key].hidden = !on;
    }
    if (name === "all") {
      // The option helper lives further down the module, so the bulk lists are
      // built here rather than at load time.
      syncBulkScope();
      syncSignalList();
    }
    if (name === "map") syncSignalMap();
  }
  for (const key of Object.keys(signalTabButtons)) signalTabButtons[key].onclick = () => showSignalTab(key);
  const signalStateNames = ["red", "amber", "green", "flashing yellow"];
  // The flat head index is the ABI's own enumeration: walk it until the read
  // says "no head", then keep one row per junction.
  function signalHeads() {
    const heads = [];
    for (let head = 0; head < 400; head++) {
      if (r(29, head, 1) < 0) break;
      heads.push(head);
    }
    return heads;
  }
  function signalJunctions() {
    const seen = new Map();
    for (const head of signalHeads()) {
      const junction = r(29, head, 0);
      if (!seen.has(junction)) seen.set(junction, head);
    }
    return [...seen.entries()].map(([junction, head]) => ({ junction, head }));
  }
  // Item 14: the turning geometry of the selected light's own arm. Read from
  // group 33, one movement per (junction, approach slot, exit slot).
  function turnSummary(head) {
    const junction = r(29, head, 0), approach = r(29, head, 3), arms = r(29, head, 4);
    const names = ["straight", "left", "right", "u-turn"];
    const rows = [];
    for (let exit = 0; exit < arms; exit++) {
      if (exit === approach) continue;
      const movement = junction * 16 + approach * 4 + exit;
      const kind = r(33, movement, 6);
      const radius = r(33, movement, 7);
      const blocked = r(33, movement, 8) === 1;
      const exitRoad = r(33, movement, 5);
      const geometry = radius > 0 ? `${radius.toFixed(1)} m radius` : "no corner";
      rows.push(`${names[kind] ?? "?"} into street #${exitRoad + 1} (${geometry}${blocked ? ", held by yielding" : ""})`);
    }
    return rows.length ? `Turning geometry from this arm — ${rows.join("; ")}.` : "";
  }
  function armSummary(head) {
    const slots = [];
    for (let slot = 0; slot < 4; slot++) {
      const branch = r(29, head, 35 + slot);
      if (branch < 0) continue;
      const state = r(29, head, 31 + slot);
      slots.push(`${streetName(r(5, branch, 15))} #${branch + 1}: ${signalStateNames[state] ?? "?"}`);
    }
    return slots.length > 0 ? slots.join(" · ") : "no branches";
  }
  function flashSummary(head) {
    if (r(29, head, 17) === 1) return "blinking yellow";
    const mode = r(29, head, 16);
    if (mode > 0.5) return "blinking by hand";
    if (mode < -0.5) return "manual off";
    if (r(29, head, 18) !== 1) return "cycling";
    return `window ${r(29, head, 19).toFixed(0)}–${r(29, head, 20).toFixed(0)}h`;
  }
  let signalRowIds = "";
  function syncSignalList() {
    const rows = signalJunctions();
    const ids = rows.map((row) => row.head).join(",");
    if (ids !== signalRowIds) {
      signalRowIds = ids;
      $("signal-list").replaceChildren(
        ...rows.map((row) => {
          const button = document.createElement("button");
          button.className = "signal-row";
          button.onclick = () => {
            signal = row.head;
            showSignalTab("one");
            showSignal(row.head);
            reveal(inspector);
          };
          return button;
        }),
      );
    }
    [...$("signal-list").children].forEach((button, i) => {
      const head = rows[i].head;
      button.textContent =
        `Node ${r(29, head, 1) + 1} · ${r(29, head, 4)} branches · green ${r(29, head, 6).toFixed(1)}s · amber ${r(29, head, 7).toFixed(1)}s · off ${r(29, head, 15).toFixed(1)}s · ${flashSummary(head)}`;
      button.title = armSummary(head);
      button.setAttribute("aria-pressed", head === signal ? "true" : "false");
    });
  }
  let signalBulkBuilt = false;
  function syncSignalBulkOptions() {
    if (signalBulkBuilt) return;
    signalBulkBuilt = true;
    $("signal-bulk-street").replaceChildren(
      ...roads.map((road) => option(road.id, `${streetName(r(5, road.id, 15))} · segment ${road.id + 1}`)),
    );
    $("signal-bulk-node").replaceChildren(
      ...signalJunctions().map((row) => {
        const node = r(29, row.head, 1);
        return option(node, `Junction at node ${node + 1}`);
      }),
    );
  }
  function syncBulkScope() {
    syncSignalBulkOptions();
    const scope = Number($("signal-bulk-scope").value);
    $("signal-bulk-street").disabled = scope !== 1;
    $("signal-bulk-node").disabled = scope !== 2;
  }
  $("signal-bulk-scope").onchange = syncBulkScope;
  $("signal-bulk-apply").onclick = () => {
    syncSignalBulkOptions();
    const scope = Number($("signal-bulk-scope").value);
    const field = Number($("signal-bulk-field").value);
    const key =
      scope === 1 ? Number($("signal-bulk-street").value) :
      scope === 2 ? Number($("signal-bulk-node").value) : 0;
    let value = Number($("signal-bulk-value").value);
    if (field === 5) value = value !== 0 ? 1 : 0;
    if (field === 6) value = Math.sign(value);
    const changed = game.signal_apply_bulk(scope, key, field, value);
    $("signal-bulk-note").textContent = changed > 0
      ? `${changed} light${changed === 1 ? "" : "s"} took that value.`
      : "No light took that change. Check the scope you picked.";
    signalRowIds = "";
    syncSignalList();
    if (signal >= 0) showSignal(signal, true);
  };
  $("signal-flash-all-on").onclick = () => {
    const changed = game.signal_flash_bulk(0, 0, 1);
    $("signal-bulk-note").textContent = `${changed} lights are now blinking yellow by hand.`;
    signalRowIds = "";
    syncSignalList();
  };
  $("signal-flash-all-off").onclick = () => {
    const changed = game.signal_flash_bulk(0, 0, 0);
    $("signal-bulk-note").textContent = `${changed} lights are back on their window and normal cycle.`;
    signalRowIds = "";
    syncSignalList();
  };
  function signalNode() {
    return signal < 0 ? -1 : r(29, signal, 1);
  }
  $("signal-flash-save").onclick = () => {
    if (signal < 0) return;
    const ok = game.signal_set_flash_schedule(
      signalNode(),
      Number(flashStartInput.value),
      Number(flashEndInput.value),
      flashEnabledInput.checked ? 1 : 0,
    );
    message(ok ? "Flash window saved." : "That junction has no signal.");
    showSignal(signal, true);
  };
  const manualFlash = (mode) => () => {
    if (signal < 0) return;
    if (!game.signal_flash_manual(signalNode(), mode)) { message("That junction has no signal."); return; }
    message(mode > 0 ? "Blinking yellow now." : mode < 0 ? "Back on the normal cycle." : "Following the daily window.");
    showSignal(signal);
  };
  $("signal-flash-on").onclick = manualFlash(1);
  $("signal-flash-auto").onclick = manualFlash(0);
  $("signal-flash-off").onclick = manualFlash(-1);
  const raiseAlert = (kind) => () => {
    if (signal < 0) return;
    const pending = game.signal_alert(signalNode(), kind, Number($("signal-alert-seconds").value));
    message(pending > 0 ? `Alert queued (${pending} pending).` : "That junction has no signal.");
    showSignal(signal);
  };
  $("signal-hold").onclick = raiseAlert(1);
  $("signal-open").onclick = raiseAlert(2);
  $("signal-release").onclick = raiseAlert(3);
  function signalLinkRows() {
    const rows = [];
    for (let i = 0; i < 128; i++) {
      if (r(30, i, 0) < 0) break;
      rows.push({ fromIndex: r(30, i, 0), toIndex: r(30, i, 1), from: r(30, i, 2), to: r(30, i, 3), delay: r(30, i, 4) });
    }
    return rows;
  }
  const SVG_NS = "http://www.w3.org/2000/svg";
  let signalLinkBuilt = false;
  function syncSignalMap() {
    const rows = signalJunctions();
    const nodes = new Map();
    for (const row of rows) {
      const node = r(29, row.head, 1);
      nodes.set(row.junction, { node, x: r(11, node, 0), z: r(11, node, 1), head: row.head });
    }
    const values = [...nodes.values()];
    const span = Math.max(1, ...values.map((n) => Math.max(n.x, n.z)));
    const place = (n) => ({ x: 16 + (n.x / span) * 288, y: 16 + (n.z / span) * 288 });
    const links = signalLinkRows();
    const svg = $("signal-map");
    svg.replaceChildren();
    for (const link of links) {
      const a = nodes.get(link.fromIndex), b = nodes.get(link.toIndex);
      if (!a || !b) continue;
      const pa = place(a), pb = place(b);
      const line = document.createElementNS(SVG_NS, "line");
      line.setAttribute("x1", pa.x); line.setAttribute("y1", pa.y);
      line.setAttribute("x2", pb.x); line.setAttribute("y2", pb.y);
      line.setAttribute("stroke", "#efb956"); line.setAttribute("stroke-width", "2");
      svg.append(line);
      const label = document.createElementNS(SVG_NS, "text");
      label.setAttribute("x", (pa.x + pb.x) / 2); label.setAttribute("y", (pa.y + pb.y) / 2);
      label.setAttribute("fill", "#fff0c8"); label.setAttribute("font-size", "10");
      label.setAttribute("text-anchor", "middle");
      label.textContent = `${link.delay.toFixed(0)}s`;
      svg.append(label);
    }
    for (const n of values) {
      const p = place(n);
      const circle = document.createElementNS(SVG_NS, "circle");
      circle.setAttribute("cx", p.x); circle.setAttribute("cy", p.y); circle.setAttribute("r", "4");
      circle.setAttribute("fill", r(29, n.head, 17) === 1 ? "#efb956" : "#262d2a");
      circle.setAttribute("stroke", "#efb956"); circle.setAttribute("stroke-width", "2");
      svg.append(circle);
      const label = document.createElementNS(SVG_NS, "text");
      label.setAttribute("x", p.x); label.setAttribute("y", p.y - 7);
      label.setAttribute("fill", "#fff0c8"); label.setAttribute("font-size", "9");
      label.setAttribute("text-anchor", "middle");
      label.textContent = `${n.node + 1}`;
      svg.append(label);
    }
    if (!signalLinkBuilt) {
      signalLinkBuilt = true;
      // signalJunctions() carries the flat head; the node is read from it.
      const choices = rows.map((row) => {
        const node = r(29, row.head, 1);
        return option(node, `Node ${node + 1}`);
      });
      $("signal-link-from").replaceChildren(...choices.map((o) => o.cloneNode(true)));
      $("signal-link-to").replaceChildren(...choices);
    }
    $("signal-map-note").textContent =
      `${links.length} coordination link${links.length === 1 ? "" : "s"}. Alerts pushed ${game.signal_alerts_pushed()} · handled ${game.signal_alerts_handled()} · pending ${game.signal_alerts_pending()}.`;
  }
  $("signal-link-add").onclick = () => {
    const from = Number($("signal-link-from").value), to = Number($("signal-link-to").value);
    const ok = game.signal_link(from, to, Number($("signal-link-delay").value));
    message(ok ? `Node ${from + 1} now leads node ${to + 1}.` : "Link refused: pick two different signalised junctions.");
    syncSignalMap();
  };
  $("signal-link-remove").onclick = () => {
    const from = Number($("signal-link-from").value), to = Number($("signal-link-to").value);
    const ok = game.signal_unlink(from, to);
    message(ok ? "Link removed." : "Those two are not linked.");
    syncSignalMap();
  };
  $("signal-alert-send").onclick = () => {
    const node = Number($("signal-link-from").value);
    game.signal_alert(node, Number($("signal-alert-kind").value), Number($("signal-alert-seconds").value));
    message(`Alert queued for node ${node + 1}.`);
    syncSignalMap();
  };
  showSignalTab("one");

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
  // Slice 24: designate loading bays on the selected street. The bays come out
  // of that segment's car supply, so the parking summary updates immediately.
  $("freight-bays-apply").onclick = () => {
    const road = Number($("traffic-road").value);
    const count = Number($("freight-bays").value);
    if (game.freight_set_bays(road, count)) message(`Street #${road + 1} now has ${count} loading bay${count === 1 ? "" : "s"}.`);
    else message("That street cannot take loading bays.");
    update();
  };
  // Slice 25: designate lighting columns on the selected street. New columns
  // are charged as municipal works, and the summary reflects coverage at once.
  $("lighting-apply").onclick = () => {
    const road = Number($("traffic-road").value);
    const lamps = Number($("lighting-lamps").value);
    const cost = game.lighting_set(road, lamps);
    if (cost < 0)
      message("That street cannot take lighting (lanes, works and pedestrian-only segments are excluded, and the count is capped by street class).");
    else if (cost === 0) message(`Street #${road + 1} already has ${lamps} column${lamps === 1 ? "" : "s"}.`);
    else message(`Street #${road + 1} now has ${lamps} column${lamps === 1 ? "" : "s"}; £${cost.toFixed(2)} of works booked.`);
    update();
  };
  // Numbered item 18: designate drains on the selected street. New drains are
  // charged as municipal works, and a street that is drained keeps its speed in
  // heavy rain while an undrained one floods.
  $("water-drains-apply").onclick = () => {
    const road = Number($("traffic-road").value);
    const drains = Number($("water-drains").value);
    const cost = game.water_set_drains(road, drains);
    if (cost < 0)
      message("That street cannot take drains (lanes, works and pedestrian-only segments are excluded, and the count is capped by street class).");
    else if (cost === 0) message(`Street #${road + 1} already has ${drains} drain${drains === 1 ? "" : "s"}.`);
    else message(`Street #${road + 1} now has ${drains} drain${drains === 1 ? "" : "s"}; £${cost.toFixed(2)} of works booked.`);
    update();
  };

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
      `measured kerbside demand ${(r(0,0,136) * 100).toFixed(0)}%`,
    ].join(" · ");
    // Slice 24: freight is a bounded private delivery layer over the same
    // kerbside. The summary is the town total; the selected street shows its
    // own loading bays and the parking demand the conversion is costing.
    $("freight-summary").textContent = [
      `${r(0,0,124)} depots · ${r(0,0,123)} runs recorded · ${r(0,0,125)} dispatched · ${r(0,0,126)} delivered`,
      `goods ${r(0,0,127).toFixed(1)} units · fees £${r(0,0,128).toFixed(2)} private · bay-seconds held ${r(0,0,129).toFixed(1)}`,
      `today demand ${r(0,0,131).toFixed(1)} delivered ${r(0,0,132).toFixed(1)} · mean business access ${(r(0,0,133)*100).toFixed(0)}%`,
      `loading bays designated ${r(0,0,134)} · held now ${r(0,0,135)}`,
    ].join(" · ");
    const road = Number($("traffic-road").value);
    const bays = r(5, road, 17);
    $("freight-bays").value = String(bays);
    $("freight-message").textContent = bays < 0
      ? "This street cannot take loading bays (lanes, works and pedestrian-only segments are excluded)."
      : `Street #${road + 1}: ${bays} loading bay${bays === 1 ? "" : "s"}; measured kerbside demand ${(r(0,0,136)*100).toFixed(0)}%.`;
    // Slice 25: street lighting. The summary is the town total; the selected
    // street shows its own coverage, its outstanding faults and the electricity
    // it draws. Darkness is published so the panel can say whether any of this
    // is currently visible on the road.
    const dusk = r(0,0,151);
    $("lighting-summary").textContent = [
      `${r(0,0,137)} lit segments · ${r(0,0,139)}/${r(0,0,138)} columns working · ${r(0,0,140)} failed`,
      `mean coverage ${(r(0,0,141)*100).toFixed(0)}% · mean night illumination ${(r(0,0,142)*100).toFixed(0)}% · night risk ${r(0,0,152).toFixed(2)}x`,
      `electricity £${r(0,0,144).toFixed(2)} of £${r(0,0,143).toFixed(2)} paid today · £${r(0,0,145).toFixed(2)} lifetime`,
      `faults today ${r(0,0,146)} · repairs today ${r(0,0,147)} · works £${r(0,0,148).toFixed(2)} today, £${r(0,0,149).toFixed(2)} lifetime · darkness ${(dusk*100).toFixed(0)}%`,
    ].join(" · ");
    const columns = r(36, road, 7);
    $("lighting-lamps").value = String(columns < 0 ? 0 : columns);
    $("lighting-message").textContent = columns < 0
      ? "This street cannot take lighting columns (lanes, works and pedestrian-only segments are excluded)."
      : `Street #${road + 1}: ${columns} of ${r(36,road,8)} columns · ${r(36,road,9)} working · ${r(36,road,10)} failed · ${(r(36,road,11)*100).toFixed(0)}% coverage · illumination ${(r(36,road,12)*100).toFixed(0)}% · electricity £${r(36,road,13).toFixed(2)}/day · ${r(36,road,14)} repairs recorded.`;
    // Numbered item 18: water, drainage and waste. The summary is the town
    // total; the selected street shows its own drains, the flood factor today
    // and how much of the day's rain the segment is carrying.
    const rain = r(0,0,169);
    $("water-summary").textContent = [
      `${r(0,0,153) ? "intake working" : "intake down"} · ${r(0,0,154)}/12 districts served · mean coverage ${(r(0,0,155)*100).toFixed(0)}%`,
      `today ${r(0,0,157).toFixed(2)} of ${r(0,0,156).toFixed(2)} units served · shortfall ${r(0,0,158).toFixed(2)}`,
      `pumping £${r(0,0,160).toFixed(2)} of £${r(0,0,159).toFixed(2)} paid today · £${r(0,0,161).toFixed(2)} lifetime · faults ${r(0,0,162)} · repairs ${r(0,0,163)}`,
      `drain coverage ${(r(0,0,166)*100).toFixed(0)}% · ${r(0,0,167)} drains · ${r(0,0,168)} blocked now · rain ${(rain*100).toFixed(0)}%`,
      `waste ${r(0,0,170).toFixed(2)} units today · collected ${r(0,0,171).toFixed(2)} · backlog ${r(0,0,172).toFixed(2)} · tipping £${r(0,0,173).toFixed(2)} today, £${r(0,0,174).toFixed(2)} lifetime`,
      `works £${r(0,0,164).toFixed(2)} today, £${r(0,0,165).toFixed(2)} lifetime`,
    ].join(" · ");
    const drainCount = r(38, road, 5);
    $("water-drains").value = String(drainCount < 0 ? 0 : drainCount);
    $("water-message").textContent = drainCount < 0
      ? "This street cannot take drains (lanes, works and pedestrian-only segments are excluded)."
      : `Street #${road + 1}: ${drainCount} of ${r(38,road,6)} drains · ${r(38,road,7)} working · ${r(38,road,8)} blocked · ${(r(38,road,9)*100).toFixed(0)}% drained · flood factor ${r(38,road,10).toFixed(2)}x · ${r(38,road,11)} clears recorded · rain ${(r(38,road,12)*100).toFixed(0)}%.`;
  }

  const overlayTitles = {
    1: "STREET CONDITION",
    2: "TRAFFIC · INTENSITY & QUEUES",
    3: "PEDESTRIAN DENSITY",
    4: "PARK CONDITION",
    5: "WATER · SUPPLY & DRAINAGE",
    6: "STREET LIGHTING",
  };
  const overlayLegends = {
    1: ["Worn", "Maintained"],
    2: ["Queued", "Flowing"],
    3: ["Busy", "Quiet"],
    4: ["Neglected", "Maintained"],
    5: ["Flooded / undrained", "Drained"],
    6: ["Dark / faulted", "Lit"],
  };
  const overlayNotes = {
    1: "",
    2: "Amber clouds: vehicle density; wider areas at city scale",
    3: "People walking or waiting outside; street intensity per 100 m² of sidewalk",
    4: "",
    5: "Streets by drained share and today's flood; blue pipes run from the river intake to each district node",
    6: "Night illumination after coverage; a red segment has a failed column",
  };
  function setOverlay(mode) {
    overlay = mode;
    game.set_overlay(mode);
    $("pedestrian-overlay").setAttribute("aria-pressed", mode === 3);
    $("traffic-overlay").setAttribute("aria-pressed", mode === 2);
    $("overlay").setAttribute("aria-pressed", mode === 1);
    $("park-overlay").setAttribute("aria-pressed", mode === 4);
    $("water-overlay").setAttribute("aria-pressed", mode === 5);
    $("lighting-overlay").setAttribute("aria-pressed", mode === 6);
    $("water-overlay-toggle").setAttribute("aria-pressed", mode === 5);
    const key = $("overlay-key");
    key.hidden = !mode;
    key.dataset.mode = String(mode);
    key.querySelector("strong").textContent = overlayTitles[mode] ?? "STREET CONDITION";
    const [low, high] = overlayLegends[mode] ?? overlayLegends[1];
    const note = overlayNotes[mode] ?? "";
    key.querySelector("small").innerHTML = `${low} <span>${high}</span><br>${note}`;
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
    if (picked >= 0) {
      // Slice 12: the inspector lives in the traffic drawer, so a click on a
      // light has to bring that drawer forward before it can be read.
      showTransportTab("signals");
      ui.open("transport");
      showSignal(picked);
      reveal(inspector);
      return true;
    }
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
    if (overlay === 2 || overlay === 3 || overlay === 5 || overlay === 6) {
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
        showTransportTab("streets");
        ui.open("transport");
        return true;
      }
    }
    return false;
  }
  function pointerMove(event) {
    // Slice 11: while a placement tool is armed, report the snap target the
    // click would land on, so placing a light or crosswalk feels immediate.
    if (tool) {
      const x = event.clientX, y = event.clientY;
      if (tool === "signal") {
        const node = game.signal_preview_screen(x, y);
        message(node < 0
          ? "No junction here. Move nearer an arm of the street network."
          : `Snap: junction ${node + 1}. Click to place the traffic light.`);
      } else {
        const road = game.crosswalk_preview_screen(x, y);
        if (road < 0) message("No street here. Move nearer a street segment.");
        else if (tool === "crosswalk") message(`Snap: street #${road + 1}. Click to add its crosswalk.`);
        else message(`Snap: street #${road + 1}${r(5, road, 14) ? " · has a crosswalk, click to remove it." : " · no crosswalk, click to add one."}`);
      }
      return true;
    }
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
    const heatOn = overlay === 2 || overlay === 3;
    heat.hidden = !heatOn;
    heat.style.display = heatOn ? "block" : "none";
    if (heatOn && ++heatFrame % 12 === 0) {
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
    if (transportTab === "agreements") agreements.update();
    if (transportTab === "stops") {
      updateObservations();
      updatePassengerOutcomes();
    }
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
    if (transportTab === "lines") {
      // summary handled below; nothing heavy here yet
    }
    if (transportTab === "signals") {
      if (signal >= 0) showSignal(signal);
      // Slice 12: whichever traffic-lights view is on screen keeps itself current.
      if (!signalTabViews.all.hidden) syncSignalList();
      if (!signalTabViews.map.hidden) syncSignalMap();
    }
    if (transportTab === "streets") syncParking();
    if (transportTab === "incidents") updateIncidents();
    if (transportTab === "incidents") updateIncidents();
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
  // Numbered item 15: traffic incidents. A live view, the full ring, and a
  // raise button that reports on the street currently selected in Streets.
  const incidentTabButtons = { live: $("incident-tab-live"), all: $("incident-tab-all") };
  const incidentTabViews = { live: $("incident-view-live"), all: $("incident-view-all") };
  const incidentKindNames = ["collision", "breakdown", "obstruction", "roadworks"];
  const incidentPhaseNames = ["reported", "responding", "clearing", "cleared"];
  function showIncidentTab(name) {
    for (const key of Object.keys(incidentTabViews)) {
      const on = key === name;
      incidentTabButtons[key].setAttribute("aria-selected", on ? "true" : "false");
      incidentTabViews[key].hidden = !on;
    }
    updateIncidents();
  }
  for (const key of Object.keys(incidentTabButtons)) incidentTabButtons[key].onclick = () => showIncidentTab(key);
  function updateIncidents() {
    const recorded = r(0, 0, 106);
    $("incident-summary").textContent =
      `${recorded} recorded · ${r(0,0,107)} open · ${r(0,0,108)} holding a lane · ${r(0,0,111)} collisions · ${r(0,0,112)} responders on scene · recovery spend ${money(r(0,0,113))} · ${r(0,0,114).toFixed(0)} blocked lane-seconds.`;
    const live = $("incident-live");
    const active = [];
    for (let i = 0; i < recorded && i < 64; i++) if (r(34, i, 15) === 1) active.push(i);
    live.textContent = recorded === 0
      ? "No incidents recorded in this session. A congested segment raises collisions on its own; the buttons below report one by hand."
      : active.length === 0
        ? "Nothing is holding a lane right now."
        : active.map(i => `#${r(34,i,0)} ${incidentKindNames[r(34,i,1)] ?? "?"} on street #${r(34,i,3)+1} lane ${r(34,i,5)} · severity ${r(34,i,6)} · ${incidentPhaseNames[r(34,i,2)] ?? "?"} · ${r(34,i,11).toFixed(0)} lane-seconds blocked`).join(" | ");
    if (!incidentTabViews.all.hidden) {
      const rows = [];
      for (let i = 0; i < recorded && i < 64; i++) {
        rows.push(`<tr><td>#${r(34,i,0)}</td><td>${incidentKindNames[r(34,i,1)] ?? "?"}</td><td>${incidentPhaseNames[r(34,i,2)] ?? "?"}</td><td>street #${r(34,i,3)+1}</td><td>${r(34,i,6)}</td><td>${r(34,i,13)}</td><td>${money(r(34,i,14))}</td></tr>`);
      }
      $("incident-list").innerHTML = rows.length === 0 ? "<p class='note'>Nothing recorded yet.</p>"
        : `<div class="table-scroll"><table><thead><tr><th>#</th><th>Kind</th><th>Phase</th><th>Where</th><th>Severity</th><th>Responders</th><th>Cost</th></tr></thead><tbody>${rows.join("")}</tbody></table></div>`;
    }
  }
  function reportIncident(kind) {
    const road = Number($("traffic-road").value);
    const node = r(5, road, 0);
    const lane = r(5, road, 13) >= 1 ? 1 : 0;
    const severity = Math.max(0, Math.min(3, Math.round(r(5, road, 12) * 3)));
    const cost = game.incident_raise(kind, road, node, lane, severity);
    $("incident-message").textContent = cost < 0
      ? "Could not report that incident: the ring is full or the segment is invalid."
      : `Reported a ${incidentKindNames[kind]} on street #${road + 1}; expected recovery cost about ${money(cost)}.`;
    updateIncidents();
  }
  [["incident-raise-collision",0],["incident-raise-breakdown",1],["incident-raise-obstruction",2],["incident-raise-works",3]].forEach(([id, kind]) => {
    $(id).onclick = () => reportIncident(kind);
  });
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
      showTransportTab("lines");
      update();
      ui.open("transport");
    },
    inspectRoad(id) {
      chooseRoad(id);
      showTransportTab("streets");
      ui.open("transport");
    },
    togglePedestrians: () => setOverlay(overlay === 3 ? 0 : 3),
    toggleTraffic: () => setOverlay(overlay === 2 ? 0 : 2),
    toggleParkCondition: () => setOverlay(overlay === 4 ? 0 : 4),
    toggleCondition: () => setOverlay(overlay === 1 ? 0 : 1),
    toggleWater: () => setOverlay(overlay === 5 ? 0 : 5),
    toggleLighting: () => setOverlay(overlay === 6 ? 0 : 6),
    setOverlay,
    currentOverlay: () => overlay,
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
