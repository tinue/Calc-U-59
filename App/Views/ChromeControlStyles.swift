import SwiftUI

/// Opts a `Button` out of the system's automatic "Button Shapes" accessibility
/// decoration, which only decorates controls using the default/automatic
/// style — see
/// https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityshowbuttonshapes
/// Any control given an *explicit* style (this one, or even Apple's own
/// `.plain`) is left alone by the system. Without this, default-style
/// buttons got an oversized system-drawn shape when the setting was on,
/// inflating their layout footprint enough to shove surrounding UI around.
///
/// Deliberately renders `configuration.label` unmodified — these controls
/// sit on a photorealistic calculator skin where exact visual parity with
/// the undecorated look matters more than reproducing the Button Shapes
/// affordance itself.
struct ChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1.0)
            .contentShape(Rectangle())
    }
}

/// Same rationale as `ChromeButtonStyle`, for `Menu` and `Picker(.menu)`
/// controls, which style via `MenuStyle` rather than `ButtonStyle`.
/// `Menu(configuration)` rebuilds the default menu trigger appearance
/// exactly, so this is purely an opt-out of the automatic decoration with
/// no visual change.
struct ChromeMenuStyle: MenuStyle {
    func makeBody(configuration: Configuration) -> some View {
        Menu(configuration)
    }
}
