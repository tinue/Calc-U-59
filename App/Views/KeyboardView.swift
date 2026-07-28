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

    /// Whether physical keypresses go to the calculator. Only consumed on macOS,
    /// where the calculator shares the window with the printer and debug panels —
    /// see `PhysicalKeyboardModifier` below.
    @FocusState private var isKeyboardFocused: Bool

    private func releaseHeldKey() {
        if let prev = pressedKey {
            viewModel.releaseKey(row: prev / 5, col: prev % 5)
            pressedKey = nil
        }
    }

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

                // ── Cue card overlay ────────────────────────────────────
                let cardW = w
                let cardH = h * Self.cardRect.height
                let cardY = h * Self.cardRect.minY

                CueCardView(content: viewModel.cueCardContent)
                    .frame(width: cardW, height: cardH)
                    .position(x: cardW / 2, y: cardY + cardH / 2)

                // ── LED display ─────────────────────────────────────────
                LEDDisplayView(
                    digits:        viewModel.displayDigits,
                    ctrl:          viewModel.displayCtrl,
                    suppressedMask: viewModel.displaySuppressedMask,
                    dpPos:         viewModel.dpPos,
                    dpAfterglowMask: viewModel.dpAfterglowMask,
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
                                // Touching the calculator claims physical-keyboard
                                // focus back from whichever panel had it. The drag
                                // gesture consumes the click, so relying on
                                // .focusable()'s own click-to-focus isn't enough.
                                isKeyboardFocused = true

                                let nx = value.location.x / w
                                let ny = value.location.y / h

                                // Check if press is on display area
                                let isOnDisplay = nx >= Self.displayRect.minX && nx <= Self.displayRect.maxX &&
                                                ny >= Self.displayRect.minY && ny <= Self.displayRect.maxY
                                if isOnDisplay {
                                    if !viewModel.isDisplayPressed {
                                        viewModel.isDisplayPressed = true
                                        viewModel.isFullSpeedMode = true
                                        releaseHeldKey()
                                    }
                                    return
                                }

                                // Release display press if moving to keyboard
                                if viewModel.isDisplayPressed {
                                    viewModel.isDisplayPressed = false
                                    viewModel.isFullSpeedMode = false
                                }

                                // Convert canvas coords → keyboard-image coords
                                let kbNy = (ny - Self.kbYStart) / Self.kbYScale
                                // Allow margin for vertical expansion (20% of max key height ≈ 0.015)
                                let verticalMargin: CGFloat = 0.025
                                guard kbNy >= -verticalMargin && kbNy <= 1 + verticalMargin else {
                                    releaseHeldKey()
                                    return
                                }
                                guard let (row, col) = Self.keyAt(nx: nx, ny: kbNy) else { return }
                                let keyID = row * 5 + col
                                guard pressedKey != keyID else { return }
                                releaseHeldKey()
                                pressedKey = keyID
                                viewModel.pressKey(row: row, col: col)
                                triggerFeedback()
                            }
                            .onEnded { _ in
                                viewModel.isDisplayPressed = false
                                viewModel.isFullSpeedMode = false
                                releaseHeldKey()
                            }
                    )

                // ── Press highlight ─────────────────────────────────────
                // Simulate key press: shift key down-right and expose black background.
                // Physical-keyboard presses light the same highlight, so a typed key
                // looks exactly like a clicked one.
                if let pk = pressedKey ?? viewModel.keyboardHeldKey {
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
        .physicalKeyboard(viewModel: viewModel, focus: $isKeyboardFocused)
        .onDisappear {
            // If this view is torn down mid-gesture (e.g. rapid panel switching),
            // the DragGesture's onEnded never fires. Force-release any held key
            // so its matrix bit doesn't stay stuck set in the emulator core.
            releaseHeldKey()
            viewModel.keyboardRelease()
            viewModel.isDisplayPressed = false
            viewModel.isFullSpeedMode = false
        }
    }
}

// MARK: - Physical keyboard (macOS)

private extension View {
    /// Route physical key presses to the calculator, on the platforms that have a
    /// keyboard to route. No-op off macOS: iOS/iPadOS is deliberately out of
    /// scope (see `reference/AppArchitecture.md` § "Physical Keyboard Mapping").
    @ViewBuilder
    func physicalKeyboard(viewModel: EmulatorViewModel, focus: FocusState<Bool>.Binding) -> some View {
        #if os(macOS)
        modifier(PhysicalKeyboardModifier(viewModel: viewModel, focus: focus))
        #else
        self
        #endif
    }
}

#if os(macOS)
/// Makes the calculator focusable and feeds key-down/key-up to the emulator.
///
/// Focus-scoped on purpose: the Mac window shows the calculator, the printer and
/// the debug panels side by side, so keys must only reach the calculator while it
/// is the focused panel — otherwise arrow keys meant for the CPU inspector's
/// instruction list would also step the program. The calculator takes focus on
/// appear, so typing works immediately at launch.
private struct PhysicalKeyboardModifier: ViewModifier {
    let viewModel: EmulatorViewModel
    let focus: FocusState<Bool>.Binding

    private var isFocused: Bool { focus.wrappedValue }

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused(focus)
            .overlay {
                // The only cue that keys go here rather than to the debug panel.
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.orange.opacity(isFocused ? 0.35 : 0), lineWidth: 1.5)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.15), value: isFocused)
            }
            .onAppear { focus.wrappedValue = true }
            .onChange(of: isFocused) { _, focused in
                // Losing focus mid-press would otherwise leave the matrix bit set.
                if !focused { viewModel.keyboardRelease() }
            }
            // Subscribing to .down and .up only — auto-repeat arrives as .repeat
            // and is dropped here, which is what we want: the matrix bit is a
            // level, so a held key can never re-trigger and repeats would only
            // produce spurious releases.
            .onKeyPress(phases: [.down, .up]) { keyPress in
                switch keyPress.phase {
                case .down:
                    guard let codes = TI59KeyboardMap.matrixCodes(for: keyPress) else { return .ignored }
                    viewModel.keyboardKeyDown(codes)
                    return .handled
                case .up:
                    guard TI59KeyboardMap.matrixCodes(for: keyPress) != nil else { return .ignored }
                    viewModel.keyboardKeyUp()
                    return .handled
                default:
                    return .ignored
                }
            }
    }
}
#endif

#Preview {
    KeyboardView()
        .environment(EmulatorViewModel())
        .background(Color(white: 0.08))
}
