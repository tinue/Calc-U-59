import XCTest

/// Screenshot automation — produces PNG files on the Desktop for visual review.
///
/// This class is excluded from UIRegressionTests via skippedTests.
/// Run via the Screenshots test plan (Product → Test Plan → Screenshots) or:
///   xcodebuild test -scheme "Calc-U-59" \
///     -testPlan Screenshots \
///     -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)"
///
/// For iPad screenshots rotate the simulator to landscape before running.
/// XCUIScreen.main.screenshot() captures physical screen pixels and respects
/// the current orientation — no post-processing needed.
#if !os(macOS)
final class ScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override class func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    // MARK: - Screenshots

    /// Load diag.ti59, run the diagnostic to completion, save a Desktop PNG.
    ///
    /// Prerequisite: diag.ti59 must be present on "On My iPhone" in the simulator.
    func testScreenshotLoadDiagPreset() throws {
        let orientation: UIDeviceOrientation = UIDevice.current.userInterfaceIdiom == .pad
            ? .landscapeLeft : .portrait
        let app = launchApp(orientation: orientation)

        let presetButton = app.buttons["btn-preset"]
        XCTAssertTrue(presetButton.waitForExistence(timeout: 5), "Preset button not found")
        presetButton.tap()

        navigateToOnMyIPhone(app, targetFile: "diag.ti59")

        let diagCell = app.cells.containing(.staticText, identifier: "diag.ti59").firstMatch
        XCTAssertTrue(diagCell.waitForExistence(timeout: 5), "diag.ti59 cell not found in file picker")

        let statusEl = app.otherElements["keystroke-playback-status"]
        let playing = NSPredicate(format: "value == 'playing'")
        let playbackStarted = XCTNSPredicateExpectation(predicate: playing, object: statusEl)

        diagCell.tap()

        XCTAssertEqual(XCTWaiter.wait(for: [playbackStarted], timeout: 8), .completed,
                       "Keystroke playback never started — diag.ti59 may not have loaded")

        // Wait for the diagnostic to finish before capturing.
        let idle = NSPredicate(format: "value == 'idle'")
        let playbackDone = XCTNSPredicateExpectation(predicate: idle, object: statusEl)
        XCTAssertEqual(XCTWaiter.wait(for: [playbackDone], timeout: 10), .completed,
                       "Keystroke playback did not complete")

        let screenshotName = "Diagnostic"
        let deviceName = UIDevice.current.name
        let dest = URL(fileURLWithPath: "/Users/me/Desktop/\(screenshotName)-\(deviceName).png")
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: dest)
        attachScreenshot(app, name: "diag.ti59 — diagnostic complete")
    }

    // MARK: - Helpers

    private func navigateToOnMyIPhone(_ app: XCUIApplication, targetFile: String) {
        if app.cells.containing(.staticText, identifier: targetFile).firstMatch.waitForExistence(timeout: 2) { return }

        for label in ["Durchsuchen", "Browse"] {
            let tab = app.tabBars.buttons[label]
            if tab.waitForExistence(timeout: 2) {
                if !tab.isSelected { tab.tap() }
                break
            }
        }

        for label in ["Auf meinem iPhone", "Auf meinem iPad", "On My iPhone", "On My iPad"] {
            let item = app.staticTexts[label]
            if item.waitForExistence(timeout: 2) { item.tap(); break }
        }
    }
}
#endif
