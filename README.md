# Calc-U-59

A TI-58, TI-58C, and TI-59 hardware emulator with an integrated debugger for macOS and iOS, running each calculator's original ROM.

## Purpose

Calc-U-59 started as a research tool and still has that focus at its core: it accurately emulates the TMC0501 processor shared by the TI-58, TI-58C, and TI-59, and lets you step through ROM code, inspect registers, trace printer output, load raw machine-state files, and study the quirks of the original hardware.

It has also grown into a capable calculator in its own right. If you just want a faithful TI-58/58C/59 on your Mac or iPhone and don't care about the debugger, that works fine too — on iPhone the debug panel is disabled by default, so the app presents as a classic calculator out of the box.

A third audience is people who have found their own old TI-58 or TI-59 programs — whether on magnetic cards, in printed listings, or from memory — and want to revive them: run them again, understand what they actually do at the machine level, or improve them with the benefit of a full debugger.

Whether you want a classic calculator that just works, or you want to run programs under a debugger and reproduce behavior from original hardware down to the instruction level, you are in the right place.

## User Guide

**For installation and day-to-day operation (Mac, iPhone, iPad) — including a debug-panel walkthrough — use the website:**

### → https://www.calcu59.ch

This repository is developer documentation only — architecture, APIs, and file formats for people building or extending the emulator (including AI agents doing so). It does not duplicate the website's end-user content; the website links back here for anyone who wants the technical detail behind a file format or feature.

Pre-built macOS DMGs are available from this repository's [Releases page](../../releases).

## Features

- Cycle-accurate TMC0501 CPU emulation
- Integrated debugger with register inspection and program memory dump
- [Debug API](reference/DebugAPI.md) for scripted access to CPU state, breakpoints, instruction tracing, and disassembly
- Printer trace mode (functional simulation — see limitation below)
- [`.ti59` state file format](reference/StateFileFormat.md) for loading calculator state
- Card reader emulation
- A playable, real (WASM-compiled) build of the emulation core at [calcu59.ch/#play](https://www.calcu59.ch/#play) — no install required

## Current Limitations

**Printer:** The PC-100C thermal printer is not hardware-emulated. The printer output is simulated functionally: the emulator intercepts the ROM's print commands and renders characters using a pixel-accurate dot-matrix font calibrated against physical hardware, but does not model the actual printer interface timing or mechanics. It will not reproduce timing-sensitive printer interactions.

**Debug API:** Despite being a research tool, the debug API is still in its infancy. Live view and inspection, step by step
operation of both calculator-level and CPU-level instructions work, and the underlying breakpoint API is fully implemented
(`reference/DebugAPI.md` § "Breakpoints") — but there is currently no in-app UI to set one interactively; the one that
exists in source (`CPUDebugView.swift`) isn't wired into the app (see `Redesign.md` item 9). Also still missing: keypress
latch while single stepping (`KeypressLatch.md`), or any sort of dynamic freeze (e.g. on register change). The API surface
will change as it matures.

**Library module:** The Master Library module is hardcoded in the native Mac/iOS app. Switching to a different Solid State Library module is not yet supported there (the separate web build at calcu59.ch/#play does support switching modules).

**Build:** The native app is Xcode-only (macOS and iOS/iPadOS); no standalone build of the full GUI yet. The emulation core itself (`Core/`) already builds standalone and cross-platform — it compiles unmodified to WebAssembly for the web build above. See [`reference/NewGUIGuide.md`](reference/NewGUIGuide.md) if you're considering a GUI for another platform (Windows, Linux, Android, …).

**Building from source:** The project contains your Apple Developer Team ID and bundle identifier (`ch.erzberger.calcu59`). To build it yourself, open the project in Xcode, go to the target's *Signing & Capabilities* tab, and change the team to your own Apple Developer account — Xcode will update the bundle identifier automatically. To run in the Simulator no changes are needed at all. If you want iCloud (card file syncing) to work on a real device, you also need to register a new iCloud container in your Apple Developer account and update the two container identifier strings in `Calc-U-59.entitlements` to match.

## AI Programming Assistant

The file [`prompt/ti59-agent-prompt.md`](prompt/ti59-agent-prompt.md) is a system prompt that turns a capable LLM (Claude, GPT-4o, etc.) into a TI-59 expert. Paste the entire file as the system prompt, then ask the model to write, explain, or debug TI-59 programs. It outputs ready-to-load `.ti59` state files.

**What it covers:** complete key-code encoding, all instructions (conditionals, DSZ, flags, indirect addressing, subroutines), the AOS operator-precedence system, alphanumeric printing via Op 00–06, the full PC-100C character table, and `.ti59` file format rules including when to use preset registers.

**How to use it:**

1. Open your LLM interface and set `prompt/ti59-agent-prompt.md` as the system prompt.
2. Ask for a program in plain language, e.g. *"Write a program that sums 1 to N"* or *"Print a sine table from 0° to 90° in 5° steps"*.
3. The model returns a `.ti59` file. Save it and load it in the emulator.

**Token cost:** The prompt is large (~15 000 tokens). Every conversation turn carries this overhead. Use a model with a generous context window and be aware that costs add up quickly in long sessions.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and release notes. This covers the app (`Core/`, `App/`, `Bridge/`); the website (`docs/`) is a separate `gh-pages` worktree with its own git history and no version numbers of its own, so website-only changes aren't logged here.

## License

Copyright © Martin Erzberger. Licensed under the [Polyform Noncommercial License 1.0.0](LICENSE).

Free to use, modify, and redistribute — including to build ports for other platforms (Android, Windows, etc.) — for any noncommercial purpose. Commercial use requires separate written permission from the author.

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
| [`TODO.md`](TODO.md) | Unsorted backlog of ideas, bugs, and observations across the core, settings, and UI. |
| [`PRIVACY.md`](PRIVACY.md) | App Store privacy policy — Calc-U-59 collects no data and makes no network connections. |
| [`Redesign.md`](Redesign.md) | Findings from a full-codebase review flagging items that need a design decision or coordinated refactor rather than a spot fix (e.g. `EmulatorViewModel`'s threading model). |
| [`KeypressLatch.md`](KeypressLatch.md) | Unimplemented design proposal for latching keypresses while the debugger is frozen. |
| [`LICENSE`](LICENSE) | Polyform Noncommercial License 1.0.0 — free for noncommercial use and for building ports to other platforms; commercial use needs the author's written permission. |

### `reference/` — architecture reference

AI-generated by reading the source code; each file carries its own provenance notice. This is developer-facing technical documentation — for how to *use* the app, see the website above, which links back to specific files here where relevant (e.g. file formats).

| Document | Abstract |
|---|---|
| [`reference/CoreArchitecture.md`](reference/CoreArchitecture.md) | The C++ emulation core (`Core/`): TMC0501 CPU, BCD register model, SCOM memory map, instruction set, display/keyboard/card/printer subsystems, machine-variant differences. |
| [`reference/AppArchitecture.md`](reference/AppArchitecture.md) | The Swift app and ObjC++ Bridge layer: view hierarchy, threading model, the real-time emulation loop, key-input coordinate systems, state-file loading, cue-card rendering, solid-state program display, ROM loading, LED/printer rendering. |
| [`reference/DebugAPI.md`](reference/DebugAPI.md) | The two-layer debug API (CPU/trace and calculator-level) exposed by `EmulatorViewModel`/`TI59Machine` for scripted inspection, breakpoints, tracing, and the ASM overlay feature. |
| [`reference/StateFileFormat.md`](reference/StateFileFormat.md) | The `.ti59`/`.ti58`/`.ti58c` file format: sections, PARTITION formula and per-model defaults, PROGRAM/REGISTERS notation, matrix codes, KEYSTROKES syntax, and the `CUECARD:` field grammar with its math-token table. |
| [`reference/NewGUIGuide.md`](reference/NewGUIGuide.md) | Porting guide for adding a new GUI frontend (Windows/Linux/Android/etc.): the contract a new GUI must implement, what's reusable as-is, and what's currently duplicated per platform, with a future-work appendix on reducing that duplication. |

### `.claude/skills/` — AI agent skills

Trigger conditions and workflows for Claude Code when working in specific areas of the codebase. These are agent-only — a human developer should read `reference/` instead; skills are kept short and point there rather than restating content.

| Document | Abstract |
|---|---|
| [`calc-u-59-core`](.claude/skills/calc-u-59-core/SKILL.md) | Working on the C++ emulation core (`Core/`): CPU model, ROM disassembly, mnemonic workflow, trace infrastructure. |
| [`calc-u-59-swift`](.claude/skills/calc-u-59-swift/SKILL.md) | Working on the Swift/SwiftUI app (`App/`, `Bridge/`): view model, bridge, display, keyboard, debug panels, printer, card reader, settings. |
| [`calc-u-59-docs`](.claude/skills/calc-u-59-docs/SKILL.md) | Working on documentation and the help website (`docs/`, `reference/`, root markdown files); states the developer-vs-end-user documentation split and the release documentation update workflow. |
| [`calc-u-59-statefiles`](.claude/skills/calc-u-59-statefiles/SKILL.md) | Pointer to `reference/StateFileFormat.md` plus a couple of navigation aids for the two mistakes that come up most (matrix codes vs. keycodes, 2nd-function presses). |
| [`calc-u-59-uitesting`](.claude/skills/calc-u-59-uitesting/SKILL.md) | Writing/debugging XCUITest UI tests (`Calc-U-59UITests/`): file picker navigation, accessibility identifiers, orientation. |

### `memory/` — committed project analysis and traces

Checked-in analysis the project keeps for itself, distinct from any AI tool's private session memory.

| Document | Abstract |
|---|---|
| [`memory/MEMORY.md`](memory/MEMORY.md) | Index of the other files in this directory. |
| [`memory/project_context.md`](memory/project_context.md) | Project goals, key reference PDFs, and implementation phase. |
| [`memory/headless.md`](memory/headless.md) | Unimplemented plan for a Python-driven headless trace-capture runner using `.ti59` scenario files, without the GUI — see also `reference/NewGUIGuide.md` and the TODO.md items on headless/cross-platform builds. |
| [`memory/sbr444-quirk-analysis.md`](memory/sbr444-quirk-analysis.md) | Analysis of the `SBR 444`/R-S firmware quirk chain behind the "printer interrupt" hack, cross-referenced with ROM annotations and an example state file. |

### `prompt/` — LLM system prompt

| Document | Abstract |
|---|---|
| [`prompt/ti59-agent-prompt.md`](prompt/ti59-agent-prompt.md) | Drop-in, self-contained system prompt turning any capable LLM into a TI-59 programming assistant that outputs ready-to-load `.ti59` state files. Self-contained by necessity (pasted into another chat with no repo access), so it duplicates the parts of `reference/StateFileFormat.md` it needs rather than linking to it. |

### `examples/` — example and debug state files

| Document | Abstract |
|---|---|
| [`examples/assembly/README.md`](examples/assembly/README.md) | Format of the assembly examples derived from Hynek Sladký's HW programming guide. |
| [`examples/debug/readme.md`](examples/debug/readme.md) | Notes that this subfolder holds debugging/regression state files, kept separate to keep the main examples folder clean. |

### `docs/` — help website (not indexed here)

`docs/` is the end-user website (linked at the top of this README) and tracks the `gh-pages` branch as its own git worktree with its own internal (build/design-system) documentation — see the `calc-u-59-docs` skill before editing it. It is intentionally not enumerated here: this repository points to it once, rather than indexing its pages alongside developer documentation.
