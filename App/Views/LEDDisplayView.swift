import SwiftUI

/// 7-segment LED display for 12 digit positions (positions 2–13 of A/B registers).
/// Position 0 (leftmost) is the "C" (calculate) annunciator.
struct LEDDisplayView: View, Equatable {
    let digits:    [UInt8]   // 12 elements: A[2..13]
    let ctrl:      [UInt8]   // 12 elements: B[2..13]
    let suppressedMask: UInt16 // Bit i suppresses display index i (zero-suppression circuit from core)
    let dpPos:     UInt8
    let dpAfterglowMask: UInt16  // Bit (pos-2) for dp positions 2..13 that should be visible
    let calcIndicatorOpacity: Double
    let fontStyle: LEDFontStyle

    var body: some View {
        Canvas { ctx, size in
            let digitWidth = size.width / 12.0
            let height     = size.height

            // Style parameters and segment geometry: Shared/LedGeometry.hpp.
            let style = TIViewRules.ledStyle(fontStyle.rawValue)
            let slant = style.slant
            let geometry = LEDGeometry(fontStyle: fontStyle, width: digitWidth, height: height)

            for i in 0..<12 {
                let x = CGFloat(11 - i) * digitWidth
                let rect = CGRect(x: x, y: 0, width: digitWidth, height: height)

                let segs: UInt8
                let cOpacity: Double   // 1.0 for normal segments; fades for "C" afterglow
                if i == 11 && calcIndicatorOpacity > 0 {
                    segs = TISharedTables.segmentsC
                    cOpacity = calcIndicatorOpacity
                } else {
                    let isSuppressed = ((suppressedMask >> i) & 1) == 1
                    segs = TISharedTables.segments(forDigit: digits[i], ctrl: ctrl[i], suppressed: isSuppressed)
                    cOpacity = 1.0
                }

                // Slant transform for the digit
                var digitCtx = ctx
                digitCtx.translateBy(x: rect.minX, y: rect.minY)
                // Shear: x' = x + slant * (height - y). To fix bottom, we shift right by slant*height.
                digitCtx.concatenate(CGAffineTransform(1, 0, -slant, 1, height * slant, 0))

                drawSegments(ctx: &digitCtx, geometry: geometry, style: style, segments: segs, segmentOpacity: cOpacity)

                // Draw decimal point dot for all positions with active afterglow.
                // dpAfterglowMask includes the current dpPos, so a single bit check suffices.
                // bit i corresponds to canvas index i (dp position i+2).
                if (dpAfterglowMask >> i) & 1 == 1 {
                    var dpCtx = ctx
                    drawDecimalPoint(ctx: &dpCtx, rect: geometry.decimalPoint.offsetBy(dx: rect.minX, dy: rect.minY),
                                     style: style)
                }
            }
        }
        .background(Color(red: 0.05, green: 0.0, blue: 0.0))
    }

    // MARK: - Display character decode (B-register table)

    // Segment patterns (bit 0=A top … 6=G middle) come from
    // Shared/SevenSegment.hpp — never from a font.

    // MARK: - Drawing

    /// One digit cell's shapes, computed once per frame (Shared/LedGeometry.hpp).
    private struct LEDGeometry {
        var polygons: [Path] = []                       // modernized: segments A–G
        var segmentWidth: CGFloat = 0
        var dots: [(centres: [CGPoint], radius: CGFloat)] = []   // classic: segments A–G
        var decimalPoint: CGRect

        init(fontStyle: LEDFontStyle, width w: CGFloat, height h: CGFloat) {
            decimalPoint = TIViewRules.decimalPoint(width: w, height: h)
            if fontStyle == .classic {
                dots = TIViewRules.classicSegments(width: w, height: h).map { seg in
                    (seg.centres.map { $0.cgPoint }, seg.radius)
                }
            } else {
                segmentWidth = TIViewRules.modernizedSegmentWidth(w)
                polygons = TIViewRules.modernizedSegments(width: w, height: h).map { pts in
                    var p = Path()
                    p.addLines(pts.map { $0.cgPoint })
                    p.closeSubpath()
                    return p
                }
            }
        }
    }

    // Draw a glowing path (reusable helper for both modernized and classic styles)
    private func drawGlowingPath(ctx: inout GraphicsContext, path: Path, color: Color,
                                blurRadius: CGFloat, glowOpacity: Double, segmentOpacity: Double) {
        var glow = ctx
        glow.addFilter(.blur(radius: blurRadius))
        glow.fill(path, with: .color(color.opacity(glowOpacity * segmentOpacity)))
    }

    private func drawSegments(ctx: inout GraphicsContext, geometry: LEDGeometry, style: TILedStyle,
                              segments: UInt8, segmentOpacity: Double) {
        let activeColor = Color(red: style.activeR, green: style.activeG, blue: style.activeB)
        let inactiveColor = Color(red: style.inactiveR, green: style.inactiveG, blue: style.inactiveB,
                                  opacity: style.inactiveAlpha)
        if fontStyle == .classic {
            // Classic: each segment a grid of dots, each dot with its own glow.
            for (bit, seg) in geometry.dots.enumerated() {
                let active = (segments >> UInt8(bit)) & 1 == 1
                let color = active ? activeColor.opacity(segmentOpacity) : inactiveColor
                for c in seg.centres {
                    let dot = Path(ellipseIn: CGRect(x: c.x - seg.radius, y: c.y - seg.radius,
                                                     width: seg.radius * 2, height: seg.radius * 2))
                    if active {
                        drawGlowingPath(ctx: &ctx, path: dot, color: color, blurRadius: seg.radius * style.glowBlurPerWidth,
                                        glowOpacity: style.glowOpacity, segmentOpacity: segmentOpacity)
                    }
                    ctx.fill(dot, with: .color(color))
                }
            }
        } else {
            // Modernized: hexagonal segments with a glow and a tighter bloom.
            let sw = geometry.segmentWidth
            for (bit, path) in geometry.polygons.enumerated() {
                let active = (segments >> bit) & 1 == 1
                if active {
                    drawGlowingPath(ctx: &ctx, path: path, color: activeColor, blurRadius: sw * style.glowBlurPerWidth,
                                    glowOpacity: style.glowOpacity, segmentOpacity: segmentOpacity)
                    drawGlowingPath(ctx: &ctx, path: path, color: activeColor, blurRadius: sw * style.bloomBlurPerWidth,
                                    glowOpacity: 1.0, segmentOpacity: segmentOpacity)
                }
                ctx.fill(path, with: .color(active ? activeColor.opacity(segmentOpacity) : inactiveColor))
            }
        }
    }

    private func drawDecimalPoint(ctx: inout GraphicsContext, rect: CGRect, style: TILedStyle) {
        // The decimal point glows with the modernized parameters in both styles.
        let activeColor = Color(red: 1.0, green: 0.1, blue: 0.1)
        let path = Path(ellipseIn: rect)
        drawGlowingPath(ctx: &ctx, path: path, color: activeColor,
                        blurRadius: rect.width * TIViewRules.decimalGlowBlurPerDiameter,
                        glowOpacity: TIViewRules.decimalGlowOpacity, segmentOpacity: 1.0)
        ctx.fill(path, with: .color(activeColor))
    }
}

#Preview {
    LEDDisplayView(
        digits:        [8,8,8,8,8,8,8,8,8,8,8,8],
        ctrl:          [0,0,0,0,0,0,0,0,0,0,0,0],
        suppressedMask: 0,
        dpPos:         4,
        dpAfterglowMask: 0b0000_0000_0000_1100,  // positions 2 & 3 lit
        calcIndicatorOpacity: 1.0,
        fontStyle:     .modernized
    )
    .frame(width: 360, height: 50)
}

private extension NSValue {
    /// The boxed CGPoint (TIViewRules boxes points with @encode(CGPoint)); works on
    /// macOS and iOS alike, unlike pointValue / cgPointValue.
    var cgPoint: CGPoint {
        var p = CGPoint.zero
        getValue(&p, size: MemoryLayout<CGPoint>.size)
        return p
    }
}
