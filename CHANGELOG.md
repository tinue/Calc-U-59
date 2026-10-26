# Changelog

## [2.2.0] - work in progress
- **iPhone Duo** Opened flat, the calculator, the printer and the debugger sit side by side, as on the iPad, whatever "Debug Page in Portrait" is set to. Half open like a laptop, closed, or held tall, it shows the pages as on the iPhone.

## [2.1.0] - 2026-10-25
- **Web calculator** Rebuilt with the apps' features: the real calculator artwork, TI-59, TI-58 and TI-58C, the PC-100C printer, magnetic cards, presets (bundled or your own file), Settings, and, in the wide layout, the full debugger with trace downloads. A wide layout follows the Mac and Windows windows; a portrait layout, also used by the installable app, follows the iPhone, with the printer on its own page. The installable app runs all three calculators offline. Cards last for the browser session; download one to keep it. <!-- appstore: skip -->

- **State Files** `WaitFullSpeed:` is gone: it took effect only after the program had stopped. Put `FullSpeed:` before the key that starts the program instead; the bundled presets now do, and the long ones finish at full speed. An unknown KEYSTROKES directive or a `Wait:` without a unit is now reported as an error instead of being read as keys.
- **TI-58C** Runs at a real TI-58C's speed, measured on a unit: about 2.6% faster than before. Its error blink takes 0.91 s stand-alone and 0.71 s on the PC-100C, as on the real calculator.
- **Printer** Prints at the real PC-100's speed, measured on a TI-59 and a TI-58C: a printed line takes about 0.29 s on the TI-59 (a List line 0.31 s, was 0.21 s), a blank line from Adv about 0.19 s (was 0.40 s). The printer runs on the calculator's clock, so on the slower TI-58C everything prints 15% slower, as on the real one.
- **Printer** The printer interrupt now cuts a line the way the real printer does: the row it interrupts keeps the dot columns already fired (right to left), and a dot cut early in its heating comes out faint. Measured on a TI-58C and a TI-59 with a PC-100A.
- **Examples** `calendar-09-dispatch.ti59` prints a year 1.8 s faster: 75 s for 2026, 7% faster than Acosta's 1981 program.

### Fixes
- **State Files** A `PARTITION:` too large for the calculator now aborts a `SKIP-RESET` load too, as it already did a normal load.
- **State Files** A file with `SKIP-RESET` and a `PROGRAM:` no longer clears the data registers: `fast-grafik-3d-plot-part2.ti59` plots again with the values entered in part 1, instead of stopping at once with "1.".
- **Debugger** The CPU tab no longer stands still during the TI-58's error blink, when the calculator runs the same short loop over and over.

## [2.0.0] - 2026-10-21
- **Windows and Linux** New desktop app for Windows (x64, ARM64) and Linux (x86_64, aarch64), with the Mac app's features: both LED styles, cue cards, the physical keyboard, magnetic cards, presets, the PC-100C printer and the full debugger. Cards and TI-58C memory are kept in `~/Calc-U-59`; Settings picks the folders. <!-- appstore: skip -->
- **Web calculator** The calculator on the website now runs the same emulator as the apps and behaves exactly like them. The installable web app loads faster and updates itself when a new version is out. <!-- appstore: skip -->
- **Accuracy** The emulator now runs at the real calculator's speed; it ran about 17% slow on the Mac. The error blink now matches a real TI-59 to within a few milliseconds: 0.9 s on the PC-100C, where the printer line slows the calculator's idle loop, and 0.45 s stand-alone, as before. The TI-58's error blink is twice as fast as before and matches a real TI-58's 0.68 s just as closely.
- **Display** The LED display now looks the way the eye sees the real one: short computations no longer flash it dark, long ones such as sin visibly dim it, and the error blink no longer flickers. As on the real calculator, the right-hand digits of the error blink look a little dimmer.
- **Full speed** Holding the display now also speeds up printing, e.g. a 2nd List or a calendar printout.
- **Debugger** The CALCULATOR tab shows X, the working value, and the whole status register. STEP now advances exactly as SST does, the program cursor marks the next step as LRN does, values no longer flicker while a program runs, and fast mode shows for every mode.
- **Examples** New `fastmode-sst.ti59`, `printer-interrupt.ti59` and `calendar-09-dispatch.ti59`, a fast-mode calendar printer faster than Acosta's 1981 program. Annotated ROM listings in `rom/` explain fast mode and the printer interrupt.
- **License** Calc-U-59 is now free software under the GPLv3.
- **User guide** The user guide moved to https://calc-u.org/59/, and the web calculator to https://calc-u.org/59/play/.

### Fixes
- **TI-58C** `REGISTERS:` in a state file now fills the right registers (they were four off), and a preset's cue card comes back after a restart.
- **Calculator switch** Switching between TI-59, TI-58 and TI-58C keeps the printer setting and the LOG, and no longer carries a debugger freeze over.
- **State Files** The first key of a KEYSTROKES script is no longer lost while the calculator is busy. A module that can't be loaded now shows an error and keeps the current one.
- **Debugger** A trace file that can't be written or gets full now shows an alert.
- **Printer** Copy as image keeps the full 600 dpi for printer-interrupt tapes.

## [1.7.0] - 2026-09-15
- **Error messages** File-load error alerts now show a title that matches what actually failed (state file, card, or ASM load/save) instead of always saying "ROM load error". A state file that isn't valid UTF-8 (e.g. saved with a curly quote or em dash in a non-UTF-8 encoding) now gets a specific explanation instead of a generic "Cannot read file."
- **State Files** New `PencilColor:` CUECARD keyword (`black` default, or `pencil`/`sharpie`) lets a CueCard or MagnetCard's title/row/label text use an ink color that contrasts against the template's printed divider lines instead of blending into them. SolidStateCard is unaffected — it always renders in its fixed printed gold.

### Fixes
- **Keyboard** Fixed key presses on iOS/iPadOS being dropped intermittently (most presses not registering) under iOS 27's revised touch-gesture timing. Key tracking now reads touches directly instead of through the higher-level gesture API, restoring the same reliable, immediate response as before. macOS input is unaffected.
- **State Files** Fixed `\blank` CUECARD labels (used to merge grid cells into a spanning label) silently turning into empty labels after a save/reload round trip through `ti58c.mem` — the invisible marker is now written back out as literal `\blank` text instead of a raw zero-width space, which whitespace-trimming was stripping on reload.

## [1.6.0] - 2026-08-13

- **Keyboard** The Mac app now takes input from a physical keyboard: the number keys, the yellow operation keys (`Esc` for CLR, `Enter` for `=`, `<` for +/−), the A–E function keys via `a`–`e`, and EE `(` `)` on `>` `(` `)`. `Shift`+`A`…`E` gives A′–E′. Everything else — 2nd, STO, RCL, LRN, R/S and the rest — stays mouse-only by design. The full map is in `reference/AppArchitecture.md` § "Physical Keyboard Mapping". Typing works as soon as the app opens — the calculator does not have to be selected first. Clicking into the debug panel hands the keyboard over to it until you click back on the calculator. The printer and debug panels have no keyboard bindings of their own. iOS and iPadOS are unaffected.
- **App Icon** Rebuilt as a layered Icon Composer `.icon` document, adding Liquid Glass depth and Light/Dark/Tinted/Clear appearance variants on iOS/macOS 26.
- **State Files** New `Trace: name.bin` / `Trace: Off` keywords turn CPU instruction tracing on or off while a state file's KEYSTROKES are executing.
- **State Files** New `FullSpeed:` / `RegularSpeed:` keywords toggle full speed persistently (no auto-revert, unlike `WaitFullSpeed:`) while a state file's KEYSTROKES are executing.
- **State Files** New `ZeroElapseTime:` / `ReportElapseTime:` keywords snapshot and report elapsed emulated time during KEYSTROKES playback, for measuring program run time.
- **Documentation** Reworked the repository's documentation around a strict split: `reference/` and skill files are developer-only, the `www.calcu59.ch` website is the sole home for end-user content, and README now links to it once instead of duplicating it. Consolidated the `.ti59`/`.ti58`/`.ti58c` state-file and CUECARD format into a new `reference/StateFileFormat.md` (previously scattered across a skill file and a section of `DebugAPI.md`), folded `reference/USERGUIDE.md`'s still-relevant ASM Overlay content into `DebugAPI.md` and retired the rest as redundant with the website, and trimmed several skill files that were restating facts already in `reference/`.

### Fixes
- **State Files** Fixed `REGISTERS:` lines for register numbers 60–99 being loaded into the wrong RAM cell on the TI-59 (they were mistaken for the TI-58C's unrelated extra `H00`–`H03` registers, which happen to live at raw RAM indices 60–63). Ordinary TI-59 registers now always use the correct top-down `STO`/`RCL` mapping regardless of number; only true TI-58C extra registers use the raw mapping, now selected by an explicit flag instead of a numeric-range guess.
- **Keyboard** Fixed a held key's matrix bit staying stuck set in the emulator core if the keyboard/R\/S automation button view was torn down (e.g. rapid panel switching) mid-press, instead of releasing normally.
- **UI** Fixed toolbar, printer, and debug panel buttons shifting position on iOS when the Button Shapes accessibility setting is enabled.

## [1.5.0] - 2026-07-02

- **Printer** Dot-matrix output now correctly supports printer-interrupt, also known as "High Rez Graphics". This is a hack documented in the 1982 magazine "PPX Exchange". Check the GitHub repository for the example state file `texas-print.ti59`.

### Fixes
- **Printer** Multiple blank-line errors fixed (ADV button). Blank lines now match the real PC-100A/B/C exactly.
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
