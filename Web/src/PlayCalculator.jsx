// PlayCalculator — the web client, and the one global calc.js exposes
// (reference/WebClient.md has the props). Two layouts:
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
const SPLITTERS = 1 + 5;  // the line after the calculator, the divider before the debugger

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

// Keyboard feedback (Settings, portrait): a vibration where the browser has
// one (not iOS Safari), or a short click synthesised with WebAudio.
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
function makeFeedback(enabled) {
  return (kind) => {
    if (!enabled) return;
    const mode = Number(storageGet(FEEDBACK_KEY) || 0);
    const count = kind === "clean" ? 2 : 1;
    if (mode === 1 && navigator.vibrate) navigator.vibrate(count === 2 ? [15, 100, 15] : 15);
    else if (mode === 2) playClick(count);
  };
}

function StatusLine({ engine }) {
  const status = useEngine(engine, (s) => s.status);
  if (!status) return null;
  return (
    <div className="calcu-status" role="status">
      <span>{status}</span>
      {engine && <button type="button" className="calcu-iconbutton" aria-label="Dismiss" onClick={engine.clearStatus}>×</button>}
    </div>
  );
}

function CalculatorColumn({ engine, faceWidth, compact, showSettings, onDialog, feedback }) {
  return (
    <div className="calcu-calc" style={{ width: faceWidth + 2 * FACE_PADDING }}>
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

function WideLayout({ engine, width, height, showSettings, onDialog, feedback }) {
  const aspect = 2064 / 4075;
  const faceWidth = Math.max(FACE_MIN.wide,
    Math.min(height ? (height - BAR_HEIGHT - 2 * FACE_PADDING) * aspect : 420, width * 0.4));
  const total = Math.max(height || 0, faceWidth / aspect + 2 * FACE_PADDING + BAR_HEIGHT);
  const [printerWidth, setPrinterWidth] = React.useState(260);
  const room = width - faceWidth - 2 * FACE_PADDING - 2;
  const pw = Math.max(PRINTER_MIN, Math.min(PRINTER_MAX, printerWidth, room - DEBUG_MIN));
  return (
    <div className="calcu-wide" style={{ height: total }}>
      <CalculatorColumn engine={engine} faceWidth={faceWidth} showSettings={showSettings} onDialog={onDialog} feedback={feedback} />
      <div className="calcu-vline" />
      <div style={{ width: pw, flex: "none", display: "flex" }}><Printer engine={engine} /></div>
      <Divider onDrag={(dx) => setPrinterWidth(Math.max(PRINTER_MIN, Math.min(PRINTER_MAX, pw + dx)))} />
      <Debugger engine={engine} />
    </div>
  );
}

function PortraitLayout({ engine, width, height, showSettings, onDialog, feedback }) {
  const aspect = 2064 / 4075;
  const byWidth = width - 2 * FACE_PADDING;
  const faceWidth = Math.max(FACE_MIN.portrait,
    height ? Math.min(byWidth, (height - BAR_HEIGHT - 2 * FACE_PADDING) * aspect) : byWidth);
  const total = Math.max(height || 0, faceWidth / aspect + 2 * FACE_PADDING + BAR_HEIGHT);
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
      <div className="calcu-page" hidden={page !== "calc"}>
        <CalculatorColumn engine={engine} faceWidth={faceWidth} compact={true} showSettings={showSettings}
          onDialog={onDialog} feedback={feedback} />
      </div>
      {page === "printer" && <div className="calcu-page calcu-page-printer"><Printer engine={engine} /></div>}
      {page === "calc" ? chevron("right") : chevron("left")}
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
}) {
  const [engine, setEngine] = React.useState(null);
  const [dialog, setDialog] = React.useState(null);
  const rootRef = React.useRef(null);
  const [measured, setMeasured] = React.useState(0);
  const portrait = layout !== "wide";

  React.useEffect(() => {
    const e = createEngine({ model, module });
    setEngine(e);
    if (preset) {
      fetchBesideCalc(`presets/${preset}`).then((text) => e.loadState(text))
        .catch((err) => e.setStatus(String(err.message || err)));
    }
    return () => e.destroy();
  }, []);

  // Without a width the client fills its container.
  React.useEffect(() => {
    if (width) return undefined;
    const el = rootRef.current.parentElement;
    const ro = new ResizeObserver(() => setMeasured(el.clientWidth));
    ro.observe(el);
    return () => ro.disconnect();
  }, [width]);
  const w = Math.max(minimumWidth(portrait), width || measured || (portrait ? 360 : 1100));

  // Keyboard feedback on each key press (portrait).
  const feedback = React.useMemo(() => makeFeedback(portrait), [portrait]);
  const heldKey = useEngine(engine, (s) => s.runState.heldKey);
  React.useEffect(() => { if (heldKey >= 0) feedback("key"); }, [heldKey]);

  // ── Physical keyboard ────────────────────────────────────────────────
  // Only with keyboard={true}, and only while the calculator itself has
  // focus (not a control in it): Tab keeps working as Tab. Which keys are
  // bound is decided in the worker (Shared/KeyboardMap), so every printing
  // key, Escape and Enter is claimed while focused.
  const ownsKeys = (e) => keyboard && engine && !dialog &&
    (e.target === rootRef.current || (e.target.classList && e.target.classList.contains("calcu-key")));
  const claims = (e) => {
    const k = keyPressOf(e);
    return !k.command && (k.produced !== 0 || e.key === "Escape" || e.key === "Enter");
  };
  const onKeyDown = (e) => {
    if (!ownsKeys(e) || !claims(e)) return;
    e.preventDefault();
    // e.repeat: the matrix bit is a level — a held key can never re-trigger.
    if (!e.repeat) engine.post({ type: "call", method: "keyDown", args: Object.values(keyPressOf(e)) });
  };
  const onKeyUp = (e) => {
    if (!ownsKeys(e) || !claims(e)) return;
    e.preventDefault();
    engine.post({ type: "call", method: "keyUp", args: Object.values(keyPressOf(e)) });
  };
  const onBlur = (e) => {
    if (engine && !rootRef.current.contains(e.relatedTarget)) engine.call("blur");
  };
  const focusForKeys = (e) => {
    if (keyboard && e.target.closest && e.target.closest(".calcu-face")) rootRef.current.focus({ preventScroll: true });
  };

  // ── Drag and drop a preset ───────────────────────────────────────────
  const onDragOver = (e) => { if (e.dataTransfer.types.includes("Files")) e.preventDefault(); };
  const onDrop = (e) => {
    const file = e.dataTransfer.files && e.dataTransfer.files[0];
    if (!file || !engine) return;
    e.preventDefault();
    if (/\.(ti59|ti58|ti58c)$/i.test(file.name)) file.text().then((t) => engine.loadState(t));
    else engine.setStatus(`${file.name}: not a .ti59, .ti58 or .ti58c file`);
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
      <Layout engine={engine} width={w} height={height} showSettings={settings} onDialog={setDialog} feedback={feedback} />
      <StatusLine engine={engine} />
      {engine && <DialogHost engine={engine} dialog={dialog} setDialog={setDialog} portrait={portrait} />}
    </div>
  );
}

Object.assign(window, { PlayCalculator });
