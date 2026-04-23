# Debug GUI User Guide

This document describes the integrated debug panel in Calc-U-59 from a user's perspective. For the underlying API surface used by Swift code, see [DebugAPI.md](DebugAPI.md).

---

## Debug Panel Overview

The debug panel is a three-tab view (`App/Views/DebugView.swift`). The active tab content adapts automatically to whether the emulator is running or frozen:

| Tab  | Running              | Frozen               |
|------|----------------------|----------------------|
| LIVE | `LiveDebugView`      | `LiveDebugView`      |
| CPU  | `SimpleLiveCPUView` + ASM section  | `CPUInspectorView` + ASM section |
| LOG  | `StaticDebugContent` | `StaticDebugContent` |

The **LIVE** tab is disabled while an ASM overlay is running (the tab button is grayed out and the view auto-switches to **CPU**).

The ASM overlay controls are embedded at the bottom of the **CPU** tab rather than occupying a separate tab — this reflects that overlays operate at ROM-instruction level, the same granularity as the CPU inspector.

---

## LIVE Tab

A 60 Hz real-time view of calculator state. Driven by `vm.liveDebugSnapshot` when `vm.liveDebugEnabled` is `true`.

Displays:

- **Partition** — number of program-RAM registers and data registers in the current partition.
- **Program window** — ±5 steps around the current program counter when running; the full program listing (scrolled to the current step) when frozen. The next-to-execute step is shown below the current step in dimmed styling.
- **HIR registers** — the eight hierarchy registers (SCOM[1]–SCOM[8]) decoded as `Double`.
- **T register** — SCOM[11] decoded as `Double`.
- **Calculator flags** — F0–F9 from SCOM[0] nibbles 11–15.
- **Angle mode** — DEG / GRAD / RAD from SCOM[13][0].
- **Indicators** — 2nd, INV, ENG, FIX position from `fA` / `fB` / SCOM[0].
- **SCOM rows** — all 16 rows as 16-character hex strings.
- **Return address stack** — up to 6 levels decoded from SCOM[14:15], with source-flag colour coding (green = RAM, purple = Library, yellow = ROM).

### Freeze and step controls

A toolbar above the LIVE view provides:

| Button | Action |
|--------|--------|
| FREEZE | Halt emulation at the next keycode boundary (`freeze()`) |
| STEP   | Advance one keycode boundary while frozen (`stepKeycode()`) |
| RUN    | Resume emulation (`unfreeze()`) |
| FREEZE ON START | Arm a one-shot freeze that fires on the next program-counter change (`freezeOnNextPCChange()`) |

When frozen, `currentStep` = decoded PC − 1 (last fully executed step) and `nextStepNum` = decoded PC (next step to execute).

---

## CPU Tab

### Running mode — live trace (`SimpleLiveCPUView`)

Shows a scrolling live trace of recent ROM instructions as they execute, updated at 60 Hz. Each row shows the ROM address, opcode, disassembly mnemonic, and key CPU register values at the time of execution. Backed by `vm.cpuDebugSnapshot`.

Trace flags `[.pc, .regsFull]` are automatically enabled while this view is active.

### Frozen mode — instruction inspector (`CPUInspectorView`)

When the emulator is frozen, the CPU tab switches to `CPUInspectorView`, which shows:

- **Instruction history** — the last ≤32 executed instructions with post-execution CPU register snapshots (from the trace ring buffer).
- **Current instruction** — the instruction the emulator is frozen at, highlighted.
- **Look-ahead** — one speculative "next instruction" entry derived from the current PC, shown in dimmed styling.

The view scrolls to the current instruction automatically each time a new inspector snapshot is captured (`vm.cpuInspectorUpdateID` increments).

Backed by `vm.cpuInspectorHistory` (a list of `InspectorSnapshot` values built by `captureInspectorSnapshot()`).

### Freeze semantics in the CPU tab

FREEZE in the CPU tab stops after the **current ROM opcode** completes — no advancement to the next calculator program step. This is the right granularity for ROM-level inspection. Contrast with the LIVE tab, where FREEZE advances to the next keycode boundary (a full calculator program step, which may span thousands of ROM instructions).

### ASM overlay section

A compact ASM overlay control section is embedded at the bottom of the CPU tab. See [ASM Overlay](#asm-overlay-cpu-tab) below for the full description.

---

## LOG Tab

A text-based debug log backed by `vm.debugLines`.

### Dump buttons

| Button | What it dumps |
|--------|---------------|
| **Vars** | Non-zero data registers in the current partition (`debugDumpVars()`) — format: `R00 = 3.14159…` |
| **SCOM** | All 16 SCOM rows as hex nibble strings (`debugDumpSCOM()`) — format: `S00 0000000000000000`, nibble[15] first |
| **Prog** | Program RAM registers R00–Rnn as raw nibble pairs in storage order (`debugDumpProg()`) — format: `R00: 67 11 24 00…` |
| **Memory** | Entire RAM, non-zero registers only, using physical indices (`debugDumpMemory()`) — same format as `ti58c.mem` |

The trash icon clears the log (`clearDebug()`).

### Debug level toggles

**TRACE** — toggles the instruction-level binary trace (`vm.cIndicatorDebug`). The indicator dot is:
- Gray — trace off.
- Orange — trace active.
- Red (not available) — indicates the trace backend is not ready.

**LOG** — cycles the C-core debug event level through three states (`toggleDebug()`):

| Dot colour | Level | `DebugLevel` value | Effect |
|------------|-------|--------------------|--------|
| Gray       | OFF   | `.off` (0)         | No output; C-core event buffer not drained |
| Orange     | INFO  | `.info` (1)        | Swift-side `debugAppend` calls at level `.info` are shown |
| Red        | DEBUG | `.debug` (2)       | All INFO output **plus** C-core write events (STO, MEMWR, RAM OP) |

Each click advances one step; after DEBUG it wraps back to OFF.

---

## ASM Overlay (CPU tab)

The ASM overlay section is embedded at the bottom of the **CPU** tab. It lets you inject raw TMC0501 machine code into the emulator's debug overlay ROM area and execute it in a single synchronous burst. It is intended for ROM-level experimentation: testing small snippets, probing CPU behavior, or exercising the emulator with precisely crafted instruction sequences.

### Overlay address range

The overlay occupies ROM addresses `0x1800–0x1FFF` (2048 words). These addresses are outside the TI-59's normal ROM and are provided exclusively for debug purposes. The 16-bit file words are masked to 13 bits (`& 0x1FFF`) before being written into the overlay.

### File format

The ASM overlay uses **`.asm` files** with two sections:

```
PROGRAM:
; human-readable assembly listing
1800:   01D8    MOV     A.ALL,#0
        ...

HEX:
01D8 01DB 0D00 0A37 1805 1007
```

The `PROGRAM:` section is free-form text — assembly source, comments, notes. It is ignored entirely by the loader. The `HEX:` marker line signals where machine code begins; the loader skips everything up to and including that line, then parses the hex opcodes that follow.

Within the `HEX:` section, the parser recognises two token forms:

- `0xHHHH` — explicit hex prefix, one 13-bit word per token.
- `HHHH` — bare 4-hex-digit sequence; longer runs are split into sequential 4-digit words.

All other characters (spaces, newlines, non-hex tokens) are silently skipped. Files without a `HEX:` section are rejected with an error.

**Maximum:** 2048 words. Files exceeding this limit are rejected.

### Example programs

The repository includes ready-to-run examples in `examples/assembly/`. Each `.asm` file contains both the annotated assembly listing (under `PROGRAM:`) and the loadable opcodes (under `HEX:`).

The examples are drawn from Hynek Sladký's *Calculators TI-58/59 HW Programming Guide*.

### Buttons

| Button | Action |
|--------|--------|
| **Select File** | Opens the file picker. On success, the file is parsed and the overlay is loaded immediately. The status line shows the word count and load address. |
| **Run** | Stops any running emulation, re-injects the overlay into ROM, and waits for a HOLD signal to enter the overlay (see Run semantics below). Resumes normal emulation on success; shows a timeout error if no HOLD is detected within 8 192 steps. |
| **Clear** | Removes the overlay from ROM and resets the status display. |

### Run semantics

**Run** works by hijacking the ROM's HOLD mechanism rather than directly jumping to `0x1800`. When Run is pressed, the emulator forces `PREG = 0x1800` before every CPU step and waits for the ROM's *currently executing* instruction to assert the HOLD signal. HOLD is generated naturally by the keyscan scan-all instruction (present in every iteration of the IDLE keyscan loop) and by `WAIT Dn` instructions. The moment HOLD fires, the PREG redirect snaps `addr` to `0x1800`, and the normal emulation loop resumes from there — running the overlay program sequentially in real time.

Concretely, when Run is pressed:

1. The emulation loop is stopped and the overlay words are written (or re-written) into ROM at `0x1800`.
2. The emulator takes over the CPU, forcing `PREG = 0x1800` on every step and watching for HOLD.
3. If the current ROM instruction generates HOLD (see below), `addr` is snapped to `0x1800` and normal emulation resumes from there.
4. If no HOLD appears within 8 192 steps, a timeout error is shown and emulation does **not** resume automatically.

**Endless loops vs. HOLD:** Many overlay programs — stopwatches, counters, display animators — are intentional infinite loops. They run forever within the overlay and are stopped by resetting the calculator; they do not need a HOLD instruction. HOLD (`0x0C00`) is only needed for programs that perform a finite computation and want to hand control back to the normal ROM when done. If a program falls off the end of the overlay without looping or halting, the CPU continues into whatever ROM code follows `0x1FFF`, which is unlikely to be useful.

### Persistence across reset and model switch

The loaded file is **not** reset when you reset the calculator or switch between models — it stays loaded in the ASM overlay section. On a model switch the overlay is automatically re-injected into the new machine's ROM; it is only discarded if it is too large for the overlay area (which would be reported in the status line). There is a single loaded file shared across all models, not one per model.

This persistence makes it straightforward to use an ASM program that reads whatever is currently on the display:

1. **Select File** — load the `.asm` file once.
2. Reset the calculator to reach a clean state.
3. Type the input value on the keyboard.
4. Press **Run**.

### Error recovery

**Why "timed out before HOLD" happens:**

The timeout means the ROM's current instruction never generated a HOLD signal during the 8 192-step window. The two common causes are:

- **Calculator not in IDLE mode.** If the calculator is computing, executing a keypress, or anywhere other than the idle keyscan loop, the ROM code at that point may have no HOLD-generating instruction. The PREG redirect snaps execution to `0x1800`, the overlay's first instruction (typically a register initialisation like `MOV A.ALL,#0`) is not a HOLD source, and all 8 192 steps cycle there without result.
- **Unlucky digit-counter timing, even from IDLE.** The keyscan scan-all instruction generates HOLD on digit ticks 1–15 but *not* on digit 0 (the scan completion tick). If Run lands exactly at digit 0, no HOLD fires on that step, PREG snaps to `0x1800`, and the program is stuck there for the remainder of the limit.

**Fix:** Press **Reset** and then **Run** again. After a reset the ROM runs its startup routine and enters the IDLE keyscan loop, where HOLD is asserted on almost every step. The loaded file is preserved through the reset, so only Run needs to be pressed again. This works the large majority of the time; if it fails a second time, wait a moment for the display to settle and try once more.

### Status display

The ASM overlay section shows three lines of status information:

| Field | Content |
|-------|---------|
| **File** | Last-loaded filename, or `No file selected` |
| **Words** | Number of 13-bit words currently loaded |
| **Status** | Most recent action result (load success, run outcome, error message) |
