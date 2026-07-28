// Physical-keyboard → TI-59 key matrix, for the embedded #play calculator.
//
// Hand-ported twin of App/TI59KeyboardMap.swift. Both follow the table in
// reference/AppArchitecture.md § "Physical Keyboard Mapping"; that document is
// the source of truth, this file and the Swift one are the two copies. Same
// situation as matrix-keys.js vs. the Bridge's kbits[], or state-file-parser.js
// vs. StateFileLoader.swift — see reference/NewGUIGuide.md § "Known Duplication
// Traps". If you change one, change the other.
//
// Values are matrix codes (row*10 + col, row 1-9 top to bottom, col 1-5 left to
// right) — the same numbering .ti59 KEYSTROKES sections use. Feed them to
// pressMatrixCode/releaseMatrixCode in matrix-keys.js.
//
// Loaded from docs/index.html only, NOT from docs/app/index.html: the installable
// standalone app runs on phones and has no keyboard to map. PlayCalculator.jsx
// therefore guards on `typeof` before touching anything here.
//
// Three rules:
//
//   1. All 45 keys of the face have an unshifted binding. 2nd functions are not
//      bound separately — they are reached the way the hardware reaches them, by
//      pressing 2nd (matrix 21) and then the key, which is why the lookup can
//      return two codes.
//   2. Shift + letter is shorthand for "2nd, then that letter's key". That is what
//      gives A'-E' from Shift+A..Shift+E, and for free sin/cos/tan from
//      Shift+Q/V/W, log from Shift+N, and so on.
//   3. Shift is NOT a 2nd prefix for non-letters, which resolve on the character
//      the keyboard produced: Shift+. is ">" -> EE, not "2nd .". That rule is also
//      what makes the shifted symbols work at all — on a US layout *, (, ), + and
//      ^ are all Shift-something.
//
// Because lookup goes through KeyboardEvent.key rather than a physical code, a
// non-US layout works wherever it happens to put these characters.

// Matrix code of the 2nd key — the prefix in every two-code sequence.
const TI59_SECOND_KEY = 21;

// KeyboardEvent.key → matrix code. Letters are stored lowercase; the uppercase
// form is handled by the Shift rule in ti59KeyboardMatrixCodes() below.
// Numeric-keypad keys need no entries of their own — they report the same
// KeyboardEvent.key values as their main-block counterparts.
const TI59_KEY_BINDINGS = {
  // Row 1 — user-defined keys (Shift gives A'-E')
  a: 11, b: 12, c: 13, d: 14, e: 15,

  // Row 2
  "'": 21,          // 2nd
  i: 22,            // INV
  n: 23,            // lnx
  Backspace: 24,    // CE
  Delete: 24,       // CE
  Escape: 25,       // CLR

  // Row 3
  l: 31,            // LRN
  t: 32,            // x⇄t
  q: 33,            // x²
  v: 34,            // √x
  w: 35,            // 1/x

  // Row 4
  ArrowDown: 41,    // SST
  s: 42,            // STO
  r: 43,            // RCL
  u: 44,            // SUM
  y: 45, "^": 45,   // yˣ

  // Row 5
  ArrowUp: 51,      // BST
  ">": 52,          // EE — `e` belongs to the E user key
  "(": 53,
  ")": 54,
  "/": 55,          // ÷

  // Row 6
  g: 61,            // GTO
  7: 62, 8: 63, 9: 64,
  "*": 65, x: 65,   // × — `x` too, so a keyboard without a numpad doesn't need
                    // Shift+8 for every multiplication

  // Row 7
  j: 71,            // SBR
  4: 72, 5: 73, 6: 74,
  "-": 75,

  // Row 8
  Home: 81,         // RST
  1: 82, 2: 83, 3: 84,
  "+": 85,

  // Row 9
  " ": 91,          // R/S
  0: 92,
  ".": 93, ",": 93, // `,` for layouts with a decimal comma on the keypad
  _: 94,            // +/−
  F9: 94,           // +/− on F9 as well, matching Windows Calculator
  Enter: 95,        // = (main block and numeric keypad both report "Enter")
  "=": 95,
};

// Resolve a keydown/keyup event to an array of one or two matrix codes, or null
// if the key is unbound. Two codes mean a 2nd-prefixed sequence that has to be
// played back as two separate presses, never sent at once.
function ti59KeyboardMatrixCodes(event) {
  // Ctrl/Cmd/Alt chords belong to the browser or the OS, never to the
  // calculator. Shift is the one modifier this map consumes.
  if (event.ctrlKey || event.metaKey || event.altKey) return null;

  const key = event.key;

  if (/^[A-Za-z]$/.test(key)) {
    const code = ti59Binding(key.toLowerCase());
    if (code === null) return null;
    // event.shiftKey rather than the case of `key`, so Caps Lock alone doesn't
    // silently turn every letter into its 2nd function.
    return event.shiftKey ? [TI59_SECOND_KEY, code] : [code];
  }

  const code = ti59Binding(key);
  return code === null ? null : [code];
}

// Plain-object lookup that can't hand back an inherited Object.prototype member
// for an event.key like "constructor".
function ti59Binding(key) {
  const code = TI59_KEY_BINDINGS[key];
  return typeof code === "number" ? code : null;
}

// The same table, in face order, for the "Keyboard" section on the #play page.
// Generated from one place so the published legend can't drift from the code
// that actually runs.
const TI59_KEYBOARD_LEGEND = [
  { keys: ["0", "…", "9"], label: "0 – 9", note: "main block or numeric keypad" },
  { keys: [".", ","], label: "." },
  { keys: ["_", "F9"], label: "+/−" },
  { keys: ["+"], label: "+" },
  { keys: ["-"], label: "−" },
  { keys: ["*", "x"], label: "×" },
  { keys: ["/"], label: "÷" },
  { keys: ["=", "Enter"], label: "=" },
  { keys: ["("], label: "(" },
  { keys: [")"], label: ")" },
  { keys: ["^", "y"], label: "yˣ" },
  { keys: [">"], label: "EE" },
  { keys: ["Esc"], label: "CLR" },
  { keys: ["⌫"], label: "CE" },
  { keys: ["Space"], label: "R/S" },
  { keys: ["Home"], label: "RST" },
  { keys: ["↓"], label: "SST" },
  { keys: ["↑"], label: "BST" },
  { keys: ["a", "…", "e"], label: "A – E" },
  { keys: ["'"], label: "2nd" },
  { keys: ["i"], label: "INV" },
  { keys: ["n"], label: "lnx" },
  { keys: ["l"], label: "LRN" },
  { keys: ["t"], label: "x⇄t" },
  { keys: ["q"], label: "x²" },
  { keys: ["v"], label: "√x" },
  { keys: ["w"], label: "1/x" },
  { keys: ["s"], label: "STO" },
  { keys: ["r"], label: "RCL" },
  { keys: ["u"], label: "SUM" },
  { keys: ["g"], label: "GTO" },
  { keys: ["j"], label: "SBR" },
];
