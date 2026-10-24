# TI-59 ROM Guide

A narrative companion to the annotated listing `rom/TI59-commented.asm` and
the label table `rom/TI59-labels.asm`. The listing documents individual
instructions; this guide explains the structures and conventions that span
many routines. Everything here was derived by tracing the unmodified ROM on
the emulator with the headless harness (`tools/headless/`), unless marked
otherwise.

Emulator-side facts (instruction set, SCOM/PREG mechanics, chip variants)
live in `reference/CoreArchitecture.md`; this guide is about the firmware.
The TI-58C runs a revised ROM; its differences (constant memory, bug fixes,
self-test) are in `rom/TI58C-ROM-Guide.md`.

## Reproducing the traces

```bash
tools/headless/ti59.py 5 + 7 '*' 3 =        # annotated trace of each key
tools/headless/coverage.py build            # which scenario runs which ROM word
tools/headless/coverage.py show 0140 0236   # per-address scenario list
```

Every claim tagged "trace-confirmed" in the listing can be re-checked this
way. `tools/annotate_rom.py` applies comment batches to the listing.

## Control flow conventions

The TMC0501 has no call stack. The ROM builds one level of subroutine
linkage out of two 16-bit registers:

- **KR** holds a jump target in bits 15..4 (address = KR >> 4). `SET KR[1]`
  arms the computed jump (PREG); the CPU executes **one more instruction**
  (the delay slot) and then continues at the KR address captured when the
  `SET KR[1]` executed.
- **SR** is the parking place for a return address. `SWAP KR,SR` exchanges
  the two.

The standard return is the pair at `02D1/02D2`:

```
02D1  SET KR[1]     ; jump to KR >> 4 …
02D2  SWAP KR,SR    ; … after this delay slot, which swaps KR back
```

so whatever address sits in KR at `02D1` (normally the continuation fetched
from SR just before) is where execution resumes.

### Threaded operation sequences

Keyboard operations are not single routines but **runs of table slots**
(`0x00B1–0x010F`, see the listing header there). `KEY_OP_ENTRY` (`0141`)
puts `0x0C00 | code<<4` (plus `0x100` / `0x200` bank tags from `KR[8]`/`KR[9]`)
into KR and jumps; each slot is a `JC` to a subroutine, and the subroutine
returns to the *next* slot because `NORM_CALL` (`041C`, `INC KR` = +1 slot)
parks the incremented KR in SR. A typical sequence:

```
00D7  JC 041C   ; SUM: normalize X / finish number entry
00D8  JC 04CC   ; collect two register digits (suspends until typed)
00D9  JC 02D5   ; …
```

A sequence that needs more keystrokes (register numbers, label names) leaves
its resume slot in SR and drops back to the idle loop with **fB[12]** set;
the next digit keys are routed to the argument collector instead of number
entry (`KEY_DISPATCH` `06A7`), which resumes the sequence when complete.

The unary functions use a second table at `0x0500` (`FN_SEQ_TABLE`), entered
through `FN_ENTRY` (`0210`) with KR = `0x5000 | fn<<4` (`+0x100` for the
`KR[8]` variant). Example: `√x` → `0x0510` (normalize) → `0x0511` →
`JC 081D` → digit-by-digit square root at `0AAC`.

### Computed-jump tables

`SET KR[1]` jumps to KR >> 4, so each KR bit 4–15 contributes one address bit
(KR[4..7] = 0x001–0x008 … KR[8] = 0x010, KR[9] = 0x020, KR[10] = 0x040,
KR[11] = 0x080, KR[12] = 0x100, KR[13] = 0x200, KR[14] = 0x400,
KR[15] = 0x800). The ROM's dispatch tables are all built this way:

| Table | Address | Built by |
|---|---|---|
| keyboard | 0x0⟨col⟩⟨row⟩, 2nd: col + 5 | key decode, `06B1` |
| operation sequences | 0x00C0 + code (+0x10 KR[8], +0x20 KR[9]); 0x00B0 bank via `017F`/`0142`; 0x0100 bank via `0211` | `KEY_OP_ENTRY` `0141` |
| AOS execute | 0x00C0 + 2·precedence | `01BB–01C0` |
| function sequences | 0x0500 + code (+0x10/+0x20/+0x40) | `FN_ENTRY` `0210` |
| Op 00–19 | 0x0A00 + 16·tens + units | `0CB7` → `0F5C` |
| program bank (Ins/Del, labels, flags) | 0x0B10 + code | `0276` |
| compact keycodes | 0x0B20 + digit | `016F` |
| program scanner | 0x0E00 + 16·units + tens | `0F53–0F6D` |
| print mnemonics | 0x1000 + 32·tens + 3·units | `1432–1462` |
| character codes | depth into the INC KR slide 0x1399–0x13E5 | mnemonic table, `1422` |

## Number formats

**Entry format** (while digits are being typed): digits accumulate in A from
nibble 3 upward, with the decimal point position tracked separately; `5`
gives `A = 0000000000005000`.

**Normalized format** (after `NUM_NORM`, `0236`): mantissa left-aligned with
the most significant digit in nibble 15, decimal exponent in nibbles 2..1,
nibble 0 a flag/selector nibble. `5` → `A = 5000000000000000` (exponent 00);
`21` → `A = 210000000000001c` (exponent 01). The working copy carries
`0xC` in nibble 0 straight after normalization, which the AOS code reuses as
the SCOM row number 12/13 (`A=A+1 DPT1` → 13).

**Stored format** (SCOM levels, data registers): as normalized, with nibble
0 = flag bits: bit 1 = mantissa negative, bit 2 = exponent negative (the
same bits as fA[2]/fA[3]); in AOS levels bit 0 additionally holds the
pending operation's inverse-pair bit (see below).

## SCOM register map (as used by the firmware)

<table class="regmap">
<tr><th>Row</th><th>15</th><th>14</th><th>13</th><th>12</th><th>11</th><th>10</th><th>9</th><th>8</th><th>7</th><th>6</th><th>5</th><th>4</th><th>3</th><th>2</th><th>1</th><th>0</th></tr>
<tr><th>0</th><td colspan="5" align="center">user flags 0–9</td><td></td><td></td><td></td><td colspan="3" align="center">step: register (BCD)</td><td>step: byte</td><td>Prg Src</td><td colspan="2" align="center">pending keycode</td><td>Fix</td></tr>
<tr><th>1</th><td colspan="13" rowspan="8" align="center">mantissa<br>AOS pending operand · HIR register n<br>rows 5–8: Op 01–04 print buffer</td><td colspan="2" rowspan="8" align="center">exponent</td><td rowspan="8">signs</td></tr>
<tr><th>2</th></tr>
<tr><th>3</th></tr>
<tr><th>4</th></tr>
<tr><th>5</th></tr>
<tr><th>6</th></tr>
<tr><th>7</th></tr>
<tr><th>8</th></tr>
<tr><th>9</th><td>list data</td><td colspan="8"></td><td colspan="2" align="center">current page</td><td colspan="2" align="center">new page</td><td>security</td><td>RAM chips</td><td>partition ÷ 10</td></tr>
<tr><th>10</th><td colspan="14" align="center">next keycodes of the program register (shifted right; 00 enters at the top)</td><td colspan="2" align="center">current keycode</td></tr>
<tr><th>11</th><td colspan="16" align="center">t register</td></tr>
<tr><th>12</th><td colspan="14" align="center">AOS: older pending operators, 2 nibbles each, same layout</td><td>top: precedence</td><td>top: paren level</td></tr>
<tr><th>13</th><td>Pgm mark</td><td colspan="5"></td><td colspan="2" align="center">partition ÷ 10</td><td colspan="2"></td><td colspan="3" align="center">top RAM register</td><td>AOS depth</td><td>paren level</td><td>angle unit</td></tr>
<tr><th>14</th><td colspan="5" align="center">return level 6</td><td colspan="5" align="center">return level 5</td><td colspan="5" align="center">return level 4</td><td></td></tr>
<tr><th rowspan="2">15</th><td colspan="5" align="center">return level 3</td><td colspan="5" align="center">return level 2</td><td colspan="5" align="center">return level 1</td><td rowspan="2">depth</td></tr>
<tr><td colspan="10" align="center">(every level has the layout of level 1)</td><td colspan="4" align="center">position (BCD, LSD first)</td><td>source</td></tr>
</table>

Empty cells are not used, or their use is not known.

- **Row 0.** Fix = n + 2 (0 = floating). The pending keycode is an argument
  terminator, a second operand digit or the Ind of a compact code (fB[14]).
  Flag n is bit ⌊n/5⌋ of nibble 11 + (n mod 5). Prg Src: § "Program memory
  and execution".
- **Rows 1–8** use the stored number format (§ "Number formats").
- **Row 9:** `reference/CoreArchitecture.md` § "SCOM registers".
- **Row 12:** § "AOS".
- **Row 13.** Angle unit 0 = DEG, 1 = GRAD, 0xC = RAD. Top RAM register is
  the index of the highest RAM register (119 TI-59, 59 TI-58), set by the
  power-on probe. Pgm mark: § "Solid State library".
- **Rows 14–15:** `reference/CoreArchitecture.md` § "SCOM registers".

Rows 1–8 are shared: AOS levels, HIR registers and (5–8) the Op 01–04 print
buffer use the same storage, so deep pending arithmetic and alpha printing or
HIR use in the keycode programs can collide.

## Flags (fA / fB)

Meanings established so far; "set" means the bit is 1.

| Flag | Meaning |
|---|---|
| fA[0] | a label name follows (address operands, label search) |
| fA[1] | inverse-pair bit: subtract (−), divide (÷), root (INV y^x); during an AOS reduction it carries the popped entry's bit |
| fA[2] | X mantissa negative |
| fA[3] | X exponent negative |
| fA[4] | arithmetic overflow exit marker (`0418`) |
| fA[5] | a result is to be (re)formatted for display: NUM_NORM's exit runs DISP_FORMAT (`02CD`) |
| fA[6] | copy of fB[6] taken at the start of each key (`06A2`) |
| fA[7] | Ind pending (indirect register / address) |
| fA[8] | INV pending; also CP vs CMs, Del vs Ins, Op 18 vs 19 |
| fA[9] | 2nd pending (column bias +5 at dispatch); in register access: 1 = read (`02D9`), 0 = write (`04B1`) |
| fA[10] | printer trace record pending (`0A68`) |
| fA[11] | tan (trig sequence) |
| fA[12] | cos (trig sequence); sin↔cos role in the octant fold |
| fA[13] | operand-only mode: LRN is recording an operand (no register range check, `0B3D`/`0D4B`); Op 08 lists only label lines (`081B`/`1161`). Verified: `LRN STO 99` with 80 data registers is accepted; Op 08 prints `001 11 A` … |
| fA[14] | tolerate an over/underflow clamp without the error blink (`025A`) |
| fA[15] | exponent entry (after EE during number entry) |
| fB[0] | program running |
| fB[2], fB[3] | saved mantissa / exponent signs of the full-precision X in C (`02C6`, `0238`) |
| fB[4] | decimal point typed (number entry); kernel mode ln (1) / exp (0) in the transcendental kernel |
| fB[5] | a result (not an entry) is on display: X is in C, the next digit starts a new number |
| fB[6] | "fresh operand": set by every key at `06A3`, cleared by an AOS push and by `(`; an operator or `)`/`=` arriving with fA[6] clear is an error (`5 + =`, `5 + × 3`) |
| fB[7] | engineering display (Eng) |
| fB[8] | INV saved for a suspended operation sequence (`0234`): INV SUM, INV Prd, INV St flg, inverted conditionals |
| fB[9] | error: display blinks until CLR/CE (`0641`) |
| fB[10] | LRN mode (toggled at `03D8`); outside LRN borrowed as a transient prefix/reformat marker, cleared before idle |
| fB[11] | program-register cache (SCOM[10]) must be reloaded |
| fB[12] | argument entry in progress: digit keys feed a suspended operation sequence |
| fB[13] | single step (SST in run mode) |
| fB[14] | a keycode is pending in SCOM[0] nibbles 1–2 and is executed on the next pass (`0620` → `04F6`); Op 16: query only |
| fB[15] | scientific (EE) display |

## AOS (algebraic operating system)

Implemented at `0146–020A`; full register-level detail in the listing.

**What is kept where.** `2 × ( 3 + 4 yˣ` cannot be computed while it is
typed: each operator must wait until it is clear that nothing of higher
precedence follows. Every waiting operation is split in two halves:

- its **left operand** goes into SCOM[1]–[8], one row per level;
- its **operator** goes onto the operator stack in SCOM[12], as a 2-digit
  entry: precedence in the higher nibble, the paren level at the time of
  the push in the lower one. The newest entry is always in nibbles 1/0;
  each push shifts the row left by 2 nibbles and each pop shifts it right.

SCOM[13] nibble 2 (depth) counts the pending levels: entry k from the
bottom of SCOM[12] belongs to the operand in SCOM[k]. Nibble 1 is the
current paren level. The precedence names the operation only up to its
inverse: `+`/`−` are both 2, `×`/`÷` both 4, `yˣ`/INV `yˣ` both 6. Which
one is meant is the inverse-pair bit, stored in nibble 0 of the operand row.

The paren level in each entry is the fence that makes `(` work: a reduce
only pops entries whose level equals the current one, so `+` inside the
parenthesis never touches the `×` outside it.

Trace of `2 × ( 3 + 4 yˣ 2 ) =` (`tools/headless/ti59.py`):

| Key | SCOM[12] (low nibbles) | Operands | SCOM[13] nibbles 2/1 (depth, paren) |
|---|---|---|---|
| `×` | `40` | S1 = 2 | 1, 0 |
| `(` | `40` | | 1, 1 |
| `+` | `40 21` | S2 = 3 | 2, 1 |
| `yˣ` | `40 21 61` | S3 = 4 | 3, 1 |
| `)` | `40 21` → `40` (yˣ, then + run) | | 1, 0 |
| `=` | empty (× runs) | | 0, 0 |

`yˣ` with precedence 6 does not reduce the `+` below it (2 < 6), so both
wait. `)` brings precedence 1, lower than both, so it pops and runs them;
it stops at `40`, which belongs to paren level 0.

- Precedences: `+ −` 2, `× ÷` 4, `y^x` (and its INV root) 6; `)` arrives
  with 1 and `=` with 0.
- An operator push first **reduces**: while the top SCOM[12] entry was
  pushed at the current paren level and its precedence ≥ the incoming one,
  it is popped and executed through slot `0x00C0 + 2·precedence`
  (`00C4` ADD, `00C8` MULDIV, `00CC` y^x). Equal precedence reduces, so all
  operators are left-associative.
- Then the operator and the left operand X are pushed: X (with the
  operation's inverse-pair bit in nibble 0) into SCOM[depth+1], the entry
  `(precedence, paren level)` onto SCOM[12].
- `(` only increments the paren level. `)` reduces the current level and
  decrements it; `=` reduces with precedence 0 and repeats for every open
  level.
- Limits (verified): 8 pending levels (a 9th push sets the error flag at
  `01D1 → 04D0`), 9 open parentheses (the 10th errors at `0138`).
- An operator, `)` or `=` immediately after another operator is an error
  (fA[6] check at `0195` / `014B`).

## Arithmetic

- **ADD** (`0358`): A := B ± A. Operands are swapped until A has the larger
  exponent, B is shifted right by the difference, then magnitudes are added
  (sharing the multiply loop's carry tail at `0449`) or the smaller is
  subtracted from the larger. An exponent gap ≥ 100 leaves A unchanged.
- **MULDIV** (`03CC`): A := B × A or B ÷ A (fA[1]). Exponents add (division
  toggles the divisor's exponent sign first); the sign is the XOR.
  Multiplication is digit-serial shift-and-add; division is restoring
  repeated subtraction, 13 quotient digits. x ÷ 0 overflows to
  9.9999999 99 (blinking); 0 ÷ 0 gives a blinking 1.
- **ARITH_EXIT** (`0419`): the common tail — advance the continuation in SR
  to the next slot, normalize, return.

## Transcendental functions

All use the 16-entry constant ROM (read with `A=A+CON` etc., index in
`KR[4..6]` + `KR[8..11]`):

| Index | Value |
|---|---|
| 0 | ln 10 |
| 1–7 | ln(1 + 10⁻ᵏ), k = 0…6 (1 = ln 2) |
| 8–12 | atan(10⁻ᵏ), k = 0…4 (8 = π/4) |
| 13 | 1.5707963267950 E+01 (5π) — used as π/200 by flipping its exponent |
| 14 | π |
| 15 | 180/π |

- **ln** (`072A`, kernel `0730–075B`, ln mode fB[4]=1): Meggitt
  pseudo-multiplication. The mantissa m is multiplied by (1+10⁻ᵏ) for
  k = 0…6 as long as it stays below 10, adding ln(1+10⁻ᵏ) each time; then
  ln(10/m) ≈ Σ + (10 − m)/10 and ln x = (e+1)·ln 10 − ln(10/m) (`0B2A`).
- **eˣ** (`0703`): x = n·ln 10 + r; the kernel runs in exp mode (fB[4]=0),
  subtracting ln(1+10⁻ᵏ) from r while multiplying a product (from 1.0) by
  (1+10⁻ᵏ); finish ≈ ×(1+r) (`0AD3`); n becomes the decimal exponent.
- **log** = ln ÷ ln 10 (`0909`); **10ˣ** = eˣ after × ln 10 (`0605`);
  **yˣ** = e^(x·ln y) (slots `050C–050F`), the root (INV yˣ) divides by x.
- **√x** (`081D`, body `0AA8`): halve the exponent, then digit-by-digit
  subtraction of odd multiples.
- **sin/cos/tan** (slots `0523–0533`): convert to radians (`05D1`), reduce
  modulo 2π (÷2π, fraction, ×2π), fold into [0, π/4] (`08FA`, `0FD5`),
  compute tan θ with a decimal CORDIC (`08C7`: θ decomposed into
  atan(10⁻ᵏ) steps, each rotating (x, y) by x' = x − y·10⁻ᵏ,
  y' = y + x·10⁻ᵏ; tan = y/x), then sin = t/√(1+t²), cos = 1/√(1+t²).
  The arc functions run the CORDIC backwards and accumulate the angle
  (`0C95`), asin/acos first forming x/√(1−x²).
- **Angle unit**: SCOM[13] nibble 0 = 0 DEG, 1 GRAD, 0xC RAD (`05D1`).

## Memory registers

`STO/RCL/SUM/Prd/Exc nn` are sequences that suspend for two digits
(`04CC` → `022C`, fB[12]); the collector (`06C6`) shifts each digit into E
and resumes the sequence at `07AD`. `REG_ADDR` (`0D33`) maps Rnn to
RAM[top − nn] using SCOM[13] nibbles 3–5 (top = 119 on the TI-59) and
rejects registers inside the program partition. The RAM.OP bus word
carries the operation in nibble 0, the units digit in nibble 2 and a
*hexadecimal* tens nibble (0–B) in nibble 3, so registers 100–119 are
reached through an uncorrected ALU sum (`0DBE–0DC6`, `0CFB–0FFB`).
`Ind` sets fA[7]; the collected number is then first used to read the
pointer register.

## Display formatting

Two layers: the **entry display** (`02E2`) builds the control image for a
number being typed; **DISP_FORMAT** (`054C`) converts a result to the
display image in two passes (fB[5]): pass 1 picks fixed/sci/eng layout,
rounds at the first hidden digit and renormalizes; pass 2 lays it out
again and strips trailing zeros. Fix n is kept in SCOM[0] nibble 0 as
n + 2 (0 = floating); fB[15] = sci, fB[7] = eng.

## Program memory and execution

- **Step counter**: SCOM[0] nibbles 4–7 — nibble 4 = byte (0–7) within an
  8-step program register, nibbles 5–7 = register number (BCD). Nibble 3 =
  Prg Src Flag (0 RAM, 1 library module, 8 keycode sub-program in the
  constant ROM; all values and how the ROM tests them:
  `reference/CoreArchitecture.md` § "PRG SOURCE flag").
- **Keycodes** are two BCD digits row·10 + column (2nd functions: column + 5,
  so units 6–9/0); digit keys store their value 00–09 (`KEY_ENCODE` `0788`).
- **SCOM[10]** caches the current program register as a shift register: the
  current keycode is in nibbles 1..0 and each step within the register
  shifts it right by one keycode; fB[11] forces a reload from RAM
  (`PRGREG_FETCH` `08B2`).
- **LRN mode** (fB[10]): every key is routed to `LRN_KEY` (`099E`) instead of
  executing; editing keys act at once, others are encoded and stored
  (`LRN_STORE` `0D80`: read register, replace byte, write back, advance).
  In operand position any key is stored as its own keycode (`STO B` is
  recorded as 42 12, i.e. STO 12, and `GTO GTO` as 61 61). The exceptions are
  the editing keys SST, BST, Ins, Del and LRN, which act instead, and
  INV SBR, which merges into the compact RTN code 92. It is the only INV
  combination that merges; every other INV is recorded as a 22 step. All trace-checked by a
  prefix × key sweep in LRN mode.
- **Keycodes that keys cannot record** still execute if they get into
  program memory (via HIR, Ins on a stale cache, or a written card). All
  100 codes were run as a step (headless sweep, program "7 kc 1 2 R/S").
  LRN (31) stops the run in LRN mode at the following step. 2nd (21), INV
  without a function (22), Ind (40), SST (41), Ins (46), BST (51) and Del
  (56) do nothing, so the digits around them run together into "712".
  Codes with a hex digit: § "Pseudo-keycodes".
- **Execution**: while fB[0] is set the pre-idle checks enter `RUN_LOOP`
  (`07C1`), which polls R/S, fetches the next step and dispatches it through
  `STEP_DISPATCH` (`0837`) — the keycode is turned back into a matrix
  position and fed into the normal keystroke pipeline at `0689`, so a stored
  keycode behaves exactly like the key press.
- **Labels**: user keys A–E′ and SBR/GTO label search walk the program with
  the **program scanner table** at `0x0E10` (indexed 0x0E⟨units⟩⟨tens⟩ by
  keycode) to skip operand bytes, comparing the byte after each Lbl.
- **Subroutines**: SBR pushes a 5-nibble level (caller's Prg Src Flag, then
  register·10 + byte LSD-first) onto SCOM[15]/[14] (`0D50`); RTN (`1175`)
  pops it; a RTN with an empty stack ends the run (keyboard-started label).
  The stack holds six levels. A seventh SBR is not an error: the push is
  skipped (`0D57` → `0D79`), so the deepest RTN returns to the sixth level's
  caller and the code after the seventh call never runs. Trace-checked with a
  chain of SBRs, each adding a distinct value to R01 after its return.
- **Conditionals** (x=t, x≥t, If flg, Dsz) leave their result in fA[9];
  `COND_TRANSFER` (`0499`) applies INV and branches or skips the address.
  Dsz (`0715`) moves the register's magnitude one step toward zero, keeping
  its sign; a magnitude below 1 becomes 0. It transfers while the result is
  non-zero. Trace-checked: 3 → 2 and −2 → −1 transfer, 2.5 → 1.5 transfers,
  1 → 0 and 0.5 → 0 do not.
  x=t and x≥t compare the full 13-digit values, not the display. 1 ÷ 3 × 3
  shows 1 but is not equal to 1, and √2 squared is less than 2.
- **User flags**: flag n = bit ⌊n/5⌋ of SCOM[0] nibble 11 + (n mod 5)
  (`FLAG_OP` `15BA`).
  Flag 8 makes an error stop a running program (run loop `07E2`).
  Without it the program keeps running and the error only blinks once the
  program stops.
  Flag 9 traces like the printer's TRACE switch (`069D`, `05A4`, `1544`).

## Solid State library

- `Pgm nn` (`PGM_SELECT` `12E1`) reads the program count from module header
  byte 0 and rejects nn beyond it; from the keyboard nn becomes the current
  page in SCOM[9]. Inside a program it only marks SCOM[13] nibble 15. The
  next step must be a label key or SBR for the call to go to the module. Any
  other step clears the mark and runs normally (`0976`).
- Labels in a module program are found by `LIB_LABEL_SEARCH` (`1364`): the
  program's start/end come from the header (2 BCD bytes per program), and
  the bytes are walked through the same scanner as RAM programs.
- Execution fetches each keycode at `LIB_EXEC_ENTRY` (`082B`, LIB.HI) and
  `LIB_EXEC_FETCH` (`082F`, LIB.IN); the
  module's own address counter is the program counter (SCOM[0]'s step
  counter is not used).
- Source 2 exists in SCOM[0] only inside a RTN back into a module program.
  RTN writes the popped level at `1192`, and `LIB_RETURN` sets the source to
  1 at `1506`, 16 instructions later, before the next step is dispatched
  (trace-checked: ML Pgm 02, key C).

## Key polls while a program runs (trace-confirmed, not in the owner's manual)

- **R/S** (row 9, col 1) is polled between RAM program steps (`07DD`): held →
  stop.
- **GTO** (row 6, col 1) is polled there too (`07CF`): held → every second
  step lights the display for 256 idle-loop passes, ≈216 ms (`04E6`), so the
  running program's intermediate X values become visible. Suppressed when
  memory is protected (SCOM[9] nibble 2).
- **RST** (row 8, col 1) is polled on every library-module fetch (`0834`):
  held → the run stops and RST is performed.

## Fast mode

Fast mode is a RAM program running with a Prg Src Flag of 2, 4 or 6: non-zero,
so the run loop (`07C9`) takes the sub-program path (`08AE`), but neither
bit 0 (module) nor bit 3 (keycode table), so the step fetch reads RAM. What
it does, its rules and the entry recipes: `rom/fastmode.md`. This section
holds the ROM side.

Only 2, 4 and 6 work. Odd values fetch from the module, because bit 0 is
tested first, and 8 fetches from the keycode table; either way the RAM
program is lost (headless sweep of 0–9, SST entry with X = 1.00000000000N).

### Entry methods compared (headless traces)

Two independent bugs lead into fast mode.

**Family 1: the St flg mis-dispatch.** St flg's argument is cut short by a
non-digit key after exactly one digit. That key's `KEY_ENCODE` leaves a
column bit in KR, and St flg's continuation ORs into it and lands at `0B34`
instead of `0B14` (missing safeguard, see `0783`). The chain ends in the HIR
STO code (`11D9`) with register 0, so X's digit image lands in SCOM[0]. Only
column-2 keys work as the terminator (B, INV, x⇄t, STO, EE; every key
tested), and any digit works as the first one. The 12th decimal digit of X
becomes the source flag, nibbles 4–7 of its image the start step.

- **St flg at the end of the partition** (`examples/fastmode.ti59`, TI PPC
  Notes V9N3P5). Fetching the operand fails, the program halts with the
  argument pending, and the user presses 7 EE.
- **Acosta's "hi2"** (`examples/calendar-08-acosta.ti59`): RCL of the
  constant, St flg, then a pseudo-keycode `0C` as the operand, all inside the
  program. Its hex units digit feeds only the digit C and leaves the argument
  open, and the next step (68 Nop) ends it. The keyboard ritual (`Pgm 12 SBR
  999`, `R/S`, `D.MS`, `LRN Ins Ins`) only manufactures that `0C`, with the
  stale-cache Ins quirk known from `examples/texas-print.ti59`.
- **SST** (`examples/fastmode-sst.ti59`). SST leaves the operand pending
  because a program operand is fed as two digits. No partition-end halt and
  no pseudo-keycode are needed.
- **No program-only form without pseudo-keycodes.** A sweep of all 10,000
  `St flg kk kk` programs recordable in LRN found none that triggers it,
  because stored operands always arrive as two decimal digits.

**Family 2: LRN inside a module program** (Arendt / Meusch, `00000 Pgm 02 SBR
239 …`; `examples/FastMode_Zero4.ti59`, `examples/characters-fastmode.ti59`).
ML-02 step 239 is a byte 31, the LRN keycode. Executed there, it switches on
LRN mode while the module keeps running, so the module records its own
keycodes into RAM. One of them then dispatches into the cold-start clear loop
at `0005`, which writes register A into SCOM[0]: source 4.

**Dead ends checked:** `HIR 00` would be the direct route, but HIR accepts only
registers 1–8 (range check at `11C1`). `St flg Ind` with flag numbers above 9
and `Fix Ind` do not reach nibble 3.

### What a fast-mode program can do

The full list of what works, what breaks and how to end a program is in
`rom/fastmode.md` § "Rules for fast-mode programs" (measured with
`uv run python tools/agentic/fastmode_matrix.py`). All of it follows from
the seven places that test the Prg Src Flag. Only the step fetch tests single
bits; the other six ask only "non-zero?", so there a fast-mode program counts
as a keycode sub-program or a library program:

| Site | Test | Effect in fast mode |
|---|---|---|
| `07C5`–`07C9` RUN_LOOP | ≠ 0 → `08AE` | No R/S poll, no GTO "peek" poll, and no error stop under flag 8 (`07E0`–`07E9`). This is where the speed comes from. |
| `054F`–`0553` DISP_FORMAT | ≠ 0 → `08A1` | X is not formatted for the display after a step. The trace-print check (`05A8`) is inside the formatter, so nothing is traced. |
| `08B2`–`08B8`, `0B8F` PRGREG_FETCH | bit 0, bit 3 | 2, 4 and 6 fetch from RAM, so the program itself runs. |
| `0860` → `0BD2` LABEL_SEARCH | ≠ 0 → `0FAD` | Labels are searched in the selected module program, not in RAM. |
| `0A4B`–`0A57` launch prologue | caller ≠ 0 → `0DA7` | Every call pushes the module's address counter as the return address, as for a library caller. The launch also clears the source, so the subroutine itself runs in normal mode. |
| `1191`, `14F9`–`1506` RTN_POP / LIB_RETURN | library level popped | The return reloads the module PC and sets source 1, so execution continues in the module. |
| `06B9`–`06C5` key epilogue | ≠ 0 → `08AE` | After an operation, the program keeps running even when fB[0] is clear: an INV SBR with an empty stack ends the run (`1195`) but the program carries on, and after a program R/S any operation key resumes it. |

**The hang.** RST clears the source flag; a program R/S leaves it set. Both
redisplay X. If X holds a computed value that fast mode never formatted, the
digit layout loops forever in `030A`–`030E`: dark display, no key works. X
in digit entry, 0, or a value just formatted by Pause or Prt is safe.

## Magnetic cards

`Write` (bank number in X) and an inserted card (idle-loop card-switch poll)
both enter the card sequence; fB[8] selects read. A bank is 246 bytes:
three header bytes (partition ÷ 10, "bank lies entirely in program memory",
3·(bank−1), each with high nibble 1), a protect byte, 30 registers × 8 bytes,
and a mod-16 nibble checksum in byte 244. See `0x1680` in the listing.

All trace-confirmed with the headless harness:

- **Read** (card inserted with no bank number given): any bank is accepted,
  but the card's partition must equal the current one. On a mismatch the
  card runs through unread and the display blinks; the calculator never
  repartitions itself. The checksum is checked after the registers are
  stored, so a bad checksum leaves the data in RAM and blinks. Afterwards X
  shows the bank number.
- **Write in a program** waits for the card and then the program goes on
  ("1 Write 5 R/S" writes bank 1 and stops showing 5). An invalid bank
  number (0 or more than 4) sets the error but still waits for a card or
  R/S, and lets the card pass unread.
- **n INV Write**: read, but only a card whose header is exactly bank n's.
  Any other card is refused.
- **Protection**: `−n Write` sets the protect byte to 1. Reading such a card
  sets SCOM[9] nibble 2. From then on LRN is refused and writing a bank that
  lies entirely in program memory errors (`16A4`), while banks that are only
  partly or not at all program memory stay writable. The bank shows as
  negative. Protected memory also turns off List (`0D2E`), Op 08, trace
  printing (both the TRACE switch and flag 9, `068E`) and the GTO display
  peek (`07D2`), and Op 17 silently acts as Op 16 (`1558`; `2 Op 17` keeps
  479.59). CP clears the protection.

## Printing

The PC-100 is driven one character at a time (PRT.OUT with a 6-bit code in
KR[4..9], filled right to left), PRT.GO prints the line, TST.BUSY paces it.

- **Mnemonics**: every keycode has a 3-character mnemonic in the table at
  `0x1000–0x1151` (slot 0x1000 + 32·tens + 3·units, rightmost character
  first), produced through the INC KR character slide at `0x1399`.
- **Values** (`PRT_VALUE` `152B`): digits from the display image as code
  digit+1, point = 32, minus = 16; with TRACE the key's mnemonic is queued
  first (`1422`) and printed with the result.
- **List** (`0D28`): per step the LRN-style fetch, the scanner (so operands
  print as numbers), the mnemonic table and the digits.
- **INV List** (`0F6E`): the data registers from Int(X) up to the last one
  in the data partition, each printed as "value nn". The register number
  is held in SCOM[0] nibbles 1–2 while the list runs. R/S held stops it,
  and X is restored at the end.
- **Trace mode**: an operand gets a line of its own with leading zeros
  suppressed (`STO 01` → "1"), and an Ind operand is marked "*" (`15E4`).
  An overflowed or error value is printed with "?" after it (`162B`).
- **Alphanumeric** (Op 00–05): a 20-column buffer in SCOM[5]–[8]; the TI
  two-digit character codes map to printer codes as tens·8 + units. Op 06
  prints X with Op 04's characters, Op 07 plots an asterisk at column X.
- **Printer interrupt**: a manufactured keycode 1F jumps into the print
  routine just before PRT.GO and cuts the line in progress short
  (`rom/printerinterrupt.md`).
- **Adv** feeds two lines and keeps feeding while Adv or the printer's ADV
  button is held (`0F36`).

## Keycode sub-programs

Statistics (Σ+, x̄, σ, Op 11–15), P→R / R→P and D.MS are not ROM routines but
TI-59 *programs* in the constant ROM (rows 16–63, 384 steps), run with Prg
Src Flag 8. Listing with entry points: `rom/TI59-keycode-programs.asm`.
They use the HIR (hierarchy register) keycode 82 for scratch storage and the
statistics registers R01–R06.
They also use AOS levels themselves, so the launch (`0A40`) refuses to start
one when five or more AOS levels are already pending: "1 + ( 2 × ( 3 + ( 4 ×
( 5 + ( 3 Σ+" blinks, while the same keys one level shallower work
(trace-checked for Σ+, D.MS, P→R and Op 11).

## HIR and compact keycodes

Keycodes at a digit key's matrix position (92, 82–84, 72–74, 62–64) are not
digits — digits are stored as 00–09 — but compact codes, dispatched by the
digit through bank `0x0B20`: 92 RTN, 82 HIR, and the Ind forms GO*, OP*,
ST*, RC*, SM*, PG*, EX*, PD*. **HIR nm** (programs only) operates on
hierarchy register m = SCOM[m] (1–8, the AOS level rows): n = 0 STO, 1 RCL,
3 SUM, 4 Prd, 5 INV SUM, 6 INV Prd (verified). The keycode ROM programs use
HIR as scratch storage.

The Ind forms come from LRN mode (`0D82`): when the operand after Ind is
complete, an STO, RCL, SUM, Exc, Prd, Pgm, GTO or Op step recorded just
before Ind is rewritten as 72, 73, 74, 63, 64, 62, 83 or 84 and the step
counter moves back over it. Every other op keeps Ind as a step of its own
(keycode 40): `Fix Ind 02` is 58 40 02 and `SBR Ind 22` is 71 40 22.

## Pseudo-keycodes

The units digit of step 8k is digit 0 of its program register, where the
CPU computes in hexadecimal. Ins on a stale step buffer can leave A–F there
(`rom/printerinterrupt.md` § "How the code is made"). TI PPC Notes called
these "hex keycodes" and took them for internal instructions (Patrick
Acosta, V6N9/10 p14–15; Dejan Ristanovic, V7N6 p8; summary at
https://www.ti59.com/accom.htm). They are not instructions. To execute a
step, and to skip it during a label search, the firmware builds computed
jumps from its two digits and never checks them, so a hex digit sends the
jump to an address built for something else. What runs there is a fragment
of another operation, working on whatever its registers hold.

The articles name a code by its display, which adds the hex digit
decimally: code tU shows as (t+1)(U−10) (1F as 25 = "h25", 9E as 04 =
"h04").

All results come from a headless sweep of the 60 codes (tens 0–9, units
A–F) at step 000, followed by R/S steps, on the TI-59 and the TI-58C, with
the printer attached, TRACE off and on. Ins makes the codes only at step
8k, and position matters: h54 below works at steps 008 and 016 and does
nothing visible at the steps in between.

**Where a code goes.**

- **Tens 0** (0A–0F): `STEP_DISPATCH` treats it as a digit (`0846` →
  number entry `04D3`). Label searches skip it like any digit step.
- **Tens 1** (1A–1F): row 1 holds the label keys, so the step calls a label
  (`KEY_USERDEF` `02D2`, return pushed at `0D50`). No label has the name, so
  the search (`0F45`) walks on until it reaches the code itself. There the
  scanner's own computed jump (`0F53–0F6D`, slot 0x0E⟨units⟩⟨tens⟩) lands
  past its table: 1F at `0EF1` is the printer interrupt
  (`rom/printerinterrupt.md`), 1E goes to `0EE1`.
- **Tens 2–9**: `STEP_DISPATCH` (`0837–0855`) makes the code a keyboard
  position, row = tens and column = units, and `06B1` jumps to
  0x00⟨column⟩⟨row⟩ (§ "Computed-jump tables"). Column A is the column that
  units 0 already uses (the 2nd functions of the fifth key column), so tA
  runs as t0. Columns B–F land in the operation-sequence table, in the
  middle of other operations' slot runs:

| Tens | B | C | D | E | F |
|---|---|---|---|---|---|
| 2 | `00B2` trig: sin | `00C2` + − push ✱ | `00D2` ) ✱ | `00E2` Prd: read register | `00F2` GTO: transfer |
| 3 | `00B3` trig: sin | `00C3` + − push: AOS_PUSH | `00D3` ): reduce | `00E3` Prd: × ÷ | `00F3` Dsz ✱ |
| 4 | `00B4` trig: sin | `00C4` reduce: ADD | `00D4` Fix ✱ | `00E4` Prd: store back | `00F4` Dsz: collect digit |
| 5 | `00B5` trig: function code left in R5 | `00C5` reduce loop | `00D5` Fix: collect digit | `00E5` Exc ✱ | `00F5` Dsz: read register |
| 6 | `00B6` If flg ✱ | `00C6` × ÷ push ✱ | `00D6` Fix: set | `00E6` Exc: collect register | `00F6` Dsz: decrement |
| 7 | `00B7` If flg: collect digit | `00C7` × ÷ push: AOS_PUSH | `00D7` SUM ✱ | `00E7` Exc: read register | `00F7` Dsz: write back |
| 8 | `00B8` If flg: test | `00C8` reduce: MULDIV | `00D8` SUM: collect register | `00E8` Exc: swap | `00F8` Dsz: zero test |
| 9 | `00B9` If flg: transfer | `00C9` reduce loop | `00D9` SUM: read register | `00E9` = ✱ | `00F9` Dsz: transfer |

**After the landing.** For a real key the dispatch leaves 0x0100 in SR, the
return to `KEY_RET` (`06A9–06AC`), and its delay slot sets KR to 0 (`06B2`).
A slot whose routine is `NORM_CALL` (`041C`) parks KR + 1 as the
continuation, and with KR = 0 that is address `0001`: the run falls into
the cold-start clear (`0001–000E`), which zeroes every SCOM row, and then
into `POWERON_SETUP`. These are the nine codes marked ✱. They clear the
display, t, EE and Eng, the AOS levels and HIR registers, the user flags and
the return stack, then stop at step 000. Program memory stays. On the TI-59
the partition goes back to 479.59 because it lives in SCOM (719.29 before
in the sweep); the TI-58C keeps its partition. A fragment that returns
through SR ends as a key would, in `KEY_OP_ENTRY` (`0141`) with whatever op
code is left in R5, so it can run on into a second operation: 3E and 7E
continue as RCL nn (`00DC`) and take the next two steps as its register.

**Trace mode.** With TRACE on, a step passes the print gate (`0689`) twice.
The first pass encodes it for the print record (`KEY_ENCODE` `0788`), and
the step is then dispatched from that encoding. `KEY_ENCODE` knows only the
ten real columns, so a code with tens 2–9 is first folded into an ordinary
keycode, which then runs exactly as that keycode:

- tA, tB, tE and tF run as t0;
- tC runs as (t+1)2 and tD as (t+1)3 (9C and 9D become the digits 2 and 3).
  Of the tens-1 codes, 1C and 1D fold the same way, into INV and lnx.

The printed mnemonic does not follow the fold: 4D prints EE but runs "("
(53), 5C prints OSS and runs Pg\* (62), 6D prints \*ST and runs RC\* (73), 7C
prints \*GT and runs HIR (82).

**Label search.** A units digit A–F also sends the program scanner past its
table (0x0E⟨units⟩⟨tens⟩ lies beyond `0E99`). That is Acosta's rule that
hex codes stop label searches. In the sweep (code at 000, Lbl A at 001, key
A) the search still found the label for 0A–0F, and by chance for 3B, 3C,
4B, 4C, 4E, 5C, 8E and 9A; it lost it for every other code.

**The articles against the sweep.** Acosta's results are from a TI-58C (he
says so for the clear codes). Ristanovic worked with the printer attached
and does not name the model.

| Claim | Code | Where it lands, and the result |
|---|---|---|
| Acosta: h04 h32 h33 h45 h53 h64 h71 h72 h83 clear everything, go to step 000 and stop; Ristanovic: h53, h64 all clear | the ✱ codes | cold start, as above. The scan prints h45 as "nes". Acosta expected h04 might clear the program on a TI-58/59; on the TI-59 it keeps the program and resets the partition. |
| Acosta: h31 h41 h51 act as sin | 2B 3B 4B | `00B2–00B4`, the trig run after its INV test |
| Acosta: h54 copies t into the display right after x⇄t, pending operations kept | 4E | `00E4`, Prd's store-back. At step 8k only; `2 + 7 x⇄t h54 =` gives 9 on the TI-58C, 2 on the TI-59 |
| Acosta: h24 reads the next seven steps one digit out of step, so 8 steps hold 15 | 1E | TI-58C only: the scanner's `0EE1` leads into the step-buffer code there (TI-58C `0C0B`), and `1E 10 20 30 10 09 91` enters the digits 123. On the TI-59, `0EE1` runs other code. |
| Acosta: codes ending in A do nothing new (`examples/repartition.ti58c`); Ristanovic: h00 acts as List | tA, 9A | tA runs as t0; 9A is List (90) |
| Acosta: all hex codes except h10–h15 disable label search | | mostly; see "Label search" |
| Acosta: h11 as the operand of RCL, Fix, St flg, GTO, SBR, Dsz or x=t also runs SBR A | 0B | not checked |
| Ristanovic: h44 acts as ln(0) | 3E | `00E3`, Prd's × ÷ on leftover operands; overflows to −9.9999999 99 |
| Ristanovic: h84 and h85 act as a strange RCL | 7E 7F | 7E: Exc's register read (`00E7`), then RCL nn; 7F: Dsz's write-back (`00F7`) |
| Ristanovic: h94 enters EE 12 | 8E | `00E8`, Exc's swap with a leftover register; no EE in the sweep |
| Ristanovic: h93 needs a five-digit address and acts as a decimal point under SST | 8D | `00D8`, SUM's operand collector: the digits after it become an operand. It acts as "." (93) in Trace, but not under SST. |
| Ristanovic, Trace: h64 \|x\|, h84 and h85 Rad, h94 Grad, h44 tan, h75 Deg, h53 EE; h62 OSS, h82 \*GT, h73 \*ST (prints a register) | 5E 7E 7F 8E 3E 6F 4D 5C 7C 6D | the Trace fold; h53, h62, h82 and h73 are what the printer shows (see "Trace mode") |
| Ristanovic: `h75 16` jumps to Lbl A′ in Trace mode only | 6F | Normal: Dsz's tail, whose conditional transfer takes 16 as its address and does not jump. Trace: 6F is Deg (60) and 16 is an ordinary A′ call. `Lbl A′ 7 R/S` at 000 and `6F 16 5 R/S` at 008, run from 008, stop with 5 normally and with 7 in Trace. |

## Error conditions

Every error sets fB[9]; the idle loop then blinks the display (`0641`) until
CLR or CE (`03B0`, `03BA`). A running program stops (fB[0] cleared) only where
noted. Sites (all in the listing):

| Address | Condition |
|---|---|
| `0138` | tenth open parenthesis |
| `014F` | `)` or `=` directly after an operator |
| `04CF/04D0` | operator after operator; ninth pending AOS level |
| `025C` | over/underflow clamp (unless fA[14]) — x÷0, overflowing results |
| `03D4` | 0 ÷ 0 (result 1) |
| `072F`, `0A0C` | ln of a negative number (continues with \|x\|) / of zero |
| `0820` | √ of a negative number (continues with \|x\|) |
| `094F` | Op 40–99 |
| `0B0A` | transfer target outside program memory (GTO 999, …) |
| `0F21` | program ran past the end of the partition (stops) |
| `11E8` | library transfer out of range (stops, return stack reset) |
| `141C` | Pgm number beyond the module (stops) |
| `1484` | Op 09: module protected or program too long |
| `15E2` | Op 07 column outside 0–19 |
| `16E9`, `1798` | card header/checksum mismatch, card aborted |
| `17EF` | Op 17 more data registers than RAM |
| `0A47` | keycode sub-program (Σ+, P→R, D.MS, Op 11–15, …) with five or more AOS levels pending |
| `07E2` | (not an error site) an error while running stops the program only if flag 8 is set |
| `16A5` | Write of a bank lying entirely in program memory while memory is protected |
| `17A5` → `16E9` | card recorded under another partition; with `n INV Write`, a card other than bank n |
| `17AA` | Write with bank 0 or above 4 (still waits for a card) |

## Execution cost

Active (non-idle) instructions from key acceptance to the next idle loop,
measured with the headless harness, including display formatting; the
millisecond column assumes the TI-59's ≈14.2 k instructions/s
(455 kHz ÷ 2 ÷ 16, see `reference/CoreArchitecture.md`).

| Operation | Instructions | ≈ ms |
|---|---|---|
| digit key | 144 | 10 |
| 5 + 3 = (the =) | 658 | 46 |
| 3 x² | 636 | 45 |
| 1/4 | 764 | 54 |
| 5 × 3 = | 834 | 59 |
| √2 | 956 | 67 |
| 5 ÷ 3 = | 1010 | 71 |
| e² | 1403 | 99 |
| ln 2 | 1531 | 108 |
| log 2 | 1899 | 134 |
| tan 45° | 2204 | 155 |
| 2 yˣ 3 = | 2370 | 167 |
| asin .5 | 3404 | 240 |
| sin 30° | 5100 | 359 |
| D.MS | 11393 | 802 |
| Σ+ | 11712 | 825 |
| P→R | 16892 | 1190 |

The last three are keycode sub-programs interpreted step by step, which is
why they are an order of magnitude slower than the native functions.
