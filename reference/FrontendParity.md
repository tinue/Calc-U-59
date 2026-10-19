# Frontend Parity (Swift app ↔ Qt6 app)

> **Provenance notice.** Maintained by hand (and by AI agents) — see
> CLAUDE.md § "Frontend Parity". Every user-visible feature has a row; a
> change to one frontend updates its row on the same branch.

Both apps run the same `Core/` and `Shared/` code; this table tracks the GUI
on top. **Status:** `Both` — present in both; `Pending (Qt)` / `Pending
(Swift)` — present in one, the other still to do (the Notes say why);
`Swift only` / `Qt only` — deliberately platform-specific.

The web calculator (`docs/play/`) runs the same `SessionController` but has a
narrower feature set (TI-59 only; no printer, debugger or traces) and is not
tracked here (see `NewGUIGuide.md`).

## Calculator

| Feature | Swift | Qt | Shared | Status | Notes |
|---|---|---|---|---|---|
| Model picker TI-59 / TI-58 / TI-58C | `CalculatorView` | `ControlBar` | `SessionController` startMachine, `MachineModelInfo` | Both | |
| Reset; clean reset (Cmd/Ctrl held, red "Clean") | `CalculatorView` | `ControlBar` | `SessionController`, `StateApplier` softReset/cleanReset | Both | iOS: 1 s long press |
| Calculator artwork, key hit test (widened rects) | `KeyboardView` | `KeyboardWidget` | `KeyboardLayout` | Both | |
| Pressed-key effect (blacked out, shifted 3 px) | `KeyboardView` | `KeyboardWidget` | — | Both | |
| One key at a time; release on focus loss / teardown | `KeyboardView` | `KeyboardWidget` | — | Both | |
| Hold display for full speed | `KeyboardView` | `KeyboardWidget` | `Pacing` | Both | |
| Physical keyboard (26 keys, Shift = 2nd, min. hold) | `KeyboardView` | `KeyboardWidget` | `KeyboardMap`, `KeySequencer` | Both | macOS only in the Swift app |
| LED display, Modernized / Classic styles | `LEDDisplayView` | `LedRenderer` | `SevenSegment`, `LedGeometry` | Both | Glow: SwiftUI blur / box-blur layers |
| Digit and decimal-point brightness (persistence of vision), "C" indicator fade | `LEDDisplayView` | `LedRenderer` | `FrameSampler`, `DisplayPov` | Both | |
| Cue card: 3 templates, `\blank` spans, shrink-to-fit, inks | `CueCardView` | `CueCardRenderer` | `CueCard` (layout, geometry, inks) | Both | |
| Module program cards (SCOM[9]), user cards | `EmulatorViewModel` | `EmulatorController` | `SessionController`, `CueCard` resolveCueCard | Both | |
| Solid State module selection | `SettingsView` | `SettingsDialog` | `ModuleCatalog` | Both | soft reset on change |
| Startup calculator (model / last used) | `SettingsView` | `SettingsDialog` | `SettingsKeys` | Both | |

## Files

| Feature | Swift | Qt | Shared | Status | Notes |
|---|---|---|---|---|---|
| Open preset `.ti59` / `.ti58` / `.ti58c` | `CalculatorView` | `MainWindow` | `SessionController` loadStateFile, `StateFile`, `StateApplier` | Both | |
| KEYSTROKES playback (Wait, FullSpeed, Trace, elapse) | `EmulatorViewModel` | `EmulatorController` | `EmulatorSession`, `KeySequencer` | Both | |
| Drag-and-drop / open-with of state files | — | `MainWindow`, `main.cpp` | — | Qt only | Swift: file importer only |
| Magnetic cards: read, write blank, eject, auto-eject | `CalculatorView`, `CardPickerView` | `ControlBar`, `CardPickerDialog` | `SessionController` (card reader), `CardFile` (format, listed names) | Both | TI-59 only |
| Card and `ti58c.mem` location | iCloud Documents (`CardStorage`) | `~/Calc-U-59` (`AppPaths`) | — | Swift only / Qt only | Qt: card folder in Settings |
| Open Preset start folder | system file importer | last used, or fixed in Settings | — | Qt only | Calc-U-1600 layout |
| TI-58C constant memory (save on change, restore) | `EmulatorViewModel` | `EmulatorController` | `SessionController` (debounced persist), `ConstantMemory` | Both | |

## Printer

| Feature | Swift | Qt | Shared | Status | Notes |
|---|---|---|---|---|---|
| PC-100C connect toggle (resets) | `PrinterView` | `PrinterWidget` | `SessionController` | Both | |
| Dot view at PC-100C proportions; text view | `PrinterView` | `PrinterWidget` | `PrinterFont` PrinterGeometry | Both | |
| PRINT / ADV (hold), T (TRACE latch) | `PrinterView` | `PrinterWidget` | `SessionController` | Both | |
| Copy (text + 600 dpi image), cut | `PrinterView` | `PrinterWidget` | `SessionController` (strip, cut), `PrinterFont` PrinterGeometry (strip height, copy scale) | Both | |

## Debugger

| Feature | Swift | Qt | Shared | Status | Notes |
|---|---|---|---|---|---|
| CALCULATOR tab: registers, flags, HIR, T, return stack, partition, source | `LiveDebugView` | `LiveDebugWidget` | `DebugModel`, `DebugSnapshots`, `DebugText`, `ModuleImage` | Both | |
| Program steps ±5 running / full listing frozen | `LiveDebugView` | `LiveDebugWidget` | `DebugModel` (listing, SolidStateReturn advance), `DebugSnapshots` | Both | |
| FREEZE, FREEZE ON START (next step), ARMED, RESUME, STEP (hold to repeat) | `LiveDebugView` | `LiveDebugWidget` | `EmulatorSession` (DebugState, freeze/step), `SessionController`, `FreezeController` | Both | |
| CPU tab: history, registers, control registers, display state | `CPUInspectorView` | `CpuInspectorWidget` | `DebugModel` (cpuHistory), `DebugSnapshots`, `DebugText` | Both | |
| CPU FREEZE ON START (scan-loop exit), STEP | `CPUInspectorView` | `CpuInspectorWidget` | `EmulatorSession` (DebugState, stepInstruction), `SessionController`, `FreezeController` | Both | |
| ROM heatmap with hover address, CLR | `CPUInspectorView` | `RomHeatmapWidget` | `DebugModel`, `RomHeatmap` | Both | |
| ASM overlay: select, run, clear | `DebugView` | `AsmOverlayBox` | `SessionController` loadAsm/runAsm/clearAsm, `AsmOverlay` | Both | |
| LOG tab: dumps, clear, log level | `DebugView` | `LogWidget` | `SessionController` (dumps, level), `DebugModel` (RingLog), `DebugLog` | Both | |
| LOG kept across model switch | `DebugView` | `LogWidget` | `DebugModel` (the LOG survives `attach`) | Both | |
| Binary trace (TRACE toggle), size limit | `DebugView` | `LogWidget` | `SessionController` setManualTrace, `EmulatorSession` (manual / scripted writers), `TraceWriter` | Both | |
| Trace location | Local / iCloud / custom | card folder, or trace folder in Settings | — | Both | iCloud: Swift only |
| Breakpoints | — | — | Core API only (headless tools) | — | no UI in either app; the session ignores them |

## App

| Feature | Swift | Qt | Shared | Status | Notes |
|---|---|---|---|---|---|
| About (version, links) | `AppInfo` | `AboutDialog` | — | Both | |
| Settings | `SettingsView` | `SettingsDialog` | — | Both | Qt: preset, card and trace folders instead of the trace location |
| iOS layouts (portrait pages, iPhone), haptics, click sound | `CalculatorView`, `KeyboardView` | — | — | Swift only | |
| UI test automation hooks | `CalculatorView` | — | — | Swift only | |
| `--grab <png>` offscreen screenshot | — | `main.cpp` | — | Qt only | developer check |
