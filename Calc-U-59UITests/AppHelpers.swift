import XCTest

// MARK: - App launch helpers

extension XCTestCase {

    /// Launch the app (macOS / any platform without device orientation).
    @discardableResult
    func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    #if !os(macOS)
    /// Launch the app after forcing the simulator into a known orientation.
    ///
    /// Setting orientation before launch avoids an iPad simulator quirk where
    /// the simulator retains its previous session orientation, causing XCUITest
    /// to rotate several times before tests can run.
    @discardableResult
    func launchApp(orientation: UIDeviceOrientation) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
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

// MARK: - State file helpers

extension XCTestCase {

    /// Open the file picker, navigate to the app's Documents folder in "On My iPhone",
    /// and tap the named file.  Fails the test if navigation or selection times out.
    ///
    /// Files must be pre-loaded into the simulator before running — `Process` (NSTask)
    /// is macOS-only and cannot be called from an iOS test process.  Run
    /// `bin/setup-simulator-state-files` once after installing the app, or add it
    /// as a scheme pre-action (provide the SRCROOT expansion).
    func selectStateFile(named name: String, in app: XCUIApplication) {
        let preset = app.buttons["btn-preset"]
        XCTAssertTrue(preset.waitForExistence(timeout: 5), "Preset button not found")
        preset.tap()

        // The document picker may open directly in a recent location or at the Browse root.
        // Tap "Browse" if it appears, to get to the location list.
        let browse = app.buttons["Browse"]
        if browse.waitForExistence(timeout: 3) { browse.tap() }

        // Navigate into "On My iPhone" if not already there.
        let onMyDevice = app.staticTexts["On My iPhone"]
        if onMyDevice.waitForExistence(timeout: 5) { onMyDevice.tap() }

        // Tap the app's folder.
        let appFolder = app.staticTexts["Calc-U-59"]
        XCTAssertTrue(appFolder.waitForExistence(timeout: 5),
                      "'Calc-U-59' folder not found — run bin/setup-simulator-state-files first")
        appFolder.tap()

        // Tap the file.
        let fileCell = app.staticTexts[name]
        XCTAssertTrue(fileCell.waitForExistence(timeout: 5),
                      "'\(name)' not found — run bin/setup-simulator-state-files first")
        fileCell.tap()
    }

    /// Wait until keystroke playback finishes (``keystroke-playback-status`` reads "idle").
    /// Fails the test if playback does not complete within `timeout` seconds.
    func waitForKeystrokePlayback(in app: XCUIApplication, timeout: TimeInterval = 30) {
        let status = app.otherElements["keystroke-playback-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5), "keystroke-playback-status element not found")
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if status.value as? String == "idle" { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTFail("Keystroke playback did not complete within \(Int(timeout)) s")
    }
}
