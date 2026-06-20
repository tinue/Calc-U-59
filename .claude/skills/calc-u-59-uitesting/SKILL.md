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

## Screenshots and Rotation

### Use `XCUIScreen.main.screenshot()`, not `app.screenshot()`

`app.screenshot()` always captures in the device's **natural portrait coordinate space**, regardless of how the simulator is oriented. On a rotated iPad, this produces a portrait-framed PNG with landscape content rotated 90° — not what you want.

`XCUIScreen.main.screenshot()` captures the **physical screen pixels** and produces a correctly-oriented PNG — no post-processing or rotation needed. This works whether the orientation was set programmatically via `XCUIDevice.shared.orientation` or by manually rotating the simulator window:

```swift
let png = XCUIScreen.main.screenshot().pngRepresentation
let dest = URL(fileURLWithPath: "/Users/me/Desktop/my-screenshot.png")
try png.write(to: dest)
```

**Note:** Device bezels only appear in screenshots taken via the simulator's camera button. `XCUIScreen.main.screenshot()` captures app pixels only — bezels are never included.

---

## Device Detection

`UIDevice.current.userInterfaceIdiom` is available in the test process and reliably distinguishes iPhone from iPad at runtime:

```swift
let orientation: UIDeviceOrientation = UIDevice.current.userInterfaceIdiom == .pad
    ? .landscapeLeft : .portrait
let app = launchApp(orientation: orientation)
```

Use this whenever the app layout differs between form factors — for example, the iPad uses a landscape side-by-side layout while iPhone uses portrait.

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

## State File Prerequisites

Screenshot tests that load `.ti59` files require those files to be present on the simulator's local storage. Run `bin/setup-simulator-state-files` once per simulator before running tests — it installs all files from `examples/` (including `examples/debug/`) into every simulator's "On My iPhone/iPad" storage. Simulators must have opened the Files app or the file picker at least once for the AppGroup storage to be initialised.

---

## Accessibility Identifiers in the App

| Identifier | Type | Value / Notes |
|------------|------|---------------|
| `btn-preset` | Button | Preset toolbar button |
| `btn-reset` | Button | Reset toolbar button |
| `btn-settings` | Button | Settings toolbar button |
| `keystroke-playback-status` | OtherElement | `.accessibilityValue` = `"playing"` or `"idle"` |
| `btn-freeze-on-start` | Button | "FREEZE ON START" in CALCULATOR debug panel (`LiveDebugView`); label shows "F.START" in narrow layout |
| `btn-freeze-armed` | Button | "ARMED" — shown in place of `btn-freeze-on-start` while freeze is pending; tap to disarm |

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

### 3. Always navigate unconditionally

Do not use a fast-path that checks whether the target file is already visible — if the same file exists in both the root and inside `1-Testfiles`, the fast-path would match the wrong copy and skip the folder navigation entirely. Always navigate through Browse → On My iPhone/iPad → 1-Testfiles. When the picker is already inside `1-Testfiles` (e.g. second load in the same test), the intermediate steps time out silently and nothing extra is tapped.

```swift
private func navigateToOnMyIPhone(_ app: XCUIApplication, targetFile: String) {
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
