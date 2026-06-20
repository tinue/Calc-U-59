import XCTest

/// Tests that loading a state file via the Preset button works end-to-end.
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
///
/// Orientation: the test inherits whatever orientation the simulator is in when
/// the test is started. For an iPad screenshot rotate the simulator to landscape
/// manually before running. Programmatic orientation changes via XCUIDevice
/// cause app.screenshot() to capture misaligned frames.
#if !os(macOS)
final class PresetLoadTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Tests

    /// Loading diag.ti59 via the file picker must trigger keystroke playback.
    ///
    /// diag.ti59 contains "KEYSTROKES: 15 + WaitFullSpeed: 3s" which auto-starts
    /// the diagnostic and runs it to completion. The keystroke-playback-status
    /// element stays "playing" for ~3 s — that is the proof of a successful load.
    override class func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    @MainActor
    func testLoadDiagPreset() throws {
        // iPad uses landscape (side-by-side layout); iPhone uses portrait.
        let orientation: UIDeviceOrientation = UIDevice.current.userInterfaceIdiom == .pad
            ? .landscapeLeft : .portrait
        let app = launchApp(orientation: orientation)

        let presetButton = app.buttons["btn-preset"]
        XCTAssertTrue(presetButton.waitForExistence(timeout: 5), "Preset button not found")
        presetButton.tap()

        // ── Navigate to the file ────────────────────────────────────────────
        // The picker may open on Recents. Tap the Browse tab to reach the
        // location list. Label is locale-dependent ("Durchsuchen" in German,
        // "Browse" in English).
        navigateToOnMyIPhone(app, targetFile: "diag.ti59")

        // Find the grid cell that contains the "diag.ti59" filename label.
        // The document picker uses collection view cells; tapping the inner
        // staticText does not trigger file selection — the cell itself must be tapped.
        let diagCell = app.cells.containing(.staticText, identifier: "diag.ti59").firstMatch
        XCTAssertTrue(diagCell.waitForExistence(timeout: 5), "diag.ti59 cell not found in file picker")
        attachScreenshot(app, name: "File picker — diag.ti59 visible")

        // ── Verify loading via keystroke playback ───────────────────────────
        // diag.ti59 has KEYSTROKES: 15 + WaitFullSpeed: 3s. On successful load
        // the view model starts playback and keystroke-playback-status transitions
        // to "playing" for ~3 s. Register the expectation BEFORE tapping the
        // file so we don't race with the very first polling interval.
        let statusEl = app.otherElements["keystroke-playback-status"]
        let playing = NSPredicate(format: "value == 'playing'")
        let playbackStarted = XCTNSPredicateExpectation(predicate: playing, object: statusEl)

        diagCell.tap()

        let result = XCTWaiter.wait(for: [playbackStarted], timeout: 8)
        XCTAssertEqual(result, .completed,
                       "Keystroke playback never started — diag.ti59 may not have loaded")

        // XCUIScreen.main captures physical screen pixels (respects rotation).
        // app.screenshot() always uses the device's natural portrait coordinate
        // space, producing a portrait-framed PNG even when rotated to landscape.
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let dest = URL(fileURLWithPath: "/Users/me/Desktop/diag-preset-load.png")
        try png.write(to: dest)
        attachScreenshot(app, name: "After loading diag.ti59 — playback running")

        // Hold the test open until the diagnostic finishes.
        let idle = NSPredicate(format: "value == 'idle'")
        let playbackDone = XCTNSPredicateExpectation(predicate: idle, object: statusEl)
        XCTAssertEqual(XCTWaiter.wait(for: [playbackDone], timeout: 10), .completed,
                       "Keystroke playback did not complete")
    }

    // MARK: - Helpers

    /// Navigate the system file picker to the "On My iPhone" level.
    ///
    /// The picker often opens directly at "On My iPhone" (last-used location),
    /// so we check for the target file first and skip navigation when it is
    /// already visible. If navigation is needed, we use `tabBars.buttons` to
    /// target the Browse tab specifically — `app.buttons["Durchsuchen"]` is
    /// ambiguous because the navigation back-button inside Browse also carries
    /// that label.
    ///
    /// Brittle: location and tab labels ("Durchsuchen", "Auf meinem iPhone")
    /// are locale-dependent.
    private func navigateToOnMyIPhone(_ app: XCUIApplication, targetFile: String) {
        // Fast path: already at the right directory level.
        if app.cells.containing(.staticText, identifier: targetFile).firstMatch.waitForExistence(timeout: 2) { return }

        // Tap the Browse tab if not already selected.
        // Use tabBars.buttons to avoid the back-button that also reads "Durchsuchen".
        for label in ["Durchsuchen", "Browse"] {
            let tab = app.tabBars.buttons[label]
            if tab.waitForExistence(timeout: 2) {
                if !tab.isSelected { tab.tap() }
                break
            }
        }

        // If we landed on a Locations list, tap "On My iPhone".
        for label in ["Auf meinem iPhone", "On My iPhone"] {
            let item = app.staticTexts[label]
            if item.waitForExistence(timeout: 2) { item.tap(); break }
        }
    }
}
#endif
