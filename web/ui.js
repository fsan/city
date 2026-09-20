// Presentation state only. Simulation commands are passed in by the browser adapter.
export function createInterface(actions) {
  const $ = (id) => document.getElementById(id);
  const windows = [...document.querySelectorAll(".game-window")];
  const order = [];
  let moving = null;
  function bringForward(name) {
    const index = order.indexOf(name);
    if (index >= 0) order.splice(index, 1);
    order.push(name);
    order.forEach((id, position) => {
      $(`${id}-window`).style.zIndex = String(10 + position);
    });
  }
  function syncButtons() {
    document.querySelectorAll("[data-toggle]").forEach((button) => {
      button.setAttribute(
        "aria-expanded",
        String(!$(`${button.dataset.toggle}-window`).hidden),
      );
    });
  }
  function closeMenus() {
    $("management-menu").hidden = true;
    $("reports-menu").hidden = true;
    $("context-menu").hidden = true;
    $("management-toggle").setAttribute("aria-expanded", "false");
    document
      .querySelector("[data-submenu]")
      .setAttribute("aria-expanded", "false");
  }
  function fit(panel) {
    const rect = panel.getBoundingClientRect();
    const top =
      document.querySelector(".hud").getBoundingClientRect().bottom + 10;
    panel.style.left = `${Math.max(12, Math.min(rect.left, innerWidth - rect.width - 12))}px`;
    panel.style.top = `${Math.max(top, Math.min(rect.top, innerHeight - rect.height - 90))}px`;
  }
  function open(name) {
    closeMenus();
    const panel = $(`${name}-window`);
    panel.hidden = false;
    bringForward(name);
    fit(panel);
    panel.focus({ preventScroll: true });
    syncButtons();
    actions.clearInput();
  }
  function close(name) {
    $(`${name}-window`).hidden = true;
    const index = order.indexOf(name);
    if (index >= 0) order.splice(index, 1);
    syncButtons();
    const next = order.at(-1);
    (next ? $(`${next}-window`) : $("city")).focus({ preventScroll: true });
    actions.clearInput();
  }
  function toggle(name) {
    if ($(`${name}-window`).hidden) open(name);
    else close(name);
  }
  function showReport(name) {
    document.querySelectorAll("[data-report]").forEach((button) => {
      const selected = button.dataset.report === name;
      button.setAttribute("aria-selected", String(selected));
      button.tabIndex = selected ? 0 : -1;
      $(`${button.dataset.report}-report`).hidden = !selected;
    });
  }
  function escape() {
    if (!$("management-menu").hidden || !$("context-menu").hidden) {
      closeMenus();
      $("city").focus();
    } else if (order.length) close(order.at(-1));
  }
  document
    .querySelectorAll("[data-open]")
    .forEach((button) => (button.onclick = () => open(button.dataset.open)));
  document
    .querySelectorAll("[data-toggle]")
    .forEach(
      (button) => (button.onclick = () => toggle(button.dataset.toggle)),
    );
  document
    .querySelectorAll("[data-close]")
    .forEach((button) => (button.onclick = () => close(button.dataset.close)));
  document.querySelectorAll("[data-report-link]").forEach(
    (button) =>
      (button.onclick = () => {
        open("reports");
        showReport(button.dataset.reportLink);
      }),
  );
  const tabs = [...document.querySelectorAll("[data-report]")];
  tabs.forEach((button, index) => {
    button.onclick = () => showReport(button.dataset.report);
    button.onkeydown = (event) => {
      let next;
      if (event.key === "ArrowRight") next = (index + 1) % tabs.length;
      if (event.key === "ArrowLeft")
        next = (index + tabs.length - 1) % tabs.length;
      if (event.key === "Home") next = 0;
      if (event.key === "End") next = tabs.length - 1;
      if (next === undefined) return;
      event.preventDefault();
      event.stopPropagation();
      showReport(tabs[next].dataset.report);
      tabs[next].focus();
    };
  });
  document.querySelectorAll('[data-action="overlay"]').forEach(
    (button) =>
      (button.onclick = () => {
        actions.overlay();
        closeMenus();
      }),
  );
  $("management-toggle").onclick = () => {
    const wasOpen = !$("management-menu").hidden;
    closeMenus();
    if (!wasOpen) {
      $("management-menu").hidden = false;
      $("management-toggle").setAttribute("aria-expanded", "true");
    }
  };
  document.querySelector("[data-submenu]").onclick = (event) => {
    $("reports-menu").hidden = !$("reports-menu").hidden;
    event.currentTarget.setAttribute(
      "aria-expanded",
      String(!$("reports-menu").hidden),
    );
  };
  $("context-inspect").onclick = () => actions.inspect();
  document.addEventListener("pointerdown", (event) => {
    if (!event.target.closest(".popup, #management-toggle")) closeMenus();
    if (event.target !== $("city")) actions.clearInput();
  });
  document.addEventListener("focusin", () => actions.clearInput());
  for (const panel of windows) {
    const name = panel.id.replace("-window", "");
    panel.addEventListener("pointerdown", (event) => {
      bringForward(name);
      if (!event.target.closest("button, select, input, textarea, a"))
        panel.focus({ preventScroll: true });
    });
    const title = panel.querySelector(".window-title");
    title.addEventListener("pointerdown", (event) => {
      if (event.button !== 0 || event.target.closest("button")) return;
      event.preventDefault();
      const rect = panel.getBoundingClientRect();
      moving = {
        panel,
        x: event.clientX - rect.left,
        y: event.clientY - rect.top,
      };
      title.setPointerCapture(event.pointerId);
    });
    title.addEventListener("pointermove", (event) => {
      if (!moving || moving.panel !== panel) return;
      panel.style.left = `${event.clientX - moving.x}px`;
      panel.style.top = `${event.clientY - moving.y}px`;
      fit(panel);
    });
    title.addEventListener("pointerup", () => {
      moving = null;
    });
    title.addEventListener("pointercancel", () => {
      moving = null;
    });
  }
  window.addEventListener("resize", () => {
    closeMenus();
    windows.filter((panel) => !panel.hidden).forEach(fit);
  });
  return {
    open,
    toggle,
    escape,
    closeMenus,
    showReport,
    context(x, y, hasSelection) {
      closeMenus();
      const menu = $("context-menu");
      menu.hidden = false;
      menu.style.left = `${Math.max(6, Math.min(x, innerWidth - menu.offsetWidth - 8))}px`;
      menu.style.top = `${Math.max(66, Math.min(y, innerHeight - menu.offsetHeight - 8))}px`;
      $("context-inspect").disabled = !hasSelection;
      menu.querySelector("button:not(:disabled)").focus();
      actions.clearInput();
    },
  };
}
