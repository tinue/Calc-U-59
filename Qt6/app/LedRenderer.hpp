#pragma once
#include "FrameSampler.hpp"
#include "LedGeometry.hpp"
#include <QRectF>

class QPainter;

// Paints the 12-digit LED display: Shared/SevenSegment patterns on
// Shared/LedGeometry shapes, sheared per digit, with a blurred glow (and, in
// the modernized style, a tighter bloom) under the crisp segments. Each digit
// and decimal point is drawn at its LedFrame brightness (Shared/DisplayPov).
// The counterpart of App/Views/LEDDisplayView.swift.
namespace LedRenderer {

void paint(QPainter& p, const QRectF& rect, const cu59::LedFrame& display, double calcIndicatorOpacity,
           cu59::LedStyle style);

} // namespace LedRenderer
