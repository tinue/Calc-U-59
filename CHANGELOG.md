# Changelog

## [0.2.0] - Unreleased

<!-- Add 0.2.0 changes here -->

## [0.1.1] - 2026-03-29

Lowered deployment targets to macOS 15 (Sequoia) and iOS/iPadOS 18.

## [0.1.0] - 2026-03-28

Initial release.

**Emulation:** Cycle-accurate TI-59, TI-58, and TI-58C emulation. TI-58C constant memory survives restarts. Master Library ROM included.

**Preset files:** Load `.ti59` / `.ti58` state files to preset the calculator with a program and data registers.

**Card reader:** Magnetic card read/write simulation with file-based card storage.

**Printer:** Paper tape view with PC-100C dot-matrix font rendering. Copy output as text or high-resolution bitmap.

**Debugger:** Register inspection and keystroke injection (macOS and iPad landscape).

**Limitation:** Printer output is functionally simulated — timing-sensitive printer interactions are not reproduced. The debug API is functional but early: expect the interface to evolve.
