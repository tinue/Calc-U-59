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
EmulatorViewModel          (App/EmulatorViewModel.swift, 103 KB)
  │  @Observable, runs the 60 Hz step loop, owns all UI state
  │
  ├─ TI59MachineWrapper    (Bridge/TI59MachineWrapper.h + .mm)
  │    ObjC++ shim — the only place Swift touches C++
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

> **Note:** `CPUDebugView.swift` exists in the repository but is not embedded in the app (only referenced in its own SwiftUI preview). Do not wire it up or confuse it with `CPUInspectorView`.

All UI state flows through `EmulatorViewModel`. Views are thin bindings — no business logic in views.

---

## Key Files

Full file-by-file responsibility table: `reference/AppArchitecture.md` §
"File Responsibilities". Not reproduced here — read it there.

---

## 60 Hz Loop and Value Timing

- `EmulatorViewModel` runs a 60 Hz display-link loop.
- **All register values shown in the debug panel are pre-execution** — what exists before the current instruction runs.
- **Frozen display**: when frozen, `current step = decodedPC − 1` (last executed instruction); registers show post-execution state of that instruction.
- **Next statement**: shows the ROM address and mnemonic of the not-yet-executed instruction; register fields are empty/blank.

---

## Program Sources and the Solid-State Display Path

How the PROGRAM STEPS view resolves and highlights solid-state (library
module) addresses — `ProgramSource`, `cacheModuleImage()`,
`libraryProgramStep()`, the PRG SOURCE=2 transitional-return case — is
documented in `reference/AppArchitecture.md` § "Solid-State Program Display".

---

## Bridge Optimization

- Fetching all 100 data registers individually per frame is too slow. Use `nonZeroDataRegisterIndices()` to get the set of non-zero registers in a single bridge call, then fetch only those.
- Never make 100 individual bridge calls per 60 Hz frame.

---

## Dynamic Type Cap

`CalculatorView.body` intentionally limits Dynamic Type to `.small … .large`. Do not remove or widen this cap — at accessibility sizes XL and above, buttons become oversized and break the layout (especially the TI-59 card reader bar).

---

## iOS and macOS: Both Platforms Must Work

Every change must leave **both** the iOS and macOS targets building and running correctly. When there is any doubt:

1. Build for iOS Simulator:
   ```bash
   xcodebuild -project Calc-U-59.xcodeproj -scheme "Calc-U-59" \
     -destination "platform=iOS Simulator,name=iPhone 17e" build
   ```
2. Build for macOS:
   ```bash
   xcodebuild -project Calc-U-59.xcodeproj -scheme "Calc-U-59" \
     -destination "platform=macOS" build
   ```

Both must succeed before the task is done.

---

## Reference

- `reference/AppArchitecture.md` — full app architecture documentation
- `reference/DebugAPI.md` — debug panel and bridge API reference

---

## Global Rules

1. **Compile, don't run.** Do not launch the Xcode iOS Simulator or run the built Mac app — that is the user's job. When runtime verification is needed, ask the user to launch the app and explain precisely what behaviour or output to look for.

2. **Commit often, never push.** Commit after each logical unit of work. Never run `git push`.

3. **iOS and macOS both must work.** See the build commands above. Both targets must succeed before declaring the task done.

4. **Cite your sources.** When referencing a hardware spec, standard, or external document, include the https URL (or a pointer to the local reference file) in the relevant code comment or documentation.
