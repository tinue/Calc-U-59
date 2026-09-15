import SwiftUI

#if !os(macOS)
import UIKit

/// Raw UIKit touch tracking, bypassing SwiftUI's `DragGesture`.
///
/// iOS 27 regressed `DragGesture(minimumDistance: 0)`'s `onChanged`/`onEnded`
/// pair: `onEnded` now frequently fires within ~1ms of `onChanged`, as if the
/// touch was released the instant it began, regardless of how long the real
/// touch is actually held — confirmed reproducible (iOS 26.5: reliable,
/// iOS 27.0: ~1-in-20 presses actually register). `UIView.touchesBegan` /
/// `touchesMoved` / `touchesEnded` / `touchesCancelled`, one layer below
/// SwiftUI's gesture-recognition engine, don't exhibit this — see the
/// key-press-reliability investigation that replaced `KeyboardView`'s and
/// `CalculatorView`'s `btn-key-rs`'s gestures with this type.
///
/// Only single-touch tracking is needed: the calculator's key matrix has no
/// multi-touch behavior to preserve (the previous `DragGesture` didn't track
/// multiple touches either).
struct UIKitTouchTracker: UIViewRepresentable {
    var onChanged: (CGPoint) -> Void
    var onEnded: () -> Void

    final class TrackingView: UIView {
        var onChanged: ((CGPoint) -> Void)?
        var onEnded: (() -> Void)?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first else { return }
            onChanged?(touch.location(in: self))
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first else { return }
            onChanged?(touch.location(in: self))
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            onEnded?()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            onEnded?()
        }
    }

    func makeUIView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        view.onChanged = onChanged
        view.onEnded = onEnded
        return view
    }

    func updateUIView(_ uiView: TrackingView, context: Context) {
        uiView.onChanged = onChanged
        uiView.onEnded = onEnded
    }
}
#endif
