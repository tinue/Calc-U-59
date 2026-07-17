// .ti59 state-file parser for the playable web calculator (#play).
// JS port of App/StateFileLoader.swift's parseStateFile and its helpers —
// same section grammar, same field semantics — minus everything tied to
// features this web build doesn't have:
//   - Trace: lines are recognized (so they don't leak into keystroke
//     parsing as garbage) but produce no event — there's no CPU trace
//     sink in the browser and trace files are out of scope, full stop.
//   - WaitFullSpeed: lines degrade to a plain Wait: of the same duration
//     — there's no press-and-hold-display fast-forward in this build,
//     but the pacing between keystrokes still matters, so the wait itself
//     is honored rather than silently dropped.
//   - MODEL: lines are recognized and ignored — the web build is TI-59
//     only, no variant switcher.
//
// Loaded as a plain (non-Babel) script — no JSX here. Exposes globals:
// parseStateFile, encodeTI59BCD, buildProgramArray.

function stripInlineComment(line) {
  return line.split("#")[0].trim();
}

// ── BCD encoder ──────────────────────────────────────────────────────────
//
// Port of encodeTI59BCD(_:) — encodes a Double as 16 TI-59 BCD nibbles.
// nibble[0] = sign flags, nibble[1..2] = exponent magnitude (LSD, MSD),
// nibble[3..15] = 13 mantissa digits (LSD at 3, MSD at 15).
function encodeTI59BCD(value) {
  const nibbles = new Array(16).fill(0);
  if (!Number.isFinite(value) || value === 0) return nibbles;

  const negative = value < 0;
  const absVal = Math.abs(value);

  // toExponential(12) matches C's "%.12e": one leading digit + 12 decimal
  // digits (13 significant digits total), with correct rounding-overflow
  // handling (e.g. 9.9999999999995e8 -> "1.000000000000e9").
  const formatted = absVal.toExponential(12);
  const eIndex = formatted.indexOf("e");
  const mantissaDigits = formatted.slice(0, eIndex).replace(".", "");
  const exp = parseInt(formatted.slice(eIndex + 1), 10);

  nibbles[0] = (negative ? 2 : 0) | (exp < 0 ? 4 : 0);

  const expMag = Math.abs(exp);
  nibbles[1] = expMag % 10;
  nibbles[2] = Math.floor(expMag / 10) % 10;

  for (let i = 15, offset = 0; i >= 3; i--, offset++) {
    nibbles[i] = parseInt(mantissaDigits[offset], 10) || 0;
  }

  return nibbles;
}

// ── Line parsers ─────────────────────────────────────────────────────────

// Port of parseProgLine: a >=3-digit leading token in range is a step
// prefix (format 2, exactly one keycode follows, rest of line ignored);
// otherwise every 1-2 digit token 0-99 on the line is a keycode (format 1).
function parseProgLine(line, maxStepAddr) {
  const tokens = line.split(/\s+/).filter((t) => t.length > 0);
  if (tokens.length === 0) return { stepAddr: null, keycodes: [] };

  let startIndex = 0;
  let startStep = null;
  if (tokens[0].length >= 3 && /^\d+$/.test(tokens[0])) {
    const n = parseInt(tokens[0], 10);
    if (n >= 0 && n <= maxStepAddr) {
      startStep = n;
      startIndex = 1;
    }
  }

  if (startStep !== null) {
    const tok = tokens[startIndex];
    if (tok === undefined || tok.length > 2 || !/^\d+$/.test(tok)) {
      return { stepAddr: startStep, keycodes: [] };
    }
    const n = parseInt(tok, 10);
    return n >= 0 && n <= 99 ? { stepAddr: startStep, keycodes: [n] } : { stepAddr: startStep, keycodes: [] };
  }

  const keycodes = [];
  for (const token of tokens) {
    if (token.length > 2 || !/^\d+$/.test(token)) continue;
    const n = parseInt(token, 10);
    if (n >= 0 && n <= 99) keycodes.push(n);
  }
  return { stepAddr: null, keycodes };
}

// Port of parseRegLine: "NN = <float>" or "HNN = <float>" (H00-H03, only
// when allowHiddenRegisters — never true in this TI-59-only web build).
function parseRegLine(line, allowHiddenRegisters, registersOut, errorsOut) {
  const parts = line.split("=");
  if (parts.length < 2) return;
  const nnStr = parts[0].trim();
  const valStr = parts.slice(1).join("=").trim();

  let regNum;
  if (/^\d+$/.test(nnStr) && Number(nnStr) <= 99) {
    regNum = Number(nnStr);
  } else if (/^H\d+$/i.test(nnStr) && Number(nnStr.slice(1)) <= 3) {
    if (!allowHiddenRegisters) {
      errorsOut.push(`Hidden register ${nnStr} is only valid for TI-58C files.`);
      return;
    }
    regNum = 60 + Number(nnStr.slice(1));
  } else {
    return;
  }

  const value = Number(valStr);
  if (!valStr || Number.isNaN(value)) {
    errorsOut.push(`Cannot parse register ${nnStr} value: "${valStr}"`);
    return;
  }
  registersOut.push({ regNum, nibbles: encodeTI59BCD(value) });
}

// Port of parseKeystrokeLine: token 99 -> toggleTrace, 11-95 -> key press.
function parseKeystrokeLine(line) {
  const tokens = line.split(/\s+/).filter((t) => t.length > 0);
  const events = [];
  for (const token of tokens) {
    if (token.length > 2 || !/^\d+$/.test(token)) continue;
    const n = parseInt(token, 10);
    if (n === 99) {
      events.push({ type: "toggleTrace" });
    } else if (n >= 11 && n <= 95) {
      events.push({ type: "key", matrixCode: n });
    }
  }
  return events;
}

function parseWaitInterval(line, prefix) {
  if (!line.toUpperCase().startsWith(prefix)) return null;
  const rest = line.slice(prefix.length).trim();
  const restUpper = rest.toUpperCase();
  if (restUpper.endsWith("MS")) {
    const v = Number(rest.slice(0, -2).trim());
    return Number.isFinite(v) ? v / 1000 : null;
  }
  if (restUpper.endsWith("S")) {
    const v = Number(rest.slice(0, -1).trim());
    return Number.isFinite(v) ? v : null;
  }
  return null;
}

// ── Section parser ───────────────────────────────────────────────────────

// Port of parseStateFile(_:maxStepAddr:allowHiddenRegisters:).
function parseStateFile(text, options) {
  const maxStepAddr = (options && options.maxStepAddr) || 479;
  const allowHiddenRegisters = !!(options && options.allowHiddenRegisters);

  const result = {
    partitionMaxStep: 479,
    partitionWasExplicit: false,
    programSteps: [], // [{stepAddr, keycode}]
    registers: [], // [{regNum, nibbles}]
    keystrokes: [], // [{type: "key"|"toggleTrace"|"wait"}]
    cueCard: null,
    solidStateModuleID: null,
    printerConnected: null,
    skipReset: false,
    errors: [],
  };

  let section = "none";
  let currentStep = 0;

  for (const rawLine of text.split(/\r\n|\r|\n/)) {
    const line = stripInlineComment(rawLine);
    if (!line) continue;
    const upper = line.toUpperCase();

    if (upper.startsWith("SOLID-STATE-MODULE:")) {
      const id = line.slice("SOLID-STATE-MODULE:".length).trim();
      if (id) result.solidStateModuleID = id;
      continue;
    }
    if (upper.startsWith("PRINTER:")) {
      const val = line.slice("PRINTER:".length).trim().toLowerCase();
      result.printerConnected = val === "on" || val === "true" || val === "1";
      continue;
    }
    if (upper.startsWith("SKIP-RESET:")) {
      const val = line.slice("SKIP-RESET:".length).trim().toLowerCase();
      result.skipReset = val === "on" || val === "true" || val === "1";
      continue;
    }
    if (upper.startsWith("MODEL:")) {
      continue; // TI-59 only in this build — recognized, ignored
    }

    if (upper.startsWith("PARTITION:")) {
      section = "partition";
      const rest = line.slice("PARTITION:".length).trim();
      const numStr = rest.split(".")[0].trim();
      if (/^\d+$/.test(numStr)) {
        const partitionSteps = Number(numStr) + 1;
        let rounded = 960;
        for (let s = 80; s <= 960; s += 80) {
          if (s >= partitionSteps) { rounded = s; break; }
        }
        result.partitionMaxStep = rounded - 1;
      }
      result.partitionWasExplicit = true;
      continue;
    }
    if (upper.startsWith("PROGRAM:")) { section = "program"; continue; }
    if (upper.startsWith("REGISTERS:")) { section = "registers"; continue; }
    if (upper.startsWith("KEYSTROKES:")) { section = "keystrokes"; continue; }
    if (upper.startsWith("CUECARD:")) {
      section = "cuecard";
      result.cueCard = newCueCard();
      continue;
    }

    switch (section) {
      case "program": {
        if (line === "...") break; // gap marker
        const { stepAddr, keycodes } = parseProgLine(line, maxStepAddr);
        if (stepAddr !== null) currentStep = stepAddr;
        for (const code of keycodes) {
          result.programSteps.push({ stepAddr: currentStep, keycode: code });
          currentStep += 1;
        }
        break;
      }
      case "registers":
        parseRegLine(line, allowHiddenRegisters, result.registers, result.errors);
        break;
      case "keystrokes": {
        const waitFullSpeed = parseWaitInterval(line, "WAITFULLSPEED:");
        const wait = waitFullSpeed !== null ? waitFullSpeed : parseWaitInterval(line, "WAIT:");
        if (wait !== null) {
          result.keystrokes.push({ type: "wait", seconds: wait });
        } else if (upper.startsWith("TRACE:")) {
          // Recognized, intentionally no-op — see file header.
        } else {
          result.keystrokes.push(...parseKeystrokeLine(line));
        }
        break;
      }
      case "cuecard":
        if (result.cueCard) applyCueCardLine(result.cueCard, line);
        break;
      default:
        break;
    }
  }

  return result;
}

// Expand a parsed result's sparse programSteps into a dense, zero-padded
// array sized to its partition — matches EmulatorViewModel's
// "programArray" construction right before the single writeProgram call.
function buildProgramArray(result) {
  const totalSteps = result.partitionMaxStep + 1;
  const programArray = new Uint8Array(totalSteps);
  for (const { stepAddr, keycode } of result.programSteps) {
    if (stepAddr < totalSteps) programArray[stepAddr] = keycode;
  }
  return programArray;
}
