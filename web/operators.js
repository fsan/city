import {operatorNames} from "./agreements.js";
// Fleet and staffing panel. Every quote, refusal and cash movement comes from Zig.
export function createOperators(game, message) {
  const $ = (id) => document.getElementById(id);
  const r = (group, id, field) => game.read(group, id, field);
  const money = (n) => `£${n.toFixed(2)}`;
  const units = 8;
  const actions = ["Ready", "Insufficient cash", "No depot space", "Driver qualification missing", "Shift coverage gap", "Unit under maintenance", "Unit still committed to a live service", "Invalid selection"];
  const dispatchStates = ["ready", "off hours", "no cash for dispatch", "no available vehicle", "no on-duty driver", "depot capacity", "all remaining units are under maintenance", "every serviceable unit is committed to a running or clearing bus"];
  const company = () => Number($("fleet-operator").value);
  function syncUnits() {
    const id = company();
    const previous = Number($("fleet-unit").value);
    const options = [];
    for (let unit = 0; unit < units; unit++) {
      if (!r(23, id * units + unit, 0)) continue;
      const condition = r(23, id * units + unit, 1);
      const state = r(23, id * units + unit, 2) ? " · maintenance" : r(23, id * units + unit, 3) ? " · on service" : " · free";
      const option = document.createElement("option");
      option.value = unit;
      option.textContent = `Unit ${unit + 1} · condition ${condition.toFixed(0)}%${state}`;
      options.push(option);
    }
    $("fleet-unit").replaceChildren(...options);
    if (options.some((o) => Number(o.value) === previous)) $("fleet-unit").value = previous;
    $("fleet-unit").disabled = !options.length;
    return options.length > 0 ? Number($("fleet-unit").value) : -1;
  }
  function update() {
    if (!document.body.contains($("fleet-operator"))) return;
    const id = company();
    const unit = syncUnits();
    const sell = unit < 0 ? 7 : r(23, id * units + unit, 8);
    const maintain = unit < 0 ? 7 : r(23, id * units + unit, 2) || r(23, id * units + unit, 3) ? 5 : r(14, id, 29);
    $("fleet-summary").textContent =
      `${operatorNames[id]}: ${r(14,id,0)} owned of ${r(14,id,15)} depot slots · ${r(14,id,17)} serviceable, ${r(14,id,16)} under maintenance · ${r(14,id,18)} free now, ${r(14,id,19)} attached to live or clearing buses · mean condition ${r(14,id,20).toFixed(0)}%. Drivers: ${r(14,id,10)} day-qualified, ${r(14,id,11)} night-qualified; ${r(14,id,9)} on duty. Cash ${money(r(14,id,4))}.`;
    $("fleet-lifecycle").textContent =
      `Lifetime: purchases ${money(r(14,id,21))} · sales ${money(r(14,id,22))} · recruitment ${money(r(14,id,23))} · severance ${money(r(14,id,24))} · maintenance ${money(r(14,id,25))}. A bus costs ${money(r(14,id,31))}; sale returns a condition-scaled price. Maintenance costs ${money(r(14,id,32))} and takes half a day.`;
    $("fleet-buy").disabled = r(14,id,26) !== 0;
    $("fleet-buy-help").textContent = `Buy a bus: ${actions[r(14,id,26)]}. Depot free slots ${r(14,id,36)}.`;
    $("fleet-sell").disabled = sell !== 0;
    $("fleet-sell-help").textContent = unit < 0 ? "No owned unit selected." : `Sell unit ${unit+1} for ${money(r(23,id*units+unit,7))}: ${actions[sell]}.`;
    $("fleet-maintain").disabled = maintain !== 0;
    $("fleet-maintain-help").textContent = unit < 0 ? "No owned unit selected." : `Repair unit ${unit+1} for ${money(r(14,id,32))}: ${actions[maintain]}. The occupying bus finishes its segment and unloads before the repair starts.`;
    $("staff-reasons").textContent =
      `Recruit: day ${actions[r(14,id,27)]} (${money(r(14,id,33))}); night ${actions[r(14,id,28)]} (${money(r(14,id,34))}, needs a day-qualified driver first). Dismiss: day ${actions[r(14,id,29)]}, night ${actions[r(14,id,30)]}; severance ${money(r(14,id,35))}. Wages accrue at £0.12 per in-service bus-second and are already inside the labour total.`;
    const blocked = r(10, Number($("bus-line").value), 34);
    $("fleet-dispatch").textContent = `Selected line dispatch state: ${dispatchStates[blocked] ?? "unknown"}. A clearing bus keeps its unit until every rider has left.`;
  }
  $("fleet-operator").onchange = update;
  $("fleet-unit").onchange = update;
  $("fleet-buy").onclick = () => {
    message(game.fleet_buy(company()) ? "Bus purchased and added to the depot pool." : "Purchase refused: check cash and depot space.");
    update();
  };
  $("fleet-sell").onclick = () => {
    const unit = Number($("fleet-unit").value);
    message(game.fleet_sell(company(), unit) ? "Bus sold at its condition-scaled value." : "Sale refused: the unit is committed to a live or clearing service.");
    update();
  };
  $("fleet-maintain").onclick = () => {
    const unit = Number($("fleet-unit").value);
    message(game.fleet_maintain(company(), unit) ? "Maintenance scheduled. The unit returns at full condition after half a day." : "Maintenance refused: check cash and the unit state.");
    update();
  };
  $("staff-recruit-day").onclick = () => {
    message(game.staff_recruit(company(), 0) ? "Day driver recruited and trained." : "Recruitment refused: check cash.");
    update();
  };
  $("staff-recruit-night").onclick = () => {
    message(game.staff_recruit(company(), 1) ? "Night endorsement completed for an existing driver." : "Night recruitment refused: needs cash and a day-qualified driver already on the roster.");
    update();
  };
  $("staff-dismiss-day").onclick = () => {
    message(game.staff_dismiss(company(), 0) ? "Day driver dismissed with severance." : "Dismissal refused: check cash and the roster.");
    update();
  };
  $("staff-dismiss-night").onclick = () => {
    message(game.staff_dismiss(company(), 1) ? "Night endorsement withdrawn." : "Dismissal refused: check cash and the roster.");
    update();
  };
  return {
    update,
    reset() {
      $("fleet-operator").value = "0";
      update();
    },
  };
}
