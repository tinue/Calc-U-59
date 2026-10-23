// The calculator face: the artwork of the current model, the LED display
// and the cue card on it, the pressed-key effect (key rect blacked out, the
// artwork shifted 3 px), as Qt6/app/KeyboardWidget and App/Views/
// KeyboardView. Pointer input goes to the worker as canvas-normalized
// points; the hit test (widened key rects, the display's full-speed hold,
// drag to another key) runs in bindings.cpp on Shared/KeyboardLayout.
//
// Transparent buttons over the keys, named by the key's face label, make
// the keys reachable for assistive technology (and tests); pointer events on
// them bubble to the face's own handler.

const KEY_LABELS = [
  "A", "B", "C", "D", "E",
  "2nd", "INV", "lnx", "CE", "CLR",
  "LRN", "x⇄t", "x²", "√x", "1/x",
  "SST", "STO", "RCL", "SUM", "yˣ",
  "BST", "EE", "(", ")", "÷",
  "GTO", "7", "8", "9", "×",
  "SBR", "4", "5", "6", "−",
  "RST", "1", "2", "3", "+",
  "R/S", "0", ".", "+/-", "=",
];

// Shared/KeyboardLayout kCanvasAspect (width / height), known before the
// engine is: the layout and the prerender need it.
const CANVAS_ASPECT = 2064 / 4075;

const artworkFor = (model) => (model === 0 ? "ti59_base" : "ti58_base");
const PRESS_SHIFT = 3;

function LedCanvas({ engine, width, height }) {
  const ref = React.useRef(null);
  const geometry = useEngine(engine, (s) => s.geometry);
  const ready = useEngine(engine, (s) => s.data !== null);

  React.useEffect(() => {
    if (engine && ready) engine.post({ type: "geometry", w: width / 12, h: height });
  }, [engine, ready, width, height]);

  const paths = React.useMemo(() => (geometry ? ledPaths(width, height, geometry) : null), [geometry, width, height]);

  React.useEffect(() => {
    const canvas = ref.current;
    const ctx = sizeCanvas(canvas, width, height);
    if (!paths || !engine) return undefined;
    const draw = () => paintLed(ctx, width, height, engine.frames.cells, geometry, paths);
    draw();
    engine.frames.onFrame = draw;
    return () => { engine.frames.onFrame = null; };
  }, [engine, paths, width, height]);

  return <canvas ref={ref} className="calcu-led" style={{ width, height }} aria-hidden="true" />;
}

function CueCardCanvas({ engine, width, height }) {
  const ref = React.useRef(null);
  const card = useEngine(engine, (s) => s.cueCard);
  const ready = useEngine(engine, (s) => s.data !== null);
  const [loaded, setLoaded] = React.useState(0);

  React.useEffect(() => {
    if (engine && ready) engine.call("setCueCardSize", width, height);
  }, [engine, ready, width, height]);

  React.useEffect(() => {
    const ctx = sizeCanvas(ref.current, width, height);
    ctx.clearRect(0, 0, width, height);
    if (card && Math.abs(card.width - width) < 0.5) paintCueCard(ctx, card, () => setLoaded((n) => n + 1));
  }, [card, width, height, loaded]);

  return (
    <canvas
      ref={ref}
      className="cuecard"
      role="img"
      aria-label={card ? card.label : "No cue card"}
      style={{ width, height, visibility: card ? "visible" : "hidden" }}
    />
  );
}

function CalculatorFace({ engine, width }) {
  const data = useEngine(engine, (s) => s.data);
  const model = useEngine(engine, (s) => (s.model ? s.model.model : 0));
  const heldKey = useEngine(engine, (s) => s.runState.heldKey);
  const fullSpeed = useEngine(engine, (s) => s.runState.fullSpeed);
  const height = width / CANVAS_ASPECT;
  const baseRef = React.useRef(null);
  const [loaded, setLoaded] = React.useState(0);
  const pointerRef = React.useRef(null);

  // Artwork and the pressed key.
  React.useEffect(() => {
    const ctx = sizeCanvas(baseRef.current, width, height);
    ctx.clearRect(0, 0, width, height);
    const img = calcImage(artworkFor(model), () => setLoaded((n) => n + 1));
    if (!img) return;
    ctx.imageSmoothingQuality = "high";
    ctx.drawImage(img, 0, 0, width, height);
    if (data && heldKey >= 0) {
      const [x, y, w, h] = data.layout.keys[heldKey];
      const sx = img.naturalWidth / width, sy = img.naturalHeight / height;
      const r = { x: x * width, y: y * height, w: w * width, h: h * height };
      ctx.fillStyle = "#000";
      ctx.fillRect(r.x, r.y, r.w, r.h);
      ctx.save();
      ctx.beginPath();
      ctx.rect(r.x, r.y, r.w, r.h);
      ctx.clip();
      ctx.drawImage(img, r.x * sx, r.y * sy, r.w * sx, r.h * sy, r.x + PRESS_SHIFT, r.y + PRESS_SHIFT, r.w, r.h);
      ctx.restore();
    }
  }, [data, model, heldKey, width, height, loaded]);

  const point = (e) => {
    const rect = baseRef.current.getBoundingClientRect();
    return [(e.clientX - rect.left) / rect.width, (e.clientY - rect.top) / rect.height];
  };
  const onPointerDown = (e) => {
    if (!engine || pointerRef.current !== null || e.button > 0) return;
    pointerRef.current = e.pointerId;
    e.currentTarget.setPointerCapture(e.pointerId);
    e.preventDefault();
    engine.call("pointerDown", ...point(e));
  };
  const onPointerMove = (e) => {
    if (pointerRef.current !== e.pointerId) return;
    engine.call("pointerMove", ...point(e));
  };
  const onPointerUp = (e) => {
    if (pointerRef.current !== e.pointerId) return;
    pointerRef.current = null;
    engine.call("pointerUp");
  };
  // A key button activated without a pointer (keyboard, screen reader).
  const onKeyClick = (index) => (e) => {
    if (e.detail !== 0 || !engine) return;
    engine.call("keyButtonDown", Math.floor(index / 5), index % 5);
    setTimeout(() => engine.call("keyButtonUp"), 150);
  };

  const d = data ? data.layout.display : [0, 0.052, 1, 0.05];
  const c = data ? data.layout.card : [0, 0.11, 1, 0.108];
  return (
    <div
      className="calcu-face"
      data-full-speed={fullSpeed}
      style={{ width, height }}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={onPointerUp}
      onLostPointerCapture={onPointerUp}
      onMouseDown={(e) => e.preventDefault()}
      onContextMenu={(e) => e.preventDefault()}
    >
      <canvas ref={baseRef} className="calcu-keyboard" style={{ width, height }} aria-hidden="true" />
      <div className="calcu-overlay" style={{ left: d[0] * width, top: d[1] * height }}>
        <LedCanvas engine={engine} width={d[2] * width} height={d[3] * height} />
      </div>
      <div className="calcu-overlay" style={{ left: c[0] * width, top: c[1] * height }}>
        <CueCardCanvas engine={engine} width={c[2] * width} height={c[3] * height} />
      </div>
      {data && KEY_LABELS.map((label, i) => {
        const [x, y, w, h] = data.layout.keys[i];
        return (
          <button
            key={i}
            type="button"
            tabIndex={-1}
            className="calcu-key"
            aria-label={label}
            aria-pressed={heldKey === i}
            onClick={onKeyClick(i)}
            style={{ left: x * width, top: y * height, width: w * width, height: h * height }}
          />
        );
      })}
    </div>
  );
}
