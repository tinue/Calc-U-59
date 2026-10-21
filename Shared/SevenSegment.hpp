#pragma once
#include <cstdint>

// 7-segment patterns for the 12-digit LED display. Every glyph (digits,
// minus, degree, blank, the "C" annunciator) comes from this table — never
// from a font: no font reproduces the hardware's lit-segment patterns (see
// reference/NewGUIGuide.md). The drawing itself (shear, glow) stays in each
// frontend; see reference/SharedArchitecture.md § "LED Display Rendering".
//
// Segments: bit 0=A(top) 1=B(upper-right) 2=C(lower-right) 3=D(bottom)
//           4=E(lower-left) 5=F(upper-left) 6=G(middle)

namespace cu59 {

inline constexpr uint8_t kDigitSegments[10] = {
    0b0111111,  // 0: A B C D E F
    0b0000110,  // 1: B C
    0b1011011,  // 2: A B D E G
    0b1001111,  // 3: A B C D G
    0b1100110,  // 4: B C F G
    0b1101101,  // 5: A C D F G
    0b1111101,  // 6: A C D E F G
    0b0000111,  // 7: A B C
    0b1111111,  // 8: all
    0b1101111,  // 9: A B C D F G
};

inline constexpr uint8_t kSegmentsMinus  = 0b1000000;  // G only
inline constexpr uint8_t kSegmentsDegree = 0b1100011;  // A B F G
inline constexpr uint8_t kSegmentsC      = 0b0111001;  // A F E D — "C" annunciator

/// Segments for one display cell from its A-register digit and B-register
/// control nibble (DisplaySnapshot::digits/ctrl), or 0 when the
/// zero-suppression circuit blanks it. Ctrl 0/1/8/9 select the digit,
/// 2/3/4 a space ('"', positive sign, apostrophe), 5 minus (digit 0) or
/// degree, 6 minus, 7 and above blank.
inline constexpr uint8_t segmentsFor(uint8_t digit, uint8_t ctrl, bool suppressed) {
    if (suppressed) return 0;
    switch (ctrl) {
    case 0: case 1: case 8: case 9: return kDigitSegments[(digit & 0xF) % 10];
    case 5: return digit == 0 ? kSegmentsMinus : kSegmentsDegree;
    case 6: return kSegmentsMinus;
    default: return 0;
    }
}

/// What one cell (0 = rightmost) shows: its glyph at its brightness (`level`
/// 0–255), or in cell 11, while the "C" annunciator is lit (`calcOpacity` > 0),
/// the C at that opacity. `opacity` is 0–1.
struct LedCell {
    uint8_t segments;
    double opacity;
};
inline constexpr LedCell ledCell(int i, uint8_t digit, uint8_t ctrl, uint8_t level, double calcOpacity) {
    if (i == 11 && calcOpacity > 0) return {kSegmentsC, calcOpacity};
    return {segmentsFor(digit, ctrl, level == 0), level / 255.0};
}

} // namespace cu59
