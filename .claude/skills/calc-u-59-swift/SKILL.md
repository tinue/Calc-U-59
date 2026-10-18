---
name: calc-u-59-swift
description: Use this skill when working on the Swift/SwiftUI code of Calc-U-59 (App/, App/Views/, Bridge/). Covers EmulatorViewModel, the ObjC++ bridge, display, keyboard, debug panels, printer, card reader, settings, and state file I/O. Trigger on any task that touches App/*.swift, App/Views/*.swift, Bridge/, or the Xcode project.
user-invocable: true
---

# Calc-U-59 Swift GUI

This skill covers all work inside `App/`, `App/Views/`, and `Bridge/`.

For TI-59 domain background (keycodes, SCOM layout, solid-state modules, program source flag) see the **calc-u-59-core** skill's Domain Primer. For general SwiftUI best practices, the **swiftui-pro** skill applies.

---

## Architecture Overview

```
EmulatorViewModel          (App/EmulatorViewModel.swift)
  │  @Observable adapter: forwards actions, ticks the controller at 60 Hz,
  │  copies state in apply(_ changes:) when the controller reports TIChange
  │
  ├─ TISessionController   (Bridge/ → Shared/SessionController: machine, presets,
  │                         card reader, printer, freeze/step, traces, ASM, LOG;
  │                         PlatformForwarder implements its TIPlatform protocol)
  ├─ TITypes, TIFileFormats, TISharedTables, TIViewRules, TISettings
  │    ObjC++ type translation over Shared/ — the only places Swift touches C++
  │
  └─ App/Views/            (SwiftUI, thin bindings only)
       CalculatorView      main container
       KeyboardView        calculator image + gesture hit-test + LED overlay
       LEDDisplayView      12-digit BCD LED with afterglow animation
       PrinterView         PC-100C tape simulation
       CueCardView         reference card overlay
       DebugView           3-tab container: CALCULATOR / CPU / LOG
         LiveDebugView     CALCULATOR tab — real-time program-step scroller
         CPUInspectorView  CPU tab — instruction ring, register/SCOM browser, ROM heatmap
         StaticDebugContent LOG tab — raw SCOM dump, trace capture toggle
       SettingsView        debug level, trace enabled, playback speed, module selection
       CardPickerView      magnetic card library picker
```

All UI state flows through `EmulatorViewModel`. Views are thin bindings — no business logic in views.

**No non-GUI logic in Swift at all.** Parsing, file formats, timing, key
sequencing, snapshot building and the numbers the views draw with live in
`Shared/` (C++), shared with the Qt6 app — see the calc-u-59-shared skill and
`reference/SharedArchitecture.md`. A user-visible change here needs the
matching Qt change on the same branch, or a `Pending (Qt)` row in
`reference/FrontendParity.md` (CLAUDE.md § "Frontend Parity").

---

## Key Files

Full file-by-file responsibility table: `reference/AppArchitecture.md` §
"File Responsibilities". Not reproduced here — read it there.

---

## 60 Hz Loop and Value Timing

- `EmulatorViewModel`'s 60 Hz timer calls `controller.tick()`; what changed
  arrives through `TIPlatform.changed(_:)` and is copied into the observable
  properties (each write guarded — `@Observable` notifies even on equal values).
- Freeze state is the controller's: `isFrozen`, `freezeOwner`,
  `pendingFreezeOnPCChange`, `pendingCPUScanLoopFreeze` are read-only mirrors
  (setting a pending flag to false disarms). The debugger's data is
  `liveDebugSnapshot`, `programListing(+Source, CurrentIndex)`, `cpuHistory`
  (+ `cpuHistoryUpdateID`) and `romHitCount`.
- Freeze/step semantics, threading and the frozen display (current step =
  last executed step): `reference/DebugAPI.md` § "Freeze / Step Controls".

---

## Program Sources and the Solid-State Display Path

How the PROGRAM STEPS view resolves and highlights solid-state (library
module) addresses — `ProgramSource`, `ModuleImage`, the PRG SOURCE=2
transitional-return case — is built in `Shared/` (`DebugSnapshots`,
`DebugModel`) and documented in `reference/AppArchitecture.md` §
"Solid-State Program Display" and `reference/DebugAPI.md`.

---

## Bridge Optimization

- Never make 100 individual bridge calls per 60 Hz frame. Per-frame work that walks registers or program memory (the live debug snapshot, listings, dumps) runs in C++ (`Shared/`) and crosses the bridge once as a finished result.

---

## Dynamic Type Cap

`CalculatorView.body` intentionally limits Dynamic Type to `.small … .large`. Do not remove or widen this cap — at accessibility sizes XL and above, buttons become oversized and break the layout (especially the TI-59 card reader bar).

---

## Build Verification: macOS by Default

Verify every change with a macOS build:

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

---

## Reference

- `reference/AppArchitecture.md` — full app architecture documentation
- `reference/DebugAPI.md` — debug panel and bridge API reference

---

## Global Rules

1. **Compile, don't run.** Do not launch the Xcode iOS Simulator or run the built Mac app — that is the user's job. When runtime verification is needed, ask the user to launch the app and explain precisely what behaviour or output to look for.

2. **Commit often, never push.** Commit after each logical unit of work. Never run `git push`.

3. **Build on macOS.** A macOS build must succeed before declaring the task done; add an iOS build only when explicitly required (see above).

4. **Cite your sources.** When referencing a hardware spec, standard, or external document, include the https URL (or a pointer to the local reference file) in the relevant code comment or documentation.
