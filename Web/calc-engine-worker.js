// Background Worker for the web calculator (PlayCalculator.jsx). It owns
// the WASM WebController (Web/bindings.cpp) — the real
// cu59::SessionController from the main repo's Shared/ layer, run
// single-threaded — and calls its 60 Hz tick. Everything that isn't drawing
// (pacing, key timing, presets, cue cards, the card reader) happens in there;
// this file only fetches files and passes messages. Every URL here is
// relative to this script, so the client works wherever it is hosted.
//
// Protocol (postMessage), main thread -> worker:
//   {type: "pointerDown", row, col}   -- on-screen key, 0-indexed grid position
//   {type: "pointerUp"}
//   {type: "keyDown", key, produced, isLetter, shift, command}  -- see playKeyPress() in src/PlayCalculator.jsx
//   {type: "keyUp", key, produced, isLetter, shift, command}
//   {type: "blur"}                    -- focus lost: release whatever is held
//   {type: "pause"} / {type: "resume"} -- document.visibilitychange
//   {type: "changeModule", id}
//   {type: "loadState", text}         -- a preset's contents
//   {type: "queueCard"}
//   {type: "geometry", w, h}          -- LED shapes for a w × h digit cell
//
// worker -> main thread (all but ready, stateLoaded and geometry posted by
// the WebController itself):
//   {type: "ready", modules}          -- modules: [{id, menuTitle}] in menu order
//   {type: "display", cells}          -- Float32Array [segments, level, dp] × 12, cell 0 rightmost
//   {type: "cueCard", card}           -- null for none
//   {type: "module", id}
//   {type: "heldKey", key}            -- row×5 + col shown pressed, -1 none
//   {type: "error", message}
//   {type: "stateLoaded", errors}
//   {type: "geometry", geometry}

importScripts("wasm/ti59-core.js");

const FRAME_MS = 1000 / 60;

let Module = null;
let controller = null;
let intervalId = null;
const pending = [];

// SessionController reads files synchronously; the start-up set is fetched
// ahead (init), any other — a module chosen in the picker or named by a
// preset — through this, a synchronous request (allowed in a worker).
// Offline in the installed app only the Master Library is cached; another
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
    case "pointerDown": controller.pointerDown(msg.row, msg.col); break;
    case "pointerUp": controller.pointerUp(); break;
    case "keyDown":
      controller.keyDown(msg.key, msg.produced, msg.isLetter, msg.shift, msg.command);
      break;
    case "keyUp":
      controller.keyUp(msg.key, msg.produced, msg.isLetter, msg.shift, msg.command);
      break;
    case "blur": controller.blur(); break;
    case "pause": controller.suspend(); stopLoop(); break;
    case "resume": controller.resume(); startLoop(); break;
    case "changeModule": controller.changeModule(msg.id); break;
    case "loadState": {
      const errors = controller.loadState(new TextEncoder().encode(msg.text));
      postMessage({ type: "stateLoaded", errors });
      break;
    }
    case "queueCard": controller.queueCard(); break;
    case "geometry":
      postMessage({ type: "geometry", geometry: Module.ledGeometry(msg.w, msg.h) });
      break;
    default: break;
  }
}

async function init() {
  // ti59-core.js resolves its .wasm next to this worker, not next to itself
  // (wasm/): locateFile points it back.
  const [mod, cuecards] = await Promise.all([
    createTI59CoreModule({ locateFile: (path) => `wasm/${path}` }),
    fetchText("cuecards.txt"),
  ]);
  Module = mod;
  const files = await fetchFiles(Module.requiredRomFiles(cuecards));
  files["cuecards.txt"] = cuecards;
  controller = new Module.WebController(files);

  startLoop();
  postMessage({ type: "ready", modules: Module.modules(cuecards) });
  while (pending.length) handle(pending.shift());
}

onmessage = (e) => {
  if (!controller) pending.push(e.data);
  else handle(e.data);
};

init();
