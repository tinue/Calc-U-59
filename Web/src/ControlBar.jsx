// The bar under the calculator (Qt6/app/ControlBar, CalculatorView's bar in
// the Swift app): Reset — Ctrl/⌘ held shows a red "Clean", a 1 s press on a
// touch screen does the same —, the model picker, the card reader buttons
// (TI-59: read / write a blank card, or Eject while one is in), Preset and
// the Settings gear. `compact` (portrait) shows icons only, as on iOS.

const CLEAN_RESET_HOLD_MS = 1000;

function useModifierHeld() {
  const [held, setHeld] = React.useState(false);
  React.useEffect(() => {
    const update = (e) => setHeld(e.ctrlKey || e.metaKey);
    const clear = () => setHeld(false);
    window.addEventListener("keydown", update);
    window.addEventListener("keyup", update);
    window.addEventListener("blur", clear);
    return () => {
      window.removeEventListener("keydown", update);
      window.removeEventListener("keyup", update);
      window.removeEventListener("blur", clear);
    };
  }, []);
  return held;
}

function BarButton({ icon, label, compact, title, className = "", ...rest }) {
  return (
    <button type="button" className={`calcu-barbutton ${className}`} title={title || label} aria-label={label} {...rest}>
      <span className="calcu-icon" aria-hidden="true">{icon}</span>
      {!compact && <span>{label}</span>}
    </button>
  );
}

function ResetButton({ engine, compact, feedback }) {
  const modifier = useModifierHeld();
  const [longPressed, setLongPressed] = React.useState(false);
  const timer = React.useRef(null);
  const consumed = React.useRef(false);
  const clean = modifier || longPressed;

  const down = (e) => {
    if (e.pointerType !== "touch") return;
    consumed.current = false;
    timer.current = setTimeout(() => {
      consumed.current = true;
      setLongPressed(true);
      feedback("clean");
      engine.call("cleanResetMachine");
    }, CLEAN_RESET_HOLD_MS);
  };
  const up = () => {
    clearTimeout(timer.current);
    setTimeout(() => setLongPressed(false), 300);
  };
  const click = (e) => {
    if (consumed.current) { consumed.current = false; return; }
    if (e.ctrlKey || e.metaKey) {
      feedback("clean");
      engine.call("cleanResetMachine");
    } else {
      feedback("reset");
      engine.call("resetMachine");
    }
  };
  return (
    <BarButton
      icon={clean ? "⊗" : "↺"}
      label={clean ? "Clean" : "Reset"}
      title={compact ? "Reset (hold: clean reset)" : "Reset (Ctrl/⌘: clean reset, wipes memory)"}
      compact={compact}
      className={clean ? "calcu-clean" : "calcu-reset"}
      onPointerDown={down}
      onPointerUp={up}
      onPointerLeave={up}
      onClick={click}
    />
  );
}

function ControlBar({ engine, compact, showSettings, onDialog, feedback }) {
  const data = useEngine(engine, (s) => s.data);
  const model = useEngine(engine, (s) => s.model);
  const swiping = useEngine(engine, (s) => s.card.swiping);
  const hasReader = model && model.hasCardReader;

  return (
    <div className="calcu-bar">
      <ResetButton engine={engine} compact={compact} feedback={feedback} />
      <select
        className="calcu-model"
        aria-label="Calculator model"
        value={model ? model.model : 0}
        disabled={!model}
        onChange={(e) => engine.call("startMachine", Number(e.target.value))}
      >
        {(data ? data.models : [{ model: 0, name: "TI-59" }]).map((m) => (
          <option key={m.model} value={m.model}>{m.name}</option>
        ))}
      </select>
      <span className="calcu-divider" />
      <span className="calcu-spacer" />
      {hasReader && !swiping && (
        <>
          <BarButton icon="⤓" label="Crd" title="Read a card" compact={compact} onClick={() => onDialog("readCard")} />
          <BarButton icon="＋" label="Crd" title="Write a blank card" compact={compact} onClick={() => onDialog("writeCard")} />
        </>
      )}
      {hasReader && swiping && (
        <BarButton icon="⏏" label="Eject Card" compact={compact} onClick={() => engine.call("ejectCard")} />
      )}
      <span className="calcu-divider" />
      <BarButton icon="▤" label="Preset" title="Load a preset (.ti59, .ti58, .ti58c)" compact={compact}
        onClick={() => onDialog("preset")} />
      {showSettings && (
        <BarButton icon="⚙" label="Settings" compact={true} onClick={() => onDialog("settings")} />
      )}
    </div>
  );
}
