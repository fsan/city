// Presentation state only. Simulation commands are passed in by the browser adapter.
export function createInterface(actions) {
  const $ = (id) => document.getElementById(id);
  const windows = [...document.querySelectorAll(".game-window")];
  const order = [];
  let moving = null;
  // Where the player last clicked. A window opens away from that point so it
  // never covers the thing that was clicked: a light, a street, a building or
  // a report row. Clicks on the HUD, the toolbar and window headers keep the
  // authored positions, because those bars draw above the windows.
  let clickPoint = null;
  let mapPoint = null;
  document.addEventListener("pointerdown", (event) => {
    const target = event.target;
    if (target === $("city")) {
      mapPoint = { x: event.clientX, y: event.clientY };
      clickPoint = mapPoint;
    } else if (target.closest(".window-body")) {
      clickPoint = { x: event.clientX, y: event.clientY };
    } else if (target.closest(".popup")) {
      // A menu item acts where the menu was opened, usually on the map.
      clickPoint = mapPoint;
    } else {
      clickPoint = null;
    }
  }, true);
  const edge = 12, gap = 16;
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
  function bounds(panel) {
    const rect = panel.getBoundingClientRect();
    const hudBottom =
      document.querySelector(".hud").getBoundingClientRect().bottom + 10;
    const minLeft = edge;
    const maxLeft = Math.max(edge, innerWidth - rect.width - edge);
    const minTop = Math.max(edge, hudBottom);
    const maxTop = Math.max(minTop, innerHeight - rect.height - 90);
    const hold = (value, low, high) => Math.max(low, Math.min(value, high));
    return {rect, hold, minLeft, maxLeft, minTop, maxTop};
  }
  // A window covers the point when the point is inside it, including a gap so
  // the clicked thing is left visibly clear rather than clipped at the border.
  function covers(left, top, width, height, point) {
    return (
      point.x > left - gap && point.x < left + width + gap &&
      point.y > top - gap && point.y < top + height + gap
    );
  }
  function fit(panel) {
    const {rect, hold, minLeft, maxLeft, minTop, maxTop} = bounds(panel);
    panel.style.left = `${hold(rect.left, minLeft, maxLeft)}px`;
    panel.style.top = `${hold(rect.top, minTop, maxTop)}px`;
  }
  // Opening a window chooses a spot beside the clicked point when the authored
  // position would sit on top of it.
  function place(panel, point) {
    const {rect, hold, minLeft, maxLeft, minTop, maxTop} = bounds(panel);
    const baseLeft = hold(rect.left, minLeft, maxLeft);
    const baseTop = hold(rect.top, minTop, maxTop);
    const spots = [[baseLeft, baseTop]];
    if (point) {
      spots.push(
        [hold(point.x + gap, minLeft, maxLeft), baseTop],
        [hold(point.x - gap - rect.width, minLeft, maxLeft), baseTop],
        [baseLeft, hold(point.y + gap, minTop, maxTop)],
        [baseLeft, hold(point.y - gap - rect.height, minTop, maxTop)],
        [hold(point.x + gap, minLeft, maxLeft), hold(point.y - rect.height / 2, minTop, maxTop)],
        [point.x < innerWidth / 2 ? maxLeft : minLeft, baseTop],
      );
      // A window too wide or tall to sit clear of the click inside the
      // viewport may poke past the far edge, as long as most of it stays
      // visible: covering the thing the player just clicked is worse than a
      // window that hangs a little over the screen edge.
      const fits = (x, y) => {
        const visibleWidth = Math.min(innerWidth, x + rect.width) - Math.max(0, x);
        const visibleHeight = Math.min(innerHeight, y + rect.height) - Math.max(0, y);
        return visibleWidth >= rect.width * 0.6 && visibleHeight >= rect.height * 0.6;
      };
      for (const [x, y] of [
        [point.x + gap, baseTop],
        [point.x - gap - rect.width, baseTop],
        [baseLeft, point.y + gap],
        [baseLeft, point.y - gap - rect.height],
        [point.x + gap, point.y - rect.height / 2],
        [point.x - gap - rect.width, point.y - rect.height / 2],
      ]) if (fits(x, y)) spots.push([x, y]);
    }
    const [left, top] =
      spots.find(([x, y]) => !point || !covers(x, y, rect.width, rect.height, point)) ||
      [baseLeft, baseTop];
    panel.style.left = `${left}px`;
    panel.style.top = `${top}px`;
  }
  function open(name) {
    closeMenus();
    const panel = $(`${name}-window`);
    panel.hidden = false;
    bringForward(name);
    const point = clickPoint;
    clickPoint = null; // one placement per click, so later opens keep their spot
    place(panel, point);
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
