#include "LedGeometry.hpp"
#include <algorithm>

namespace cu59 {

const LedStyleParams& ledStyleParams(LedStyle style) {
    static const LedStyleParams kModernized{0.14, 1.0, 0.1, 0.1, 0.2, 0.0, 0.0, 0.2, 0.8, 0.6, 0.2};
    static const LedStyleParams kClassic{0.1139, 1.0, 0.2, 0.2, 0.2, 0.0, 0.0, 0.2, 1.3, 0.65, 0.0};
    return style == LedStyle::Classic ? kClassic : kModernized;
}

namespace {

struct Inset { double minX, minY, w, h; };
Inset digitInset(double w, double h) {
    double padX = w * 0.22, padY = h * 0.10;
    return {padX, padY, w - 2 * padX, h - 2 * padY};
}

std::vector<LedPoint> hSeg(double x, double y, double len, double sw) {
    double c = sw * 0.5;
    return {{x + c, y}, {x + len - c, y}, {x + len, y + sw / 2}, {x + len - c, y + sw}, {x + c, y + sw}, {x, y + sw / 2}};
}

std::vector<LedPoint> vSeg(double x, double y, double len, double sw) {
    double c = sw * 0.5;
    return {{x + sw / 2, y}, {x + sw, y + c}, {x + sw, y + len - c}, {x + sw / 2, y + len}, {x, y + len - c}, {x, y + c}};
}

} // namespace

double modernizedSegmentWidth(double w) { return digitInset(w, 1).w * 0.14; }

std::vector<std::vector<LedPoint>> modernizedSegments(double w, double h) {
    Inset r = digitInset(w, h);
    double sw = r.w * 0.14;
    double gap = sw * 0.15;
    double hh = r.h / 2, maxX = r.minX + r.w, maxY = r.minY + r.h, midY = r.minY + hh;
    double hLen = r.w - sw - 2 * gap, vLen = hh - sw - 2 * gap;
    return {
        hSeg(r.minX + sw / 2 + gap, r.minY, hLen, sw),        // A top
        vSeg(maxX - sw, r.minY + sw / 2 + gap, vLen, sw),     // B upper-right
        vSeg(maxX - sw, midY + sw / 2 + gap, vLen, sw),       // C lower-right
        hSeg(r.minX + sw / 2 + gap, maxY - sw, hLen, sw),     // D bottom
        vSeg(r.minX, midY + sw / 2 + gap, vLen, sw),          // E lower-left
        vSeg(r.minX, r.minY + sw / 2 + gap, vLen, sw),        // F upper-left
        hSeg(r.minX + sw / 2 + gap, midY - sw / 2, hLen, sw), // G middle
    };
}

std::vector<DotSegment> classicSegments(double w, double h) {
    Inset r = digitInset(w, h);
    double sw = r.w * 0.16;
    double hh = r.h / 2, maxX = r.minX + r.w, maxY = r.minY + r.h, midY = r.minY + hh;
    struct S { bool horizontal; double x, y, len; };
    // Vertical segments define the boundaries; horizontal ones just touch them.
    const S segs[7] = {
        {true, r.minX + sw, r.minY, r.w - 2 * sw},        // A
        {false, maxX - sw, r.minY, hh},                   // B
        {false, maxX - sw, midY, hh},                     // C
        {true, r.minX + sw, maxY - sw, r.w - 2 * sw},     // D
        {false, r.minX, midY, hh},                        // E
        {false, r.minX, r.minY, hh},                      // F
        {true, r.minX + sw, midY - sw / 2, r.w - 2 * sw}, // G
    };
    std::vector<DotSegment> out;
    for (const auto& s : segs) {
        // Horizontal: 2 rows × N cols; vertical: 2 cols × N rows.
        int cols, rows;
        if (s.horizontal) { rows = 2; cols = std::max(2, static_cast<int>(s.len / (sw / 2))); }
        else { cols = 2; rows = std::max(2, static_cast<int>(s.len / (sw / 2))); }
        double cellW = s.horizontal ? s.len / cols : sw / cols;
        double cellH = s.horizontal ? sw / rows : s.len / rows;
        DotSegment d;
        d.radius = std::min(cellW, cellH) * 0.45;
        for (int row = 0; row < rows; ++row)
            for (int col = 0; col < cols; ++col)
                d.centres.push_back({s.x + (col + 0.5) * cellW, s.y + (row + 0.5) * cellH});
        out.push_back(std::move(d));
    }
    return out;
}

LedDot decimalPoint(double w, double h) {
    double size = h * 0.13;
    return {w - size * 1.1 + size / 2, h - size * 1.4 + size / 2, size};
}

} // namespace cu59
