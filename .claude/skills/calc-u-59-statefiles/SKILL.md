---
name: calc-u-59-statefiles
description: Use this skill when writing or editing .ti59 / .ti58 / .ti58c state files, including KEYSTROKES sequences, PROGRAM listings, and screenshot-automation scenario files. Covers the file format, the matrix-code vs. keycode distinction, and the 2nd-function lookup table.
user-invocable: true
---

# Calc-U-59 State Files

The format — sections, PARTITION, PROGRAM and REGISTERS notation, print-code
register values, matrix codes vs. keycodes, the 2nd-function table,
KEYSTROKES directives, reloads, `CARD:` blocks and `ArmCard:`/`InsertCard:`,
SKIP-RESET, the CUECARD grammar — is in
**`reference/StateFileFormat.md`**. Read it before writing or editing a
file. The parser, `Shared/StateFile.cpp`, wins if the two disagree.

## Mistakes that come up most

- **KEYSTROKES takes matrix codes (row × 10 + col), PROGRAM takes keycodes.**
  Digit 1 is `82` in KEYSTROKES and `01` in PROGRAM.
- **A 2nd function in KEYSTROKES is two presses:** `21`, then the key.
- **`#` starts a comment anywhere**, also inside a cue-card value.
- **Order matters:** `PROGRAM:`/`REGISTERS:`/`CUECARD:`/`PARTITION:` after
  `KEYSTROKES:` are a reload played mid-script, not part of the load. Put
  them first unless that is what you mean.
- **Reload or card?** A reload is keyed-in changes: only the listed steps
  and registers change (a `...` gap stays as it was). A card replaces a
  whole bank. Use `InsertCard:` when the program stops for a card, and
  `ArmCard:` when it runs `Write` / `INV Write` itself.
- **Adv (`21 93`) needs `RegularSpeed:`** or the paper runs away.
- **Check a file by loading it:** `tools/agentic/` runs `.ti59` files
  headless (`tools/agentic/README.md`). It doesn't know reloads or preset
  cards; check those in an app or with a controller test.

## Transcribing magazine listings (52-Notes)

Lessons from the 52-Notes calendar programs
(`examples/calendar-01-Weinberger.ti59` and the rest of the series, see
`examples/CALENDAR_PROGRAMS.md`). The listings use their own shorthand
(`S29`/`R13` for STO/RCL, `rtn` for the merged RTN, `CP`, `x=t`, `xGEt`,
`Op`, `Adv`, `Pgm` for 2nd functions); don't assume it carries over to
other sources.

- **Keep packed print-code registers as printed.** A register with four
  characters has eight digits; don't pad it to ten with `00`.
- **An OCR'd "xXt" can be `x=t` (67) or `x⇄t` (32), and the step count
  doesn't decide it.** A branch destination can be a single step (any
  keycode but 00–09 and 40 is a label, `Shared/KeyNames.hpp`
  `argumentSteps`), so `x=t` plus its label takes the same two steps as
  `x⇄t` plus the next instruction. Decide each occurrence by what makes
  sense at that point: a branch, or an exchange.

## Related

- XCUITest scenario files and verifying a load: `calc-u-59-uitesting`.
- A new GUI that parses this format: `reference/NewGUIGuide.md`.
