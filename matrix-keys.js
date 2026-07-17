// Keyboard matrix conversion, shared by calc-engine-worker.js (KEYSTROKES
// replay) and PlayCalculator.jsx (live key grid clicks). Plain script, no
// JSX — loaded via importScripts() in the worker and a <script> tag on
// the main thread.
//
// TI59Machine::pressKey(row, col) does NOT take raw 0-indexed grid
// coordinates. Per Bridge/TI59MachineWrapper.mm's pressMatrixKey, the two
// arguments are actually (kBit, digitSlot):
//   kBit      = K-line bit index, looked up from physical column (1-5)
//               via KBITS — note column 4 skips kBit value 4, jumping to
//               5 (a real hardware quirk, not a typo).
//   digitSlot = row (1-9), used directly.
//
// KBITS[0] is unused (columns are 1-5); mirrors
// `static const int kbits[] = {0, 1, 2, 3, 5, 6};` in the Bridge exactly.
const KBITS = [0, 1, 2, 3, 5, 6];

// uiRow/uiCol are 0-indexed grid positions (row 0-8 top-to-bottom, col 0-4
// left-to-right) — the same shape as docs/Calculator.jsx's `rows` array
// and KeyboardView.swift's `keyAt` hit-test loop.
function pressUIKey(machine, uiRow, uiCol) {
  const digitSlot = uiRow + 1;
  const col = uiCol + 1;
  machine.pressKey(KBITS[col], digitSlot);
}

function releaseUIKey(machine, uiRow, uiCol) {
  const digitSlot = uiRow + 1;
  const col = uiCol + 1;
  machine.releaseKey(KBITS[col], digitSlot);
}

// matrixCode is the 1-indexed "row*10+col" form used in .ti59 KEYSTROKES
// sections (11-95) — see docs/state-file-parser.js / StateFileLoader.swift.
function pressMatrixCode(machine, matrixCode) {
  const row = Math.floor(matrixCode / 10);
  const col = matrixCode % 10;
  if (col < 1 || col > 5 || row < 1 || row > 9) return;
  machine.pressKey(KBITS[col], row);
}

function releaseMatrixCode(machine, matrixCode) {
  const row = Math.floor(matrixCode / 10);
  const col = matrixCode % 10;
  if (col < 1 || col > 5 || row < 1 || row > 9) return;
  machine.releaseKey(KBITS[col], row);
}
