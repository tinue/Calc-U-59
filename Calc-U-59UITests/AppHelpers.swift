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

/// App bundle identifier — must match PRODUCT_BUNDLE_IDENTIFIER in the project.
private let appBundleID = "ch.erzberger.calcu59"

extension XCTestCase {

    /// Copy named state files from `examples/debug/` in the repo into the simulator's
    /// app Documents folder so they appear under "On My iPhone → Calc-U-59" in the
    /// file picker.
    ///
    /// The app must have been launched and terminated at least once before calling this
    /// so that the data container exists.  Call from `override class func setUp()`.
    ///
    /// - Parameter names: file names, e.g. `["screenshot_leisure_start.ti59"]`
    func copyStateFiles(named names: [String]) {
        guard let containerPath = simctlAppContainer() else {
            XCTFail("Could not resolve app container — is the app installed on the booted simulator?")
            return
        }
        let docsURL = URL(fileURLWithPath: containerPath).appendingPathComponent("Documents")
        try? FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)

        // Derive repo root from this source file's location: <repo>/Calc-U-59UITests/AppHelpers.swift
        let repoRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()   // Calc-U-59UITests/
            .deletingLastPathComponent()   // <repo root>

        for name in names {
            let src = repoRoot.appendingPathComponent("examples/debug/\(name)")
            let dst = docsURL.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dst)
            do {
                try FileManager.default.copyItem(at: src, to: dst)
            } catch {
                XCTFail("Failed to copy \(name): \(error)")
            }
        }
    }

    /// Open the file picker, navigate to the app's Documents folder in "On My iPhone",
    /// and tap the named file.  Fails the test if navigation or selection times out.
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
        XCTAssertTrue(appFolder.waitForExistence(timeout: 5), "'Calc-U-59' folder not found in On My iPhone")
        appFolder.tap()

        // Tap the file.
        let fileCell = app.staticTexts[name]
        XCTAssertTrue(fileCell.waitForExistence(timeout: 5), "'\(name)' not found in Calc-U-59 folder")
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

    // MARK: - Private

    private func simctlAppContainer() -> String? {
        let process = Process()
        process.launchPath = "/usr/bin/xcrun"
        process.arguments = ["simctl", "get_app_container", "booted", appBundleID, "data"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()  // suppress stderr
        process.launch()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == false ? output : nil
    }
}
