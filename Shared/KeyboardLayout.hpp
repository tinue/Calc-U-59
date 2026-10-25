#pragma once

// Calculator canvas geometry shared by every frontend: the base image
// (2064×4075: display panel, card slot, keyboard), where the LED and cue-card
// overlays sit, and the 9×5 key rectangles with the widened hit test.
// Rects are normalized: display/card to the whole canvas, keys to the
// keyboard section (canvas y from kKeyboardYStart, height kKeyboardYScale).
// Key rects were extracted from key_rectangles.png.

#include <optional>
#include <utility>

namespace cu59 {

struct NRect {
    double x, y, w, h;
    constexpr bool contains(double px, double py) const {
        return px >= x && px < x + w && py >= y && py < y + h;
    }
};

inline constexpr double kCanvasAspect = 2064.0 / 4075.0;  ///< width / height

/// LED display window (canvas-space), above the card to avoid overlap.
inline constexpr NRect kDisplayRect{0.0, 0.052, 1.0, 0.05};

/// Cue-card slot (canvas-space). The card images are 440 px tall: 440 / 4075 ≈ 0.108.
inline constexpr NRect kCardRect{0.0, 0.11, 1.0, 0.1080};

/// Keyboard section within the canvas.
inline constexpr double kKeyboardYStart = 0.2324;
inline constexpr double kKeyboardYScale = 0.7676;

/// Key rects in keyboard-image space, [row 0–8][col 0–4]. Matrix code = (row+1)×10 + (col+1).
inline constexpr NRect kKeyRects[9][5] = {
    // row 0
    {{0.0160, 0.0365, 0.1245, 0.0486}, {0.2277, 0.0365, 0.1245, 0.0486}, {0.4375, 0.0365, 0.1245, 0.0486}, {0.6483, 0.0365, 0.1245, 0.0486}, {0.8571, 0.0365, 0.1245, 0.0486}},
    // row 1
    {{0.0140, 0.1484, 0.1265, 0.0508}, {0.2277, 0.1484, 0.1245, 0.0508}, {0.4375, 0.1484, 0.1245, 0.0508}, {0.6483, 0.1484, 0.1245, 0.0508}, {0.8566, 0.1484, 0.1250, 0.0508}},
    // row 2
    {{0.0160, 0.2625, 0.1245, 0.0508}, {0.2277, 0.2625, 0.1245, 0.0508}, {0.4375, 0.2625, 0.1245, 0.0508}, {0.6483, 0.2625, 0.1245, 0.0508}, {0.8571, 0.2625, 0.1245, 0.0508}},
    // row 3
    {{0.0160, 0.3753, 0.1245, 0.0508}, {0.2277, 0.3753, 0.1245, 0.0508}, {0.4375, 0.3753, 0.1245, 0.0508}, {0.6483, 0.3753, 0.1245, 0.0508}, {0.8571, 0.3753, 0.1245, 0.0508}},
    // row 4
    {{0.0160, 0.4853, 0.1245, 0.0508}, {0.2277, 0.4853, 0.1245, 0.0508}, {0.4375, 0.4853, 0.1245, 0.0508}, {0.6483, 0.4853, 0.1245, 0.0508}, {0.8566, 0.4853, 0.1284, 0.0508}},
    // row 5
    {{0.0155, 0.5987, 0.1250, 0.0508}, {0.2001, 0.5963, 0.1623, 0.0534}, {0.4186, 0.5959, 0.1623, 0.0537}, {0.6366, 0.5963, 0.1628, 0.0534}, {0.8566, 0.5963, 0.1289, 0.0534}},
    // row 6
    {{0.0160, 0.7110, 0.1245, 0.0508}, {0.2001, 0.7091, 0.1623, 0.0528}, {0.4186, 0.7084, 0.1623, 0.0534}, {0.6366, 0.7094, 0.1628, 0.0524}, {0.8566, 0.7091, 0.1289, 0.0528}},
    // row 7
    {{0.0160, 0.8232, 0.1245, 0.0508}, {0.2001, 0.8219, 0.1623, 0.0537}, {0.4186, 0.8213, 0.1623, 0.0528}, {0.6371, 0.8223, 0.1623, 0.0537}, {0.8566, 0.8217, 0.1289, 0.0537}},
    // row 8
    {{0.0160, 0.9360, 0.1245, 0.0508}, {0.2001, 0.9336, 0.1623, 0.0541}, {0.4186, 0.9336, 0.1623, 0.0534}, {0.6366, 0.9336, 0.1623, 0.0556}, {0.8566, 0.9340, 0.1294, 0.0557}},
};

/// Hit-test expansion: each rect grows by this fraction of its width left
/// AND right, and of its height top AND bottom.
inline constexpr double kHitExpandHorizontal = 0.15;
inline constexpr double kHitExpandVertical   = 0.35;

constexpr NRect expandedKeyRect(int row, int col) {
    const NRect& r = kKeyRects[row][col];
    double ew = r.w * kHitExpandHorizontal, eh = r.h * kHitExpandVertical;
    return {r.x - ew, r.y - eh, r.w + ew * 2, r.h + eh * 2};
}

struct KeyHit { int row, col; };  ///< 0-based

/// First key whose expanded rect contains the keyboard-space point; false if none.
inline bool keyAt(double nx, double ny, KeyHit& out) {
    for (int row = 0; row < 9; ++row)
        for (int col = 0; col < 5; ++col)
            if (expandedKeyRect(row, col).contains(nx, ny)) { out = {row, col}; return true; }
    return false;
}

/// The pointer on the calculator canvas, as every frontend handles it:
/// holding the display runs the emulator at full speed, a key under the
/// pointer is held (one at a time; a drag moves it to another key), leaving
/// the keyboard releases it. Points are canvas-normalized; each call returns
/// what to do, which the frontend applies to its controller.
class PointerTracker {
public:
    struct Change {
        std::optional<bool> fullSpeed;  ///< switch full speed on or off
        int release = -1;               ///< key (row × 5 + col) to release
        int press = -1;                 ///< key to press
    };

    Change move(double nx, double ny) {
        Change c;
        if (kDisplayRect.contains(nx, ny)) {
            if (!m_onDisplay) {
                m_onDisplay = true;
                c.fullSpeed = true;
                c.release = std::exchange(m_key, -1);
            }
            return c;
        }
        if (m_onDisplay) {
            m_onDisplay = false;
            c.fullSpeed = false;
        }
        const double kbNy = (ny - kKeyboardYStart) / kKeyboardYScale;
        const double margin = 0.025;  // room for the vertical hit expansion
        if (kbNy < -margin || kbNy > 1 + margin) {
            c.release = std::exchange(m_key, -1);
            return c;
        }
        KeyHit hit{};
        if (!keyAt(nx, kbNy, hit) || hit.row * 5 + hit.col == m_key) return c;
        c.release = m_key;
        c.press = m_key = hit.row * 5 + hit.col;
        return c;
    }

    Change up() {
        Change c;
        if (m_onDisplay) {
            m_onDisplay = false;
            c.fullSpeed = false;
        }
        c.release = std::exchange(m_key, -1);
        return c;
    }

    /// The key the pointer holds (row × 5 + col), -1 for none.
    int key() const { return m_key; }

private:
    int m_key = -1;
    bool m_onDisplay = false;
};

} // namespace cu59
