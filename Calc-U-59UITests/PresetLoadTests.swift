import XCTest

/// Regression tests for loading a state file via the Preset button.
///
/// This test drives the iOS system document picker, which is inherently brittle:
/// navigation element labels ("Durchsuchen", "Auf meinem iPhone") are
/// locale-dependent and Apple can restructure the picker between iOS releases.
/// The filename itself ("diag.ti59") and the keystroke-playback-status assertion
/// are stable. If this test breaks after an Xcode/iOS upgrade, first inspect
/// the picker's element tree with Xcode's Accessibility Inspector or a
/// print(app.debugDescription) dump.
///
/// Prerequisite: diag.ti59 must be present on "On My iPhone" in the simulator.
/// The setup-simulator-state-files script installs it.
#if !os(macOS)
final class PresetLoadTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override class func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    // MARK: - Tests

    /// Loading diag.ti59 via the file picker must trigger keystroke playback.
    ///
    /// diag.ti59 contains "KEYSTROKES: 15 + WaitFullSpeed: 3s" which auto-starts
    /// the diagnostic. The keystroke-playback-status element transitions to
    /// "playing" — that is the proof of a successful load.
    @MainActor
    func testLoadDiagPreset() throws {
        let orientation: UIDeviceOrientation = UIDevice.current.userInterfaceIdiom == .pad
            ? .landscapeLeft : .portrait
        let app = launchApp(orientation: orientation)

        let presetButton = app.buttons["btn-preset"]
        XCTAssertTrue(presetButton.waitForExistence(timeout: 5), "Preset button not found")
        presetButton.tap()

        navigateToOnMyIPhone(app, targetFile: "diag.ti59")

        let diagCell = app.cells.containing(.staticText, identifier: "diag.ti59").firstMatch
        XCTAssertTrue(diagCell.waitForExistence(timeout: 5), "diag.ti59 cell not found in file picker")
        attachScreenshot(app, name: "File picker — diag.ti59 visible")

        let statusEl = app.otherElements["keystroke-playback-status"]
        let playing = NSPredicate(format: "value == 'playing'")
        let playbackStarted = XCTNSPredicateExpectation(predicate: playing, object: statusEl)

        diagCell.tap()

        XCTAssertEqual(XCTWaiter.wait(for: [playbackStarted], timeout: 8), .completed,
                       "Keystroke playback never started — diag.ti59 may not have loaded")

        attachScreenshot(app, name: "After loading diag.ti59 — playback running")
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

        let folder = app.cells.containing(.staticText, identifier: "1-Testfiles").firstMatch
        if folder.waitForExistence(timeout: 2) { folder.tap() }
    }
}
#endif
