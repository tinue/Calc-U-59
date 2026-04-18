import SwiftUI

/// Full calculator canvas: base image (display + empty card slot + keyboard),
/// with runtime overlays for LED display and ML-01 card.
struct KeyboardView: View {
    @Environment(EmulatorViewModel.self) var viewModel

    // Canvas native size: 2064×4075 (aspect ratio ≈ 0.5065)
    private static let imageAspect: CGFloat = 2064.0 / 4075.0

    // ── Display panel and card slot rects (canvas-space) ─────────────────

    /// LED display window — normalized to canvas size.
    /// Positioned in upper portion of maroon display panel, shifted up to avoid card overlap.
    private static let displayRect = CGRect(x: 0.0, y: 0.02,
                                             width: 1.0, height: 0.05)

    /// ML-01 card slot — normalized to canvas size.
    /// Full-width, positioned between display and keyboard.
    /// ML-01.png is 440px tall; 440 / 4075 ≈ 0.108
    private static let cardRect = CGRect(x: 0.0, y: 0.0979,
                                          width: 1.0, height: 0.1080)

    /// Keyboard section position within canvas.
    /// Keyboard image is placed at this y-offset, scaled by this factor.
    private static let kbYStart: CGFloat = 0.2324   // top of keyboard
    private static let kbYScale: CGFloat = 0.7676   // height factor

    // ── Colors ──────────────────────────────────────────────────────────

    private static let cardEdge = Color(red: 0x0A/255.0, green: 0x08/255.0, blue: 0x06/255.0)
    private static let maroon = Color(red: 0x1C/255.0, green: 0x06/255.0, blue: 0x06/255.0)

    // ── Key rects — keyboard-image space (0..1) ────────────────────────
    /// Extracted from key_rectangles.png by automated scanning (without transformation).
    /// All 9×5 = 45 keys.
    private static let keyRects: [[CGRect]] = [
        // row 0
        [CGRect(x:0.0160, y:0.2604, width:0.1245, height:0.0373), CGRect(x:0.2277, y:0.2604, width:0.1245, height:0.0373), CGRect(x:0.4375, y:0.2604, width:0.1245, height:0.0373), CGRect(x:0.6483, y:0.2604, width:0.1245, height:0.0373), CGRect(x:0.8571, y:0.2604, width:0.1245, height:0.0373)],
        // row 1
        [CGRect(x:0.0160, y:0.3463, width:0.1245, height:0.0390), CGRect(x:0.2277, y:0.3463, width:0.1245, height:0.0390), CGRect(x:0.4375, y:0.3463, width:0.1245, height:0.0390), CGRect(x:0.6483, y:0.3463, width:0.1245, height:0.0390), CGRect(x:0.8571, y:0.3463, width:0.1245, height:0.0390)],
        // row 2
        [CGRect(x:0.0160, y:0.4339, width:0.1245, height:0.0390), CGRect(x:0.2277, y:0.4339, width:0.1245, height:0.0390), CGRect(x:0.4375, y:0.4339, width:0.1245, height:0.0390), CGRect(x:0.6483, y:0.4339, width:0.1245, height:0.0390), CGRect(x:0.8571, y:0.4339, width:0.1245, height:0.0390)],
        // row 3
        [CGRect(x:0.0160, y:0.5205, width:0.1245, height:0.0390), CGRect(x:0.2277, y:0.5205, width:0.1245, height:0.0390), CGRect(x:0.4375, y:0.5205, width:0.1245, height:0.0390), CGRect(x:0.6483, y:0.5205, width:0.1245, height:0.0390), CGRect(x:0.8571, y:0.5205, width:0.1245, height:0.0390)],
        // row 4
        [CGRect(x:0.0160, y:0.6049, width:0.1245, height:0.0390), CGRect(x:0.2277, y:0.6049, width:0.1245, height:0.0390), CGRect(x:0.4375, y:0.6049, width:0.1245, height:0.0390), CGRect(x:0.6483, y:0.6049, width:0.1245, height:0.0390), CGRect(x:0.8571, y:0.6049, width:0.1279, height:0.0390)],
        // row 5
        [CGRect(x:0.0160, y:0.6920, width:0.1245, height:0.0390), CGRect(x:0.2001, y:0.6901, width:0.1623, height:0.0410), CGRect(x:0.4186, y:0.6898, width:0.1623, height:0.0412), CGRect(x:0.6371, y:0.6901, width:0.1623, height:0.0410), CGRect(x:0.8571, y:0.6901, width:0.1284, height:0.0410)],
        // row 6
        [CGRect(x:0.0160, y:0.7782, width:0.1245, height:0.0390), CGRect(x:0.2001, y:0.7767, width:0.1623, height:0.0405), CGRect(x:0.4186, y:0.7762, width:0.1623, height:0.0410), CGRect(x:0.6371, y:0.7769, width:0.1623, height:0.0402), CGRect(x:0.8571, y:0.7769, width:0.1284, height:0.0412)],
        // row 7
        [CGRect(x:0.0160, y:0.8643, width:0.1245, height:0.0390), CGRect(x:0.2001, y:0.8633, width:0.1623, height:0.0412), CGRect(x:0.4186, y:0.8628, width:0.1623, height:0.0405), CGRect(x:0.6371, y:0.8636, width:0.1623, height:0.0412), CGRect(x:0.8571, y:0.8631, width:0.1284, height:0.0412)],
        // row 8
        [CGRect(x:0.0160, y:0.9509, width:0.1245, height:0.0390), CGRect(x:0.2001, y:0.9490, width:0.1623, height:0.0415), CGRect(x:0.4186, y:0.9490, width:0.1623, height:0.0410), CGRect(x:0.6366, y:0.9490, width:0.1623, height:0.0427), CGRect(x:0.8571, y:0.9497, width:0.1289, height:0.0412)],
    ]

    // ── Key hit-test ──────────────────────────────────────────────────────

    /// Scan all 45 rects (in keyboard-image space) for the one containing (nx, ny).
    /// Non-overlapping so at most one matches.
    private static func keyAt(nx: CGFloat, ny: CGFloat) -> (Int, Int)? {
        let pt = CGPoint(x: nx, y: ny)
        for row in 0..<9 {
            for col in 0..<5 {
                if keyRects[row][col].contains(pt) { return (row, col) }
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

    #if canImport(UIKit)
    private let haptic = UIImpactFeedbackGenerator(style: .rigid)
    #endif

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
                    .overlay(alignment: .top) {
                        // Top-wash gradient: opacity 0.96→0 over top 36% of card
                        LinearGradient(stops: [
                            .init(color: Self.maroon.opacity(0.96), location: 0.00),
                            .init(color: Self.maroon.opacity(0.90), location: 0.12),
                            .init(color: Self.maroon.opacity(0.60), location: 0.24),
                            .init(color: Self.maroon.opacity(0.00), location: 0.36),
                        ], startPoint: .top, endPoint: .bottom)
                        .frame(height: cardH)
                    }
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Self.cardEdge).frame(width: cardW * 0.009)
                    }
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Self.cardEdge).frame(width: cardW * 0.009)
                    }
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Self.cardEdge).frame(height: cardH * 0.03)
                    }
                    .position(x: cardW / 2, y: cardY + cardH / 2)

                // ── LED display ─────────────────────────────────────────
                LEDDisplayView(
                    digits:        viewModel.displayDigits,
                    ctrl:          viewModel.displayCtrl,
                    dpPos:         viewModel.dpPos,
                    calcIndicatorOpacity: viewModel.calcIndicatorOpacity
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
                                guard kbNy >= 0 && kbNy <= 1 else {
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
                                #if canImport(UIKit)
                                haptic.impactOccurred()
                                #endif
                            }
                            .onEnded { _ in
                                if let prev = pressedKey {
                                    viewModel.releaseKey(row: prev / 5, col: prev % 5)
                                }
                                pressedKey = nil
                            }
                    )

                // ── Press highlight ─────────────────────────────────────
                // keyRects are in keyboard-image space; convert to canvas space for rendering
                if let pk = pressedKey {
                    let r = Self.keyRects[pk / 5][pk % 5]
                    let canvasY = Self.kbYStart + r.midY * Self.kbYScale
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.35))
                        .frame(width:  w * r.width,
                               height: h * r.height * Self.kbYScale)
                        .position(x: w * r.midX,
                                  y: h * canvasY)
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
