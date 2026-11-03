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
        XCTAssertTrue(pickerCancelButton(app).waitForExistence(timeout: 5), "File picker did not appear")

        attachScreenshot(app, name: "File picker open")

        cancelPicker(app)
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
        XCTAssertTrue(pickerCancelButton(app).waitForExistence(timeout: 5), "File picker did not appear on first tap")
        cancelPicker(app)

        // Second open — this was the failure case
        presetButton.tap()
        XCTAssertTrue(
            pickerCancelButton(app).waitForExistence(timeout: 5),
            "File picker did not reopen after cancel — regression in filePickerPresented state"
        )

        attachScreenshot(app, name: "File picker reopened after cancel")

        cancelPicker(app)
    }

    // MARK: - Helpers

    /// The picker's Cancel button. Only the one in the navigation bar: while the
    /// picker settles on the iPhone Duo, a toolbar holds a second one.
    private func pickerCancelButton(_ app: XCUIApplication) -> XCUIElement {
        app.navigationBars.buttons["Cancel"]
    }

    /// Tap Cancel and check that the picker closes and stays closed.
    ///
    /// On the iPhone Duo the picker slides and resizes for over a second after
    /// opening, and a tap at a position read during that lands beside the button.
    private func cancelPicker(_ app: XCUIApplication) {
        let cancelButton = pickerCancelButton(app)
        var settledFrame = cancelButton.frame
        var settledSince = Date()
        let deadline = Date().addingTimeInterval(10)
        while Date().timeIntervalSince(settledSince) < 1, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            if cancelButton.frame != settledFrame {
                settledFrame = cancelButton.frame
                settledSince = Date()
            }
        }
        cancelButton.tap()

        XCTAssertTrue(cancelButton.waitForNonExistence(timeout: 5), "Picker did not dismiss")
        XCTAssertFalse(cancelButton.waitForExistence(timeout: 1), "Picker came back after dismissing")
    }
    #endif
}
