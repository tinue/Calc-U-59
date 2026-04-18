import SwiftUI

/// Full calculator canvas: base image (display + empty card slot + keyboard),
/// with runtime overlays for LED display and ML-01 card.
struct KeyboardView: View {
    @Environment(EmulatorViewModel.self) var viewModel

    // Canvas native size: 2064×4066 (aspect ratio ≈ 0.5076)
    private static let imageAspect: CGFloat = 2064.0 / 4066.0

    // ── Display panel and card slot rects (canvas-space) ─────────────────

    /// LED display window — normalized to canvas size.
    /// Extracted from reference image (white rectangle overlay on exact LED area).
    private static let displayRect = CGRect(x: 0.05, y: 0.06,
                                             width: 0.85, height: 0.05)

    /// ML-01 card slot — normalized to canvas size.
    /// Full-width, positioned between display and keyboard.
    private static let cardRect = CGRect(x: 0, y: 0.1557,
                                          width: 1.0, height: 0.1166)

    /// Keyboard section position within canvas.
    /// Keyboard image is placed at this y-offset, scaled by this factor.
    private static let kbYStart: CGFloat = 0.2723   // top of keyboard
    private static let kbYScale: CGFloat = 0.7051   // height factor

    // ── Colors ──────────────────────────────────────────────────────────

    private static let cardEdge = Color(red: 0x0A/255.0, green: 0x08/255.0, blue: 0x06/255.0)
    private static let maroon = Color(red: 0x1C/255.0, green: 0x06/255.0, blue: 0x06/255.0)

    // ── Key rects — keyboard-image space (0..1) ────────────────────────
    /// Extracted from user-corrected key_validation.png, converted to keyboard-image coords.
    /// All 9×5 = 45 keys.
    private static let keyRects: [[CGRect]] = [
        // row 0  (A, B, C, D, E)
        [CGRect(x:0.0552, y:0.0484, width:0.1153, height:0.0495), CGRect(x:0.2495, y:0.0484, width:0.1153, height:0.0495), CGRect(x:0.4423, y:0.0484, width:0.1153, height:0.0495), CGRect(x:0.6371, y:0.0484, width:0.1153, height:0.0495), CGRect(x:0.8270, y:0.0484, width:0.1153, height:0.0495)],
        // row 1  (2nd, INV, lnx, CE, CLR)
        [CGRect(x:0.0552, y:0.1611, width:0.1153, height:0.0495), CGRect(x:0.2495, y:0.1611, width:0.1153, height:0.0495), CGRect(x:0.4423, y:0.1611, width:0.1153, height:0.0495), CGRect(x:0.6371, y:0.1611, width:0.1153, height:0.0495), CGRect(x:0.8270, y:0.1611, width:0.1153, height:0.0495)],
        // row 2  (LRN, x≷t, x², √x, 1/x)
        [CGRect(x:0.0552, y:0.2734, width:0.1153, height:0.0495), CGRect(x:0.2495, y:0.2734, width:0.1153, height:0.0495), CGRect(x:0.4423, y:0.2734, width:0.1153, height:0.0495), CGRect(x:0.6371, y:0.2734, width:0.1153, height:0.0495), CGRect(x:0.8270, y:0.2734, width:0.1153, height:0.0495)],
        // row 3  (SST, STO, RCL, SUM, y^x)
        [CGRect(x:0.0552, y:0.3843, width:0.1153, height:0.0495), CGRect(x:0.2495, y:0.3843, width:0.1153, height:0.0495), CGRect(x:0.4423, y:0.3843, width:0.1153, height:0.0495), CGRect(x:0.6371, y:0.3843, width:0.1153, height:0.0495), CGRect(x:0.8270, y:0.3843, width:0.1153, height:0.0495)],
        // row 4  (BST, EE, (, ), ÷)
        [CGRect(x:0.0552, y:0.4952, width:0.1153, height:0.0495), CGRect(x:0.2495, y:0.4952, width:0.1153, height:0.0495), CGRect(x:0.4423, y:0.4952, width:0.1153, height:0.0495), CGRect(x:0.6371, y:0.4952, width:0.1153, height:0.0495), CGRect(x:0.8270, y:0.4963, width:0.1182, height:0.0520)],
        // row 5  (GTO, 7, 8, 9, ×) — cols 1–3 wider
        [CGRect(x:0.0552, y:0.6090, width:0.1153, height:0.0495), CGRect(x:0.2263, y:0.6079, width:0.1478, height:0.0523), CGRect(x:0.4259, y:0.6090, width:0.1478, height:0.0523), CGRect(x:0.6255, y:0.6090, width:0.1478, height:0.0523), CGRect(x:0.8266, y:0.6062, width:0.1192, height:0.0551)],
        // row 6  (SBR, 4, 5, 6, −) — cols 1–3 wider
        [CGRect(x:0.0552, y:0.7241, width:0.1153, height:0.0495), CGRect(x:0.2263, y:0.7209, width:0.1478, height:0.0527), CGRect(x:0.4259, y:0.7209, width:0.1478, height:0.0527), CGRect(x:0.6255, y:0.7213, width:0.1478, height:0.0523), CGRect(x:0.8256, y:0.7213, width:0.1182, height:0.0551)],
        // row 7  (RST, 1, 2, 3, +) — cols 1–3 wider
        [CGRect(x:0.0552, y:0.8378, width:0.1153, height:0.0495), CGRect(x:0.2263, y:0.8332, width:0.1478, height:0.0544), CGRect(x:0.4259, y:0.8329, width:0.1478, height:0.0544), CGRect(x:0.6255, y:0.8329, width:0.1478, height:0.0544), CGRect(x:0.8275, y:0.8332, width:0.1187, height:0.0551)],
        // row 8  (R/S, 0, ., ±, =) — cols 1–3 wider
        [CGRect(x:0.0552, y:0.9511, width:0.1153, height:0.0495), CGRect(x:0.2263, y:0.9455, width:0.1478, height:0.0544), CGRect(x:0.4259, y:0.9459, width:0.1478, height:0.0544), CGRect(x:0.6255, y:0.9455, width:0.1478, height:0.0544), CGRect(x:0.8275, y:0.9455, width:0.1187, height:0.0551)],
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
