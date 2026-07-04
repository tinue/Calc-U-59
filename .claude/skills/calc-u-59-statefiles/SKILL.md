---
name: calc-u-59-statefiles
description: Use this skill when writing or editing .ti59 / .ti58 / .ti58c state files, including KEYSTROKES sequences, PROGRAM listings, and screenshot-automation scenario files. Covers the file format, the matrix-code vs. keycode distinction, and the 2nd-function lookup table.
user-invocable: true
---

# Calc-U-59 State File Format

State files are plain UTF-8 text (`.ti59`, `.ti58`, `.ti58c`). The authoritative parser is `App/StateFileLoader.swift`; this skill is a human-friendly reference.

---

## Sections

| Keyword | Purpose |
|---------|---------|
| `PARTITION: nnn` | Last visible step (display shows nnn). Total steps = nnn+1, rounded up to multiple of 80. Default: 479 (480 steps). |
| `PROGRAM:` | Program listing. Accepts bare keycodes, step-prefixed keycodes, or printer-trace format (mnemonics ignored). |
| `REGISTERS:` | `NN = value` lines. NN = 00–99; TI-58C only: `HNN` for hidden regs 00–03. |
| `KEYSTROKES:` | Physical key presses to inject after load. Uses **matrix codes**, not keycodes (see below). |
| `SOLID-STATE-MODULE: ID` | Load a module. IDs: ML ST RE SY NG AV **LE** SA BD MU EE SE AG RP |
| `PRINTER: on` | Connect the printer. Values: `on` / `off` / `true` / `false` / `1` / `0` |
| `SKIP-RESET: on` | Skip machine reset; apply only non-destructive sections (see below). |
| `CUECARD:` | Custom cue-card content (template + fields). |

Lines starting with `#` are comments. Inline `#` comments are also stripped.

---

## KEYSTROKES vs. PROGRAM: two different numbering systems

This is the most important distinction when writing state files.

| | PROGRAM section | KEYSTROKES section |
|-|----------------|--------------------|
| What it is | Keycodes stored in program RAM | Physical key-matrix scan codes |
| Number format | 0–99 (the ROM's internal encoding) | 11–95 (row × 10 + col) |
| Example: digit 0 | keycode `00` | matrix code `92` |
| Example: digit 1 | keycode `01` | matrix code `82` |
| Example: SBR | keycode `71` | matrix code `71` (same for this key) |
| Example: 2nd Pgm | keycode `36` (PGM, stored as one step) | matrix codes `21 31` (two physical presses) |

**Rule:** the KEYSTROKES section simulates a user's fingers. Always use matrix codes there, never keycodes.

---

## Matrix Code Table — KEYSTROKES

Matrix code = **row × 10 + col**, row 1–9 top to bottom, col 1–5 left to right.

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

Pressing **2nd (21)** then a key activates that key's 2nd (upper-label) function. In KEYSTROKES, always send **two** matrix codes: `21` then the key's matrix code. The resulting program keycode is listed for reference.

The rule: **2nd keycode = matrix\_code + 5** for cols 1–4; **matrix\_code − 5** for col 5. This applies to every row, using the *matrix code* (not the primary keycode — these differ for digit and operator keys).

| 2nd press sequence | 2nd function | Prog keycode |
|--------------------|--------------|-------------|
| `21 11` | A' | 16 |
| `21 12` | B' | 17 |
| `21 13` | C' | 18 |
| `21 14` | D' | 19 |
| `21 15` | E' | 10 |
| `21 23` | log | 28 |
| `21 24` | CP (clear pending) | 29 |
| `21 25` | CLR | 20 |
| `21 31` | **Pgm** (program select) | 36 |
| `21 32` | P→R (polar to rectangular) | 37 |
| `21 33` | sin | 38 |
| `21 34` | cos | 39 |
| `21 35` | tan | 30 |
| `21 41` | Ins (insert step) | 46 |
| `21 42` | CMs (clear memories) | 47 |
| `21 43` | Exc (exchange) | 48 |
| `21 44` | Prd (product) | 49 |
| `21 45` | IND (indirect) | 40 |
| `21 51` | Del (delete step) | 56 |
| `21 52` | Eng (engineering notation) | 57 |
| `21 53` | Fix | 58 |
| `21 54` | Int (integer part) | 59 |
| `21 55` | \|x\| (absolute value) | 50 |
| `21 61` | Pause | 66 |
| `21 62` | x=t (equality test) | 67 |
| `21 63` | Nop | 68 |
| `21 64` | Op | 69 |
| `21 65` | Deg | 60 |
| `21 71` | Lbl | 76 |
| `21 72` | GE (≥) | 77 |
| `21 73` | Σ+ | 78 |
| `21 74` | x̄ (mean) | 79 |
| `21 75` | Rad | 70 |
| `21 81` | St flg (set flag) | 86 |
| `21 82` | If flg (if flag) | 87 |
| `21 83` | D.MS (deg/min/sec) | 88 |
| `21 84` | **π** | 89 |
| `21 85` | Grad | 80 |
| `21 91` | Write | 96 |
| `21 92` | Dsz | 97 |
| `21 93` | Adv (printer advance) | 98 |
| `21 94` | Prt (printer print) | 99 |
| `21 95` | List (print program listing) | 90 |

---

## Compact / Shortcut Keycodes (PROGRAM section only)

Digit keys store their face value in program memory (pressing "2" stores keycode `2`, not `83`). This frees up the matrix-code-like slots (62–64, 72–74, 82–84, 92) for the ROM to use as compact single-step encodings of multi-key operations.

These are **only relevant in the PROGRAM section**. In KEYSTROKES you must always use the physical multi-key press sequence.

| Keycode | Mnemonic | Physical keypress sequence (KEYSTROKES) | Notes |
|---------|----------|-----------------------------------------|-------|
| `62` | PG\* (Pgm Ind) | `21 31` `21 45` | Pgm with indirect register |
| `63` | EX\* (Exc Ind) | `21 43` `21 45` | Exc with indirect register |
| `64` | PD\* (Prd Ind) | `21 44` `21 45` | Prd with indirect register |
| `72` | ST\* (STO Ind) | `42` `21 45` | STO with indirect register |
| `73` | RC\* (RCL Ind) | `43` `21 45` | RCL with indirect register |
| `74` | SM\* (SUM Ind) | `44` `21 45` | SUM with indirect register |
| `82` | HIR | — | Undocumented; cannot be entered via keypresses |
| `83` | GO\* (GTO Ind) | `61` `21 45` | GTO with indirect register |
| `84` | OP\* (Op Ind) | `21 64` `21 45` | Op (2nd+9) with indirect register |
| `92` | RTN | `22 71` | INV SBR; saves one program step vs storing INV + SBR separately |

All indirect codes (`62–64`, `72–74`, `83–84`) take one additional operand byte (the register number) — see `stepsAfterTable` in `TI59KeyNames.swift`.

The IND key itself is entered as **`21 45`** (2nd + y^x).

---

## KEYSTROKES Syntax

```
# One matrix code per token. Text tokens (mnemonics) are silently ignored.
# Each line is one key press (press + release). 500 ms gap between presses.

21 31       # 2nd Pgm  (select program mode)
92          # 0
82          # 1        → Pgm 01 selected
71          # SBR
95          # =        → run program 01

# Explicit wait:
Wait: 2s
Wait: 500ms
```

---

## Common Sequences (ready to paste)

```
# 2nd Pgm 01 SBR =   (select and run program 01)
21 31
92
82
71
95

# π × 4 =
21 84
65
72
95

# SBR =   (continue/re-enter a program)
71
95

# CLR
25

# 2nd P/R  (toggle program/run mode)
21 32
```

---

## `Wait:` and `WaitFullSpeed:` Timing

- Default gap between presses: 500 ms (450 ms hold + 50 ms gap, hardcoded in `EmulatorViewModel.playKeystrokes`)
- `Wait: Xs` / `Wait: Xms` — pause for the given interval; emulator runs at its configured speed
- `WaitFullSpeed: Xs` / `WaitFullSpeed: Xms` — enable full speed (`isFullSpeedMode = true`) for the given interval, then restore the previous speed; use this after a key that starts a computation so the program finishes quickly without affecting key-press timing

```
71          # SBR
95          # =    → program starts
WaitFullSpeed: 5s   # run flat-out until program reaches input prompt
21 84       # π    → next key sent at normal speed
```

---

## `Trace:` — Scripted CPU Trace Capture

Starts or stops a binary CPU instruction trace (same format as the manual "C"
indicator button — see `reference/DebugAPI.md`), independent of that button
and of any other `Trace:` session. Written under the configured trace
directory (Settings → trace location: Local / iCloud / Custom).

- `Trace: <filename>` — starts a fresh capture to `<filename>`, silently
  overwriting an existing file of that name. The filename is the entire
  trimmed remainder of the line, taken verbatim (spaces allowed, no
  whitespace splitting) — it must not contain `/` or `\`. Opening a new
  file while one is already open first closes the previous one cleanly.
- `Trace: Off` — stops the current scripted capture, if any.
- Any capture still open when the KEYSTROKES sequence ends is closed
  automatically.
- Each `Trace: <filename>` gets its own full size budget (Settings → max
  trace file size); usage does not carry over between files.

```
Trace: LrnCheck.bin
83  2
72  4
91  R/S
Wait: 5s
Trace: Off
```

**Not the same thing as** the `99` virtual key below — that toggles the
*emulated printer's* own TRACE latch (a calculator feature, printed on
paper); `Trace:` here is a debugging/CPU-instruction capture to a file on
disk, unrelated to the printer.

---

## Special Virtual Keys in KEYSTROKES

Matrix code `99` is outside the valid key grid (rows 1–9, cols 1–5 give max code 95) and is repurposed as a virtual button:

| Code | Action |
|------|--------|
| `99` | Toggle printer TRACE latch (each press flips on→off or off→on) |

---

## SKIP-RESET

`SKIP-RESET: on` skips the machine reset that normally occurs when a state file is loaded. Use it for files that only inject keystrokes into a running machine (e.g. the second step of a multi-file screenshot sequence).

**Applied sections** (work without a reset):

| Section | Behaviour |
|---------|-----------|
| `PARTITION:` | Updated in SCOM only if explicitly specified; otherwise left as-is |
| `PROGRAM:` | Full zero-padded write (replaces existing program) |
| `REGISTERS:` | Listed registers are written individually |
| `CUECARD:` | Cue card is replaced if present |
| `KEYSTROKES:` | Played normally |

**Silently dropped sections** (require a reset — a `[WARN]` is printed to the console):

| Section | Why dropped |
|---------|------------|
| `MODEL:` | Model switch requires full machine reset |
| `SOLID-STATE-MODULE:` | Module load requires full machine reset |
| `PRINTER:` | Printer connection change requires full machine reset |

---

## KEYSTROKES Does Not Support

- FREEZE / FREEZE ON START (debug panel — must be driven by XCUITest)
