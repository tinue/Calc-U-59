# Frontend Parity (Swift app ↔ Qt6 app ↔ web client)

> **Provenance notice.** Maintained by hand (and by AI agents) — see
> CLAUDE.md § "Frontend Parity". Every user-visible feature has a row; a
> change to one frontend updates its row on the same branch.

All three GUIs run the same `Core/` and `Shared/` code; this table tracks
the GUI on top. The web client (`Web/`, `WebClient.md`) is deliberately
narrower — TI-59 only; no printer, debugger, traces or settings — so its
column is `—` for much of the apps. Web paths are relative to `Web/`
(`WebController` is `bindings.cpp`).

**Status:** `All` — in all three; `Both` — in both apps, deliberately not
in the web client; `Pending (Qt)` / `Pending (Swift)` / `Pending (Web)` —
the named one still to do (the Notes say why); `Swift only` / `Qt only` /
`Web only` — deliberately platform-specific.

## Calculator

| Feature | Swift | Qt | Web | Shared | Status | Notes |
|---|---|---|---|---|---|---|
| Model picker TI-59 / TI-58 / TI-58C | `CalculatorView` | `ControlBar` | — | `SessionController` startMachine, `MachineModelInfo` | Both | Web: TI-59 only |
| Reset; clean reset (Cmd/Ctrl held, red "Clean") | `CalculatorView` | `ControlBar` | — | `SessionController`, `StateApplier` softReset/cleanReset | Both | iOS: 1 s long press; web: changing the module resets |
| Calculator artwork, key hit test (widened rects) | `KeyboardView` | `KeyboardWidget` | `Calculator.jsx` (drawn keys, no artwork) | `KeyboardLayout` | All | Web: DOM buttons in the `CALC_ROWS` grid, no hit test |
| Pressed-key effect (blacked out, shifted 3 px) | `KeyboardView` | `KeyboardWidget` | `CalcKey` | — | All | Web: its own key chrome (darker, shifted 1 px) |
| One key at a time; release on focus loss / teardown | `KeyboardView` | `KeyboardWidget` | `PlayCalculator`, `WebController` | — | All | |
| Hold display for full speed | `KeyboardView` | `KeyboardWidget` | — | `Pacing` | Both | |
| Physical keyboard (26 keys, Shift = 2nd, min. hold) | `KeyboardView` | `KeyboardWidget` | `PlayCalculator` (`keyboard` prop), `WebController` | `KeyboardMap`, `KeySequencer` | All | macOS only in the Swift app; web: only while the calculator has focus |
| LED display, Modernized / Classic styles | `LEDDisplayView` | `LedRenderer` | `led-display.jsx` | `SevenSegment`, `LedGeometry` | All | Glow: SwiftUI blur / box-blur layers / Canvas 2D blur; web: Classic only |
| Digit and decimal-point brightness (persistence of vision), "C" indicator fade | `LEDDisplayView` | `LedRenderer` | `led-display.jsx`, `WebController` | `FrameSampler`, `DisplayPov` | All | |
| Cue card: 3 templates, `\blank` spans, shrink-to-fit, inks | `CueCardView` | `CueCardRenderer` | `cuecard.jsx` | `CueCard` (layout, geometry, inks) | All | Web: shrink-to-fit measured in the DOM, no bank badges |
| Module program cards (SCOM[9]), user cards | `EmulatorViewModel` | `EmulatorController` | `WebController` | `SessionController`, `CueCard` resolveCueCard | All | |
| Solid State module selection | `SettingsView` | `SettingsDialog` | `PlayControls` | `ModuleCatalog` | All | soft reset on change; web: picker under the calculator |
| Startup calculator (model / last used) | `SettingsView` | `SettingsDialog` | — | `SettingsKeys` | Both | |

## Files

| Feature | Swift | Qt | Web | Shared | Status | Notes |
|---|---|---|---|---|---|---|
| Open preset `.ti59` / `.ti58` / `.ti58c` | `CalculatorView` | `MainWindow` | `PlayControls` (preset picker, upload) | `SessionController` loadStateFile, `StateFile`, `StateApplier` | All | Web: presets from `presets.json` |
| KEYSTROKES playback (Wait, FullSpeed, Trace, elapse) | `EmulatorViewModel` | `EmulatorController` | `WebController` | `EmulatorSession`, `KeySequencer` | All | Web: `Trace:` lines report an error |
| Drag-and-drop / open-with of state files | — | `MainWindow`, `main.cpp` | — | — | Qt only | Swift: file importer only |
| Magnetic cards: read, write blank, eject, auto-eject | `CalculatorView`, `CardPickerView` | `ControlBar`, `CardPickerDialog` | `PlayControls` (Queue Card), `WebController` | `SessionController` (card reader), `CardFile` (format, listed names) | All | TI-59 only; web: one virtual card, blank until written |
| Card and `ti58c.mem` location | iCloud Documents (`CardStorage`) | `~/Calc-U-59` (`AppPaths`) | page memory (`WebController`) | — | Swift only / Qt only / Web only | Qt: card folder in Settings; web: the card lasts for the page session |
| Open Preset start folder | system file importer | last used, or fixed in Settings | — | — | Qt only | Calc-U-1600 layout |
| TI-58C constant memory (save on change, restore) | `EmulatorViewModel` | `EmulatorController` | — | `SessionController` (debounced persist), `ConstantMemory` | Both | |

## Printer

| Feature | Swift | Qt | Web | Shared | Status | Notes |
|---|---|---|---|---|---|---|
| PC-100C connect toggle (resets) | `PrinterView` | `PrinterWidget` | — | `SessionController` | Both | |
| Dot view at PC-100C proportions; text view | `PrinterView` | `PrinterWidget` | — | `PrinterFont` PrinterGeometry | Both | |
| PRINT / ADV (hold), T (TRACE latch) | `PrinterView` | `PrinterWidget` | — | `SessionController` | Both | |
| Copy (text + 600 dpi image), cut | `PrinterView` | `PrinterWidget` | — | `SessionController` (strip, cut), `PrinterFont` PrinterGeometry (strip height, copy scale) | Both | |

## Debugger

| Feature | Swift | Qt | Web | Shared | Status | Notes |
|---|---|---|---|---|---|---|
| CALCULATOR tab: registers, flags, HIR, T, return stack, partition, source | `LiveDebugView` | `LiveDebugWidget` | — | `DebugModel`, `DebugSnapshots`, `DebugText`, `ModuleImage` | Both | |
| Program steps ±5 running / full listing frozen | `LiveDebugView` | `LiveDebugWidget` | — | `DebugModel` (listing, SolidStateReturn advance), `DebugSnapshots` | Both | |
| FREEZE, FREEZE ON START (next step), ARMED, RESUME, STEP (hold to repeat) | `LiveDebugView` | `LiveDebugWidget` | — | `EmulatorSession` (DebugState, freeze/step), `SessionController`, `FreezeController` | Both | |
| CPU tab: history, registers, control registers, display state | `CPUInspectorView` | `CpuInspectorWidget` | — | `DebugModel` (cpuHistory), `DebugSnapshots`, `DebugText` | Both | |
| CPU FREEZE ON START (scan-loop exit), STEP | `CPUInspectorView` | `CpuInspectorWidget` | — | `EmulatorSession` (DebugState, stepInstruction), `SessionController`, `FreezeController` | Both | |
| ROM heatmap with hover address, CLR | `CPUInspectorView` | `RomHeatmapWidget` | — | `DebugModel`, `RomHeatmap` | Both | |
| ASM overlay: select, run, clear | `DebugView` | `AsmOverlayBox` | — | `SessionController` loadAsm/runAsm/clearAsm, `AsmOverlay` | Both | |
| LOG tab: dumps, clear, log level | `DebugView` | `LogWidget` | — | `SessionController` (dumps, level), `DebugModel` (RingLog), `DebugLog` | Both | |
| LOG kept across model switch | `DebugView` | `LogWidget` | — | `DebugModel` (the LOG survives `attach`) | Both | |
| Binary trace (TRACE toggle), size limit | `DebugView` | `LogWidget` | — | `SessionController` setManualTrace, `EmulatorSession` (manual / scripted writers), `TraceWriter` | Both | |
| Trace location | Local / iCloud / custom | card folder, or trace folder in Settings | — | — | Both | iCloud: Swift only |
| Breakpoints | — | — | — | Core API only (headless tools) | — | no UI in any GUI; the session ignores them |

## App

| Feature | Swift | Qt | Web | Shared | Status | Notes |
|---|---|---|---|---|---|---|
| About (version, links) | `AppInfo` | `AboutDialog` | — | — | Both | |
| Settings | `SettingsView` | `SettingsDialog` | — | — | Both | Qt: preset, card and trace folders instead of the trace location |
| iOS layouts (portrait pages, iPhone), haptics, click sound | `CalculatorView`, `KeyboardView` | — | — | — | Swift only | |
| UI test automation hooks | `CalculatorView` | — | — | — | Swift only | |
| `--grab <png>` offscreen screenshot | — | `main.cpp` | — | — | Qt only | developer check |
| Installable PWA, offline (Master Library only) | — | — | `app/` | — | Web only | |
| Pause while the page is hidden | — | — | `PlayCalculator` (`visibilitychange`) | `SessionController` suspend/resume | Web only | |
