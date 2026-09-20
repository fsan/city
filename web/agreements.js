// Agreement review UI; quotes, delivery and all money rules come from Zig.
export const operatorNames = ["Bellwether Transit", "Ridgeway Passenger", "Community Bus"];
export function createAgreements(game, selectedLine, message) {
  const $ = id => document.getElementById(id);
  const r = (group, id, field) => game.read(group, id, field);
  const money = n => `£${n.toFixed(2)}`;
  const statuses = ["No agreement", "Offered", "Active", "Expired", "Cancelled", "Revised", "Line withdrawn"];
  const reasons = ["Eligible at this price", "Insufficient owned buses", "Price below cost and margin", "Enter valid fleet, days and price", "Insufficient drivers across promised hours", "Working capital below operating buffer"];
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
    $("operator-receipts").textContent = operatorNames.map((name,id) => `${name}: opening ${money(r(14,id,3))} + fares ${money(r(14,id,5))} + subsidies ${money(r(14,id,6))} + agreements ${money(r(14,id,2))} − vehicle/clearance ${money(r(14,id,7))} − labour ${money(r(14,id,8))} = cash ${money(r(14,id,4))}. Drivers: ${r(14,id,9)} on duty, ${r(14,id,13)} occupied (includes clearing), ${r(14,id,14)} available. Committed day/night: ${r(14,id,1)}/${r(14,id,12)}; roster day/night: ${r(14,id,10)}/${r(14,id,11)}.`).join("\n");
    const line = selectedLine();
    const status = line < 0 ? 0 : r(13,line,0);
    const available = r(0,0,3) + (status === 1 ? r(13,line,6) : 0);
    $("service-funding").textContent = `Available for this offer: ${money(available)}${status === 1 ? " (includes the reservation replaced by revision)" : ""}. ${price > available ? "Draft exceeds available funds." : "Quotes do not reserve funds; companies review after time advances."}`;
    $("service-offer").disabled = line < 0 || !r(10,line,0) || status === 2;
    $("service-cancel").disabled = status !== 1 && status !== 2;
  }
  function describe(group, id) {
    const a = field => r(group,id,field);
    if (!a(0)) return "No agreement. This line operates privately from its operator account.";
    const expected = a(11), delivered = a(7);
    const performance = expected > 0 ? `${(100*delivered/expected).toFixed(1)}% of elapsed target` : "No contracted time delivered yet";
    return `Agreement #${a(10)} · Line ${a(16)+1} · ${statuses[a(0)]} · ${operatorNames[a(1)]}.\n${a(2)} buses, ${a(21) ? "06:00–22:00" : "all day (00:00–24:00)"}, for ${(a(3)/480).toFixed(2)} days; maximum ${money(a(4))}.\nPaid ${money(a(5))}; reserved ${money(a(6))}; released ${money(a(13))}.\nDelivery ${delivered.toFixed(1)} / ${expected.toFixed(1)} bus-seconds (${performance}). ${a(0) === 1 || a(0) === 5 ? reasons[a(8)] + "." : `Earned ${money(a(12))}; ${money(Math.max(0, a(4)*expected/Math.max(1,a(22))-a(12)))} not earned through under-delivery to date.`}\nOffered ${stamp(a(14))}${a(0) >= 3 ? `; closed ${stamp(a(15))}` : ""}.`;
  }
  function historyDetail() {
    const number = Number($("service-history").value);
    const count = r(13,0,19);
    const id = Array.from({length: count}, (_,i) => i).find(i => r(17,i,10) === number);
    $("service-history-detail").textContent = id === undefined ? "No closed agreements yet." : describe(17,id);
    $("service-history-route").textContent = id === undefined ? "" : `Route when offered (version ${r(17,id,17)}): ${Array.from({length:r(17,id,18)}, (_,i) => r(17,id,32+i)+1).join(" → ")} → first stop. Later route edits do not rewrite this record.`;
  }
  $("service-history").onchange = historyDetail;
  for (const id of ["service-fleet", "service-days", "service-price", "service-window"]) $(id).addEventListener("input", compare);
  $("service-offer").onclick = () => {
    const [fleet, days, price] = terms();
    const ok = Number.isInteger(fleet) && game.service_window_offer(selectedLine(), Number($("service-operator").value), fleet, days, price, window());
    message(ok ? "Offer reserved for operator review. Any replaced offer is retained in the agreement register." : "Offer rejected: check active line, available funds, fleet 1–3, days 1–7 and price. End an active agreement before re-offering.");
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
    $("service-status").textContent = line < 0 ? "Select a line." : describe(13,line);
    $("service-delivery").textContent = line < 0 ? "" : `${operatorNames[r(10,line,32)]} · ${r(10,line,33) ? "06:00–22:00" : "All day"} · ${r(10,line,9)} waiting at this line’s stops. Requested fleet now: ${r(10,line,11)} moving · ${r(10,line,12)} dwelling · ${r(10,line,13)} held at signals / in queues · ${r(10,line,14)} clearing an old route · ${r(10,line,10)} unavailable. Dispatch check for an empty slot: ${["ready", "off hours", "no cash for dispatch", "no available vehicle", "no on-duty driver"][r(10,line,34)]}. Held, clearing and unavailable buses do not earn payment. Off-hours have no delivery target.`;
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
  return {update, reset() { historyRevision = -1; update(); }};
}
