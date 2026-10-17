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
| 13 | nibble 1 = current paren level, nibble 2 = AOS depth; nibbles 8–9 = partition (see `reference/CoreArchitecture.md`) |

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
| fA[10] | printer trace record pending (`0A68`) |
| fB[6] | "fresh operand": set by every key at `06A3`, cleared by an AOS push and by `(`; an operator or `)`/`=` arriving with fA[6] clear is an error (`5 + =`, `5 + × 3`) |
| fB[9] | error: display blinks until CLR/CE (`0641`) |
| fB[12] | argument entry in progress: digit keys feed a suspended operation sequence |

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
