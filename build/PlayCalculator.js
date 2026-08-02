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
  useCallback: usePlayCallback
} = React;

// Keys never change with display state — memoized so the 60 Hz display
// re-renders don't fan out into 45 key re-renders while a program runs.
const MemoCalcKey = React.memo(CalcKey);

// PLAY_KEY_HOLD_MS: the *minimum* a key stays down, not a fixed synthetic
// hold — real on-screen/keyboard presses release on the real pointer-up/
// key-up, extended to this floor if they were shorter. PLAY_KEY_GAP_MS is
// the gap between taps in a fully synthesized sequence (2nd-prefixed
// bindings, and calc-engine-worker.js's own KEYSTROKES replay). The ROM only
// accepts a key seen at two scans one display sweep apart, so a release
// that lands too early is discarded as bounce — see KeypressLatch.md.
const PLAY_KEY_HOLD_MS = 80;
const PLAY_KEY_GAP_MS = 120;
function PlayCalculator({
  scale = 1,
  controls = true,
  keyboard = false
}) {
  const workerRef = usePlayRef(null);
  const [ready, setReady] = usePlayState(false);
  const [display, setDisplay] = usePlayState(null);
  const [currentModule, setCurrentModule] = usePlayState(null); // {id, menuTitle, cuecards}
  const [presetCueCard, setPresetCueCard] = usePlayState(null); // from a loaded file's CUECARD: section
  const [programNumber, setProgramNumber] = usePlayState(0); // SCOM-selected library program (worker-polled)
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
    worker.onmessage = e => {
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
          setCurrentModule({
            id: msg.id,
            menuTitle: msg.menuTitle,
            cuecards: msg.cuecards
          });
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
      fetch("/wasm/roms/modules.json").then(r => r.json()).then(setModules).catch(() => {});
      fetch("/presets/manifest.json").then(r => r.json()).then(setPresets).catch(() => {});
    }
    const onVisibility = () => {
      worker.postMessage({
        type: document.hidden ? "pause" : "resume"
      });
    };
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      document.removeEventListener("visibilitychange", onVisibility);
      worker.terminate();
    };
  }, []);

  // ── Physical keyboard ────────────────────────────────────────────────
  // Only when mounted with keyboard={true}, i.e. from docs/index.html's #play
  // page. The standalone app (docs/app/) is a phone app and doesn't even load
  // keyboard-map.js, hence the typeof guard.
  //
  // Focus-scoped: the #play page is a long article with module/preset pickers
  // and a file upload below the calculator, so keys are only claimed while the
  // calculator itself has focus. That also keeps Tab working as Tab — a page
  // you can't tab out of is a keyboard trap.
  const rootRef = usePlayRef(null);
  const heldRef = usePlayRef(null); // { row, col, at } while a single key is down
  const seqRef = usePlayRef(0); // bumped to supersede an in-flight 2nd sequence
  const [keyboardFocused, setKeyboardFocused] = usePlayState(false);
  const [typedKey, setTypedKey] = usePlayState(null); // "row,col" of the lit key

  const releaseHeld = usePlayCallback(() => {
    const held = heldRef.current;
    if (!held) return;
    heldRef.current = null;
    setTypedKey(null);
    const send = () => workerRef.current?.postMessage({
      type: "release",
      row: held.row,
      col: held.col
    });
    // Releasing sooner than the hold window would let the ROM throw the key away
    // as bounce, which is exactly what fast typing produces.
    const remaining = PLAY_KEY_HOLD_MS - (Date.now() - held.at);
    if (remaining > 0) setTimeout(send, remaining);else send();
  }, []);

  // ── On-screen key clicks/taps ────────────────────────────────────────
  // Tied to the real pointer down/up (via <CalcKey>'s onDown/onUp), sharing
  // heldRef/releaseHeld with the physical keyboard above, instead of a fixed
  // synthetic hold measured from onClick. The previous approach sent an
  // independent, uncoordinated release timer per click; mashing a key — what
  // a user does exactly when a press seems to not register (e.g. R/S during
  // a slow "2nd List" output) — queued overlapping stale releases that could
  // clip a later click's hold short before the ROM's debounce window
  // elapsed. Tying release to the real pointer-up removes that race; the
  // minimum hold in releaseHeld() still applies if the real press was
  // shorter than the ROM needs.
  const pointerDown = usePlayCallback((row, col) => {
    const held = heldRef.current;
    if (held && held.row === row && held.col === col) return; // already down
    seqRef.current++; // supersede any running 2nd-prefixed keyboard sequence
    releaseHeld(); // one key at a time — release whatever else was held
    heldRef.current = {
      row,
      col,
      at: Date.now()
    };
    setTypedKey(`${row},${col}`);
    workerRef.current?.postMessage({
      type: "press",
      row,
      col
    });
  }, [releaseHeld]);
  const pointerUp = usePlayCallback((row, col) => {
    const held = heldRef.current;
    if (!held || held.row !== row || held.col !== col) return; // not the held key
    releaseHeld();
  }, [releaseHeld]);

  // <CalcKey> (from docs/Calculator.jsx) calls onDown(label)/onUp(label);
  // resolve the label back to its grid position via CALC_ROWS. Every label
  // is unique. Stable identity (useCallback) so MemoCalcKey's memoization
  // holds.
  const pointerDownByLabel = usePlayCallback(label => {
    for (let ri = 0; ri < CALC_ROWS.length; ri++) {
      const ci = CALC_ROWS[ri].findIndex(kc => kc.label === label);
      if (ci !== -1) {
        pointerDown(ri, ci);
        return;
      }
    }
  }, [pointerDown]);
  const pointerUpByLabel = usePlayCallback(label => {
    for (let ri = 0; ri < CALC_ROWS.length; ri++) {
      const ci = CALC_ROWS[ri].findIndex(kc => kc.label === label);
      if (ci !== -1) {
        pointerUp(ri, ci);
        return;
      }
    }
  }, [pointerUp]);

  // A 2nd-prefixed binding (Shift+A for A', say) is one logical action played
  // back as two full taps: the ROM has to see 2nd released and re-scanned before
  // it will accept the second key, so they cannot be sent together.
  const playSequence = usePlayCallback(async codes => {
    const generation = ++seqRef.current;
    for (const code of codes) {
      if (generation !== seqRef.current) return; // superseded by a newer key
      const row = Math.floor(code / 10) - 1;
      const col = code % 10 - 1;
      setTypedKey(`${row},${col}`);
      workerRef.current?.postMessage({
        type: "press",
        row,
        col
      });
      await new Promise(r => setTimeout(r, PLAY_KEY_HOLD_MS));
      // Always paired with its own press, even once superseded — an unmatched
      // press would leave the matrix bit stuck set in the core.
      workerRef.current?.postMessage({
        type: "release",
        row,
        col
      });
      await new Promise(r => setTimeout(r, PLAY_KEY_GAP_MS));
    }
    if (generation === seqRef.current) setTypedKey(null);
  }, []);
  const handleKeyDown = usePlayCallback(e => {
    // e.repeat: the matrix bit is a level, not an event — a held key can never
    // re-trigger, so auto-repeat would only produce spurious releases.
    if (!keyboard || e.repeat || typeof ti59KeyboardMatrixCodes !== "function") return;
    const codes = ti59KeyboardMatrixCodes(e);
    if (!codes) return;
    // Space would scroll, Backspace could navigate, "/" opens quick-find.
    e.preventDefault();
    seqRef.current++; // supersede any running sequence
    releaseHeld(); // the hardware rejects chords: one key at a time

    if (codes.length > 1) {
      playSequence(codes);
      return;
    }
    const row = Math.floor(codes[0] / 10) - 1;
    const col = codes[0] % 10 - 1;
    heldRef.current = {
      row,
      col,
      at: Date.now()
    };
    setTypedKey(`${row},${col}`);
    workerRef.current?.postMessage({
      type: "press",
      row,
      col
    });
  }, [keyboard, releaseHeld, playSequence]);
  const handleKeyUp = usePlayCallback(e => {
    if (!keyboard || typeof ti59KeyboardMatrixCodes !== "function") return;
    if (!ti59KeyboardMatrixCodes(e)) return;
    e.preventDefault();
    releaseHeld();
  }, [keyboard, releaseHeld]);
  function handleModuleChange(id) {
    // No "Loading module…" status: switching modules is a single fast
    // in-memory swap (well under 100ms), and the message had no message
    // to clear it on completion — it just stuck around forever. Not worth
    // a transient status for something this quick.
    setPresetCueCard(null);
    workerRef.current?.postMessage({
      type: "loadModule",
      id
    });
  }
  function loadPresetText(text) {
    setStatusMessage("Loading program…");
    setPresetCueCard(null);
    workerRef.current?.postMessage({
      type: "loadState",
      text
    });
  }
  function handlePresetChange(file) {
    if (!file) return;
    fetch(`/presets/${file}`).then(r => r.text()).then(loadPresetText);
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
  return /*#__PURE__*/React.createElement("div", {
    className: "calcu-device",
    ref: rootRef,
    tabIndex: keyboard ? 0 : undefined,
    onKeyDown: keyboard ? handleKeyDown : undefined,
    onKeyUp: keyboard ? handleKeyUp : undefined
    // React's onFocus/onBlur are focusin/focusout, so they still fire when the
    // focus lands on one of the inner key <button>s.
    ,
    onFocus: keyboard ? () => setKeyboardFocused(true) : undefined,
    onBlur: keyboard ? () => {
      setKeyboardFocused(false);
      seqRef.current++;
      releaseHeld();
    } : undefined
    // preventScroll matters: without it, focusing on pointer-down scrolls the
    // calculator into view mid-click, which moves the key out from under the
    // pointer before the click completes.
    ,
    onPointerDown: keyboard ? () => rootRef.current?.focus({
      preventScroll: true
    }) : undefined,
    style: {
      width: `${360 * scale}px`,
      background: "#000",
      padding: `${10 * scale}px ${12 * scale}px ${8 * scale}px`,
      fontFamily: "var(--font-keycap)",
      userSelect: "none",
      // Always reserve the ring's space so focusing doesn't shift the layout.
      outline: `2px solid ${keyboardFocused ? "rgba(240,192,64,.55)" : "transparent"}`,
      outlineOffset: 2,
      borderRadius: 6
    }
  }, /*#__PURE__*/React.createElement(PlayDisplay, {
    scale: scale,
    snap: display,
    moduleName: currentModule ? currentModule.menuTitle : "",
    statusMessage: statusMessage
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 3 * scale,
      minHeight: 70 * scale
    }
  }, activeCueCard ? /*#__PURE__*/React.createElement(CueCard, {
    card: activeCueCard,
    scale: scale
  }) : null), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "grid",
      gap: 10 * scale,
      marginTop: 6 * scale
    }
  }, CALC_ROWS.map((row, ri) => /*#__PURE__*/React.createElement("div", {
    key: ri,
    style: {
      display: "grid",
      gridTemplateColumns: "repeat(5, 1fr)",
      gap: 8 * scale
    }
  }, row.map((kc, ci) => /*#__PURE__*/React.createElement(MemoCalcKey, {
    key: ci,
    kc: kc,
    scale: scale,
    onDown: pointerDownByLabel,
    onUp: pointerUpByLabel,
    forcePressed: typedKey === `${ri},${ci}`
  }))))), keyboard && !keyboardFocused ? /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 8 * scale,
      fontFamily: "var(--font-body)",
      fontSize: 11 * scale,
      color: "var(--fg-3)",
      textAlign: "center"
    }
  }, "Click the calculator to type on it with your keyboard.") : null, controls ? /*#__PURE__*/React.createElement(PlayControls, {
    scale: scale,
    modules: modules,
    presets: presets,
    currentModuleId: currentModule ? currentModule.id : "",
    onModuleChange: handleModuleChange,
    onPresetChange: handlePresetChange,
    onUpload: handleUpload,
    onQueueCard: () => workerRef.current?.postMessage({
      type: "queueCard"
    }),
    disabled: !ready
  }) : null);
}
function PlayDisplay({
  scale,
  snap,
  moduleName,
  statusMessage
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      background: "linear-gradient(180deg, var(--display-bezel-2) 0%, var(--display-bezel) 50%, var(--display-bezel-2) 100%)",
      borderRadius: 10 * scale,
      padding: `${10 * scale}px ${10 * scale}px ${6 * scale}px`,
      border: "1px solid #3a2418",
      boxShadow: "0 1px 0 rgba(255,200,100,.04), inset 0 0 0 1px rgba(0,0,0,.4)",
      position: "relative"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      background: "#0a0302",
      borderRadius: 4 * scale,
      padding: `${10 * scale}px ${12 * scale}px ${4 * scale}px`,
      position: "relative",
      boxShadow: "inset 0 2px 8px rgba(0,0,0,.8)",
      overflow: "hidden"
    }
  }, /*#__PURE__*/React.createElement(LedDisplayCanvas, {
    scale: scale,
    snap: snap
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      justifyContent: "space-between",
      alignItems: "center",
      padding: `${8 * scale}px 2px ${2 * scale}px`,
      color: "#c89858",
      fontFamily: "var(--font-keycap)",
      fontWeight: 700,
      fontSize: 11 * scale,
      letterSpacing: ".05em",
      minHeight: 16 * scale
    }
  }, /*#__PURE__*/React.createElement("span", null, moduleName || " "), /*#__PURE__*/React.createElement("span", null, statusMessage)));
}
function PlayControls({
  scale,
  modules,
  presets,
  currentModuleId,
  onModuleChange,
  onPresetChange,
  onUpload,
  onQueueCard,
  disabled
}) {
  const fileInputRef = usePlayRef(null);
  const selectStyle = {
    background: "var(--bg-inset)",
    color: "var(--fg)",
    border: "1px solid var(--stroke)",
    borderRadius: 6 * scale,
    padding: `${6 * scale}px ${8 * scale}px`,
    fontFamily: "var(--font-body)",
    fontSize: 13 * scale
  };
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "grid",
      gap: 8 * scale,
      marginTop: 16 * scale,
      paddingTop: 12 * scale,
      borderTop: "1px solid rgba(255,255,255,.08)"
    }
  }, /*#__PURE__*/React.createElement("label", {
    style: {
      display: "grid",
      gap: 4,
      fontSize: 11 * scale,
      color: "var(--fg-3)"
    }
  }, "Solid state module", /*#__PURE__*/React.createElement("select", {
    style: selectStyle,
    value: currentModuleId,
    disabled: disabled,
    onChange: e => onModuleChange(e.target.value)
  }, modules.map(m => /*#__PURE__*/React.createElement("option", {
    key: m.id,
    value: m.id
  }, m.menuTitle)))), /*#__PURE__*/React.createElement("label", {
    style: {
      display: "grid",
      gap: 4,
      fontSize: 11 * scale,
      color: "var(--fg-3)"
    }
  }, "Load a preset program", /*#__PURE__*/React.createElement("select", {
    style: selectStyle,
    defaultValue: "",
    disabled: disabled,
    onChange: e => {
      onPresetChange(e.target.value);
      e.target.value = "";
    }
  }, /*#__PURE__*/React.createElement("option", {
    value: "",
    disabled: true
  }, "Choose a preset\u2026"), presets.map(p => /*#__PURE__*/React.createElement("option", {
    key: p.file,
    value: p.file
  }, p.title)))), /*#__PURE__*/React.createElement("button", {
    type: "button",
    disabled: disabled,
    onClick: onQueueCard,
    title: "Feeds a virtual magnetic card to 2nd Write / 2nd Read \u2014 same card every time, so writing then reading it back reproduces what was last written.",
    style: {
      ...selectStyle,
      cursor: disabled ? "default" : "pointer"
    }
  }, "Queue Card"), /*#__PURE__*/React.createElement("button", {
    type: "button",
    disabled: disabled,
    onClick: () => fileInputRef.current && fileInputRef.current.click(),
    style: {
      ...selectStyle,
      cursor: disabled ? "default" : "pointer"
    }
  }, "Upload your own .ti59 file\u2026"), /*#__PURE__*/React.createElement("input", {
    ref: fileInputRef,
    type: "file",
    accept: ".ti59,.ti58,.ti58c",
    style: {
      display: "none"
    },
    onChange: onUpload
  }));
}
Object.assign(window, {
  PlayCalculator
});