// PlayCalculator — the real, WASM-backed TI-59. Mounted from two places:
// docs/index.html (docs/#play, with the module/preset/upload controls) and
// docs/app/index.html (the installable standalone app, controls={false} —
// calculator face only, module 01 preloaded, no way to switch modules or
// load a file).
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

function PlayCalculator({ scale = 1, controls = true }) {
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
    // Root-relative: PlayCalculator is mounted both from docs/index.html
    // (at the site root) and docs/app/index.html (one directory down), and
    // a page-relative URL here would resolve against whichever document
    // mounted it. The worker script's own URL — not the page's — is what
    // its internal importScripts()/fetch() calls resolve against, so this
    // is the only path in this file that needs to be root-relative for
    // both mount points to work; everything the worker fetches internally
    // is already relative to itself.
    const worker = new Worker("/calc-engine-worker.js");
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

    // Same root-relative reasoning as the worker URL above. Only needed to
    // populate the module/preset pickers, so skip it entirely when those
    // controls aren't rendered (the standalone app).
    if (controls) {
      fetch("/wasm/roms/modules.json").then((r) => r.json()).then(setModules).catch(() => {});
      fetch("/presets/manifest.json").then((r) => r.json()).then(setPresets).catch(() => {});
    }

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
    fetch(`/presets/${file}`).then((r) => r.text()).then(loadPresetText);
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
        snap={display}
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

      {controls ? (
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
      ) : null}
    </div>
  );
}

function PlayDisplay({ scale, snap, moduleName, statusMessage }) {
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
        <LedDisplayCanvas scale={scale} snap={snap} />
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
