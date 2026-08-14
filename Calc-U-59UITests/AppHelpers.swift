import XCTest

// MARK: - App launch helpers

extension XCTestCase {

    /// Launch the app (macOS / any platform without device orientation).
    ///
    /// `--UITesting` gates automation-only UI (e.g. the hidden R/S button and
    /// keystroke-playback accessibility element in CalculatorView) that must
    /// never be reachable in a real user's build — see CalculatorView.isUITesting.
    @discardableResult
    func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--UITesting"]
        app.launch()
        return app
    }

    #if !os(macOS)
    /// Launch the app after forcing the simulator into a known orientation.
    ///
    /// Setting orientation before launch avoids an iPad simulator quirk where
    /// the simulator retains its previous session orientation, causing XCUITest
    /// to rotate several times before tests can run.
    ///
    /// `--UITesting` gates automation-only UI (e.g. the hidden R/S button and
    /// keystroke-playback accessibility element in CalculatorView) that must
    /// never be reachable in a real user's build — see CalculatorView.isUITesting.
    @discardableResult
    func launchApp(orientation: UIDeviceOrientation) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments += ["--UITesting"]
        app.launch()
        return app
    }
    #endif

    /// Attach a labelled screenshot to the current test result (always kept).
    func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
