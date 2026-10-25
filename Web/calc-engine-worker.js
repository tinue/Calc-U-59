// Background Worker of the web client (src/engine.js starts it). It owns the
// WASM WebController (Web/bindings.cpp) — the real cu59::SessionController
// from Shared/, run single-threaded — and calls its 60 Hz tick. Everything
// that isn't drawing happens in there; this file only fetches files and
// passes messages. Every URL here is relative to this script, so the client
// works wherever it is hosted.
//
// Protocol (postMessage), main thread -> worker:
//   {type: "init", settings, model, module}   -- first message: stored settings
//        by key (strings), the host's model/module overrides ("" for none)
//   {type: "call", method, args}       -- a WebController method (bindings.cpp)
//   {type: "loadState", text}          -- a preset's contents -> stateLoaded
//   {type: "cardBytes", name}          -- -> {type: "cardFile", name, bytes}
//   {type: "traceBytes", name}         -- -> {type: "traceFile", name, bytes}
//   {type: "geometry", w, h}           -- LED shapes for a w × h digit cell
//   {type: "pause"} / {type: "resume"} -- document.visibilitychange
//
// worker -> main thread:
//   {type: "ready", data}              -- staticData(): models, modules, layout,
//                                         printer geometry and font, heatmap
//   {type: "stateLoaded", errors}
//   {type: "geometry", geometry}
//   {type: "cardFile" | "traceFile", name, bytes}
//   and what WebController posts on its own (bindings.cpp drain()):
//   model, display, cueCard, runState, printer, card, live, cpu, heatmap,
//   log, asm, traces, traceReady, settings, store, debugFont, error.

importScripts("wasm/ti59-core.js");

const FRAME_MS = 1000 / 60;

let Module = null;
let controller = null;
let intervalId = null;
const pending = [];

// SessionController reads files synchronously; the start-up set is fetched
// ahead (init), any other — a module chosen later, another model's ROM —
// through this, a synchronous request (allowed in a worker). Offline in the
// installed app only what the service worker precached is there; another
// module then fails to load and is reported.
self.readRomFile = (name) => {
  try {
    const xhr = new XMLHttpRequest();
    xhr.open("GET", `wasm/roms/${name}`, false);
    xhr.send();
    return xhr.status === 200 ? xhr.responseText : null;
  } catch (e) {
    return null;
  }
};

function fetchText(name) {
  return fetch(`wasm/roms/${name}`).then((r) => {
    if (!r.ok) throw new Error(`${name}: ${r.status}`);
    return r.text();
  });
}

async function fetchFiles(names) {
  const texts = await Promise.all(names.map(fetchText));
  const files = {};
  names.forEach((n, i) => { files[n] = texts[i]; });
  return files;
}

function startLoop() {
  if (intervalId === null) intervalId = setInterval(() => controller.tick(), FRAME_MS);
}

function stopLoop() {
  if (intervalId === null) return;
  clearInterval(intervalId);
  intervalId = null;
}

function handle(msg) {
  switch (msg.type) {
    case "call": controller[msg.method](...(msg.args || [])); break;
    case "loadState": {
      const errors = controller.loadState(new TextEncoder().encode(msg.text));
      postMessage({ type: "stateLoaded", errors });
      break;
    }
    case "cardBytes":
      postMessage({ type: "cardFile", name: msg.name, bytes: controller.cardBytes(msg.name) });
      break;
    case "traceBytes":
      postMessage({ type: "traceFile", name: msg.name, bytes: controller.traceBytes(msg.name) });
      break;
    case "geometry":
      postMessage({ type: "geometry", geometry: Module.ledGeometry(msg.w, msg.h) });
      break;
    case "pause": controller.suspend(); stopLoop(); break;
    case "resume": controller.resume(); startLoop(); break;
    default: break;
  }
}

async function init({ settings, model, module }) {
  // ti59-core.js resolves its .wasm next to this worker, not next to itself
  // (wasm/): locateFile points it back.
  const [mod, cuecards] = await Promise.all([
    createTI59CoreModule({ locateFile: (path) => `wasm/${path}` }),
    fetchText("cuecards.txt"),
  ]);
  Module = mod;
  const plan = Module.startupPlan(settings, model || "", module || "", cuecards);
  const files = await fetchFiles(plan.files);
  files["cuecards.txt"] = cuecards;
  postMessage({ type: "ready", data: Module.staticData(cuecards) });
  controller = new Module.WebController(files, settings, plan.model, plan.moduleID);

  startLoop();
  while (pending.length) handle(pending.shift());
}

onmessage = (e) => {
  if (e.data.type === "init") {
    init(e.data).catch((err) => postMessage({ type: "error", message: String(err && err.message || err) }));
  } else if (!controller) {
    pending.push(e.data);
  } else {
    handle(e.data);
  }
};
