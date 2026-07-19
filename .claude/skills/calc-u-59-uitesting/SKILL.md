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
| `ScreenshotTests.swift` | App Store screenshot capture (driven by `bin/run-screenshots`); writes PNGs to the dir named in `/tmp/calc-u-59-screenshot-dir` |
| `Calc_U_59UITestsLaunchTests.swift` | Default launch test (auto-generated, rarely edited) |
| `UIRegressionTests.xctestplan` | Test plan used by CI |
| `Screenshots.xctestplan` | Test plan for the screenshot run (`bin/run-screenshots`) |

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

### Writing screenshots to the Mac filesystem

In the XCUITest process, `HOME` and `NSHomeDirectory()` point to the **simulator sandbox**, not the Mac. Use `SIMULATOR_HOST_HOME` to get the real Mac home directory:

```swift
let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? "/tmp"
let dest = URL(fileURLWithPath: "\(home)/Desktop/shot.png")
```

To pass a target directory from a driving script into the test process, use the handoff-file pattern from `bin/run-screenshots`: the script writes the directory path to `/tmp/calc-u-59-screenshot-dir` before invoking `xcodebuild`, and `ScreenshotTests.swift` reads that file at runtime (env vars don't cross the `xcodebuild` → test-runner boundary without scheme changes).

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

Screenshot tests that load `.ti59` files require those files to be present on the simulator's local storage. Run `bin/setup-simulators` once before running tests — it ensures the target simulators exist and installs state files into each one: an explicit list of files from `examples/` goes to the storage root, and everything from `examples/screentest/` goes into a `1-Testfiles/` folder (sorted first by name) in the simulator's "On My iPhone/iPad" storage. Simulators must have opened the Files app or the file picker at least once for the AppGroup storage to be initialised.

---

## Testing the debug panel (CALCULATOR/CPU/LOG tabs) — prefer iPad

On iPhone portrait, the debug panel (`DebugView`, holding `btn-tab-calculator`/`btn-tab-cpu`/`btn-tab-log`) lives on a second page reached via `btn-page-right`, and that page only exists at all when the `SettingsKey.portraitDebugPage` `@AppStorage` toggle is on (default `false` — see `App/Views/CalculatorView.swift:41`). A fresh iPhone simulator won't show it, and `btn-page-right` may not even reveal the debug tabs until that setting is flipped on (e.g. via the Settings screen, or by seeding `UserDefaults` before launch).

The iPad layout shows the debug panel side-by-side with the calculator permanently — no paging, no setting to flip. When a test only needs to reach the debug tabs (e.g. checking the LOG tab's content after a KEYSTROKES script runs), prefer running it on an iPad simulator destination to skip this whole prerequisite.

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
| `btn-page-left` | Button | Chevron-left page arrow (iPhone portrait only); destination depends on current page |
| `btn-page-right` | Button | Chevron-right page arrow (iPhone portrait only); destination depends on current page |
| `btn-tab-calculator` | Button | CALCULATOR tab in debug panel (`DebugView`) |
| `btn-tab-cpu` | Button | CPU tab in debug panel (`DebugView`) |
| `btn-tab-log` | Button | LOG tab in debug panel (`DebugView`) |
| `btn-cpu-freeze-on-start` | Button | "FREEZE ON START" in CPU tab (`CPUInspectorView`) |
| `btn-cpu-step` | Button | "STEP" in CPU tab (`CPUInspectorView`); tap to single-step, hold to auto-step |
| `btn-key-rs` | Button | 1×1 automation-only button; calls `viewModel.pressKey(row: 8, col: 0)` (R/S); invisible to users, reachable by XCUITest |
| `btn-asm-select` | Button | "Select File" in ASM overlay (`ASMDebugContent` in `DebugView`); opens `.asm` file picker |
| `btn-asm-run` | Button | "Run" in ASM overlay; disabled until a file is loaded (`vm.canRunASM`) |
| `btn-freeze` | Button | "FREEZE" in CALCULATOR debug tab (`LiveDebugView`) |
| `btn-resume` | Button | "RESUME" in CALCULATOR debug tab (`LiveDebugView`); left of FREEZE |

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

### 2. Use `tabBars.buttons` / `cells` to avoid ambiguous matches

Several picker labels appear in two places simultaneously:

- **Browse tab** ("Durchsuchen" / "Browse"): in the tab bar and as a back-button in the navigation bar. Use `app.tabBars.buttons[label]` to target the tab bar only.
- **"On My iPhone/iPad"**: in the sidebar cell list and as the navigation bar title once selected. Use `app.cells.containing(.staticText, identifier: label).firstMatch` — the nav bar title is not inside a cell.

Never use bare `app.buttons[label]` or `app.staticTexts[label]` for these — both will find multiple matches and crash.

### 3. Fast-path is safe because test filenames are unique

All files in `1-Testfiles/` (sourced from `examples/screentest/`) are prefixed with `test_` (e.g. `test_diag.ti59`). This prefix is never used for files in the root, so a fast-path check is unambiguous: if the file is already visible, we are already inside `1-Testfiles`.

```swift
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
