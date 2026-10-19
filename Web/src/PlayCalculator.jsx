// PlayCalculator — the real, WASM-backed TI-59, and the one global calc.js
// exposes (reference/WebClient.md). Mounted by a host page (the website's
// /play/, Web/index.html: module/preset/card controls and the physical
// keyboard) and by app/app.jsx (the installable standalone app,
// controls={false} — calculator face only, Master Library preloaded).
// Builds the keys from Calculator.jsx's <CalcKey> and CALC_ROWS. Everything that isn't drawing — pacing, key timing,
// presets, cue cards, the card reader — runs in calc-engine-worker.js, in
// the main repo's Shared/ layer compiled to WASM; this component draws what
// the worker posts and forwards input to it.

const {
  useState: usePlayState,
  useEffect: usePlayEffect,
  useRef: usePlayRef,
  useCallback: usePlayCallback,
} = React;

// Keys, the cue card and the controls never change with display state —
// memoized so the 60 Hz display re-renders don't fan out into them while a
// program runs.
const MemoCalcKey = React.memo(CalcKey);
const MemoCueCard = React.memo(CueCard);

// The directory calc.js was loaded from: the worker, the engine and the
// presets sit beside it, wherever the client is hosted. Captured while the
// script runs (document.currentScript is null afterwards); without one — a
// server-side prerender — relative to the page, which a render never uses.
const PLAY_BASE = (() => {
  const script = typeof document !== "undefined" ? document.currentScript : null;
  if (script && script.src) return new URL(".", script.src).href;
  return typeof location !== "undefined" ? new URL(".", location.href).href : "";
})();

// LED canvas size at scale 1 (CSS px); a digit cell is a twelfth of it.
const PLAY_LED_WIDTH = 292;
const PLAY_LED_HEIGHT = 36;

// A KeyboardEvent as Shared/KeyboardMap.hpp's KeyPress: the key's base
// character (letters from the physical key, so Caps Lock and Shift don't
// change it), the character the layout produced, and the modifiers.
function playKeyPress(e) {
  const cp = (s) => (s && [...s].length === 1 ? s.codePointAt(0) : 0);
  let key = 0;
  let isLetter = false;
  if (e.key === "Escape") key = 0x1b;
  else if (e.key === "Enter") key = e.code === "NumpadEnter" ? 0x03 : 0x0d;
  else if (/^Key[A-Z]$/.test(e.code)) { key = e.code.charCodeAt(3) + 32; isLetter = true; }
  else key = cp(e.key);
  return {
    key,
    produced: cp(e.key),
    isLetter,
    shift: e.shiftKey,
    command: e.ctrlKey || e.metaKey || e.altKey,
  };
}

function PlayCalculator({ scale = 1, controls = true, keyboard = false }) {
  const workerRef = usePlayRef(null);
  const post = usePlayCallback((msg) => workerRef.current?.postMessage(msg), []);

  const [cells, setCells] = usePlayState(null);
  const [geometry, setGeometry] = usePlayState(null);
  const [moduleId, setModuleId] = usePlayState("");
  const [modules, setModules] = usePlayState([]);
  const [cueCard, setCueCard] = usePlayState(null);
  const [heldKey, setHeldKey] = usePlayState(-1);   // row×5 + col shown pressed
  const [presets, setPresets] = usePlayState([]);
  const [statusMessage, setStatusMessage] = usePlayState("Starting the emulator…");

  usePlayEffect(() => {
    // The worker's own URL is what its importScripts()/fetch() calls resolve
    // against.
    const worker = new Worker(`${PLAY_BASE}calc-engine-worker.js`);
    workerRef.current = worker;

    worker.onmessage = (e) => {
      const msg = e.data;
      switch (msg.type) {
        case "ready":
          setModules(msg.modules);
          setStatusMessage("");
          break;
        case "display": setCells(msg.cells); break;
        case "geometry": setGeometry(msg.geometry); break;
        case "module": setModuleId(msg.id); break;
        case "cueCard": setCueCard(msg.card); break;
        case "heldKey": setHeldKey(msg.key); break;
        case "error": setStatusMessage(msg.message); break;
        case "stateLoaded":
          setStatusMessage(msg.errors && msg.errors.length ? msg.errors[0] : "");
          break;
        default: break;
      }
    };

    // Only the pickers need it, so the standalone app skips it.
    if (controls) fetch(`${PLAY_BASE}presets/manifest.json`).then((r) => r.json()).then(setPresets).catch(() => {});

    const onVisibility = () => worker.postMessage({ type: document.hidden ? "pause" : "resume" });
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      document.removeEventListener("visibilitychange", onVisibility);
      worker.terminate();
    };
  }, []);

  // The LED shapes for the current size (the page fits the scale to its column).
  usePlayEffect(() => {
    post({ type: "geometry", w: (PLAY_LED_WIDTH * scale) / 12, h: PLAY_LED_HEIGHT * scale });
  }, [scale, post]);

  // ── Physical keyboard ────────────────────────────────────────────────
  // Only with keyboard={true} (the /play/ page), and only while the
  // calculator has focus: the page is a long article with pickers below the
  // calculator, and Tab must keep working as Tab (no keyboard trap). Which
  // keys are bound is decided in the worker (Shared/KeyboardMap), so every
  // printing key, Escape and Enter is claimed while focused — Space would
  // scroll, Backspace could navigate, "/" opens quick-find.
  const rootRef = usePlayRef(null);
  const [keyboardFocused, setKeyboardFocused] = usePlayState(false);

  const claims = (e) => {
    const k = playKeyPress(e);
    return !k.command && (k.produced !== 0 || e.key === "Escape" || e.key === "Enter");
  };

  const handleKeyDown = usePlayCallback((e) => {
    if (!claims(e)) return;
    e.preventDefault();
    // e.repeat: the matrix bit is a level — a held key can never re-trigger.
    if (!e.repeat) post({ type: "keyDown", ...playKeyPress(e) });
  }, [post]);

  const handleKeyUp = usePlayCallback((e) => {
    if (!claims(e)) return;
    e.preventDefault();
    post({ type: "keyUp", ...playKeyPress(e) });
  }, [post]);

  // ── On-screen key clicks/taps ────────────────────────────────────────
  // Real pointer down/up; the worker keeps a short click down for the
  // ROM's minimum hold. <CalcKey> reports its label — every label is unique —
  // and also reports an up when the pointer merely leaves a key, so only the
  // key the pointer pressed is released.
  const pointerLabelRef = usePlayRef(null);
  const pointerDownByLabel = usePlayCallback((label) => {
    for (let ri = 0; ri < CALC_ROWS.length; ri++) {
      const ci = CALC_ROWS[ri].findIndex((kc) => kc.label === label);
      if (ci !== -1) {
        pointerLabelRef.current = label;
        post({ type: "pointerDown", row: ri, col: ci });
        return;
      }
    }
  }, [post]);

  const pointerUpByLabel = usePlayCallback((label) => {
    if (pointerLabelRef.current !== label) return;
    pointerLabelRef.current = null;
    post({ type: "pointerUp" });
  }, [post]);

  const loadPresetText = usePlayCallback((text) => {
    setStatusMessage("Loading program…");
    post({ type: "loadState", text });
  }, [post]);

  const handlePresetChange = usePlayCallback((file) => {
    if (!file) return;
    fetch(`${PLAY_BASE}presets/${file}`).then((r) => r.text()).then(loadPresetText);
  }, [loadPresetText]);

  const handleUpload = usePlayCallback((e) => {
    const file = e.target.files && e.target.files[0];
    if (!file) return;
    file.text().then(loadPresetText);
    e.target.value = "";
  }, [loadPresetText]);

  const changeModule = usePlayCallback((id) => post({ type: "changeModule", id }), [post]);
  const queueCard = usePlayCallback(() => post({ type: "queueCard" }), [post]);

  const keyboardProps = keyboard ? {
    tabIndex: 0,
    onKeyDown: handleKeyDown,
    onKeyUp: handleKeyUp,
    // React's onFocus/onBlur are focusin/focusout, so they also fire when the
    // focus moves to one of the inner key <button>s — a click on a key. Only
    // focus leaving the calculator releases a held key.
    onFocus: () => setKeyboardFocused(true),
    onBlur: (e) => {
      if (e.currentTarget.contains(e.relatedTarget)) return;
      setKeyboardFocused(false);
      post({ type: "blur" });
    },
    // preventScroll matters: without it, focusing on pointer-down scrolls the
    // calculator into view mid-click, which moves the key out from under the
    // pointer before the click completes.
    onPointerDown: () => rootRef.current?.focus({ preventScroll: true }),
  } : {};

  const currentModule = modules.find((m) => m.id === moduleId);

  return (
    <div className="calcu-device calcu-client"
      ref={rootRef}
      {...keyboardProps}
      style={{
      width: `${360 * scale}px`,
      background: "#000",
      padding: `${10 * scale}px ${12 * scale}px ${8 * scale}px`,
      fontFamily: "var(--font-keycap)",
      userSelect: "none",
      // Always reserve the ring's space so focusing doesn't shift the layout.
      outline: `2px solid ${keyboardFocused ? "rgba(240,192,64,.55)" : "transparent"}`,
      outlineOffset: 2,
      borderRadius: 6,
    }}>
      <PlayDisplay
        scale={scale}
        cells={cells}
        geometry={geometry}
        moduleName={currentModule ? currentModule.menuTitle : ""}
        statusMessage={statusMessage}
      />

      {/* Reserved even with no card showing, so the calculator doesn't
          jump size when a card appears/disappears (a 2-row card is ~69px
          at scale=1). */}
      <div style={{ marginTop: 3 * scale, minHeight: 70 * scale }}>
        {cueCard ? <MemoCueCard card={cueCard} scale={scale} /> : null}
      </div>

      <div style={{ display: "grid", gap: 10 * scale, marginTop: 6 * scale }}>
        {CALC_ROWS.map((row, ri) => (
          <div key={ri} style={{ display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: 8 * scale }}>
            {row.map((kc, ci) => (
              <MemoCalcKey key={ci} kc={kc} scale={scale}
                           onDown={pointerDownByLabel} onUp={pointerUpByLabel}
                           forcePressed={heldKey === ri * 5 + ci} />
            ))}
          </div>
        ))}
      </div>

      {/* Hidden, not removed, once focused: removing it would move the
          controls below up between a click's mousedown (which focuses the
          calculator) and its mouseup, and the click would be lost. */}
      {keyboard ? (
        <div style={{
          marginTop: 8 * scale,
          fontFamily: "var(--font-body)",
          fontSize: 11 * scale,
          color: "var(--fg-3)",
          textAlign: "center",
          visibility: keyboardFocused ? "hidden" : "visible",
        }}>
          Click the calculator to type on it with your keyboard.
        </div>
      ) : null}

      {controls ? (
        <PlayControls
          scale={scale}
          modules={modules}
          presets={presets}
          currentModuleId={moduleId}
          onModuleChange={changeModule}
          onPresetChange={handlePresetChange}
          onUpload={handleUpload}
          onQueueCard={queueCard}
          disabled={modules.length === 0}
        />
      ) : null}
    </div>
  );
}

function PlayDisplay({ scale, cells, geometry, moduleName, statusMessage }) {
  return (
    <div style={{
      background: "linear-gradient(180deg, var(--display-bezel-2) 0%, var(--display-bezel) 50%, var(--display-bezel-2) 100%)",
      borderRadius: 10 * scale,
      padding: `${10 * scale}px ${10 * scale}px ${6 * scale}px`,
      border: "1px solid #3a2418",
      boxShadow: "0 1px 0 rgba(255,200,100,.04), inset 0 0 0 1px rgba(0,0,0,.4)",
      position: "relative",
    }}>
      <div style={{
        background: "#0a0302",
        borderRadius: 4 * scale,
        padding: `${10 * scale}px ${12 * scale}px ${4 * scale}px`,
        position: "relative",
        boxShadow: "inset 0 2px 8px rgba(0,0,0,.8)",
        overflow: "hidden",
      }}>
        <LedDisplayCanvas scale={scale} cells={cells} geometry={geometry}
                          width={PLAY_LED_WIDTH} height={PLAY_LED_HEIGHT} />
      </div>

      <div style={{
        display: "flex", justifyContent: "space-between", alignItems: "center",
        padding: `${8 * scale}px 2px ${2 * scale}px`,
        color: "#c89858",
        fontFamily: "var(--font-keycap)",
        fontWeight: 700,
        fontSize: 11 * scale,
        letterSpacing: ".05em",
        minHeight: 16 * scale,
      }}>
        <span>{moduleName || " "}</span>
        <span>{statusMessage}</span>
      </div>
    </div>
  );
}

const PlayControls = React.memo(function PlayControls({ scale, modules, presets, currentModuleId, onModuleChange, onPresetChange, onUpload, onQueueCard, disabled }) {
  const fileInputRef = usePlayRef(null);
  const selectStyle = {
    background: "var(--bg-inset)",
    color: "var(--fg)",
    border: "1px solid var(--stroke)",
    borderRadius: 6 * scale,
    padding: `${6 * scale}px ${8 * scale}px`,
    fontFamily: "var(--font-body)",
    fontSize: 13 * scale,
  };
  return (
    <div style={{
      display: "grid", gap: 8 * scale,
      marginTop: 16 * scale, paddingTop: 12 * scale,
      borderTop: "1px solid rgba(255,255,255,.08)",
    }}>
      <label style={{ display: "grid", gap: 4, fontSize: 11 * scale, color: "var(--fg-3)" }}>
        Solid state module
        <select style={selectStyle} value={currentModuleId} disabled={disabled}
                onChange={(e) => onModuleChange(e.target.value)}>
          {modules.map((m) => <option key={m.id} value={m.id}>{m.menuTitle}</option>)}
        </select>
      </label>
      <label style={{ display: "grid", gap: 4, fontSize: 11 * scale, color: "var(--fg-3)" }}>
        Load a preset program
        <select style={selectStyle} defaultValue="" disabled={disabled}
                onChange={(e) => { onPresetChange(e.target.value); e.target.value = ""; }}>
          <option value="" disabled>Choose a preset…</option>
          {presets.map((p) => <option key={p.file} value={p.file}>{p.title}</option>)}
        </select>
      </label>
      <button
        type="button"
        disabled={disabled}
        onClick={onQueueCard}
        title="Passes the virtual magnetic card through the reader — blank at first, then whatever was last written to it."
        style={{ ...selectStyle, cursor: disabled ? "default" : "pointer" }}
      >
        Queue Card
      </button>
      <button
        type="button"
        disabled={disabled}
        onClick={() => fileInputRef.current && fileInputRef.current.click()}
        style={{ ...selectStyle, cursor: disabled ? "default" : "pointer" }}
      >
        Upload your own .ti59 file…
      </button>
      <input
        ref={fileInputRef}
        type="file"
        accept=".ti59,.ti58,.ti58c"
        style={{ display: "none" }}
        onChange={onUpload}
      />
    </div>
  );
});

Object.assign(window, { PlayCalculator });
