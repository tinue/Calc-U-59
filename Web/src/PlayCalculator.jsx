// PlayCalculator — the web client, and the one global calc.js exposes
// (reference/WebClient.md has the props). Two layouts, and layout="auto" (the
// PWA) picks between them by the window's size, with Shared's iOS rules:
//   wide     — calculator | printer | debugger, as the macOS window and the
//              Qt MainWindow (resizable dividers between the columns);
//   portrait — one page at a time, calculator or printer, switched with the
//              corner chevrons, as the iPhone layout (no debugger).
// It owns the engine (src/engine.js), the physical keyboard while focused,
// drag-and-drop of presets, and keyboard feedback (portrait).

const BAR_HEIGHT = 50;
const FACE_PADDING = 8;
const PRINTER_MIN = 220, PRINTER_MAX = 320, DEBUG_MIN = 220;
// The narrowest artwork whose control bar still fits (labelled in wide, icons
// in portrait). Below it the client keeps its size and the page scrolls, as
// the apps' windows have a minimum size.
const FACE_MIN = { wide: 400, portrait: 264 };
const FACE_MIN_AUTO = 120;  // layout="auto": whatever a landscape phone's height leaves
const SPLITTERS = 1 + 5;  // the line after the calculator, the divider before the debugger

/// The artwork's width that `height` leaves room for, and the column height for an artwork width.
const faceWidthFor = (height) => (height - BAR_HEIGHT - 2 * FACE_PADDING) * CANVAS_ASPECT;
const columnHeight = (faceWidth, height) => Math.max(height || 0, faceWidth / CANVAS_ASPECT + 2 * FACE_PADDING + BAR_HEIGHT);

/// The client's minimum width for a layout.
function minimumWidth(portrait) {
  return portrait ? FACE_MIN.portrait + 2 * FACE_PADDING
    : FACE_MIN.wide + 2 * FACE_PADDING + PRINTER_MIN + DEBUG_MIN + SPLITTERS;
}

// A KeyboardEvent as Shared/KeyboardMap.hpp's KeyPress: the key's base
// character (letters from the physical key, so Caps Lock and Shift don't
// change it), the character the layout produced, and the modifiers.
function keyPressOf(e) {
  const cp = (s) => (s && [...s].length === 1 ? s.codePointAt(0) : 0);
  let key = 0;
  let isLetter = false;
  if (e.key === "Escape") key = 0x1b;
  else if (e.key === "Enter") key = e.code === "NumpadEnter" ? 0x03 : 0x0d;
  else if (/^Key[A-Z]$/.test(e.code)) { key = e.code.charCodeAt(3) + 32; isLetter = true; }
  else key = cp(e.key);
  return { key, produced: cp(e.key), isLetter, shift: e.shiftKey, command: e.ctrlKey || e.metaKey || e.altKey };
}

// Keyboard feedback (Settings, portrait): a short click synthesised with
// WebAudio. No vibration: iOS Safari has no Vibration API, and Android's
// did nothing on the phones tried.
let clickAudio = null;
function playClick(count) {
  try {
    clickAudio = clickAudio || new (window.AudioContext || window.webkitAudioContext)();
    for (let i = 0; i < count; i++) {
      const t = clickAudio.currentTime + i * 0.15;
      const osc = clickAudio.createOscillator(), gain = clickAudio.createGain();
      osc.frequency.value = 2000;
      gain.gain.setValueAtTime(0.25, t);
      gain.gain.exponentialRampToValueAtTime(0.001, t + 0.03);
      osc.connect(gain).connect(clickAudio.destination);
      osc.start(t);
      osc.stop(t + 0.03);
    }
  } catch (e) { /* no audio */ }
}
function makeFeedback(engine, enabled) {
  return (kind) => {
    if (!enabled || !engine) return;
    const mode = engine.getState().settings.keyboardFeedback;
    const count = kind === "clean" ? 2 : 1;
    if (mode === 2) playClick(count);
  };
}

// Keyboard feedback on each key press (portrait). A leaf of its own, so a
// key press re-renders nothing else.
function KeyFeedback({ engine, feedback }) {
  const heldKey = useEngine(engine, (s) => s.runState.heldKey);
  React.useEffect(() => { if (heldKey >= 0) feedback("key"); }, [heldKey]);
  return null;
}

function StatusLine({ engine }) {
  const status = useEngine(engine, (s) => s.status);
  if (!status) return null;
  return (
    <div className="calcu-status" role="status">
      <span>{status}</span>
      {engine && <button type="button" className="calcu-iconbutton" aria-label="Dismiss" onClick={() => engine.setStatus("")}>×</button>}
    </div>
  );
}

function CalculatorColumn({ engine, faceWidth, compact, showSettings, onDialog, feedback, width }) {
  return (
    <div className="calcu-calc" style={{ width: width || faceWidth + 2 * FACE_PADDING }}>
      <div className="calcu-face-pad"><CalculatorFace engine={engine} width={faceWidth} /></div>
      <ControlBar engine={engine} compact={compact} showSettings={showSettings} onDialog={onDialog} feedback={feedback} />
    </div>
  );
}

/// A draggable divider that changes the width before it by the drag.
function Divider({ onDrag }) {
  const start = React.useRef(null);
  return (
    <div className="calcu-splitter" role="separator" aria-orientation="vertical"
      onPointerDown={(e) => { start.current = e.clientX; e.currentTarget.setPointerCapture(e.pointerId); }}
      onPointerMove={(e) => {
        if (start.current === null) return;
        onDrag(e.clientX - start.current);
        start.current = e.clientX;
      }}
      onPointerUp={() => { start.current = null; }} />
  );
}

/// `rules` (layout="auto", bindings.cpp mobileRules): the artwork fills the
/// height, whatever its size, the bar and the printer follow the iOS app, and
/// the debugger may be left out. A bar wider than the artwork widens the column.
function WideLayout({ engine, width, height, showSettings, onDialog, feedback, rules }) {
  const faceWidth = rules ? Math.max(FACE_MIN_AUTO, faceWidthFor(height))
    : Math.max(FACE_MIN.wide, Math.min(height ? faceWidthFor(height) : 420, width * 0.4));
  const compact = !!rules && (!rules.barLabels || faceWidth < FACE_MIN.wide);
  const columnWidth = Math.max(faceWidth + 2 * FACE_PADDING, compact ? minimumWidth(true) : 0);
  const total = columnHeight(faceWidth, height);
  const printerMin = rules ? rules.printerMin : PRINTER_MIN, printerMax = rules ? rules.printerMax : PRINTER_MAX;
  const hasDebugger = !rules || rules.debugger;
  const [printerWidth, setPrinterWidth] = React.useState(rules ? printerMax : 260);
  const room = width - columnWidth - 2;
  const pw = Math.max(printerMin, Math.min(printerMax, printerWidth, room - (hasDebugger ? DEBUG_MIN : 0)));
  return (
    <div className="calcu-wide" style={{ height: total }}>
      <CalculatorColumn engine={engine} faceWidth={faceWidth} width={columnWidth} compact={compact}
        showSettings={showSettings} onDialog={onDialog} feedback={feedback} />
      <div className="calcu-vline" />
      <div style={{ width: pw, flex: "none", display: "flex" }}><Printer engine={engine} compactBar={!!rules && rules.compactPrinterBar} /></div>
      {hasDebugger && <Divider onDrag={(dx) => setPrinterWidth(Math.max(printerMin, Math.min(printerMax, pw + dx)))} />}
      {hasDebugger && <Debugger engine={engine} />}
    </div>
  );
}

function PortraitLayout({ engine, width, height, showSettings, onDialog, feedback }) {
  const byWidth = width - 2 * FACE_PADDING;
  const faceWidth = Math.max(FACE_MIN.portrait, height ? Math.min(byWidth, faceWidthFor(height)) : byWidth);
  const total = columnHeight(faceWidth, height);
  const [page, setPage] = React.useState("calc");
  const other = page === "calc" ? "printer" : "calc";
  const chevron = (side) => (
    <button type="button" className={`calcu-chevron calcu-chevron-${side}`}
      aria-label={other === "printer" ? "Printer" : "Calculator"} onClick={() => setPage(other)}>
      {side === "left" ? "‹" : "›"}
    </button>
  );
  return (
    <div className="calcu-portrait" style={{ height: total }}>
      {/* Pages and chevrons share the calculator's column: on a screen wider
          than the calculator (a tablet, a desktop window) the chevrons stay at
          its corners instead of the screen's. */}
      <div className="calcu-column" style={{ width: faceWidth + 2 * FACE_PADDING }}>
        <div className="calcu-page" hidden={page !== "calc"}>
          <CalculatorColumn engine={engine} faceWidth={faceWidth} compact={true} showSettings={showSettings}
            onDialog={onDialog} feedback={feedback} />
        </div>
        {page === "printer" && <div className="calcu-page calcu-page-printer"><Printer engine={engine} /></div>}
        {page === "calc" ? chevron("right") : chevron("left")}
      </div>
    </div>
  );
}

function PlayCalculator({
  layout = "portrait",
  width,
  height,
  keyboard = false,
  settings = true,
  model,
  module,
  preset,
  workerUrl,
}) {
  const [engine, setEngine] = React.useState(null);
  const [dialog, setDialog] = React.useState(null);
  const rootRef = React.useRef(null);
  const [measured, setMeasured] = React.useState(0);
  const auto = layout === "auto";
  const [rules, setRules] = React.useState(null);
  const portrait = auto ? !rules || rules.paged : layout !== "wide";

  React.useEffect(() => {
    const e = createEngine({ model, module, workerUrl });
    setEngine(e);
    if (preset) {
      fetchBesideCalc(`presets/${preset}`).then((text) => e.loadState(text))
        .catch((err) => e.setStatus(String(err.message || err)));
    }
    return () => e.destroy();
  }, []);

  // layout="auto": the rules for this size come from the worker.
  React.useEffect(() => {
    if (!auto || !engine) return undefined;
    let current = true;
    engine.request("mobileRules", width, height).then((r) => { if (current) setRules(r); });
    return () => { current = false; };
  }, [auto, engine, width, height]);

  // Without a width the client fills its container.
  React.useEffect(() => {
    if (width) return undefined;
    const el = rootRef.current.parentElement;
    const ro = new ResizeObserver(() => setMeasured(el.clientWidth));
    ro.observe(el);
    return () => ro.disconnect();
  }, [width]);
  const w = Math.max(minimumWidth(auto || portrait), width || measured || (portrait ? 360 : 1100));

  // Keyboard feedback is for touch screens: portrait, and the PWA in any layout.
  const touch = layout !== "wide";
  const feedback = React.useMemo(() => makeFeedback(engine, touch), [engine, touch]);

  // ── Physical keyboard ────────────────────────────────────────────────
  // Only with keyboard={true}, and only while the calculator itself has
  // focus (not a control in it): Tab keeps working as Tab. Which keys are
  // bound is decided in the worker (Shared/KeyboardMap), so every printing
  // key, Escape and Enter is claimed while focused.
  const ownsKeys = (e) => keyboard && engine && !dialog &&
    (e.target === rootRef.current || (e.target.classList && e.target.classList.contains("calcu-key")));
  // The key's KeyPress when the calculator takes it, else null.
  const claimed = (e) => {
    if (!ownsKeys(e)) return null;
    const k = keyPressOf(e);
    return !k.command && (k.produced !== 0 || e.key === "Escape" || e.key === "Enter") ? k : null;
  };
  const onKeyDown = (e) => {
    const k = claimed(e);
    if (!k) return;
    e.preventDefault();
    // e.repeat: the matrix bit is a level — a held key can never re-trigger.
    if (!e.repeat) engine.call("keyDown", k.key, k.produced, k.isLetter, k.shift, k.command);
  };
  const onKeyUp = (e) => {
    const k = claimed(e);
    if (!k) return;
    e.preventDefault();
    engine.call("keyUp", k.key, k.produced, k.isLetter, k.shift, k.command);
  };
  const onBlur = (e) => {
    if (e.target === rootRef.current) delete rootRef.current.dataset.pointerFocus;
    if (engine && !rootRef.current.contains(e.relatedTarget)) engine.call("blur");
  };
  // Marked, as this focus is for the keys and no reason to outline the client:
  // WebKit counts any focus from script as focus-visible.
  const focusForKeys = (e) => {
    if (!keyboard || !e.target.closest || !e.target.closest(".calcu-face")) return;
    rootRef.current.dataset.pointerFocus = "";
    rootRef.current.focus({ preventScroll: true });
  };

  // ── Drag and drop a preset or a card ─────────────────────────────────
  const onDragOver = (e) => { if (e.dataTransfer.types.includes("Files")) e.preventDefault(); };
  const onDrop = (e) => {
    const file = e.dataTransfer.files && e.dataTransfer.files[0];
    if (!file || !engine) return;
    e.preventDefault();
    engine.dropFile(file);
  };

  const Layout = portrait ? PortraitLayout : WideLayout;
  return (
    <div
      ref={rootRef}
      className="calcu-client calcu-device"
      data-layout={portrait ? "portrait" : "wide"}
      style={{ width: w }}
      tabIndex={keyboard ? 0 : undefined}
      aria-label="Calc-U-59 calculator"
      onKeyDown={onKeyDown}
      onKeyUp={onKeyUp}
      onBlur={onBlur}
      onPointerDownCapture={focusForKeys}
      onDragOver={onDragOver}
      onDrop={onDrop}
    >
      {(!auto || rules) && (
        <Layout engine={engine} width={w} height={height} showSettings={settings} onDialog={setDialog} feedback={feedback}
          rules={rules} />
      )}
      <StatusLine engine={engine} />
      <KeyFeedback engine={engine} feedback={feedback} />
      {engine && <DialogHost engine={engine} dialog={dialog} setDialog={setDialog} feedbackSetting={touch} traceSetting={!portrait} />}
    </div>
  );
}

/// The portrait client's width for a height: no wider than the calculator
/// at that height needs (the demo page sizes itself with it).
PlayCalculator.portraitWidth = (height) => faceWidthFor(height) + 2 * FACE_PADDING;

Object.assign(window, { PlayCalculator });
