# TO DO
Unsorted collection of ideas, bugs, observations etc.

## Core emulation
- **Keep memory on model switch** - This requires separate memory per model (currently shared)
- **Emulation speed control** — a multiplier to run the emulator faster or slower than real time.
- **Rework display scanning** - Simple scanning on DIGIT 0 vs. scan per digit; Still open issues with the latter
    - **Split TMC 0501 and SCOM** - Take this to the extreme, and support out of phase DIGIT / KEY shenanigans

## Settings
- **Enable/disable persistency** - For TI-58/59 (TI-58C always is persistent by design)

## UI
- **Keyboard support** for debugging panels — the calculator itself is done (macOS app and `docs/#play`, see `reference/AppArchitecture.md` § "Physical Keyboard Mapping"); the debug panels and the printer were deliberately left out. On macOS all three panels are visible at once, so Space (R/S vs. STEP) and ⌘C/⌘X (printer tape vs. selected debugger text) have no unambiguous owner. Needs a panel-ownership decision first, not just bindings.
- **Keyboard support on iPadOS** — an iPad with a hardware keyboard is a plausible case the current macOS-only gating excludes. The map and the view-model machinery are already platform-neutral; only `KeyboardView`'s `#if os(macOS)` and a focus story for the portrait page navigation would need work.

## Debugger
### CPU Debugger
- **Break points** PC-based breakpoints are fully implemented end to end (`TI59Machine`/`EmulatorViewModel`/`reference/DebugAPI.md` § "Breakpoints") with a working UI already written in `CPUDebugView.swift` — it just isn't wired into the app's navigation (see `Redesign.md` item 9). Remaining work here is narrower than it sounds: wire up (or rebuild) that UI, then extend to conditional triggers (register content, IDLE-RUN change, and more) which genuinely don't exist yet.
- **Latch keyboard entries** Support catching a keypress in single step mode — see `KeypressLatch.md` for the existing design proposal.

### Calculator Debugger
- **Break points** Support break points (e.g. STO content, t content, PGM step) — unlike the CPU Debugger, nothing exists here yet, not even PC-level.
- **Latch keyboard entries** Support catching a keypress in single step mode — see `KeypressLatch.md`.

## Various
- **Event callbacks** — push notifications for display updates and register changes, replacing the current polling model.
- **Card stacking** — a queue of cards fed automatically on successive read/write requests, for programs that use multiple cards.
- **CMake build** — standalone build targeting the C++ core, enabling headless use and non-macOS platforms. See `memory/headless.md` for a Python/CMake-based plan, and `reference/NewGUIGuide.md` for the WASM build's already-working precedent of building `Core/` standalone without CMake.
- **Headless / REST API** — full GUI decoupling to enable scripted research workflows and alternative frontends. See `memory/headless.md` and `reference/NewGUIGuide.md`.
- **Frozen** - Visually indicate when the calculator is frozen in one of the debuggers (mostly useful on iPhone, where only one panel is visible at a time)

## Far out (if ever)
- **Additional calculator models** Such as TI-57
