// Canvas painters — drawing only; every shape, size and colour comes from
// Shared/ through the worker:
//   LED       — the Classic style of Qt6/app/LedRenderer.cpp: Shared/
//               LedGeometry's dot grid per segment, sheared, with a blurred
//               glow (Canvas 2D filter). Never a font.
//   cue card  — the draw list bindings.cpp builds from Shared/CueCard
//               (CueCardRenderer.cpp in Qt): template image, text frames,
//               badges, dividers and the top wash.
//   printer   — PC-100C dots from Shared/PrinterFont (PrinterWidget.cpp).

// ── Images ──────────────────────────────────────────────────────────────────

const imageCache = new Map();
/// The artwork `name` (img/<name>.png), calling `onLoad` once it has loaded.
function calcImage(name, onLoad) {
  let entry = imageCache.get(name);
  if (!entry) {
    const img = new Image();
    entry = { img, waiting: [] };
    img.onload = () => { entry.waiting.forEach((f) => f()); entry.waiting = []; };
    img.src = `${CALC_BASE}img/${name}.png`;
    imageCache.set(name, entry);
  }
  if (!entry.img.complete && onLoad) entry.waiting.push(onLoad);
  return entry.img.complete && entry.img.naturalWidth ? entry.img : null;
}

/// Size a canvas for CSS px w × h at the device's pixel ratio; returns its context.
function sizeCanvas(canvas, w, h) {
  const dpr = window.devicePixelRatio || 1;
  const pw = Math.max(1, Math.round(w * dpr)), ph = Math.max(1, Math.round(h * dpr));
  if (canvas.width !== pw || canvas.height !== ph) {
    canvas.width = pw;
    canvas.height = ph;
  }
  const ctx = canvas.getContext("2d");
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  return ctx;
}

// ── LED ─────────────────────────────────────────────────────────────────────

const rgbaOf = (rgb, a) => `rgba(${rgb[0]},${rgb[1]},${rgb[2]},${a})`;

// Per geometry, built once: each segment of each cell as a Path2D, already
// sheared into place, and the decimal points (unsheared).
function ledPaths(width, height, g) {
  const w = width / 12;
  const segments = [];
  const dps = [];
  for (let i = 0; i < 12; i++) {
    const x = (11 - i) * w;
    const m = new DOMMatrix([1, 0, -g.slant, 1, x + height * g.slant, 0]);
    segments.push(g.segments.map((seg) => {
      const dots = new Path2D();
      for (const [cx, cy] of seg.centres) {
        dots.moveTo(cx + seg.radius, cy);
        dots.arc(cx, cy, seg.radius, 0, Math.PI * 2);
      }
      const sheared = new Path2D();
      sheared.addPath(dots, m);
      return sheared;
    }));
    const dp = new Path2D();
    dp.arc(x + g.dp.cx, g.dp.cy, g.dp.diameter / 2, 0, Math.PI * 2);
    dps.push(dp);
  }
  return { segments, dps };
}

// Lit shapes with the same brightness, in 1/64 steps, share one blurred glow
// pass: brightness is continuous, and a blur per distinct level is expensive.
function ledFillGlowing(ctx, shapes, rgb, blur, glowOpacity) {
  const byLevel = new Map();
  for (const [path, exact] of shapes) {
    const level = Math.round(exact * 64) / 64;
    if (!byLevel.has(level)) byLevel.set(level, new Path2D());
    byLevel.get(level).addPath(path);
  }
  for (const [level, path] of byLevel) {
    ctx.save();
    ctx.filter = `blur(${blur}px)`;
    ctx.fillStyle = rgbaOf(rgb, glowOpacity * level);
    ctx.fill(path);
    ctx.restore();
    ctx.fillStyle = rgbaOf(rgb, level);
    ctx.fill(path);
  }
}

/// cells: Float32Array [segments, level, dp] × 12, cell 0 rightmost.
function paintLed(ctx, width, height, cells, g, paths) {
  ctx.fillStyle = rgbaOf(g.background, 1);
  ctx.fillRect(0, 0, width, height);
  const lit = [];
  const dps = [];
  ctx.fillStyle = rgbaOf(g.inactive, g.inactiveAlpha);
  for (let i = 0; i < 12; i++) {
    const segments = cells ? cells[i * 3] : 0;
    const level = cells ? cells[i * 3 + 1] : 0;
    const dp = cells ? cells[i * 3 + 2] : 0;
    for (let bit = 0; bit < 7; bit++) {
      const path = paths.segments[i][bit];
      if ((segments >> bit) & 1 && level > 0) lit.push([path, level]);
      else ctx.fill(path);
    }
    if (dp > 0) dps.push([paths.dps[i], dp]);
  }
  ledFillGlowing(ctx, lit, g.active, g.segments[0].radius * g.glowBlurPerRadius, g.glowOpacity);
  ledFillGlowing(ctx, dps, g.active, g.dp.diameter * g.dpGlowBlurPerDiameter, g.dpGlowOpacity);
}

// ── Cue card ────────────────────────────────────────────────────────────────

const CARD_FONT = '"Archivo", "Helvetica Neue", Helvetica, Arial, sans-serif';

/// One line elided to `width` with "…", like SwiftUI's lineLimit(1).
function elide(ctx, text, width) {
  if (ctx.measureText(text).width <= width) return text;
  const chars = [...text];
  while (chars.length && ctx.measureText(chars.join("") + "…").width > width) chars.pop();
  return chars.join("") + "…";
}

function paintCueCard(ctx, card, onImage) {
  ctx.clearRect(0, 0, card.width, card.height);
  const img = calcImage(card.template, onImage);
  if (img) ctx.drawImage(img, 0, 0, card.width, card.height);
  ctx.textBaseline = "middle";
  for (const it of card.items) {
    if (it.kind === "rect") {
      const [x, y, w, h] = it.rect;
      ctx.globalAlpha = it.alpha;
      ctx.fillStyle = it.color;
      ctx.fillRect(x, y, w, h);
      ctx.globalAlpha = 1;
    } else if (it.kind === "badge") {
      const [x, y, w, h] = it.frame;
      ctx.save();
      ctx.beginPath();
      ctx.rect(x, y, w, h);
      ctx.clip();
      ctx.font = `700 ${Math.round(it.size)}px ${CARD_FONT}`;
      ctx.fillStyle = "#000";
      ctx.textAlign = "center";
      ctx.fillText(it.text, x + w / 2, y + h / 2);
      ctx.restore();
    } else {
      ctx.font = `700 ${Math.max(1, Math.round(it.size))}px ${CARD_FONT}`;
      ctx.fillStyle = it.color;
      ctx.strokeStyle = it.color;
      ctx.textAlign = it.align;
      const left = it.cx - it.width / 2;
      const x = it.align === "left" ? left : it.align === "right" ? left + it.width : it.cx;
      ctx.fillText(elide(ctx, it.text, it.width), x, it.cy);
      if (it.box) {
        const lineH = it.size * 1.2, [padX, padY] = it.box;
        ctx.lineWidth = 1;
        ctx.strokeRect(left - padX, it.cy - lineH / 2 - padY, it.width + 2 * padX, lineH + 2 * padY);
      }
    }
  }
}

// ── Printer ─────────────────────────────────────────────────────────────────

/// Lines from `first` with their tops (strip px, from `top`) until `bottom`.
/// `pitch` is px per dot pitch; `tops` the cumulative line tops in units.
function paintStrip(ctx, lines, tops, pitch, geo, color, top, bottom) {
  const radius = pitch * geo.dotRadiusFraction;
  ctx.fillStyle = color;
  // First line whose bottom is below `top` (binary search over the tops).
  let lo = 0, hi = lines.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if ((tops[mid] + lines[mid].height) * pitch < top) lo = mid + 1;
    else hi = mid;
  }
  ctx.beginPath();
  for (let i = lo; i < lines.length && tops[i] * pitch < bottom; i++) {
    const line = lines[i];
    if (!line.codes) continue;
    const y = tops[i] * pitch;
    for (let row = 0; row < line.rows; row++) {
      const cy = y + (row + 0.5) * pitch;
      for (let ch = 0; ch < 20; ch++) {
        const bits = geo.font[line.codes[ch]][row];
        if (!bits) continue;
        const cx0 = ch * geo.charStepUnits * pitch;
        for (let col = 0; col < 5; col++) {
          if (!(bits & (0x10 >> col))) continue;
          const cx = cx0 + (col + 0.5) * pitch;
          ctx.moveTo(cx + radius, cy);
          ctx.arc(cx, cy, radius, 0, Math.PI * 2);
        }
      }
    }
  }
  ctx.fill();
}

/// Cumulative line tops, in dot pitches.
function stripTops(lines) {
  const tops = new Array(lines.length);
  let y = 0;
  for (let i = 0; i < lines.length; i++) { tops[i] = y; y += lines[i].height; }
  return tops;
}
