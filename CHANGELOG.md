# Changelog

## [0.3.0] - TBD

**Core emulation:** Fixed critical R5 register bug where ALU results were captured at the wrong digit position. The R5 register must capture results at the mask's constant position (cpos), not the start position. This bug caused subroutine returns (P/R, transcendental functions, etc.) to jump to incorrect addresses. Bug was present since initial implementation and affected all machine variants.

**TI-58C emulation:** Add MEMWR/MEMRD support. Fixed address decoding (Sout[1:0] are hex nibbles, not BCD, not decimal). Implemented full field-mask support for partial RAM writes. Fixed deferred-write behavior and printer-detection digit selection. Expanded RAM from 60 to 64 registers. TI-58C now uses proper CD2400/CD2401 constants instead of TI-59 constants, fixing mathematical function accuracy. TI-58C now fully functional: programs can store and retrieve variables.

**Preset files:** TI-58C files now support hidden register loading via H00–H03 syntax (e.g., `H01 = 7.77E22`), allowing direct access to the four special constant-memory registers (060–063) used for partition settings and validation. Quirky partition support (steps 480–511) removed; TI-58C now treats partition limits identically to TI-58 (max 479 steps, default 239).

**Constant memory:** TI-58C RAM persistence (`ti58c.mem`) switched from binary to human-readable text format. File now shows individual registers as hex bytes (e.g., `R000: 67 11 96 00 10 00 00 96`), making saved state transparent and editable. Only non-zero registers are written to keep files compact. Old binary `.mem` files are automatically detected and loaded on startup; load errors silently initialize RAM to zeros. TI-58C state now persists continuously on every 20 ms emulation batch, ensuring register changes during program execution are saved within milliseconds. State is also written immediately after loading preset files or performing a clean reset.

**Debugger:** Fixed live snapshot and register display to correctly show TI-58C's 64 displayable registers beyond the partition limit. Fixed debugger crashes on quirky partitions.

**UI:** Clean Reset feature (Cmd+Reset on macOS, long-press on iOS) zeros all registers and resets the calculator. Label and icon change to "Clean" with orange highlight when Command is held (macOS only), providing clear visual feedback. Works across all models; for TI-58C, the empty state is immediately persisted to the save file. Improved accessibility: Reset button now includes text label for screen readers.

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
