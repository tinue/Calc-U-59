// The calculator's dialogs, drawn inside the client (an embedding page has
// no window of ours to open): the card picker (Qt6/app/CardPickerDialog,
// over the page session's card folder), the preset picker (bundled presets
// and file upload), Settings (Qt6/app/SettingsDialog, App/Views/
// SettingsView) and About.

const CALC_VERSION = "__CALC_VERSION__";
const HELP_URL = "https://calc-u.org/59/";

function Dialog({ title, onClose, children, footer }) {
  React.useEffect(() => {
    const onKey = (e) => { if (e.key === "Escape") { e.stopPropagation(); onClose(); } };
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [onClose]);
  return (
    <div className="calcu-modal" onPointerDown={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="calcu-dialog" role="dialog" aria-label={title}>
        <div className="calcu-dialog-title">{title}</div>
        <div className="calcu-dialog-body">{children}</div>
        {footer && <div className="calcu-dialog-footer">{footer}</div>}
      </div>
    </div>
  );
}

function readFileInput(e, as) {
  const file = e.target.files && e.target.files[0];
  e.target.value = "";
  if (!file) return Promise.resolve(null);
  return (as === "text" ? file.text() : file.arrayBuffer().then((b) => new Uint8Array(b)))
    .then((content) => ({ name: file.name, content }));
}

// ── Cards ───────────────────────────────────────────────────────────────────

function CardPicker({ engine, mode, onClose }) {
  const card = useEngine(engine, (s) => s.card);
  const [selected, setSelected] = React.useState(null);
  const [name, setName] = React.useState(card.fileName);
  const save = mode === "save";

  const read = (n) => { engine.call("insertCard", n, null); onClose(); };
  const upload = (e) => readFileInput(e, "bytes").then((f) => {
    if (!f) return;
    engine.call("insertCard", f.name, f.content);
    onClose();
  });
  const write = () => { engine.call("insertBlankCard", name.trim()); onClose(); };

  return (
    <Dialog
      title={save ? "Write Blank Card" : "Read Card"}
      onClose={onClose}
      footer={<>
        <span className="calcu-dialog-note">Cards last for this page session — download one to keep it.</span>
        <button type="button" onClick={onClose}>Cancel</button>
        {save
          ? <button type="button" className="calcu-primary" disabled={!name.trim()} onClick={write}>Save</button>
          : <button type="button" className="calcu-primary" disabled={!selected} onClick={() => read(selected)}>Read</button>}
      </>}
    >
      {save && (
        <input
          className="calcu-textfield"
          aria-label="Card name"
          value={name}
          autoFocus
          onChange={(e) => setName(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter" && name.trim()) write(); }}
        />
      )}
      <ul className="calcu-list" aria-label="Session cards">
        {card.cards.length === 0 && <li className="calcu-empty">{save ? "No existing cards" : "No cards in this session"}</li>}
        {card.cards.map((n) => (
          <li key={n} className={selected === n ? "calcu-selected" : ""}>
            <button
              type="button"
              className="calcu-listitem"
              onClick={() => { setSelected(n); if (save) setName(n); }}
              onDoubleClick={() => (save ? setName(n) : read(n))}
            >{n}</button>
            <button type="button" className="calcu-iconbutton" title={`Download ${n}`} aria-label={`Download ${n}`}
              onClick={() => engine.post({ type: "cardBytes", name: n })}>⤓</button>
          </li>
        ))}
      </ul>
      {!save && (
        <label className="calcu-filebutton">
          Upload card file…
          <input type="file" accept=".u59,.U59,.bin" onChange={upload} />
        </label>
      )}
    </Dialog>
  );
}

// ── Presets ─────────────────────────────────────────────────────────────────

function PresetPicker({ engine, onClose }) {
  const [presets, setPresets] = React.useState(null);
  React.useEffect(() => {
    fetchBesideCalc("presets/manifest.json").then((t) => setPresets(JSON.parse(t))).catch(() => setPresets([]));
  }, []);
  const pick = (file) => {
    onClose();
    fetchBesideCalc(`presets/${file}`).then((text) => engine.loadState(text))
      .catch((err) => engine.setStatus(String(err.message || err)));
  };
  const upload = (e) => readFileInput(e, "text").then((f) => {
    if (!f) return;
    onClose();
    engine.loadState(f.content);
  });
  return (
    <Dialog title="Load Preset" onClose={onClose}
      footer={<button type="button" onClick={onClose}>Cancel</button>}>
      <ul className="calcu-list" aria-label="Presets">
        {presets === null && <li className="calcu-empty">Loading…</li>}
        {(presets || []).map((p) => (
          <li key={p.file}>
            <button type="button" className="calcu-listitem" onClick={() => pick(p.file)}>
              {p.title}<span className="calcu-filename">{p.file}</span>
            </button>
          </li>
        ))}
      </ul>
      <label className="calcu-filebutton">
        Open file…
        <input type="file" accept=".ti59,.ti58,.ti58c" onChange={upload} />
      </label>
    </Dialog>
  );
}

// ── Settings ────────────────────────────────────────────────────────────────

function Settings({ engine, portrait, onClose, onAbout }) {
  const data = useEngine(engine, (s) => s.data);
  const model = useEngine(engine, (s) => s.model);
  const settings = useEngine(engine, (s) => s.settings);
  const [moduleID, setModuleID] = React.useState(model ? model.moduleID : "ML");
  const [traceMB, setTraceMB] = React.useState(settings.traceMaxMB);

  // The module applies when the dialog closes, as in both apps.
  const close = () => {
    if (model && moduleID !== model.moduleID) engine.call("changeModule", moduleID);
    const mb = Number(traceMB);
    if (!portrait && mb > 0 && mb !== settings.traceMaxMB) engine.call("setTraceMaxMB", mb);
    onClose();
  };
  return (
    <Dialog title="Settings" onClose={close}
      footer={<button type="button" className="calcu-primary" onClick={close}>Done</button>}>
      <div className="calcu-form">
        <label>Startup Calculator
          <select value={settings.startupModel} onChange={(e) => engine.call("setStartupModel", Number(e.target.value))}>
            <option value={-1}>Last Used</option>
            {(data ? data.models : []).map((m) => <option key={m.model} value={m.model}>{m.name}</option>)}
          </select>
        </label>
        <label>Solid State Module
          <select value={moduleID} onChange={(e) => setModuleID(e.target.value)}>
            {(data ? data.modules : []).map((m) => <option key={m.id} value={m.id}>{m.menuTitle}</option>)}
          </select>
        </label>
        {portrait && (
          <label>Keyboard Feedback
            <select value={settings.keyboardFeedback} onChange={(e) => engine.call("setKeyboardFeedback", Number(e.target.value))}>  {/* 0 off, 1 vibrate, 2 click */}
              <option value={0}>Off</option>
              <option value={1}>Vibrate</option>
              <option value={2}>Click Sound</option>
            </select>
          </label>
        )}
        {!portrait && (
          <label>Maximum Trace File Size (MB)
            <input type="number" min="1" max="1000" value={traceMB} onChange={(e) => setTraceMB(e.target.value)} />
          </label>
        )}
        <div className="calcu-form-row"><span>Version</span><span>{CALC_VERSION}</span></div>
        <div className="calcu-form-row">
          <a href={HELP_URL} target="_blank" rel="noopener">Calc-U-59 Help</a>
          <button type="button" className="calcu-link" onClick={onAbout}>About</button>
        </div>
      </div>
    </Dialog>
  );
}

function About({ onClose }) {
  return (
    <Dialog title="About Calc-U-59" onClose={onClose}
      footer={<button type="button" className="calcu-primary" onClick={onClose}>OK</button>}>
      <p>A TI-59, TI-58 and TI-58C emulator with the PC-100C printer.</p>
      <p>Version {CALC_VERSION}</p>
      <p><a href={HELP_URL} target="_blank" rel="noopener">calc-u.org/59</a></p>
    </Dialog>
  );
}

// Which dialog is open, and the element that draws it.
function DialogHost({ engine, dialog, setDialog, portrait }) {
  const close = () => setDialog(null);
  switch (dialog) {
    case "readCard": return <CardPicker engine={engine} mode="load" onClose={close} />;
    case "writeCard": return <CardPicker engine={engine} mode="save" onClose={close} />;
    case "preset": return <PresetPicker engine={engine} onClose={close} />;
    case "settings": return <Settings engine={engine} portrait={portrait} onClose={close} onAbout={() => setDialog("about")} />;
    case "about": return <About onClose={close} />;
    default: return null;
  }
}
