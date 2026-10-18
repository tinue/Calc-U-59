# Frontend Parity (Swift app ↔ Qt6 app)

> **Provenance notice.** Maintained by hand (and by AI agents) — see
> CLAUDE.md § "Frontend Parity". Every user-visible feature has a row; a
> change to one frontend updates its row on the same branch.

Both apps run the same `Core/` and `Shared/` code; this table tracks the GUI
on top. **Status:** `Both` — present in both; `Pending (Qt)` / `Pending
(Swift)` — present in one, the other still to do (the Notes say why);
`Swift only` / `Qt only` — deliberately platform-specific.

The web build (`docs/#play`) has its own, narrower feature set and is not
tracked here (see `NewGUIGuide.md`).

## Calculator

| Feature | Swift | Qt | Shared | Status | Notes |
|---|---|---|---|---|---|
| Model picker TI-59 / TI-58 / TI-58C | `CalculatorView` | `ControlBar` | `MachineModelInfo` | Both | |
| Reset; clean reset (Cmd/Ctrl held, red "Clean") | `CalculatorView` | `ControlBar` | `StateApplier` softReset/cleanReset | Both | iOS: 1 s long press |
| Calculator artwork, key hit test (widened rects) | `KeyboardView` | `KeyboardWidget` | `KeyboardLayout` | Both | |
| Pressed-key effect (blacked out, shifted 3 px) | `KeyboardView` | `KeyboardWidget` | — | Both | |
| One key at a time; release on focus loss / teardown | `KeyboardView` | `KeyboardWidget` | — | Both | |
| Hold display for full speed | `KeyboardView` | `KeyboardWidget` | `Pacing` | Both | |
| Physical keyboard (26 keys, Shift = 2nd, min. hold) | `KeyboardView` | `KeyboardWidget` | `KeyboardMap`, `KeySequencer` | Both | macOS only in the Swift app |
| LED display, Modernized / Classic styles | `LEDDisplayView` | `LedRenderer` | `SevenSegment`, `LedGeometry` | Both | Glow: SwiftUI blur / box-blur layers |
| Decimal-point afterglow, "C" indicator fade | `LEDDisplayView` | `LedRenderer` | `FrameSampler` | Both | |
| Cue card: 3 templates, `\blank` spans, shrink-to-fit, inks | `CueCardView` | `CueCardRenderer` | `CueCard` | Both | |
| Module program cards (SCOM[9]), user cards | `EmulatorViewModel` | `EmulatorController` | `CueCard` resolveCueCard | Both | |
| Solid State module selection | `SettingsView` | `SettingsDialog` | `ModuleCatalog` | Both | soft reset on change |
| Startup calculator (model / last used) | `SettingsView` | `SettingsDialog` | `SettingsKeys` | Both | |

## Files

| Feature | Swift | Qt | Shared | Status | Notes |
|---|---|---|---|---|---|
| Open preset `.ti59` / `.ti58` / `.ti58c` | `CalculatorView` | `MainWindow` | `StateFile`, `StateApplier` | Both | |
| KEYSTROKES playback (Wait, FullSpeed, Trace, elapse) | `EmulatorViewModel` | `EmulatorController` | `KeySequencer` | Both | |
| Drag-and-drop / open-with of state files | — | `MainWindow`, `main.cpp` | — | Qt only | Swift: file importer only |
| Magnetic cards: read, write blank, eject, auto-eject | `CalculatorView`, `CardPickerView` | `ControlBar`, `CardPickerDialog` | `CardFile` (format, listed names) | Both | TI-59 only |
| Card and `ti58c.mem` location | iCloud Documents (`CardStorage`) | `~/Calc-U-59` (`AppPaths`) | — | Swift only / Qt only | Qt: card folder in Settings |
| Open Preset start folder | system file importer | last used, or fixed in Settings | — | Qt only | Calc-U-1600 layout |
| TI-58C constant memory (save on change, restore) | `EmulatorViewModel` | `EmulatorController` | `ConstantMemory` | Both | |

## Printer

| Feature | Swift | Qt | Shared | Status | Notes |
|---|---|---|---|---|---|
| PC-100C connect toggle (resets) | `PrinterView` | `PrinterWidget` | — | Both | |
| Dot view at PC-100C proportions; text view | `PrinterView` | `PrinterWidget` | `PrinterFont` PrinterGeometry | Both | |
| PRINT / ADV (hold), T (TRACE latch) | `PrinterView` | `PrinterWidget` | — | Both | |
| Copy (text + 600 dpi image), cut | `PrinterView` | `PrinterWidget` | `PrinterFont` PrinterGeometry (strip height, copy scale) | Both | |

## Debugger

| Feature | Swift | Qt | Shared | Status | Notes |
|---|---|---|---|---|---|
| CALCULATOR tab: registers, flags, HIR, T, return stack, partition, source | `LiveDebugView` | `LiveDebugWidget` | `DebugSnapshots`, `DebugText`, `ModuleImage` | Both | |
| Program steps ±5 running / full listing frozen | `LiveDebugView` | `LiveDebugWidget` | `DebugSnapshots` | Both | |
| FREEZE, FREEZE ON START (next PC change), ARMED, RESUME, STEP (hold to repeat) | `LiveDebugView` | `LiveDebugWidget` | `FreezeController` | Both | |
| CPU tab: history, registers, control registers, display state | `CPUInspectorView` | `CpuInspectorWidget` | `DebugSnapshots`, `DebugText` | Both | |
| CPU FREEZE ON START (scan-loop exit), STEP | `CPUInspectorView` | `CpuInspectorWidget` | `FreezeController` | Both | |
| ROM heatmap with hover address, CLR | `CPUInspectorView` | `RomHeatmapWidget` | `RomHeatmap` | Both | |
| ASM overlay: select, run, clear | `DebugView` | `AsmOverlayBox` | `AsmOverlay` | Both | |
| LOG tab: dumps, clear, log level | `DebugView` | `LogWidget` | `DebugLog` | Both | |
| Binary trace (TRACE toggle), size limit | `DebugView`, `TraceWriter` | `LogWidget` | `TraceWriter` | Both | |
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
