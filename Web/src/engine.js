// The engine: owns calc-engine-worker.js (the WASM SessionController) and
// keeps what it posts in a small store the components subscribe to — the
// web's Qt6/app/EmulatorController. Display frames bypass the store: the
// LED canvas repaints from `frames`, once per animation frame, without a
// React render. Settings and the
// TI-58C constant memory the worker asks to keep go to localStorage.
// Created in an effect only (the website prerenders without a Worker).

// The directory calc.js was loaded from: the worker, the engine, the
// artwork and the presets sit beside it, wherever the client is hosted.
// Captured while the script runs (document.currentScript is null
// afterwards); without one — a server-side prerender — relative to the page,
// which a render never uses.
const CALC_BASE = (() => {
  const script = typeof document !== "undefined" ? document.currentScript : null;
  if (script && script.src) return new URL(".", script.src).href;
  return typeof location !== "undefined" ? new URL(".", location.href).href : "";
})();

const STORAGE_PREFIX = "calcu59/";

function storageGet(key) {
  try { return window.localStorage.getItem(STORAGE_PREFIX + key); } catch (e) { return null; }
}

function storageSet(key, value) {
  try { window.localStorage.setItem(STORAGE_PREFIX + key, value); } catch (e) { /* private mode */ }
}

function storedSettings() {
  const out = {};
  try {
    const ls = window.localStorage;
    for (let i = 0; i < ls.length; i++) {
      const k = ls.key(i);
      if (k && k.startsWith(STORAGE_PREFIX)) out[k.slice(STORAGE_PREFIX.length)] = ls.getItem(k);
    }
  } catch (e) { /* private mode: defaults */ }
  return out;
}

function downloadBytes(name, bytes) {
  const url = URL.createObjectURL(new Blob([bytes], { type: "application/octet-stream" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

const INITIAL_STATE = {
  data: null,          // staticData(): models, modules, layout, printer, heatmap
  status: "Starting the emulator…",
  model: null,         // {model, moduleID}
  cueCard: null,       // draw list (bindings.cpp cueCard())
  runState: { frozen: false, owner: null, pcArmed: false, scanArmed: false, fullSpeed: false, heldKey: -1, asmActive: false },
  printer: { lines: [], connected: false, trace: false, heightUnits: 0, copyPixelsPerUnit: 1 },
  card: { swiping: false, fileName: "card.U59", cards: [] },
  live: null,
  cpu: [],
  heatmap: null,
  log: { text: "", level: 0, trace: false },
  asm: { fileName: "", words: 0, status: "", active: false },
  traces: [],
  settings: { startupModel: -1, traceMaxMB: 50, keyboardFeedback: 0 },
  debugFont: 11,
  debugPanel: { panel: 0, n: 0 },  // KEYSTROKES DebugPanel: the tab asked for, and how often
  geometry: null,
};

function createEngine({ model, module }) {
  let state = INITIAL_STATE;
  const listeners = new Set();
  const frames = { cells: null, onFrame: null };
  let framePending = false;
  const stateLoadedWaiters = [];

  const set = (patch) => {
    state = { ...state, ...patch };
    listeners.forEach((l) => l());
  };

  const worker = new Worker(`${CALC_BASE}calc-engine-worker.js`);
  const post = (msg) => worker.postMessage(msg);

  worker.onmessage = (e) => {
    const m = e.data;
    switch (m.type) {
      case "ready": set({ data: m.data, status: "" }); break;
      case "display":
        frames.cells = m.cells;
        if (!framePending) {
          framePending = true;
          requestAnimationFrame(() => {
            framePending = false;
            if (frames.onFrame) frames.onFrame();
          });
        }
        break;
      case "model": set({ model: m.model }); break;
      case "cueCard": set({ cueCard: m.card }); break;
      case "runState": set({ runState: m.state }); break;
      case "printer": {
        const p = m.printer;
        const lines = state.printer.lines.slice(0, p.from).concat(p.lines);
        set({ printer: { ...p, lines } });
        break;
      }
      case "card": set({ card: m.card }); break;
      case "live": set({ live: m.live }); break;
      case "cpu": set({ cpu: m.rows }); break;
      case "heatmap": set({ heatmap: m.steps }); break;
      case "log": set({ log: m.log }); break;
      case "asm": set({ asm: m.asm }); break;
      case "traces": set({ traces: m.traces }); break;
      case "traceReady": post({ type: "traceBytes", name: m.name }); break;
      case "traceFile":
      case "cardFile":
        if (m.bytes) downloadBytes(m.name, m.bytes);
        break;
      case "settings": set({ settings: m.settings }); break;
      case "store": storageSet(m.key, m.value); break;
      case "debugFont": set({ debugFont: m.size }); break;
      case "debugPanel": set({ debugPanel: { panel: m.panel, n: state.debugPanel.n + 1 } }); break;
      case "geometry": set({ geometry: m.geometry }); break;
      case "stateLoaded": {
        set({ status: m.errors && m.errors.length ? m.errors.join("\n") : "" });
        const resolve = stateLoadedWaiters.shift();
        if (resolve) resolve(m.errors || []);
        break;
      }
      case "error": set({ status: m.message }); break;
      default: break;
    }
  };

  post({ type: "init", settings: storedSettings(), model: model || "", module: module || "" });

  const onVisibility = () => post({ type: document.hidden ? "pause" : "resume" });
  document.addEventListener("visibilitychange", onVisibility);

  return {
    frames,
    getState: () => state,
    subscribe: (l) => { listeners.add(l); return () => listeners.delete(l); },
    /// A WebController method (bindings.cpp).
    call: (method, ...args) => post({ type: "call", method, args }),
    post,
    /// A preset's text; resolves with its errors.
    loadState: (text) => new Promise((resolve) => {
      stateLoadedWaiters.push(resolve);
      post({ type: "loadState", text });
    }),
    setStatus: (status) => set({ status }),
    destroy: () => {
      document.removeEventListener("visibilitychange", onVisibility);
      worker.terminate();
    },
  };
}

// The engine's state for a component: the whole of it, or a slice.
const NO_ENGINE = { getState: () => INITIAL_STATE, subscribe: () => () => {} };
function useEngine(engine, select) {
  const e = engine || NO_ENGINE;
  return React.useSyncExternalStore(e.subscribe, () => select(e.getState()), () => select(INITIAL_STATE));
}

// Fetch a file next to calc.js (presets) as text.
function fetchBesideCalc(path) {
  return fetch(`${CALC_BASE}${path}`).then((r) => {
    if (!r.ok) throw new Error(`${path}: ${r.status}`);
    return r.text();
  });
}
