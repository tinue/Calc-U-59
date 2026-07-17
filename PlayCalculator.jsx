// PlayCalculator — the real, WASM-backed TI-59 (docs/#play).
// Reuses docs/Calculator.jsx's <CalcKey> for identical key chrome, but
// every press drives the actual emulation core (via calc-engine-worker.js)
// instead of toy JS arithmetic. See the plan at
// /Users/me/.claude/plans/replicated-riding-duckling.md for scope
// decisions (TI-59 only, no debugger/printer/card reader, module 01
// preloaded, two curated presets, client-side upload only).

const { useState: usePlayState, useEffect: usePlayEffect, useRef: usePlayRef } = React;

// Same 9x5 grid shape as docs/Calculator.jsx's `rows` — row/col here ARE
// the UI grid position pressUIKey()/releaseUIKey() expect (see
// docs/matrix-keys.js).
const D = "dark", C = "cream", Y = "yellow";
const PLAY_ROWS = [
  [
    { top: "A'", label: "A", tone: D }, { top: "B'", label: "B", tone: D },
    { top: "C'", label: "C", tone: D }, { top: "D'", label: "D", tone: D }, { top: "E'", label: "E", tone: D },
  ],
  [
    { top: "", label: "2nd", tone: Y }, { top: "", label: "INV", tone: D },
    { top: "log", label: "lnx", tone: D }, { top: "CP", label: "CE", tone: D }, { top: "", label: "CLR", tone: Y },
  ],
  [
    { top: "Pgm", label: "LRN", tone: D }, { top: "P→R", label: "x⇄t", tone: D },
    { top: "sin", label: "x²", tone: D }, { top: "cos", label: "√x", tone: D }, { top: "tan", label: "1/x", tone: D },
  ],
  [
    { top: "Ins", label: "SST", tone: D }, { top: "CMs", label: "STO", tone: D },
    { top: "Exc", label: "RCL", tone: D }, { top: "Prd", label: "SUM", tone: D }, { top: "Ind", label: "yˣ", tone: D },
  ],
  [
    { top: "Del", label: "BST", tone: D }, { top: "Eng", label: "EE", tone: D },
    { top: "Fix", label: "(", tone: D }, { top: "Int", label: ")", tone: D }, { top: "|x|", label: "÷", tone: Y },
  ],
  [
    { top: "Pause", label: "GTO", tone: D }, { top: "x=t", label: "7", tone: C },
    { top: "Nop", label: "8", tone: C }, { top: "Op", label: "9", tone: C }, { top: "Deg", label: "×", tone: Y },
  ],
  [
    { top: "Lbl", label: "SBR", tone: D }, { top: "x≥t", label: "4", tone: C },
    { top: "Σ+", label: "5", tone: C }, { top: "x̄", label: "6", tone: C }, { top: "Rad", label: "−", tone: Y },
  ],
  [
    { top: "St flg", label: "RST", tone: D }, { top: "If flg", label: "1", tone: C },
    { top: "D.MS", label: "2", tone: C }, { top: "π", label: "3", tone: C }, { top: "Grad", label: "+", tone: Y },
  ],
  [
    { top: "Write", label: "R/S", tone: D }, { top: "Dsz", label: "0", tone: C },
    { top: "Adv", label: ".", tone: C }, { top: "Prt", label: "+/-", tone: C }, { top: "List", label: "=", tone: Y },
  ],
];

// Position of the physical "2nd" key and the key whose 2nd-function is
// "Pgm" (the LRN key) — used to detect a "2nd Pgm NN" dispatch so the
// matching module cue card can be shown. Digit positions are derived
// below from PLAY_ROWS itself rather than hand-listed, so they can't
// drift out of sync with the grid.
const SECOND_POS = [1, 0];
const PGM_POS = [2, 0];
const DIGIT_POS = {};
PLAY_ROWS.forEach((row, ri) => row.forEach((kc, ci) => {
  if (/^[0-9]$/.test(kc.label)) DIGIT_POS[kc.label] = [ri, ci];
}));

function decodeDisplayChar(digit, ctrl) {
  switch (ctrl) {
    case 0: case 1: case 8: case 9:
      return String((digit & 0xF) % 10);
    case 2: case 3: case 4:
      return " ";
    case 5:
      return digit === 0 ? "-" : "°";
    case 6:
      return "-";
    default:
      return " ";
  }
}

// snap.digits/ctrl: 12 elements, index 0 = rightmost position (13),
// index 11 = leftmost (position 2) — see Core/TMC0501.hpp's DisplaySnapshot
// and App/Views/LEDDisplayView.swift's `x = (11-i) * digitWidth` layout.
// dpAfterglowMask (not dpPos) gates whether the decimal point is actually
// visible right now — same per-position decay/afterglow counter the
// digits themselves use for blink, so a blinked-off digit and its dot go
// dark together automatically. dpPos alone is just "last known position"
// and stays set through a blink-off phase, which is why using it directly
// showed a dot that should've been blanked.
//
// Returns 12 cells in left-to-right visual order (cells[0] = position 13,
// the leftmost slot ... cells[11] = position 2, the rightmost), each
// {char, hasDot, isC, cIntensity}. Rendered as fixed-size grid cells (see
// LedCell) rather than concatenated into one string: a single
// right-aligned string can't be kept pixel-aligned with the
// differently-shaped ghost backdrop, which was the root cause of the C
// indicator and decimal point landing in the wrong place.
function decodeDisplayCells(snap) {
  if (!snap) {
    const cells = Array.from({ length: 12 }, () => ({ char: "", hasDot: false, isC: false, cIntensity: 0 }));
    cells[11] = { char: "0", hasDot: true, isC: false, cIntensity: 0 };
    return cells;
  }
  const cells = [];
  for (let i = 11; i >= 0; i--) {
    // Leftmost slot (i=11) doubles as the "C" (calculate) annunciator.
    // calcIndicator is a duty-cycle fraction (0..1) sampled each tick, not
    // a plain boolean — rendering it as one flattened the natural flicker
    // real hardware/the Swift app has (Flag A toggling fast enough that
    // the fraction genuinely varies frame to frame). cIntensity carries
    // that fraction through to <CIndicator>, which fades its opacity by
    // it instead of a hard on/off.
    if (i === 11 && snap.calcIndicator > 0) {
      cells.push({ char: "", hasDot: false, isC: true, cIntensity: snap.calcIndicator });
      continue;
    }
    const suppressed = ((snap.suppressedMask >> i) & 1) === 1;
    const char = suppressed ? "" : decodeDisplayChar(snap.digits[i], snap.ctrl[i]).trim();
    const hasDot = ((snap.dpAfterglowMask >> i) & 1) === 1;
    cells.push({ char, hasDot, isC: false, cIntensity: 0 });
  }
  return cells;
}

function PlayCalculator({ scale = 1 }) {
  const workerRef = usePlayRef(null);
  const pressBuffer = usePlayRef([]);

  const [ready, setReady] = usePlayState(false);
  const [display, setDisplay] = usePlayState(null);
  const [currentModule, setCurrentModule] = usePlayState(null); // {id, title, menuTitle, cuecards}
  const [activeCueCard, setActiveCueCard] = usePlayState(null);
  const [modules, setModules] = usePlayState([]);
  const [presets, setPresets] = usePlayState([]);
  const [statusMessage, setStatusMessage] = usePlayState("Starting the emulator…");
  const fileInputRef = usePlayRef(null);

  usePlayEffect(() => {
    const worker = new Worker("calc-engine-worker.js");
    workerRef.current = worker;

    worker.onmessage = (e) => {
      const msg = e.data;
      switch (msg.type) {
        case "ready":
          setReady(true);
          setStatusMessage("");
          break;
        case "display":
          setDisplay(msg);
          break;
        case "moduleLoaded":
          setCurrentModule({ id: msg.id, title: msg.title, menuTitle: msg.menuTitle, cuecards: msg.cuecards });
          setActiveCueCard(null);
          break;
        case "cueCard":
          if (msg.card) setActiveCueCard(msg.card);
          break;
        case "stateLoaded":
          setStatusMessage("");
          break;
        default:
          break;
      }
    };

    fetch("wasm/roms/modules.json").then((r) => r.json()).then(setModules).catch(() => {});
    fetch("presets/manifest.json").then((r) => r.json()).then(setPresets).catch(() => {});

    const onVisibility = () => {
      worker.postMessage({ type: document.hidden ? "pause" : "resume" });
    };
    document.addEventListener("visibilitychange", onVisibility);

    return () => {
      document.removeEventListener("visibilitychange", onVisibility);
      worker.terminate();
    };
  }, []);

  function recordPressForCueCardDetection(row, col) {
    const buf = pressBuffer.current;
    buf.push([row, col]);
    if (buf.length > 4) buf.shift();
    if (buf.length === 4
        && buf[0][0] === SECOND_POS[0] && buf[0][1] === SECOND_POS[1]
        && buf[1][0] === PGM_POS[0] && buf[1][1] === PGM_POS[1]) {
      const d1 = Object.entries(DIGIT_POS).find(([, p]) => p[0] === buf[2][0] && p[1] === buf[2][1]);
      const d2 = Object.entries(DIGIT_POS).find(([, p]) => p[0] === buf[3][0] && p[1] === buf[3][1]);
      if (d1 && d2 && currentModule) {
        const programNumber = String(parseInt(d1[0] + d2[0], 10));
        const card = currentModule.cuecards && currentModule.cuecards[programNumber];
        if (card) setActiveCueCard(cueCardFromPacked(card));
      }
      buf.length = 0;
    }
  }

  function press(row, col) {
    const worker = workerRef.current;
    if (!worker) return;
    recordPressForCueCardDetection(row, col);
    worker.postMessage({ type: "press", row, col });
    setTimeout(() => worker.postMessage({ type: "release", row, col }), 80);
  }

  // <CalcKey> (from docs/Calculator.jsx) calls onPress(label); resolve the
  // label back to its grid position via PLAY_ROWS. Every label is unique.
  function pressByLabel(label) {
    for (let ri = 0; ri < PLAY_ROWS.length; ri++) {
      const ci = PLAY_ROWS[ri].findIndex((kc) => kc.label === label);
      if (ci !== -1) { press(ri, ci); return; }
    }
  }

  function handleModuleChange(id) {
    setStatusMessage("Loading module…");
    workerRef.current?.postMessage({ type: "loadModule", id });
  }

  function loadPresetText(text) {
    setStatusMessage("Loading program…");
    setActiveCueCard(null);
    workerRef.current?.postMessage({ type: "loadState", text });
  }

  function handlePresetChange(file) {
    if (!file) return;
    fetch(`presets/${file}`).then((r) => r.text()).then(loadPresetText);
  }

  function handleUpload(e) {
    const file = e.target.files && e.target.files[0];
    if (!file) return;
    file.text().then(loadPresetText);
    e.target.value = "";
  }

  const cells = decodeDisplayCells(display);

  return (
    <div className="calcu-device" style={{
      width: `${360 * scale}px`,
      background: "#000",
      padding: `${10 * scale}px ${12 * scale}px ${8 * scale}px`,
      fontFamily: "var(--font-keycap)",
      userSelect: "none",
    }}>
      <PlayDisplay
        scale={scale}
        cells={cells}
        moduleName={currentModule ? currentModule.menuTitle : ""}
        statusMessage={statusMessage}
      />

      {/* Reserved even with no card showing, sized to the ML-01 cue card
          (measured ~88px at scale=1 — that card renders correctly; others
          currently don't, see cuecard.jsx/cuecard-data.js) so the
          calculator doesn't jump size when a card appears/disappears. */}
      <div style={{ marginTop: 10 * scale, minHeight: 88 * scale }}>
        {activeCueCard ? <CueCard card={activeCueCard} /> : null}
      </div>

      <div style={{ display: "grid", gap: 10 * scale, marginTop: 14 * scale }}>
        {PLAY_ROWS.map((row, ri) => (
          <div key={ri} style={{ display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: 8 * scale }}>
            {row.map((kc, ci) => <CalcKey key={ci} kc={kc} scale={scale} onPress={pressByLabel} />)}
          </div>
        ))}
      </div>

      <PlayControls
        scale={scale}
        modules={modules}
        presets={presets}
        currentModuleId={currentModule ? currentModule.id : ""}
        onModuleChange={handleModuleChange}
        onPresetChange={handlePresetChange}
        onUpload={handleUpload}
        fileInputRef={fileInputRef}
        disabled={!ready}
      />
    </div>
  );
}

// The "C" (calculate) annunciator, drawn as its own 4-bar shape — top,
// bottom, and both left segments (7-segment bits A, D, E, F; the same
// segmentsC = 0b0111001 pattern LEDDisplayView.swift uses) — rather than
// the display font's letter "C" glyph, which doesn't reliably render at
// the same weight/size as the digit glyphs in that font.
function CIndicator({ scale, intensity }) {
  const bar = {
    position: "absolute",
    background: "#ff2614",
    boxShadow: "0 0 6px rgba(255,38,20,.8), 0 0 12px rgba(255,38,20,.4)",
    borderRadius: 1 * scale,
  };
  const thickness = 3 * scale;
  return (
    <div className="led-cell-c" style={{ position: "absolute", inset: "12% 22%", opacity: intensity }}>
      <div style={{ ...bar, top: 0, left: 0, right: 0, height: thickness }} />
      <div style={{ ...bar, bottom: 0, left: 0, right: 0, height: thickness }} />
      <div style={{ ...bar, top: 0, bottom: "52%", left: 0, width: thickness }} />
      <div style={{ ...bar, bottom: 0, top: "52%", left: 0, width: thickness }} />
    </div>
  );
}

// One fixed-size digit position: ghost "8" backdrop + the real glyph
// (digit/minus/degree/blank) or the C indicator stacked on top, plus an
// optional decimal dot anchored to this cell — mirrors
// LEDDisplayView.swift's per-position (x = (11-i)*digitWidth) drawing
// instead of relying on text-flow alignment across two differently-shaped
// strings.
function LedCell({ scale, char, hasDot, isC, cIntensity }) {
  return (
    <div className="led-cell" style={{ position: "relative", textAlign: "center", lineHeight: 1 }}>
      <span style={{
        fontFamily: "var(--font-display)",
        fontSize: 26 * scale,
        color: "#3a0e08",
      }}>8</span>
      {isC ? (
        <CIndicator scale={scale} intensity={cIntensity} />
      ) : (
        <span className="led-cell-fg" style={{
          position: "absolute", inset: 0,
          fontFamily: "var(--font-display)",
          fontSize: 26 * scale,
          color: "#ff2614",
          textShadow: "0 0 10px rgba(255,38,20,.7), 0 0 22px rgba(255,38,20,.3)",
        }}>{char}</span>
      )}
      {hasDot ? (
        <span className="led-cell-dot" style={{
          position: "absolute", right: -1 * scale, bottom: "8%",
          width: 4 * scale, height: 4 * scale, borderRadius: "50%",
          background: "#ff2614",
          boxShadow: "0 0 6px rgba(255,38,20,.8)",
        }} />
      ) : null}
    </div>
  );
}

function PlayDisplay({ scale, cells, moduleName, statusMessage }) {
  return (
    <div style={{
      background: "linear-gradient(180deg,#1a0c08 0%,#2c1812 50%,#1a0c08 100%)",
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
        display: "grid",
        gridTemplateColumns: "repeat(12, 1fr)",
      }}>
        {cells.map((c, i) => (
          <LedCell key={i} scale={scale} char={c.char} hasDot={c.hasDot} isC={c.isC} cIntensity={c.cIntensity} />
        ))}
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
        <span>{moduleName || " "}</span>
        <span>{statusMessage}</span>
      </div>
    </div>
  );
}

function PlayControls({ scale, modules, presets, currentModuleId, onModuleChange, onPresetChange, onUpload, fileInputRef, disabled }) {
  const selectStyle = {
    background: "var(--bg-inset)",
    color: "var(--fg)",
    border: "1px solid var(--stroke, #5a4628)",
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
}

Object.assign(window, { PlayCalculator });
