#include "KeyboardMap.hpp"

namespace cu59 {

namespace {

/// Character → matrix code, for the 26 bound keys only. Letters are
/// lowercase; the Shift rule handles uppercase. Numeric-keypad keys produce
/// the same characters as their main-block counterparts.
int binding(char32_t c) {
    switch (c) {
    // ── Function keys A–E (Shift gives A′–E′) ───────────────────────────
    case 'a': return 11;
    case 'b': return 12;
    case 'c': return 13;
    case 'd': return 14;
    case 'e': return 15;
    // ── Yellow keys, 2nd excluded ───────────────────────────────────────
    case kKeyEscape: return 25;  // CLR
    case '/': return 55;         // ÷
    case '*': case 'x': return 65;  // × — `x` too, so a keyboard without a
                                    // numpad doesn't need Shift+8
    case '-': return 75;
    case '+': return 85;
    case '=': case kKeyReturn: case kKeyEnter: return 95;
    // ── White keys ──────────────────────────────────────────────────────
    case '7': return 62;
    case '8': return 63;
    case '9': return 64;
    case '4': return 72;
    case '5': return 73;
    case '6': return 74;
    case '1': return 82;
    case '2': return 83;
    case '3': return 84;
    case '0': return 92;
    case '.': case ',': return 93;  // `,` for layouts with a decimal comma
    case '<': return 94;            // +/−
    // ── Exceptions: three dark keys worth typing ────────────────────────
    case '>': return 52;  // EE — `e` belongs to the E user key
    case '(': return 53;
    case ')': return 54;
    default: return 0;
    }
}

char32_t asciiLower(char32_t c) { return (c >= 'A' && c <= 'Z') ? c + ('a' - 'A') : c; }

} // namespace

std::vector<uint8_t> matrixCodesFor(const KeyPress& press) {
    if (press.command) return {};
    if (press.isLetter) {
        int code = binding(asciiLower(press.key));
        if (!code) return {};
        if (press.shift) return {kSecondKey, static_cast<uint8_t>(code)};
        return {static_cast<uint8_t>(code)};
    }
    // Rule 3: the produced character wins for everything that isn't a letter.
    if (press.produced) {
        if (int code = binding(press.produced)) return {static_cast<uint8_t>(code)};
    }
    if (int code = binding(press.key)) return {static_cast<uint8_t>(code)};
    return {};
}

} // namespace cu59
