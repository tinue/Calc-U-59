# `.ti59` / `.ti58` / `.ti58c` State File Format

> **Provenance notice.** This document was consolidated by an AI (Claude)
> from the parser, the `calc-u-59-statefiles` skill and an earlier section
> of `reference/DebugAPI.md`. The parser is `Shared/StateFile.cpp`, shared
> by the Swift and Qt6 apps; where they disagree, the code wins.

A state file (a "preset" in the GUI) is UTF-8 text that sets the
calculator's state: program, data registers, module, printer, cue card,
and a key sequence to play after the load. How the apps apply one:
`SharedArchitecture.md` § "State File Loading". For using the example files,
point readers at the user guide, https://calc-u.org/59/.

---

## Sections and directives

| Line | Meaning |
|---|---|
| `MODEL: TI-59` | Load into `TI-59`, `TI-58` or `TI-58C` (any case); the app switches model first. An unknown value is an error |
| `PARTITION: nnn[.xx]` | Program/data split, see below |
| `PROGRAM:` | Program steps, see below |
| `REGISTERS:` | Data registers, see below |
| `KEYSTROKES:` | Keys and directives played after the load, see below |
| `CUECARD:` | The user's cue card, see "CUECARD: Field Grammar" |
| `SOLID-STATE-MODULE: ID` | Insert a module: `ML ST RE SY NG AV LE SA BD MU EE SE AG RP` (`roms/solid-state/cuecards.txt`) |
| `PRINTER: on` | Connect the printer: `on`, `true` or `1`; anything else disconnects it |
| `SKIP-RESET: on` | Load without a reset, see "SKIP-RESET" |

- Keywords are case-insensitive. `PROGRAM:`, `REGISTERS:`, `KEYSTROKES:`,
  `CUECARD:` and `PARTITION:` end the current section; lines after
  `PARTITION:` are ignored until the next section keyword. `MODEL:`,
  `SOLID-STATE-MODULE:`, `PRINTER:` and `SKIP-RESET:` may stand anywhere,
  even inside a section.
- `#` starts a comment, anywhere on a line. A value therefore cannot
  contain `#`, not even a cue-card title or a trace file name.
- Errors (unknown model, bad register value, bad `Trace:` line) are shown
  after parsing; the load goes on without the bad line.

---

## PARTITION

- The number before the dot is the last step; steps = number + 1.
- Steps are rounded up to a multiple of 80 (10 program registers), at most
  960.
- The `.xx` suffix (e.g. `479.59`) documents the register count and is
  ignored.
- **Default when omitted:** TI-59 479 (480 steps, 60 data registers);
  TI-58/58C 239.
- A value above the model's last step (479 on the TI-58/58C) aborts the
  load.

---

## PROGRAM

Each line is one of two notations:

```
PROGRAM:
76 11 42 00              # bare keycodes, any number per line
000 43 RCL               # step number, keycode, then an optional label
001 00 00
110 42 STO               # a step number moves the position: 002–109 stay 00
```

- **Bare keycodes:** every token of 1–2 digits with a value 0–99 is a
  keycode; other tokens (mnemonics) are skipped.
- **Step-numbered:** a first token of 3 or more characters that is a step
  number (0 up to the model's last physical step, 959 or 479) sets the
  position. The next token is the one keycode; anything after it is a
  label, even a number (`473 00 0`).
- Steps not listed are 00. The program is written zero-padded to the
  model's physical capacity, not to the partition.

---

## REGISTERS

```
REGISTERS:
00 = 3.141592653589793
05 = -1.5e-3
H01 = 7.77E22
```

- **`NN = value`, NN = 00–99:** the `STO`/`RCL` register number. All of
  00–99 are ordinary registers on the TI-59; only 00–59 exist on the
  TI-58/58C.
- **`HNN = value`, NN = 00–03, TI-58C only:** the 4 extra RAM cells beyond
  the 60 registers, reachable only by `MEMWR`/`MEMRD`. They are not
  registers 60–63 (`CoreArchitecture.md` § "TI-58C Extra (Constant Memory)
  Registers"). In a `.ti59` or `.ti58` file this is an error.
- The value is a decimal literal (exponent allowed). Integers are stored
  digit for digit, anything else rounded to 13 significant digits
  (`cu59::encodeBcd`, `Shared/Bcd.hpp`).
- Registers not listed are zero. `PROGRAM:` and `REGISTERS:` are written
  as given, registers after the program: some listings deliberately put
  registers in the program area or steps in the data area
  (`examples/calendar-05-vanderburgh.ti59`).

### Print-code register values

Some programs store text for the PC-100 printer: a register holds up to
five 2-digit character codes (`Op 01`–`Op 04`). Each code is a `row col`
pair in an 8×8 grid, character index `row × 8 + col` (`PRN_CODE[64]` in
`Core/TMC0501.cpp`). `3013351523` → 30 13 35 15 23 → `MARCH`.

```
     col 0  1  2  3  4  5  6  7
row 0    (sp) 0  1  2  3  4  5  6
row 1     7  8  9  A  B  C  D  E
row 2     -  F  G  H  I  J  K  L
row 3     M  N  O  P  Q  R  S  T
row 4     .  U  V  W  X  Y  Z  +
row 5     x  *  √  π  e  (  )  ,
row 6     ↑  %  ⇄  /  =  '  ˣ  x̄
row 7     ²  ?  ÷  !  Ⅱ  ▴  ∏  ∑
```

A value with fewer than five characters has fewer digits; keep it as
printed.

---

## KEYSTROKES vs. PROGRAM: two different numbering systems

| | PROGRAM | KEYSTROKES |
|-|---|---|
| What it is | Keycodes stored in program RAM | Physical key-matrix codes |
| Range | 00–99 | 11–95 (row × 10 + col) |
| Digit 0 | `00` | `92` |
| Digit 1 | `01` | `82` |
| SBR | `71` | `71` (same for this key) |
| 2nd Pgm | `36` (one step) | `21 31` (two presses) |

KEYSTROKES simulates fingers: always matrix codes, never keycodes.

---

## Matrix Code Table — KEYSTROKES

Matrix code = **row × 10 + col**, row 1–9 top to bottom, col 1–5 left to
right (`Shared/KeyMatrix.hpp`).

```
         Col 1   Col 2   Col 3   Col 4   Col 5
Row 1:   A(11)   B(12)   C(13)   D(14)   E(15)
Row 2:   2nd(21) INV(22) lnx(23) CE(24)  CLR(25)
Row 3:   LRN(31) x⇔t(32) x²(33)  √x(34)  1/x(35)
Row 4:   SST(41) STO(42) RCL(43) SUM(44) yˣ(45)
Row 5:   BST(51) EE(52)  ((53)   )(54)   ÷(55)
Row 6:   GTO(61) 7(62)   8(63)   9(64)   ×(65)
Row 7:   SBR(71) 4(72)   5(73)   6(74)   -(75)
Row 8:   RST(81) 1(82)   2(83)   3(84)   +(85)
Row 9:   R/S(91) 0(92)   .(93)   +/-(94) =(95)
```

---

## 2nd Function Table

A 2nd function is two presses: `21`, then the key's matrix code. The
program keycode it stores is the matrix code + 5 for columns 1–4, − 5 for
column 5.

| Presses | Function | Keycode |
|---|---|---|
| `21 11` … `21 14` | A' … D' | 16 … 19 |
| `21 15` | E' | 10 |
| `21 23` | log | 28 |
| `21 24` | CP | 29 |
| `21 25` | CLR | 20 |
| `21 31` | Pgm | 36 |
| `21 32` | P→R | 37 |
| `21 33` | sin | 38 |
| `21 34` | cos | 39 |
| `21 35` | tan | 30 |
| `21 41` | Ins | 46 |
| `21 42` | CMs | 47 |
| `21 43` | Exc | 48 |
| `21 44` | Prd | 49 |
| `21 45` | Ind | 40 |
| `21 51` | Del | 56 |
| `21 52` | Eng | 57 |
| `21 53` | Fix | 58 |
| `21 54` | Int | 59 |
| `21 55` | \|x\| | 50 |
| `21 61` | Pause | 66 |
| `21 62` | x=t | 67 |
| `21 63` | Nop | 68 |
| `21 64` | Op | 69 |
| `21 65` | Deg | 60 |
| `21 71` | Lbl | 76 |
| `21 72` | x≥t | 77 |
| `21 73` | Σ+ | 78 |
| `21 74` | x̄ | 79 |
| `21 75` | Rad | 70 |
| `21 81` | St flg | 86 |
| `21 82` | If flg | 87 |
| `21 83` | D.MS | 88 |
| `21 84` | π | 89 |
| `21 85` | Grad | 80 |
| `21 91` | Write | 96 |
| `21 92` | Dsz | 97 |
| `21 93` | Adv | 98 |
| `21 94` | Prt | 99 |
| `21 95` | List | 90 |

---

## Merged Keycodes (PROGRAM only)

Digit keys store their face value (`2` stores `02`, not `83`). The free
codes hold single-step forms of two-key operations. In KEYSTROKES, press
the keys.

| Keycode | Mnemonic | KEYSTROKES | Meaning |
|---|---|---|---|
| `62` | PG\* | `21 31 21 45` | Pgm Ind |
| `63` | EX\* | `21 43 21 45` | Exc Ind |
| `64` | PD\* | `21 44 21 45` | Prd Ind |
| `72` | ST\* | `42 21 45` | STO Ind |
| `73` | RC\* | `43 21 45` | RCL Ind |
| `74` | SM\* | `44 21 45` | SUM Ind |
| `83` | GO\* | `61 21 45` | GTO Ind |
| `84` | OP\* | `21 64 21 45` | Op Ind |
| `92` | RTN | `22 71` | INV SBR |
| `82` | HIR | — | Undocumented; no key sequence enters it |

Each of these except RTN takes one operand step (the register number).
Operand rules: `stepsAfter()` and `argumentSteps()` in `Shared/KeyNames.cpp`.

---

## KEYSTROKES Syntax

Every token of 1–2 digits is one press and release: 11–95 a key, 99 the
virtual key below; other numbers and words are ignored, so a line can
carry a comment-like mnemonic. `21 31` on one line is two presses.

```
KEYSTROKES:
21 31       # 2nd Pgm
92 82       # 0 1
71 95       # SBR =    → Pgm 01, label =
Wait: 2s
21 84 65 72 95   # π × 4 =
```

**Timing.** Each key is held 100 ms, then playback waits until the CPU is
back in the keyboard scan loop, so no key is lost to a busy calculator
(`Shared/KeySequencer`). While the debugger is frozen it doesn't wait.

**Directives** (one per line, case-insensitive):

| Directive | Effect |
|---|---|
| `Wait: 2s`, `Wait: 500ms` | Pause; the calculator runs at its current speed. The unit is required |
| `WaitFullSpeed: 5s` | Full speed for the interval, then the previous speed. Use it after a key that starts a long computation |
| `FullSpeed:` / `RegularSpeed:` | Switch speed until the other one or the end of the script |
| `Trace: <name>` | Start a binary CPU trace to `<name>` in the trace folder (format: `DebugAPI.md` § "Trace File Format") |
| `Trace: Off` | Stop it |
| `ZeroElapseTime:` | Take the core's elapsed-time counter (`elapsedTicks()`) as the baseline |
| `ReportElapseTime:` | Log `Elapsed: m:ss.mmm` since the baseline (or reset) to the LOG tab |

- `Trace:` takes the rest of the line as the file name, spaces included;
  `/` and `\` are errors. An existing file is overwritten. A new `Trace:`
  closes the previous one; each file gets the full size limit from
  Settings. The trace runs independently of the manual trace button.
- When the script ends, speed returns to regular and an open `Trace:` file
  is closed.
- **Adv (`21 93`) needs `RegularSpeed:`.** Adv repeats while held, gated by
  a CPU-step countdown, not real time: at full speed one 100 ms press feeds
  many lines. `Prt` (`21 94`) is unaffected.
- **Virtual key 99** toggles the printer's TRACE latch (paper trace), not a
  CPU trace.
- A new load's KEYSTROKES queue behind a script still playing. A model
  switch or Reset cancels playback.
- KEYSTROKES cannot freeze the debugger; a UI test has to press FREEZE.

```
ZeroElapseTime:
FullSpeed:
71 95       # SBR =  → timed run
RegularSpeed:
ReportElapseTime:
```

---

## CUECARD: Field Grammar

`Key: value` lines until the next section keyword. Keys are
case-insensitive; unknown keys are ignored (`CueCardContent::parseLine`,
`Shared/CueCard.cpp`). How the fields are drawn: `SharedArchitecture.md`
§ "Cue Card Rendering".

| Key | Applies to | Meaning |
|---|---|---|
| `Template` | all | `CueCard` (default), `MagnetCard` or `SolidStateCard`, exact case |
| `Title` | all | Headline |
| `Banks` | MagnetCard | `left, right` page badges, e.g. `Banks: 1, 2`; either may be blank |
| `ID` | SolidStateCard | Module/program ID right of the title, e.g. `ML-01` |
| `Row1` | all | Text in place of the A′–E′ label row |
| `Row2`, `Row2R` | all | Text in place of the A–E label row; `Row2R` is right of `Row2` on the same line |
| `Row1Align` | all | `left`, `center` (default) or `right` |
| `Row2Align`, `Row2RAlign` | all | `left` (default), `center` or `right` |
| `Style` | all | `none` (default) or `button` (a box around the row text) |
| `PencilColor` | CueCard, MagnetCard | `black` (default), `pencil` or `sharpie`, for the whole card. SolidStateCard always prints gold |
| `A` … `E` | all | Labels of the A–E row |
| `A'` … `E'` (or `A′` … `E′`) | all | Labels of the A′–E′ row |

A label row shows only when its `Row` text is empty. A label `\blank` is an
empty cell that the preceding label spans into; plain empty cells don't
span. `IDAlign` is accepted and ignored.

```
CUECARD:
Template: SolidStateCard
Title: DETERMINANT, MATRIX, & SIMUL. EQ.
ID: ML-02
Row1: i: \to x_{i} | \to A^{-1}
```

### Math notation

`Title`, `ID`, the rows and every label expand tokens: Greek letters,
overlined variables such as `\xbar`, arrows, `\sqrt`, `\sum`, `\integral`,
and `^{…}` / `_{…}` super- and subscripts. The table is `kMathTokens` in
`Shared/CueCard.cpp`.

---

## SKIP-RESET

`SKIP-RESET: on` loads into the running machine without a reset, e.g. the
second file of a multi-file screenshot sequence.

| Section | Under SKIP-RESET |
|---|---|
| `PARTITION:` | Set only if given |
| `PROGRAM:` | Written (zero-padded) only if it has steps |
| `REGISTERS:` | The listed registers are written |
| `CUECARD:` | Replaces the card if present |
| `KEYSTROKES:` | Played |
| `MODEL:`, `SOLID-STATE-MODULE:`, `PRINTER:` | Ignored, with a line in the LOG tab |

---

## What a load does

Without `SKIP-RESET`, in this order (code: `SessionController::loadStateFile`,
`Shared/StateApplier.cpp`):

1. `MODEL:` switches the machine if it names another model.
2. Reset, then 300,000 steps for the ROM's power-on routine.
3. The partition (or the model's default).
4. RAM cleared, except the TI-58C's extra registers (the ROM needs H00).
5. The program, then the registers.
6. The loop restarts and the printer paper is cut. Then
   `SOLID-STATE-MODULE:`, `PRINTER:` and `CUECARD:` (no `CUECARD:` clears
   the user's card). The TI-58C saves its memory.
7. `KEYSTROKES:` play.
