// Small interactive canvas charts. Zero dependencies, high-DPI aware.
// Both charts support click hit-testing: onPick(entry) for one item and
// onPickGroup(name) for a whole category; entries carry an optional `group`
// label so stacked/grouped categories can be selected together.

const palette = ["#379b6b", "#ada45c", "#b8503a", "#5b84ae", "#7d5ba6", "#4aa3a2", "#c97a40", "#888078", "#a3b899", "#6b8f71"];

function surface(canvas) {
  const dpr = devicePixelRatio || 1;
  const rect = canvas.getBoundingClientRect();
  const w = Math.max(80, rect.width), h = Math.max(60, rect.height || 160);
  if (canvas.width !== w * dpr || canvas.height !== h * dpr) {
    canvas.width = w * dpr; canvas.height = h * dpr;
  }
  const ctx = canvas.getContext("2d");
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, w, h);
  return { ctx, w, h };
}

function bind(canvas, canvasState) {
  if (canvasState.done) return;
  canvasState.done = true;
  canvas.addEventListener("click", (event) => {
    const hit = canvasState.hittest?.(event.offsetX, event.offsetY);
    if (!hit) return;
    if (hit.onPick) hit.onPick(hit);
    else if (hit.group !== undefined && canvasState.onPickGroup) canvasState.onPickGroup(hit.group);
  });
}

// Horizontal bar chart. items: [{label, value, text?, color?, group?, onPick?}]
export function barChart(canvas, items, { onPickGroup, selected = null, legend = false } = {}) {
  const state = (canvas._chart ||= {});
  const { ctx, w, h } = surface(canvas);
  if (!items.length) return;
  const groups = [...new Set(items.map((i) => i.group).filter((g) => g !== undefined))];
  const showLegend = legend && groups.length > 1;
  const padL = 118, padR = 54, top = showLegend ? 24 : 6;
  let rowH = Math.min(24, (h - top - 4) / items.length); if (rowH < 10) rowH = (h - top - 4) / items.length;
  const max = Math.max(1e-9, ...items.map((i) => Math.abs(i.value)));
  const groupColors = {};
  let gi = 0;
  const boxes = [];
  ctx.font = "10px system-ui, sans-serif";
  const chips = [];
  if (showLegend) {
    let cx = padL, cy = 3;
    const gc = {};
    groups.forEach((g, i) => (gc[g] = palette[i % palette.length]));
    for (const g of groups) {
      const text = String(g);
      const cw = ctx.measureText(text).width + 18;
      ctx.fillStyle = gc[g];
      ctx.globalAlpha = 0.9;
      ctx.fillRect(cx, cy, 10, 8);
      ctx.globalAlpha = 1;
      ctx.fillStyle = "#c9c4ae";
      ctx.textAlign = "left";
      ctx.fillText(text, cx + 14, cy + 8);
      chips.push({ x: cx - 4, y: 0, w: cw + 8, h: 16, group: g, onPick: null });
      cx += cw + 8;
    }
  }
  items.forEach((item, n) => {
    const y = top + n * rowH;
    if (item.group !== undefined && !(item.group in groupColors)) groupColors[item.group] = palette[gi++ % palette.length];
    const color = item.color || (item.group !== undefined ? groupColors[item.group] : "#379b6b");
    const barW = (Math.abs(item.value) / max) * (w - padL - padR);
    ctx.fillStyle = "#0e1413";
    const bh = Math.max(2, rowH - Math.min(6, rowH * 0.35)); const yo = y + (rowH - bh) / 2; ctx.fillRect(padL, yo, w - padL - padR, bh);
    ctx.globalAlpha = selected && item.label !== selected ? 0.45 : 1;
    ctx.fillStyle = color;
    ctx.fillRect(padL, yo, Math.max(2, barW), bh);
    ctx.globalAlpha = 1;
    ctx.fillStyle = "#c9c4ae";
    ctx.textAlign = "right";
    if (rowH >= 7) ctx.fillText(String(item.label).slice(0, 22), padL - 6, y + rowH / 2 + Math.min(4, rowH * 0.35));
    ctx.textAlign = "left";
    ctx.fillStyle = "#8f988c";
    if (rowH >= 7) ctx.fillText(item.text ?? String(item.value), padL + barW + 6, y + rowH / 2 + Math.min(4, rowH * 0.35));
    boxes.push({ x: padL, y, w: Math.max(10, barW), h: rowH, ...item });
  });
  state.hit = [...chips, ...boxes];
  state.onPickGroup = onPickGroup;
  state.hittest = (x, y) =>
    chips.find((c) => x >= c.x && x <= c.x + c.w && y >= c.y && y <= c.y + c.h) ||
    boxes.find((b) => x >= b.x - padL && x <= b.x + b.w && y >= b.y && y <= b.y + b.h);
  bind(canvas, state);
  return { groupColors };
}

// Multi-series line chart over an index axis. series: [{label, points:[number], color?}]
export function lineChart(canvas, series, { onPickPoint } = {}) {
  const state = (canvas._chart ||= {});
  const { ctx, w, h } = surface(canvas);
  const padL = 8, padR = 8, top = 10, bottom = 16;
  const all = series.flatMap((s) => s.points);
  if (!all.length) return;
  const max = Math.max(1e-9, ...all), min = Math.min(0, ...all);
  const span = max - min || 1;
  const n = Math.max(...series.map((s) => s.points.length));
  const at = (i, v) => [padL + (i / Math.max(1, n - 1)) * (w - padL - padR), top + (1 - (v - min) / span) * (h - top - bottom)];
  ctx.strokeStyle = "#2c3532";
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(padL, h - bottom); ctx.lineTo(w - padR, h - bottom);
  ctx.stroke();
  const dots = [];
  series.forEach((s, k) => {
    const color = s.color || palette[k % palette.length];
    ctx.strokeStyle = color; ctx.lineWidth = 1.5;
    ctx.beginPath();
    s.points.forEach((v, i) => { const [x, y] = at(i, v); i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); });
    ctx.stroke();
    s.points.forEach((v, i) => {
      const [x, y] = at(i, v);
      dots.push({ x, y, r: 6, index: i, value: v, series: s });
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(x, y, 2.2, 0, Math.PI * 2);
      ctx.fill();
    });
  });
  ctx.font = "9px system-ui, sans-serif";
  ctx.fillStyle = "#8f988c";
  series.forEach((s, k) => ctx.fillText(s.label, padL + k * 90, h - 4));
  state.hit = dots;
  state.hittest = (x, y) => dots.find((d) => (d.x - x) ** 2 + (d.y - y) ** 2 <= d.r * d.r);
  state.onPickPoint = onPickPoint;
  state.done || canvas.addEventListener("click", (e) => {
    const hit = state.hittest(e.offsetX, e.offsetY);
    if (hit && state.onPickPoint) state.onPickPoint(hit);
  });
  state.done = true;
}
