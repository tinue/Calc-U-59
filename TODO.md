# TO DO
Unsorted collection of ideas, bugs, observations etc.

## Core emulation
- **Keep memory on model switch** - This requires separate memory per model (currently shared)
- **Emulation speed control** — a multiplier to run the emulator faster or slower than real time.
- **Rework display scanning** - Simple scanning on DIGIT 0 vs. scan per digit; Still open issues with the latter
    - **Split TMC 0501 and SCOM** - Take this to the extreme, and support out of phase DIGIT / KEY shenanigans

## Settings
- **Enable/disable persistency** - For TI-58/59 (TI-58C always is persistent by design)
- **Enable/disable printer** - Allow to set desired printer state at startup (on, off, last selected)

## UI
- **Keyboard support** Number keys, operators, "Enter" to trigger "=" etc.
- **Keyboard support** for debugging panels

## Debugger
### CPU Debugger
- **Break points** Support break points (e.g. register content, IDLE-RUN change, PGM counter, and more)
- **Latch keyboard entries** Support catching a keypress in single step mode
- **Heatmap** Add a heatmap of the entire ROM. Start with green (never touched), and go through yellow to red
- **Live Register** The current live view (not frozen) only shows program steps. Add flags and registers as well

### Calculator Debugger
- **Live mode** Support additional live mode pgm sources (fast mode, solid state ROM)
- **Break points** Support break points (e.g. STO content, t content, PGM step)
- **Latch keyboard entries** Support catching a keypress in single step mode

## Various
- **Event callbacks** — push notifications for display updates and register changes, replacing the current polling model.
- **Card stacking** — a queue of cards fed automatically on successive read/write requests, for programs that use multiple cards.
- **CMake build** — standalone build targeting the C++ core, enabling headless use and non-macOS platforms.
- **Headless / REST API** — full GUI decoupling to enable scripted research workflows and alternative frontends.
- **Printer hardware support** - Enable features like printer interrupt, i.e. pseudo graphics mode

## Far out (if ever)
- **Additional calculator models** Such as TI-57
