import SwiftUI

/// Full calculator face: model-specific canvas image as background, LED display overlay,
/// and invisible tap targets mapped to the 5×9 hardware key matrix.
struct KeyboardView: View {
    @Environment(EmulatorViewModel.self) var viewModel

    // Image native size: 1200×2321  (aspect ratio ≈ 0.5170)
    private static let imageAspect: CGFloat = 1200.0 / 2321.0

    // ── Normalized rects relative to image size ────────────────────────────────

    /// LED display window blacked out in the artwork (auto-detected from red pixels).
    private static let displayRect = CGRect(x: 0.1605, y: 0.0948, width: 0.6800, height: 0.0349)

    /// 9 rows × 5 cols — key body rects measured from refs/KeyAreas.png,
    /// mapped onto the canvas images (1200×2321) coordinate space.
    /// Rows 5–8 cols 1–3 are wider (physical number keys).
    private static let keyRects: [[CGRect]] = [
        // row 0
        [CGRect(x:0.1317, y:0.3309, width:0.0967, height:0.0319), CGRect(x:0.2900, y:0.3309, width:0.0975, height:0.0323), CGRect(x:0.4500, y:0.3309, width:0.0975, height:0.0323), CGRect(x:0.6108, y:0.3309, width:0.0975, height:0.0327), CGRect(x:0.7658, y:0.3309, width:0.0975, height:0.0327)],
        // row 1
        [CGRect(x:0.1317, y:0.3964, width:0.0975, height:0.0327), CGRect(x:0.2900, y:0.3968, width:0.0975, height:0.0323), CGRect(x:0.4500, y:0.3964, width:0.0975, height:0.0323), CGRect(x:0.6108, y:0.3968, width:0.0975, height:0.0323), CGRect(x:0.7658, y:0.3964, width:0.0975, height:0.0323)],
        // row 2
        [CGRect(x:0.1308, y:0.4645, width:0.0975, height:0.0323), CGRect(x:0.2892, y:0.4645, width:0.0975, height:0.0323), CGRect(x:0.4500, y:0.4645, width:0.0975, height:0.0323), CGRect(x:0.6100, y:0.4645, width:0.0975, height:0.0323), CGRect(x:0.7658, y:0.4645, width:0.0975, height:0.0323)],
        // row 3
        [CGRect(x:0.1317, y:0.5321, width:0.0975, height:0.0323), CGRect(x:0.2892, y:0.5317, width:0.0975, height:0.0323), CGRect(x:0.4500, y:0.5317, width:0.0975, height:0.0323), CGRect(x:0.6100, y:0.5317, width:0.0975, height:0.0323), CGRect(x:0.7658, y:0.5317, width:0.0975, height:0.0323)],
        // row 4
        [CGRect(x:0.1317, y:0.5963, width:0.0975, height:0.0323), CGRect(x:0.2900, y:0.5963, width:0.0975, height:0.0323), CGRect(x:0.4492, y:0.5963, width:0.0975, height:0.0323), CGRect(x:0.6100, y:0.5963, width:0.0975, height:0.0323), CGRect(x:0.7658, y:0.5963, width:0.0975, height:0.0323)],
        // row 5  (cols 1–3 wider: number keys 7/8/9)
        [CGRect(x:0.1317, y:0.6626, width:0.0975, height:0.0323), CGRect(x:0.2742, y:0.6626, width:0.1192, height:0.0323), CGRect(x:0.4383, y:0.6626, width:0.1208, height:0.0327), CGRect(x:0.6000, y:0.6626, width:0.1200, height:0.0327), CGRect(x:0.7658, y:0.6626, width:0.0975, height:0.0323)],
        // row 6  (cols 1–3 wider: number keys 4/5/6)
        [CGRect(x:0.1308, y:0.7307, width:0.0975, height:0.0323), CGRect(x:0.2783, y:0.7307, width:0.1208, height:0.0332), CGRect(x:0.4383, y:0.7307, width:0.1208, height:0.0327), CGRect(x:0.5992, y:0.7307, width:0.1200, height:0.0327), CGRect(x:0.7658, y:0.7307, width:0.0975, height:0.0323)],
        // row 7  (cols 1–3 wider: number keys 1/2/3)
        [CGRect(x:0.1317, y:0.7971, width:0.0975, height:0.0323), CGRect(x:0.2733, y:0.7966, width:0.1200, height:0.0327), CGRect(x:0.4392, y:0.7966, width:0.1200, height:0.0327), CGRect(x:0.6000, y:0.7966, width:0.1200, height:0.0327), CGRect(x:0.7658, y:0.7971, width:0.0975, height:0.0323)],
        // row 8  (cols 1–3 wider: number keys 0/./+/-)
        [CGRect(x:0.1317, y:0.8647, width:0.0975, height:0.0323), CGRect(x:0.2733, y:0.8643, width:0.1200, height:0.0332), CGRect(x:0.4392, y:0.8604, width:0.1200, height:0.0327), CGRect(x:0.5983, y:0.8643, width:0.1200, height:0.0332), CGRect(x:0.7658, y:0.8647, width:0.0975, height:0.0323)],
    ]

    // ── Key hit-test ──────────────────────────────────────────────────────────

    /// Scan all 45 rects for the one containing (nx, ny). Non-overlapping so at most one matches.
    private static func keyAt(nx: CGFloat, ny: CGFloat) -> (Int, Int)? {
        let pt = CGPoint(x: nx, y: ny)
        for row in 0..<9 {
            for col in 0..<5 {
                if keyRects[row][col].contains(pt) { return (row, col) }
            }
        }
        return nil
    }

    private var keyboardImageName: String {
        switch viewModel.model {
        case .ti59:  return "ti59_canvas"
        case .ti58:  return "ti58_canvas"
        case .ti58c: return "ti58c_canvas"
        }
    }

    @State private var pressedKey: Int? = nil   // physRow * 5 + physCol

    #if canImport(UIKit)
    private let haptic = UIImpactFeedbackGenerator(style: .rigid)
    #endif

    // ── Body ───────────────────────────────────────────────────────────────────

    var body: some View {
        // Fix the ZStack to the image's aspect ratio so geometry inside is exact.
        ZStack(alignment: .topLeading) {
            Image(keyboardImageName)
                .resizable()
                .scaledToFill()

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                // Display overlay
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

                // Single gesture over entire view — hit-tests by scanning key rects
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let nx = value.location.x / w
                                let ny = value.location.y / h
                                guard let (row, col) = Self.keyAt(nx: nx, ny: ny) else { return }
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

                // Press highlight — matches the key rect exactly
                if let pk = pressedKey {
                    let r = Self.keyRects[pk / 5][pk % 5]
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.35))
                        .frame(width: w * r.width, height: h * r.height)
                        .position(x: w * r.midX, y: h * r.midY)
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
