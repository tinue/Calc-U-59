# Calc-U-59

A TI-59 hardware emulator and integrated debugger for macOS, built for researchers and enthusiasts who want to understand the machine rather than merely use it.

## Purpose

Calc-U-59 is a research tool, not a calculator replacement. While it accurately emulates the TI-59's processor (the TMC0501), its primary audience is people who want to explore how the TI-59 works: stepping through ROM code, inspecting registers, tracing printer output, loading raw machine-state files, and understanding the quirks of the original hardware.

A second audience is people who have found their own old TI-59 programs — whether on magnetic cards, in printed listings, or from memory — and want to revive them: run them again, understand what they actually do at the machine level, or improve them with the benefit of a full debugger.

If you are looking for a polished calculator app, this is probably not for you. If you want to run programs under a debugger, observe how the ROM handles edge cases, or reproduce behavior from original hardware, you are in the right place.

## Features

- Cycle-accurate TMC0501 CPU emulation
- Integrated debugger with register inspection and program memory dump
- [User Guide](https://www.calcu59.ch) — installation, operation, and debug-pane walkthroughs
- [Debug API](reference/DebugAPI.md) for scripted access to CPU state, breakpoints, instruction tracing, and disassembly
- Printer trace mode (functional simulation — see limitation below)
- `.ti59` state file format for loading calculator state
- Card reader emulation

## Current Limitations

**Printer:** The PC-100C thermal printer is not hardware-emulated. The printer output is simulated functionally: the emulator intercepts the ROM's print commands and renders characters using a pixel-accurate dot-matrix font calibrated against physical hardware, but does not model the actual printer interface timing or mechanics. It will not reproduce timing-sensitive printer interactions.

**Debug API:** Despite being a research tool, the debug API is still in its infancy. Live view and inspection, step by step
operation of both calculator-level and CPU-level instructions work. Still missing are breakpoints, keypress latch while
single stepping, or any sort of dynamic freeze (e.g. on register change). The API surface will change as it matures.

**Library module:** The Master Library module is hardcoded. Switching to a different Solid State Library module is not yet supported.

**Build:** Xcode only (macOS and iOS/iPadOS). No standalone build or cross-platform support yet.

**Building from source:** The project contains your Apple Developer Team ID and bundle identifier (`ch.erzberger.calcu59`). To build it yourself, open the project in Xcode, go to the target's *Signing & Capabilities* tab, and change the team to your own Apple Developer account — Xcode will update the bundle identifier automatically. To run in the Simulator no changes are needed at all. If you want iCloud (card file syncing) to work on a real device, you also need to register a new iCloud container in your Apple Developer account and update the two container identifier strings in `Calc-U-59.entitlements` to match.

## User Guide

For installation and day-to-day operation (Mac, iPhone, iPad), use the user guide:

- https://www.calcu59.ch

Pre-built macOS DMGs are available from this repository's [Releases page](../../releases).

## AI Programming Assistant

The file [`prompt/ti59-agent-prompt.md`](prompt/ti59-agent-prompt.md) is a system prompt that turns a capable LLM (Claude, GPT-4o, etc.) into a TI-59 expert. Paste the entire file as the system prompt, then ask the model to write, explain, or debug TI-59 programs. It outputs ready-to-load `.ti59` state files.

**What it covers:** complete key-code encoding, all instructions (conditionals, DSZ, flags, indirect addressing, subroutines), the AOS operator-precedence system, alphanumeric printing via Op 00–06, the full PC-100C character table, and `.ti59` file format rules including when to use preset registers.

**How to use it:**

1. Open your LLM interface and set `prompt/ti59-agent-prompt.md` as the system prompt.
2. Ask for a program in plain language, e.g. *"Write a program that sums 1 to N"* or *"Print a sine table from 0° to 90° in 5° steps"*.
3. The model returns a `.ti59` file. Save it and load it in the emulator.

**Token cost:** The prompt is large (~15 000 tokens). Every conversation turn carries this overhead. Use a model with a generous context window and be aware that costs add up quickly in long sessions.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and release notes.

## License

Copyright © Martin Erzberger. Licensed under the [Polyform Noncommercial License 1.0.0](LICENSE).

Free to use, modify, and redistribute — including to build ports for other platforms (Android, Windows, etc.) — for any noncommercial purpose. Commercial use requires separate written permission from the author.

## Acknowledgements

Special thanks to:

- **hrastprogrammer** ([hrastprogrammer.com](https://www.hrastprogrammer.com)) for the first emulator core that made this work possible.
- **Hynek Sladký** ([hsl.wz.cz/ti_59.htm](https://hsl.wz.cz/ti_59.htm) — currently offline, [archived 2024-08-18](https://web.archive.org/web/20240818211248/https://hsl.wz.cz/ti_59.htm)) for the initial ROM dump of the TI-59.
