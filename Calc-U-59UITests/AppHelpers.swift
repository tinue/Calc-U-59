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
    func launchApp(orientation: UIDeviceOrientation, arguments: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments += ["--UITesting"] + arguments
        app.launch()
        return app
    }

    /// Open the document picker's folder that holds `targetFile`
    /// ("On My iPhone/iPad" → 1-Testfiles), unless the picker already shows it.
    func navigateToOnMyIPhone(_ app: XCUIApplication, targetFile: String) {
        let target = app.cells.containing(.staticText, identifier: targetFile).firstMatch
        // The picker's first opening on a fresh simulator takes many seconds.
        let search = app.searchFields.firstMatch
        let pickerUp = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in search.exists || target.exists }, object: nil)
        _ = XCTWaiter.wait(for: [pickerUp], timeout: 30)

        if target.waitForExistence(timeout: 2) { return }

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

    /// Load `file` through the Preset button and wait for its KEYSTROKES to
    /// start playing, then to finish within `idleTimeout`.
    func loadPreset(_ app: XCUIApplication, file: String, idleTimeout: TimeInterval) {
        let presetButton = app.buttons["btn-preset"]
        XCTAssertTrue(presetButton.waitForExistence(timeout: 5), "Preset button not found")
        presetButton.tap()

        navigateToOnMyIPhone(app, targetFile: file)
        let cell = app.cells.containing(.staticText, identifier: file).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "\(file) not found in file picker")

        let statusEl = app.otherElements["keystroke-playback-status"]
        let playing = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'playing'"), object: statusEl)
        cell.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 8), .completed,
                       "\(file) did not load")
        let idle = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'idle'"), object: statusEl)
        XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: idleTimeout), .completed,
                       "\(file) keystrokes did not complete")
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
