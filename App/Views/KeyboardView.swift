import SwiftUI
import AudioToolbox

/// Full calculator canvas: base image (display + empty card slot + keyboard),
/// with runtime overlays for LED display and ML-01 card.
struct KeyboardView: View {
    @Environment(EmulatorViewModel.self) var viewModel

    // Canvas native size: 2064×4075 (aspect ratio ≈ 0.5065)
    private static let imageAspect: CGFloat = 2064.0 / 4075.0

    // ── Display panel and card slot rects (canvas-space) ─────────────────

    /// LED display window — normalized to canvas size.
    /// Positioned in upper portion of maroon display panel, shifted up to avoid card overlap.
    private static let displayRect = CGRect(x: 0.0, y: 0.052,
                                             width: 1.0, height: 0.05)

    /// ML-01 card slot — normalized to canvas size.
    /// Full-width, positioned between display and keyboard.
    /// ML-01.png is 440px tall; 440 / 4075 ≈ 0.108
    private static let cardRect = CGRect(x: 0.0, y: 0.11,
                                          width: 1.0, height: 0.1080)

    /// Keyboard section position within canvas.
    /// Keyboard image is placed at this y-offset, scaled by this factor.
    private static let kbYStart: CGFloat = 0.2324   // top of keyboard
    private static let kbYScale: CGFloat = 0.7676   // height factor

    // ── Colors ──────────────────────────────────────────────────────────

    private static let cardEdge = Color(red: 0x0A/255.0, green: 0x08/255.0, blue: 0x06/255.0)
    private static let maroon = Color(red: 0x1C/255.0, green: 0x06/255.0, blue: 0x06/255.0)

    // ── Key rects — keyboard-image space (0..1) ────────────────────────
    /// Extracted from key_rectangles.png, converted to keyboard-image-space coords.
    /// All 9×5 = 45 keys.
    private static let keyRects: [[CGRect]] = [
        // row 0
        [CGRect(x:0.0160, y:0.0365, width:0.1245, height:0.0486), CGRect(x:0.2277, y:0.0365, width:0.1245, height:0.0486), CGRect(x:0.4375, y:0.0365, width:0.1245, height:0.0486), CGRect(x:0.6483, y:0.0365, width:0.1245, height:0.0486), CGRect(x:0.8571, y:0.0365, width:0.1245, height:0.0486)],
        // row 1
        [CGRect(x:0.0140, y:0.1484, width:0.1265, height:0.0508), CGRect(x:0.2277, y:0.1484, width:0.1245, height:0.0508), CGRect(x:0.4375, y:0.1484, width:0.1245, height:0.0508), CGRect(x:0.6483, y:0.1484, width:0.1245, height:0.0508), CGRect(x:0.8566, y:0.1484, width:0.1250, height:0.0508)],
        // row 2
        [CGRect(x:0.0160, y:0.2625, width:0.1245, height:0.0508), CGRect(x:0.2277, y:0.2625, width:0.1245, height:0.0508), CGRect(x:0.4375, y:0.2625, width:0.1245, height:0.0508), CGRect(x:0.6483, y:0.2625, width:0.1245, height:0.0508), CGRect(x:0.8571, y:0.2625, width:0.1245, height:0.0508)],
        // row 3
        [CGRect(x:0.0160, y:0.3753, width:0.1245, height:0.0508), CGRect(x:0.2277, y:0.3753, width:0.1245, height:0.0508), CGRect(x:0.4375, y:0.3753, width:0.1245, height:0.0508), CGRect(x:0.6483, y:0.3753, width:0.1245, height:0.0508), CGRect(x:0.8571, y:0.3753, width:0.1245, height:0.0508)],
        // row 4
        [CGRect(x:0.0160, y:0.4853, width:0.1245, height:0.0508), CGRect(x:0.2277, y:0.4853, width:0.1245, height:0.0508), CGRect(x:0.4375, y:0.4853, width:0.1245, height:0.0508), CGRect(x:0.6483, y:0.4853, width:0.1245, height:0.0508), CGRect(x:0.8566, y:0.4853, width:0.1284, height:0.0508)],
        // row 5
        [CGRect(x:0.0155, y:0.5987, width:0.1250, height:0.0508), CGRect(x:0.2001, y:0.5963, width:0.1623, height:0.0534), CGRect(x:0.4186, y:0.5959, width:0.1623, height:0.0537), CGRect(x:0.6366, y:0.5963, width:0.1628, height:0.0534), CGRect(x:0.8566, y:0.5963, width:0.1289, height:0.0534)],
        // row 6
        [CGRect(x:0.0160, y:0.7110, width:0.1245, height:0.0508), CGRect(x:0.2001, y:0.7091, width:0.1623, height:0.0528), CGRect(x:0.4186, y:0.7084, width:0.1623, height:0.0534), CGRect(x:0.6366, y:0.7094, width:0.1628, height:0.0524), CGRect(x:0.8566, y:0.7091, width:0.1289, height:0.0528)],
        // row 7
        [CGRect(x:0.0160, y:0.8232, width:0.1245, height:0.0508), CGRect(x:0.2001, y:0.8219, width:0.1623, height:0.0537), CGRect(x:0.4186, y:0.8213, width:0.1623, height:0.0528), CGRect(x:0.6371, y:0.8223, width:0.1623, height:0.0537), CGRect(x:0.8566, y:0.8217, width:0.1289, height:0.0537)],
        // row 8
        [CGRect(x:0.0160, y:0.9360, width:0.1245, height:0.0508), CGRect(x:0.2001, y:0.9336, width:0.1623, height:0.0541), CGRect(x:0.4186, y:0.9336, width:0.1623, height:0.0534), CGRect(x:0.6366, y:0.9336, width:0.1623, height:0.0556), CGRect(x:0.8566, y:0.9340, width:0.1294, height:0.0557)],
    ]

    // ── Key hit-test ──────────────────────────────────────────────────────

    /// Expand each key rect horizontally for hit-testing.
    /// **Tunable: 0.15 = add 15% of width left AND right**
    private static let hitTestExpansionHorizontal: CGFloat = 0.15

    /// Expand each key rect vertically for hit-testing.
    /// **Tunable: 0.35 = add 35% of height top AND bottom**
    private static let hitTestExpansionVertical: CGFloat = 0.35

    /// Get the expanded detection rect for a key (in keyboard-image space)
    private static func expandedKeyRect(row: Int, col: Int) -> CGRect {
        let rect = keyRects[row][col]
        let expandWidth = rect.width * hitTestExpansionHorizontal
        let expandHeight = rect.height * hitTestExpansionVertical
        return CGRect(
            x: rect.minX - expandWidth,
            y: rect.minY - expandHeight,
            width: rect.width + expandWidth * 2,
            height: rect.height + expandHeight * 2
        )
    }

    /// Scan all 45 rects (in keyboard-image space) for the one containing (nx, ny).
    /// Rects are expanded independently on horizontal/vertical axes. At most one matches unless rects overlap.
    private static func keyAt(nx: CGFloat, ny: CGFloat) -> (Int, Int)? {
        let pt = CGPoint(x: nx, y: ny)
        for row in 0..<9 {
            for col in 0..<5 {
                if expandedKeyRect(row: row, col: col).contains(pt) { return (row, col) }
            }
        }
        return nil
    }

    private var canvasImageName: String {
        switch viewModel.model {
        case .ti59:         return "ti59_base"
        case .ti58, .ti58c: return "ti58_base"
        }
    }

    @State private var pressedKey: Int? = nil   // physRow * 5 + physCol
    @AppStorage(SettingsKey.ledFontStyle) private var ledFontStyleRaw: Int = LEDFontStyle.modernized.rawValue

    private var fontStyle: LEDFontStyle {
        LEDFontStyle(rawValue: ledFontStyleRaw) ?? .modernized
    }

    #if canImport(UIKit)
    private let haptic = UIImpactFeedbackGenerator(style: .rigid)
    #endif

    private func triggerFeedback() {
        #if os(iOS)
        let feedbackType = AppSettings.resolvedKeyboardFeedback()
        switch feedbackType {
        case .off:
            // No feedback
            break
        case .haptic:
            haptic.impactOccurred()
        case .click:
            playClickSound()
        }
        #endif
        // macOS: No audio feedback
    }

    private func playClickSound() {
        // iOS only: Use system UI click sound
        #if os(iOS)
        AudioServicesPlaySystemSound(1104)
        #endif
    }

    // ── Body ───────────────────────────────────────────────────────────────

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Base canvas: display panel, empty card slot, keyboard
            Image(canvasImageName)
                .resizable()
                .scaledToFill()

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                // ── ML-01 card overlay ──────────────────────────────────
                let cardW = w
                let cardH = h * Self.cardRect.height
                let cardY = h * Self.cardRect.minY

                Image("ML01")
                    .resizable()
                    .frame(width: cardW, height: cardH)
                    .background(Color(red: 29.0/255.0, green: 29.0/255.0, blue: 28.0/255.0))
                    .overlay(alignment: .top) {
                        // Top-wash: uniform dark overlay
                        Rectangle()
                            .fill(Color(red: 0.1, green: 0.02, blue: 0.02).opacity(0.95))
                            .frame(height: cardH * 0.28)
                    }
                    .position(x: cardW / 2, y: cardY + cardH / 2)

                // ── LED display ─────────────────────────────────────────
                LEDDisplayView(
                    digits:        viewModel.displayDigits,
                    ctrl:          viewModel.displayCtrl,
                    dpPos:         viewModel.dpPos,
                    calcIndicatorOpacity: viewModel.calcIndicatorOpacity,
                    fontStyle:     fontStyle
                )
                .equatable()
                .frame(width:  w * Self.displayRect.width,
                       height: h * Self.displayRect.height)
                .position(x: w * Self.displayRect.midX,
                          y: h * Self.displayRect.midY)

                // ── Key hit-testing ─────────────────────────────────────
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let nx = value.location.x / w
                                let ny = value.location.y / h
                                // Convert canvas coords → keyboard-image coords
                                let kbNy = (ny - Self.kbYStart) / Self.kbYScale
                                // Allow margin for vertical expansion (20% of max key height ≈ 0.015)
                                let verticalMargin: CGFloat = 0.025
                                guard kbNy >= -verticalMargin && kbNy <= 1 + verticalMargin else {
                                    if let prev = pressedKey {
                                        viewModel.releaseKey(row: prev / 5, col: prev % 5)
                                        pressedKey = nil
                                    }
                                    return
                                }
                                guard let (row, col) = Self.keyAt(nx: nx, ny: kbNy) else { return }
                                let keyID = row * 5 + col
                                guard pressedKey != keyID else { return }
                                if let prev = pressedKey {
                                    viewModel.releaseKey(row: prev / 5, col: prev % 5)
                                }
                                pressedKey = keyID
                                viewModel.pressKey(row: row, col: col)
                                triggerFeedback()
                            }
                            .onEnded { _ in
                                if let prev = pressedKey {
                                    viewModel.releaseKey(row: prev / 5, col: prev % 5)
                                }
                                pressedKey = nil
                            }
                    )

                // ── Press highlight ─────────────────────────────────────
                // Simulate key press: shift key down-right and expose black background
                if let pk = pressedKey {
                    let r = Self.keyRects[pk / 5][pk % 5]
                    let keyW = w * r.width
                    let keyH = h * r.height * Self.kbYScale
                    let canvasX = w * r.minX
                    let canvasY = h * (Self.kbYStart + r.minY * Self.kbYScale)
                    let shiftX: CGFloat = 3    // tunable: shift right (points)
                    let shiftY: CGFloat = 3    // tunable: shift down (points)

                    // Layer 1 — black fill at original key position (erases the key)
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: keyW, height: keyH)
                        .position(x: canvasX + keyW / 2,
                                  y: canvasY + keyH / 2)
                        .allowsHitTesting(false)

                    // Layer 2 — key region of base image, shifted down-right
                    // Crop the image to show only the key rect, then position it shifted
                    Image(canvasImageName)
                        .resizable()
                        .frame(width: w, height: h)
                        .offset(x: -canvasX, y: -canvasY)   // align key's top-left to frame origin
                        .frame(width: keyW, height: keyH,
                               alignment: .topLeading)
                        .clipped()
                        .position(x: canvasX + keyW / 2 + shiftX,
                                  y: canvasY + keyH / 2 + shiftY)
                        .allowsHitTesting(false)
                }
            }
        }
        .aspectRatio(Self.imageAspect, contentMode: .fit)
    }
}

#Preview {
    KeyboardView()
        .environment(EmulatorViewModel())
        .background(Color(white: 0.08))
}
