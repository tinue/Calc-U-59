---
name: calc-u-59-qt
description: Use this skill when working on the Qt6 desktop app of Calc-U-59 (Qt6/, Qt6/app/, Qt6/resources/, .github/workflows/build.yml, tools/build_qt.sh, build_and_run.sh, tools/gen_qt_icons.sh). Covers the class map against the Swift views, threading (the SessionController Platform's GUI-thread queue), building, packaging for Windows and Linux, and the parity rule with the Swift app. Trigger on any task that touches Qt6/ or the Qt CI workflow.
user-invocable: true
---

# Calc-U-59 Qt6 App

**Ship scope first:** the Qt app ships on **Windows and Linux** only (CI:
`.github/workflows/build.yml`, released through `release.yaml`). The **macOS
Qt build is local and for development only** — never shipped, never built in
CI, never signed. On the Mac the Swift app is the product. The Qt app has no
iCloud: cards, `ti58c.mem` and traces live in `~/Calc-U-59`, each folder (and
where Open Preset starts) set in Settings, as in Calc-U-1600 (`AppPaths`,
`AppSettings::OpenFolder`).

Reference: Calc-U-59's sibling project Calc-U-1600 (`~/Development/sharp/Calc-U-1600/Qt6`)
set the structure — Widgets, AUTOMOC/AUTORCC, no `.ui` files, QPainter rendering.

## Rules

1. **Parity with the Swift app** (CLAUDE.md § "Frontend Parity"): a
   user-visible change here needs the matching Swift change on the same
   branch, or a `Pending (Swift)` row in `reference/FrontendParity.md`.
   Update the table either way.
2. **No logic in `Qt6/app/`.** Anything that isn't Qt widgets, painting or
   file dialogs belongs in `Shared/` (calc-u-59-shared skill) so the Swift app
   gets it too. `EmulatorController` is a thin QObject adapter over
   `cu59::SessionController` (the same orchestrator the Swift app uses): it
   forwards actions and turns `changed(mask)` into Qt signals, nothing more.
3. **Threading is the controller's.** `EmulatorController` implements
   `SessionController::Platform` privately; its `runOnUiThread` queues jobs
   with `QMetaObject::invokeMethod(..., Qt::QueuedConnection)`, and the
   controller hops every session event to the GUI thread itself (see
   `reference/SharedArchitecture.md` § "SessionController").
4. **Assets have one source:** ROMs from `roms/` and artwork from
   `App/Assets.xcassets` are compiled in as Qt resources by `Qt6/CMakeLists.txt`;
   icons come from `App/AppIcon.icon` via `tools/gen_qt_icons.sh`. Never copy them.
5. **Settings keys** in `Qt6/app/AppSettings.hpp` match `App/AppSettings.swift`.
6. **Compile, don't run.** Build with the commands below. To check rendering
   without showing a window: `QT_QPA_PLATFORM=offscreen Qt6/build/Calc-U-59.app/Contents/MacOS/Calc-U-59 [state-file] --grab out.png --after 3000`
   (an offscreen screen may clamp the window size). Ask the user to try the app itself.
7. **Commit often, never push.**

## Class map

| Qt (`Qt6/app/`) | Swift counterpart |
|---|---|
| `main.cpp` | `Calc-U-59App.swift` |
| `MainWindow` | `CalculatorView` (layout, menus, presets, drag and drop) |
| `EmulatorController` | `EmulatorViewModel` |
| `CalculatorPanel`, `ControlBar` | `CalculatorView` calculator column and bar |
| `KeyboardWidget` | `KeyboardView` |
| `LedRenderer` | `LEDDisplayView` |
| `CueCardRenderer` | `CueCardView` |
| `PrinterWidget` | `PrinterView` |
| `CardPickerDialog` | `CardPickerView` |
| `debug/DebugPanel`, `AsmOverlayBox`, `LogWidget` | `DebugView` |
| `debug/LiveDebugWidget` | `LiveDebugView` |
| `debug/CpuInspectorWidget`, `RomHeatmapWidget` | `CPUInspectorView` |
| `HoldRepeatButton` | `HoldRepeatButton.swift` |
| `SettingsDialog`, `AppSettings.hpp`, `AppPaths` | `SettingsView`, `AppSettings.swift`, `CardStorage.swift` |
| `AboutDialog` | `AppInfo.swift` |

## Build

```bash
tools/build_qt.sh                 # Release build into Qt6/build (configures once)
./build_and_run.sh [file.ti59]    # build and start (user's call — see rule 6)
cmake -S . -B build/cmake -G Ninja && cmake --build build/cmake   # root build: tests + Qt app
```

Qt comes from Homebrew on macOS (`/opt/homebrew/opt/qt`, found automatically).
The version is read from the Xcode project's `MARKETING_VERSION`.

## Packaging (CI only)

- **Linux** x86_64 / aarch64: linuxdeploy + Qt plugin → AppImage, with the
  Wayland and platform-theme plugins and a GTK-theme `AppRun` wrapper.
- **Windows** x86_64 / arm64: windeployqt → Inno Setup
  (`Qt6/resources/windows/calc-u-59.iss`, state-file associations).
- `THIRD-PARTY-NOTICES.md` and `licenses/` ship with the packages (Qt LGPLv3).
