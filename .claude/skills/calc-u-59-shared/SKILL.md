---
name: calc-u-59-shared
description: Use this skill when working on the shared C++ layer of Calc-U-59 (Shared/, tests/, the root CMakeLists.txt, tools/goldens/) — the non-GUI logic both the Swift app and the Qt6 app use: file formats, state files, cue cards, the emulator runtime (session, run loop, freezes, key sequencing, frame sampling), debug snapshots, trace writer, view rules. Also trigger when adding a Bridge/ wrapper for a Shared module, or when logic is about to be written in App/*.swift or Qt6/app/ that isn't drawing.
user-invocable: true
---

# Calc-U-59 Shared C++ Layer

Architecture, module list and the runtime's threads:
`reference/SharedArchitecture.md`. Don't restate them here.

## Rules

1. **Shared is the home of all non-GUI logic.** If code would parse, encode,
   time, sequence, build a snapshot or compute a layout number in Swift or
   Qt, it belongs here instead (CLAUDE.md § "Frontend Parity").
2. **C++17, standard library only.** No Foundation, Qt or platform APIs; no
   C++20 (the CMake build is C++17 — it is the gate).
3. **No locations.** Take `std::filesystem::path` or a `ResourceReader`;
   never look up iCloud, Documents, bundles or qrc.
4. **Both builds before every commit:**
   ```bash
   cmake -S . -B build/cmake -G Ninja && cmake --build build/cmake && ctest --test-dir build/cmake --output-on-failure
   xcodebuild -project Calc-U-59.xcodeproj -scheme Calc-U-59 -destination platform=macOS build
   ```
   (The Qt app builds as part of the root CMake build when Qt is installed.)
5. **Test every module** in `tests/` (`TestHarness.hpp`, `TEST`/`CHECK`;
   `TestRoms.hpp` boots machines from `roms/`). Tests run from the repo root.
6. **Commit often, never push.**

## Adding a module

1. `Shared/Foo.{hpp,cpp}` in namespace `cu59`, with a header comment saying
   what it is and where its format/rules are documented. CMake picks up new
   `.cpp` files by glob; the Xcode project by its synchronized `Shared` folder.
2. A test in `tests/`.
3. Swift access: an ObjC++ wrapper in `Bridge/` (type translation only),
   imported from `Bridge/Calc-U-59-Bridging-Header.h`. Wrappers that need the
   C++ object behind another wrapper use the `+Cpp.h` categories
   (`TI59MachineWrapper+Cpp.h`, `TIFileFormats+Cpp.h`, `TITraceWriter+Cpp.h`);
   never import those from the bridging header.
4. Qt access: call it directly.
5. Add the module to `reference/SharedArchitecture.md`.

## Porting Swift logic (goldens)

When moving existing Swift logic here, capture its behaviour first:
`tools/goldens/` holds small Swift drivers compiled together with the Swift
original (read from a pinned git commit) that print a golden file into
`tests/golden/`; the C++ test compares against it. See
`tools/goldens/README.md`. Then delete the Swift implementation — no
forwarding shims.
