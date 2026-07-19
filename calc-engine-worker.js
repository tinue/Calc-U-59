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
//   {type: "queueCard"}                -- user pressed "Queue Card"; see the
//                                          Magnetic card reader section below
//
// worker -> main thread:
//   {type: "ready"}
//   {type: "display", digits, ctrl, dpAfterglowMask, suppressedMask, calcIndicator}
//                                      -- only posted when the snapshot changed
//   {type: "moduleLoaded", id, menuTitle, cuecards}
//   {type: "cueCard", card}            -- from a loaded state file's own CUECARD: section
//   {type: "programNumber", n}         -- selected library program (SCOM[9]), 0 = none
//   {type: "stateLoaded", errors}      -- errors: string[] from the state-file parser

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

// ── Magnetic card reader ─────────────────────────────────────────────────
//
// Matches EmulatorViewModel.swift's model exactly, not an automatic
// "detect and answer" scheme — isWaitingForCard() was tried first and
// rejected: it reads true almost continuously during ordinary idle
// operation (TST BUSY polls the card-switch line as part of routine
// keyboard scanning, regardless of whether "2nd Write"/"2nd Read" was
// ever pressed — confirmed directly against Core), so it doesn't actually
// signal "the user just asked for a card". Swift's own app never watches
// it either: the user explicitly triggers insertCard() (there, via a file
// picker; here, via the "Queue Card" button in PlayCalculator.jsx's
// controls), and the app reacts only to auto-eject
// (tick(): "if cardState==.swiping && !machine.isCardPresent
// { ejectCard() }") to harvest anything written — never re-inserting on
// its own. Pressing "2nd Write"/"2nd Read" without ever clicking "Queue
// Card" waits forever, same as real hardware without a card physically
// swiped.
//
// One bank (246 bytes), not the full 4-bank/984-byte card: covers writing
// and reading back a single program, the realistic common case, and keeps
// this simple. Persists for the page session (reset()s don't clear it,
// same as Core: reset() only clears its own m_cardFullData, not our copy)
// — same as carrying one real card in your wallet across sessions.
const CARD_BANK_BYTES = 246;
let cardBuffer = new Uint8Array(CARD_BANK_BYTES);
let cardQueued = false; // true from "Queue Card" until the ROM auto-ejects it

function queueCard() {
  machine.insertCard(cardBuffer);
  cardQueued = true;
}

// Called every tick; a no-op unless a card was actually queued and the ROM
// has since finished with it (CRD_OFF auto-ejects on both read and write
// passes — see reference/CoreArchitecture.md's "Magnetic Card Reader").
function pollCardReader() {
  if (cardQueued && !machine.isCardPresent()) {
    const written = machine.cardEject();
    if (written.length > 0) cardBuffer = Uint8Array.from(written);
    cardQueued = false;
  }
}

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
// Bumped on every load; the keystroke-playback loop below re-checks it
// after each await and bails when a newer load has started — the same
// cancel-on-new-load behavior EmulatorViewModel.swift's keystrokeTask
// cancellation provides (a real bug fixed there in commit 182d0f5:
// without it, a second load mid-playback interleaves the first playback's
// remaining keystrokes into the freshly reset machine).
let loadGeneration = 0;

async function applyStateFile(text) {
  const generation = ++loadGeneration;
  const result = parseStateFile(text, { maxStepAddr: 479, allowHiddenRegisters: false });

  // Posted immediately, before reset/program/keystroke playback — a
  // preset's KEYSTROKES section can take many seconds to play out (each
  // key press paced with real delays below), and the card shouldn't wait
  // on that; it's just reference material for what's about to run.
  postMessage({ type: "cueCard", card: result.cueCard });

  if (!result.skipReset) {
    machine.reset();
    machine.stepN(POWER_ON_STEPS);
    cardQueued = false; // reset() clears Core's own card state too
  }

  const totalSteps = result.partitionMaxStep + 1;
  machine.setPartitionProgramRegs(Math.floor(totalSteps / 8));
  machine.writeProgram(buildProgramArray(result));

  // All of 00-99 goes through writeDataRegister: Core maps data registers
  // down from the top of the 120-slot RAM (R00 = RAM[119], R75 = RAM[44]),
  // valid for the whole range on the TI-59. There is no >= 60 special
  // case here — that branch in EmulatorViewModel.swift exists for TI-58C
  // hidden registers (H00-H03 -> raw slots 60-63), which this TI-59-only
  // build never parses (allowHiddenRegisters is always false). A file
  // whose partition leaves fewer than NN+1 data registers gets exactly
  // what it wrote — same trust-the-file behavior as the Swift app.
  for (const { regNum, nibbles } of result.registers) {
    machine.writeDataRegister(regNum, Uint8Array.from(nibbles));
  }

  if (result.solidStateModuleID && result.solidStateModuleID !== currentModuleId) {
    await loadModule(result.solidStateModuleID);
  }

  // Printer connection state (result.printerConnected) is intentionally
  // not applied — the printer is out of scope for this build.

  let fullSpeed = false;
  for (const event of result.keystrokes) {
    if (generation !== loadGeneration) return; // superseded by a newer load
    if (event.type === "key") {
      pressMatrixCode(machine, event.matrixCode);
      await sleep(fullSpeed ? 0 : 80);
      releaseMatrixCode(machine, event.matrixCode);
      await sleep(fullSpeed ? 0 : 120);
    } else if (event.type === "wait") {
      await sleep(fullSpeed ? 0 : event.seconds * 1000);
    } else if (event.type === "speed") {
      fullSpeed = event.full;
    }
  }

  postMessage({ type: "stateLoaded", errors: result.errors });
}

// ── Run loop ─────────────────────────────────────────────────────────────

// Last display snapshot actually posted, for change detection: at idle the
// snapshot is identical frame after frame, and skipping the post keeps the
// main thread (React re-render per message) at ~zero CPU while the page
// just sits in a tab. During execution frames genuinely differ (blink,
// C-indicator duty cycle), so nothing visible is lost.
let lastPosted = null;

function displayChanged(d) {
  if (!lastPosted) return true;
  if (d.dpAfterglowMask !== lastPosted.dpAfterglowMask ||
      d.suppressedMask !== lastPosted.suppressedMask ||
      d.calcIndicator !== lastPosted.calcIndicator) return true;
  for (let i = 0; i < 12; i++) {
    if (d.digits[i] !== lastPosted.digits[i] || d.ctrl[i] !== lastPosted.ctrl[i]) return true;
  }
  return false;
}

// The selected library program number (SCOM[9] nibbles 4/3 — what
// "2nd Pgm NN" sets), polled the same way EmulatorViewModel.swift's
// checkProgramNumber() does at 2 Hz, and posted on change so the UI can
// show the matching cue card. Machine state is the source of truth here:
// a UI-side key-sequence matcher would miss preset KEYSTROKES playback,
// program-driven Pgm calls, and RST clearing the selection.
const PROGRAM_POLL_TICKS = 30; // every 0.5 s at 60 Hz, matching Swift's 2 Hz-ish cadence
let tickCount = 0;
let lastProgramNumber = -1;

function tick() {
  if (!machine) return;
  if (cyclesAhead < TICK_TARGET_CYCLES) {
    const budget = Math.round(TICK_TARGET_CYCLES - cyclesAhead);
    cyclesAhead += machine.stepCycles(budget);
  }
  cyclesAhead -= TICK_TARGET_CYCLES;
  pollCardReader();

  if (++tickCount % PROGRAM_POLL_TICKS === 0) {
    const n = machine.insertedModuleNumber();
    if (n !== lastProgramNumber) {
      lastProgramNumber = n;
      postMessage({ type: "programNumber", n });
    }
  }

  const d = machine.getDisplay();
  if (!displayChanged(d)) return;
  lastPosted = d;
  postMessage({
    type: "display",
    digits: d.digits,
    ctrl: d.ctrl,
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
  // WASM compile, core ROM fetch, and the ML module's manifest+data
  // fetches are mutually independent — start them all before awaiting
  // anything, instead of serializing four round-trips (halves
  // time-to-ready on high-RTT connections).
  //
  // ti59-core.js resolves its .wasm path relative to *this worker's own*
  // script location (self.location.href, i.e. docs/), not relative to
  // where it was importScripts()'d from (docs/wasm/) — so the default
  // lookup misses. locateFile corrects it back onto docs/wasm/.
  const modulePromise = createTI59CoreModule({ locateFile: (path) => `wasm/${path}` });
  const corePromise = fetchJSON("wasm/roms/ti59-core.json");
  const mlPrefetch = loadModulesManifest()
    .then((manifest) => {
      const entry = manifest.find((m) => m.id === "ML");
      return entry ? fetchJSON(`wasm/roms/${entry.file}`) : null;
    })
    .then((data) => { if (data) moduleCache.ML = data; });

  const Module = await modulePromise;
  machine = new Module.WebMachine();

  const core = await corePromise;
  const romBytes = base64ToBytes(core.romWords);
  const romWords = new Uint16Array(romBytes.buffer, romBytes.byteOffset, romBytes.byteLength / 2);
  machine.loadROM(romWords);
  machine.loadConstants(base64ToBytes(core.constants));
  machine.reset();
  machine.stepN(POWER_ON_STEPS);

  await mlPrefetch;
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
    case "queueCard":
      if (machine) queueCard();
      break;
    default:
      break;
  }
};

init();
