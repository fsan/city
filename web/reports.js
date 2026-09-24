import {operatorNames} from "./agreements.js";
import {
  createData,
  streetName,
  streetClasses,
  parkingBands,
  kinds,
  statusNames,
  reasons,
  commandErrors,
  money,
  signedMoney,
  timeLabel,
} from "./data.js";
const $ = (id) => document.getElementById(id);
const link = (text, action) => ({ text, action });
// Reuse cells so a live refresh does not remove the keyboard-focused button.
function rows(id, values) {
  const body = $(id);
  values.forEach((values, index) => {
    const row =
      body.children[index] || body.appendChild(document.createElement("tr"));
    values.forEach((value, column) => {
      const cell =
        row.children[column] || row.appendChild(document.createElement("td"));
      if (typeof value === "object") {
        let button = cell.querySelector("button");
        if (!button) {
          cell.replaceChildren();
          button = cell.appendChild(document.createElement("button"));
        }
        if (button.textContent !== value.text) button.textContent = value.text;
        button.onclick = value.action;
      } else {
        const text = String(value);
        if (cell.textContent !== text || cell.querySelector("button"))
          cell.textContent = text;
      }
    });
    while (row.children.length > values.length) row.lastElementChild.remove();
  });
  while (body.children.length > values.length) body.lastElementChild.remove();
}
function options(select, values) {
  select.replaceChildren(
    ...values.map(([value, text]) => {
      const option = document.createElement("option");
      option.value = value;
      option.textContent = text;
      return option;
    }),
  );
}
export function createReports(game, ui, transport) {
  const data = createData(game),
    { read: r, metric: m, buildings, districts, companyName } = data;
  const people = Array.from({ length: m(7) }, (_, id) => ({
    id,
    home: r(3, id, 0),
    employer: r(3, id, 1),
  }));
  let streetIds = Array.from({ length: m(15) }, (_, id) => id);
  let personPage = 0,
    streetPage = 0,
    selectedOrder = -1,
    selected = { kind: 1, id: -1 };
  const pageSize = 18;
  const district = () => Number($("district-filter").value);
  const inDistrict = (id) => district() < 0 || id === district();
  const activity = (id) =>
    ["At destination", "Travelling", "At work site"][r(3, id, 8)];
  const buildingName = (id) => `${kinds[buildings[id].kind]} #${id + 1}`;
  const visible = (id) => !$(id).hidden;
  options($("district-filter"), [
    [-1, "Whole city"],
    ...districts.map((name, id) => [id, name]),
  ]);
  options(
    $("work-district"),
    districts.map((name, id) => [id, name]),
  );
  function streetOptions(selectedStreet) {
    const area = Number($("work-district").value);
    const ids = streetIds.filter((id) => r(5, id, 4) === area);
    options(
      $("work-street"),
      ids.map((id) => [
        id,
        `Street ${id + 1} · nodes ${r(5, id, 0) + 1}–${r(5, id, 1) + 1}`,
      ]),
    );
    $("work-street").value = ids.includes(selectedStreet)
      ? selectedStreet
      : ids.reduce(
          (best, id) => (r(5, id, 5) < r(5, best, 5) ? id : best),
          ids[0],
        );
  }
  function chooseStreet(id) {
    $("work-district").value = r(5, id, 4);
    streetOptions(id);
  }
  streetOptions(0);
  $("work-district").onchange = () => {
    streetOptions(-1);
    updateWorks();
  };
  // Scroll the window's own body to reveal a row. scrollIntoView() would also
  // scroll the map container, which drags the whole game view sideways and
  // leaves the panel over the button the player just clicked.
  function reveal(element) {
    const body = element.closest(".window-body");
    if (!body) return;
    const outer = body.getBoundingClientRect(), inner = element.getBoundingClientRect();
    if (inner.bottom > outer.bottom) body.scrollTop += inner.bottom - outer.bottom + 8;
    else if (inner.top < outer.top) body.scrollTop -= outer.top - inner.top + 8;
  }
  function inspect(kind, id) {
    selected = { kind, id };
    game.select_resident(kind === 3 ? id : 0xffffffff);
    ui.open("inspector");
    updateInspector();
  }
  function showDistrict(id) {
    $("district-filter").value = id;
    personPage = 0;
    streetPage = 0;
    updateReports();
  }
  function offerStreet(id) {
    chooseStreet(id);
    ui.open("works");
    updateWorks();
  }
  function openOrder(id) {
    selectedOrder = id;
    chooseStreet(r(6, id, 0));
    $("work-scope").value = r(6, id, 1);
    $("work-price").value = r(6, id, 2);
    $("revised-price").value = Math.round(r(6, id, 2));
    $("confirm-cancel").hidden = true;
    ui.open("works");
    updateWorks();
    reveal($("order-detail"));
  }
  $("district-filter").onchange = () => {
    personPage = 0;
    streetPage = 0;
    updateReports();
  };
  $("resident-search").oninput = () => {
    personPage = 0;
    updateReports();
  };
  $("contractors-only").onchange = updateReports;
  for (const [id, step] of [
    ["people-prev", -1],
    ["people-next", 1],
    ["street-prev", -1],
    ["street-next", 1],
  ])
    $(id).onclick = () => {
      if (id.startsWith("people")) personPage = Math.max(0, personPage + step);
      else streetPage = Math.max(0, streetPage + step);
      updateReports();
    };
  $("home-tax").oninput = taxPreview;
  $("business-tax").oninput = taxPreview;
  $("apply-taxes").onclick = () => {
    const home = Number($("home-tax").value),
      business = Number($("business-tax").value);
    const valid =
      $("home-tax").value !== "" &&
      $("business-tax").value !== "" &&
      game.apply_taxes(home, business);
    $("tax-status").textContent = valid
      ? "Policy applied. Next collection at midnight."
      : "Enter rates between 0% and 5%.";
    updateBudget();
  };
  $("funding").onchange = () => {
    game.set_funding(Number($("funding").value));
    updateBudget();
  };
  for (const id of ["work-street", "work-scope", "work-price"])
    $(id).addEventListener("input", updateWorks);
  $("locate-street").onclick = () =>
    game.focus(5, Number($("work-street").value));
  $("submit-order").onclick = () => {
    const result = game.offer(
      Number($("work-street").value),
      Number($("work-scope").value),
      Number($("work-price").value),
    );
    $("order-message").textContent = commandErrors[result];
    if (!result) openOrder(m(17) - 1);
    updateWorks();
  };
  $("revise-order").onclick = () => {
    const result = game.revise(selectedOrder, Number($("revised-price").value));
    $("order-message").textContent = result
      ? commandErrors[result]
      : "Offer revised. Companies will reconsider it.";
    if (!result) $("work-price").value = r(6, selectedOrder, 2);
    updateWorks();
  };
  $("cancel-order").onclick = () => {
    $("confirm-cancel").hidden = false;
    updateWorks();
  };
  $("confirm-cancel").onclick = () => {
    $("order-message").textContent = game.cancel_order(selectedOrder)
      ? "Order cancelled and funds settled."
      : "This order can no longer be cancelled.";
    $("confirm-cancel").hidden = true;
    updateWorks();
  };
  $("locate-order").onclick = () => game.focus(5, r(6, selectedOrder, 0));
  $("export-ledger").onclick = () => {
    const values = [
      ["time", "category", "party", "order", "amount", "cash"],
      ...ledgerValues(Math.min(m(18), 1024)),
    ];
    const csv = values
      .map((row) =>
        row
          .map((value) => '"' + String(value).replaceAll('"', '""') + '"')
          .join(","),
      )
      .join("\n");
    const url = URL.createObjectURL(new Blob([csv], { type: "text/csv" }));
    const a = document.createElement("a");
    a.href = url;
    a.download = "bellwether-ledger.csv";
    a.click();
    URL.revokeObjectURL(url);
  };
  function updateReports() {
    if (!visible("reports-window")) return;
    const filteredPeople = people.filter((p) =>
      inDistrict(buildings[p.home].district),
    );
    if (visible("overview-report")) {
      $("report-population").textContent =
        filteredPeople.length.toLocaleString();
      $("employed").textContent = filteredPeople
        .filter((p) => p.employer >= 0)
        .length.toLocaleString();
      $("walking").textContent = filteredPeople
        .filter((p) => r(3, p.id, 8) === 1)
        .length.toLocaleString();
      const sites = buildings.filter((b) => inDistrict(b.district));
      $("city-summary").textContent =
        `${district() < 0 ? "Whole city" : districts[district()]} · ${sites.length} buildings · ${filteredPeople.filter((p) => p.employer < 0).length} jobseekers. Town elevation ranges from 0 to 24 metres.`;
      rows(
        "land-use",
        kinds.map((kind, id) => [
          kind,
          sites.filter((b) => b.kind === id).length,
          [
            "Housing",
            "Employment",
            "Employment",
            "Civic workplace",
            "Government",
            "Recreation",
            "Street contractor",
            "Undeveloped",
            "Parking",
            "Parking",
            "Housing",
            "Employment",
            "Recreation",
            "Public space",
          ][id],
        ]),
      );
    }
    if (visible("districts-report"))
      rows(
        "district-rows",
        districts.flatMap((name, id) =>
          inDistrict(id)
            ? [
                [
                  link(name, () => showDistrict(id)),
                  r(2, id, 2),
                  r(2, id, 3),
                  `${r(2, id, 0).toFixed(1)}%`,
                  `${r(2, id, 1).toFixed(1)}%`,
                ],
              ]
            : [],
        ),
      );
    if (visible("mobility-report")) {
      const ids = streetIds.filter((id) => inDistrict(r(5, id, 4)));
      streetPage = Math.min(
        streetPage,
        Math.max(0, Math.ceil(ids.length / pageSize) - 1),
      );
      $("street-page").textContent =
        `${ids.length} streets · page ${streetPage + 1} / ${Math.max(1, Math.ceil(ids.length / pageSize))}`;
      $("street-prev").disabled = streetPage === 0;
      $("street-next").disabled = (streetPage + 1) * pageSize >= ids.length;
      rows(
        "street-rows",
        ids
          .slice(streetPage * pageSize, (streetPage + 1) * pageSize)
          .map((id) => [
            link(`#${id + 1}`, () => inspect(5, id)),
            districts[r(5, id, 4)],
            `${r(5, id, 2).toFixed(1)} m`,
            `${(r(5, id, 3) * 100).toFixed(0)}%`,
            `${r(5, id, 5).toFixed(1)}%`,
            r(5, id, 6) ? "Active" : r(5, id, 9) ? "Ordered" : "—",
          ]),
      );
    }
    if (visible("people-report")) {
      const search = $("resident-search").value;
      const ids = filteredPeople.filter(
        (p) => search === "" || p.id === Number(search) - 1,
      );
      personPage = Math.min(
        personPage,
        Math.max(0, Math.ceil(ids.length / pageSize) - 1),
      );
      $("people-page").textContent =
        `${ids.length} residents · page ${personPage + 1} / ${Math.max(1, Math.ceil(ids.length / pageSize))}`;
      $("people-prev").disabled = personPage === 0;
      $("people-next").disabled = (personPage + 1) * pageSize >= ids.length;
      rows(
        "people-rows",
        ids
          .slice(personPage * pageSize, (personPage + 1) * pageSize)
          .map((p) => [
            link(`Resident ${p.id + 1}`, () => inspect(3, p.id)),
            link(`#${p.home + 1}`, () => inspect(1, p.home)),
            p.employer < 0
              ? `Jobseeker · ${["general", "clerical", "professional"][r(3, p.id, 35)]}`
              : link(companyName(p.employer), () => inspect(4, p.employer)) +
                ` · ${["general", "clerical", "professional"][r(3, p.id, 35)]}`,
            activity(p.id),
            r(3, p.id, 7) >= 0
              ? link(`Order ${r(3, p.id, 7) + 1}`, () =>
                  openOrder(r(3, p.id, 7)),
                )
              : "Daily routine",
          ]),
      );
    }
    if (visible("housing-report")) {
      $("housing-summary").textContent =
        `${m(44).toLocaleString()} housing units · ${m(45).toLocaleString()} occupied · ${m(46).toLocaleString()} vacant. Last day: ${m(49)} moves, ${m(50)} displacements, ${m(51)} applications, ${m(52).toFixed(2)} arrears.`;
      $("housing-units").textContent = m(44).toLocaleString();
      $("housing-occupied").textContent = m(45).toLocaleString();
      $("housing-vacant").textContent = m(46).toLocaleString();
      const unitIds = buildings
        .map((b, id) => ({ b, id }))
        .filter(({ b }) => inDistrict(b.district) && b.kind === 0);
      rows(
        "housing-rows",
        unitIds.slice(0, 40).map(({ id }) => [
          link(`Unit #${id + 1}`, () => inspect(1, id)),
          districts[buildings[id].district],
          r(26, id, 1) ? "Rented" : "Owned",
          money(r(26, id, 1) ? r(26, id, 2) : r(26, id, 3)),
          r(26, id, 6),
          money(r(26, id, 5)),
          r(26, id, 8) < 0
            ? "—"
            : link(`Unit #${r(26, id, 8) + 1}`, () => inspect(1, r(26, id, 8))),
          ["Idle", "Pending", "Moved", "Displaced", "Refused"][r(26, id, 9)],
        ]),
      );
    }
    if (visible("companies-report")) {
      const ids = Array.from({ length: m(9) }, (_, i) => i).filter(
        (id) =>
          inDistrict(buildings[r(4, id, 0)].district) &&
          (!$("contractors-only").checked || r(4, id, 4)),
      );
      rows(
        "company-rows",
        ids.map((id) => [
          link(companyName(id), () => inspect(4, id)),
          `${r(27, id, 5)} / ${r(27, id, 6)}`,
          money(r(4, id, 3)),
          r(4, id, 4) ? "Street repairs" : "Local employer",
          r(4, id, 5) < 0
            ? "—"
            : link(`#${r(4, id, 5) + 1}`, () => openOrder(r(4, id, 5))),
        ]),
      );
    }
    if (visible("history-report"))
      rows(
        "history-rows",
        Array.from({ length: Math.min(96, m(19)) }, (_, id) => [
          timeLabel(r(8, id, 0)),
          money(r(8, id, 1)),
          money(r(8, id, 2)),
          r(8, id, 3),
          `${r(8, id, 4).toFixed(1)}%`,
        ]).reverse(),
      );
  }
  function taxPreview() {
    const home = Number($("home-tax").value),
      business = Number($("business-tax").value);
    const value = (m(22) * home) / 100 / 360 + (m(23) * business) / 100 / 360;
    $("tax-preview").textContent =
      `Draft daily assessment: ${money(value)} (${signedMoney(value - m(4))} versus active policy). Actual receipts can be lower if firms cannot pay.`;
  }
  const ledgerKinds = [
    "Opening reserves",
    "Residential tax",
    "Commercial tax",
    "Other services",
    "Street maintenance",
    "Contract settlement",
    "Cancellation settlement",
    "Bus boarding subsidy",
    "Bus service agreement",
    "Road construction",
    "Service credit",
  ];
  function ledgerValues(limit) {
    return Array.from({ length: limit }, (_, id) => {
      const kind = r(7, id, 3),
        party = r(7, id, 4),
        order = r(7, id, 5);
      return [
        timeLabel(r(7, id, 0)),
        ledgerKinds[kind],
        party < 0
          ? "City"
          : kind === 1 || kind === 2
            ? `Property ${party + 1}`
            : kind === 8 || kind === 10 ? operatorNames[party] : companyName(party),
        order < 0 ? "—" : kind === 8 || kind === 10 ? `Agreement #${order}` : String(order + 1),
        r(7, id, 1).toFixed(2),
        r(7, id, 2).toFixed(2),
      ];
    });
  }
  function updateBudget() {
    if (!visible("budget-window")) return;
    $("budget-reserves").textContent = money(m(1));
    $("reserved").textContent = money(m(2));
    $("available").textContent = money(m(3));
    $("home-base").textContent = money(m(22));
    $("business-base").textContent = money(m(23));
    $("home-rate").textContent = m(20).toFixed(2) + "%";
    $("business-rate").textContent = m(21).toFixed(2) + "%";
    $("funding").value = String(m(11));
    $("funding-note").textContent =
      `Operating payments occur every 30 simulation seconds. Current maintenance coverage: ${(m(12) * 100).toFixed(0)}%. Unfunded maintenance allows deterioration. Contract reserves are protected.`;
    $("projected-revenue").textContent = money(m(4));
    $("projected-expense").textContent = money(m(5));
    $("budget-balance").textContent = signedMoney(m(4) - m(5));
    $("actual-revenue").textContent = money(m(24));
    $("actual-expense").textContent = money(m(25));
    const weekNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    const phaseNames = ["sleep", "morning commute", "work", "evening", "leisure", "night"];
    $("period-note").textContent =
      `${weekNames[m(29)]} week ${m(32) + 1} · ${phaseNames[m(31)]} · next period boundary ${timeLabel(m(33))}; retained periods ${m(34)}. ` +
      `Weekly summaries reconcile recorded ledger movements only.`;
    $("household-note").textContent =
      `${m(35)} households in arrears · ${money(m(36))} total household arrears · ${m(37)} households tracked. Arrears are private household state, not municipal debt.`;
    $("employment-note").textContent =
      `${m(38).toLocaleString()} jobseekers · ${m(39).toLocaleString()} open posts · last day ${m(40)} hires, ${m(41)} dismissals · ${money(m(42))} wages paid. Unpaid employer wages are wage arrears, not municipal debt.`;
    taxPreview();
    rows(
      "ledger-rows",
      ledgerValues(Math.min(80, m(18))).map((v) => [
        v[0],
        `${v[1]} · ${v[2]}`,
        v[3],
        v[4],
        v[5],
      ]),
    );
  }
  function updateWorks() {
    if (!visible("works-window")) return;
    const road = Number($("work-street").value),
      scope = Number($("work-scope").value),
      price = Number($("work-price").value);
    const effective = Math.min(scope, 100 - r(5, road, 5));
    $("work-location").textContent =
      `${districts[r(5, road, 4)]} · condition ${r(5, road, 5).toFixed(1)}% · ${(r(5, road, 3) * 100).toFixed(0)}% grade · ${r(5, road, 2).toFixed(1)} metres.`;
    $("offer-summary").textContent =
      `Effective improvement: ${Math.max(0, effective).toFixed(1)} points. ${money(price)} reserved from ${money(m(3))} uncommitted funds. Delivery time depends on crew travel and work.`;
    const contractors = Array.from({ length: m(9) }, (_, i) => i).filter((id) =>
      r(4, id, 4),
    );
    rows(
      "quote-rows",
      contractors.map((id) => [
        link(companyName(id), () => inspect(4, id)),
        money(game.quote(id, road, Math.max(1, effective), price, 0)),
        reasons[game.quote(id, road, Math.max(1, effective), price, 1)],
      ]),
    );
    rows(
      "order-rows",
      Array.from({ length: m(17) }, (_, id) => [
        link(`#${id + 1} / street ${r(6, id, 0) + 1}`, () => openOrder(id)),
        statusNames[r(6, id, 3)],
        r(6, id, 4) < 0 ? "Awaiting firm" : companyName(r(6, id, 4)),
        `${(r(6, id, 5) * 100).toFixed(0)}%`,
        money(r(6, id, 2)),
      ]),
    );
    $("order-detail").hidden = selectedOrder < 0 || selectedOrder >= m(17);
    if ($("order-detail").hidden) return;
    const id = selectedOrder,
      status = r(6, id, 3),
      company = r(6, id, 4),
      progress = r(6, id, 5),
      offered = r(6, id, 2);
    $("order-title").textContent = `Order ${id + 1} · ${statusNames[status]}`;
    $("order-description").textContent =
      `Street ${r(6, id, 0) + 1}; ${r(6, id, 1).toFixed(1)} condition points. ${company < 0 ? "No contractor has accepted. Consult company responses for this street and price." : companyName(company) + "."} Contractor costs so far: ${money(r(6, id, 10))}. City paid: ${money(r(6, id, 11))}.${status === 5 ? " Blocked: " + reasons[r(6, id, 9)] + "." : ""}`;
    $("revise-order").disabled = status !== 0;
    $("revised-price").disabled = status !== 0;
    $("cancel-order").disabled = status === 3 || status === 4;
    if (status === 3 || status === 4) $("confirm-cancel").hidden = true;
    $("confirm-cancel").textContent =
      `Confirm · ${money(company < 0 ? 0 : Math.min(offered, offered * (0.05 + progress * 0.95)))} settlement`;
    const crew = $("crew-list");
    if (company >= 0) {
      for (let i = 0; i < r(4, company, 6); i++) {
        const person = r(4, company, 8 + i);
        const button =
          crew.children[i] ||
          crew.appendChild(document.createElement("button"));
        button.textContent = `Worker ${person + 1} · ${activity(person)} · inspect route`;
        button.onclick = () => inspect(3, person);
      }
    } else crew.replaceChildren();
  }
  function updateInspector() {
    if (!visible("inspector-window") || selected.id < 0) return;
    const { kind, id } = selected;
    let title,
      fields = [],
      actions = [];
    if (kind === 1) {
      const b = buildings[id];
      title = buildingName(id);
      fields = [
        ["Neighbourhood", districts[b.district]],
        ["Address", `${r(1,id,14)} ${streetName(r(1,id,13))}`],
        ["Ground elevation", `${r(1, id, 3).toFixed(1)} m`],
        ["Sun exposure (assessment proxy)", `${(r(1,id,12)*100).toFixed(0)}%`],
        ["Building height", `${r(1, id, 2).toFixed(1)} m`],
        ["Residents", r(1, id, 5)],
        ["Assessed value", money(r(1, id, 4))],
        ["Daily property bill", money(r(1, id, 7))],
        ["Arrears", money(r(1, id, 8))],
        ["Tenure", r(26, id, 1) ? "Rented" : "Owned"],
        ["Daily housing charge", money(r(26, id, 1) ? r(26, id, 2) : r(26, id, 3))],
        ["Housing arrears", money(r(26, id, 5))],
        ["Occupancy", r(26, id, 6)],
        ["Move state", ["Idle", "Pending", "Moved", "Displaced", "Refused"][r(26, id, 9)]],
      ];
      actions = [
        link("Locate building", () => game.focus(1, id)),
        link("Local streets", () => {
          showDistrict(b.district);
          ui.open("reports");
          ui.showReport("mobility");
        }),
      ];
      const resident = people.find((p) => p.home === id);
      if (resident)
        actions.push(
          link(`Inspect resident ${resident.id + 1}`, () =>
            inspect(3, resident.id),
          ),
        );
      if (b.employer >= 0)
        actions.push(link("Inspect employer", () => inspect(4, b.employer)));
    } else if (kind === 3) {
      const home = r(3, id, 0),
        employer = r(3, id, 1),
        order = r(3, id, 7);
      title = `Resident ${id + 1}`;
      fields = [
        ["Home", buildingName(home)],
        ["Employer", companyName(employer)],
        ["Activity", activity(id)],
        ["Routine", ["sleep", "morning commute", "work", "evening", "leisure", "night"][r(3, id, 33)]],
        ["Shift", ["day 06-14", "evening 14-22", "night 22-06"][r(3, id, 32)]],
        ["Skill", ["general", "clerical", "professional"][r(3, id, 35)] || "general"],
        ["Household", `#${r(3, id, 34) + 1} · balance ${money(r(25, r(3, id, 34), 2))} · income ${money(r(25, r(3, id, 34), 3))} · essentials ${money(r(25, r(3, id, 34), 4))} · arrears ${money(r(25, r(3, id, 34), 5))}`],
        [
          "Travel scores · walk / cycle / car / bus",
          [21, 22, 23, 24]
            .map((f) =>
              r(3, id, f) < 0 ? "Unavailable" : r(3, id, f).toFixed(0),
            )
            .join(" / "),
        ],
        [
          "Score meaning",
          "Time + cost weighted by income; lowest available wins at departure",
        ],
        ["Travel mode", ["Walk", "Cycle", "Car", "Bus"][r(3, id, 13)]],
        [
          "Parked car / bicycle nodes",
          `${r(3, id, 16) ? r(3, id, 20) + 1 : "—"} / ${r(3, id, 17) ? r(3, id, 26) + 1 : "—"}`,
        ],
        ["Bus line", r(3, id, 13) === 3 ? `Line ${r(3, id, 25) + 1}` : "—"],
        [
          "Travel wallet / daily income",
          `${money(r(3, id, 14))} / ${money(r(3, id, 15))}`,
        ],
        [
          "Own transport",
          `${r(3, id, 16) ? "Car" : "No car"} · ${r(3, id, 17) ? "Bicycle" : "No bicycle"}`,
        ],
        [
          "Bus wait / aboard",
          `${r(3, id, 18).toFixed(0)} seconds / ${r(3, id, 19) >= 0 ? "Yes" : "No"}`,
        ],
        ["Trip markers", "Blue roof: origin · amber roof: destination"],
        ["Origin node", r(3,id,27)+1],
        ["Current node → next", `${r(3, id, 3) + 1} → ${r(3, id, 4) + 1}`],
        [
          "Destination",
          r(3, id, 7) >= 0
            ? `Work site · node ${r(3, id, 2) + 1}`
            : buildings.find((b) => b.node === r(3, id, 2))
              ? buildingName(r(3,id,28))
              : `Node ${r(3, id, 2) + 1}`,
        ],
        [
          "Remaining route estimate",
          r(3, id, 12) < 0
            ? "Depends on traffic / bus arrival"
            : `${r(3, id, 12).toFixed(0)} simulation seconds`,
        ],
        [
          "Current / last trip",
          `${r(3, id, 10).toFixed(0)} / ${r(3, id, 11).toFixed(0)} seconds`,
        ],
        ["Completed trips", r(3, id, 9)],
        ["Home tax share / resident", money(r(1, home, 7) / r(1, home, 5))],
        ["Work order", order < 0 ? "None" : `#${order + 1}`],
      ];
      actions = [
        link("Locate & show route", () => game.focus(3, id)),
        link("Inspect home", () => inspect(1, home)),
      ];
      if (r(3, id, 13) === 3)
        actions.push(
          link("Inspect bus service", () =>
            transport.inspectLine(r(3, id, 25)),
          ),
        );
      if (employer >= 0)
        actions.push(link("Inspect employer", () => inspect(4, employer)));
      if (order >= 0)
        actions.push(link("Inspect work order", () => openOrder(order)));
    } else if (kind === 4) {
      title = companyName(id);
      const b = r(4, id, 0),
        order = r(4, id, 5);
      fields = [
        ["Premises", buildingName(b)],
        ["Employees / capacity", `${r(4, id, 1)} / ${r(4, id, 2)}`],
        ["Vacancies", r(27, id, 0)],
        ["Posted daily wage", money(r(27, id, 1))],
        ["Skill required", ["general", "clerical", "professional"][r(27, id, 2)]],
        ["Wage arrears", money(r(27, id, 3))],
        ["Staffing pressure", `${(r(27, id, 4) * 100).toFixed(0)}%`],
        ["Operating cash", money(r(4, id, 3))],
        ["Capability", r(4, id, 4) ? "Street repairs" : "Local employment"],
        [
          "Available repair crew",
          r(4, id, 4) && order < 0 && r(4, id, 6) === 4
            ? "1 crew / 4 workers"
            : "None",
        ],
        ["Active order", order < 0 ? "None" : `#${order + 1}`],
        ["Contract costs incurred", money(r(4, id, 7))],
        ["Daily commercial tax", money(r(1, b, 7))],
        ["Tax arrears", money(r(1, b, 8))],
      ];
      actions = [
        link("Locate premises", () => game.focus(1, b)),
        link("Inspect premises", () => inspect(1, b)),
      ];
      if (order >= 0)
        actions.push(link("Inspect order", () => openOrder(order)));
      if (r(4, id, 4))
        for (let i = 0; i < r(4, id, 6); i++) {
          const person = r(4, id, 8 + i);
          actions.push(
            link(`Crew member ${person + 1}`, () => inspect(3, person)),
          );
        }
    } else if (kind === 5) {
      title = `Street segment ${id + 1}`;
      fields = [
        ["Neighbourhood", districts[r(5, id, 4)]],
        ["Endpoints", `${r(5, id, 0) + 1} ↔ ${r(5, id, 1) + 1}`],
        ["Length", `${r(5, id, 2).toFixed(1)} m`],
        ["Grade", `${(r(5, id, 3) * 100).toFixed(1)}%`],
        [
          "Elevation",
          `${r(5, id, 7).toFixed(1)} → ${r(5, id, 8).toFixed(1)} m`,
        ],
        ["Condition", `${r(5, id, 5).toFixed(1)}%`],
        [
          "Works disruption",
          r(5, id, 6) ? "Walking −35% / vehicles −55%" : "None",
        ],
        ["Street type", streetClasses[r(5, id, 17)] ?? "Street"],
        ["Vehicles / queued", `${r(5, id, 10)} / ${r(5, id, 11)}`],
        ["Queue pressure", `${(r(5, id, 12) * 100).toFixed(0)}%`],
        [
          "Lane allocation",
          ["Mixed", "Bus lanes", "Cycle lanes"][r(5, id, 13)],
        ],
        [
          "Kerbside parking",
          r(5, id, 17) === 0
            ? "Not allowed on a lane"
            : `${parkingBands[r(5, id, 19)]} · £${r(5, id, 20).toFixed(2)} per stay`,
        ],
        ["Observed movement", r(5, id, 18).toFixed(2)],
      ];
      actions = [
        link("Locate street", () => game.focus(5, id)),
        link("Transport & lanes", () => transport.inspectRoad(id)),
        link("Prepare repair offer", () => offerStreet(id)),
      ];
    }
    $("inspect-type").textContent = {
      1: "PROPERTY",
      3: "RESIDENT",
      4: "COMPANY",
      5: "STREET",
    }[kind];
    $("place-title").textContent = title;
    if (!$("inspect-fields")) {
      const table = document.createElement("table"),
        body = document.createElement("tbody");
      body.id = "inspect-fields";
      table.append(body);
      $("place-detail").replaceChildren(table);
    }
    rows("inspect-fields", fields);
    const container = $("inspect-actions");
    actions.forEach((action, index) => {
      const button =
        container.children[index] ||
        container.appendChild(document.createElement("button"));
      button.textContent = action.text;
      button.onclick = action.action;
    });
    while (container.children.length > actions.length)
      container.lastElementChild.remove();
  }
  return {
    inspectPerson: (id) => inspect(3, id),
    inspectBuilding: (id) => inspect(1, id),
    update() {
      if(streetIds.length!==m(15)){streetIds=Array.from({length:m(15)},(_,id)=>id);streetOptions(Number($("work-street").value));}
      $("clock").textContent = timeLabel(m(0));
      $("treasury").textContent = money(m(1));
      $("population").textContent = `${m(7).toLocaleString()} residents`;
      document
        .querySelectorAll("[data-speed]")
        .forEach((button) =>
          button.classList.toggle(
            "active",
            Number(button.dataset.speed) === m(13),
          ),
        );
      $("simulation-status").textContent = m(13)
        ? "SIMULATION RUNNING"
        : "SIMULATION PAUSED";
      updateReports();
      updateBudget();
      updateWorks();
      updateInspector();
    },
    reset() {
      buildings.forEach((b,id) => Object.assign(b,{kind:r(1,id,0),district:r(1,id,1),employer:r(1,id,6),node:r(1,id,11)}));
      people.forEach((p,id) => Object.assign(p,{home:r(3,id,0),employer:r(3,id,1)}));
      personPage = streetPage = 0;
      streetIds = Array.from({length:m(15)},(_,id)=>id);
      $("work-district").value = "0";
      $("work-scope").value = "30";
      $("work-price").value = "12000";
      $("revised-price").value = "12000";
      streetOptions(0);
      selectedOrder = -1;
      selected = { kind: 1, id: -1 };
      $("home-tax").value = m(20);
      $("business-tax").value = m(21);
      $("order-message").textContent = "";
      $("tax-status").textContent = "";
      $("place-title").textContent = "Look a little closer.";
      $("place-detail").textContent = "Select a building or a report entry.";
      $("inspect-actions").replaceChildren();
    },
  };
}
