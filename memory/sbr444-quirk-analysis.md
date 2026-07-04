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
keycode. The session of 2026-07-04 analyzed exactly what `SBR 444` and `R/S` do —
quirk 1 of the chain — and corrected an earlier, wrong account.

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
   from chip PC 0028 = **the header**. Exactly two keycodes are fetched: module[28] =
   0x29 and module[29] = 0x52 — literally the two BCD bytes of **Pgm 14's start
   address 2952** — executed as keycodes **29 = CP** and **52 = EE**.
3. CP is harmless and its epilogue re-enters the fetch loop (…054C → 08A1 → 08AE →
   082B). EE dispatches into KEY_EE (0110), sets fB[15] (EE mode) at 011A, and exits
   through the *keyboard* epilogue (0129–012C → 02DE → 06B9); the continue-run gate
   there (06C0 `TST fB[10]` / 06C3 `JNC 08AE`) fails, so the machine falls into the
   display idle loop. **The run ends — no third fetch, no new error.**
4. Final state after the second halt: fB = 8A60 — fB[9] still set (the blink is the
   *first* crash's error, R/S never cleared it), fB[15] set (EE mode → display
   "0. 00" from the zeroed display), fB[0]/fB[13] clear; SCOM[0] Prg Src Flag **still
   1**, PC 008; CROM PC now 0030.

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
  cache stale (previously known).
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

## Open questions and proposed next steps

1. **Why does P/R arrive at the 087E test with fB[0] SET after halt 1 but CLEAR after
   halt 2?** The live fB[0] is clear after *both* halts (fB = 0A60 / 8A60), so the
   value must be re-derived during P/R key processing — candidate: the 0A59–0A5D block
   (`TST fB[0] / TST fB[13] / SET fB[0] / SET fB[13]`) or a flags restore from
   persisted state (SCOM[15]? EE flag fB[15]? Prg Src still 1?). The end behaviour was
   trace-verified in earlier sessions; the mechanism was not.
   **Proposed traces:** `pr-after-halt1.bin` — run the sequence *without* R/S and trace
   only the `2nd P/R` press; `pr-after-halt2.bin` — full sequence, trace only the
   `2nd P/R` press. Compare at 07F3, 0A4B–0A5D, and 087E (use
   `tools/compare_trace.py`).
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
   invalidates the stack. Only the exact semantics of F (empty vs. locked) remain
   unverified.
3. **Why exactly does the EE handler end a running program?** The keyboard-epilogue
   gate (fB[10] at 06C0, plus fA[5] at 06BE — fA[5] was clear during the whole resumed
   run) fell through. A *normal* running program that contains keycode 52 presumably
   does not halt — determine which flag a normal run carries that the R/S-resumed
   garbage run lacks.
   **Proposed trace:** a small RAM program containing keycode 52 (EE), started with
   R/S and traced across the EE step; compare the 02DE/06B9/06C0 flags with rs.txt.
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

Traces for 1 and 3 can be captured the same way as the existing ones: temporarily
insert `Trace: <name>.bin` / `Trace: Off` around the key of interest in the
`KEYSTROKES` script of a scenario file, then render with `tools/read_trace.py`.

**Reminder:** whatever any of these resolves, update `rom/TI59-commented.asm`,
`examples/texas-print.ti59`, *and* this document.
