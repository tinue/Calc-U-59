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

## PC-100/PC-100A printer character-code table

Some `REGISTERS:` values aren't numbers at all — they're print-buffer data:
a register packs up to five 2-digit character codes (up to 10 decimal digits)
that the ROM's print routine feeds to the PC-100/PC-100A thermal printer.
You'll hit this when transcribing a magazine/manual program listing whose
"Prestored Data" holds strings (weekday/month names, labels) rather than
arithmetic constants. **Don't force every chunk to a uniform width** — see
"52-Notes" below.

**Each 2-digit code is a `row col` pair, not a base-10 number** — the digits
address an 8×8 grid, so the character index is `row*8 + col`, not
`row*10 + col`. E.g. code `36` means row 3, col 6 → `S`, not index 36 of a
flat 0–63 array read in base 10.

```
     col 0  1  2  3  4  5  6  7
row0    (sp) 0  1  2  3  4  5  6
row1     7  8  9  A  B  C  D  E
row2     -  F  G  H  I  J  K  L
row3     M  N  O  P  Q  R  S  T
row4     .  U  V  W  X  Y  Z  +
row5     x  *  √  π  e  (  )  ,
row6     ↑  %  ⇄  /  =  '  ˣ  x̄
row7     ²  ?  ÷  !  Ⅱ  ▴  ∏  ∑
```

Source of truth: `PRN_CODE[64]` in `Core/TMC0501.cpp` (consumed by the
`OUT PRT` opcode handler) — that array's declaration order is exactly this
grid, row-major, 8 entries per row. Decode a register value by splitting it
into 2-digit groups and looking up `table[row*8+col]` for each; e.g. register
value `3013351523` → groups `30,13,35,15,23` → row/col lookups → `MARCH`.

There's a second, unrelated table in the same file, `PRN_STR[]` — a sparse
7-bit function-code → 3-letter-mnemonic lookup (`STO`, `RUN`, `SIN`, …) used
for printing keystroke/function names during LIST/trace printing, not for
decoding dense character data out of a register.

## 52-Notes

Rules learned transcribing a specific magazine-listing notation style (the
Jared Weinberger "Calendar Printer" PC-100A program, `examples/calendar.ti59`)
into a state file. This shorthand — `S29`/`R13` for STO/RCL, `rtn` for
merged RTN, `CP`/`x=t`/`xGEt`/`Op`/`Adv`/`Pgm` for their 2nd-function keys —
appears to be specific to this magazine's compact print style, not a
general TI convention, so treat it as a source-specific dialect rather than
assuming it transfers to other listings unchanged. Two lessons worth
carrying forward to the *next* listing in this same dialect:

- **Don't pad a short packed-string register out to a "standard" width.**
  `REGISTERS:` values that hold packed PC-100 print codes (see the table
  above) don't all need to be the same number of digits — a register that
  only needs 4 characters legitimately has an 8-digit value, not a
  10-digit one with a fabricated trailing `00`. Transcribe the digits
  exactly as printed; don't round a short chunk up to match its neighbors.
- **"xXt"-style OCR garble is genuinely ambiguous between EQ (`x=t`) and
  X⇄T (exchange, keycode 32), and the step-count checksum does not always
  resolve it.** Both readings can cost the same number of program steps —
  X⇄T alone is 1 step, and EQ's destination-byte encoding sometimes needs
  only 1 byte too (the "arbitrary keycode as a 1-byte label" case; see the
  `PROGRAM` section's compact-keycode notes) — so a checksum match is not
  proof the reading is right. Verify each occurrence against what's
  semantically plausible at that point in the program (does a branch make
  sense here, or a register/display exchange?) rather than assuming every
  instance in a listing resolves the same way.

## Where to look for related work

- Writing test/regression scenario files for XCUITest: see the
  `calc-u-59-uitesting` skill for file-picker navigation and verifying a
  loaded state.
- Building a new (non-Swift, non-Web) GUI that needs to parse this format:
  see `reference/NewGUIGuide.md`.
