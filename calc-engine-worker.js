// Background emulation Worker for the playable web calculator (#play).
// Owns the WASM TI59Machine instance and the step loop — the same shape
// as EmulatorViewModel's background emulQueue + 60 Hz displayTimer, just
// Worker + postMessage instead of GCD + Timer. See the plan at
// /Users/me/.claude/plans/replicated-riding-duckling.md for the "cycle
// accuracy is relaxed" / "pauses on tab-hidden" decisions this encodes.
//
// A classic (non-module) Worker, so cuecard-data.js and state-file-parser.js
// (already plain global-scope scripts, no JSX/Babel needed) can be shared
// via importScripts() instead of duplicating their logic.
//
// Protocol (postMessage), main thread -> worker:
//   {type: "press",  row, col}   -- 0-indexed UI grid position (see matrix-keys.js)
//   {type: "release", row, col}
//   {type: "pause"}                    -- e.g. on document.visibilitychange
//   {type: "resume"}
//   {type: "loadModule", id}           -- e.g. "ML", "ST", ...
//   {type: "loadState", text}          -- raw .ti59 file contents
//
// worker -> main thread:
//   {type: "ready"}
//   {type: "display", digits, ctrl, dpPos, dpAfterglowMask, suppressedMask, calcIndicator}
//   {type: "moduleLoaded", id, title, menuTitle, cuecards}
//   {type: "cueCard", card}            -- from a loaded state file's own CUECARD: section
//   {type: "stateLoaded"}

importScripts("cuecard-data.js", "state-file-parser.js", "matrix-keys.js", "wasm/ti59-core.js");

const STEP_INTERVAL_MS = 1000 / 60;

// TI-59 hardware clock: 455 kHz crystal / 2 (two-phase) / 16 (digit-serial)
// = 14,218.75 instructions/sec — matches EmulatorViewModel.swift's
// startEmulationLoop targetHz exactly. The tick loop below calls
// machine.stepCycles(), which loops step() until a *weighted* cycle
// budget is exhausted (1 unit/active step, 4/IDLE step — IDLE runs at
// 1/4 real speed on hardware) with no early exit at keycode boundaries.
// Two other primitives were tried and rejected for this:
//   - stepUntilNextKeycode: exits at every keycode boundary, which
//     happens almost every step during active program execution — under
//     a small per-tick budget that barely advances the CPU at all (this
//     was the actual cause of the "C" indicator reading near-zero).
//   - stepN: correctly runs the full budget with no early exit, but
//     treats the budget as a literal *count of step() calls*, ignoring
//     the active/IDLE weighting — so an IDLE-heavy period (e.g. the
//     error blink) burned ~4x more simulated hardware time per tick than
//     an active one for the same budget, making the blink run too fast
//     even though active computation was correctly paced.
const TARGET_HZ = 14218.75;
const TICK_TARGET_CYCLES = TARGET_HZ * (STEP_INTERVAL_MS / 1000);
const POWER_ON_STEPS = 300000; // matches EmulatorViewModel's post-reset stabilization run

let machine = null;
let intervalId = null;
let currentModuleId = null;
// Cycles executed ahead of (positive) or behind (negative) the wall-clock
// schedule — carried across ticks the same way EmulatorViewModel's
// startEmulationLoop carries `cyclesDone -= targetBatchCycles`.
let cyclesAhead = 0;
let modulesManifest = null;
const moduleCache = {};

function base64ToBytes(b64) {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchJSON(path) {
  const resp = await fetch(path);
  return resp.json();
}

// ── Module (solid-state library) loading ────────────────────────────────

async function loadModulesManifest() {
  if (!modulesManifest) modulesManifest = await fetchJSON("wasm/roms/modules.json");
  return modulesManifest;
}

async function loadModule(moduleId) {
  const manifest = await loadModulesManifest();
  const entry = manifest.find((m) => m.id === moduleId);
  if (!entry) return;

  if (!moduleCache[moduleId]) {
    moduleCache[moduleId] = await fetchJSON(`wasm/roms/${entry.file}`);
  }
  const data = moduleCache[moduleId];
  machine.loadLibrary(base64ToBytes(data.rom));
  currentModuleId = moduleId;
  postMessage({
    type: "moduleLoaded",
    id: moduleId,
    title: data.title,
    menuTitle: data.menuTitle,
    cuecards: data.cuecards,
  });
}

// ── State file (.ti59) loading ──────────────────────────────────────────
//
// Mirrors the write order in EmulatorViewModel's loadStateFile: reset,
// partition, program, registers, then module, then keystrokes. Unlike the
// app, there's no separate "clear RAM preserving hidden registers" pass —
// reset() already zeroes everything, and this build has no constant-memory
// (TI-58C) variant that would need hidden registers preserved.
async function applyStateFile(text) {
  const result = parseStateFile(text, { maxStepAddr: 479, allowHiddenRegisters: false });

  // Posted immediately, before reset/program/keystroke playback — a
  // preset's KEYSTROKES section can take many seconds to play out (each
  // key press paced with real delays below), and the card shouldn't wait
  // on that; it's just reference material for what's about to run.
  postMessage({ type: "cueCard", card: result.cueCard });

  if (!result.skipReset) {
    machine.reset();
    machine.stepN(POWER_ON_STEPS);
  }

  const totalSteps = result.partitionMaxStep + 1;
  machine.setPartitionProgramRegs(Math.floor(totalSteps / 8));
  machine.writeProgram(buildProgramArray(result));

  for (const { regNum, nibbles } of result.registers) {
    if (regNum >= 60) continue; // hidden registers: TI-58C only, out of scope here
    machine.writeDataRegister(regNum, Uint8Array.from(nibbles));
  }

  if (result.solidStateModuleID && result.solidStateModuleID !== currentModuleId) {
    await loadModule(result.solidStateModuleID);
  }

  // Printer connection state (result.printerConnected) is intentionally
  // not applied — the printer is out of scope for this build.

  for (const event of result.keystrokes) {
    if (event.type === "key") {
      pressMatrixCode(machine, event.matrixCode);
      await sleep(80);
      releaseMatrixCode(machine, event.matrixCode);
      await sleep(120);
    } else if (event.type === "wait") {
      await sleep(event.seconds * 1000);
    }
    // toggleTrace: printer TRACE latch, out of scope, no-op.
  }

  postMessage({ type: "stateLoaded" });
}

// ── Run loop ─────────────────────────────────────────────────────────────

function tick() {
  if (!machine) return;
  if (cyclesAhead < TICK_TARGET_CYCLES) {
    const budget = Math.round(TICK_TARGET_CYCLES - cyclesAhead);
    cyclesAhead += machine.stepCycles(budget);
  }
  cyclesAhead -= TICK_TARGET_CYCLES;

  const d = machine.getDisplay();
  postMessage({
    type: "display",
    digits: d.digits,
    ctrl: d.ctrl,
    dpPos: d.dpPos,
    dpAfterglowMask: d.dpAfterglowMask,
    suppressedMask: d.suppressedMask,
    calcIndicator: d.calcIndicator,
  });
}

function startLoop() {
  if (intervalId !== null) return;
  intervalId = setInterval(tick, STEP_INTERVAL_MS);
}

function stopLoop() {
  if (intervalId === null) return;
  clearInterval(intervalId);
  intervalId = null;
}

// ── Init ─────────────────────────────────────────────────────────────────

async function init() {
  // ti59-core.js resolves its .wasm path relative to *this worker's own*
  // script location (self.location.href, i.e. docs/), not relative to
  // where it was importScripts()'d from (docs/wasm/) — so the default
  // lookup misses. locateFile corrects it back onto docs/wasm/.
  const Module = await createTI59CoreModule({ locateFile: (path) => `wasm/${path}` });
  machine = new Module.WebMachine();

  const core = await fetchJSON("wasm/roms/ti59-core.json");
  const romBytes = base64ToBytes(core.romWords);
  const romWords = new Uint16Array(romBytes.buffer, romBytes.byteOffset, romBytes.byteLength / 2);
  machine.loadROM(romWords);
  machine.loadConstants(base64ToBytes(core.constants));
  machine.reset();
  machine.stepN(POWER_ON_STEPS);

  await loadModule("ML"); // startup default: module 01, Master Library

  startLoop();
  postMessage({ type: "ready" });
}

onmessage = async (e) => {
  const msg = e.data;
  switch (msg.type) {
    case "press":
      if (machine) pressUIKey(machine, msg.row, msg.col);
      break;
    case "release":
      if (machine) releaseUIKey(machine, msg.row, msg.col);
      break;
    case "pause":
      stopLoop();
      break;
    case "resume":
      startLoop();
      break;
    case "loadModule":
      await loadModule(msg.id);
      break;
    case "loadState":
      await applyStateFile(msg.text);
      break;
    default:
      break;
  }
};

init();
