#pragma once
#include "../Core/TI59Machine.hpp"
#include <cstdint>

// Keyboard matrix codes (row×10 + col, row 1–9 top→bottom, col 1–5
// left→right — the same codes state files use, see
// reference/StateFileFormat.md) and their mapping onto the core's
// (K-line bit, digit slot) key coordinates. See reference/SharedArchitecture.md
// § "Key Input Coordinate Systems".

namespace cu59 {

/// K-line bit for each physical column; index 0 unused.
inline constexpr int kKBits[6] = {0, 1, 2, 3, 5, 6};

inline constexpr bool isValidMatrixCode(int code) {
    return code / 10 >= 1 && code / 10 <= 9 && code % 10 >= 1 && code % 10 <= 5;
}

/// Matrix code of the key at 0-based (row, col) — KeyboardLayout's key grid.
inline constexpr uint8_t matrixCode(int row, int col) { return static_cast<uint8_t>((row + 1) * 10 + (col + 1)); }

/// TI59Machine::pressKey takes (kBit, digitSlot): the digit slot is the row,
/// which equals the digit-counter column for that keyboard row.
inline void pressMatrix(TI59Machine& m, int code) {
    if (!isValidMatrixCode(code)) return;
    m.pressKey(kKBits[code % 10], code / 10);
}

inline void releaseMatrix(TI59Machine& m, int code) {
    if (!isValidMatrixCode(code)) return;
    m.releaseKey(kKBits[code % 10], code / 10);
}

} // namespace cu59
