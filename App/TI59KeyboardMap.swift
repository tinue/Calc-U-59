import SwiftUI

/// Maps a computer keyboard to the TI-59 key matrix.
///
/// Values are **matrix codes** (`row × 10 + col`, row 1–9 top to bottom, col 1–5
/// left to right) — the same numbering the `KEYSTROKES:` section of a state file
/// uses, *not* the 0–99 program keycodes that `TI59KeyNames` deals in. The grid
/// and the 2nd-function table are documented in `reference/StateFileFormat.md`
/// § "Matrix Code Table" / § "2nd Function Table"; the keyboard mapping itself is
/// documented in `reference/AppArchitecture.md` § "Physical Keyboard Mapping",
/// which `docs/keyboard-map.js` (the web build's hand-ported twin) also follows.
///
/// **Only 26 of the 45 keys are bound**, deliberately: the white (digit) keys,
/// the yellow keys except 2nd, the A–E function keys, and EE / `(` / `)`. Every
/// other key — 2nd, INV, lnx, CE, LRN, x⇄t, x², √x, 1/x, SST, STO, RCL, SUM,
/// yˣ, BST, GTO, SBR, RST, R/S — is mouse-only on purpose. Don't "complete" this
/// table without asking.
///
/// Three rules it encodes:
///
/// 1. **A binding may resolve to two matrix codes.** 2nd functions are not bound
///    as codes of their own — they are reached the way the hardware reaches them,
///    by pressing 2nd (matrix 21) and then the key.
/// 2. **Shift + letter is shorthand for "2nd, then that letter's key"**, which is
///    what produces A′–E′ from `Shift+A`…`Shift+E`. Since only `a`–`e` are bound,
///    that is the only place the rule fires — and the only second function
///    reachable from the keyboard at all, as 2nd itself has no binding.
/// 3. **Non-letters resolve on the character the keyboard actually produced**, so
///    Shift is *not* a 2nd prefix for them: `Shift+.` is `>` → EE and `Shift+,`
///    is `<` → +/−. This is also what makes the shifted symbols work at all — on
///    a US layout `*`, `(`, `)` and `+` are all Shift-something.
///
/// Because lookup is by produced character rather than physical scan code, a
/// non-US layout works wherever it happens to put these characters.
enum TI59KeyboardMap {

    /// Matrix code of the 2nd key — the prefix in every two-code sequence.
    static let secondKey: UInt8 = 21

    // MARK: - Lookup

    /// Resolve a key press to one or two matrix codes, or nil if unbound.
    ///
    /// Two codes mean a 2nd-prefixed sequence that has to be played back as two
    /// separate presses (see `EmulatorViewModel.typeKey`), never sent at once.
    static func matrixCodes(for keyPress: KeyPress) -> [UInt8]? {
        // Command/Control/Option chords belong to the menu bar or the system,
        // never to the calculator. Shift is the one modifier this map consumes.
        let modifiers = keyPress.modifiers
        guard !modifiers.contains(.command),
              !modifiers.contains(.control),
              !modifiers.contains(.option) else { return nil }

        let key = keyPress.key.character

        if key.isLetter {
            guard let lower = key.lowercased().first, let code = bindings[lower] else { return nil }
            return modifiers.contains(.shift) ? [secondKey, code] : [code]
        }

        // Rule 3: the produced character wins for everything that isn't a letter.
        if let produced = keyPress.characters.first, let code = bindings[produced] {
            return [code]
        }
        return bindings[key].map { [$0] }
    }

    // MARK: - Bindings

    /// Character → matrix code, for the 26 bound keys only.
    ///
    /// Letters are stored lowercase; the uppercase form is handled by the Shift
    /// rule in `matrixCodes` above. Numeric-keypad keys need no entries of their
    /// own — they produce the same characters as their main-block counterparts.
    private static let bindings: [Character: UInt8] = [
        // ── Function keys A–E (Shift gives A′–E′) ───────────────────────────
        "a": 11, "b": 12, "c": 13, "d": 14, "e": 15,

        // ── Yellow keys, 2nd excluded ───────────────────────────────────────
        KeyEquivalent.escape.character:  25,  // CLR
        "/": 55,                              // ÷
        "*": 65, "x": 65,                     // × — `x` too, so a keyboard without
                                              // a numpad doesn't need Shift+8 for
                                              // every multiplication
        "-": 75,
        "+": 85,
        "=": 95,
        KeyEquivalent.return.character:  95,  // = — Return
        "\u{3}":                         95,  // = — numeric-keypad Enter

        // ── White keys ──────────────────────────────────────────────────────
        "7": 62, "8": 63, "9": 64,
        "4": 72, "5": 73, "6": 74,
        "1": 82, "2": 83, "3": 84,
        "0": 92,
        ".": 93, ",": 93,                     // `,` for layouts with a decimal
                                              // comma on the keypad
        "<": 94,                              // +/−

        // ── Exceptions: three dark keys worth typing ────────────────────────
        ">": 52,                              // EE — `e` belongs to the E user key
        "(": 53,
        ")": 54,
    ]
}
