import XCTest

/// Layout and visual regression tests for the card reader bar.
///
/// These tests check that toolbar buttons are present and hittable on every
/// device size (iPhone SE, iPhone 16 Pro, iPad). They also attach labelled
/// screenshots so visual issues — such as button labels wrapping onto two lines
/// — can be spotted during result review in Xcode or CI.
///
/// To check for label wrapping automatically, each button's height is compared
/// against a single-line threshold. The threshold is generous (56 pt) to
/// account for Dynamic Type and padding, but a wrapped two-line label would
/// push a .large control well past that.
final class LayoutTests: XCTestCase {

    private let singleLineLabelMaxHeight: CGFloat = 56

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

    // MARK: - Button visibility

    /// The Reset button must be visible and hittable in the card reader bar.
    @MainActor
    func testResetButtonVisible() throws {
        #if os(macOS)
        let app = launchApp()
        #else
        let app = launchApp(orientation: .portrait)
        #endif
        let button = app.buttons["btn-reset"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Reset button not found")
        XCTAssertTrue(button.isHittable, "Reset button exists but is not hittable")
    }

    #if !os(macOS)
    /// The Preset button must be visible and hittable in the card reader bar.
    @MainActor
    func testPresetButtonVisible() throws {
        let app = launchApp(orientation: .portrait)
        let button = app.buttons["btn-preset"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Preset button not found")
        XCTAssertTrue(button.isHittable, "Preset button exists but is not hittable")
    }

    /// The Settings button must be visible and hittable.
    @MainActor
    func testSettingsButtonVisible() throws {
        let app = launchApp(orientation: .portrait)
        let button = app.buttons["btn-settings"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Settings button not found")
        XCTAssertTrue(button.isHittable, "Settings button exists but is not hittable")
    }

    // MARK: - Label wrapping

    /// Preset button label must not wrap onto two lines.
    ///
    /// A .large SwiftUI button with a single-line label should be at most
    /// ~56 pt tall. If the label wraps, the button grows taller than that.
    @MainActor
    func testPresetButtonLabelSingleLine() throws {
        let app = launchApp(orientation: .portrait)
        let button = app.buttons["btn-preset"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Preset button not found")
        let height = button.frame.height
        XCTAssertLessThanOrEqual(
            height, singleLineLabelMaxHeight,
            "Preset button is \(height) pt tall — label may be wrapping"
        )
    }

    /// Reset button label must not wrap onto two lines.
    @MainActor
    func testResetButtonLabelSingleLine() throws {
        let app = launchApp(orientation: .portrait)
        let button = app.buttons["btn-reset"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Reset button not found")
        let height = button.frame.height
        XCTAssertLessThanOrEqual(
            height, singleLineLabelMaxHeight,
            "Reset button is \(height) pt tall — label may be wrapping"
        )
    }

    /// Landscape: Preset button label must not wrap onto two lines.
    ///
    /// On iPad the landscape layout switches to side-by-side mode where the
    /// card reader bar is always visible — the most likely place for wrapping.
    @MainActor
    func testPresetButtonLabelSingleLineLandscape() throws {
        let app = launchApp(orientation: .landscapeLeft)
        let button = app.buttons["btn-preset"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Preset button not found in landscape")
        let height = button.frame.height
        XCTAssertLessThanOrEqual(
            height, singleLineLabelMaxHeight,
            "Preset button is \(height) pt tall in landscape — label may be wrapping"
        )
    }
    #endif

    // MARK: - Screenshots

    /// Portrait screenshot for visual review.
    @MainActor
    func testScreenshotPortrait() throws {
        #if os(macOS)
        let app = launchApp()
        #else
        let app = launchApp(orientation: .portrait)
        #endif
        _ = app.buttons["btn-reset"].waitForExistence(timeout: 5)
        attachScreenshot(app, name: "Portrait — \(deviceDescription)")
    }

    #if !os(macOS)
    /// Landscape screenshot — important for iPad where the layout switches to
    /// side-by-side mode and the card reader bar must fit without wrapping.
    @MainActor
    func testScreenshotLandscape() throws {
        let app = launchApp(orientation: .landscapeLeft)
        _ = app.buttons["btn-preset"].waitForExistence(timeout: 5)
        attachScreenshot(app, name: "Landscape — \(deviceDescription)")
    }
    #endif

    // MARK: - Helpers

    private var deviceDescription: String {
        #if os(macOS)
        return "macOS"
        #else
        let device = UIDevice.current
        return "\(device.model) \(device.systemVersion)"
        #endif
    }
}
