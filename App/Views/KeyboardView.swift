import SwiftUI
import AudioToolbox

/// Full calculator canvas: base image (display + empty card slot + keyboard),
/// with runtime overlays for LED display and ML-01 card.
struct KeyboardView: View {
    @Environment(EmulatorViewModel.self) var viewModel

    // Canvas geometry (2064×4075 base image, display/card overlays, keyboard
    // section) lives in Shared/KeyboardLayout.hpp; rects are normalized.
    private static let imageAspect: CGFloat = TISharedTables.canvasAspect
    private static let displayRect = TISharedTables.displayRect
    private static let cardRect = TISharedTables.cardRect
    private static let kbYStart: CGFloat = TISharedTables.keyboardYStart
    private static let kbYScale: CGFloat = TISharedTables.keyboardYScale

    // ── Colors ──────────────────────────────────────────────────────────

    private static let cardEdge = Color(red: 0x0A/255.0, green: 0x08/255.0, blue: 0x06/255.0)
    private static let maroon = Color(red: 0x1C/255.0, green: 0x06/255.0, blue: 0x06/255.0)

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
                    levels:        viewModel.displayLevels,
                    dpLevels:      viewModel.dpLevels,
                    calcIndicatorOpacity: viewModel.calcIndicatorOpacity,
                    fontStyle:     fontStyle
                )
                .equatable()
                .frame(width:  w * Self.displayRect.width,
                       height: h * Self.displayRect.height)
                .position(x: w * Self.displayRect.midX,
                          y: h * Self.displayRect.midY)

                // ── Key hit-testing ─────────────────────────────────────
                // iOS 27 regressed DragGesture(minimumDistance: 0)'s reliability for
                // continuous press-and-hold (onEnded firing ~1ms after onChanged
                // regardless of real touch duration — see UIKitTouchTracker's doc
                // comment). Track touches via raw UIKit there instead; macOS mouse
                // input is unaffected and keeps the DragGesture it always used.
                let handleChanged: (CGPoint) -> Void = { location in
                    // Touching the calculator claims physical-keyboard
                    // focus back from whichever panel had it. The drag
                    // gesture consumes the click, so relying on
                    // .focusable()'s own click-to-focus isn't enough.
                    isKeyboardFocused = true

                    let nx = location.x / w
                    let ny = location.y / h

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
                    let keyID = TISharedTables.keyIndex(x: nx, y: kbNy)
                    guard keyID >= 0 else { return }
                    let row = keyID / 5, col = keyID % 5
                    guard pressedKey != keyID else { return }
                    releaseHeldKey()
                    pressedKey = keyID
                    viewModel.pressKey(row: row, col: col)
                    triggerFeedback()
                }
                let handleEnded: () -> Void = {
                    viewModel.isDisplayPressed = false
                    viewModel.isFullSpeedMode = false
                    releaseHeldKey()
                }

                #if os(macOS)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { handleChanged($0.location) }
                            .onEnded { _ in handleEnded() }
                    )
                #else
                UIKitTouchTracker(onChanged: handleChanged, onEnded: handleEnded)
                    .frame(width: w, height: h)
                #endif

                // ── Press highlight ─────────────────────────────────────
                // Simulate key press: shift key down-right and expose black background.
                // Physical-keyboard presses light the same highlight, so a typed key
                // looks exactly like a clicked one.
                if let pk = pressedKey ?? viewModel.keyboardHeldKey {
                    let r = TISharedTables.keyRect(row: pk / 5, col: pk % 5)
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
/// Focus-scoped for now, and deliberately without a focus indicator: the Mac
/// window shows the calculator, the printer and the debug panels side by side,
/// so keys currently only reach the calculator while it holds focus — otherwise
/// arrow keys meant for the CPU inspector's instruction list would also step the
/// program. It takes focus on appear and reclaims it on touch, so typing works at
/// launch with nothing to select.
///
/// This is a stepping stone, not the target design. The Mac is meant to end up
/// with one unified input surface where every key has exactly one meaning and
/// focus stops mattering at all (the three panels only stay separate because
/// iPhone portrait swipes between them). See `TODO.md` § UI. Until then, note
/// that clicking into the debug panel silently stops keys reaching the
/// calculator, with nothing on screen to say so.
private struct PhysicalKeyboardModifier: ViewModifier {
    let viewModel: EmulatorViewModel
    let focus: FocusState<Bool>.Binding

    private var isFocused: Bool { focus.wrappedValue }

    /// One or two matrix codes for a key press, or empty if unbound. The
    /// mapping and its rules live in Shared/KeyboardMap.hpp; this only
    /// translates SwiftUI's KeyPress into its neutral form.
    private func matrixCodes(for keyPress: KeyPress) -> [UInt8] {
        let key = keyPress.key.character
        let modifiers = keyPress.modifiers
        let data = TISharedTables.matrixCodes(
            forKey: key.unicodeScalars.first?.value ?? 0,
            produced: keyPress.characters.unicodeScalars.first?.value ?? 0,
            isLetter: key.isLetter,
            shift: modifiers.contains(.shift),
            command: modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option))
        return [UInt8](data)
    }

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused(focus)
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
                    let codes = matrixCodes(for: keyPress)
                    guard !codes.isEmpty else { return .ignored }
                    viewModel.keyboardKeyDown(codes)
                    return .handled
                case .up:
                    guard !matrixCodes(for: keyPress).isEmpty else { return .ignored }
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
