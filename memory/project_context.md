---
name: Calc-U-59 project context
description: Goals, key reference PDFs, current phase, and implementation status for the Calc-U-59 (TI-59/58/58C) Apple ecosystem emulator
type: project
---

Cycle-accurate emulator of TI-59/58/58C for macOS 26 / iOS 26 / iPadOS 26 in Swift + C++.

**Current phase:** Implementation complete for all three variants (TI-59/58/58C); shipping on the App Store with ongoing feature and bug-fix releases — see `CHANGELOG.md` for the current version and `TODO.md` for open work. This entry's original "not yet started" note is long stale; kept only as a historical marker of when this file was written.

**Key reference PDFs** (external hardware documentation, not committed to this repository — most likely for copyright reasons; the paths below no longer resolve and are kept as citations only):
- `TI_58_59-HW-manual.pdf` — Hynek Sladký's 28-page HW guide: complete instruction list, SCOM register layout, display decode table, signal descriptions
- `TI 59-service-manual.pdf` — Official TI 65-page service manual: chip names (DSCOM/BROM/CROM), keyboard matrix Figure 3, display Figure 4, printer interface Figures 7–10, function test sequences, full schematic
- `Individuelles_Programmieren_TI59.pdf` — Official German user manual ~350pp: program opcode table (00–99), AOS explanation, all key functions, printer/card/library modules

**Why:** Important correctness details found in fresh OCR pass (March 2026):
- IO bus carries pre-BCD data (hexadecimal possible) — affects RAM/SCOM read correctness
- SHR does NOT go through ALU; SHL does (with DPT edge case at digit 0)
- WAIT Dn: argument must be 1 higher than target digit (counter decrements before check)
- Card reader routines at ROM 0x16B2–0x1796 (in TMC0571 BROM block)
- SCOM regs 0–15: detailed AOS hierarchy stack layout documented in architecture.md
