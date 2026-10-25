---
name: calc-u-59-swift
description: Use this skill when working on the Swift/SwiftUI code of Calc-U-59 (App/, App/Views/, Bridge/). Covers EmulatorViewModel, the ObjC++ bridge, display, keyboard, debug panels, printer, card reader, settings, and state file I/O. Trigger on any task that touches App/*.swift, App/Views/*.swift, Bridge/, or the Xcode project.
user-invocable: true
---

# Calc-U-59 Swift GUI

This skill covers all work inside `App/`, `App/Views/`, and `Bridge/`.

- App structure, files, threading, bridge: `reference/AppArchitecture.md`.
- Everything that isn't drawing (run loop, keys, files, debugger, drawing
  rules): `reference/SharedArchitecture.md` and the calc-u-59-shared skill.
- Freeze / step and the debug snapshots: `reference/DebugAPI.md`.
- TI-59 background: the calc-u-59-core skill's Domain Primer. SwiftUI
  practice: the swiftui-pro skill.

## Rules

1. **No non-GUI logic in Swift.** Parsing, file formats, timing, key
   sequencing, snapshot building and the numbers the views draw with belong
   in `Shared/`, reached through `EmulatorViewModel` → `TISessionController`
   or a `Bridge/` wrapper. Views are thin bindings over `EmulatorViewModel`.
2. **Parity.** A user-visible change here needs the matching Qt change, and
   the web change if the feature is in the web's scope, on the same branch —
   or a `Pending (Qt)` / `Pending (Web)` row in `reference/FrontendParity.md`.
   Update the table either way (CLAUDE.md § "Frontend Parity").
3. **Bridge wrappers translate types only.** Per-frame work that walks
   registers or program memory runs in C++ and crosses the bridge once as a
   finished result — never 100 bridge calls per 60 Hz frame.
4. **Guard `@Observable` writes.** `apply(_:)` assigns a property only when
   the value differs; `@Observable` notifies on equal writes too.
5. **Keep the Dynamic Type cap.** `CalculatorView.body` limits Dynamic Type
   to `.small ... .large`. Wider sizes break the layout (the TI-59 card bar
   first).
6. **Compile, don't run.** Never launch the simulator or the built Mac app;
   ask the user to, saying exactly what to look for.
7. **Commit often, never push.**
8. **Cite sources.** A hardware spec or external document gets its https URL
   (or local reference file) in the comment or doc.

## Build Verification

Every change needs a macOS build:

```bash
xcodebuild -project Calc-U-59.xcodeproj -scheme "Calc-U-59" \
  -destination "platform=macOS" build
```

Build for iOS only when a task or test explicitly needs it, and only on a
simulator from `bin/simulators.yaml`. `bin/simulators status` lists them with
their UDIDs; never hard-code a model name from memory.

```bash
bin/simulators status    # pick a device, e.g. the iPhone 18 Pro Max
xcodebuild -project Calc-U-59.xcodeproj -scheme "Calc-U-59" \
  -destination "platform=iOS Simulator,id=<UDID>" build
```

A change to `Core/` or `Shared/` also needs the CMake build and tests
(calc-u-59-shared skill).
