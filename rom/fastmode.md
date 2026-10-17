# TI-59 Fast Mode

## What fast mode is

The TI-59 runs some programs that are not in RAM. The built-in functions Σ+,
x̄, P→R, D.MS and Op 11–15 are short keycode programs stored in ROM, and Solid
State Software modules hold up to 5000 more steps. TI built a faster way to
run these programs. Between two steps the firmware skips work that a user
program normally needs:

- **No display update.** X is not formatted for the display after each step.
  The display stays as it was until the program ends.
- **No R/S check.** The R/S key cannot interrupt the program, and holding
  GTO shows no intermediate values.
- **No trace printing.** Neither the printer's TRACE switch nor flag 9
  prints the steps.
- **No error stop.** An error does not halt the program, even with flag 8
  set.

For a ROM routine such as P→R this is exactly right: 20–40 internal steps
should look like a single operation, with no flicker and no way to interrupt
them halfway. The same steps run in about 40 % less time.

## The hack

The firmware keeps a *program source* digit that says where the running
program comes from: 0 for RAM, 1 for the module, 8 for the ROM routines. The
digit is tested in two different ways:

- The run loop asks only "is it non-zero?". If so, it takes the fast path.
- The step fetch tests single bits. Bit 0 means fetch from the module,
  bit 3 means fetch from ROM, and anything else means fetch from RAM.

The values 2, 4 and 6 are never set by TI's code. They pass the first test
but match neither bit of the second. With one of them in place, a user
program in RAM runs on the fast path. No normal key writes this digit, so
getting such a value there takes a firmware bug. TI-59 users' clubs found
and published such bugs.

## Rules for fast-mode programs

**Allowed:**

- Number entry, all arithmetic and parentheses, and all functions.
- STO, RCL, SUM, Prd and Exc, including their INV and Ind forms. Also HIR,
  CMs, CP, x⇄t, CE and CLR.
- St flg, If flg, Fix, Eng, Deg, Rad and Grad.
- Op 00–08, Op 10 and Op 16–39, and Prt, Adv and Pause.
- Transfers to an absolute or Ind address: GTO, x=t, x≥t, If flg and Dsz.
  Dsz loops do work, despite the old advice not to use them.

**Not allowed.** Each of these leaves fast mode and loses the result:

- **Labels as targets:** GTO, SBR, x=t, x≥t, If flg or Dsz to a label, and
  A–E′ called from the program. Use absolute addresses instead.
- **Subroutines:** SBR in every form, including `Pgm nn SBR`.
- **Built-in ROM routines:** Σ+, x̄, P→R, D.MS and Op 11–15, and their INV
  forms.

**Differences you must expect:**

- The display is frozen, and R/S cannot stop the program.
- Errors never stop the program, and nothing is traced.
- INV SBR with nothing to return to does not stop the program.

**Ending the program.** This is where most fast-mode programs go wrong. The
program must end with RST or R/S, and at that moment X must be 0, a number
still being typed, or a value just shown by Pause or Prt. If X holds any other
result, the calculator hangs with a dark display, and only switching it off
helps. Switching off erases the program.

- Safe endings: `CLR RST`, `0 RST`, `RCL nn Pause RST`.
- Hanging endings: `RCL nn RST`, `… = RST`, `RCL nn R/S`.
- A good pattern: store the result, end with `CLR RST`, and let a normal-mode
  `RCL nn R/S` at step 000 show it.
- `RCL nn Pause R/S` stops with the result on the display, but the calculator
  is still in fast mode. Pressing any operation key quietly continues the
  program. Press RST first.

## Ways in

All methods put X = 1.000000000002 (or …04, …06) on the display first;
`1 + 2 EE 12 +/- =` produces it exactly.

- **SST** (shortest; `examples/fastmode-sst.ti59`). Put a St flg step at step
  007 (the last step of the first 8-step block; see "How the hack works") and
  start the real program at step 008. Key
  `GTO 007 SST 0 STO`.
- **St flg at the end of the partition** (TI PPC Notes V9N3P5;
  `examples/fastmode.ti59`). The program ends with St flg on the last step and
  halts with a flashing display. Key `7 EE`.
- **Acosta's "hi2"** (`examples/calendar-08-acosta.ti59`). The trigger is
  built into the program with a manufactured pseudo-keycode, so a single key
  starts it.
- **LRN inside a module program** (`Pgm 02 SBR 239`;
  `examples/FastMode_Zero4.ti59`). This is an unrelated bug that reaches the
  same state.

## What entry does to the flags and Fix

Every way in writes the whole status register at once, so it replaces all
ten user flags and the Fix setting. Flags set before entry are lost. Set
them inside the fast-mode program instead (St flg works there).

**From X** (SST, St flg at the end of the partition, Acosta's STF IND 7 INV
and "hi2"). The first five mantissa digits of X become the flags, one digit
per pair of flags:

| Mantissa digit | 1st | 2nd | 3rd | 4th | 5th |
|---|---|---|---|---|---|
| Flags | 4 / 9 | 3 / 8 | 2 / 7 | 1 / 6 | 0 / 5 |

The value of the digit decides which flags of the pair are set:

| Digit | 0, 4, 8 | 1, 5, 9 | 2, 6 | 3, 7 |
|---|---|---|---|---|
| Set | neither | lower (0–4) | upper (5–9) | both |

The leading digit cannot be 0, because X is always normalized. That is why
`1 + 2 EE 12 +/- =` sets flag 4. Flag 4 means nothing to the calculator;
it is just what a leading 1 gives. A leading 4 or 8 sets no flag:
`4 + 2 EE 12 +/- =` enters fast mode with all flags clear (tested with the
SST method and leading digits 1, 2, 3, 4 and 8: same run time and result).
Avoid a leading 2 or 3 unless you want flag 9, the trace flag.

The signs of X become the Fix setting: a positive X with a non-negative
exponent, as above, gives floating display (TI PPC Notes V6N8P3, rule 7).

**From program memory** (`Pgm 02 SBR 239`, the Neef method). Here the
firmware loads the status register from the program register that holds
steps 008–015 (Acosta, TI PPC Notes V6N8P3: "from the following octet").
The keycode at step 015 sits in the top two digits, step 014 in the next
two, and so on, so:

- step 015, first digit → flags 4 / 9; second digit → 3 / 8
- step 014, first digit → flags 2 / 7; second digit → 1 / 6
- step 013, first digit → flags 0 / 5

The digit values work as in the table above. Zeros in 013–015 clear all
flags, and `Op 00` (69 00) at 014–015 sets flags 7 and 1. Steps 011, 012
and the second digit of 013 land next to the step address, so keep
011–015 zero unless you mean to set flags. Jay Claborn's PPX article states
the same rule for 011–015 (Fast Mode Summaries, "Fast Mode (continued)",
item 4). This method also leaves Fix 0. Checked on the emulator with
several codes at 011–015.

## How the hack works

You need three facts about the calculator's internals to follow it.

1. **The status register.** The firmware keeps its bookkeeping in one
   16-digit scratch register. That register holds the Fix setting, the
   current program step, the user flags, and the program source digit.
2. **Operations come in pieces.** A key such as St flg needs a second key,
   the flag number. The firmware stores the half-finished operation, waits
   for the digit, and then jumps to the code that completes it. It computes
   that jump target by combining address bits.
3. **HIR registers.** HIR STO n copies X, digit for digit, into internal
   register n. HIR normally accepts only n = 1–8. Register 0 would be the
   status register.

**The bug.** Run from a program, St flg expects a two-digit flag number. If
a key such as STO, EE or x⇄t arrives after the first digit, the firmware
ends the operation early. But the code that
decoded that key leaves one stray address bit behind, and St flg's
completion adds its own bits on top of it. The jump lands in the wrong
routine. After one more misrouted jump, execution ends in the code of
HIR STO, with register number 0.

**The payload.** X is now copied into the status register, digit for digit.
1.000000000002 is laid out so that each digit lands in a useful field:

- The final 2 becomes the program source.
- The zeros become step 000 and floating-point display.
- The leading 1 happens to set flag 4.

**Why it starts running.** Like every operation, the misrouted St flg ends
in the display routine. That routine sees a non-zero source, assumes a ROM
routine such as P→R is between two of its steps, and fetches the next step
instead of formatting X. This is TI's own mechanism for running ROM routines;
from here on every step takes the fast path, and the fetch still reads RAM.

**Why the program starts at step 008.** The RAM chips transfer only whole
registers of 16 digits. A register is either one data register or 8 program
steps (000–007, 008–015, …). The firmware therefore copies a whole block of
8 steps into a buffer, takes the steps out one by one, and reads memory again
only when the next block begins.

The hack sets the step counter to 000 but leaves the buffer alone. Steps
001–007 come from the leftovers of St flg's own block, minus the step after
St flg, which held the place of its flag number:

- **St flg on step 007:** nothing is left. Steps 001–007 run as empty steps,
  each typing a harmless 0, and the real program starts when block 008–015
  is read from memory.
- **St flg on, say, step 004:** steps 006 and 007 run first, in place of 001
  and 002. It works, but it is hard to follow.

Steps 000–006 are never read during the run, so they can hold anything.

**Why the restrictions follow.** All the other places that look at the source
digit also ask only "non-zero?", and each draws the conclusion that suits a
module program:

- **Label search** scans the module, because a module program's labels live
  there. The RAM label is never found.
- **A subroutine call** saves the module's position as the return address,
  because that is where a module program continues. The return then jumps
  into the module.
- **The ROM routines** (Σ+, P→R, …) are called the same way, so they fail the
  same way.
- **The display** is never formatted. When the program stops, the firmware
  shows X, but X is still in internal format. The routine that lays out the
  digits then waits for a condition that never occurs. A typed number, 0, or
  a value just shown by Pause or Prt is already in display format, so these
  endings are safe.

## How we came to these conclusions

- **ROM reading.** The annotated ROM listing (`rom/TI59-commented.asm`) was
  searched for every place that reads the program source digit. There are
  seven, and each is listed with its address in `rom/TI59-ROM-Guide.md`,
  § "Fast mode".
- **Side-by-side runs.** On the emulator, which runs the original ROM
  unmodified, each instruction class was run once in fast mode and once in
  normal mode. X, the data registers, the printout and the display were then
  compared. A second set of runs ended fast-mode programs in different ways
  to find the endings that hang. To reproduce both:
  `uv run python tools/agentic/fastmode_matrix.py`.
- **Traces.** Where the results differed, instruction traces showed which of
  the seven places caused it.
- **Limits.** Everything was observed on the emulator, not on a real TI-59.
  Op 09 and card reading or writing were not tested.
