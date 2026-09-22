import {streetName} from "./data.js";
// Agreement review UI; quotes, delivery and all money rules come from Zig.
export const operatorNames = ["Bellwether Transit", "Ridgeway Passenger", "Community Bus"];
export function createAgreements(game, selectedLine, message) {
  const $ = id => document.getElementById(id);
  const r = (group, id, field) => game.read(group, id, field);
  const money = n => `£${n.toFixed(2)}`;
  const statuses = ["No agreement", "Offered", "Active", "Expired", "Cancelled", "Revised", "Line withdrawn"];
  const reasons = ["Eligible at this price", "Insufficient owned buses for this fleet", "Price below cost and margin", "Enter valid fleet, days and price", "Not enough recruited drivers for the promised hours", "Working capital below the operating buffer", "No night-qualified driver for the all-day window", "Owned buses are under maintenance", "Serviceable buses are committed to another live service"];
  const stamp = t => `day ${Math.floor(t / 480) + 1}, ${String(Math.floor(t % 480 / 20)).padStart(2, "0")}:${String(Math.floor(t % 20 * 3)).padStart(2, "0")}`;
  const rows = operatorNames.map(name => {
    const row = document.createElement("tr");
    const cells = Array.from({length: 4}, () => row.appendChild(document.createElement("td")));
    cells[0].textContent = name;
    $("service-comparison").append(row);
    return cells;
  });
  let historyRevision = -1;
  const window = () => Number($("service-window").value);
  const interval = () => Number($("service-interval").value);
  const terms = () => [Number($("service-fleet").value), Number($("service-days").value), Number($("service-price").value)];
  function compare() {
    const [fleet, days, price] = terms();
    const validFleet = Number.isInteger(fleet);
    rows.forEach((cells, company) => {
      const minimum = validFleet ? game.service_window_quote(selectedLine(), company, fleet, days, price, window(), 0) : -1;
      const reason = validFleet ? game.service_window_quote(selectedLine(), company, fleet, days, price, window(), 1) : 3;
      cells[1].textContent = `${game.service_window_quote(selectedLine(), company, fleet, days, price, window(), 2)} / ${r(14,company,0)}`;
      cells[2].textContent = minimum < 0 ? "—" : money(minimum);
      cells[3].textContent = `${reasons[reason]}. Cash ${money(r(14,company,4))}; required buffer ${money(game.service_window_quote(selectedLine(), company, fleet, days, price, window(), 3))}.`;
    });
    $("operator-receipts").textContent = operatorNames.map((name,id) => `${name}: opening ${money(r(14,id,3))} + fares ${money(r(14,id,5))} + subsidies ${money(r(14,id,6))} + agreements ${money(r(14,id,2))} + bus sales ${money(r(14,id,22))} − bus purchases ${money(r(14,id,21))} − recruitment ${money(r(14,id,23))} − severance ${money(r(14,id,24))} − maintenance ${money(r(14,id,25))} − vehicle/clearance ${money(r(14,id,7))} − wages ${money(r(14,id,8))} = cash ${money(r(14,id,4))}. Fleet: ${r(14,id,0)} owned / ${r(14,id,15)} depot, ${r(14,id,17)} serviceable, ${r(14,id,16)} under maintenance, ${r(14,id,19)} attached to live or clearing buses, ${r(14,id,18)} free; mean condition ${r(14,id,20).toFixed(0)}%. Roster: ${r(14,id,10)} day-qualified / ${r(14,id,11)} night-qualified; on duty ${r(14,id,9)} of ${r(14,id,14) + r(14,id,13)} committed. Committed day/night: ${r(14,id,1)}/${r(14,id,12)}.`).join("\n");
    const line = selectedLine();
    const status = line < 0 ? 0 : r(13,line,0);
    const available = r(0,0,3) + (status === 1 ? r(13,line,6) : 0);
    $("service-funding").textContent = `Available for this offer: ${money(available)}${status === 1 ? " (includes the reservation replaced by revision)" : ""}. ${price > available ? "Draft exceeds available funds." : "Quotes do not reserve funds; companies review after time advances."}`;
    const validTarget = game.service_target_valid(interval());
    $("service-target-help").textContent = !validTarget ? "Enter 0 to disable the interval target, or a whole number from 30 to 600." : interval() === 0 ? "No regularity target in this draft." : `Draft target: no more than ${interval()} simulation seconds between arrivals at each offered stop. Financial quotes below do not assess target feasibility. No payment penalty applies.`;
    $("service-offer").disabled = line < 0 || !r(10,line,0) || status === 2 || !validTarget;
    $("service-cancel").disabled = status !== 1 && status !== 2;
  }
  function describe(group, id) {
    const a = field => r(group,id,field);
    if (!a(0)) return "No agreement. This line operates privately from its operator account.";
    const expected = a(11), delivered = a(7);
    const performance = expected > 0 ? `${(100*delivered/expected).toFixed(1)}% of elapsed target` : "No contracted time delivered yet";
    return `Agreement #${a(10)} · Line ${a(16)+1} · ${statuses[a(0)]} · ${operatorNames[a(1)]}.\n${a(2)} buses, ${a(21) ? "06:00–22:00" : "all day (00:00–24:00)"}, for ${(a(3)/480).toFixed(2)} days; maximum ${money(a(4))}.\nPaid ${money(a(5))}; reserved ${money(a(6))}; released ${money(a(13))}.\nDelivery ${delivered.toFixed(1)} / ${expected.toFixed(1)} bus-seconds (${performance}). ${a(0) === 1 || a(0) === 5 ? reasons[a(8)] + "." : `Earned ${money(a(12))}; ${money(Math.max(0, a(4)*expected/Math.max(1,a(22))-a(12)))} not earned through under-delivery to date.`}\nOffered ${stamp(a(14))}${a(0) >= 3 ? `; closed ${stamp(a(15))}` : ""}.`;
  }
  function regularityReport(id) {
    const container = $(id);
    const summary = document.createElement("p");
    summary.className = "note";
    const scroll = document.createElement("div");
    scroll.style.overflowX = "auto";
    const table = document.createElement("table");
    table.setAttribute("aria-label", id === "service-regularity" ? "Current agreement regularity" : "Closed agreement regularity");
    const head = document.createElement("thead");
    const header = document.createElement("tr");
    for (const name of ["Stop · locate", "Visits", "Pairs", "Exceeded", "Worst interval", "Gap state"]) {
      const cell = document.createElement("th");
      cell.textContent = name;
      header.append(cell);
    }
    head.append(header);
    const body = document.createElement("tbody");
    table.append(head,body);
    scroll.append(table);
    container.append(summary,scroll);
    const rows = Array.from({length:16}, () => {
      const row = document.createElement("tr");
      const cells = Array.from({length:6}, () => row.appendChild(document.createElement("td")));
      const locate = document.createElement("button");
      cells[0].append(locate);
      let node = -1;
      locate.onclick = () => { if (node >= 0) game.focus(11,node); };
      body.append(row);
      return {row,cells,locate,setNode(value) { node = value; }};
    });
    const states = ["Target disabled", "Not accepted", "Suspended: route / service changed", "Off hours", "Awaiting first arrival · grace", "First arrival overdue", "Within current gap allowance", "Arrival gap overdue"];
    return (group, record) => {
      const exists = record !== undefined && record >= 0 && r(group,record,0) > 0;
      const target = exists ? r(group,record,23) : 0;
      scroll.hidden = !target;
      summary.textContent = !exists ? "" : !target ? "No regularity target was included in this agreement." :
        `Maximum interval: ${target} simulation seconds. ${r(group,record,25)} of ${r(group,record,24)} completed eligible pairs exceeded; ${r(group,record,26)} of ${r(group,record,18)} stops have interval evidence. ${r(group,record,27) ? "Assessment suspended after a route or service change; retained results are unchanged." : "Counts describe observed pairs, not a blanket service pass."} ${r(group,record,0) >= 3 ? "Gap states are frozen at closure." : "Gap states are live."} No payment penalty applies.`;
      if (!target) return;
      const stopGroup = group === 13 ? 20 : 21;
      rows.forEach(({row,cells,locate,setNode}, index) => {
        const id = record * 16 + index;
        const node = r(stopGroup,id,0);
        row.hidden = node < 0;
        if (node < 0) return;
        setNode(node);
        locate.textContent = `${r(11,node,6)} ${streetName(r(11,node,5))} · stop ${node+1}`;
        cells[1].textContent = r(stopGroup,id,1);
        cells[2].textContent = r(stopGroup,id,2) || "No pairs yet";
        cells[3].textContent = r(stopGroup,id,2) ? r(stopGroup,id,3) : "—";
        const worst = r(stopGroup,id,5), age = r(stopGroup,id,7);
        cells[4].textContent = worst < 0 ? "—" : `${worst.toFixed(1)} s`;
        cells[5].textContent = `${states[r(stopGroup,id,6)]}${age < 0 ? "" : ` · ${age.toFixed(1)} s`}`;
      });
    };
  }
  const currentRegularity = regularityReport("service-regularity");
  const closedRegularity = regularityReport("service-history-regularity");
  function historyDetail() {
    const number = Number($("service-history").value);
    const count = r(13,0,19);
    const id = Array.from({length: count}, (_,i) => i).find(i => r(17,i,10) === number);
    closedRegularity(17,id);
    $("service-history-detail").textContent = id === undefined ? "No closed agreements yet." : describe(17,id);
    $("service-history-route").textContent = id === undefined ? "" : `Route when offered (version ${r(17,id,17)}): ${Array.from({length:r(17,id,18)}, (_,i) => r(17,id,32+i)+1).join(" → ")} → first stop. Later route edits do not rewrite this record.`;
  }
  $("service-history").onchange = historyDetail;
  for (const id of ["service-fleet", "service-days", "service-price", "service-window", "service-interval"]) $(id).addEventListener("input", compare);
  $("service-offer").onclick = () => {
    const [fleet, days, price] = terms();
    const ok = Number.isInteger(fleet) && game.service_target_offer(selectedLine(), Number($("service-operator").value), fleet, days, price, window(), interval());
    message(ok ? "Offer reserved for operator review. Any replaced offer is retained in the agreement register." : "Offer rejected: check active line, available funds, fleet 1–3, days 1–7, price and interval target (0 or whole 30–600). End an active agreement before re-offering.");
    update();
  };
  $("service-cancel").onclick = () => {
    const line = selectedLine(), before = r(13,line,5), reserve = r(13,line,6);
    game.service_cancel(line);
    message(`Agreement ended: ${money(r(13,line,5)-before)} final payment; ${money(reserve-(r(13,line,5)-before))} released. The route continues privately with the same operator and hours; choose an operator and publish a replacement offer when ready.`);
    update();
  };
  function update() {
    compare();
    const line = selectedLine();
    currentRegularity(13,line);
    $("service-status").textContent = line < 0 ? "Select a line." : describe(13,line);
    $("service-delivery").textContent = line < 0 ? "" : `${operatorNames[r(10,line,32)]} · ${r(10,line,33) ? "06:00–22:00" : "All day"} · ${r(10,line,9)} waiting at this line’s stops. Requested fleet now: ${r(10,line,11)} moving · ${r(10,line,12)} dwelling · ${r(10,line,13)} held at signals / in queues · ${r(10,line,14)} clearing an old route · ${r(10,line,10)} unavailable. ${r(10,line,10) > 0 || r(10,line,34) === 1 ? "Dispatch: " + ["ready", "off hours", "no cash for dispatch", "no available vehicle", "no on-duty driver"][r(10,line,34)] + "." : "Requested slots are occupied; clearing buses must unload before replacement."} Held, clearing and unavailable buses do not earn payment. Off-hours have no delivery target.`;
    const revision = r(13,0,20);
    if (revision !== historyRevision) {
      historyRevision = revision;
      const previous = $("service-history").value;
      const options = Array.from({length:r(13,0,19)}, (_,i) => {
        const option = document.createElement("option");
        option.value = r(17,i,10);
        option.textContent = `#${r(17,i,10)} · Line ${r(17,i,16)+1} · ${operatorNames[r(17,i,1)]} · ${statuses[r(17,i,0)]}`;
        return option;
      });
      $("service-history").replaceChildren(...options);
      if (options.some(o => o.value === previous)) $("service-history").value = previous;
      $("service-history").disabled = !options.length;
    }
    historyDetail();
  }
  return {update, reset() {
    historyRevision = -1;
    $("service-history").replaceChildren();
    for (const [id,value] of [["service-operator","0"],["service-fleet","2"],["service-days","1"],["service-price","240"],["service-window","1"],["service-interval","0"]]) $(id).value=value;
    update();
  }};
}
