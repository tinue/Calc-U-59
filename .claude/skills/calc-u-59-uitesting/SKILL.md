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
| `PresetLoadTests.swift` | End-to-end load of `test_diag.ti59` via the file picker; verifies keystroke playback starts |
| `ScreenshotTests.swift` | App Store screenshot capture (driven by `bin/run-screenshots`); writes PNGs to the dir named in `/tmp/calc-u-59-screenshot-dir` |
| `Calc_U_59UITestsLaunchTests.swift` | Default launch test (auto-generated, rarely edited) |
| `UIRegressionTests.xctestplan` | Local regression test plan (no CI job runs XCUITests) |
| `Screenshots.xctestplan` | Test plan for the screenshot run (`bin/run-screenshots`) |

The file-picker, preset and orientation tests are `#if !os(macOS)` guarded; `LayoutTests` also has macOS branches.

`launchApp()` adds the `--UITesting` launch argument. Without it `keystroke-playback-status` and `btn-key-rs` don't exist (`CalculatorView.isUITesting`, always false on macOS). Launch through the helpers.

---

## Running a Single Test Standalone

Click the diamond icon next to the test function in Xcode, or from the
terminal. Use a simulator from `bin/simulators status` (the configured set in
`bin/simulators.yaml`); never hard-code a model name from memory:

```bash
xcodebuild test \
  -project Calc-U-59.xcodeproj \
  -scheme "Calc-U-59" \
  -destination "platform=iOS Simulator,id=<UDID from bin/simulators status>" \
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

Screenshot tests that load `.ti59` files require those files to be present on the simulator's local storage. Run `bin/simulators setup` once before running tests — it ensures the target simulators from `bin/simulators.yaml` exist and installs state files into each one: an explicit list of files from `examples/` goes to the storage root, and everything from `examples/screentest/` goes into a `1-Testfiles/` folder (sorted first by name) in the simulator's "On My iPhone/iPad" storage. It also boots each new simulator once and launches the Files app, which is what initialises the AppGroup storage in the first place. `bin/simulators status` reports whether a machine is fully provisioned; `bin/simulators` alone prints the full command reference.

---

## Testing the debug panel (CALCULATOR/CPU/LOG tabs) — prefer iPad

On iPhone portrait the pages are calculator → printer → debug (`btn-page-right`), and `btn-page-left` on the calculator page goes straight to debug. The debug page (`DebugView`, holding `btn-tab-calculator`/`btn-tab-cpu`/`btn-tab-log`) exists only when Settings → "Debug Page in Portrait" is on (`SettingsKey.portraitDebugPage`, default `false`). A fresh iPhone simulator doesn't show it; turn the setting on through the Settings screen or by seeding `UserDefaults` before launch.

The iPad layout in landscape (and the iPhone Duo opened flat) shows the debug panel side-by-side with the calculator — no paging, no setting to flip. Which layout a window gets is Shared `mobileLayout` (by size, not idiom); `LayoutTests.testWideWindowShowsDebugger` checks it. When a test only needs to reach the debug tabs (e.g. checking the LOG tab's content after a KEYSTROKES script runs), prefer running it on an iPad simulator destination to skip this whole prerequisite.

---

## Accessibility Identifiers in the App

| Identifier | Type | Value / Notes |
|------------|------|---------------|
| `btn-preset` | Button | Preset toolbar button |
| `btn-reset` | Button | Reset toolbar button |
| `btn-settings` | Button | Settings toolbar button |
| `keystroke-playback-status` | OtherElement | `.accessibilityValue` = `"playing"` or `"idle"` |
| `btn-freeze-on-start` | Button | "FREEZE ON START" in CALCULATOR debug panel (`LiveDebugView`); label shows "F.START" in narrow layout |
| `btn-freeze-armed` | Button | "ARMED" in CALCULATOR debug tab; always present, enabled only while FREEZE ON START is pending; tap to disarm |
| `btn-page-left` | Button | Chevron-left page arrow (iPhone portrait only); destination depends on current page |
| `btn-page-right` | Button | Chevron-right page arrow (iPhone portrait only); destination depends on current page |
| `btn-tab-calculator` | Button | CALCULATOR tab in debug panel (`DebugView`) |
| `btn-tab-cpu` | Button | CPU tab in debug panel (`DebugView`) |
| `btn-tab-log` | Button | LOG tab in debug panel (`DebugView`) |
| `btn-cpu-freeze-on-start` | Button | "FREEZE ON START" in CPU tab (`CPUInspectorView`) |
| `btn-cpu-step` | Button | "STEP" in CPU tab (`CPUInspectorView`); tap to single-step, hold to auto-step. The CALCULATOR tab's STEP and the CPU tab's ARMED have no identifier |
| `btn-key-rs` | Button | 10×10 pt automation-only R/S key (`--UITesting`, iOS only): pressed on touch-down, released on touch-up, so `press(forDuration:)` works |
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
app.staticTexts["test_diag.ti59"].tap()

// CORRECT — taps the parent cell, picker loads the file
let cell = app.cells.containing(.staticText, identifier: "test_diag.ti59").firstMatch
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

`navigateToOnMyIPhone(_:targetFile:)` in `PresetLoadTests.swift` does this: return at once if the file is visible, else Browse tab → "On My iPhone/iPad" → `1-Testfiles`.

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

**Important:** register the predicate expectation *before* tapping the file, so the poll is already running when the transition happens. A short script can finish before an expectation registered after the tap starts polling.

```swift
let statusEl = app.otherElements["keystroke-playback-status"]
let playing = NSPredicate(format: "value == 'playing'")
let playbackStarted = XCTNSPredicateExpectation(predicate: playing, object: statusEl)

cell.tap()   // load the file

let result = XCTWaiter.wait(for: [playbackStarted], timeout: 8)
XCTAssertEqual(result, .completed, "File did not load — keystroke playback never started")
```

To keep the playing window wide enough to catch, end the script with a `Wait:` (playback counts as playing until the script ends), as `examples/screentest/test_diag.ti59` does:

```
KEYSTROKES:
FullSpeed:
15              # E — start
Wait: 1.5s
```

---

## Brittleness Notes

The system document picker is the most fragile part of the test suite. Things that can change between iOS/Xcode versions:

- Tab bar label strings ("Durchsuchen", "Browse")
- Location list strings ("Auf meinem iPhone", "On My iPhone")
- Cell element type (currently `cell`; could become `otherElement`)
- Grid vs. list layout (affects which queries match)

Things that are stable:
- Filenames (e.g. `"test_diag.ti59"`) — always your primary locator
- `keystroke-playback-status` — our own element, won't change
- `btn-preset`, `btn-reset`, `btn-settings` — our own identifiers
