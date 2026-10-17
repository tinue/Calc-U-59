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

The unary functions use a second table at `0x0500` (`FN_TABLE`), entered
through `FN_ENTRY` (`0210`) with KR = `0x5000 | fn<<4` (`+0x100` for the
`KR[8]` variant). Example: `√x` → `0x0510` (normalize) → `0x0511` →
`JC 081D` → digit-by-digit square root at `0AAC`.

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
| 1–8 | AOS pending left operands, one per level |
| 12 | AOS operator stack: 2 nibbles per entry (precedence, paren level), top entry in nibbles 1/0 |
| 0 | nibble 0 = Fix setting (n+2, 0 = floating); nibble 3 = Prg Src Flag; nibbles 4–7 = program step (see `reference/CoreArchitecture.md`) |
| 13 | nibble 0 = angle unit (0 DEG, 1 GRAD, 0xC RAD); nibble 1 = current paren level; nibble 2 = AOS depth; nibbles 3–5 = index of the top RAM register (119 TI-59, 59 TI-58), set by the power-on probe; nibbles 8–9 = program partition ÷ 10 |

(Other rows are covered in `reference/CoreArchitecture.md`; this table grows
as more of the ROM is documented.)

## Flags (fA / fB)

Meanings established so far; "set" means the bit is 1.

| Flag | Meaning |
|---|---|
| fA[1] | inverse-pair bit: subtract (−), divide (÷), root (INV y^x); during an AOS reduction it carries the popped entry's bit |
| fA[2] | X mantissa negative |
| fA[3] | X exponent negative |
| fA[4] | arithmetic overflow exit marker (`0418`) |
| fA[6] | copy of fB[6] taken at the start of each key (`06A2`) |
| fA[8] | INV pending |
| fA[7] | Ind pending (indirect register / address) |
| fA[9] | 2nd pending (column bias +5 at dispatch); in register access: 1 = read (`02D9`), 0 = write (`04B1`) |
| fA[10] | printer trace record pending (`0A68`) |
| fA[11] | tan (trig sequence) |
| fA[12] | cos (trig sequence); sin↔cos role in the octant fold |
| fA[15] | exponent entry (after EE during number entry) |
| fB[4] | decimal point typed (number entry); kernel mode ln (1) / exp (0) in the transcendental kernel |
| fB[5] | a result (not an entry) is on display: X is in C, the next digit starts a new number |
| fB[7] | engineering display (Eng) |
| fB[8] | INV saved for a suspended operation sequence (`0234`) |
| fB[10] | LRN mode (toggled at `03D8`); outside LRN borrowed as a transient prefix/reformat marker, cleared before idle |
| fB[6] | "fresh operand": set by every key at `06A3`, cleared by an AOS push and by `(`; an operator or `)`/`=` arriving with fA[6] clear is an error (`5 + =`, `5 + × 3`) |
| fB[9] | error: display blinks until CLR/CE (`0641`) |
| fB[12] | argument entry in progress: digit keys feed a suspended operation sequence |
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
