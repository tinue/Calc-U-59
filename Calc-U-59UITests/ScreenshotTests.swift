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

    // MARK: - Helpers

    private var screenshotDir: String {
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] { return dir }
        // HOME points to the simulator sandbox; SIMULATOR_HOST_HOME is the real Mac home.
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? "/tmp"
        return "\(home)/Desktop"
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

        navigateToOnMyIPhone(app, targetFile: "test_diag.ti59")

        let diagCell = app.cells.containing(.staticText, identifier: "test_diag.ti59").firstMatch
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

        let dest = URL(fileURLWithPath: "\(screenshotDir)/Diagnostic-\(UIDevice.current.name).png")
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: dest)
        attachScreenshot(app, name: "diag.ti59 — diagnostic complete")
    }

    /// Leisure Library screenshot — iPad landscape only.
    ///
    /// Sequence:
    ///   1. Load screenshot_leisure_start.ti59 (sets up module, runs program, prints trace)
    ///   2. Arm FREEZE ON START (btn-freeze-on-start)
    ///   3. Load screenshot_leisure_run.ti59 (SKIP-RESET; SBR= re-enters program; freeze fires)
    ///   4. Capture screenshot after keystrokes complete
    ///
    /// Both files must be present on the device — run bin/setup-simulator-state-files first.
    func testScreenshotCalcDebuggeriPad() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        let app = launchApp(orientation: .landscapeLeft)

        let presetButton = app.buttons["btn-preset"]
        XCTAssertTrue(presetButton.waitForExistence(timeout: 5), "Preset button not found")

        let statusEl = app.otherElements["keystroke-playback-status"]
        let playing = NSPredicate(format: "value == 'playing'")
        let idle    = NSPredicate(format: "value == 'idle'")

        // Step 1: load screenshot_leisure_start.ti59
        presetButton.tap()
        navigateToOnMyIPhone(app, targetFile: "test_cdebug_1.ti59")
        let startCell = app.cells.containing(.staticText, identifier: "test_cdebug_1.ti59").firstMatch
        XCTAssertTrue(startCell.waitForExistence(timeout: 5), "screenshot_leisure_start.ti59 not found")
        let step1Playing = XCTNSPredicateExpectation(predicate: playing, object: statusEl)
        startCell.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [step1Playing], timeout: 8), .completed,
                       "screenshot_leisure_start.ti59 did not load")
        let step1Idle = XCTNSPredicateExpectation(predicate: idle, object: statusEl)
        XCTAssertEqual(XCTWaiter.wait(for: [step1Idle], timeout: 30), .completed,
                       "screenshot_leisure_start.ti59 keystrokes did not complete")

        // Step 2: arm FREEZE ON START
        let freezeButton = app.buttons["btn-freeze-on-start"]
        XCTAssertTrue(freezeButton.waitForExistence(timeout: 3), "FREEZE ON START button not found")
        freezeButton.tap()

        // Step 3: load screenshot_leisure_run.ti59 (SKIP-RESET; SBR= triggers freeze)
        presetButton.tap()
        navigateToOnMyIPhone(app, targetFile: "test_cdebug_2.ti59")
        let runCell = app.cells.containing(.staticText, identifier: "test_cdebug_2.ti59").firstMatch
        XCTAssertTrue(runCell.waitForExistence(timeout: 5), "screenshot_leisure_run.ti59 not found")
        let step2Playing = XCTNSPredicateExpectation(predicate: playing, object: statusEl)
        runCell.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [step2Playing], timeout: 8), .completed,
                       "screenshot_leisure_run.ti59 did not load")
        let step2Idle = XCTNSPredicateExpectation(predicate: idle, object: statusEl)
        XCTAssertEqual(XCTWaiter.wait(for: [step2Idle], timeout: 10), .completed,
                       "screenshot_leisure_run.ti59 keystrokes did not complete")

        // Screenshot — freeze has fired; calculator is stopped on first instruction
        let dest = URL(fileURLWithPath: "\(screenshotDir)/CalcDebuggeriPad-\(UIDevice.current.name).png")
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: dest)
        attachScreenshot(app, name: "Calc Debugger iPad — frozen on run")
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
            let item = app.cells.containing(.staticText, identifier: label).firstMatch
            if item.waitForExistence(timeout: 2) { item.tap(); break }
        }

        let folder = app.cells.containing(.staticText, identifier: "1-Testfiles").firstMatch
        if folder.waitForExistence(timeout: 2) { folder.tap() }
    }
}
#endif
