# Project Context

## Skills

Invoke the right skill before starting work in each area:

| Skill | Invoke for |
|-------|-----------|
| `calc-u-59-core` | C++ emulation core (`Core/`, `tools/`, ROM disassembly, trace infrastructure) |
| `calc-u-59-shared` | Shared C++ layer (`Shared/`, `tests/`, root `CMakeLists.txt`, `tools/goldens/`) — non-GUI logic all three frontends use |
| `calc-u-59-swift` | Swift/SwiftUI app (`App/`, `App/Views/`, `Bridge/`) |
| `calc-u-59-qt` | Qt6 desktop app (`Qt6/`, `.github/workflows/build.yml`, Qt packaging) |
| `calc-u-59-web` | Web client (`Web/`: React + WASM engine, PWA, `Web/build.sh`, `Web/dist/`, the `web` CI job) |
| `calc-u-59-docs` | Documentation (`reference/`, root markdown files); the user guide lives in `../calc-u-site` and is updated with them |
| `calc-u-59-statefiles` | Writing `.ti59`/`.ti58`/`.ti58c` state files — format, matrix codes, KEYSTROKES sequences |
| `calc-u-59-uitesting` | XCUITest UI tests (`Calc-U-59UITests/`) — file picker navigation, accessibility identifiers, orientation |

## Architecture Reference

Architecture facts (register model, SCOM layout, PC encoding, machine variants, trace API) live in:

- `reference/CoreArchitecture.md` — C++ emulation core
- `reference/SharedArchitecture.md` — the shared C++ layer and its runtime threads
- `reference/AppArchitecture.md` — Swift app and bridge layer
- `reference/DebugAPI.md` — debug panel and bridge API
- `reference/FrontendParity.md` — which feature lives where in the three GUIs
- `reference/WebClient.md` — the web client and its `dist/` contract
- `reference/StateFileFormat.md` — the `.ti59`/`.ti58`/`.ti58c` file format
- `rom/TI59-ROM-Guide.md`, `rom/TI58C-ROM-Guide.md` — how the ROMs work

Do not restate these facts in CLAUDE.md, skills, or memory files — link to the reference doc instead.

## Agentic tools

`tools/agentic/` holds command-line tools for running, timing and profiling
`.ti59` programs headless (run a file, per-line print times, run time per
key, hot steps, step costs, keycode disassembler/assembler). Read
`tools/agentic/README.md` before measuring or comparing program speed.
ROM-level traces of key sequences come from `tools/headless/` (its README).

## Frontend Parity (Swift app ↔ Qt6 app ↔ web client)

Three GUIs share `Core/` (hardware) and `Shared/` (everything else that isn't
drawing): the Swift app (macOS, iOS — the Mac product, with iCloud), the
Qt6 app (Windows and Linux; its macOS build is for development only, never
shipped and never built in CI) and the web client (`Web/`, embedded by the
website; TI-59 only, no printer, debugger or traces). Keep them in step:

- **Non-GUI logic goes in `Shared/` only** — parsing, file formats, timing,
  key sequencing, snapshot building, layout rules and numbers the renderers
  use. Never write such logic in `App/*.swift`, `Qt6/app/` or `Web/`; put it
  in `Shared/` and call it (Bridge/ wrapper for Swift, directly from Qt,
  `Web/bindings.cpp` for the web).
- **`Bridge/`, the Qt adapters and `Web/bindings.cpp` translate types only.**
- **`Shared/` never resolves locations.** It takes paths or a ResourceReader;
  iCloud lives only in `App/CardStorage.swift` (and `AppSettings.traceDirectory()`).
- **A user-visible change in one GUI needs the matching change in the others
  on the same branch** — or a `Pending (Qt)` / `Pending (Swift)` /
  `Pending (Web)` row with a reason in `reference/FrontendParity.md`. Features
  outside the web's scope need no web change (its column says so). Update
  that table either way. `tools/check_parity.sh` flags a branch that touches
  one GUI only.
- **Every change to `Core/` or `Shared/` must pass all builds before committing:**
  `cmake -S . -B build/cmake -G Ninja && cmake --build build/cmake && ctest --test-dir build/cmake --output-on-failure`,
  `xcodebuild -project Calc-U-59.xcodeproj -scheme Calc-U-59 -destination platform=macOS build`,
  and the web client, which compiles both layers too:
  `Web/build.sh && Web/run-tests.sh` (`Web/dist/` is gitignored; CI builds it).
  `Shared/` stays C++17 and standard-library-only, and must work without threads
  (`Threading::Cooperative`, used by the web build).
- **Settings both apps store** (key names, defaults, resolution) live in
  `Shared/SettingsKeys.hpp`; `App/AppSettings.swift` and `Qt6/app/AppSettings.hpp` use them.
- **Assets have one source:** ROMs in `roms/`, artwork in `App/Assets.xcassets`,
  the icon in `App/AppIcon.icon` (`tools/gen_qt_icons.sh` derives the Qt icons;
  `Web/build.sh` copies the Linux one), presets the web offers in `examples/`.
- **Version:** `MARKETING_VERSION` in the Xcode project is the only version;
  the Qt build and the web build read it.

