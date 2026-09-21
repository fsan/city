import { createPlanning } from "./planning.js";
import { createTransport } from "./transport.js";
import { createRenderer } from "./renderer.js";
import { createInterface } from "./ui.js";
import { createReports } from "./reports.js";
const $ = (id) => document.getElementById(id);
const canvas = $("city");
let game;
try {
  const response = await fetch("/build/city.wasm");
  if (!response.ok)
    throw new Error(
      `City build unavailable (${response.status}). Check docker compose logs compiler.`,
    );
  const result = await WebAssembly.instantiate(
    await response.arrayBuffer(),
    {},
  );
  game = result.instance.exports;
  const renderer = createRenderer(canvas);
  game.init();
  $("loading").hidden = true;
  start(renderer);
} catch (error) {
  $("loading").hidden = false;
  $("loading").textContent = `Unable to start: ${error.message}`;
  console.error(error);
}
function start(renderer) {
  const keys = new Set();
  let drag = null,
    last = performance.now(),
    uiElapsed = 1,
    frames = 0,
    frameTime = 0,
    lastSpeed = 1;
  const metric = (field) => game.read(0, 0, field);
  let reports, transport, planning;
  const refresh = () => {
    reports.update();
    transport?.update();
  };
  const speed = (value) => {
    game.set_speed(value);
    if (value) lastSpeed = value;
    refresh();
  };
  document
    .querySelectorAll("[data-speed]")
    .forEach(
      (button) => (button.onclick = () => speed(Number(button.dataset.speed))),
    );
  $("reset-camera").onclick = () => game.reset_camera();
  const toggleOverlay = () => transport.toggleCondition();
  $("overlay").onclick = toggleOverlay;
  const ui = createInterface({
    overlay: toggleOverlay,
    clearInput: () => {
      keys.clear();
      drag = null;
    },
    inspect: () => reports.inspectBuilding(metric(10)),
  });
  transport = createTransport(game, ui);
  reports = createReports(game, ui, transport);
  planning = createPlanning(game, transport);
  $("restart").onclick = () => {
    game.init();
    lastSpeed = 1;
    reports.reset();
    planning.reset();
    transport.reset();
    refresh();
  };
  const saveStatus = text => { $("save-status").textContent = text; };
  $("save-town").onclick = () => {
    try {
      const length = game.save_write();
      if (!length) throw new Error("The town could not fit in the save-file limit.");
      // Copy immediately: subsequent simulation/export may reuse WASM memory.
      const bytes = new Uint8Array(game.memory.buffer, game.save_pointer(), length).slice();
      const url = URL.createObjectURL(new Blob([bytes], {type:"application/json"}));
      const link = document.createElement("a");
      link.href = url;
      link.download = `bellwether-day-${Math.floor(metric(0)/480)+1}-${Date.now()}.json`;
      document.body.append(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      saveStatus(`Town file exported (${(length/1048576).toFixed(1)} MB). Keep the downloaded file to restore this session.`);
    } catch (error) {
      saveStatus(`Save failed: ${error.message}`);
    } finally { last = performance.now(); }
  };
  $("load-town").onclick = () => {
    $("town-file").value = "";
    $("town-file").click();
  };
  $("town-file").onchange = async () => {
    const file = $("town-file").files[0];
    if (!file) return;
    if (!file.size || file.size > game.save_capacity()) {
      saveStatus("Load rejected: choose a non-empty town file no larger than 16 MB. Current town retained.");
      return;
    }
    $("load-town").disabled = $("save-town").disabled = true;
    let restored = false;
    try {
      const bytes = new Uint8Array(await file.arrayBuffer());
      new Uint8Array(game.memory.buffer, game.save_pointer(), bytes.length).set(bytes);
      const result = game.save_load(bytes.length);
      const errors = ["", "File is empty or too large.", "File is malformed or exceeds parser limits.", "File uses an incompatible town format or rules version.", "File contains inconsistent town data."];
      if (result) {
        saveStatus(`Load rejected: ${errors[result] || "Validation failed."} Current town retained.`);
        return;
      }
      restored = true;
      keys.clear(); drag = null; uiElapsed = 0;
      lastSpeed = game.saved_resume_speed();
      reports.reset(); planning.reset(); transport.reset();
      refresh();
      saveStatus(`Loaded ${file.name}. Day ${Math.floor(metric(0)/480)+1}; ${metric(13) ? `running at ${metric(13)}×` : "paused"}. Unapplied drafts cleared.`);
    } catch (error) {
      saveStatus(restored ? `Town loaded, but report refresh failed: ${error.message}` : `Load failed: ${error.message}. Current town retained.`);
    } finally {
      last = performance.now();
      $("load-town").disabled = $("save-town").disabled = false;
    }
  };
  window.addEventListener("keydown", (event) => {
    if (event.ctrlKey || event.metaKey || event.altKey) return;
    const key = event.key.toLowerCase();
    if (!event.target.closest('select, input, textarea, [contenteditable="true"]') && planning.key(key)) {event.preventDefault();return;}
    if (key === "escape") {
      event.preventDefault();
      if (!transport.cancel()) ui.escape();
      return;
    }
    if (
      event.target.closest('select, input, textarea, [contenteditable="true"]')
    )
      return;
    const shortcuts = {
      p: "reports",
      b: "budget",
      j: "works",
      i: "inspector",
      h: "help",
      t: "transport",
    };
    if (shortcuts[key]) {
      if (!event.repeat) ui.toggle(shortcuts[key]);
      event.preventDefault();
      return;
    }
    if (key === " " && event.target.closest("button")) return;
    if (
      [" ", "arrowup", "arrowdown", "arrowleft", "arrowright"].includes(key) &&
      !event.target.closest("button")
    )
      event.preventDefault();
    if (event.target === canvas || event.target === document.body)
      keys.add(key);
    if (event.repeat) return;
    if (key === " ") speed(metric(13) ? 0 : lastSpeed);
    if (key === "r") game.reset_camera();
    if (key === "o") toggleOverlay();
    if (key === "g") transport.toggleTraffic();
    if (key === "f") transport.togglePedestrians();
    if (["1", "2", "3"].includes(key)) speed([1, 4, 16][Number(key) - 1]);
  });
  window.addEventListener("keyup", (event) =>
    keys.delete(event.key.toLowerCase()),
  );
  window.addEventListener("blur", () => {
    keys.clear();
    drag = null;
  });
  document.addEventListener("visibilitychange", () => {
    last = performance.now();
    keys.clear();
  });
  canvas.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) return;
    canvas.focus();
    canvas.setPointerCapture(event.pointerId);
    if (planning.pointerDown(event)) return;
    if (transport.pointerDown(event)) return;
    drag = { x: event.clientX, y: event.clientY, distance: 0 };
  });
  canvas.addEventListener("pointermove", (event) => {
    if (planning.pointerMove(event)) return;
    if (transport.pointerMove(event)) return;
    if (!drag) return;
    const dx = event.clientX - drag.x,
      dy = event.clientY - drag.y;
    drag.distance += Math.abs(dx) + Math.abs(dy);
    game.pan(-dx, -dy);
    drag.x = event.clientX;
    drag.y = event.clientY;
  });
  canvas.addEventListener("pointerup", (event) => {
    if (transport.pointerUp()) {
      drag = null;
      return;
    }
    if (drag && drag.distance < 5) {
      const rect = canvas.getBoundingClientRect();
      game.pick(event.clientX - rect.left, event.clientY - rect.top);
      refresh();
      if (metric(26) >= 0) reports.inspectPerson(metric(26));
      else if (metric(10) >= 0) reports.inspectBuilding(metric(10));
    }
    drag = null;
  });
  canvas.addEventListener("pointercancel", () => {
    transport.pointerUp();
    drag = null;
  });
  canvas.addEventListener("contextmenu", (event) => {
    event.preventDefault();
    const rect = canvas.getBoundingClientRect();
    game.pick(event.clientX - rect.left, event.clientY - rect.top);
    refresh();
    ui.context(event.clientX, event.clientY, metric(10) >= 0);
  });
  canvas.addEventListener(
    "wheel",
    (event) => {
      event.preventDefault();
      const rect = canvas.getBoundingClientRect();
      const units =
        event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? rect.height : 1;
      const amount = Math.exp(
        Math.max(-0.7, Math.min(0.7, -event.deltaY * units * 0.004)),
      );
      game.zoom_at(amount, event.clientX - rect.left, event.clientY - rect.top);
    },
    { passive: false },
  );
  function frame(now) {
    const dt = Math.min((now - last) / 1000, 0.1);
    last = now;
    const horizontal =
      Number(keys.has("d") || keys.has("arrowright")) -
      Number(keys.has("a") || keys.has("arrowleft"));
    const vertical =
      Number(keys.has("s") || keys.has("arrowdown")) -
      Number(keys.has("w") || keys.has("arrowup"));
    game.pan(horizontal * dt * 420, vertical * dt * 420);
    game.rotate((Number(keys.has("e")) - Number(keys.has("q"))) * dt);
    game.update(dt);
    const rect = canvas.getBoundingClientRect();
    const count = game.draw(rect.width, rect.height);
    renderer.draw(
      new Float32Array(game.memory.buffer, game.vertex_pointer(), count * 6),
      count,
    );
    transport.paint();
    uiElapsed += dt;
    frameTime += dt;
    frames++;
    if (uiElapsed > 0.5) {
      refresh();
      uiElapsed = 0;
    }
    if (frameTime > 1) {
      $("fps").textContent = `${Math.round(frames / frameTime)} FPS`;
      frames = 0;
      frameTime = 0;
    }
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
}
