---
name: calc-u-59-shared
description: Use this skill when working on the shared C++ layer of Calc-U-59 (Shared/, tests/, the root CMakeLists.txt, tools/goldens/) — the non-GUI logic the Swift app, the Qt6 app and the web client use: file formats, state files, cue cards, the UI-thread orchestrator (SessionController), the emulator runtime (session, run loop, freeze state, key sequencing, frame sampling), the debugger model (DebugModel), debug snapshots, trace writer, view rules. Also trigger when adding a Bridge/ wrapper for a Shared module, or when logic is about to be written in App/*.swift, Qt6/app/ or Web/ that isn't drawing.
user-invocable: true
---

# Calc-U-59 Shared C++ Layer

Architecture, module list, threads, run loop, key input, file flows and
drawing rules: `reference/SharedArchitecture.md`. Don't restate them here.

## Rules

1. **Shared is the home of all non-GUI logic.** If code would parse, encode,
   time, sequence, build a snapshot or compute a layout number in Swift, Qt
   or the web client's JS, it belongs here instead (CLAUDE.md § "Frontend Parity").
2. **C++17, standard library only.** No Foundation, Qt or platform APIs; no
   C++20 (the CMake build is C++17 — it is the gate).
3. **No locations.** Take `std::filesystem::path` or a `ResourceReader`;
   never look up iCloud, Documents, bundles or qrc.
4. **All builds before every commit:**
   ```bash
   cmake -S . -B build/cmake -G Ninja && cmake --build build/cmake && ctest --test-dir build/cmake --output-on-failure
   xcodebuild -project Calc-U-59.xcodeproj -scheme Calc-U-59 -destination platform=macOS build
   Web/build.sh && Web/run-tests.sh
   ```
   (The Qt app builds as part of the root CMake build when Qt is installed;
   the web build needs `emcc` — calc-u-59-web skill.)
5. **No threads you can't pump.** The web build compiles `Shared/` without
   threads (`Threading::Cooperative`, `reference/SharedArchitecture.md`
   § "Cooperative mode (no threads)"). New runtime code that waits or runs
   in the background must work both ways, with a test in
   `tests/shared_cooperative_tests.cpp`. `Web/bindings.cpp` is the web's
   adapter, to update like `Qt6/app/EmulatorController` when the controller
   or `Platform` changes.
6. **Test every module** in `tests/` (`TestHarness.hpp`, `TEST`/`CHECK`;
   `TestRoms.hpp` boots machines from `roms/`). Tests run from the repo root.
7. **Commit often, never push.**

## Adding a module

1. `Shared/Foo.{hpp,cpp}` in namespace `cu59`, with a header comment saying
   what it is and where its format/rules are documented. CMake picks up new
   `.cpp` files by glob; the Xcode project by its synchronized `Shared` folder.
2. A test in `tests/`.
3. Swift access: usually through `SessionController` and its Bridge wrapper
   `Bridge/TISessionController`; a standalone module gets an ObjC++ wrapper in
   `Bridge/` (type translation only), imported from
   `Bridge/Calc-U-59-Bridging-Header.h`. C++-only helpers live in
   `Bridge/TIFileFormats+Cpp.h` and `Bridge/BridgeConvert.h` (struct/string
   conversions); never import those from the bridging header.
4. Qt access: call it directly.
5. Add the module to `reference/SharedArchitecture.md`, and a new wrapper to
   `reference/AppArchitecture.md` § "Bridge Layer".

## Porting Swift logic (goldens)

When moving existing Swift logic here, capture its behaviour first:
`tools/goldens/` holds small Swift drivers compiled together with the Swift
original (read from a pinned git commit) that print a golden file into
`tests/golden/`; the C++ test compares against it. See
`tools/goldens/README.md`. Then delete the Swift implementation — no
forwarding shims.
