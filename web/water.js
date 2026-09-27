import { streetName } from "./data.js";
// Water & waste window. Every rule, price and refusal comes from Zig; this
// module only lays out the scalar reads the ABI already publishes.
export function createWater(game, transport) {
  const $ = (id) => document.getElementById(id);
  const r = (group, id, field) => game.read(group, id, field);
  const metric = (field) => r(0, 0, field);
  const money = (n) => `\u00a3${Number(n).toFixed(2)}`;
  const decoder = new TextDecoder();
  const districtName = (id) =>
    decoder.decode(
      new Uint8Array(game.memory.buffer, game.name_pointer(id), game.name_length(id)),
    );
  const districts = Math.max(0, Math.round(metric(16)));
  const roadCount = () => Math.max(0, Math.round(metric(15)));
  // One row per district and per street is built once; the refresh only writes
  // text into the existing cells, so a live update never steals focus.
  const districtRows = Array.from({ length: districts }, (_, id) => {
    const row = document.createElement("tr");
    const cells = Array.from({ length: 7 }, () => row.appendChild(document.createElement("td")));
    const locate = document.createElement("button");
    cells[0].append(locate);
    locate.onclick = () => {
      const node = r(37, id, 1);
      if (node >= 0) game.focus(11, node);
    };
    $("water-district-rows").append(row);
    return { row, cells, locate };
  });
  const drainRows = Array.from({ length: roadCount() }, (_, id) => {
    const row = document.createElement("tr");
    const cells = Array.from({ length: 7 }, () => row.appendChild(document.createElement("td")));
    const locate = document.createElement("button");
    cells[0].append(locate);
    locate.onclick = () => game.focus(5, id);
    $("water-drain-rows").append(row);
    return { row, cells, locate };
  });
  let streetIds = "";
  function streetOptions() {
    const previous = Number($("water-street").value);
    const ids = [];
    for (let road = 0; road < roadCount(); road++) if (r(38, road, 4) === 1) ids.push(road);
    const key = ids.join(",");
    if (key !== streetIds) {
      streetIds = key;
      $("water-street").replaceChildren(
        ...ids.map((road) => {
          const option = document.createElement("option");
          option.value = road;
          option.textContent = `#${road + 1} · ${streetName(r(5, road, 15))}`;
          return option;
        }),
      );
    }
    if (ids.includes(previous)) $("water-street").value = String(previous);
    $("water-street").disabled = ids.length === 0;
  }
  function refresh() {
    const districtTotal = Math.round(metric(16));
    if (districtTotal !== districts) return; // a rebuilt town re-creates the module
    const installed = metric(178) === 1;
    $("water-window-summary").textContent =
      `${metric(153) ? "Intake working" : "Intake down"} · ${metric(154)}/${districts} districts served · mean coverage ${(metric(155) * 100).toFixed(0)}% · today ${metric(157).toFixed(2)} of ${metric(156).toFixed(2)} units served, shortfall ${metric(158).toFixed(2)} · pumping ${money(metric(160))} of ${money(metric(159))} paid, ${money(metric(161))} lifetime · works ${money(metric(164))} today, ${money(metric(165))} lifetime · intake faults ${metric(162)}, repairs ${metric(163)}.`;
    $("water-intake").textContent = installed
      ? `Intake at (${metric(179).toFixed(1)}, ${metric(180).toFixed(1)}) on the river, nearest walk-graph node ${metric(181) + 1}. ${metric(153) ? "The works is lifting water now." : "The works has lost pressure and is waiting for a repair crew."} Rain today ${(metric(169) * 100).toFixed(0)}%.`
      : "No intake is installed in this town.";
    $("water-locate-intake").disabled = !installed;
    $("water-overlay-toggle").setAttribute("aria-pressed", transport.currentOverlay() === 5 ? "true" : "false");
    districtRows.forEach(({ cells, locate }, id) => {
      const demand = r(37, id, 2), working = r(37, id, 3), coverage = r(37, id, 4);
      const node = r(37, id, 1), run = r(37, id, 6), served = r(37, id, 5) === 1;
      locate.textContent = `${districtName(id)}${served ? "" : " · unserved"}`;
      locate.setAttribute("aria-pressed", served ? "false" : "true");
      cells[1].textContent = demand.toFixed(2);
      cells[2].textContent = working.toFixed(2);
      cells[3].textContent = `${(coverage * 100).toFixed(0)}%`;
      cells[4].textContent = run < 0 ? `unreachable · node ${node + 1}` : `${run.toFixed(0)} m`;
      cells[5].textContent = r(37, id, 7);
      cells[6].textContent = r(37, id, 8);
    });
    const road = Number($("water-street").value);
    const drains = road >= 0 ? r(38, road, 5) : -1;
    $("water-window-drains").value = String(drains < 0 ? 0 : drains);
    $("water-window-drains").disabled = drains < 0;
    $("water-window-drains-apply").disabled = drains < 0;
    $("water-locate-street").disabled = road < 0;
    $("water-street-summary").textContent =
      road < 0 || drains < 0
        ? "No eligible street selected."
        : `Street #${road + 1} ${streetName(r(5, road, 15))}: ${drains} of ${r(38, road, 6)} drains · ${r(38, road, 7)} working · ${r(38, road, 8)} blocked · ${(r(38, road, 9) * 100).toFixed(0)}% drained · flood factor ${r(38, road, 10).toFixed(2)}x · ${r(38, road, 11)} clears recorded. City drain coverage ${(metric(166) * 100).toFixed(0)}% · ${metric(167)} drains · ${metric(168)} blocked now · rain ${(metric(169) * 100).toFixed(0)}%.`;
    drainRows.forEach(({ row, cells, locate }, id) => {
      const eligible = r(38, id, 4) === 1;
      const count = r(38, id, 5);
      row.hidden = !eligible || count < 0;
      if (!eligible || count < 0) return;
      locate.textContent = `#${id + 1} · ${streetName(r(5, id, 15))}`;
      cells[1].textContent = `${count} / ${r(38, id, 6)}`;
      cells[2].textContent = r(38, id, 7);
      cells[3].textContent = r(38, id, 8);
      cells[4].textContent = `${(r(38, id, 9) * 100).toFixed(0)}%`;
      cells[5].textContent = `${r(38, id, 10).toFixed(2)}x`;
      cells[6].textContent = r(38, id, 11);
    });
    $("water-waste").textContent =
      `Waste ${metric(170).toFixed(2)} units today · collected ${metric(171).toFixed(2)} · backlog ${metric(172).toFixed(2)} · tipping ${money(metric(173))} today, ${money(metric(174))} lifetime · ${metric(175)} collection rounds · ${metric(176)} drains blocked today · ${metric(177)} cleared today.`;
  }
  $("water-street").onchange = refresh;
  $("water-locate-street").onclick = () => {
    const road = Number($("water-street").value);
    if (road >= 0) game.focus(5, road);
  };
  $("water-locate-intake").onclick = () => {
    const node = metric(181);
    if (node >= 0) game.focus(11, node);
  };
  $("water-overlay-toggle").onclick = () => {
    transport.toggleWater();
    refresh();
  };
  $("water-window-drains-apply").onclick = () => {
    const road = Number($("water-street").value);
    if (road < 0) return;
    const drains = Number($("water-window-drains").value);
    const cost = game.water_set_drains(road, drains);
    $("water-window-message").textContent = cost < 0
      ? "That street cannot take drains (lanes, works and pedestrian-only segments are excluded, and the count is capped by street class)."
      : cost === 0
        ? `Street #${road + 1} already has ${drains} drain${drains === 1 ? "" : "s"}.`
        : `Street #${road + 1} now has ${drains} drain${drains === 1 ? "" : "s"}; ${money(cost)} of works booked.`;
    streetOptions();
    refresh();
  };
  streetOptions();
  refresh();
  return {
    update() {
      streetOptions();
      refresh();
    },
    reset() {
      streetIds = "";
      $("water-window-message").textContent = "";
      $("water-street").replaceChildren();
      streetOptions();
      refresh();
    },
  };
}
