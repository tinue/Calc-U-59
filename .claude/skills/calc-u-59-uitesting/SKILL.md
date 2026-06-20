---
name: calc-u-59-uitesting
description: Use this skill when writing or debugging XCUITest UI tests for Calc-U-59 (Calc-U-59UITests/). Covers test helpers, file picker navigation, accessibility identifiers, orientation setup, and how to verify state after a load. Trigger on any task that touches Calc-U-59UITests/*.swift or *.xctestplan.
user-invocable: true
---

# Calc-U-59 UI Testing

This skill covers all work inside `Calc-U-59UITests/`.

---

## Test Files

| File | Purpose |
|------|---------|
| `AppHelpers.swift` | Shared helpers: `launchApp()`, `launchApp(orientation:)`, `attachScreenshot()` |
| `LayoutTests.swift` | Button visibility, label-wrapping, portrait/landscape screenshots |
| `FilePickerTests.swift` | File picker opens; reopens after cancel (regression for iPad popover dismiss bug) |
| `PresetLoadTests.swift` | End-to-end load of `diag.ti59` via file picker; verifies keystroke playback starts |
| `Calc_U_59UITestsLaunchTests.swift` | Default launch test (auto-generated, rarely edited) |
| `UIRegressionTests.xctestplan` | Test plan used by CI |

All tests are `#if !os(macOS)` guarded (the file picker and orientation APIs are iOS-only).

---

## Running a Single Test Standalone

Click the diamond icon next to the test function in Xcode, or from the terminal:

```bash
xcodebuild test \
  -project Calc-U-59.xcodeproj \
  -scheme "Calc-U-59" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest" \
  -only-testing "Calc-U-59UITests/PresetLoadTests/testLoadDiagPreset"
```

---

## Orientation

Always set orientation **before** `app.launch()` to avoid simulator state leaking between runs. The shared helper does this:

```swift
let app = launchApp(orientation: .portrait)  // sets XCUIDevice.shared.orientation first
```

Reset in `tearDown`:

```swift
override class func tearDown() {
    XCUIDevice.shared.orientation = .portrait
    super.tearDown()
}
```

---

## Accessibility Identifiers in the App

| Identifier | Type | Value / Notes |
|------------|------|---------------|
| `btn-preset` | Button | Preset toolbar button |
| `btn-reset` | Button | Reset toolbar button |
| `btn-settings` | Button | Settings toolbar button |
| `keystroke-playback-status` | OtherElement | `.accessibilityValue` = `"playing"` or `"idle"` |

---

## Navigating the System Document Picker (fileImporter)

The iOS system document picker (`UIDocumentPickerViewController`) is driven by XCUITest as a sheet within the app's window. Several non-obvious rules apply:

### 1. Tap the *cell*, not the filename label

The picker shows files as collection view cells. Each cell contains inner labels (filename, date, size). Sending a tap to an inner `staticText` does **not** trigger file selection — only tapping the cell itself works.

```swift
// WRONG — taps the label, picker stays open
app.staticTexts["diag.ti59"].tap()

// CORRECT — taps the parent cell, picker loads the file
let cell = app.cells.containing(.staticText, identifier: "diag.ti59").firstMatch
XCTAssertTrue(cell.waitForExistence(timeout: 5))
cell.tap()
```

### 2. Use `tabBars.buttons` for the Browse tab, not `buttons`

The Browse tab button (labeled "Durchsuchen" in German, "Browse" in English) appears twice in the accessibility hierarchy once Browse is active: once in the tab bar and once as a back-button in the navigation bar. `app.buttons["Durchsuchen"]` is ambiguous and crashes. Use:

```swift
app.tabBars.buttons["Durchsuchen"]   // targets tab bar only
```

### 3. Fast-path: picker usually opens at last-used location

The picker remembers its last location. In practice it often opens directly at "On My iPhone", so navigation is a no-op. Always check for the target cell first before navigating:

```swift
private func navigateToOnMyIPhone(_ app: XCUIApplication, targetFile: String) {
    if app.cells.containing(.staticText, identifier: targetFile).firstMatch
           .waitForExistence(timeout: 2) { return }

    for label in ["Durchsuchen", "Browse"] {
        let tab = app.tabBars.buttons[label]
        if tab.waitForExistence(timeout: 2) {
            if !tab.isSelected { tab.tap() }
            break
        }
    }

    for label in ["Auf meinem iPhone", "On My iPhone"] {
        let item = app.staticTexts[label]
        if item.waitForExistence(timeout: 2) { item.tap(); break }
    }
}
```

### 4. Locale-dependent labels

Navigation labels are locale-dependent. The helpers above try German first (device is German), then English. Any third locale will fail silently at the navigation step — the file cell check will then time out with a useful error.

### Debugging picker element tree

When the picker changes between iOS versions, dump the hierarchy after opening it:

```swift
presetButton.tap()
_ = app.buttons["Cancel"].waitForExistence(timeout: 3)  // wait for picker
print(app.debugDescription)
```

---

## Verifying a Successful Preset Load

`keystroke-playback-status` (an `OtherElement` overlay in `CalculatorView`) exposes `isKeystrokesPlaying` as its accessibility value (`"playing"` / `"idle"`). Use it to confirm that a state file with a `KEYSTROKES:` section was actually loaded and the keystrokes started.

**Important:** register the predicate expectation *before* tapping the file, so the poll is already running when the transition happens. A single 500 ms keystroke can be missed if the expectation is registered after the tap.

```swift
let statusEl = app.otherElements["keystroke-playback-status"]
let playing = NSPredicate(format: "value == 'playing'")
let playbackStarted = XCTNSPredicateExpectation(predicate: playing, object: statusEl)

cell.tap()   // load the file

let result = XCTWaiter.wait(for: [playbackStarted], timeout: 8)
XCTAssertEqual(result, .completed, "File did not load — keystroke playback never started")
```

To make the playing window wide enough to catch reliably, add `WaitFullSpeed: Xs` to the state file's `KEYSTROKES:` section (keeps `isKeystrokesPlaying = true` for the full duration):

```
KEYSTROKES:
15              # E — start
WaitFullSpeed: 3s
```

---

## Brittleness Notes

The system document picker is the most fragile part of the test suite. Things that can change between iOS/Xcode versions:

- Tab bar label strings ("Durchsuchen", "Browse")
- Location list strings ("Auf meinem iPhone", "On My iPhone")
- Cell element type (currently `cell`; could become `otherElement`)
- Grid vs. list layout (affects which queries match)

Things that are stable:
- Filenames (e.g. `"diag.ti59"`) — always your primary locator
- `keystroke-playback-status` — our own element, won't change
- `btn-preset`, `btn-reset`, `btn-settings` — our own identifiers
