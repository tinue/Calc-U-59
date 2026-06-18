import SwiftUI

/// A monospaced text button that fires its action once on tap and then
/// auto-repeats while held down. Used by the debug headers' STEP button so
/// the user can single-step by tapping or hold to step continuously.
struct HoldRepeatButton: View {
    let title: String
    let color: Color
    let baseFontSize: CGFloat
    let enabled: Bool
    /// Seconds between auto-repeats while held. 0.25 == 4 steps per second.
    var repeatInterval: TimeInterval = 0.25
    let action: () -> Void

    @State private var timer: Timer?
    @State private var isPressing = false

    var body: some View {
        Text(title)
            .font(.system(size: baseFontSize, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .opacity(enabled ? (isPressing ? 0.5 : 1) : 0.4)
            .contentShape(Rectangle())
            // minimumDistance 0 makes onChanged fire on touch-down.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard enabled, !isPressing else { return }
                        isPressing = true
                        action()                      // immediate first step
                        // Register in .common modes so the timer keeps firing
                        // while the mouse button is held on macOS (the run loop
                        // is in event-tracking mode during a press).
                        let t = Timer(timeInterval: repeatInterval, repeats: true) { _ in
                            action()
                        }
                        RunLoop.current.add(t, forMode: .common)
                        timer = t
                    }
                    .onEnded { _ in
                        stop()
                    }
            )
            .onDisappear { stop() }
    }

    private func stop() {
        isPressing = false
        timer?.invalidate()
        timer = nil
    }
}
