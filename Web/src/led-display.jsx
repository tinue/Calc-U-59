// The LED display of the playable calculator: the classic (dot-matrix) style
// of App/Views/LEDDisplayView.swift and Qt6/app/LedRenderer.cpp. What to
// draw comes from the worker, computed by the main repo's Shared/ layer:
//   frames   — {cells, onFrame}: the owner stores each frame's cells and calls
//              onFrame(), which repaints without a React render. cells is a
//              Float32Array [segments, level, dp] × 12, cell 0 rightmost: the
//              lit-segment mask (Shared/SevenSegment.hpp, the "C" indicator
//              in cell 11), brightness 0–1 (Shared/DisplayPov) and the
//              decimal point's
//   geometry — Shared/LedGeometry's dot grid per segment for one digit cell,
//              the decimal point, the shear and the colours
// Only the painting is here: shear, glow (Canvas 2D blur) and dots. Never a
// font — no font reproduces the hardware's lit segments.

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

function ledDrawDisplay(ctx, width, height, cells, g, paths) {
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

const { useRef: useLedRef, useEffect: useLedEffect, useMemo: useLedMemo } = React;

// width/height are CSS pixels at scale=1; `geometry` must be for a cell of
// (width × scale / 12) × (height × scale). Nothing is drawn until it arrives.
function LedDisplayCanvas({ scale, frames, geometry, width, height }) {
  const canvasRef = useLedRef(null);
  const cssWidth = width * scale;
  const cssHeight = height * scale;
  const paths = useLedMemo(
    () => (geometry ? ledPaths(cssWidth, cssHeight, geometry) : null),
    [cssWidth, cssHeight, geometry]
  );

  // Sizing the canvas clears it, so only when the size changes.
  useLedEffect(() => {
    const canvas = canvasRef.current;
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.round(cssWidth * dpr);
    canvas.height = Math.round(cssHeight * dpr);
    canvas.getContext("2d").setTransform(dpr, 0, 0, dpr, 0, 0);
  }, [cssWidth, cssHeight]);

  useLedEffect(() => {
    if (!paths) return undefined;
    const draw = () =>
      ledDrawDisplay(canvasRef.current.getContext("2d"), cssWidth, cssHeight, frames.cells, geometry, paths);
    draw();
    frames.onFrame = draw;
    return () => { frames.onFrame = null; };
  }, [frames, paths]);

  return (
    <canvas
      ref={canvasRef}
      style={{ display: "block", width: cssWidth, height: cssHeight }}
    />
  );
}
