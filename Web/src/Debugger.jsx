// The debugger panel, wide layout only (Qt6/app/debug/, App/Views/DebugView):
// tabs CALCULATOR / CPU / LOG. Only the visible tab's snapshots are built
// (setLiveDebugEnabled / setCpuDebugEnabled follow it). Rows arrive
// formatted by Shared/DebugText (bindings.cpp postLive / postCpu); this
// draws them with the panels' dimming and colours.

const STEP_REPEAT_MS = 250;
const CURRENT_PC_RGB = [52, 199, 89];

const grey = (white) => `rgba(255,255,255,${white})`;

function Section({ title, extra, children }) {
  return (
    <div className="calcu-section">
      <div className="calcu-section-head"><span>{title}</span>{extra}</div>
      {children !== undefined && <div className="calcu-section-body">{children}</div>}
    </div>
  );
}

const Run = ({ white = 0.85, color, children }) => <span style={{ color: color || grey(white) }}>{children}</span>;
const Gap = () => <span>{"   "}</span>;

/// Fires at once, then every 250 ms while held (Qt6/app/HoldRepeatButton).
function RepeatButton({ onFire, disabled, children, className }) {
  const timer = React.useRef(null);
  const stop = () => { clearInterval(timer.current); timer.current = null; };
  React.useEffect(() => stop, []);
  React.useEffect(() => { if (disabled) stop(); }, [disabled]);
  return (
    <button type="button" className={className} disabled={disabled}
      onPointerDown={() => { onFire(); stop(); timer.current = setInterval(onFire, STEP_REPEAT_MS); }}
      onPointerUp={stop} onPointerLeave={stop} onPointerCancel={stop}
      onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); if (!e.repeat) onFire(); } }}
    >{children}</button>
  );
}

/// RESUME / FREEZE / FREEZE ON START / ARMED / STEP for one owner.
function FreezeHeader({ engine, title, narrowTitle, cpu, narrow }) {
  const rs = useEngine(engine, (s) => s.runState);
  const owner = cpu ? "cpu" : "calculator";
  const armed = cpu ? rs.scanArmed : rs.pcArmed;
  const owned = rs.frozen && rs.owner === owner;
  const canFreeze = !rs.frozen && !armed;
  return (
    <div className="calcu-debug-header">
      <span className="calcu-debug-title">{narrow ? narrowTitle : title}</span>
      <button type="button" className="calcu-hb calcu-hb-orange" disabled={!owned}
        onClick={() => engine.call("resumeFrozen")}>RESUME</button>
      <button type="button" className="calcu-hb" disabled={!canFreeze}
        onClick={() => engine.call("freeze", cpu)}>FREEZE</button>
      <button type="button" className="calcu-hb" disabled={!canFreeze}
        onClick={() => engine.call(cpu ? "armScanLoopExit" : "armPcChange")}>{narrow ? "F.START" : "FREEZE ON START"}</button>
      <button type="button" className="calcu-hb calcu-hb-yellow" disabled={!armed}
        onClick={() => engine.call(cpu ? "disarmScanLoopExit" : "disarmPcChange")}>ARMED</button>
      <RepeatButton className="calcu-hb calcu-hb-blue" disabled={!owned}
        onFire={() => engine.call(cpu ? "stepInstruction" : "stepKeycode")}>STEP</RepeatButton>
    </div>
  );
}

/// A list that keeps one row in view (centred, or at the bottom while running).
function useScrollTo(ref, index, mode, deps) {
  React.useLayoutEffect(() => {
    const list = ref.current;
    if (!list || index < 0 || !list.children[index]) return;
    const row = list.children[index];
    if (mode === "bottom") list.scrollTop = list.scrollHeight;
    else list.scrollTop = row.offsetTop - list.clientHeight / 2 + row.offsetHeight / 2;
  }, deps);
}

function LiveDebug({ engine, font, narrow }) {
  const s = useEngine(engine, (st) => st.live);
  const stepsRef = React.useRef(null);
  const current = s ? s.steps.findIndex((r) => r.current) : -1;
  useScrollTo(stepsRef, current, "center", [s]);
  const dim = (on) => (on ? 0.85 : 0.4);
  return (
    <div className="calcu-debug-tab" style={{ fontSize: font }}>
      <FreezeHeader engine={engine} title="CALCULATOR DEBUG" narrowTitle="DEBUG" narrow={narrow} />
      {s && <>
        <div className="calcu-debug-fixed">
          <Section title="DEBUG"><Run white={0.65}>{s.fA}</Run><Gap /><Run white={0.65}>{s.fB}</Run><Gap /><Run>{s.hir0}</Run></Section>
        </div>
        <div className="calcu-debug-scroll">
          <Section title="PARTITION"><Run white={0.75}>{s.partition}</Run></Section>
          <Section title={s.source} />
          <Section title="PROGRAM STEPS">
            <div className="calcu-steps" ref={stepsRef}>
              {s.steps.map((r, i) => (
                <div key={i} style={r.current ? { background: s.stepHighlight, color: "#fff" } : { color: grey(0.6) }}>{r.text}</div>
              ))}
            </div>
          </Section>
          <Section title="">
            <Run>{s.fix}</Run><Gap /><Run white={s.angleKnown ? 0.85 : 0.4}>{s.angle}</Run><Gap />
            <Run white={dim(s.eng)}>Eng</Run><Gap /><Run white={dim(s.second)}>2nd</Run><Gap /><Run white={dim(s.inv)}>INV</Run>
          </Section>
          <Section title="RETURN ADDRESS">
            {[5, 4, 3].map((i) => <React.Fragment key={i}><Run color={s.returns[i].color}>{s.returns[i].text}</Run><Gap /></React.Fragment>)}
            <br />
            {[2, 1, 0].map((i) => <React.Fragment key={i}><Run color={s.returns[i].color}>{s.returns[i].text}</Run><Gap /></React.Fragment>)}
          </Section>
          <Section title="FLAGS">
            {s.flags.map((on, i) => (
              <React.Fragment key={i}><Run white={on ? 0.85 : 0.6}>{`F${i}:${on ? 1 : 0}`}</Run>{i === 4 ? <br /> : <Gap />}</React.Fragment>
            ))}
          </Section>
          <Section title="HIR">
            {s.hir.map((h, i) => (
              <React.Fragment key={i}><Run white={h.zero ? 0.6 : 0.85}>{h.text}</Run>{i === 3 ? <br /> : <Gap />}</React.Fragment>
            ))}
          </Section>
          <Section title=""><Run color={s.xColor}>{s.x}</Run><Gap /><Run white={s.tZero ? 0.6 : 0.85}>{s.t}</Run></Section>
          <Section title="VARIABLES">
            {s.vars.length === 0
              ? <Run white={0.35}>(all zero)</Run>
              : s.vars.map((v, i) => <div key={i}><Run>{v}</Run></div>)}
          </Section>
        </div>
      </>}
    </div>
  );
}

function Heatmap({ engine, data, currentPC }) {
  const steps = useEngine(engine, (s) => s.heatmap);
  const ref = React.useRef(null);
  const [hover, setHover] = React.useState(-1);
  const { cols, rows, colors } = data.heatmap;

  React.useEffect(() => {
    const canvas = ref.current;
    canvas.width = cols;
    canvas.height = rows;
    const ctx = canvas.getContext("2d");
    const img = ctx.createImageData(cols, rows);
    const d = img.data;
    for (let i = 0; i < cols * rows; i++) {
      const c = currentPC === i ? CURRENT_PC_RGB : colors[steps ? steps[i] : 0];
      d[i * 4] = c[0];
      d[i * 4 + 1] = c[1];
      d[i * 4 + 2] = c[2];
      d[i * 4 + 3] = 255;
    }
    ctx.putImageData(img, 0, 0);
  }, [steps, currentPC]);

  const onMove = (e) => {
    const r = e.currentTarget.getBoundingClientRect();
    const x = Math.floor(((e.clientX - r.left) / r.width) * cols), y = Math.floor(((e.clientY - r.top) / r.height) * rows);
    setHover(x >= 0 && x < cols && y >= 0 && y < rows ? y * cols + x : -1);
  };
  const hex = (a) => "0x" + a.toString(16).toUpperCase().padStart(4, "0");
  return (
    <Section title="ROM HEATMAP" extra={<span className="calcu-section-extra">
      <span className="calcu-hover">{hover >= 0 ? hex(hover) : ""}</span>
      <button type="button" className="calcu-clr" onClick={() => engine.call("clearHeatmap")}>CLR</button>
    </span>}>
      <canvas ref={ref} className="calcu-heatmap" style={{ aspectRatio: `${cols} / ${rows}` }}
        onPointerMove={onMove} onPointerLeave={() => setHover(-1)} />
    </Section>
  );
}

function AsmOverlay({ engine }) {
  const asm = useEngine(engine, (s) => s.asm);
  const select = (e) => readFileInput(e, "text").then((f) => { if (f) engine.call("loadAsm", f.content, f.name); });
  return (
    <Section title="ASM OVERLAY">
      <div>File: {asm.fileName}</div>
      <div>Words: {asm.words}</div>
      <div>Status: {asm.status}</div>
      <div className="calcu-buttonrow">
        <label className="calcu-pill calcu-filebutton-inline">Select File<input type="file" onChange={select} /></label>
        <button type="button" className="calcu-pill" disabled={asm.words === 0} onClick={() => engine.call("runAsm")}>Run</button>
        <button type="button" className="calcu-pill" onClick={() => engine.call("clearAsm")}>Clear</button>
      </div>
    </Section>
  );
}

function CpuInspector({ engine, data, font, narrow }) {
  const rows = useEngine(engine, (s) => s.cpu);
  const frozen = useEngine(engine, (s) => s.runState.frozen);
  const [picked, setPicked] = React.useState(-1);
  const listRef = React.useRef(null);
  const current = rows.findIndex((r) => r.current);
  // Running: follow the newest; frozen: the current instruction, unless one was picked.
  const auto = frozen ? current : rows.length - 1;
  React.useEffect(() => setPicked(-1), [frozen]);
  const selected = frozen && picked >= 0 && picked < rows.length ? picked : auto;
  useScrollTo(listRef, selected, frozen ? "center" : "bottom", [rows]);
  // Running, only the newest row carries registers (bindings.cpp postCpu).
  const f = rows[selected] && rows[selected].registers ? rows[selected] : undefined;
  const value = grey(0.85);
  return (
    <div className="calcu-debug-tab" style={{ fontSize: font }}>
      <FreezeHeader engine={engine} title="CPU DEBUG" narrowTitle="CPU" cpu={true} narrow={narrow} />
      <div className="calcu-cpu-list" ref={listRef}>
        {rows.map((r, i) => (
          <div key={i} onClick={() => setPicked(i)}
            className={i === selected ? "calcu-cpu-selected" : ""}
            style={{ color: `rgba(255,255,255,${r.history ? 0.9 : 0.35})`, background: r.current ? "rgba(52,199,89,0.35)" : undefined }}>
            {r.text}
          </div>
        ))}
      </div>
      <div className="calcu-debug-scroll">
        <Section title="REGISTERS">
          {f && f.registers.map(([n, v]) => <div key={n}><b style={{ color: grey(0.6) }}>{n}</b> <Run>{v}</Run></div>)}
        </Section>
        <Section title="CONTROL REGISTERS">
          {f && <>
            <div style={{ color: value }}>{f.KR}</div>
            <div style={{ color: value }}>{f.fA}</div>
            <div style={{ color: value }}>{f.fB}</div>
            <div><Run>{f.SR}</Run><Gap /><Run>{f.R5}</Run></div>
            <div>
              <Run color={f.cond ? "rgba(255,204,0,0.4)" : "#ffcc00"}>{`COND: ${f.cond ? 1 : 0}`}</Run><Gap />
              <Run color={f.idle ? "#fff" : grey(0.45)}>{`IDLE: ${f.idle ? 1 : 0}`}</Run><Gap />
              <Run>{f.digit}</Run>
            </div>
          </>}
        </Section>
        <Section title="DISPLAY STATE">
          {f && <><Run>{f.lit}</Run><Gap />
            <Run color={f.displayOn ? "rgba(52,199,89,0.85)" : "rgba(255,59,48,0.7)"}>{f.displayOn ? "ON" : "OFF"}</Run></>}
        </Section>
        <Heatmap engine={engine} data={data} currentPC={current >= 0 ? rows[current].pc : -1} />
        <AsmOverlay engine={engine} />
      </div>
    </div>
  );
}

function LogTab({ engine }) {
  const log = useEngine(engine, (s) => s.log);
  const traces = useEngine(engine, (s) => s.traces);
  const ref = React.useRef(null);
  React.useLayoutEffect(() => { ref.current.scrollTop = ref.current.scrollHeight; }, [log.text]);
  const levels = ["LOG ○", "LOG ●", "LOG ●"];
  const mb = (n) => (n / 1e6).toFixed(n < 1e5 ? 2 : 1) + " MB";
  return (
    <div className="calcu-debug-tab">
      <div className="calcu-debug-header calcu-center"><span className="calcu-debug-title">DEBUG LOG</span></div>
      <textarea className="calcu-log" ref={ref} readOnly value={log.text} aria-label="Debug log" />
      <div className="calcu-log-bar">
        <div className="calcu-buttonrow">
          {[["SCOM", "dumpScom"], ["Memory", "dumpMemory"], ["Prog", "dumpProg"], ["Vars", "dumpVars"]].map(([label, fn]) => (
            <button key={fn} type="button" className="calcu-pill" onClick={() => engine.call(fn)}>{label}</button>
          ))}
          <span className="calcu-spacer" />
          <button type="button" className="calcu-pill" title="Clear the log" aria-label="Clear the log" disabled={!log.text}
            onClick={() => engine.call("clearLog")}>🗑</button>
        </div>
        <div className="calcu-buttonrow">
          <button type="button" className="calcu-pill" aria-pressed={log.trace}
            title="Write every executed instruction to the binary trace file (downloaded when switched off)"
            style={log.trace ? { color: "orange" } : undefined}
            onClick={() => engine.call("setManualTrace", !log.trace)}>{log.trace ? "TRACE ●" : "TRACE ○"}</button>
          <button type="button" className="calcu-pill" title="Core log level: off / info / debug"
            style={log.level ? { color: log.level === 1 ? "orange" : "#ff3b30" } : undefined}
            onClick={() => engine.call("cycleDebugLevel")}>{levels[log.level]}</button>
        </div>
        {traces.length > 0 && (
          <div className="calcu-traces" aria-label="Trace files">
            {traces.map((t) => (
              <button key={t.name} type="button" className="calcu-link" title={`Download ${t.name}`}
                onClick={() => engine.post({ type: "traceBytes", name: t.name })}>⤓ {t.name} ({mb(t.size)})</button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function Debugger({ engine }) {
  const data = useEngine(engine, (s) => s.data);
  const asmActive = useEngine(engine, (s) => s.runState.asmActive);
  const font = useEngine(engine, (s) => s.debugFont);
  const panelRequest = useEngine(engine, (s) => s.debugPanel);
  const [tab, setTab] = React.useState(panelRequest.panel);
  React.useEffect(() => { if (panelRequest.n) setTab(panelRequest.panel); }, [panelRequest]);
  const rootRef = React.useRef(null);
  const shown = asmActive && tab === 0 ? 1 : tab;  // the overlay runs on the CPU tab

  React.useEffect(() => {
    if (!data) return undefined;
    engine.call("setLiveDebugEnabled", shown === 0);
    engine.call("setCpuDebugEnabled", shown === 1);
    return undefined;
  }, [engine, data, shown]);
  React.useEffect(() => () => {
    if (!engine) return;
    engine.call("setLiveDebugEnabled", false);
    engine.call("setCpuDebugEnabled", false);
  }, [engine]);

  React.useEffect(() => {
    const el = rootRef.current;
    if (!engine || !data) return undefined;
    const ro = new ResizeObserver(() => engine.call("setDebugWidth", el.clientWidth));
    ro.observe(el);
    return () => ro.disconnect();
  }, [engine, data]);

  const narrow = font < 13;
  return (
    <div className="calcu-debugger" data-panel="debug" ref={rootRef}>
      <div className="calcu-tabs" role="tablist">
        {["CALCULATOR", "CPU", "LOG"].map((t, i) => (
          <button key={t} type="button" role="tab" aria-selected={shown === i} disabled={i === 0 && asmActive}
            onClick={() => setTab(i)}>{t}</button>
        ))}
      </div>
      {data && shown === 0 && <LiveDebug engine={engine} font={font + 2} narrow={narrow} />}
      {data && shown === 1 && <CpuInspector engine={engine} data={data} font={font + 2} narrow={narrow} />}
      {data && shown === 2 && <LogTab engine={engine} />}
    </div>
  );
}
