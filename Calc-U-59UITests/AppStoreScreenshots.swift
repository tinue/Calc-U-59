import XCTest

/// App Store screenshot automation.
///
/// Produces one screenshot of the Leisure Library running with TRACE output on the printer tape,
/// frozen at the start of the program so the display shows the clean initial state.
///
/// Two-file sequence:
///   1. `screenshot_leisure_start.ti59` — resets machine, loads LE module, plays
///      2nd Pgm 01 SBR = (wait) π×4= with TRACE on, then TRACE off.
///   2. `screenshot_leisure_run.ti59`   — SKIP-RESET; injects SBR= into the running
///      machine; FREEZE ON START fires on the first PC change.
///
/// Prerequisites (handled in class setUp):
///   - UIFileSharingEnabled = YES in Info.plist (makes Documents visible in file picker)
///   - State files copied to the simulator's app Documents folder via simctl
///
/// Target: iPad landscape (the debug panel is only always-visible in that layout).
#if !os(macOS)
final class AppStoreScreenshots: XCTestCase {

    private static let stateFiles = [
        "screenshot_leisure_start.ti59",
        "screenshot_leisure_run.ti59",
    ]

    // MARK: - Class-level setup

    override class func setUp() {
        super.setUp()
        // Launch once to create the app data container, then terminate.
        // Without a prior launch, simctl cannot resolve the container path.
        let bootstrap = XCUIApplication()
        bootstrap.launch()
        bootstrap.terminate()

        // Copy state files from examples/debug/ into the simulator's Documents folder.
        // We call this via a temporary instance — copyStateFiles is on XCTestCase.
        AppStoreScreenshots().copyStateFiles(named: stateFiles)
    }

    override class func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    // MARK: - Screenshot tests

    /// Leisure Library: π × 4 computation with TRACE output, frozen at program start.
    @MainActor
    func testLeisureLibraryFrozenAtStart() throws {
        let app = launchApp(orientation: .landscapeLeft)

        // ── Step 1: load the start file ───────────────────────────────────────
        // Resets the machine, loads the Leisure Library module, plays the key
        // sequence 2nd Pgm 01 SBR = (full-speed wait) π × 4 = with TRACE.
        selectStateFile(named: "screenshot_leisure_start.ti59", in: app)

        // Wait for keystroke playback to finish before touching the UI.
        waitForKeystrokePlayback(in: app)

        // ── Step 2: arm FREEZE ON START ───────────────────────────────────────
        // The CALCULATOR debug tab is the default; the button is always visible
        // in iPad landscape (debug panel is part of the side-by-side layout).
        let freezeOnStart = app.buttons["btn-freeze-on-start"]
        XCTAssertTrue(freezeOnStart.waitForExistence(timeout: 5), "FREEZE ON START button not found")
        XCTAssertTrue(freezeOnStart.isEnabled, "FREEZE ON START button is disabled")
        freezeOnStart.tap()

        // Confirm armed: the ARMED button becomes enabled.
        let armed = app.buttons["btn-freeze-armed"]
        XCTAssertTrue(armed.waitForExistence(timeout: 3), "ARMED button not found")
        XCTAssertTrue(armed.isEnabled, "FREEZE ON START did not arm")

        // ── Step 3: load the run file (SKIP-RESET) ────────────────────────────
        // Injects SBR = into the running machine; FREEZE ON START fires on the
        // first PC change and the machine freezes immediately.
        selectStateFile(named: "screenshot_leisure_run.ti59", in: app)

        // Confirm frozen: RESUME button becomes enabled.
        let resume = app.buttons["btn-resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5), "RESUME button not found")
        XCTAssertTrue(resume.isEnabled, "Machine did not freeze after SBR =")

        // ── Step 4: screenshot ────────────────────────────────────────────────
        attachScreenshot(app, name: "Leisure Library — frozen at program start")
    }
}
#endif
