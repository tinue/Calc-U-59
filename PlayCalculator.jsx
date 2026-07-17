// PlayCalculator — the real, WASM-backed TI-59 (docs/#play).
// Reuses docs/Calculator.jsx's <CalcKey> and CALC_ROWS key table for
// identical key chrome/layout, but every press drives the actual emulation
// core (via calc-engine-worker.js) instead of toy JS arithmetic. See the
// plan at /Users/me/.claude/plans/replicated-riding-duckling.md for scope
// decisions (TI-59 only, no debugger/printer, module 01 preloaded, two
// curated presets, client-side upload only).

const {
  useState: usePlayState,
  useEffect: usePlayEffect,
  useRef: usePlayRef,
  useMemo: usePlayMemo,
  useCallback: usePlayCallback,
} = React;

// Keys never change with display state — memoized so the 60 Hz display
// re-renders don't fan out into 45 key re-renders while a program runs.
const MemoCalcKey = React.memo(CalcKey);

const LED_RED = "var(--led-red)";
const LED_BAR_GLOW = "0 0 6px rgba(255,38,20,.8), 0 0 12px rgba(255,38,20,.4)";

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

  const [ready, setReady] = usePlayState(false);
  const [display, setDisplay] = usePlayState(null);
  const [currentModule, setCurrentModule] = usePlayState(null); // {id, menuTitle, cuecards}
  const [presetCueCard, setPresetCueCard] = usePlayState(null); // from a loaded file's CUECARD: section
  const [programNumber, setProgramNumber] = usePlayState(0);    // SCOM-selected library program (worker-polled)
  const [modules, setModules] = usePlayState([]);
  const [presets, setPresets] = usePlayState([]);
  const [statusMessage, setStatusMessage] = usePlayState("Starting the emulator…");

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
          setCurrentModule({ id: msg.id, menuTitle: msg.menuTitle, cuecards: msg.cuecards });
          break;
        case "cueCard":
          if (msg.card) setPresetCueCard(msg.card);
          break;
        case "programNumber":
          setProgramNumber(msg.n);
          break;
        case "stateLoaded":
          setStatusMessage(msg.errors && msg.errors.length ? msg.errors[0] : "");
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

  const press = usePlayCallback((row, col) => {
    const worker = workerRef.current;
    if (!worker) return;
    worker.postMessage({ type: "press", row, col });
    setTimeout(() => worker.postMessage({ type: "release", row, col }), 80);
  }, []);

  // <CalcKey> (from docs/Calculator.jsx) calls onPress(label); resolve the
  // label back to its grid position via CALC_ROWS. Every label is unique.
  // Stable identity (useCallback) so MemoCalcKey's memoization holds.
  const pressByLabel = usePlayCallback((label) => {
    for (let ri = 0; ri < CALC_ROWS.length; ri++) {
      const ci = CALC_ROWS[ri].findIndex((kc) => kc.label === label);
      if (ci !== -1) { press(ri, ci); return; }
    }
  }, [press]);

  function handleModuleChange(id) {
    // No "Loading module…" status: switching modules is a single fast
    // in-memory swap (well under 100ms), and the message had no message
    // to clear it on completion — it just stuck around forever. Not worth
    // a transient status for something this quick.
    setPresetCueCard(null);
    workerRef.current?.postMessage({ type: "loadModule", id });
  }

  function loadPresetText(text) {
    setStatusMessage("Loading program…");
    setPresetCueCard(null);
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

  // The shown card mirrors EmulatorViewModel.swift's resolvedCueCard():
  // while the machine has a library program selected (SCOM[9], polled by
  // the worker — the source of truth, so preset KEYSTROKES playback,
  // program-driven Pgm calls, and RST all update it correctly), that
  // program's module card wins; otherwise the loaded file's own card.
  const programCueCard = usePlayMemo(() => {
    if (programNumber <= 0 || !currentModule || !currentModule.cuecards) return null;
    const record = currentModule.cuecards[String(programNumber)];
    return record ? cueCardFromPacked(record) : null;
  }, [programNumber, currentModule]);
  const activeCueCard = programCueCard || presetCueCard;

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

      {/* Reserved even with no card showing, so the calculator doesn't
          jump size when a card appears/disappears. Measured against a
          2-row card (SolidState: ~96.6px, MagnetCard: ~95.75px at
          scale=1.4, i.e. ~69px at scale=1) after cuecard.jsx's row-height
          fixes made all 2-row cards a consistent height regardless of
          which cells are populated — 70px leaves a small margin. */}
      <div style={{ marginTop: 3 * scale, minHeight: 70 * scale }}>
        {activeCueCard ? <CueCard card={activeCueCard} scale={scale} /> : null}
      </div>

      <div style={{ display: "grid", gap: 10 * scale, marginTop: 6 * scale }}>
        {CALC_ROWS.map((row, ri) => (
          <div key={ri} style={{ display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: 8 * scale }}>
            {row.map((kc, ci) => <MemoCalcKey key={ci} kc={kc} scale={scale} onPress={pressByLabel} />)}
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
        onQueueCard={() => workerRef.current?.postMessage({ type: "queueCard" })}
        disabled={!ready}
      />
    </div>
  );
}

// Absolute-positioned LED segment bars (the shared mechanics behind the
// C annunciator and the digit 7 — both drawn as bars rather than font
// glyphs). Each entry in `bars` maps the bar thickness to its edge
// placement. Bar specs live at module scope so their identities are
// stable across renders.
function SegmentBars({ scale, inset, opacity, className, bars }) {
  const t = 3 * scale;
  const base = {
    position: "absolute",
    background: LED_RED,
    boxShadow: LED_BAR_GLOW,
    borderRadius: 1 * scale,
  };
  return (
    <div className={className} style={{ position: "absolute", inset, opacity }}>
      {bars.map((b, i) => <div key={i} style={{ ...base, ...b(t) }} />)}
    </div>
  );
}

// The "C" (calculate) annunciator — top, bottom, and both left segments
// (7-segment bits A, D, E, F; the same segmentsC = 0b0111001 pattern
// LEDDisplayView.swift uses) — rather than the display font's letter "C"
// glyph, which doesn't reliably render at the same weight/size as the
// digit glyphs in that font.
const C_BARS = [
  (t) => ({ top: 0, left: 0, right: 0, height: t }),
  (t) => ({ bottom: 0, left: 0, right: 0, height: t }),
  (t) => ({ top: 0, bottom: "52%", left: 0, width: t }),
  (t) => ({ bottom: 0, top: "52%", left: 0, width: t }),
];

function CIndicator({ scale, intensity }) {
  return <SegmentBars scale={scale} inset="12% 22%" opacity={intensity} className="led-cell-c" bars={C_BARS} />;
}

// The digit "7" — top bar + a full-height right-side bar (7-segment bits
// A, B, C) — rather than the display font's "7" glyph, which turned out
// to include an extra top-left stroke real 7-segment hardware doesn't
// light for this digit.
const SEVEN_BARS = [
  (t) => ({ top: 0, left: 0, right: 0, height: t }),
  (t) => ({ top: 0, bottom: 0, right: 0, width: t }),
];

function Digit7({ scale }) {
  return <SegmentBars scale={scale} inset="8% 20%" className="led-cell-7" bars={SEVEN_BARS} />;
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
      ) : char === "7" ? (
        <Digit7 scale={scale} />
      ) : (
        <span className="led-cell-fg" style={{
          position: "absolute", inset: 0,
          fontFamily: "var(--font-display)",
          fontSize: 26 * scale,
          color: LED_RED,
          textShadow: "0 0 10px rgba(255,38,20,.7), 0 0 22px rgba(255,38,20,.3)",
        }}>{char}</span>
      )}
      {hasDot ? (
        <span className="led-cell-dot" style={{
          position: "absolute", right: -1 * scale, bottom: "8%",
          width: 4 * scale, height: 4 * scale, borderRadius: "50%",
          background: LED_RED,
          boxShadow: "0 0 6px rgba(255,38,20,.8)",
        }} />
      ) : null}
    </div>
  );
}

function PlayDisplay({ scale, cells, moduleName, statusMessage }) {
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
        <span>{moduleName || " "}</span>
        <span>{statusMessage}</span>
      </div>
    </div>
  );
}

function PlayControls({ scale, modules, presets, currentModuleId, onModuleChange, onPresetChange, onUpload, onQueueCard, disabled }) {
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
        title="Feeds a virtual magnetic card to 2nd Write / 2nd Read — same card every time, so writing then reading it back reproduces what was last written."
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
}

Object.assign(window, { PlayCalculator });
