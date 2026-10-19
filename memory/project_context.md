---
name: Calc-U-59 project context
description: Goals, platforms and key reference PDFs of the Calc-U-59 (TI-59/58/58C) emulator
type: project
---

Cycle-accurate emulator of the TI-59, TI-58 and TI-58C, running the original
ROMs. `Core/` (C++) emulates the hardware, `Shared/` (C++) holds the
non-drawing logic, and two GUIs draw: the Swift app (macOS as a DMG, iOS and iPadOS
in the App Store) and the Qt6 app (Windows, Linux). Current version:
`CHANGELOG.md`; open work: `TODO.md`; architecture: `reference/`.

**Key reference PDFs** (external hardware documentation, not in this
repository; cited by name):
- `TI_58_59-HW-manual.pdf` — Hynek Sladký's 28-page HW guide: complete instruction list, SCOM register layout, display decode table, signal descriptions
- `TI 59-service-manual.pdf` — Official TI 65-page service manual: chip names (DSCOM/BROM/CROM), keyboard matrix Figure 3, display Figure 4, printer interface Figures 7–10, function test sequences, full schematic
- `Individuelles_Programmieren_TI59.pdf` — Official German user manual ~350pp: program opcode table (00–99), AOS explanation, all key functions, printer/card/library modules

**Correctness details from an OCR pass of these PDFs (March 2026)** —
historical notes; the code and `reference/` win where they differ:
- IO bus carries pre-BCD data (hexadecimal possible) — affects RAM/SCOM read correctness
- SHR does NOT go through the ALU; SHL does (with a DPT edge case at digit 0)
- `WAIT Dn`: the instruction after it runs at digit n−1 (`reference/CoreArchitecture.md`)
- Card reader routines at ROM 0x16B2–0x1796 (in the TMC0571 BROM block)
- SCOM rows 0–15, including the AOS stack: `reference/CoreArchitecture.md`, `rom/TI59-ROM-Guide.md`
