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
/// Three rules the table below encodes:
///
/// 1. **Every one of the 45 keys has an unshifted binding.** 2nd functions are
///    not bound separately — they are reached the way the hardware reaches them,
///    by pressing 2nd (matrix 21) and then the key, which is why `matrixCodes`
///    can return two codes.
/// 2. **Shift + letter is shorthand for "2nd, then that letter's key"**, which is
///    what produces A′–E′ from `Shift+A`…`Shift+E` (and, for free, sin/cos/tan
///    from `Shift+Q/V/W`, log from `Shift+N`, and so on).
/// 3. **Non-letters resolve on the character the keyboard actually produced**, so
///    Shift is *not* a 2nd prefix for them: `Shift+.` is `>` → EE, not "2nd `.`".
///    This is also what makes the shifted symbols work at all — on a US layout
///    `*`, `(`, `)`, `+` and `^` are all Shift-something.
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

    /// Character → matrix code, covering all 45 keys.
    ///
    /// Letters are stored lowercase; the uppercase form is handled by the Shift
    /// rule in `matrixCodes` above. Numeric-keypad keys need no entries of their
    /// own — they produce the same characters as their main-block counterparts.
    private static let bindings: [Character: UInt8] = [
        // ── Row 1 — user-defined keys (Shift gives A′–E′) ───────────────────
        "a": 11, "b": 12, "c": 13, "d": 14, "e": 15,

        // ── Row 2 ───────────────────────────────────────────────────────────
        "'": 21,                                   // 2nd
        "i": 22,                                   // INV
        "n": 23,                                   // lnx
        KeyEquivalent.delete.character:        24,  // CE — Backspace
        KeyEquivalent.deleteForward.character: 24,  // CE — Delete
        KeyEquivalent.escape.character:        25,  // CLR

        // ── Row 3 ───────────────────────────────────────────────────────────
        "l": 31,                                   // LRN
        "t": 32,                                   // x⇄t
        "q": 33,                                   // x²
        "v": 34,                                   // √x
        "w": 35,                                   // 1/x

        // ── Row 4 ───────────────────────────────────────────────────────────
        KeyEquivalent.downArrow.character:     41,  // SST
        "s": 42,                                   // STO
        "r": 43,                                   // RCL
        "u": 44,                                   // SUM
        "y": 45, "^": 45,                          // yˣ

        // ── Row 5 ───────────────────────────────────────────────────────────
        KeyEquivalent.upArrow.character:       51,  // BST
        ">": 52,                                   // EE — `e` belongs to the E user key
        "(": 53,
        ")": 54,
        "/": 55,                                   // ÷

        // ── Row 6 ───────────────────────────────────────────────────────────
        "g": 61,                                   // GTO
        "7": 62, "8": 63, "9": 64,
        "*": 65, "x": 65,                          // × — `x` too, so a keyboard
                                                   // without a numpad doesn't
                                                   // need Shift+8 for every
                                                   // multiplication

        // ── Row 7 ───────────────────────────────────────────────────────────
        "j": 71,                                   // SBR
        "4": 72, "5": 73, "6": 74,
        "-": 75,

        // ── Row 8 ───────────────────────────────────────────────────────────
        KeyEquivalent.home.character:          81,  // RST
        "1": 82, "2": 83, "3": 84,
        "+": 85,

        // ── Row 9 ───────────────────────────────────────────────────────────
        KeyEquivalent.space.character:         91,  // R/S
        "0": 92,
        ".": 93, ",": 93,                          // `,` for layouts with a
                                                   // decimal comma on the keypad
        "_": 94,                                   // +/−
        "\u{F70C}": 94,                            // +/− on F9 as well, matching
                                                   // Windows Calculator. AppKit
                                                   // reports function keys as
                                                   // private-use scalars, F1 at
                                                   // U+F704; macOS only, and only
                                                   // when F9 isn't claimed by the
                                                   // system's Mission Control map.
        KeyEquivalent.return.character:        95,  // =
        "\u{3}": 95,                               // = on the numeric keypad's Enter
        "=": 95,
    ]
}
