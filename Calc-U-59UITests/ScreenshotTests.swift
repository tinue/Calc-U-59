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
        if let dir = try? String(contentsOfFile: "/tmp/calc-u-59-screenshot-dir", encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), !dir.isEmpty {
            return dir
        }
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

    /// Calc Debugger screenshot — iPad landscape or iPhone portrait.
    ///
    /// iPad (landscape): debug panel is visible alongside the calculator; no panel navigation needed.
    /// iPhone (portrait): navigate left to debug panel to arm freeze, then right back to calculator,
    ///                    load the second file, then navigate left again for the screenshot.
    ///
    /// Sequence:
    ///   1. Load test_cdebug_1.ti59 (sets up module, runs program, prints trace)
    ///   2. [iPhone] Navigate left to debug panel
    ///   3. Arm FREEZE ON START (btn-freeze-on-start)
    ///   4. [iPhone] Navigate right back to calculator
    ///   5. Load test_cdebug_2.ti59 (SKIP-RESET; SBR= re-enters program; freeze fires)
    ///   6. [iPhone] Navigate left to debug panel
    ///   7. Capture screenshot
    ///
    /// Both files must be present on the device — run bin/setup-simulator-state-files first.
    func testScreenshotCalcDebuggeriPad() throws {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let app = launchApp(orientation: isPad ? .landscapeLeft : .portrait)

        let presetButton = app.buttons["btn-preset"]
        XCTAssertTrue(presetButton.waitForExistence(timeout: 5), "Preset button not found")

        let statusEl = app.otherElements["keystroke-playback-status"]
        let playing = NSPredicate(format: "value == 'playing'")
        let idle    = NSPredicate(format: "value == 'idle'")

        // Step 1: load test_cdebug_1.ti59
        presetButton.tap()
        navigateToOnMyIPhone(app, targetFile: "test_cdebug_1.ti59")
        let startCell = app.cells.containing(.staticText, identifier: "test_cdebug_1.ti59").firstMatch
        XCTAssertTrue(startCell.waitForExistence(timeout: 5), "test_cdebug_1.ti59 not found")
        let step1Playing = XCTNSPredicateExpectation(predicate: playing, object: statusEl)
        startCell.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [step1Playing], timeout: 8), .completed,
                       "test_cdebug_1.ti59 did not load")
        let step1Idle = XCTNSPredicateExpectation(predicate: idle, object: statusEl)
        XCTAssertEqual(XCTWaiter.wait(for: [step1Idle], timeout: 30), .completed,
                       "test_cdebug_1.ti59 keystrokes did not complete")

        // Step 2 (iPhone): navigate left to debug panel
        if !isPad {
            let left = app.buttons["btn-page-left"]
            XCTAssertTrue(left.waitForExistence(timeout: 3), "btn-page-left not found")
            left.tap()
        }

        // Step 3: arm FREEZE ON START
        let freezeButton = app.buttons["btn-freeze-on-start"]
        XCTAssertTrue(freezeButton.waitForExistence(timeout: 3), "FREEZE ON START button not found")
        freezeButton.tap()

        // Step 4 (iPhone): navigate right back to calculator
        if !isPad {
            let right = app.buttons["btn-page-right"]
            XCTAssertTrue(right.waitForExistence(timeout: 3), "btn-page-right not found")
            right.tap()
        }

        // Step 5: load test_cdebug_2.ti59 (SKIP-RESET; SBR= triggers freeze)
        presetButton.tap()
        navigateToOnMyIPhone(app, targetFile: "test_cdebug_2.ti59")
        let runCell = app.cells.containing(.staticText, identifier: "test_cdebug_2.ti59").firstMatch
        XCTAssertTrue(runCell.waitForExistence(timeout: 5), "test_cdebug_2.ti59 not found")
        let step2Playing = XCTNSPredicateExpectation(predicate: playing, object: statusEl)
        runCell.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [step2Playing], timeout: 8), .completed,
                       "test_cdebug_2.ti59 did not load")
        let step2Idle = XCTNSPredicateExpectation(predicate: idle, object: statusEl)
        XCTAssertEqual(XCTWaiter.wait(for: [step2Idle], timeout: 10), .completed,
                       "test_cdebug_2.ti59 keystrokes did not complete")

        // Step 6 (iPhone): navigate left to debug panel for screenshot
        if !isPad {
            let left = app.buttons["btn-page-left"]
            XCTAssertTrue(left.waitForExistence(timeout: 3), "btn-page-left not found")
            left.tap()
        }

        // Screenshot — freeze has fired; calculator is stopped on first instruction
        let dest = URL(fileURLWithPath: "\(screenshotDir)/CalcDebugger-\(UIDevice.current.name).png")
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: dest)
        attachScreenshot(app, name: "Calc Debugger — frozen on run")
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
