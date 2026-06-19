import XCTest

/// Regression tests for the file picker sheet.
///
/// Background: on iPad, SwiftUI's fileImporter can dismiss the popover (setting
/// isPresented = false) on a tap-outside without calling the result handler.
/// This left filePickerMode non-nil and prevented a second open.
/// The two-variable fix in CalculatorView ensures re-tapping always reopens.
final class FilePickerTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Leave the simulator in portrait after all tests complete so the next run
    /// starts in the expected orientation without a rotation dance.
    #if !os(macOS)
    override class func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }
    #endif

    // MARK: - Tests

    #if !os(macOS)
    /// The Preset button must open the document picker sheet.
    @MainActor
    func testFilePickerOpens() throws {
        let app = launchApp(orientation: .portrait)

        let presetButton = app.buttons["btn-preset"]
        XCTAssertTrue(presetButton.waitForExistence(timeout: 5), "Preset button not found")
        presetButton.tap()

        // The system document picker presents a Cancel button on both iPhone and iPad.
        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5), "File picker did not appear")

        attachScreenshot(app, name: "File picker open")

        cancelButton.tap()
    }

    /// Tapping Preset a second time after a Cancel must reopen the picker.
    ///
    /// Regression: the iPad popover dismiss path left filePickerMode non-nil while
    /// filePickerPresented was false, so a second tap was a no-op.
    @MainActor
    func testFilePickerReopensAfterCancel() throws {
        let app = launchApp(orientation: .portrait)

        let presetButton = app.buttons["btn-preset"]
        XCTAssertTrue(presetButton.waitForExistence(timeout: 5), "Preset button not found")

        // First open → cancel
        presetButton.tap()
        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5), "File picker did not appear on first tap")
        cancelButton.tap()
        XCTAssertFalse(cancelButton.waitForExistence(timeout: 2), "Picker did not dismiss")

        // Second open — this was the failure case
        presetButton.tap()
        XCTAssertTrue(
            app.buttons["Cancel"].waitForExistence(timeout: 5),
            "File picker did not reopen after cancel — regression in filePickerPresented state"
        )

        attachScreenshot(app, name: "File picker reopened after cancel")

        app.buttons["Cancel"].tap()
    }
    #endif
}
