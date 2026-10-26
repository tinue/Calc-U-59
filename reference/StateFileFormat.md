# `.ti59` / `.ti58` / `.ti58c` State File Format

> **Provenance notice.** This document was consolidated by an AI (Claude)
> from the parser, the `calc-u-59-statefiles` skill and an earlier section
> of `reference/DebugAPI.md`. The parser is `Shared/StateFile.cpp`, shared
> by the Swift and Qt6 apps and the web client; where they disagree, the
> code wins.

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
| `CARD: mem:name` … `END-CARD` | An in-memory magnetic card, see "CARD" |
| `SOLID-STATE-MODULE: ID` | Insert a module: `ML ST RE SY NG AV LE SA BD MU EE SE AG RP` (`roms/solid-state/cuecards.txt`). Without the line the current module stays |
| `PRINTER: on` | Connect the printer: `on`, `true` or `1`; anything else disconnects it. Without the line the printer setting stays |

- Keywords are case-insensitive. `PROGRAM:`, `REGISTERS:`, `KEYSTROKES:`,
  `CUECARD:`, `PARTITION:` and `CARD:` end the current section; lines after
  `PARTITION:` are ignored until the next section keyword. `MODEL:`,
  `SOLID-STATE-MODULE:` and `PRINTER:` may stand anywhere,
  even inside a section.
- `PROGRAM:`, `REGISTERS:`, `CUECARD:` and `PARTITION:` after a
  `KEYSTROKES:` section are a reload, played in turn ("Reloads").
- `SKIP-RESET:` (up to 2.1: load into the running machine) is an error: put
  the second file's sections after the first file's `KEYSTROKES:`. The file
  loads with a reset.
- `#` starts a comment, anywhere on a line. A value therefore cannot
  contain `#`, not even a cue-card title or a trace file name.
- Errors (unknown model, bad register value, bad `Trace:` line, unknown
  KEYSTROKES directive, `Wait:` without a unit) are shown after parsing;
  the load goes on without the bad line.

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
- **Gap marker:** a line that is exactly `...` is skipped; the steps it
  stands for stay 00 until the next step number.
- Steps not listed are 00. The program is written zero-padded to the
  model's physical capacity, not to the partition. A reload is different:
  it writes only the steps it lists ("Reloads").

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
  TI-58/58C, and lines for 60–99 are silently ignored there.
- **`HNN = value`, NN = 00–03, TI-58C only:** the 4 extra RAM cells beyond
  the 60 registers, reachable only by `MEMWR`/`MEMRD`. They are not
  registers 60–63 (`CoreArchitecture.md` § "TI-58C Extra (Constant Memory)
  Registers"). They are an error unless the file loads into a TI-58C (its
  `MODEL:`, or the current model); the file extension doesn't matter.
- The value is a decimal literal (exponent allowed). Integers are stored
  digit for digit, anything else rounded to 13 significant digits
  (`cu59::encodeBcd`, `Shared/Bcd.hpp`).
- Registers not listed are zero. `PROGRAM:` and `REGISTERS:` are written
  as given, registers after the program: some listings deliberately put
  registers in the program area or steps in the data area
  (`examples/calendar/calendar-05-vanderburgh.ti59`).

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

Every token of 1–2 digits is one press and release: 11–95 a key (a code
with no key, such as 16, presses nothing but still takes a press's time);
other numbers and words are ignored, so a line can carry a comment-like
mnemonic. 99, up to 2.1 a virtual key that toggled the printer's TRACE, is
an error: use `PrinterTrace:`. `21 31` on one line is two presses. A line
that starts with `Word:` is a directive (below), never keys; an unknown
one is an error.

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
(`Shared/KeySequencer`). While the debugger is frozen, keys, reloads and
`InsertCard:` wait until it runs again (a key pressed into a frozen machine
would be lost); directives go on, so `Step:` and `Resume:` work.

**Directives** (one per line, case-insensitive):

| Directive | Effect |
|---|---|
| `Wait: 2s`, `Wait: 500ms` | Pause, for the user to see something; the calculator runs at its current speed. The unit is required |
| `FullSpeed:` / `RegularSpeed:` | Switch speed until the other one or the end of the script |
| `Trace: <name>` | Start a binary CPU trace to `<name>` in the trace folder (format: `DebugAPI.md` § "Trace File Format") |
| `Trace: Off` | Stop it |
| `ZeroElapseTime:` | Take the core's elapsed-time counter (`elapsedTicks()`) as the baseline |
| `ReportElapseTime:` | Log `Elapsed: m:ss.mmm` since the baseline (or reset) to the LOG tab |
| `ArmCard: <card>` | Queue a card for the next card wait of `Write` / `INV Write`, see "Cards in KEYSTROKES" |
| `InsertCard: <card>` | Insert a card once the calculator is idle; playback waits until it has passed |
| `PrinterTrace: on` / `off`, `CutPaper:`, `DebugPanel:`, `Freeze:`, `FreezeOnStart:`, `Step:`, `Resume:` | The GUI's controls, see "Controls" |

- `Trace:` takes the rest of the line as the file name, spaces included;
  `/` and `\` are errors. An existing file is overwritten. A new `Trace:`
  closes the previous one; each file gets the full size limit from
  Settings. The trace runs independently of the manual trace button.
- **Full speed for a program run:** put `FullSpeed:` before the key that
  starts it. Playback waits on that key until the program stops, so the
  whole run is at full speed; speed returns to regular at the end of the
  script, or at a `RegularSpeed:` after the key. (`WaitFullSpeed:` existed
  until 2.1.0; it started only after the program had stopped and is now
  an error.)
- When the script ends, speed returns to regular and an open `Trace:` file
  is closed.
- **Adv (`21 93`) needs `RegularSpeed:`.** Adv repeats while held, gated by
  a CPU-step countdown, not real time: at full speed one 100 ms press feeds
  many lines. `Prt` (`21 94`) is unaffected.
- A new load's KEYSTROKES queue behind a script still playing. A model
  switch or Reset cancels playback.

```
ZeroElapseTime:
FullSpeed:
71 95       # SBR =  → timed run
RegularSpeed:
ReportElapseTime:
```

---

## Controls

A script can operate the controls around the calculator, at the point in
the script where they stand: the printer's TRACE switch, the paper, and the
debugger's buttons. Before 2.2, a screenshot sequence needed a UI test to
press them between two files. Playback waits until each control has taken
effect.

| Directive | Same as |
|---|---|
| `PrinterTrace: on` / `off` | Setting the PC-100's TRACE switch (the paper trace, not a CPU trace) |
| `CutPaper:` | Cutting the printer paper |
| `DebugPanel: Calculator` / `CPU` / `Log` | Clicking that tab of the debugger. On a paged layout (iPhone portrait) the page stays where it is; the web client without a debugger remembers it |
| `Freeze: Calculator` / `CPU` | That panel's FREEZE (ignored if frozen already) |
| `FreezeOnStart: Calculator` / `CPU` | That panel's FREEZE ON START: CALCULATOR freezes before the next program step, CPU when the keyboard scan loop exits |
| `FreezeOnStart: Off` | Disarm both |
| `Step: Calculator` / `CPU` [n] | That panel's STEP, n times (default 1): a keycode or an instruction. Ignored, with a LOG line, unless frozen |
| `Resume:` | RESUME |

```
KEYSTROKES:
PrinterTrace: on
21 84 65 72 95          # π × 4 = — traced on the paper
PrinterTrace: off
DebugPanel: Calculator
FreezeOnStart: Calculator
71 95                   # SBR =: the debugger freezes at the program's first step
```

- The freeze directives name their panel. They don't depend on the tab
  shown, which is the GUI's (`Platform::showDebugPanel`).
- After a freeze, keys wait until the machine runs again: a `Resume:`, or
  the user's RESUME. `Step:` and `Resume:` work while frozen. A script
  that ends frozen stays frozen.
- Example: `examples/screentest/test_cdebug.ti59`, the debugger screenshot
  of the UI tests.

---

## Reloads

A reload is the user **keying in changes between runs**: they load a
program and registers, run it, change a few steps and registers by hand,
and run it again. `KEYSTROKES:` could do the same through LRN and STO, but
`PROGRAM:` and `REGISTERS:` are easier to read. Reloads work on every model.

`PROGRAM:`, `REGISTERS:`, `CUECARD:` and `PARTITION:` sections before the
first `KEYSTROKES:` section are the load itself. After a `KEYSTROKES:`
section they are a **reload**. Consecutive ones form one reload, and a
further `KEYSTROKES:` section continues the script after it.

```
PROGRAM:             # the load, as usual
…
KEYSTROKES:
11                   # A: the program runs and stops
PROGRAM:             # reload: applied once it has stopped
017 01               # step 017 becomes 1; every other step stays
REGISTERS:
05 = 2.5             # R05 changes; every other register stays
KEYSTROKES:
11                   # A: run again
```

- Playback reaches the reload and waits for the scan loop, as a key would.
  It then writes the partition (if given) and **only the listed steps and
  registers**. Everything else keeps its contents: steps not listed, a
  `...` gap, the other registers. This is unlike a card, which replaces a
  whole bank ("CARD").
- A `CUECARD:` replaces the card shown.
- A reload's `PROGRAM:` starts at step 000 again.
- A reload's partition above the model's last step is skipped, with a line
  in the LOG tab.
- `MODEL:`, `SOLID-STATE-MODULE:` and `PRINTER:` belong to the whole file,
  wherever they stand.
- Example: `examples/historic/fast-grafik-3d-plot.ti59`. Part 2 is a reload after
  part 1 stops. Up to 2.1 it was two files, the second loaded with
  `SKIP-RESET`, which reloads replace.

---

## CARD

Cards are the workflow for **anything larger than a few keyed-in changes**.
A TI-59 user prepared a stack of cards in advance, together with a written
sequence. They read the first cards (say, four banks) and started the
program. They then fed each further card when the calculator asked for it:

- **The program stops** (R/S), perhaps with a hint in the display, and the
  user pushes the next card in, then presses R/S or a label key. The preset
  writes this as `InsertCard:` after the key that runs up to the stop.
- **The program asks for a card without stopping:** `n Write` or
  `n INV Write` in the program waits for a card. Users learnt to recognise
  this from the display (the blink pattern). The preset writes this as an
  `ArmCard:` before the run. The card goes in as soon as the program waits.

Choosing the right card stays the preset's responsibility, as it was the
user's. The calculator checks only what its ROM checks: the partition on an
idle read, and the bank number on `n INV Write`. A card is named in one of
two ways:

| Name | Card |
|---|---|
| `mem:Scratch` (prefix in any case) | In-memory: built from a `CARD:` block, or blank. A bank written to it is kept and read back by the next use. It is never saved to a file |
| `Results` / `Results.U59` | The card file in the card folder (Swift: iCloud or Documents; Qt: the card folder in Settings; web: the session's cards). `.U59` is added when there is no extension. A missing file goes in as a blank card, so a `Write` creates it |

A `CARD:` block is one prepared card side, defined in the preset. It is an
in-memory card, may stand anywhere in the file, and ends at `END-CARD`:

```
CARD: mem:MyVars
Bank: 3              # required, 1–4
Protected: no        # optional: yes / no (or on / off); written as −n Write
Partition: 479.59    # optional header; default: the calculator's when the card goes in
REGISTERS:           # R30–R59: bank 3
30 = 1.5
31 = 2.25
PROGRAM:             # steps 480–719: bare keycodes start at 480
…
CUECARD:             # shown when the card goes in, like a card file's
Template: MagnetCard
Title: My Vars
END-CARD
```

- **A card replaces its whole bank.** Steps and registers the block doesn't
  list are read as 00. Bank n holds raw RAM registers 30·(n−1)…+29: program
  steps 240·(n−1)…+239, and data registers 120 − 30·n … 149 − 30·n
  (bank 4 = R00–R29, bank 3 = R30–R59, bank 2 = R60–R89, bank 1 =
  R90–R99). Contents outside the bank are an error and left out.
- The bank is built as the ROM writes it, header and checksum included
  (`buildCardBank`, `Shared/CardFile.hpp`; bank format:
  `rom/TI59-ROM-Guide.md` § "Magnetic cards").
- The header's partition must equal the calculator's when the card is read
  without a bank number (an idle insert). That is why it defaults to the
  partition at insert time.
- Errors: a `CARD:` name without `mem:` (card files are used by name,
  never defined here), a missing or wrong `Bank:`, a missing `END-CARD`,
  the same name twice (the last counts).

### Feeding cards: ArmCard and InsertCard

```
KEYSTROKES:
InsertCard: mem:Bank1    # the prepared stack: read banks 1–4 at idle …
InsertCard: mem:Bank2
InsertCard: mem:Bank3
InsertCard: mem:Bank4
ArmCard: mem:MyVars      # … the program's 3 INV Write will ask for this one
ArmCard: mem:Scratch     # blank: the program's 4 Write fills it …
ArmCard: mem:Scratch     # … and 4 INV Write reads it back
11                       # A: run until the program stops
InsertCard: Results      # it stopped for the next card: Results.U59
91                       # R/S: go on
```

- **`InsertCard:`** is the user pushing a card into a stopped calculator.
  It waits for the scan loop and inserts the card. The ROM reads it as a
  manual insert, partition check included. Playback goes on only after the
  card has passed.
- **`ArmCard:`** is a card laid ready for the program's `Write` /
  `INV Write`. It queues the card and playback goes on at once. When the
  CPU is in the card wait (0x16B2–0x16B7) and the reader is empty, the
  controller feeds the first armed card. The idle loop polls the card
  switch too, so the PC tells the two apart. A bank the program writes goes
  to the memory card or the card file.
- Armed cards are used in order, and so are inserted cards. The two
  queues don't hold each other up: an armed card nobody asks for doesn't
  block an `InsertCard`.
- Queued and memory cards last until the next full load, reset or model
  switch, not just to the end of the script. A `Write` keyed in last, or a
  run the user starts later, still gets its card. A card never fed is
  logged then.
- TI-59 only. On the TI-58/58C, `CARD:`, `ArmCard:` and `InsertCard:` are an
  error and the directives are dropped. Reloads work on all models.

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

## What a load does

In this order (code: `SessionController::loadStateFile`,
`Shared/StateApplier.cpp`):

1. `MODEL:` switches the machine if it names another model.
2. Reset, then 300,000 steps for the ROM's power-on routine.
3. The partition (or the model's default).
4. RAM cleared, except the TI-58C's extra registers (the ROM needs H00).
5. The program, then the registers.
6. The loop restarts and the printer paper is cut. Then
   `SOLID-STATE-MODULE:`, `PRINTER:` and `CUECARD:` (no `CUECARD:` clears
   the user's card). The TI-58C saves its memory.
7. `KEYSTROKES:` play, with any reloads and cards in between. A full load
   first drops the previous preset's queued and memory cards.
