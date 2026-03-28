import SwiftUI

/// 7-segment LED display for 12 digit positions (positions 2–13 of A/B registers).
/// Position 0 (leftmost) is the "C" (calculate) annunciator.
struct LEDDisplayView: View, Equatable {
    let digits:    [UInt8]   // 12 elements: A[2..13]
    let ctrl:      [UInt8]   // 12 elements: B[2..13]
    let dpPos:     UInt8
    let calcIndicator: Bool

    var body: some View {
        Canvas { ctx, size in
            let digitWidth = size.width / 12.0
            let height     = size.height

            // Zero suppression — mirrors the TI-59 display driver's leading-zero blanking.
            // Scan right-to-left (MSD→LSD, index 11→0); `zero` tracks whether all more-
            // significant digits seen so far have been zero.
            //
            // A digit breaks the zero run (stays visible) when:
            //   - it is at index 1 (the units column immediately left of the decimal point)
            //   - it is the decimal-point column (dpPos - 2 == i)
            //   - ctrl ≥ 8  (ROM-forced display, e.g. exponent digits in scientific notation)
            //   - ctrl ≤ 1 and digit ≠ 0  (plain BCD digit mode, non-zero)
            //
            // Index 0 (leftmost — "C" annunciator position) always resets zero=true so that
            // the digit just to its right is never suppressed by the annunciator slot itself.
            //
            // A digit is suppressed when:
            //   - ctrl == 7 (blank) or ctrl == 3 (positive-sign placeholder)
            //   - ctrl ≤ 4 and digit == 0 and zero == true  (leading zero)
            var suppressed = [Bool](repeating: false, count: 12)
            var zero = true
            for i in stride(from: 11, through: 0, by: -1) {
                if i == 1 || (Int(dpPos) >= 2 && Int(dpPos) - 2 == i) || ctrl[i] >= 8 {
                    zero = false
                }
                if i == 0 { zero = true }
                if ctrl[i] == 7 || ctrl[i] == 3
                    || (ctrl[i] <= 4 && zero && digits[i] == 0) {
                    suppressed[i] = true
                } else if ctrl[i] <= 1 && digits[i] != 0 {
                    zero = false
                }
            }

            for i in 0..<12 {
                let x = CGFloat(11 - i) * digitWidth
                let rect = CGRect(x: x, y: 0, width: digitWidth, height: height)

                let segs: UInt8
                if i == 11 && calcIndicator {
                    segs = segmentsC
                } else {
                    let ch = suppressed[i] ? DisplayChar.space
                                           : displayChar(digit: digits[i], ctrl: ctrl[i])
                    segs = segmentMask(for: ch)
                }
                
                // Slant transform for the digit (around 8 degrees)
                let slant: CGFloat = 0.14
                var digitCtx = ctx
                digitCtx.translateBy(x: rect.minX, y: rect.minY)
                // Shear: x' = x + slant * (height - y). To fix bottom, we shift right by slant*height.
                digitCtx.concatenate(CGAffineTransform(1, 0, -slant, 1, height * slant, 0))
                
                let digitRect = CGRect(origin: .zero, size: rect.size)
                drawSegments(ctx: &digitCtx, rect: digitRect, segments: segs)
                
                if Int(dpPos) >= 2 && Int(dpPos) - 2 == i {
                    // Decimal point is usually NOT slanted or handled separately
                    var dpCtx = ctx
                    drawDecimalPoint(ctx: &dpCtx, rect: rect)
                }
            }
        }
        .background(Color(red: 0.05, green: 0.0, blue: 0.0))
    }

    // MARK: - Display character decode (B-register table)

    enum DisplayChar: Equatable {
        case digit(UInt8)
        case minus
        case degree
        case space
        case blank
    }

    private func displayChar(digit: UInt8, ctrl: UInt8) -> DisplayChar {
        switch ctrl {
        case 0, 1, 8, 9: return .digit(digit & 0xF)
        case 2, 3, 4:     return .space   // '"', positive sign, apostrophe
        case 5:           return digit == 0 ? .minus : .degree
        case 6:           return .minus
        case 7:           return .blank
        default:          return .blank
        }
    }

    // MARK: - 7-segment bitmasks
    // Segments: bit 0=A(top) 1=B(upper-right) 2=C(lower-right)
    //           3=D(bottom) 4=E(lower-left) 5=F(upper-left) 6=G(middle)

    private static let digitSegments: [UInt8] = [
        0b0111111, // 0: A B C D E F
        0b0000110, // 1: B C
        0b1011011, // 2: A B D E G
        0b1001111, // 3: A B C D G
        0b1100110, // 4: B C F G
        0b1101101, // 5: A C D F G
        0b1111101, // 6: A C D E F G
        0b0000111, // 7: A B C
        0b1111111, // 8: all
        0b1101111, // 9: A B C D F G
    ]

    private let segmentsC: UInt8 = 0b0111001  // A F E D — "C" shape

    private func segmentMask(for ch: DisplayChar) -> UInt8 {
        switch ch {
        case .digit(let v): return LEDDisplayView.digitSegments[Int(v) % 10]
        case .minus:        return 0b1000000 // G only
        case .degree:       return 0b1100011 // A B F G
        case .space, .blank: return 0b0000000
        }
    }

    // MARK: - Drawing

    private func drawSegments(ctx: inout GraphicsContext, rect: CGRect, segments: UInt8) {
        let padX = rect.width * 0.22
        let padY = rect.height * 0.10
        let r = rect.insetBy(dx: padX, dy: padY)
        let sw: CGFloat = r.width * 0.14   // thinner segments
        let gap: CGFloat = sw * 0.15

        // Segment paths (A–G)
        let hh = r.height / 2
        let paths: [(CGPath, Int)] = [
            (hSeg(x: r.minX + sw/2 + gap, y: r.minY,             w: r.width - sw - 2*gap, sw: sw), 0), // A top
            (vSeg(x: r.maxX - sw,        y: r.minY + sw/2 + gap, h: hh - sw - 2*gap,      sw: sw), 1), // B upper-right
            (vSeg(x: r.maxX - sw,        y: r.midY + sw/2 + gap, h: hh - sw - 2*gap,      sw: sw), 2), // C lower-right
            (hSeg(x: r.minX + sw/2 + gap, y: r.maxY - sw,        w: r.width - sw - 2*gap, sw: sw), 3), // D bottom
            (vSeg(x: r.minX,             y: r.midY + sw/2 + gap, h: hh - sw - 2*gap,      sw: sw), 4), // E lower-left
            (vSeg(x: r.minX,             y: r.minY + sw/2 + gap, h: hh - sw - 2*gap,      sw: sw), 5), // F upper-left
            (hSeg(x: r.minX + sw/2 + gap, y: r.midY - sw/2,      w: r.width - sw - 2*gap, sw: sw), 6), // G middle
        ]

        let activeColor = Color(red: 1.0, green: 0.1, blue: 0.1)
        let inactiveColor = Color(red: 0.2, green: 0.0, blue: 0.0, opacity: 0.2)

        for (path, bit) in paths {
            let active = (segments >> bit) & 1 == 1
            if active {
                var glow = ctx
                glow.addFilter(.blur(radius: sw * 0.8))
                glow.fill(Path(path), with: .color(activeColor.opacity(0.6)))
                
                var bloom = ctx
                bloom.addFilter(.blur(radius: sw * 0.2))
                bloom.fill(Path(path), with: .color(activeColor))
            }
            ctx.fill(Path(path), with: .color(active ? activeColor : inactiveColor))
        }
    }

    private func drawDecimalPoint(ctx: inout GraphicsContext, rect: CGRect) {
        let dotSize: CGFloat = rect.height * 0.13
        let dotRect = CGRect(x: rect.maxX - dotSize * 1.1,
                             y: rect.maxY - dotSize * 1.4,
                             width: dotSize, height: dotSize)
        
        let activeColor = Color(red: 1.0, green: 0.1, blue: 0.1)
        
        var glow = ctx
        glow.addFilter(.blur(radius: dotSize * 0.8))
        glow.fill(Path(ellipseIn: dotRect), with: .color(activeColor.opacity(0.6)))
        
        ctx.fill(Path(ellipseIn: dotRect), with: .color(activeColor))
    }

    // MARK: - Path helpers (hexagonal chamfered segments)

    private func hSeg(x: CGFloat, y: CGFloat, w: CGFloat, sw: CGFloat) -> CGPath {
        let c = sw * 0.5
        let p = CGMutablePath()
        p.move(to:    CGPoint(x: x + c,     y: y))
        p.addLine(to: CGPoint(x: x + w - c, y: y))
        p.addLine(to: CGPoint(x: x + w,     y: y + sw/2))
        p.addLine(to: CGPoint(x: x + w - c, y: y + sw))
        p.addLine(to: CGPoint(x: x + c,     y: y + sw))
        p.addLine(to: CGPoint(x: x,         y: y + sw/2))
        p.closeSubpath()
        return p
    }

    private func vSeg(x: CGFloat, y: CGFloat, h: CGFloat, sw: CGFloat) -> CGPath {
        let c = sw * 0.5
        let p = CGMutablePath()
        p.move(to:    CGPoint(x: x + sw/2, y: y))
        p.addLine(to: CGPoint(x: x + sw,   y: y + c))
        p.addLine(to: CGPoint(x: x + sw,   y: y + h - c))
        p.addLine(to: CGPoint(x: x + sw/2, y: y + h))
        p.addLine(to: CGPoint(x: x,        y: y + h - c))
        p.addLine(to: CGPoint(x: x,        y: y + c))
        p.closeSubpath()
        return p
    }
}

#Preview {
    LEDDisplayView(
        digits:        [8,8,8,8,8,8,8,8,8,8,8,8],
        ctrl:          [0,0,0,0,0,0,0,0,0,0,0,0],
        dpPos:         4,
        calcIndicator: true
    )
    .frame(width: 360, height: 50)
}
