# SBR 444 / R/S Quirk Analysis (texas-print printer-interrupt chain)

**Maintenance rule: any further analysis of this quirk chain must update all three
files together — `rom/TI59-commented.asm` (ROM annotations), `examples/texas-print.ti59`
(quirk walkthrough in the file header), and this document.** Much of the information
below is deliberately redundant with those two files; this document adds the trace
archive, the analysis provenance, and the open questions.

## Background

The TI-59 "printer interrupt" hack (PPX Exchange, March/April 1982) plants an invalid
keycode `1F` in program memory through a chain of four firmware quirks. The
initialization sequence `[9 Op 17] [Pgm 12] [SBR 444] [R/S] [P/R] [LRN] [Ins] [LRN]`
looks harmless, yet leaves the machine in a state where `Ins` computes the invalid
keycode. What the hack does and a shorter way to make 1F (through fast mode)
are in `rom/printerinterrupt.md`; this document is the trace-level analysis.
The session of 2026-07-04 analyzed exactly what `SBR 444` and `R/S` do —
quirk 1 of the chain — and corrected an earlier, wrong account. The session of
2026-07-05 analyzed the `2nd P/R` press — quirk 2 — from the two traces proposed by
open question 1, resolving it.

### Files and tools used

| Artifact | Role |
|----------|------|
| `rom/TI59-commented.asm` | Commented TI-59 ROM disassembly. Relevant annotations: 0x086F (transfer target validate/commit), 0x08B2 (PRGREG_FETCH source dispatch), 0x0A4B (launch prologue / Prg Src Flag write), 0x0D50 (return-stack push), 0x1286 (library transfer resolver — added this session), 0x11E1 (transfer-error halt — added this session). |
| `reference/CoreArchitecture.md` | Architecture reference; § SCOM registers now documents the SCOM[14]/[15] return stack. |
| `TI_58_59-HW-manual.pdf` | "Calculators TI-58/59 HW programming guide" by Hynek Sladký (external document, not in the repository). Source of the SCOM[9] layout and the return-stack level layout. |
| `examples/texas-print.ti59` | State file automating the article's key sequence; its header holds the authoritative quirk walkthrough (quirks 1–4). |
| `.claude/skills/calc-u-59-core` | Skill covering the emulation core, trace infrastructure, and ROM analysis workflow. |
| `tools/read_trace.py` | Rendered the binary traces to text (including the deferred-field validity windows for RAMOP/RAMREG/SREG added just before this analysis — commit `fa6799e`). |
| `memory/sbr444.txt` | CPU trace: from just before the third `4` of `SBR 444` through the first halt (blinking 239.89). Captured with a scripted `Trace:` directive in the keystroke script (temporary edit of `examples/printer-quirks.ti59`, which replays the same sequence). |
| `memory/rs.txt` | CPU trace: the `R/S` keypress through the second halt (EE-mode "0. 00"). Same capture method. |
| `memory/pr-after-halt1.txt` | CPU trace: `2nd P/R` pressed after halt 1 only (scenario run *without* the `R/S`). Captured 2026-07-05, same method. |
| `memory/pr-after-halt2.txt` | CPU trace: `2nd P/R` pressed after halt 2 (full quirk-1 sequence first). Captured 2026-07-05, same method. |

Setup at trace start: TI-59 + Master Library, partition 239.89 (after `9 Op 17`),
step counter at 008 (from an earlier `GTO 008`), Pgm 12 selected.
Master Library layout facts used throughout: Pgm 12 starts at module address 2609 and
is 155 steps long; Pgm 13 starts at 2764; Pgm 14 starts at 2952 (all three read
directly off the module header in the traces).

## Verified findings

### SBR 444 never executes any library code (sbr444.txt)

1. **Launch prologue writes the source flag first.** ROM 0A4B–0A53 rewrites SCOM[0]
   with Prg Src Flag (nibble 3) := 1 *before* any validation. E holds the launch
   descriptor `…444001` (target 444, source 1).
2. **The resolver reads two header entries.** ROM 1286 selects SCOM[9] (R5 = 9);
   128B–1290 recall it — its mantissa holds the selected program number 12 — and form
   the header offset 2·12 = 24. The `LIB.PC` loop 1293–1297 points the CROM pointer
   there; 1298–12AA read header bytes 24–27: **B := 2609** (Pgm 12 start),
   **C := 2764** (Pgm 13 start = Pgm 12's end bound).
3. **The bounds check.** 12AB computes A := 2609 + 444 = 3053; `12AE B=A-B MANT` /
   `12AF JC 11E1` rejects because 3053 ≥ 2764. The transfer dies here, before a single
   program byte is fetched (zero `IN LIB` fetches at the interpreter site 082F in the
   whole trace). The success path 12B0–12B6 (commit target to CROM PC) never runs.
   Nothing is special about 444: any offset ≥ 155 (past Pgm 12's end) fails the same
   check, and since the leftover CROM pointer position comes from the *header reads*
   (not the target value), the resulting state is identical for every rejected offset —
   SBR 333 confirmed empirically to work just as well. Offsets 000–154 are in range
   and would actually execute Pgm 12 code.
4. **The error halt does a minimal cleanup.** 11E1: reloads SCOM[0] (`…101000`),
   drops nibble 3 with the `SRB MANT`/`SLB MANT` pair (Prg Src back to 0, step counter
   008 preserved), sets fB[9] (error/blink), resets the subroutine return stack in
   SCOM[15] (11E9–11EC store `…10000F`: level slots cleared, caller PC 008 in level 1,
   F in the depth nibble — discarding the return the SBR had pushed), clears fB[0],
   idles → blinking 239.89. End flags: fB = 0A60.
5. **The dirty leftovers** (the actual bug): the CROM chip's internal PC sits at header
   address 28 (auto-incremented past the two entries just read), and SCOM[9] still
   holds the run descriptor naming library program 12 (`…1212043` at R/S time).

### R/S resumes into the module header (rs.txt)

1. The R/S handler (07F3) loads SCOM[9] (SREG=09), finds fB[0]/fB[13] both clear →
   resume path 0BB3 → 0928, which fetches the saved source digit **1** from the
   descriptor; the same 0A4B launcher then writes Prg Src Flag := 1 again. Display is
   zeroed (0BCD), target E := 0 — a resume is not a transfer, so **no range check of
   any kind runs**.
2. PRGREG_FETCH (08B2) dispatches flag = 1 → CROM interpreter fetch at 082B/082F…
   from chip PC 0028 = **the header**. *Corrected 2026-10-17 (headless harness,
   tools/headless/, exact replay of examples/printer-quirks.ti59):* the run fetches
   **12** keycodes, module[28..39] — the BCD start addresses of Pgm 14–19 —
   executed as **29 CP, 52 EE, 30 tan, 95 =, 32 x⇄t, 31 LRN, 33 x², 63 Exc Ind,
   34 √x, 80 Grad, 36 Pgm**, and `Pgm` consumes byte 39 = **51** as its program
   number. There is no Pgm 51: the run halts at ROM 141C (`SET fB[9]`, `CLR fB[0]`,
   → 12B8). The result does not depend on how long R/S is held (3000–60000
   instruction steps tried): execution only starts after the release wait at 07EA.
3. EE (keycode 52) does **not** end the run. Its handler (0110 → 012C → 02DE) sees
   fB[0] set and takes 06B9; with a non-zero Prg Src Flag the 06C0/06C3 gate
   continues the run at 08AE on both branches. A plain RAM program containing EE
   (`1 EE 2 + 3 = R/S`) likewise runs through it (result 1.03 02). The earlier
   reading — "exactly two keycodes, EE ends the run, CROM PC 0030" — came from an
   incomplete rs.txt capture window.
4. Final state after the second halt: fB = 8A60 — fB[9] set (the blink; the Pgm 51
   error re-asserts it), fB[15] set (EE mode from keycode 52 → display "0. 00"),
   fB[0]/fB[13] clear; SCOM[0] Prg Src Flag **still 1**, PC 008; **CROM PC 0040**.

### P/R re-derives the transfer type from the leftover Prg Src Flag (pr-after-halt1.txt / pr-after-halt2.txt)

Resolves open question 1. `2nd P/R` (P→R, a keycode-ROM sub-program) launches through
the same 0A4B prologue as SBR, with descriptor E = `…284008` (entry step 284, new
source 8).

1. **The prologue stashes the caller's source.** 0A4C loads SCOM[0]; besides writing
   the *new* source into nibble 3, the 0A4D–0A53 shuffle copies the *old* nibble 3 —
   the caller's Prg Src Flag — into nibble 1 of the rewritten SCOM[0]. Observed
   values at the 0A52 STOF: `…108000` after halt 1 (old source 0), `…108010` after
   halt 2 (old source 1).
2. **0A54–0A57 dispatch on the caller's source** (`IO=-D EXP` / `JNC 0DA7`):
   - *Source 0 (keyboard/RAM caller):* fall through to 0A58–0A5E, which **SET fB[0]
     and fB[13]**. All keyboard-initiated launches take this path — sbr444.txt,
     rs.txt, and pr-after-halt1.txt all execute 0A5C/0A5D.
   - *Source ≠ 0 (library caller):* jump to 0DA7–0DB9, which instead reads the CROM
     chip's PC digit-by-digit (`LIB.PC.IN` ×4, LSD first, non-destructive) as the
     caller's return address — and **never touches fB[0]/fB[13]**. Only
     pr-after-halt2.txt takes this path: the R/S resume left Prg Src = 1 and nothing
     since had cleaned it.
   Both paths join at 0A66 → the 0D50 return-stack push → the 086F validate/commit
   block. So fB[0] at the 087E test is not restored from any persisted flag state —
   it is **freshly derived from the leftover Prg Src Flag on every launch**. (Both
   candidate mechanisms in the original question were half right: the 0A59–0A5D
   block is what sets it after halt 1; the persisted Prg-Src-still-1 is what
   suppresses it after halt 2.)
3. **Outcomes.** After halt 1, fB[0] SET → range check skipped (0883 → 0889), PC 284
   / source 8 committed, the P→R sub-program runs to completion; SCOM[0] reads
   `…100000` (source 0, step 008) near the end and the final fB = 0A60 — only the
   first crash's blink remains, the machine is otherwise clean and LRN would show
   step 008's true content (the hack fails without R/S). After halt 2, fB[0] CLEAR →
   the 0884–0888 range check runs (target register 35 vs 30 partition registers) and
   fails → 0B0A: `SET fB[9]`, `CLR fB[0]`; final fB = 8A40.
4. **Dirty leftovers of the failed launch** (quirk 2's actual leak, all
   trace-verified):
   - SCOM[0] = `…108010`: the leaked Prg Src 8 in nibble 3 *plus* the stashed caller
     source 1 in nibble 1; step counter still 008 (the PC := 284 commit at 089A/089B
     never ran). No SCOM write occurs after 0B0A in the whole trace.
   - The return-stack push is never popped — 0B0A does **not** reset the stack
     (contrast 11E1). SCOM[15] ends as `0000000100004012`, SCOM[14] = 0: depth 2,
     level 1 = the failed launch's library caller (source 1, CROM address 0040),
     level 2 = the R/S-resume's keyboard caller (register 001 · byte 0 · source 0)
     shifted up one level.
5. **Return-stack byproducts.** The halt2 value pins down the per-level nibble order
   (see resolved question 2), and rs.txt settles the depth-marker question: the
   R/S-resume push wrote `…1001` (clean depth 1) directly over the 11E1-reset
   `…10000F` — the F depth marker behaves as "empty"; the next push starts a fresh
   depth-1 stack.

### Corrections applied to the repo (commit `0c57628`)

- The old quirk-1 story ("SBR 444 starts executing mid-formula in Pgm 14's code at
  3053, quickly errors; R/S resumes and crashes again half a second later") was
  **wrong** on every mechanism point and was rewritten in `texas-print.ti59`.
- The "side benefit" claim that the garbage run's `RCL 02`/`RCL 01` need valid data
  registers is disproved: neither trace contains a single data-register access
  (`RAMOP` never fires).
- New ROM annotations at 0x1286 and 0x11E1; the 0x086F note now states only what was
  verified (P/R after the second halt *reaches the 087E test* with fB[0] clear).

### Incidental knowledge gained

- Flag semantics: fB[9] = error/blink; fB[15] = EE mode; fB[0] at the 087E test =
  transfer type (set → keycode sub-program, skip RAM range check); fB[11] = SCOM[10]
  cache stale (previously known). Refined 2026-07-05: fB[0]/fB[13] are set by the
  launch prologue's keyboard/RAM-caller branch (0A5C/0A5D) and left clear by its
  library-caller branch (0DA7) — i.e. fB[0] really encodes "launch initiated from
  keyboard/RAM", which the 086F block then treats as the target-type selector.
- SCOM[9] is the library/partition bookkeeping register (layout documented — see
  resolved open question 4): the "program number appearing twice" (`…1212043`) is the
  current-page / new-page field pair.
- SCOM[14]/SCOM[15] hold the 6-level subroutine return stack — SCOM[15] levels 1–3,
  SCOM[14] levels 4–6 — pushed on every calculator-level call: SBR into a RAM or
  library program, and keycode-ROM sub-program launches such as P→R (user-provided
  2026-07-04, trace-consistent). The push routine is ROM 0D50–0D78 and runs in *both*
  traces (during the SBR 444 launch and again during the R/S resume). An earlier
  revision of this document claimed the R/S handler's 0BC4–0BCA also writes row 15 —
  that was a static misreading; 0BC4 never executes in rs.txt.
- Trace frames are post-execution: the COND shown on a `TST`/`Jxx` line is the value
  *after* that instruction; a taken branch is only visible from the next line's
  address. Observed: `TST` of a SET flag leaves COND = 0.

### Related trigger: `Pgm nn R/S` inside a program (headless, 2026-10-17)

A RAM program step `Pgm nn` only marks SCOM[13] nibble 15; the next step
decides (ROM `0976`). For R/S the library path is taken without any label
search or start-address load, so the run continues at the CROM chip's
current address. After a fresh selection that is the module header: with ML
the fetches at `082F` go to CROM 0001, 0002, …, 0009 and then jump (Pgm 23
→ 4660, Pgm 02 → 0596), the header bytes acting as keycodes exactly as in
the R/S resume after the failed SBR 444. Program "3 Pgm 02 R/S" ends with
an error from a 0 ÷ 0 inside that garbage (`03D4`).

## Open questions and proposed next steps

1. **RESOLVED — Why does P/R arrive at the 087E test with fB[0] SET after halt 1 but
   CLEAR after halt 2?** Traced with pr-after-halt1.txt / pr-after-halt2.txt
   (2026-07-05): fB[0] is freshly derived on every launch by the prologue's
   caller-source dispatch at 0A54–0A57 — caller source 0 sets fB[0]/fB[13] at
   0A5C/0A5D; a library caller (source ≠ 0) branches to 0DA7, saves the CROM PC as
   the return address, and leaves both flags clear. After halt 1 SCOM[0]'s Prg Src
   is 0 (11E1 reset it); after halt 2 it is still 1 (the R/S resume wrote it, the EE
   halt never cleaned it). See the full findings section above.
2. **RESOLVED — What does SCOM row 15 hold?** SCOM[14]/[15] are the 6-level
   subroutine return stack (15 = levels 1–3, 14 = levels 4–6), written by SBR,
   library-program calls, and keycode-ROM sub-program launches (P→R). The 11E9–11EC
   store in the error halt is the stack being reset (return discarded, F depth
   marker). Push routine annotated at ROM 0x0D50; SCOM table updated in
   reference/CoreArchitecture.md. Per-level layout documented by the SCOM register
   table in "Calculators TI-58/59 HW programming guide" by Hynek Sladký
   (TI_58_59-HW-manual.pdf, not in the repository): each level is 5 nibbles — RAM
   register no. (3) + byte no. (1), or a
   4-digit "second ROM" (CROM) address for library callers, plus the caller's Prg
   Src Flag — and SCOM[15] nibble 0 holds the number of pushed levels.
   Trace-verified: the SBR 444 push stores SCOM[15] = `0000000000001001` = register
   001 / byte 0 / source 0 / depth 1, i.e. the keyboard caller at step 008. This
   also clarifies the error-path value `…10000F`: it is *not* an encoded level entry
   but the raw SCOM[0] image with F stuffed into the depth nibble — the F is what
   invalidates the stack.
   *Refined 2026-07-05 from pr-after-halt2.txt:* the per-level nibble order is,
   from the level's lowest nibble upward: **caller's Prg Src Flag, then the 4-digit
   BCD position LSD-first** — position = register·10 + byte for keyboard/RAM
   callers (step 008 → `0010`), or the CROM address for library callers. Checks:
   keyboard level `…1001` → n1 src 0, digits 0,1,0,0 → position 0010 ✓; halt-2
   value `0000000100004012` → depth 2, level 1 = src 1 + digits 0,4,0,0 = CROM 0040,
   level 2 = src 0 + position 0010 ✓. The F semantics are also settled: rs.txt's
   resume push wrote `…1001` (clean depth 1) straight over the reset `…10000F`, so
   F acts as "empty" and the next push restarts the stack at depth 1.
3. **RESOLVED 2026-10-17 — EE does not end a running program.** The R/S-resumed
   run continues through EE and ends on the invalid `Pgm 51`; see the corrected
   R/S findings above. (The earlier question rested on an incomplete rs.txt
   capture window.)
4. **RESOLVED — SCOM[9] descriptor layout.** Documented by the SCOM register table
   in "Calculators TI-58/59 HW programming guide" by Hynek Sladký
   (TI_58_59-HW-manual.pdf, not in the repository). Nibble 15 = list-data flag;
   14–7 = 0; 6–5 = "current
   page" (current library program); 4–3 = "new page" (pending `Pgm nn` selection);
   2 = module security code; 1 = number of RAM chips; 0 = number of program banks =
   program-partition registers / 10 (the OP 17 partition pointer already known from
   CoreArchitecture.md). Trace check (07F3 `B=LOAD ALL` → `…1212043`): current page
   12, new page 12, security 0, RAMs 4, banks 3 (= 30 program registers under
   239.89) — all consistent. Correction to the original question: the `…010` tail
   seen during the SBR launch was an artifact — that read was `C=LOAD MANT`
   (nibbles 3–15 only), so nibbles 0–2 were stale C content, not SCOM[9]; nothing
   actually changes across states. Layout added to reference/CoreArchitecture.md
   § SCOM registers.
5. **RESOLVED 2026-10-17 — the "extra" CROM fetches between the second halt
   and P/R are part of the R/S-resumed run itself** (12 fetches, 28–39, ending
   with Pgm 51; see above). rs.txt had stopped too early to show them.

New traces are easiest with the headless harness (`tools/headless/`), which
replays a key sequence and prints the ROM trace directly. In the GUI, insert
`Trace: <name>.bin` / `Trace: Off` around the key of interest in a scenario's
`KEYSTROKES` (e.g. `examples/printer-quirks.ti59`, whose `Trace:` line is
commented out) and render with `tools/read_trace.py`.

Headless replay (2026-10-17) also re-verified the rest of the chain: after P/R,
SCOM[15] = `0000000100004012`, SCOM[0] = `…108010`; after LRN Ins LRN, program
register 1 reads `1F 92 21 42 46 11 40 49` — the invalid keycode 1F at step 008.

**Reminder:** whatever any of these resolves, update `rom/TI59-commented.asm`,
`examples/texas-print.ti59`, *and* this document.
