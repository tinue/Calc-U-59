# TI-59 ROM Guide

A narrative companion to the annotated listing `rom/TI59-commented.asm` and
the label table `rom/TI59-labels.asm`. The listing documents individual
instructions; this guide explains the structures and conventions that span
many routines. Everything here was derived by tracing the unmodified ROM on
the emulator with the headless harness (`tools/headless/`), unless marked
otherwise.

Emulator-side facts (instruction set, SCOM/PREG mechanics, chip variants)
live in `reference/CoreArchitecture.md`; this guide is about the firmware.

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

| Row | Use |
|---|---|
| 0 | nibble 0 = Fix setting (n+2, 0 = floating); nibbles 1–2 = pending keycode (argument terminator, second operand digit, Ind of a compact code; fB[14]); nibble 3 = Prg Src Flag; nibbles 4–7 = program step (nibble 4 = byte 0–7, nibbles 5–7 = BCD register number); nibbles 11–15 = user flags (flag n = bit ⌊n/5⌋ of nibble 11 + n mod 5) |
| 1–8 | AOS pending left operands, one per level; also the HIR hierarchy registers 1–8, and rows 5–8 hold the Op 01–04 print buffer |
| 9 | library/partition descriptor (see `reference/CoreArchitecture.md`) |
| 10 | current program register as a keycode shift register (current keycode in nibbles 1..0) |
| 11 | t register |
| 12 | AOS operator stack: 2 nibbles per entry (precedence, paren level), top entry in nibbles 1/0 |
| 13 | nibble 0 = angle unit (0 DEG, 1 GRAD, 0xC RAD); nibble 1 = current paren level; nibble 2 = AOS depth; nibbles 3–5 = index of the top RAM register (119 TI-59, 59 TI-58), set by the power-on probe; nibbles 8–9 = program partition ÷ 10 |
| 14, 15 | subroutine return stack (6 levels; SCOM[15] nibble 0 = depth) |

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
  Prg Src Flag (0 RAM, 1 library module, 2 return into a library program,
  8 keycode sub-program in the constant ROM; 2/4/6 on a RAM program = fast
  mode, see below).
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
- Execution fetches each keycode at `LIB_EXEC_FETCH` (`082B`/`082F`); the
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
  step lights the display for ≈256 cycles (`04E6`), so the running program's
  intermediate X values become visible. Suppressed when a module security
  code is set.
- **RST** (row 8, col 1) is polled on every library-module fetch (`0834`):
  held → the run stops and RST is performed.

## Fast mode

The TI PPC "fast mode" is a RAM program running with a non-zero Prg Src Flag
that selects neither the library (bit 0) nor the keycode table (bit 3) —
2, 4 or 6. The run loop (`07C9`) then takes the sub-program path (`08AE`) and
skips the per-step display rebuild and R/S/GTO polls: ~40% less time, but R/S
cannot stop it. The only way in is a quirk chain that writes X's digit image
into SCOM[0] (an argument terminated by EE after `St flg` at the end of the
partition, mis-dispatched twice, ending in the HIR STO code at `11D9` with
register 0, i.e. SCOM[0]). The 12th decimal digit of X becomes the source
flag, the digits after it the start step. Full walkthrough: `examples/fastmode.ti59`.

**Designed or accidental?** Both, in different parts.

- **The fast path is designed.** It exists for the ROM's own sub-programs:
  the keycode programs in the constant ROM (source 8: Σ+, x̄, P→R, D.MS,
  Op 11–15) and module programs (source 1). A built-in "function" such as
  P→R is 20–40 keycode steps internally, and the fast path makes it look
  like a single operation, with no display flicker in between.
- **Getting a RAM program onto that path is an accident.** The two tests on
  the source flag disagree. The run loop asks only "non-zero?", while the
  step fetch tests single bits (bit 0 → module, bit 3 → constant ROM), so 2,
  4 and 6 fall through to an ordinary RAM fetch. The only way to put such a
  value into SCOM[0] is the bug chain above: EE's `KEY_ENCODE` leaves a
  column bit in KR, and St flg's continuation ORs into it and lands at
  `0B34` instead of `0B14` (missing safeguard, see `0783`).

**Not meant for end users.** Fast mode is not in TI's owner's manual; TI-59
users found it and published it (the example cites TI PPC Notes V9N3P5). It
is also fragile:

- Only 2, 4 and 6 are fast mode. Odd values (1, 3, 5, 7, 9) fetch from the
  module, because bit 0 is tested first, and 8 fetches from the constant-ROM
  table. The run loses its RAM program either way (headless sweep of 0–9,
  SST entry with X = 1.00000000000N).
- X's digits also overwrite the step counter, the Fix setting, the
  pending-key field and the user flags (the example ends with flag 4 set).
  Digit-to-flag mapping, and the `Pgm 02 SBR 239` variant that takes the
  flags from steps 013–015: `rom/fastmode.md` § "What entry does to the
  flags and Fix".
- Labels, subroutines and the built-in keycode sub-programs do not work, and
  stopping can hang the calculator. See "What a fast-mode program can do"
  below.

It is a hobbyist technique built on a firmware bug, not a TI feature.

### Entry methods compared (headless traces)

Two independent bugs lead into fast mode.

**Family 1: the St flg mis-dispatch.** St flg's argument is cut short by a
non-digit key after exactly one digit. That key's KEY_ENCODE column bit bends
the continuation to `0B34`, and the chain ends in the HIR STO code (`11D9`)
with register 0, so X's digit image lands in SCOM[0]. Only column-2 keys work
as the terminator (B, INV, x⇄t, STO, EE; every key tested), and any digit
works as the first one. X must carry 2, 4 or 6 as its 12th decimal; nibbles
4–7 of its image become the start step. `1 + 2 EE 12 +/- =` gives exactly
1.000000000002, so no tan 45 is needed.

- **St flg at the end of the partition** (`examples/fastmode.ti59`, the St flg
  trick of TI PPC Notes V9N3P5). Fetching the operand fails, the program halts
  with the argument pending, and the user presses 7 EE.
- **Acosta's "hi2"** (`examples/calendar-08-acosta.ti59`): RCL of the
  constant, St flg, then a pseudo-keycode `0C` as the operand, all inside the
  program. Its hex units digit feeds only the digit C and leaves the argument
  open, and the next step (68 Nop) ends it. The keyboard ritual (`Pgm 12 SBR
  999`, `R/S`, `D.MS`, `LRN Ins Ins`) only manufactures that `0C`, with the
  stale-cache Ins quirk known from `examples/texas-print.ti59`.
- **SST** (the simplest, `examples/fastmode-sst.ti59`). One St flg step
  anywhere, preferably at step 8k+7, then `GTO` to it, `SST`, a digit and
  STO. SST leaves the operand pending because a program operand is fed as
  two digits. No partition-end halt and no pseudo-keycode are needed.
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

**After entry.** The jump to the new step does not reload the
program-register cache. Steps 001–007 therefore run from the drained cache
(as 00 when St flg was the last byte of its register), and the real program
starts at step 008.

### What a fast-mode program can do

Every instruction class was run once in fast mode and once in normal mode
from the same program, and X, the data registers, the printout and the
display were compared. Sources 2, 4 and 6 behave alike. To reproduce:
`uv run python tools/agentic/fastmode_matrix.py`.

**Why things break.** The ROM tests the Prg Src Flag in seven places. Only
the step fetch tests single bits. The other six ask only "non-zero?", so
there a fast-mode program counts as a keycode sub-program or a library
program:

| Site | Test | Effect in fast mode |
|---|---|---|
| `07C5`–`07C9` RUN_LOOP | ≠ 0 → `08AE` | No R/S poll, no GTO "peek" poll, and no error stop under flag 8 (`07E0`–`07E9`). This is where the speed comes from. |
| `054F`–`0553` DISP_FORMAT | ≠ 0 → `08A1` | X is not formatted for the display after a step. The trace-print check (`05A8`) is inside the formatter, so nothing is traced. |
| `08B2`–`08B8`, `0B8F` PRGREG_FETCH | bit 0, bit 3 | 2, 4 and 6 fetch from RAM, so the program itself runs. |
| `0860` → `0BD2` LABEL_SEARCH | ≠ 0 → `0FAD` | Labels are searched in the selected module program, not in RAM. |
| `0A4B`–`0A57` launch prologue | caller ≠ 0 → `0DA7` | Every call pushes the module's address counter as the return address, as for a library caller. |
| `1191`, `14F9`–`1506` RTN_POP / LIB_RETURN | library level popped | The return reloads the module PC and sets source 1, so execution continues in the module. |
| `06B9`–`06C5` key epilogue | ≠ 0 → `08AE` | After an operation, the program keeps running even when fB[0] is clear. |

**Works as in normal mode:**

- Number entry, EE, AOS arithmetic with all 8 parenthesis levels, and every
  function computed in microcode: ln x, log, their inverses, sin, cos and tan
  and their inverses in DEG, RAD and GRAD, √x, x², 1/x, yˣ, INV yˣ, |x|,
  Int, INV Int, π, +/-, Fix, Eng and INV EE.
- Memory: STO, RCL, SUM, Prd and Exc with their INV forms, all Ind forms,
  CMs, CP (inside a program it clears only t, as usual), x⇄t, CE, CLR, and
  HIR STO, RCL and SUM.
- Flags: St flg, INV St flg, If flg.
- Transfers to absolute or indirect addresses: GTO nnn, GTO Ind, x=t and x≥t
  (with or without INV) to nnn or Ind, If flg to nnn or Ind, and Dsz n nnn.
  **Dsz loops work.** The comment in `examples/fastmode.ti59` (TI PPC
  folklore) says otherwise, but only Dsz to a *label* fails.
- Lbl and Nop steps in the flow of the program; they are skipped as usual.
- Op 00–08, Op 10, Op 16, Op 17, Op 18/19, Op 20–39, Op Ind, Fix Ind, and
  Pgm nn on its own (it only selects the module program).
- Printing: Prt, Adv, Op 05 and Op 06, Op 08 (label list). Pause shows
  the correctly formatted X, because Pause formats it itself.
- Errors (1/0, …) set the error condition as usual, and Op 18/19 see it.

**Broken.** In each case the program leaves fast mode, usually stops with a
dark display, and the result is lost:

- **Any label as a transfer target.** This covers GTO, SBR, x=t, x≥t, If flg
  and Dsz to a label, and the user keys A–E′ called from the program. The
  search runs in the module program selected in SCOM[9]. When the label is
  not there, the run stops with an error. If the label does exist there,
  execution continues in the module. Use absolute addresses or Ind instead.
- **Any subroutine call:** SBR nnn, SBR label, SBR Ind, and `Pgm nn SBR`
  into the module. The subroutine itself runs, but its INV SBR returns into
  the module, at whatever address the module's address counter held at the
  call. (The launch also clears the source, so the subroutine runs in normal
  mode.)
- **The built-in keycode sub-programs**, which are calls of the same kind:
  Σ+ and INV Σ+, x̄, P→R and INV P→R, D.MS and INV D.MS, and Op 11–15. The
  sub-program completes (the first Σ+ does update R01–R06), and then returns
  into the module.

**Behaves differently:**

- Nothing is traced: neither the printer's TRACE switch nor flag 9 prints
  anything during the run.
- Errors never stop the run, not even with flag 8 set.
- INV SBR with an empty return stack does not stop the program. RTN_POP ends
  the run (`1195`), but the key epilogue sees the source flag and carries on
  with the next step.
- The R/S and GTO keys are not polled, so R/S cannot interrupt the program
  and holding GTO shows no peek. The other keys are ignored, as in normal
  mode.
- The display keeps whatever it showed at entry until the program stops.

**Stopping and leaving.** RST clears the source flag and continues at step
000 in normal mode. A program R/S stops the run but leaves the source flag
set. Both then redisplay X. If X holds a computed, non-zero value that
fast mode never formatted, that redisplay loops forever in `030A`–`030E`.
The display stays dark, no key works, and only switching off ends it, which
also loses the program. Measured stops (second table of the tool):

| Ends with | Result |
|---|---|
| `CLR RST`, `CLR +/- RST`, `0 RST` | safe, normal mode (X = 0 or digit entry) |
| `RCL nn Pause RST`, `RCL nn Prt RST` | safe: Pause and Prt format X |
| `RCL nn RST`, `… = RST` | **hangs** |
| `5 R/S`, `CLR R/S` (X in digit entry) | stops, shows the entry, source still set |
| `RCL nn Pause R/S`, `RCL nn Prt R/S` | stops showing the formatted result, source still set |
| `RCL nn R/S`, `… = R/S`, `STO nn R/S`, `RCL nn CE R/S` | **hangs** |

So X must be in digit entry, or 0, or have just been shown by Pause or Prt.
The robust pattern is `CLR RST` with the result in a register, which a
normal-mode RCL at step 000 then shows (`examples/fastmode-sst.ti59`).

**After a program R/S** the calculator is still in fast mode, with the
source flag set:

- The R/S key resumes the program, still in fast mode.
- Digit keys, `.`, +/-, EE, INV, CLR and CE work as number entry.
- Any operation key (+, =, x², x⇄t, 1/x, (, STO nn, RCL nn, …) executes and
  then, through the key epilogue, quietly runs the program on from the
  stopped step to its next R/S.
- A user key A–E′ searches the module for its label and fails.
- **RST from the keyboard** clears the source flag and is the way back to a
  normal calculator.

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
  peek (`07D2`). CP clears the protection.

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
