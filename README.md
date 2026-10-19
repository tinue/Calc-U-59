# Calc-U-59

A TI-58, TI-58C, and TI-59 hardware emulator with an integrated debugger for macOS, iOS, Windows and Linux, running each calculator's original ROM.

## Purpose

Calc-U-59 started as a research tool and still has that focus at its core: it accurately emulates the TMC0501 processor shared by the TI-58, TI-58C, and TI-59, and lets you step through ROM code, inspect registers, trace printer output, load raw machine-state files, and study the quirks of the original hardware.

It has also grown into a capable calculator in its own right. If you just want a faithful TI-58/58C/59 on your Mac, iPhone, iPad or Windows/Linux PC and don't care about the debugger, that works fine too — on iPhone the debug panel is disabled by default, so the app presents as a classic calculator out of the box.

A third audience is people who have found their own old TI-58 or TI-59 programs — whether on magnetic cards, in printed listings, or from memory — and want to revive them: run them again, understand what they actually do at the machine level, or improve them with the benefit of a full debugger.

Whether you want a classic calculator that just works, or you want to run programs under a debugger and reproduce behavior from original hardware down to the instruction level, you are in the right place.

## User Guide

**For installation and day-to-day operation — including a debug-panel walkthrough — use the website:**

### → https://www.calcu59.ch

This repository is developer documentation only — architecture, APIs, and file formats for people building or extending the emulator (including AI agents doing so). It does not duplicate the website's end-user content; the website links back here for anyone who wants the technical detail behind a file format or feature.

Pre-built macOS DMGs, Windows installers (x64, ARM64) and Linux AppImages (x86_64, aarch64) are on this repository's [Releases page](../../releases); the iPhone and iPad app is on the App Store.

## Features

- Cycle-accurate TMC0501 CPU emulation
- Two native apps and a web client on one shared C++ layer: Swift for macOS, iOS and iPadOS (with iCloud card sync), Qt6 for Windows and Linux, and the browser (`Web/`, the engine compiled to WebAssembly)
- Integrated debugger with register inspection and program memory dump
- [Debug API](reference/DebugAPI.md) for scripted access to CPU state, breakpoints, instruction tracing, and disassembly
- Printer trace mode (functional simulation — see limitation below)
- [`.ti59` state file format](reference/StateFileFormat.md) for loading calculator state
- Card reader emulation and the Solid State Software modules, with cue cards
- The web client, playable at [calcu59.ch/play](https://www.calcu59.ch/play/) — no install required

## Current Limitations

**Printer:** The PC-100C thermal printer is simulated functionally: the emulator intercepts the ROM's print commands, keeps the printer busy for a line's print time (enough for the [printer interrupt](rom/printerinterrupt.md)), and renders characters with a dot-matrix font calibrated against physical hardware. The print head and paper mechanics are not modeled.

**Debugger:** Live view and inspection, and stepping both calculator-level and CPU-level instructions work. The core has a breakpoint API used by the headless tools (`reference/DebugAPI.md` § "Breakpoints"), but neither app has a UI to set one. Also missing: keypress latch while single-stepping (`ideas/KeypressLatch.md`) and conditional freezes (e.g. on a register change). The API surface will change as it matures.

## Building

The code is layered: `Core/` emulates the hardware, `Shared/` (C++17, standard library only) holds all non-drawing logic, and the three GUIs only draw — see [`reference/SharedArchitecture.md`](reference/SharedArchitecture.md) and [`reference/FrontendParity.md`](reference/FrontendParity.md).

**Swift app (macOS, iOS, iPadOS):** open `Calc-U-59.xcodeproj` in Xcode, or `xcodebuild -project Calc-U-59.xcodeproj -scheme Calc-U-59 -destination platform=macOS build`. The project carries the author's Apple Developer Team ID and bundle identifier (`ch.erzberger.calcu59`). To build it yourself, change the team on the target's *Signing & Capabilities* tab to your own; Xcode updates the bundle identifier. The Simulator needs no changes. For iCloud card sync on a real device, also register a new iCloud container and update the two container identifiers in `Calc-U-59.entitlements`.

**C++ build, tests and Qt6 app:** the root CMake build compiles `Core/`, `Shared/`, the C++ test suite and, when Qt6 is found, the Qt app (`-DCALCU59_BUILD_QT=OFF` skips it):

```bash
cmake -S . -B build/cmake -G Ninja && cmake --build build/cmake && ctest --test-dir build/cmake --output-on-failure
```

`tools/build_qt.sh` builds only the Qt app into `Qt6/build`; `./build_and_run.sh [file.ti59]` builds and starts it. On macOS, Qt comes from Homebrew and the Qt build is for development only. The Windows and Linux packages are built by CI (`.github/workflows/build.yml`), which also lists the packages each platform needs.

**Web client:** `Web/build.sh` compiles `Core/` and `Shared/` with Emscripten (`emcc`, e.g. `brew install emscripten`) and builds a self-contained `Web/dist/` that the website embeds; `Web/run-tests.sh` runs its Playwright tests against it. CI builds it too and uploads it zipped. See [`reference/WebClient.md`](reference/WebClient.md).

See [`reference/NewGUIGuide.md`](reference/NewGUIGuide.md) if you're considering a GUI for yet another platform.

## AI Programming Assistant

The file [`prompt/ti59-agent-prompt.md`](prompt/ti59-agent-prompt.md) is a system prompt that turns a capable LLM (Claude, GPT-4o, etc.) into a TI-59 expert. Paste the entire file as the system prompt, then ask the model to write, explain, or debug TI-59 programs. It outputs ready-to-load `.ti59` state files.

**What it covers:** complete key-code encoding, all instructions (conditionals, DSZ, flags, indirect addressing, subroutines), the AOS operator-precedence system, alphanumeric printing via Op 00–06, the full PC-100C character table, and `.ti59` file format rules including when to use preset registers.

**How to use it:**

1. Open your LLM interface and set `prompt/ti59-agent-prompt.md` as the system prompt.
2. Ask for a program in plain language, e.g. *"Write a program that sums 1 to N"* or *"Print a sine table from 0° to 90° in 5° steps"*.
3. The model returns a `.ti59` file. Save it and load it in the emulator.

**Token cost:** The prompt is large (about 40 KB, roughly 10 000 tokens). Every conversation turn carries this overhead. Use a model with a generous context window and be aware that costs add up quickly in long sessions.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and release notes. This covers the apps and the web client (`Core/`, `Shared/`, `App/`, `Bridge/`, `Qt6/`, `Web/`); the website (`docs/`) is a separate `gh-pages` worktree with its own git history and no version numbers of its own, so website-only changes aren't logged here.

## License

Copyright (C) 2026 Martin Erzberger. Calc-U-59 is free software, licensed
under the [GNU General Public License, version 3](LICENSE) (GPLv3); see
[NOTICE](NOTICE) for the full copyright notice.

The Windows and Linux app is built on [Qt6](https://www.qt.io/), used under
the LGPLv3 — see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for Qt and
for the `roms/` ROM images, which are third-party copyrighted material not
covered by this project's license.

## Acknowledgements

Special thanks to:

- **hrastprogrammer** ([hrastprogrammer.com](https://www.hrastprogrammer.com)) for the first emulator core that made this work possible.
- **Hynek Sladký** ([hsl.wz.cz/ti_59.htm](https://hsl.wz.cz/ti_59.htm) — currently offline, [archived 2024-08-18](https://web.archive.org/web/20240818211248/https://hsl.wz.cz/ti_59.htm)) for the initial ROM dump of the TI-59.

## Appendix: Documentation Index

This repository's documentation is for developers (and AI agents working on
the code) — not end users. Every document here, grouped by location, with a
one-line abstract. Start here before writing new documentation — several of
these already cover ground a new document might otherwise duplicate.

End-user documentation (installing, operating, debug-panel walkthrough) is
**not** indexed here — it lives entirely on the website linked above and
isn't duplicated in this repository.

### Project root

| Document | Abstract |
|---|---|
| [`README.md`](README.md) | This file — project overview, features, limitations, and this index. |
| [`CLAUDE.md`](CLAUDE.md) | Skill-routing table and pointers to the architecture reference docs, for AI coding agents working in this repo. |
| [`CHANGELOG.md`](CHANGELOG.md) | Version history, one heading per release. |
| [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) | Qt6 (LGPLv3) notice for the Windows/Linux app; status of the `roms/` ROM images. |
| [`TODO.md`](TODO.md) | Unsorted backlog of ideas, bugs, and observations across the core, settings, and UI. |
| [`release.yaml`](release.yaml) | Release configuration for ReleaseIt: the Mac DMG built locally, the Windows/Linux packages and the web client's zip from CI, the iOS App Store upload. |
| [`PRIVACY.md`](PRIVACY.md) | App Store privacy policy — Calc-U-59 collects no data and makes no network connections. |
| [`ideas/KeypressLatch.md`](ideas/KeypressLatch.md) | Unimplemented design proposal for latching keypresses while the debugger is frozen. |
| [`ideas/Pico.md`](ideas/Pico.md) | Feasibility analysis for running the core on a Raspberry Pi Pico wired to a real TI-59's keyboard, display, and card reader. |
| [`ideas/CardRecovery.md`](ideas/CardRecovery.md) | Signal-chain analysis and breadboard circuit design for a standalone Pico-based magnetic-card reader, aimed at recovering cards a stock TI-59 fails to read. |
| [`LICENSE`](LICENSE) | GNU General Public License, version 3 (GPLv3). |
| [`NOTICE`](NOTICE) | Copyright notice for the GPLv3 license. |

### `reference/` — architecture reference

AI-generated by reading the source code; each file carries its own provenance notice. This is developer-facing technical documentation — for how to *use* the app, see the website above, which links back to specific files here where relevant (e.g. file formats).

| Document | Abstract |
|---|---|
| [`reference/CoreArchitecture.md`](reference/CoreArchitecture.md) | The C++ emulation core (`Core/`): TMC0501 CPU, BCD register model, SCOM memory map, instruction set, display/keyboard/card/printer subsystems, machine-variant differences. |
| [`reference/SharedArchitecture.md`](reference/SharedArchitecture.md) | The shared C++ layer (`Shared/`) all three GUIs use: modules, `SessionController`, threads, the real-time emulation loop, key input and the physical keyboard map, card reader, state-file loading, ROM loading, drawing rules, tests and goldens. |
| [`reference/FrontendParity.md`](reference/FrontendParity.md) | Feature-by-feature table of the Swift app, the Qt6 app and the web client — where each feature lives and what is platform-specific. |
| [`reference/WebClient.md`](reference/WebClient.md) | The web client (`Web/`): layout, build, and the contract of the `Web/dist/` folder the website embeds — mounting `PlayCalculator`, location independence, no side effects in render, styling, the PWA, `MANIFEST.json`. |
| [`reference/AppArchitecture.md`](reference/AppArchitecture.md) | The Swift app and ObjC++ `Bridge/` layer on top of `Shared/`: layers, file responsibilities, threading, Swift-specific details. |
| [`reference/DebugAPI.md`](reference/DebugAPI.md) | The debugger across Core (trace, breakpoints, CpuFrame), Shared (`DebugModel`, snapshots, LOG, trace files, ASM overlay) and both GUIs’ debug panels. |
| [`reference/StateFileFormat.md`](reference/StateFileFormat.md) | The `.ti59`/`.ti58`/`.ti58c` file format: sections, PARTITION formula and per-model defaults, PROGRAM/REGISTERS notation, matrix codes, KEYSTROKES syntax, and the `CUECARD:` field grammar with its math-token table. |
| [`reference/NewGUIGuide.md`](reference/NewGUIGuide.md) | Porting guide for adding another GUI frontend: building on `Shared/` (the Qt6 app as the worked example), or compiling `Shared/` for a platform without threads (the web build as the example). |

### `.claude/skills/` — AI agent skills

Trigger conditions and workflows for Claude Code when working in specific areas of the codebase. These are agent-only — a human developer should read `reference/` instead; skills are kept short and point there rather than restating content.

| Document | Abstract |
|---|---|
| [`calc-u-59-core`](.claude/skills/calc-u-59-core/SKILL.md) | Working on the C++ emulation core (`Core/`): CPU model, ROM disassembly, mnemonic workflow, trace infrastructure. |
| [`calc-u-59-shared`](.claude/skills/calc-u-59-shared/SKILL.md) | Working on the shared C++ layer (`Shared/`, `tests/`, root CMake): rules, adding a module and its Bridge wrapper, golden-file ports. |
| [`calc-u-59-qt`](.claude/skills/calc-u-59-qt/SKILL.md) | Working on the Qt6 app (`Qt6/`, CI workflow): ship scope (Windows/Linux), class map against the Swift views, threading, build and packaging. |
| [`calc-u-59-web`](.claude/skills/calc-u-59-web/SKILL.md) | Working on the web client (`Web/`): rules (no logic, location independence, no side effects in render, own styling), build and tests; points to `reference/WebClient.md`. |
| [`calc-u-59-swift`](.claude/skills/calc-u-59-swift/SKILL.md) | Working on the Swift/SwiftUI app (`App/`, `Bridge/`): view model, bridge, display, keyboard, debug panels, printer, card reader, settings. |
| [`calc-u-59-docs`](.claude/skills/calc-u-59-docs/SKILL.md) | Working on documentation and the help website (`docs/`, `reference/`, root markdown files); states the developer-vs-end-user documentation split and the release documentation update workflow. |
| [`calc-u-59-statefiles`](.claude/skills/calc-u-59-statefiles/SKILL.md) | Pointer to `reference/StateFileFormat.md` plus a couple of navigation aids for the two mistakes that come up most (matrix codes vs. keycodes, 2nd-function presses). |
| [`calc-u-59-uitesting`](.claude/skills/calc-u-59-uitesting/SKILL.md) | Writing/debugging XCUITest UI tests (`Calc-U-59UITests/`): file picker navigation, accessibility identifiers, orientation. |

### `memory/` — committed project analysis and traces

Checked-in analysis the project keeps for itself, distinct from any AI tool's private session memory.

| Document | Abstract |
|---|---|
| [`memory/MEMORY.md`](memory/MEMORY.md) | Index of the other files in this directory. |
| [`memory/sbr444-quirk-analysis.md`](memory/sbr444-quirk-analysis.md) | Trace-level analysis of the `SBR 444`/R-S firmware quirk chain in the article's printer-interrupt sequence (overview: `rom/printerinterrupt.md`). The `*.txt` files beside it are the CPU traces it and the ROM annotations cite. |

### `rom/` — ROM listings and guides

| Document | Abstract |
|---|---|
| [`rom/TI59-ROM-Guide.md`](rom/TI59-ROM-Guide.md), [`rom/TI58C-ROM-Guide.md`](rom/TI58C-ROM-Guide.md) | How each ROM works, as a guide to the annotated listings (`*-commented.asm`, `*-labels.asm`, `*-keycode-programs.asm`). |
| [`rom/fastmode.md`](rom/fastmode.md) | Fast mode: what it is, the rules for fast-mode programs, the ways in, and how the hack works. |
| [`rom/printerinterrupt.md`](rom/printerinterrupt.md) | The printer interrupt (keycode 1F): how to use it, how the code is made, and how it works. |

### `tools/` — developer tools

| Document | Abstract |
|---|---|
| [`tools/headless/README.md`](tools/headless/README.md) | Python harness that drives `Core/` without a GUI and prints ROM traces of key sequences. |
| [`tools/agentic/README.md`](tools/agentic/README.md) | Command-line tools to run, time and profile `.ti59` programs headless, plus a keycode disassembler and assembler. |
| [`tools/goldens/README.md`](tools/goldens/README.md) | How the golden files that check the `Shared/` ports against the former Swift code are made. |

### `prompt/` — LLM system prompt

| Document | Abstract |
|---|---|
| [`prompt/ti59-agent-prompt.md`](prompt/ti59-agent-prompt.md) | Drop-in, self-contained system prompt turning any capable LLM into a TI-59 programming assistant that outputs ready-to-load `.ti59` state files. Self-contained by necessity (pasted into another chat with no repo access), so it duplicates the parts of `reference/StateFileFormat.md` it needs rather than linking to it. |

### `examples/` — example and debug state files

| Document | Abstract |
|---|---|
| [`examples/CALENDAR_PROGRAMS.md`](examples/CALENDAR_PROGRAMS.md) | History of the 1978–1981 calendar-printer competition and a timing comparison of the `calendar-0*.ti59` programs. |
| [`examples/assembly/README.md`](examples/assembly/README.md) | Format of the assembly examples derived from Hynek Sladký's HW programming guide. |
| [`examples/debug/readme.md`](examples/debug/readme.md) | Notes that this subfolder holds debugging/regression state files, kept separate to keep the main examples folder clean. |

### `docs/` — help website (not indexed here)

`docs/` is the end-user website (linked at the top of this README) and tracks the `gh-pages` branch as its own git worktree with its own internal (build/design-system) documentation — see the `calc-u-59-docs` skill before editing it. It is intentionally not enumerated here: this repository points to it once, rather than indexing its pages alongside developer documentation.
