#pragma once
#include <cstdint>
#include <vector>

// Geometry of the 12-digit LED display, shared so every frontend draws the
// same segment shapes; each frontend does its own painting (shear, glow,
// bloom). See reference/SharedArchitecture.md § "LED Display Rendering".
//
// Coordinates are in one digit cell (origin top-left, width w, height h),
// before the per-digit shear. Cell i (0 = rightmost) sits at x = (11 − i) × w;
// cell 11 also carries the "C" annunciator.

namespace cu59 {

enum class LedStyle { Modernized = 0, Classic = 1 };  ///< settings value "ledFontStyle"

struct LedPoint { double x, y; };

struct LedStyleParams {
    double slant;                 ///< shear x' = x + slant × (h − y): bottom fixed
    double activeR, activeG, activeB;
    double inactiveR, inactiveG, inactiveB, inactiveAlpha;
    double glowBlurPerWidth;      ///< glow blur radius per segment width (classic: per dot radius)
    double glowOpacity;
    double bloomBlurPerWidth;     ///< modernized only: second, tighter glow at full opacity
};
const LedStyleParams& ledStyleParams(LedStyle style);

/// Modernized: one hexagonal chamfered polygon per segment A–G (bit 0–6).
std::vector<std::vector<LedPoint>> modernizedSegments(double w, double h);
/// Width of a modernized segment (the glow radii scale with it).
double modernizedSegmentWidth(double w);

/// Classic: each segment A–G as a grid of dots (centres) of one radius.
struct DotSegment { std::vector<LedPoint> centres; double radius; };
std::vector<DotSegment> classicSegments(double w, double h);

/// Decimal point of a cell, drawn unsheared: centre and diameter.
struct LedDot { double cx, cy, diameter; };
LedDot decimalPoint(double w, double h);

/// The decimal point's glow uses the modernized parameters in both styles.
inline constexpr double kDecimalGlowBlurPerDiameter = 0.8;
inline constexpr double kDecimalGlowOpacity = 0.6;
/// Display background (dark red-black).
inline constexpr double kLedBackgroundR = 0.05, kLedBackgroundG = 0.0, kLedBackgroundB = 0.0;

} // namespace cu59
