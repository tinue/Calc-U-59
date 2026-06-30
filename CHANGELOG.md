# Changelog

## [1.5.0] - Work in progress

- **Printer** Dot-matrix output is now rendered row by row. Lines interrupted mid-print (via the hacked `1F` printer-interrupt keycode) show only the dot-rows that were physically laid down, with no padding below — matching the hard stop of the real printer's stepper motor.

### Fixes
- **Debug Log** Fixed out-of-memory crash and GUI slowdown when the LOG panel is active at DEBUG level.

## [1.4.0] - 2026-06-29

- **State Files** New `MODEL:` keyword switches the machine variant (TI-59/58/58C) when a state file is loaded.
- **State Files** New `WaitFullSpeed: Xs` keyword runs the calculator at full speed for the given duration before continuing.
- **State Files** New `SKIP-RESET:` directive applies only PROGRAM, REGISTERS, and KEYSTROKES to the running machine, skipping the reset.
- **State Files** Printer tape is cleared whenever a state file is loaded.

### Fixes
- **ASM Overlay** Running an overlay no longer spuriously times out.
- **ASM Overlay** FREEZE ON START in the CPU tab now also triggers when Run is pressed in the ASM Overlay.
- **CPU Debugger** KEY instruction disassembly no longer shows a spurious digit suffix.

## [1.3.0] - 2026-06-19
- **Calculator Debugger** Enables tracing and single-stepping of solid-state module keycode programs.
- **Portrait View** Enables the debugger in portrait view as well (disabled by default, enable in Settings). Particularly useful for iPhone users who previously had no debugger access.
- **ROM Heatmap** Hover over (or touch and hold) a block to see its hex address in the header.
- **CPU Debugger** Binary flag registers are now grouped into nibbles for readability.
- **Debugger** Hold the STEP button to step continuously at 4 steps per second.

### Fixes
- **Debugger** Moved the RESUME button to the left of FREEZE to avoid accidental presses while stepping.
- **CPU Debugger** Registers A–E and Sout are displayed MSN-first.
- **CPU Debugger** FREEZE ON START now triggers on a keypress or on reset of the calculator. This allows single-stepping the reset routine.
- **Trace** File size limit is now enforced by disabling TRACE when the limit is reached.

## [1.2.0] - 2026-06-10
- **CPU Debugger** Live view shows the same information as "frozen"; New "ROM heatmap" is a visual indicator which parts of the ROM got executed so far.
- **Debuggers** Debuggers are always active (on/off sliders removed).
- **Samples** Additional samples.

### Fixes
- **Debugger** Clearer labels "Calculator", "CPU" and "Log" to indicate what the panels actually do.
- **Canvas** Cosmetic improvements on canvas, e.g. on key "9".
- **Core** Fix error in original ROM code obtained from Datamath
- **Cue Cards** Fix rendering of empty cue card labels
- **Debuggers** Fix buttons jumping around, fix state machine for the buttons.
- **Calculator Debugger** Fix Arrow location in PROGRAM STEPS view

## [1.1.1] - 2026-05-15

### Fixes

- **File Picker Stability:** Fixed "Select File" (ASM overlay) and "Preset" file pickers becoming unresponsive after multiple uses, requiring app restart. Consolidated separate file picker modifiers into a single unified fileImporter to work around iOS/iPadOS modal stacking limitations, and improved state reset timing to prevent corruption.

- **State Management:** Improved fileImporter binding stability by using a computed property instead of recreating the binding on every view render. Explicit state resets in all result handler code paths ensure the modal state machine never gets stuck in an inconsistent state.

## [1.1.0] - 2026-05-15

**Solid-State Modules:** 14 library modules are now supported and can be selected in Settings. Previously only the ML-01 Master Library was available (hardcoded); 13 additional modules are now included, among them the LE07 Leisure Library.

**Cue Cards:** New cue card panel renders dynamically from a template system. All 25 ML-01 Master Library program cards are included with accurate titles, key labels, and descriptions, and each solid-state module has its own set of cards. Cards switch automatically when the calculator detects a new program number.

**Card File Format:** A new human-readable `.U59` text format for card files, that includes the cue card for the card file.

**State File Improvements:** Allow to specify the SolidState module to load. Allow to explicitly set the printer on or off.

 **TI-58C Persistency Fixes:** Fix the file format. The cue card is persisted inside the TI-58C `.mem` file and survives app restarts.

**High-Speed Mode:** Touch and hold the display to run the calculator at full speed — useful for long computations or to LIST a program on the printer.

**Haptic & Audio:** The reset button now produces haptic and audio feedback.

**Help Site:** New help site at https://www.calcu59.ch provides documentation and user guides.

### Fixes

- Loading a preset could silently delete the tail of the stored program.
- Printer scroll could hang the emulator on macOS.
- Copying printer output on macOS now produces an image that can be pasted directly into Pixelmator and similar apps.

## [1.0.0] - 2026-05-04
First iOS / iPadOS release in the App Store.

**UI:** Improved key detection and feedback with refined key rectangles for better visual press simulation and more accurate hit-testing. New classic display font with dot-matrix LED segments, offering an authentic retro aesthetic alongside the existing modernized font style.

**Display:** Fixed display content artefacts during afterglow phase. When exiting IDLE mode, the display now correctly freezes its content (digits, decimal point) until returning to IDLE, preventing stale register values (e.g., R5) from appearing visually during computation. Added per-position decimal-point afterglow (phosphor persistence): each decimal-point position now independently decays over a short window (tuned to 2 display cycles), accurately reproducing the phosphor persistence of the original LED hardware.

**Emulation:** Implemented accurate TI-58/58C clock speed. Implement constant-speed IDLE behavior for the TI-58C. The emulator now runs at the correct machine frequency and maintains a stable cadence in the IDLE state for the TI-58C.

**Battery/Performance:** Fixed background behavior to freeze CPU emulation loop and display timer when the app is backgrounded, eliminating battery drain while the app is suspended. On return to foreground, emulation automatically resumes (preserving any debug-mode freeze). App eviction is handled gracefully with state persisted on background transition; fresh launch after eviction reads startup settings and restores TI-58C CMOS RAM, matching iPhone reboot behavior. Afterglow lock contention reduced: mutex scope narrowed to protect only display register writes; decimal-point mask computation skipped when display is blanked.

**Documentation:** Added example programs documenting fast-mode quirks and explaining why certain programs behave differently in the emulator.

## [0.4.0] - 2026-04-24

**UI:** Full GUI rework of the main calculator panel. The layout now uses an edge-to-edge canvas with a runtime card overlay, replacing the previous button-based layout. The ML-01 reference card was regenerated at full canvas width. The LED display was repositioned to avoid overlap with the card slot. Key rectangles were recalculated from accurate image extraction. Fixed wide borders on iPad Mini in landscape mode. Dark mode is now enforced app-wide.

**Printer:** Printer toggle button added in landscape mode. Printer can now be disabled.

**Debugger:** CPU Inspector frozen view reliability significantly improved. Trace snapshot capture unified to pre-execution semantics; COND field is now correctly patched at freeze time. The frozen view shows the correct next instruction and register state. Fixed SwiftUI ForEach ID collisions in debug views. Refined coloring for return address, HIR, and conditional result fields. ASM overlay tab merged into the CPU tab (unified three-tab layout: LIVE, CPU, LOG). Fixed freeze semantics so that freeze and step-out of IDLE behave correctly.

**Assembly overlay:** `.asm` file format unified. Fixed `ObjCBool` type mismatch in `runASMOverlay`.

**Display:** The calculator display now live-updates while the machine is in IDLE mode (previously stale between keystrokes). Decimal-point position is now read live from R5 rather than cached.

**Disassembler:** Fixed KEY instruction disassembly mask decoding. Dropped redundant `+0`/`-0` suffix for `ADD #0` / `SUB #0` opcodes.

**Trace:** Binary trace format reset to v1 baseline with unified post-execution frame semantics. Fixed Sout offset bug in trace output. `read_trace.py` enhanced with trace numbering, colorization, proper idle-loop detection, and display-phase analysis.

**Emulation:** Removed experimental `WAIT Dn` timing patch (was causing inaccurate idle timing). TI-58C blink timing analyzed, but still no solution found as to the wrong error blink pattern.

**Documentation:** Added `docs/USERGUIDE.md` covering the debug GUI (three-tab panel: LIVE, CPU, LOG). Debug GUI documentation split out of `DebugAPI.md`. Assembly examples from Sladský's hardware programming guide added under `examples/assembly/`.

## [0.3.0] - 2026-04-18

**Core emulation:** Fixed critical R5 register bug where ALU results were captured at the wrong digit position. The R5 register must capture results at the mask's constant position (cpos), not the start position. This bug caused subroutine returns (P/R, transcendental functions, etc.) to jump to incorrect addresses. Bug was present since initial implementation and affected all machine variants.

**Library module:** Fixed IN LIB_PC to be a pure read-only operation (no longer destructively modifies m_libAddr). Implemented direction tracking for address operations: position counter now resets to 0 when switching between reading (IN LIB_PC) and writing (OUT LIB_PC) operations, preventing incomplete address loads when ROM switches modes mid-sequence. Added m_libAddrReadPos to trace output as ROM=xxxx.y (digit position counter). Fixed EXT register logging to display actual byte values by shifting right 4 bits before masking.

**TI-58C emulation:** Add MEMWR/MEMRD support. Fixed address decoding (Sout[1:0] are hex nibbles, not BCD, not decimal). Implemented full field-mask support for partial RAM writes. Fixed deferred-write behavior and printer-detection digit selection. Expanded RAM from 60 to 64 registers. TI-58C now uses proper CD2400/CD2401 constants instead of TI-59 constants, fixing mathematical function accuracy. TI-58C now fully functional: programs can store and retrieve variables.

**Preset files:** TI-58C files now support hidden register loading via H00–H03 syntax (e.g., `H01 = 7.77E22`), allowing direct access to the four special constant-memory registers (060–063) used for partition settings and validation. Quirky partition support (steps 480–511) removed; TI-58C now treats partition limits identically to TI-58 (max 479 steps, default 239).

**Constant memory:** TI-58C RAM persistence (`ti58c.mem`) switched from binary to human-readable text format. File now shows individual registers as hex bytes (e.g., `R000: 67 11 96 00 10 00 00 96`), making saved state transparent and editable. Only non-zero registers are written to keep files compact. Old binary `.mem` files are automatically detected and loaded on startup; load errors silently initialize RAM to zeros. TI-58C state now persists continuously on every 20 ms emulation batch, ensuring register changes during program execution are saved within milliseconds. State is also written immediately after loading preset files or performing a clean reset.

**Debugger:** Fixed live snapshot and register display to correctly show TI-58C's 64 displayable registers beyond the partition limit. Fixed debugger crashes on quirky partitions.

**UI:** Clean Reset feature (Cmd+Reset on macOS, long-press on iOS) zeros all registers and resets the calculator. Label and icon change to "Clean" with orange highlight when Command is held (macOS only), providing clear visual feedback. Works across all models; for TI-58C, the empty state is immediately persisted to the save file. Improved accessibility: Reset button now includes text label for screen readers.

**Configuration** Start with a rudimentary "settings" panel. So far allows to choose the model at startup, and the location of the trace log file.

**Documentation:** Added `.ti58c` preset file example showing TI-58C repartitioning workflow. Updated `.ti59` state file format documentation to include hidden register syntax.

## [0.2.0] - 2026-04-06

**Emulation:** Replaced TI-58C "cheat" with real TI-58C ROM and constant-memory support. Missing MEMWR/MEMRD instructions for RAM read/write lead the the calculator being able to "calculate", but not store variables or program steps. Fixed 2nd Op 40 instruction. 'C' indicator now uses hardware-accurate SH-pin duty-cycle emulation with proper latch behavior and realistic afterglow. Printer mechanical busy timing matches real PC-100C hardware behavior.

**Debugging:** Binary execution trace facility (`TI59_TRACE.bin`) for advanced program analysis and verification against reference traces.

**Files:** iOS users can now access calculator state files via the public iCloud Drive folder; easier file management on iPad and iPhone.

**UI:** Card reader bar buttons show icon-only on narrow portrait screens (all iPhones; wide iPads are unaffected).

**Samples:** Added more samples, for example memory test preset files `ram_test.ti59` and `ram_test_full_fast.ti59` for hardware validation.

## [0.1.2] - 2026-03-30

Lowered deployment targets to macOS 15 (Sequoia) and iOS/iPadOS 18.

## [0.1.1] - 2026-03-29

Broken, do not use

## [0.1.0] - 2026-03-28

Initial release.

**Emulation:** Cycle-accurate TI-59 and TI-58 emulation. TI-58C emulation provided as a variant of TI-58 with persistent RAM (a functional workaround, not proper TI-58C hardware emulation). Master Library ROM included.

**Preset files:** Load `.ti59` / `.ti58` state files to preset the calculator with a program and data registers.

**Card reader:** Magnetic card read/write simulation with file-based card storage.

**Printer:** Paper tape view with PC-100C dot-matrix font rendering. Copy output as text or high-resolution bitmap.

**Debugger:** Register inspection and keystroke injection (macOS and iPad landscape).

**Known limitations:** TI-58C is not truly emulated — it runs TI-58 code with persistent RAM instead of proper TI-58C ROM and constant-memory support. Printer output is functionally simulated — timing-sensitive printer interactions are not reproduced. The debug API is functional but early: expect the interface to evolve.
