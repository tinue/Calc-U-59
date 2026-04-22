# TI-58C vs TI-59 Idle Loop Blink Timing Analysis

Date: 2026-04-22

## Goal

Investigate why TI-58C runtime around the idle/blink loop appears about 3x-4x too long versus real hardware, while TI-59 appears correct.

Primary suspicion raised during analysis:
- WAIT and/or KEY timing in IDLE mode may be over-weighted.

## Files and Regions Analyzed

- CALCU59_TRACE.ans
  - Initial requested region around lines 302-410
  - Focused loop marker: `REPEATING: 18-instruction cycle, 99 total repetitions`
- CALCU58C_TRACE.ans
  - Requested region around lines 694-910
  - Noted markers:
    - `REPEATING: 39-instruction cycle, 49 total repetitions` (line ~692)
    - `REPEATING: 36-instruction cycle, 49 total repetitions` (line ~910)
- ROM disassembly
  - rom/TI59.asm around 063C-0658 and branch targets
  - rom/TI58C.asm around 063D-0659 and 0A25-0A2E
- Emulator core timing and control
  - Core/TMC0501.cpp
  - Core/TMC0501.hpp
- Trace formatting/collapse semantics
  - tools/read_trace.py

## Important Trace Semantics

The trace files shown here are generated with repeating-loop collapsing enabled.

Implication:
- The visible "N-instruction cycle" is not the full executed cost.
- Suppressed same-PC hold/re-execution cycles (especially WAIT/KEY HOLD behavior) are not fully visible in the printed loop body.
- True executed cycle count is best inferred from the left trace index deltas.

## TI-59 Findings

### Loop under focus

Marker:
- `REPEATING: 18-instruction cycle, 99 total repetitions`

Representative behavior:
- Loop path includes 063C..064A then 0656..0658.
- Exit condition is when branch at 064A (`JNC 0656`) falls through to 064B.
- This is governed by KR bit test at 0649 (`TST KR[4]`) after state updates (`C<>D`, `C=C+1`, `IO=C MANT`, `MOV KR[4..7],R5`).

### Runtime estimate from trace indices

Example measured delta:
- Start around index 5432
- Next marker region starts around 6632
- Delta approximately 1200 executed instruction steps over 100 passes

Average cost per pass:
- About 12 effective steps/pass (after suppression effects)

## TI-58C Findings

## Clarification on requested region

The region around lines 694-910 contains the tail of a 39-instruction repeated block and begins a 36-instruction repeated block at line ~910.

Markers observed in file:
- `REPEATING: 39-instruction cycle, 49 total repetitions`
- `REPEATING: 36-instruction cycle, 49 total repetitions`
- pattern repeats alternately later in the file

### Structural similarity to TI-59

Strong similarity exists:
- WAIT + KEY scan + back-branch idle-loop skeleton
- Busy/condition gating with `TST.BUSY` and conditional branches
- Same counter/state advance motif:
  - `CLR.IDLE`
  - `C<>D`
  - `C=C+1`
  - `IO=C MANT`
  - `MOV KR[4..7],R5`
  - `C<>D`
  - test KR bit
  - branch/fall-through

Difference:
- TI-58C has extra KR tests and an additional detour through 0A25-0A2E in this loop family, making it branch-heavier and more sensitive to WAIT/KEY hold timing.

### Runtime estimate from trace indices

For the 36-instruction marker region:
- Start around index 14614
- Next major marker region around 19414
- Delta approximately 4800 executed instruction steps over 50 passes

Average cost per pass:
- About 96 effective steps/pass

Comparison to TI-59:
- TI-58C per-pass effective cost in this region is much larger than TI-59 despite visible cycle lengths being only moderately larger.
- This points to hidden/suppressed hold cycles as the dominant factor.

## Root Cause Hypothesis

Most likely source of the slowdown:
- IDLE weighting applies 4x cost to instructions that should not be slowed the same way, especially WAIT Dn while repeatedly held.

Relevant implementation detail before experiment:
- In `TMC0501::step()`, weight was computed as:
  - `w = 4` whenever `FLG_IDLE` was set
  - otherwise `w = 1`
- This was applied uniformly, including WAIT Dn opcodes.

Why this over-amplifies TI-58C:
- TI-58C loop uses many WAIT sites (`WAIT D13`, `WAIT D10`, `WAIT D0`, etc.) with HOLD re-execution.
- If each held WAIT is also charged at 4x, total runtime inflates quickly.
- TI-59 loop family is less sensitive because it has fewer expensive wait/hold sites in the corresponding path.

## Experimental Fix Applied

File changed:
- Core/TMC0501.cpp

Change:
- Adjust instruction cycle weight policy in `step()` so WAIT Dn uses base weight even in IDLE.

New policy:
- WAIT Dn (`opcode` matching 0xA?0): weight 1
- Other instructions in IDLE: weight 4
- Non-IDLE: weight 1

Implementation note:
- Added `isWaitDn` detection and explicit `if` logic to avoid nested-ternary lint warning.
- File-level error check after edit reported no errors.

## Why this matches the observed symptom

The measured discrepancy (~3x-4x too long) is consistent with over-weighting of heavily repeated WAIT cycles.

Given that:
- TI-58C loop path has many WAIT hold replays
- TI-59 appears acceptable

A WAIT-specific timing correction is a plausible first-order fix.

## Remaining Secondary Suspect

If timing is still long after this change, next suspect is KEY scan-all HOLD behavior in IDLE mode:
- scan-all KEY path can reassert HOLD while scanning digit phases
- repeated same-PC suppressions may still be over-counted relative to hardware

Likely next experiment if needed:
- apply same selective weighting idea to specific KEY scan-all hold cycles
- remeasure with index deltas and wall-clock side-by-side against hardware

## Summary

1. The TI-58C slowdown is not explained by visible loop instruction count alone.
2. Trace-index deltas show much larger hidden hold/re-execution cost for TI-58C.
3. The emulator likely over-charged WAIT Dn in IDLE mode.
4. A targeted fix was applied so WAIT Dn runs at weight 1 even when IDLE is set.
5. This is the most likely cause of the 3x-4x runtime inflation observed in TI-58C blink/idle behavior.
