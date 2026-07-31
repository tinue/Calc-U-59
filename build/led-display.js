// Canvas port of App/Views/LEDDisplayView.swift's "classic" (dot-matrix)
// 7-segment render. See that file for the reference this ports 1:1 — same
// segment bitmasks, same per-digit shear transform, same two-pass
// glow-then-solid dot fill. Replaces the old font-glyph + hand-drawn-bar
// approach (DSEG7Classic-Bold for 0-9, custom CSS bars for 7 and the "C"
// annunciator): DSEG7's "seven" glyph lights an extra segment real
// hardware doesn't (4 segments, not 3 — confirmed by decoding the font's
// glyf table), and its Latin "C" glyph is ~56% of a digit's height, so
// neither ever matched the surrounding digits. Drawing every character
// from the same bitmask table sidesteps both problems, and a single
// canvas redraws at the container's actual size every frame instead of
// depending on hand-tuned CSS insets that only looked right at one scale.

// Segments: bit 0=A(top) 1=B(upper-right) 2=C(lower-right)
//           3=D(bottom) 4=E(lower-left) 5=F(upper-left) 6=G(middle)
const LED_DIGIT_SEGMENTS = [0b0111111,
// 0: A B C D E F
0b0000110,
// 1: B C
0b1011011,
// 2: A B D E G
0b1001111,
// 3: A B C D G
0b1100110,
// 4: B C F G
0b1101101,
// 5: A C D F G
0b1111101,
// 6: A C D E F G
0b0000111,
// 7: A B C
0b1111111,
// 8: all
0b1101111 // 9: A B C D F G
];
const LED_SEGMENTS_C = 0b0111001; // A F E D — "C" annunciator shape
const LED_SEGMENTS_MINUS = 0b1000000; // G only
const LED_SEGMENTS_DEGREE = 0b1100011; // A B F G

// Mirrors LEDDisplayView.swift's displayChar()+segmentMask(): ctrl values
// 2/3/4 (space), 7 (blank), and anything else fall through to 0 (no
// segments lit — the dim all-off ghost pattern).
function ledCharSegments(ctrl, digit) {
  switch (ctrl) {
    case 0:
    case 1:
    case 8:
    case 9:
      return LED_DIGIT_SEGMENTS[(digit & 0xF) % 10];
    case 5:
      return digit === 0 ? LED_SEGMENTS_MINUS : LED_SEGMENTS_DEGREE;
    case 6:
      return LED_SEGMENTS_MINUS;
    default:
      return 0;
  }
}
const LED_SLANT = 0.1139; // LEDDisplayView.swift's classic-style slant
const LED_GLOW_BLUR_MULTIPLIER = 1.3;
const LED_GLOW_OPACITY_FACTOR = 0.65;
const LED_DOT_RADIUS_MULTIPLIER = 0.45;

// Draws one segment as a grid of glowing dots (2 rows x N cols for a
// horizontal segment, N rows x 2 cols for vertical) — the same
// subdivision LEDDisplayView.swift's drawDotSegment uses, ported from
// CGPath/GraphicsContext.addFilter(.blur) to Canvas 2D's ctx.filter.
function ledDrawDotSegment(ctx, x, y, length, sw, isHorizontal, active, segmentOpacity) {
  let cols, rows;
  if (isHorizontal) {
    rows = 2;
    const cellH = sw / rows;
    cols = Math.max(2, Math.floor(length / cellH));
  } else {
    cols = 2;
    const cellW = sw / cols;
    rows = Math.max(2, Math.floor(length / cellW));
  }
  const cellW = isHorizontal ? length / cols : sw / cols;
  const cellH = isHorizontal ? sw / rows : length / rows;
  const dotR = Math.min(cellW, cellH) * LED_DOT_RADIUS_MULTIPLIER;
  const color = active ? `rgba(255,51,51,${segmentOpacity})` : "rgba(51,0,0,0.2)";
  if (active) {
    ctx.save();
    ctx.filter = `blur(${dotR * LED_GLOW_BLUR_MULTIPLIER}px)`;
    ctx.fillStyle = `rgba(255,51,51,${LED_GLOW_OPACITY_FACTOR * segmentOpacity})`;
    for (let row = 0; row < rows; row++) {
      for (let col = 0; col < cols; col++) {
        const cx = x + (col + 0.5) * cellW;
        const cy = y + (row + 0.5) * cellH;
        ctx.beginPath();
        ctx.arc(cx, cy, dotR, 0, Math.PI * 2);
        ctx.fill();
      }
    }
    ctx.restore();
  }
  ctx.fillStyle = color;
  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < cols; col++) {
      const cx = x + (col + 0.5) * cellW;
      const cy = y + (row + 0.5) * cellH;
      ctx.beginPath();
      ctx.arc(cx, cy, dotR, 0, Math.PI * 2);
      ctx.fill();
    }
  }
}

// Ports drawSegmentsClassic(): pads the digit's local rect, derives
// segment thickness from its width, then draws all 7 segments (A-G) —
// active or not, so unlit segments show as the dim ghost pattern that
// used to be a separate hand-drawn "8" backdrop.
function ledDrawSegmentsClassic(ctx, rect, segments, segmentOpacity) {
  const padX = rect.width * 0.22;
  const padY = rect.height * 0.10;
  const rx = rect.x + padX;
  const ry = rect.y + padY;
  const rw = rect.width - 2 * padX;
  const rh = rect.height - 2 * padY;
  const rMaxX = rx + rw;
  const rMaxY = ry + rh;
  const rMidY = ry + rh / 2;
  const sw = rw * 0.16;
  const hh = rh / 2;
  const segs = [[true, rx + sw, ry, rw - 2 * sw, 0],
  // A top
  [false, rMaxX - sw, ry, hh, 1],
  // B upper-right
  [false, rMaxX - sw, rMidY, hh, 2],
  // C lower-right
  [true, rx + sw, rMaxY - sw, rw - 2 * sw, 3],
  // D bottom
  [false, rx, rMidY, hh, 4],
  // E lower-left
  [false, rx, ry, hh, 5],
  // F upper-left
  [true, rx + sw, rMidY - sw / 2, rw - 2 * sw, 6] // G middle
  ];
  for (const [isHorizontal, sx, sy, len, bit] of segs) {
    const active = (segments >> bit & 1) === 1;
    ledDrawDotSegment(ctx, sx, sy, len, sw, isHorizontal, active, segmentOpacity);
  }
}

// Smaller, less glowy, and further from the digit than
// LEDDisplayView.swift's literal "modernized" constants (0.13/1.1/1.4/0.8/
// 0.6) — those read as an oversized, over-glowing blob at the web
// display's proportions, sitting almost flush against the digit above it.
// Still drawn unsheared, in the digit's plain (non-slanted) rect.
function ledDrawDecimalPoint(ctx, rect) {
  const dotSize = rect.height * 0.09;
  const cx = rect.x + rect.width - dotSize * 1.4 + dotSize / 2;
  const cy = rect.y + rect.height - dotSize * 1.8 + dotSize / 2;
  const r = dotSize / 2;
  ctx.save();
  ctx.filter = `blur(${dotSize * 0.45}px)`;
  ctx.fillStyle = "rgba(255,26,26,0.45)";
  ctx.beginPath();
  ctx.arc(cx, cy, r, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
  ctx.fillStyle = "rgba(255,26,26,1)";
  ctx.beginPath();
  ctx.arc(cx, cy, r, 0, Math.PI * 2);
  ctx.fill();
}

// Ports LEDDisplayView.swift's Canvas body: one pass over all 12 digit
// positions (i=0 rightmost/position 13 ... i=11 leftmost/position 2,
// matching Core/TMC0501.hpp's DisplaySnapshot ordering), each sheared
// individually so the classic style's characteristic italic lean doesn't
// distort neighboring digits.
function ledDrawDisplay(ctx, cssWidth, cssHeight, snap) {
  ctx.clearRect(0, 0, cssWidth, cssHeight);
  const digitWidth = cssWidth / 12;
  const height = cssHeight;
  for (let i = 0; i < 12; i++) {
    const x = (11 - i) * digitWidth;
    let segments = 0;
    let segmentOpacity = 1.0;
    let hasDot = false;
    if (!snap) {
      if (i === 0) {
        segments = LED_DIGIT_SEGMENTS[0];
        hasDot = true;
      }
    } else if (i === 11 && snap.calcIndicator > 0) {
      segments = LED_SEGMENTS_C;
      segmentOpacity = snap.calcIndicator;
    } else {
      const suppressed = (snap.suppressedMask >> i & 1) === 1;
      segments = suppressed ? 0 : ledCharSegments(snap.ctrl[i], snap.digits[i]);
      hasDot = (snap.dpAfterglowMask >> i & 1) === 1;
    }
    ctx.save();
    ctx.translate(x, 0);
    ctx.transform(1, 0, -LED_SLANT, 1, height * LED_SLANT, 0);
    ledDrawSegmentsClassic(ctx, {
      x: 0,
      y: 0,
      width: digitWidth,
      height
    }, segments, segmentOpacity);
    ctx.restore();
    if (hasDot) {
      ledDrawDecimalPoint(ctx, {
        x,
        y: 0,
        width: digitWidth,
        height
      });
    }
  }
}
const {
  useRef: useLedRef,
  useEffect: useLedEffect
} = React;

// width/height are CSS pixels at scale=1; the caller multiplies by its
// own `scale` prop so this stays in lockstep with the rest of the device
// chrome. Backing-store size is width/height * devicePixelRatio — the one
// piece SwiftUI's resolution-independent Canvas doesn't need an
// equivalent for.
function LedDisplayCanvas({
  scale,
  snap,
  width = 292,
  height = 36
}) {
  const canvasRef = useLedRef(null);
  const cssWidth = width * scale;
  const cssHeight = height * scale;
  useLedEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.round(cssWidth * dpr);
    canvas.height = Math.round(cssHeight * dpr);
    const ctx = canvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ledDrawDisplay(ctx, cssWidth, cssHeight, snap);
  }, [cssWidth, cssHeight, snap]);
  return /*#__PURE__*/React.createElement("canvas", {
    ref: canvasRef,
    style: {
      display: "block",
      width: cssWidth,
      height: cssHeight
    }
  });
}
Object.assign(window, {
  LedDisplayCanvas
});