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
- **Unified Mac input surface** — the target design: on macOS the whole window is one keyboard surface, every key has exactly one meaning, and focus stops being a concept. The three panels only remain separate because iPhone portrait swipes between them, which is a layout concern, not an input one. Today's `KeyboardView` focus scoping (`PhysicalKeyboardModifier`) is a stepping stone toward this, and it has a live rough edge in the meantime: clicking the debug panel silently stops keys reaching the calculator, with no indicator — the focus ring was removed rather than made visible, because indicating focus is not where this is heading.
- **Keyboard support** for debugging panels — the calculator itself is done (macOS app, Qt6 app and the website's `/59/play/`, see `reference/SharedArchitecture.md` § "Physical Keyboard Mapping"); the debug panels and the printer were deliberately left out. On macOS all three panels are visible at once, so Space (R/S vs. STEP) and ⌘C/⌘X (printer tape vs. selected debugger text) have no unambiguous owner. Resolved by the unified surface above: one meaning per key settles the ownership question instead of arbitrating it per panel.
- **Keyboard support on iPadOS** — an iPad with a hardware keyboard is a plausible case the current macOS-only gating excludes. The map and the view-model machinery are already platform-neutral; only `KeyboardView`'s `#if os(macOS)` and a focus story for the portrait page navigation would need work.

## Debugger
### CPU Debugger
- **Break points** The core has PC breakpoints (`TI59Machine::addBreakpoint`, `reference/DebugAPI.md` § "Breakpoints"), used only by the headless tools; the unwired Swift UI and the view model's breakpoint API were removed in 2.0.0. Remaining: a UI in both apps (through `Shared/`), then conditional triggers (register content, IDLE-RUN change, and more).
- **Latch keyboard entries** Support catching a keypress in single step mode — see `ideas/KeypressLatch.md` for the existing design proposal.

### Calculator Debugger
- **Break points** Support break points (e.g. STO content, t content, PGM step) — unlike the CPU Debugger, nothing exists here yet, not even PC-level.
- **Latch keyboard entries** Support catching a keypress in single step mode — see `ideas/KeypressLatch.md`.

## Various
- **Event callbacks** — push notifications for display updates and register changes, replacing the current polling model.
- **Card stacking** — a queue of cards fed automatically on successive read/write requests, for programs that use multiple cards.
- **REST API** — scripted control of a running app. Headless runs (`tools/headless/`, `tools/agentic/`) and GUI decoupling (`Shared/`, `reference/NewGUIGuide.md`) are done.
- **Frozen** - Visually indicate when the calculator is frozen in one of the debuggers (mostly useful on iPhone, where only one panel is visible at a time)

## Far out (if ever)
- **Additional calculator models** Such as TI-57
