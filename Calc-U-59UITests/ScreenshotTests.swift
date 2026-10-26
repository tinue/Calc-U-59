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
/// saveScreenshot(fallbackName:) writes the PNG in the device orientation.
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

    /// Desired output filename stem, written by bin/run-screenshots before each xcodebuild call.
    /// Falls back to nil when running tests directly from Xcode (no temp file present).
    private var screenshotName: String? {
        guard let s = try? String(contentsOfFile: "/tmp/calc-u-59-screenshot-name", encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    /// Capture the screen and write it to `screenshotDir` as `screenshotName`
    /// (or `<fallbackName>-<device>.png` when run straight from Xcode).
    ///
    /// Since Xcode 27 (Device Hub), XCUIScreen hands back landscape shots in
    /// portrait pixel order, tagged with the orientation that turns them
    /// upright (.left on the iPad, .right on the open iPhone Duo). Drawing the
    /// image applies that tag; an untagged shot is written as is.
    private func saveScreenshot(fallbackName: String) throws {
        let dest = URL(fileURLWithPath: "\(screenshotDir)/\(screenshotName ?? "\(fallbackName)-\(UIDevice.current.name)").png")
        // The largest screen: XCUIScreen.main is the iPhone Duo's outer
        // display, dark while the device is open.
        let shot = XCUIScreen.screens.map { $0.screenshot() }.max {
            $0.image.size.width * $0.image.size.height < $1.image.size.width * $1.image.size.height
        } ?? XCUIScreen.main.screenshot()
        let image = shot.image
        guard image.imageOrientation != .up else {
            try shot.pngRepresentation.write(to: dest)
            return
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let png = UIGraphicsImageRenderer(size: size, format: format).pngData { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        try png.write(to: dest)
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

        try saveScreenshot(fallbackName: "Diagnostic")
        attachScreenshot(app, name: "diag.ti59 — diagnostic complete")
    }

    /// Assembly overlay screenshot — iPad mini (A17 Pro) landscape.
    ///
    /// Sequence:
    ///   1. Switch to CPU tab (shows ASM overlay at the bottom)
    ///   2. Select test_stopwatch.asm via the file picker
    ///   3. Tap Run
    ///   4. Tap R/S to start the stopwatch
    ///   5. Wait 3.5 seconds
    ///   6. Tap R/S to stop the stopwatch
    ///   7. Capture screenshot showing elapsed time
    func testScreenshotAssembly() throws {
        let app = launchApp(orientation: .landscapeLeft)

        // Step 1: switch to CPU tab
        let cpuTab = app.buttons["btn-tab-cpu"]
        XCTAssertTrue(cpuTab.waitForExistence(timeout: 5), "CPU tab not found")
        cpuTab.tap()

        // Step 2: open file picker and navigate to test_stopwatch.asm
        let selectFile = app.buttons["btn-asm-select"]
        XCTAssertTrue(selectFile.waitForExistence(timeout: 3), "btn-asm-select not found")
        selectFile.tap()

        navigateToOnMyIPhone(app, targetFile: "test_stopwatch.asm")
        let asmCell = app.cells.containing(.staticText, identifier: "test_stopwatch.asm").firstMatch
        XCTAssertTrue(asmCell.waitForExistence(timeout: 5), "test_stopwatch.asm not found")
        asmCell.tap()

        // Step 3: run the ASM overlay
        let runButton = app.buttons["btn-asm-run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 3), "btn-asm-run not found")
        runButton.tap()

        // If a "ROM Load Error" alert appears, dismiss it then Freeze/Resume to
        // clear the bad state before continuing.
        if app.alerts.buttons["OK"].waitForExistence(timeout: 2) {
            app.alerts.buttons["OK"].tap()
            app.buttons["btn-tab-calculator"].tap()
            let freeze = app.buttons["btn-freeze"]
            XCTAssertTrue(freeze.waitForExistence(timeout: 3), "btn-freeze not found")
            freeze.tap()
            let resume = app.buttons["btn-resume"]
            XCTAssertTrue(resume.waitForExistence(timeout: 3), "btn-resume not found")
            resume.tap()
            app.buttons["btn-tab-cpu"].tap()
        }

        // Step 4: press R/S to start the stopwatch
        let rs = app.buttons["btn-key-rs"]
        XCTAssertTrue(rs.waitForExistence(timeout: 3), "btn-key-rs not found")
        rs.press(forDuration: 0.05)

        // Step 5: let the stopwatch run for 3.5 seconds
        Thread.sleep(forTimeInterval: 3.5)

        // Step 6: press R/S to stop the stopwatch
        rs.press(forDuration: 0.05)

        // Screenshot
        try saveScreenshot(fallbackName: "Assembly")
        attachScreenshot(app, name: "Assembly — stopwatch stopped at ~3.5s")
    }

    /// Settings screenshot — iPhone 16e portrait.
    func testScreenshotSettings() throws {
        let app = launchApp(orientation: .portrait)

        let settingsButton = app.buttons["btn-settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "btn-settings not found")
        settingsButton.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5),
                      "Settings sheet did not appear")

        try saveScreenshot(fallbackName: "Settings")
        attachScreenshot(app, name: "Settings")
    }

    /// Plain calculator screenshot — TI-58C with -1.2345678e-90 on the display.
    func testScreenshotPlainCalculator() throws {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let app = launchApp(orientation: isPad ? .landscapeLeft : .portrait)

        let presetButton = app.buttons["btn-preset"]
        XCTAssertTrue(presetButton.waitForExistence(timeout: 5), "Preset button not found")
        presetButton.tap()

        navigateToOnMyIPhone(app, targetFile: "test_58c_display.ti58c")
        let cell = app.cells.containing(.staticText, identifier: "test_58c_display.ti58c").firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "test_58c_display.ti58c not found")

        let statusEl = app.otherElements["keystroke-playback-status"]
        let idle = NSPredicate(format: "value == 'idle'")
        let playbackStarted = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'playing'"), object: statusEl)
        cell.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [playbackStarted], timeout: 8), .completed,
                       "test_58c_display.ti58c did not load")
        let playbackDone = XCTNSPredicateExpectation(predicate: idle, object: statusEl)
        XCTAssertEqual(XCTWaiter.wait(for: [playbackDone], timeout: 15), .completed,
                       "test_58c_display.ti58c keystrokes did not complete")

        try saveScreenshot(fallbackName: "PlainCalculator")
        attachScreenshot(app, name: "Plain Calculator — TI-58C display")
    }

    /// CPU Inspector screenshot — iPhone 17 Pro Max portrait only.
    ///
    /// Sequence:
    ///   1. Navigate left to debugger
    ///   2. Switch to CPU tab
    ///   3. Arm FREEZE ON START (CPU pane)
    ///   4. Navigate right to calculator
    ///   5. Tap Reset — freeze fires on first PC change
    ///   6. Navigate left to debugger
    ///   7. Single-step 5 times
    ///   8. Capture screenshot
    func testScreenshotCPUInspector() throws {
        let app = launchApp(orientation: .portrait)

        let left  = app.buttons["btn-page-left"]
        let right = app.buttons["btn-page-right"]

        // Step 1: navigate to debugger
        XCTAssertTrue(left.waitForExistence(timeout: 5), "btn-page-left not found")
        left.tap()

        // Step 2: switch to CPU tab
        let cpuTab = app.buttons["btn-tab-cpu"]
        XCTAssertTrue(cpuTab.waitForExistence(timeout: 3), "CPU tab not found")
        cpuTab.tap()

        // Step 3: arm FREEZE ON START in CPU pane
        let freezeButton = app.buttons["btn-cpu-freeze-on-start"]
        XCTAssertTrue(freezeButton.waitForExistence(timeout: 3), "btn-cpu-freeze-on-start not found")
        freezeButton.tap()

        // Step 4: navigate back to calculator
        XCTAssertTrue(right.waitForExistence(timeout: 3), "btn-page-right not found")
        right.tap()

        // Step 5: tap Reset — FREEZE ON START fires on first PC change
        let resetButton = app.buttons["btn-reset"]
        XCTAssertTrue(resetButton.waitForExistence(timeout: 3), "btn-reset not found")
        resetButton.tap()

        // Step 6: navigate back to debugger
        XCTAssertTrue(left.waitForExistence(timeout: 3), "btn-page-left not found")
        left.tap()

        // Step 7: hold STEP for 2 seconds (auto-repeats at 4 steps/second)
        let stepButton = app.buttons["btn-cpu-step"]
        XCTAssertTrue(stepButton.waitForExistence(timeout: 3), "btn-cpu-step not found")
        stepButton.press(forDuration: 2)

        // Screenshot
        try saveScreenshot(fallbackName: "CPUInspector")
        attachScreenshot(app, name: "CPU Inspector — 5 steps after reset")
    }

    /// Calc Debugger screenshot — landscape where the debugger sits beside the
    /// calculator (iPad, iPhone Duo opened flat), else iPhone portrait.
    ///
    /// Side by side (landscape): debug panel is visible alongside the calculator; no panel navigation needed.
    /// iPhone (portrait): after the playback, navigate left to the debug panel for the screenshot.
    ///
    /// Sequence:
    ///   1. Load test_cdebug.ti59: it sets up the module, runs the program, prints
    ///      the trace, then arms FREEZE ON START itself (KEYSTROKES FreezeOnStart:)
    ///      and re-enters the program with SBR =, so the calculator freezes
    ///   2. [iPhone] Navigate left to debug panel
    ///   3. Capture screenshot
    ///
    /// The file must be present on the device — run bin/setup-simulator-state-files first.
    func testScreenshotCalcDebugger() throws {
        // Try landscape; a plain iPhone stays in portrait (page arrows), so
        // relaunch it upright for the paged flow and an unrotated screenshot.
        var app = launchApp(orientation: .landscapeLeft)
        XCTAssertTrue(app.buttons["btn-preset"].waitForExistence(timeout: 5), "Preset button not found")
        let isPad = !app.buttons["btn-page-right"].exists  // side by side
        if !isPad {
            app.terminate()
            app = launchApp(orientation: .portrait)
        }

        let presetButton = app.buttons["btn-preset"]
        XCTAssertTrue(presetButton.waitForExistence(timeout: 5), "Preset button not found")

        let statusEl = app.otherElements["keystroke-playback-status"]
        let playing = NSPredicate(format: "value == 'playing'")
        let idle    = NSPredicate(format: "value == 'idle'")

        // Step 1: load test_cdebug.ti59
        presetButton.tap()
        navigateToOnMyIPhone(app, targetFile: "test_cdebug.ti59")
        let cell = app.cells.containing(.staticText, identifier: "test_cdebug.ti59").firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "test_cdebug.ti59 not found")
        let started = XCTNSPredicateExpectation(predicate: playing, object: statusEl)
        cell.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 8), .completed,
                       "test_cdebug.ti59 did not load")
        let finished = XCTNSPredicateExpectation(predicate: idle, object: statusEl)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 40), .completed,
                       "test_cdebug.ti59 keystrokes did not complete")

        // Step 2 (iPhone): navigate left to debug panel for screenshot
        if !isPad {
            let left = app.buttons["btn-page-left"]
            XCTAssertTrue(left.waitForExistence(timeout: 3), "btn-page-left not found")
            left.tap()
        }

        // Screenshot — freeze has fired; calculator is stopped on first instruction
        try saveScreenshot(fallbackName: "CalcDebugger")
        attachScreenshot(app, name: "Calc Debugger — frozen on run")
    }

    /// Texas Instruments printer program screenshot — iPad only.
    ///
    /// Loads test_texas.ti59, waits for keystroke playback to complete, captures a screenshot.
    func testScreenshotTexas() throws {
        let app = launchApp(orientation: .landscapeLeft)

        let presetButton = app.buttons["btn-preset"]
        XCTAssertTrue(presetButton.waitForExistence(timeout: 5), "Preset button not found")
        presetButton.tap()

        navigateToOnMyIPhone(app, targetFile: "test_texas.ti59")
        let cell = app.cells.containing(.staticText, identifier: "test_texas.ti59").firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "test_texas.ti59 not found")

        let statusEl = app.otherElements["keystroke-playback-status"]
        let playing = NSPredicate(format: "value == 'playing'")
        let idle = NSPredicate(format: "value == 'idle'")
        let playbackStarted = XCTNSPredicateExpectation(predicate: playing, object: statusEl)
        cell.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [playbackStarted], timeout: 8), .completed,
                       "test_texas.ti59 did not load")
        let playbackDone = XCTNSPredicateExpectation(predicate: idle, object: statusEl)
        XCTAssertEqual(XCTWaiter.wait(for: [playbackDone], timeout: 45), .completed,
                       "test_texas.ti59 keystrokes did not complete")

        try saveScreenshot(fallbackName: "Texas")
        attachScreenshot(app, name: "Texas — test_texas.ti59 complete")
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
