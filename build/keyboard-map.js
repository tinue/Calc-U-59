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
// Only 26 of the 45 keys are bound, deliberately: the white (digit) keys, the
// yellow keys except 2nd, the A-E function keys, and EE / ( / ). Every other key
// — 2nd, INV, lnx, CE, LRN, x⇄t, x², √x, 1/x, SST, STO, RCL, SUM, yˣ, BST, GTO,
// SBR, RST, R/S — is click-only on purpose. Don't "complete" this table without
// asking.
//
// Three rules:
//
//   1. A binding may resolve to two matrix codes. 2nd functions are not bound as
//      codes of their own — they are reached the way the hardware reaches them,
//      by pressing 2nd (matrix 21) and then the key.
//   2. Shift + letter is shorthand for "2nd, then that letter's key". Since only
//      a-e are bound, that is the only place the rule fires: it gives A'-E' from
//      Shift+A..Shift+E, the only second function reachable from the keyboard at
//      all, as 2nd itself has no binding.
//   3. Shift is NOT a 2nd prefix for non-letters, which resolve on the character
//      the keyboard produced: Shift+. is ">" -> EE and Shift+, is "<" -> +/−.
//      That rule is also what makes the shifted symbols work at all — on a US
//      layout *, ( , ) and + are all Shift-something.
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
  // Function keys A-E (Shift gives A'-E')
  a: 11, b: 12, c: 13, d: 14, e: 15,

  // Yellow keys, 2nd excluded
  Escape: 25,       // CLR
  "/": 55,          // ÷
  "*": 65, x: 65,   // × — `x` too, so a keyboard without a numpad doesn't need
                    // Shift+8 for every multiplication
  "-": 75,
  "+": 85,
  "=": 95,
  Enter: 95,        // = (main block and numeric keypad both report "Enter")

  // White keys
  7: 62, 8: 63, 9: 64,
  4: 72, 5: 73, 6: 74,
  1: 82, 2: 83, 3: 84,
  0: 92,
  ".": 93, ",": 93, // `,` for layouts with a decimal comma on the keypad
  "<": 94,          // +/−

  // Exceptions: three dark keys worth typing
  ">": 52,          // EE — `e` belongs to the E user key
  "(": 53,
  ")": 54,
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
  { keys: ["0", "…", "9"], label: "0 – 9", note: "or numeric keypad" },
  { keys: [".", ","], label: "." },
  { keys: ["<"], label: "+/−" },
  { keys: ["+"], label: "+" },
  { keys: ["-"], label: "−" },
  { keys: ["*", "x"], label: "×" },
  { keys: ["/"], label: "÷" },
  { keys: ["=", "Enter"], label: "=" },
  { keys: ["Esc"], label: "CLR" },
  { keys: [">"], label: "EE" },
  { keys: ["("], label: "(" },
  { keys: [")"], label: ")" },
  { keys: ["a", "…", "e"], label: "A – E" },
  { keys: ["Shift", "A", "…", "E"], label: "A' – E'" },
];
