# TO DO
Unsorted collection of ideas, bugs, obsdervations etc.

## Settings
- **Enbable/disable persistency** - For TI-58/59 (TI-58C always is persistent by design)
- **Enable/disable printer** - Allow to set desired porinter state at startup (on, off, last selected)

## UI
- **Keyboard support** Number keys, operators, "Enter" to trigger "=" etc.
- **Keyboard support** for debugging panels
- **Optimize screen area** remove black areas left/right

## Various
- **Keep memory on mddel switch** - This requires separate memory per model (currently shared)
- **Emulation speed control** — a multiplier to run the emulator faster or slower than real time.
- **Event callbacks** — push notifications for display updates and register changes, replacing the current polling model.
- **Library module switching** — a UI picker to load different Solid State Library modules, with a machine reset on swap (matching real hardware behaviour).
- **Card stacking** — a queue of cards fed automatically on successive read/write requests, for programs that use multiple cards.
- **CMake build** — standalone build targeting the C++ core, enabling headless use and non-macOS platforms.
- **Headless / REST API** — full GUI decoupling to enable scripted research workflows and alternative frontends.
- **Printer hardware support** - Enable features like printer interrupt, i.e. pseudo graphics mode
