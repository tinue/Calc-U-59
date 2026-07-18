---
name: calc-u-59-statefiles
description: Use this skill when writing or editing .ti59 / .ti58 / .ti58c state files, including KEYSTROKES sequences, PROGRAM listings, and screenshot-automation scenario files. Covers the file format, the matrix-code vs. keycode distinction, and the 2nd-function lookup table.
user-invocable: true
---

# Calc-U-59 State File Format

The full format grammar — sections, PARTITION formula and per-model defaults,
PROGRAM/REGISTERS notation, the matrix-code vs. keycode distinction, the
2nd-function table, KEYSTROKES syntax (`Wait:`/`WaitFullSpeed:`/`Trace:`),
`SKIP-RESET:`, and the `CUECARD:` field grammar with its math-token table —
lives in **`reference/StateFileFormat.md`**. Read that document before
writing or editing a state file; nothing here duplicates it.

The authoritative parser is `App/StateFileLoader.swift`; that file's own
header comment is the ground truth if this skill or the reference doc ever
disagree with it.

---

## Quick facts worth keeping in working memory while editing a file

These are navigation aids, not a substitute for the reference doc — they
just save a round trip for the two mistakes that come up most:

- **KEYSTROKES uses matrix codes (11–95, row×10+col); PROGRAM uses keycodes
  (0–99, the ROM's internal encoding).** These are different numbering
  systems for the same physical keys — see `reference/StateFileFormat.md`'s
  "KEYSTROKES vs. PROGRAM" table before hand-writing either section.
- **2nd functions in KEYSTROKES are two presses**, `21` then the key's matrix
  code — never the "2nd keycode" from the PROGRAM section's numbering.
- **CUECARD math tokens** (`\lambda`, `^{2}`, `_{i}`, etc.) are documented in
  `reference/StateFileFormat.md`; the canonical token table itself lives in
  `App/CueCardContent.swift`, not in any markdown file.

## Where to look for related work

- Writing test/regression scenario files for XCUITest: see the
  `calc-u-59-uitesting` skill for file-picker navigation and verifying a
  loaded state.
- Building a new (non-Swift, non-Web) GUI that needs to parse this format:
  see `reference/NewGUIGuide.md`.
