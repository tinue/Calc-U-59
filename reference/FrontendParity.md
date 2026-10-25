# Frontend Parity (Swift app ↔ Qt6 app ↔ web client)

> **Provenance notice.** Maintained by hand (and by AI agents) — see
> CLAUDE.md § "Frontend Parity". Every user-visible feature has a row; a
> change to one frontend updates its row on the same branch.

All three GUIs run the same `Core/` and `Shared/` code; this table tracks
the GUI on top. The web client (`Web/`, `WebClient.md`) has two layouts:
wide (as the macOS/Qt window) and portrait (as the iPhone, no debugger).
Web paths are relative to `Web/src/` (`WebController` is
`Web/bindings.cpp`).

**Status:** `All` — in all three (web: in both layouts unless the Notes say
"wide only"); `Both` — in both apps, deliberately not in the web client; `Pending (Qt)` / `Pending (Swift)` / `Pending (Web)` —
the named one still to do (the Notes say why); `Swift only` / `Qt only` /
`Web only` — deliberately platform-specific.

## Calculator

| Feature | Swift | Qt | Web | Shared | Status | Notes |
|---|---|---|---|---|---|---|
| Model picker TI-59 / TI-58 / TI-58C | `CalculatorView` | `ControlBar` | `ControlBar` | `SessionController` startMachine, `MachineModelInfo` | All | |
| Reset; clean reset (Cmd/Ctrl held, red "Clean") | `CalculatorView` | `ControlBar` | `ControlBar` | `SessionController`, `StateApplier` softReset/cleanReset | All | iOS and web touch: 1 s long press |
| Calculator artwork, key hit test (widened rects) | `KeyboardView` | `KeyboardWidget` | `CalculatorFace`, `WebController` (hit test) | `KeyboardLayout` | All | Web: transparent key buttons for assistive technology |
| Pressed-key effect (blacked out, shifted 3 px) | `KeyboardView` | `KeyboardWidget` | `CalculatorFace` | — | All | |
| One key at a time; release on focus loss / teardown | `KeyboardView` | `KeyboardWidget` | `CalculatorFace`, `WebController` | — | All | |
| Hold display for full speed | `KeyboardView` | `KeyboardWidget` | `CalculatorFace`, `WebController` | `Pacing`, `KeyboardLayout` (`PointerTracker`) | All | |
| Physical keyboard (26 keys, Shift = 2nd, min. hold) | `KeyboardView` | `KeyboardWidget` | `PlayCalculator` (`keyboard` prop), `WebController` | `KeyboardMap`, `KeySequencer` | All | macOS only in the Swift app; web: only while the calculator has focus |
| LED display, Modernized / Classic styles | `LEDDisplayView` | `LedRenderer` | `painters.js` | `SevenSegment`, `LedGeometry` | All | Glow: SwiftUI blur / box-blur layers / Canvas 2D blur; web: Classic only |
| Digit and decimal-point brightness (persistence of vision), "C" indicator fade | `LEDDisplayView` | `LedRenderer` | `painters.js`, `WebController` | `FrameSampler`, `DisplayPov` | All | |
| Cue card: 3 templates, `\blank` spans, shrink-to-fit, inks | `CueCardView` | `CueCardRenderer` | `painters.js`, `WebController` (draw list) | `CueCard` (layout, geometry, inks) | All | |
| Module program cards (SCOM[9]), user cards | `EmulatorViewModel` | `EmulatorController` | `WebController` | `SessionController`, `CueCard` resolveCueCard | All | |
| Solid State module selection | `SettingsView` | `SettingsDialog` | `Dialogs` (Settings) | `ModuleCatalog` | All | soft reset on change |
| Startup calculator (model / last used) | `SettingsView` | `SettingsDialog` | `Dialogs` (Settings) | `SettingsKeys` | All | web: `localStorage`; the `model` prop overrides it |

## Files

| Feature | Swift | Qt | Web | Shared | Status | Notes |
|---|---|---|---|---|---|---|
| Open preset `.ti59` / `.ti58` / `.ti58c` | `CalculatorView` | `MainWindow` | `Dialogs` (preset picker: bundled, upload) | `SessionController` loadStateFile, `StateFile`, `StateApplier` | All | Web: bundled presets from `presets.json` |
| KEYSTROKES playback (Wait, FullSpeed, Trace, elapse) | `EmulatorViewModel` | `EmulatorController` | `WebController` | `EmulatorSession`, `KeySequencer` | All | Web: `Trace:` lines write to MEMFS, downloadable from the LOG tab |
| Drag-and-drop / open-with of state files | — | `MainWindow`, `main.cpp` | `PlayCalculator` (drop) | — | Qt only / Web only | Swift: file importer only; web: drop only |
| Magnetic cards: read, write blank, eject, auto-eject | `CalculatorView`, `CardPickerView` | `ControlBar`, `CardPickerDialog` | `ControlBar`, `Dialogs` (card picker), `WebController` | `SessionController` (card reader), `CardFile` (format, listed names) | All | TI-59 only; web: upload a card to read it, download one to keep it |
| Card and `ti58c.mem` location | iCloud Documents (`CardStorage`) | `~/Calc-U-59` (`AppPaths`) | session card folder and `localStorage` (`WebController`) | — | Swift only / Qt only / Web only | Qt: card folder in Settings; web: cards last for the page session |
| Open Preset start folder | system file importer | last used, or fixed in Settings | — | — | Qt only | Calc-U-1600 layout |
| TI-58C constant memory (save on change, restore) | `EmulatorViewModel` | `EmulatorController` | `WebController`, `engine.js` (`localStorage`) | `SessionController` (debounced persist), `ConstantMemory` | All | |

## Printer

| Feature | Swift | Qt | Web | Shared | Status | Notes |
|---|---|---|---|---|---|---|
| PC-100C connect toggle (resets) | `PrinterView` | `PrinterWidget` | `Printer` | `SessionController` | All | |
| Dot view at PC-100C proportions; text view | `PrinterView` | `PrinterWidget` | `Printer`, `painters.js` | `PrinterFont` PrinterGeometry | All | |
| Printer interrupt: cut-short lines, the interrupted row's fired columns, faint dots | `PrinterView` (`PrinterDotLine`) | `PrinterWidget` | `painters.js` | `PrinterFont` PrinterGeometry (`drawnRows`, `inkedColumns`, `faintColumns`) | All | |
| PRINT / ADV (hold), T (TRACE latch) | `PrinterView` | `PrinterWidget` | `Printer` | `SessionController` | All | |
| Copy (text + 600 dpi image), cut | `PrinterView` | `PrinterWidget` | `Printer` | `SessionController` (strip, cut), `PrinterFont` PrinterGeometry (strip height, copy scale) | All | web: image where the browser's clipboard takes one, else text |

## Debugger

| Feature | Swift | Qt | Web | Shared | Status | Notes |
|---|---|---|---|---|---|---|
| CALCULATOR tab: registers, flags, HIR, T, return stack, partition, source | `LiveDebugView` | `LiveDebugWidget` | `Debugger` (`LiveDebug`) | `DebugModel`, `DebugSnapshots`, `DebugText`, `ModuleImage` | All | web: wide only |
| Program steps ±5 running / full listing frozen | `LiveDebugView` | `LiveDebugWidget` | `Debugger` (`LiveDebug`) | `DebugModel` (listing, SolidStateReturn advance), `DebugSnapshots` | All | web: wide only |
| FREEZE, FREEZE ON START (next step), ARMED, RESUME, STEP (hold to repeat) | `LiveDebugView` | `LiveDebugWidget` | `Debugger` (`FreezeHeader`) | `EmulatorSession` (DebugState, freeze/step), `SessionController`, `FreezeController` | All | web: wide only |
| CPU tab: history, registers, control registers, display state | `CPUInspectorView` | `CpuInspectorWidget` | `Debugger` (`CpuInspector`) | `DebugModel` (cpuHistory), `DebugSnapshots`, `DebugText` | All | web: wide only |
| CPU FREEZE ON START (scan-loop exit), STEP | `CPUInspectorView` | `CpuInspectorWidget` | `Debugger` (`FreezeHeader`) | `EmulatorSession` (DebugState, stepInstruction), `SessionController`, `FreezeController` | All | web: wide only |
| ROM heatmap with hover address, CLR | `CPUInspectorView` | `RomHeatmapWidget` | `Debugger` (`Heatmap`) | `DebugModel`, `RomHeatmap` | All | web: wide only |
| ASM overlay: select, run, clear | `DebugView` | `AsmOverlayBox` | `Debugger` (`AsmOverlay`, upload) | `SessionController` loadAsm/runAsm/clearAsm, `AsmOverlay` | All | web: wide only |
| LOG tab: dumps, clear, log level | `DebugView` | `LogWidget` | `Debugger` (`LogTab`) | `SessionController` (dumps, level), `DebugModel` (RingLog), `DebugLog` | All | web: wide only |
| LOG kept across model switch | `DebugView` | `LogWidget` | `Debugger` (`LogTab`) | `DebugModel` (the LOG survives `attach`) | All | web: wide only |
| Binary trace (TRACE toggle), size limit | `DebugView` | `LogWidget` | `Debugger` (`LogTab`), `WebController` (MEMFS) | `SessionController` setManualTrace, `EmulatorSession` (manual / scripted writers), `TraceWriter` | All | web: wide only; downloaded when switched off |
| Trace location | Local / iCloud / custom | card folder, or trace folder in Settings | MEMFS, downloads | — | Swift only / Qt only / Web only | iCloud: Swift only; web: no location to choose |
| Breakpoints | — | — | — | Core API only (headless tools) | — | no UI in any GUI; the session ignores them |

## App

| Feature | Swift | Qt | Web | Shared | Status | Notes |
|---|---|---|---|---|---|---|
| About (version, links) | `AppInfo` | `AboutDialog` | `Dialogs` (About) | — | All | |
| Settings | `SettingsView` | `SettingsDialog` | `Dialogs` (Settings) | — | All | Qt: preset, card and trace folders instead of the trace location; web: no folders, no segment style |
| iOS layouts (portrait pages, iPhone), haptics, click sound | `CalculatorView`, `KeyboardView` | — | `PlayCalculator` (portrait layout, keyboard feedback) | — | Swift only / Web only | Swift: iOS only; web: vibrate where the browser can (not iOS Safari), click via WebAudio |
| UI test automation hooks | `CalculatorView` | — | — | — | Swift only | |
| `--grab <png>` offscreen screenshot | — | `main.cpp` | — | — | Qt only | developer check |
| Installable PWA, offline | — | — | `app/` | — | Web only | portrait layout; all three models offline |
| Pause while the page is hidden | — | — | `engine.js` (`visibilitychange`) | `SessionController` suspend/resume | Web only | |
