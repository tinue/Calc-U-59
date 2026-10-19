#pragma once
#include <cstdint>
#include <vector>

// Computer keyboard → TI-59 key matrix. Values are matrix codes (row×10 +
// col), the numbering KEYSTROKES: sections use — not program keycodes. The
// mapping is documented in reference/SharedArchitecture.md § "Physical Keyboard
// Mapping" (docs/keyboard-map.js is the web build's hand-ported twin).
//
// Only 26 of the 45 keys are bound, deliberately: the white (digit) keys, the
// yellow keys except 2nd, the A–E function keys, and EE / ( / ). Every other
// key is mouse-only on purpose. Don't "complete" the table without asking.
//
// Rules:
// 1. A binding may resolve to two matrix codes: 2nd functions are reached the
//    way the hardware reaches them, by pressing 2nd (21) and then the key.
// 2. Shift + letter is shorthand for "2nd, then that letter's key" (A′–E′).
// 3. Non-letters resolve on the character the keyboard actually produced, so
//    Shift is not a 2nd prefix for them (Shift+. is '>' → EE). Lookup by
//    produced character makes non-US layouts work wherever they put these.

namespace cu59 {

/// Matrix code of the 2nd key — the prefix in every two-code sequence.
inline constexpr uint8_t kSecondKey = 21;

/// Special characters frontends pass for non-printing keys.
inline constexpr char32_t kKeyEscape = 0x1B;
inline constexpr char32_t kKeyReturn = '\r';
inline constexpr char32_t kKeyEnter  = 0x03;  ///< Numeric-keypad Enter.

struct KeyPress {
    char32_t key = 0;        ///< The key's base character (unshifted label).
    char32_t produced = 0;   ///< The character the layout produced (0 if none).
    bool isLetter = false;   ///< key is a letter (frontend's Unicode test).
    bool shift = false;
    bool command = false;    ///< Command / Control / Option(Alt): never the calculator's.
};

/// One or two matrix codes for the key press; empty if unbound. Two codes are
/// a 2nd-prefixed sequence that must be played back as two separate presses.
std::vector<uint8_t> matrixCodesFor(const KeyPress& press);

} // namespace cu59
