# Debug API Reference

This document describes the two-layer debug API available in the TI-59 emulator.

- **Layer 1 — CPU / trace API**: instruction-level tracing, disassembler (and core
  breakpoints, used only by the headless tools).
  Operates at the TMC0501 CPU level; useful for ROM debugging.
- **Layer 2 — Calculator API**: read/write data registers, program steps, and internal
  state at the TI-59 user level; useful for debugging calculator programs.

Both layers are thread-safe. The underlying C++ is in `TI59Machine` and
`TMC0501`; the debugger built on them — freeze/step, the panels' data, the LOG
— is in `Shared/` (`EmulatorSession`, `SessionController`, `DebugModel`) and
used by both apps: the Swift app through `EmulatorViewModel` →
`Bridge/TISessionController`, the Qt app through `Qt6/app/EmulatorController`.
See `reference/SharedArchitecture.md`.

This reference is API-focused. For user-facing debug-pane behavior (LIVE/CPU/LOG, controls, workflows), see the user guide: https://www.calcu59.ch

---

## Partition System

The TI-59 divides its 120 × 16-nibble RAM between program storage and data registers
using the `n OP 17` key sequence. This is the fundamental context for every debug
operation.

### Formula

```
n OP 17  →  programRAMregs = (12 − n) × 10
           totalSteps      = programRAMregs × 8
           dataRegs        = n × 10          (R00 … R(n×10 − 1))
```

| n  | Steps (last shown) | Data registers (last shown) |
|----|--------------------|-----------------------------|
|  0 | 959                | none                        |
|  1 | 879                | R00–R09                     |
|  2 | 799                | R00–R19                     |
|  3 | 719                | R00–R29                     |
|  4 | 639                | R00–R39                     |
|  5 | 559                | R00–R49                     |
|  6 | 479 ← **default** | R00–R59                     |
|  7 | 399                | R00–R69                     |
|  8 | 319                | R00–R79                     |
|  9 | 239                | R00–R89                     |
| 10 | 159                | R00–R99                     |

### RAM layout

Data registers are stored **top-down** from the end of RAM:

```
R00 = RAM[119]
R01 = RAM[118]
Rnn = RAM[119 − nn]
```

Program steps are stored **bottom-up** from the start of RAM.  Eight steps per
RAM register, two nibbles per step (units at even nibble, tens at odd nibble):

```
step s → RAM register  s / 8
          nibble       (s % 8) * 2       (units digit of keycode)
          nibble       (s % 8) * 2 + 1   (tens  digit of keycode)
```

### SCOM partition encoding

The ROM stores the current partition in two SCOM locations (discovered empirically
by diffing SCOM across multiple `n OP 17` operations):

| Location   | Value                        |
|------------|------------------------------|
| SCOM[9][0] | `programRAMregs / 10`        |
| SCOM[13][8]| `(programRAMregs / 10) % 10` (BCD LSD) |
| SCOM[13][9]| `(programRAMregs / 10) / 10` (BCD MSD) |

`TI59Machine::partitionProgramRegs()` / `setPartitionProgramRegs()` read and write
these SCOM nibbles directly — no key simulation required.

---

## Calculator-Level API (Layer 2)

These are `TI59Machine` (Core) and Shared helper functions; neither app
exposes them to its GUI code directly — the debug panels read what
`DebugModel` builds from them (see below).

### Reading state

| Call | Returns |
|------|---------|
| `TI59Machine::copyRAMReg(reg, out16)` | A raw 16-nibble RAM register. `reg` is the **physical** index (0 … `ramRegCount()` − 1); data register Rnn is `119 − nn` on the TI-59 |
| `TI59Machine::readProgramStep(step)` | One program-step keycode |
| `cu59::programSteps(m)` (`Shared/DebugSnapshots.hpp`) | All steps of the current partition (clamped to physical RAM) |
| `TI59Machine::partitionProgramRegs()` | RAM registers allocated to program storage (SCOM[9][0] × 10) |
| `TI59Machine::snapshotCPU()` | A `CpuFrame` of all CPU registers (A–E, SCOM, KR, SR, fA, fB, …) at this instant; safe while the run loop runs. Identity fields (pc, opcode, seqno) are not meaningful here |
| `TI59Machine::printerBufferContent()` | Characters in the 20-character printer accumulator not yet printed |

### Writing state

| Call | Effect |
|------|--------|
| `TI59Machine::writeRAMReg(reg, nibbles16)` | Write a raw 16-nibble RAM register (physical index) |
| `TI59Machine::writeProgram(keycodes, count)` | Write program steps from step 0 (one byte per step, 0–99) |
| `TI59Machine::writeDataRegister(regNum, nibbles16)` | Write data register Rnn; encode values with `cu59::encodeBcd` (`Shared/Bcd.hpp`) |
| `TI59Machine::setPartitionProgramRegs(n)` | Set the partition by writing the SCOM nibbles; `n` is a multiple of 10 in [0, 120] |

Writes are made with the run loop stopped (`EmulatorSession::sync`), as
`Shared/StateApplier.cpp` does.

### BCD encoding

Data registers use a 16-nibble serial-BCD format:

```
nibble[0]    sign flags:   bit 1 = mantissa sign (1=negative), bit 2 = exponent sign (1=negative)
               0 (0b0000) = +mantissa, +exponent
               4 (0b0100) = +mantissa, −exponent
               2 (0b0010) = −mantissa, +exponent
               6 (0b0110) = −mantissa, −exponent
nibble[1]    exponent magnitude LSD  (decimal units, 0–99)
nibble[2]    exponent magnitude MSD  (decimal tens,  0–99)
nibble[3]    mantissa LSD
…
nibble[15]   mantissa MSD
```

Exponent is stored as an unsigned magnitude (0–99); the sign is encoded in nibble[0] bit 2.
All-zero encodes 0.0.

Helpers: `cu59::encodeBcd(double)` / `cu59::encodeBcd(std::string_view)` (in `Shared/Bcd.hpp`)
and `TI59Machine::decodeBCD`.

---

## Freeze / Step Controls

The debug panels can pause the emulator at a keycode boundary (CALCULATOR) or
an instruction (CPU), letting you inspect and single-step program execution.
The freeze state lives in `Shared/EmulatorSession`; `Shared/SessionController`
wraps it for the apps and rebuilds the panels' data (`DebugModel`). Both apps
call the controller (Swift: `EmulatorViewModel.freeze(from:)`, `unfreeze()`,
`freezeOnNextPCChange()`, `freezeOnScanLoopExit()`, `stepKeycode()`,
`stepFrozen()`; Qt: `EmulatorController`).

### `DebugState` (`EmulatorSession::debugState()`)

| Field | Description |
|-------|-------------|
| `frozen` | Emulation is halted |
| `owner` | `FreezeOwner::Cpu` or `::Calculator` — the panel whose RESUME / STEP apply; empty when running |
| `pcChangeArmed` | CALCULATOR "FREEZE ON START": freeze before the next program byte executes (at the next step boundary, `TI59Machine::kStepBoundary`, where a STEP stops too) |
| `scanLoopExitArmed` | CPU "FREEZE ON START": freeze when the CPU leaves the keyboard scan loop (key press or reset) |
| `generation` | Bumped on every freeze, resume and clear, so a view built for an earlier freeze can be recognised |

The two armed freezes are mutually exclusive (arming one disarms the other);
freezing disarms both. The controller mirrors the state
(`SessionController::debugState()`) and reports changes as `RunStateChanged`;
Swift copies it into `isFrozen`, `freezeOwner`, `pendingFreezeOnPCChange` and
`pendingCPUScanLoopFreeze`.

### Methods (`EmulatorSession`, UI thread)

| Method | Effect |
|--------|--------|
| `freeze(owner)` | Stop the loop, mark frozen; then on the emulation thread `stepUntilNextKeycode()` + `beginNextStep()` → `frozenViewReady(Freeze)` |
| `freezeInPlace(owner)` | Mark frozen where the stopped machine stands, no step (used by the ASM overlay's FREEZE ON START) |
| `resume()` | Unfreeze and start the run loop |
| `clearFreeze()` | Unfreeze without starting (caller stopped the loop to change state, e.g. a preset load) |
| `armPcChange()` / `disarmPcChange()` | CALCULATOR armed freeze; fires at the next step boundary; checked by `FreezeController::checkStep` per instruction |
| `armScanLoopExit()` / `disarmScanLoopExit()` | CPU armed freeze; checked by `FreezeController::checkStep` per instruction |
| `stepKeycode()` | While frozen: `stepUntilNextKeycode()` (runs to the next step boundary, `TI59Machine::kStepBoundary`: one program byte per STEP, as SST; a jump completes in the byte that causes it) + `beginNextStep()` → `frozenViewReady(StepKeycode)` |
| `stepInstruction()` | While frozen: one `step()`, repeated (≤ 32) while the PC stays put — a HOLD (`WAIT Dn`) — then `beginNextStep()` → `frozenViewReady(StepInstruction)` |
| `setCpuPanelVisible(bool)` | The CPU panel needs the trace ring |

`SessionController` has the same calls (`freeze`, `resume`, `armPcChange`,
`armScanLoopExit`, `disarm…`, `stepKeycode`, `stepInstruction`) plus
`setLiveDebugEnabled` / `setCpuDebugEnabled` for panel visibility.

### Threading

- Freezes and steps run on the emulation thread as posted jobs (the job queue
  is serial, so they run after the loop has exited).
- An armed freeze fires in the run loop; `EmulatorSession` applies it
  (frozen, owner, new generation; for a CALCULATOR freeze also
  `beginNextStep()`) on the emulation thread **before** any listener runs, so
  the key sequencer never sees a stopped machine as running. Then
  `Listener::debugStateChanged()` and `frozenViewReady(generation, FreezeFired)`.
- `frozenViewReady` hops to the UI thread (`Platform::runOnUiThread`).
  `SessionController::onFrozenView` builds the view (`DebugModel::frozenView`)
  only if the session is still frozen with the same `generation` — a RESUME or
  new freeze that came first makes the view stale and it is dropped (the
  machine may already be running). Events from a replaced session (model
  switch) are dropped too.
- Trace flags are computed inside the session by `traceFlagsFor(TraceConsumers)`
  (CPU panel visible, frozen, an armed freeze, manual or scripted trace →
  `TRACE_PC | TRACE_REGS_FULL`, otherwise `TRACE_NONE`) and set on every change.

### What a frozen view rebuilds

`DebugModel::frozenView(m, model, reason)`:

- CALCULATOR snapshot and program listing — except for `StepInstruction`.
- CPU history (`inspectorHistory`) — always.
- **SolidStateReturn rule:** if the program source is
  `ProgramSource::SolidStateReturn` (PRG SOURCE `2`: SCOM[0] holds a raw CROM
  return address, not a step), the listing is kept. A listing is never rebuilt
  from a SolidStateReturn snapshot. (A STEP or CALCULATOR freeze stops at the
  step dispatch, after the RTN has reset the source to 1, so it doesn't arise
  there.)

Showing the CALCULATOR panel while frozen rebuilds its snapshot at once
(`DebugModel::rebuildLive`), since the frozen view may predate it.

The listing is built only while frozen (only a frozen panel shows it), and
reported with its own change bit, `SessionController::ListingChanged`, so the
60 Hz running snapshot never carries the whole program across the bridge.

### Frozen-display semantics

The CALCULATOR tab shows the program position **pre-execution**, as the
calculator's LRN display does: `currentStep` in `LiveDebugSnapshot` is the
next step to execute, marked `← next` when frozen (`← running` while running;
`cu59::currentStepMarker`). The registers, flags, X and T shown with it are
the state before that step runs.

The tab only ever shows calculator-level boundaries, running or frozen. The
CPU latches its state at each one (`TMC0501::noteStepBoundary`,
`TI59Machine::lastStepBoundary()`), and `cu59::calcViewState` hands the latest
latch to `buildLiveSnapshot`, never the CPU mid-operation:

- **step boundary**: the next instruction is the interpreter's step dispatch
  (`0837` TI-59/58, `082B` TI-58C), once per executed program byte from RAM,
  a module or the constant-ROM keycode table. `step()` reports it with the
  bit `kStepBoundary`; STEP (`stepUntilNextKeycode`) and the armed CALCULATOR
  freeze stop on that bit, the only place it is detected.
- **idle entry**: `0624` in both ROMs, where the ROM falls into the idle loop
  after a keyboard operation or when a program stops (latched, no bit).

The CPU tab samples the CPU continuously, instruction by instruction.

- User programs and ROM keycode programs: the SCOM[0] step counter. At a
  step boundary it names the byte about to execute. At idle entry it names
  the last one, so the next is counter + 1 — except after RST or a jump,
  which leave the target in the counter with fB[11] (reload) set, so the
  next fetch reads it without advancing (`08B9`).
- Solid State: the library exec latch (`libExecPC`), the module byte fetched
  for dispatch at `LIB_EXEC_FETCH`. The chip's own address counter is not a
  program counter (one chip holds many programs; jumps and label searches
  reload it), so only the fetch is meaningful.

(The CPU tab is instruction-level and stays post-execution, see below.)

The frozen program window shows the whole listing of the current source
(`DebugModel::listing()`, `listingSource()`, `listingCurrentIndex()`; Swift
`programListing`, `programListingSource`, `programListingCurrentIndex`) and
scrolls to the current entry (the next step to execute).

---

## Live Debug Snapshot

`LiveDebugSnapshot` is a value type (`struct`) that carries a complete point-in-time
view of the calculator's user-visible and SCOM-derived state.  It is built in
C++ by `cu59::buildLiveSnapshot` (`Shared/DebugSnapshots.cpp`) and held by
`DebugModel` (`live()`) — rebuilt at 60 Hz while running and the CALCULATOR
panel is visible, and once per freeze / keycode step (see above), each time
from the last latched boundary (`calcViewState`). The Swift app
copies it (via `TILiveDebugSnapshot`) into `vm.liveDebugSnapshot` for
`LiveDebugView`; the Qt app reads it from the controller.

### Partition fields

| Field | Type | Description |
|-------|------|-------------|
| `programRegCount` | `Int` | RAM registers allocated to program storage (from SCOM[9][0]) |
| `dataRegCount` | `Int` | Displayable data registers (varies by model) |

### Program steps

| Field | Type | Description |
|-------|------|-------------|
| `programWindow` | `[StepEntry]` | ±5 steps around `currentStep` when running; not used when frozen (the full listing is used instead) |
| `currentStep` | `Int` | The next step to execute (decoded program counter, or the solid-state fetch latch); −1 = unknown |

`StepEntry` fields: `stepNum: Int`, `keycode: UInt8`, `mnemonic: String`, `isCurrent: Bool`.

The program source (RAM vs. ROM) is selected by `prSourceFlag`:

| `prSourceFlag` | Source | Steps decoded from |
|----------------|--------|--------------------|
| `0` | User RAM | `cu59::programSteps(m)` |
| `8` | Main ROM constants | `TI59Machine::readROMKeycode` (indices 0–383; `cu59::romKeycodes` in `Shared/DebugSnapshots.hpp`) |

### HIR registers (SCOM[1..8])

The eight hierarchy registers are decoded as `Double` values from their 16-nibble
BCD representation in SCOM rows 1–8.

| Field | SCOM row | Description |
|-------|----------|-------------|
| `hir[0]`–`hir[7]` | SCOM[1]–SCOM[8] | Hierarchy registers 1–8 |

Each HIR nibble layout: bits 15–3 = mantissa, 2–1 = exponent, 0 = sign (same
format as data registers).

### T register

| Field | SCOM row | Description |
|-------|----------|-------------|
| `tRegister` | SCOM[11] | Stack top / last-X equivalent; decoded as `Double` |
| `xValue`, `xRaw` | C or A, fA/fB | X, the working value, at a keystroke boundary: with a result on display (fB[5]) C normalized (nibble 0 = 0xC), signs fB[2]/fB[3]; otherwise X is in A with signs fA[2]/fA[3]: normalized (nibble 0 = 0xC) at the first step of a keycode sub-program such as P→R, whose launch leaves NUM_NORM's working copy there; else the entry image of a number being typed (digits 15–3, exponent 2–1, digits after the point in 0), at idle shifted back two places when B's exponent field is set (ROM `0662`; at the step dispatch the run loop has already done so at `07C1`). Shown with all 13 digits before T as `X:`; when the register holds no number (mid-calculation, LRN mode, fast mode) `xRaw` is `"C=…"`/`"A=…"` (nibble 15 first) and the line is amber |

### Calculator flags (SCOM[0] nibbles 11–15)

`calcFlags: [Bool?]` has 10 entries (indices 0–9).  Mapping:

| Flag | Nibble | Bit |
|------|--------|-----|
| F0–F4 | 11–15 | bit 0 (value 1) |
| F5–F9 | 11–15 | bit 1 (value 2) |

```
Flag N → nibble (11 + N % 5), bit (1 if N < 5 else 2)
```

### SCOM[0] scalar fields

| Field | Source | Description |
|-------|--------|-------------|
| `fixIndicator` | nibble 0 | `"-"` when raw == 0; otherwise `(raw − 2) % 10` as a decimal string |
| `statusRegister` | nibbles 15–0 | The whole status register (HIR 0) as 16 lowercase hex digits, nibble 15 first; the DEBUG row shows it as `HIR0:` |
| `fA` | FA register | FA register raw value (16-bit); bit 1 of nibble 1 = `2nd`, bit 0 = `INV` |
| `fB` | FB register | FB register raw value (16-bit); bit 3 of nibble 2 = ENG mode |
| `secondIndicator` | fA nibble 1 bit 1 | `"2nd"` when set, `""` otherwise |
| `invIndicator` | fA nibble 1 bit 0 | `"INV"` when set, `""` otherwise |
| `engIndicator` | fB nibble 2 bit 3 | `"Eng"` when set, `""` otherwise |

### Angle mode (SCOM[13][0])

| `angleMode` | Nibble value | Description |
|-------------|--------------|-------------|
| `.deg` | `0x0` | Degrees |
| `.grad` | `0x1` | Gradians |
| `.rad` | `0xC` | Radians |
| `nil` | other | Unknown / transitional state |

### Control state

| Field | Source | Description |
|-------|--------|-------------|
| `prSourceFlag` | SCOM[0] nibble 3 | `0` = user RAM, `1` = library, `2` = library return pending (see below), `8` = main ROM |

**Value `2` — solid-state return (PC reload):** transitional state lasting one
keycode dispatch. When a library program's context is saved (e.g. it invokes a
main-ROM keycode routine such as P→R, or does an SBR), the firmware reads the
4-digit CROM program counter via `IN LIB_PC` (ROM 0DAF) and pushes a return
level whose source nibble is the literal `2` (ROM 0DA9). The RTN handler (ROM
1175–1192) pops that level verbatim into SCOM[0]: source → nibble 3, saved CROM
address → nibbles 4–7 (plain BCD, *not* a step number). On the next dispatch
the firmware sees `2`, reloads the CROM PC from those nibbles via `OUT LIB_PC`,
and rewrites the flag to `1`. While `2` is active the debug panel keeps showing
the previously displayed listing with the highlight on the just-executed RTN
(see "What a frozen view rebuilds").
| `pendingOpsCount` | SCOM[13][0] | Number of pending operations in hierarchy stack (exact bit position TBD) |

### SCOM display

| Field | Type | Description |
|-------|------|-------------|
| `scomRows` | `[String]` | All 16 SCOM rows as 16-character lowercase hex strings (nibble[0] first) |

### Return address stack (SCOM[14:15])

The ROM stores up to 6 levels of subroutine return addresses in SCOM rows 14–15.

**Layout:**

```
SCOM[15][0]   count         number of active return levels (0–6)
SCOM[15][1..5]   Level 1   nibble[1] = PRG SOURCE; nibbles[5:2] = address (Base-80, right-to-left)
SCOM[15][6..10]  Level 2   same format
SCOM[15][11..15] Level 3   same format
SCOM[14][1..5]   Level 4   same format
SCOM[14][6..10]  Level 5   same format
SCOM[14][11..15] Level 6   same format
```

**Address decode:**

```
address = n[5]×800 + n[4]×80 + n[3]×8 + n[2]
```

(Same Base-80 encoding as the program counter in SCOM[0].)

**`LiveDebugSnapshot` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `returnAddresses` | `[Int]` (6 elements) | Decoded address for each level (L1 at index 0) |
| `returnAddressSourceFlags` | `[UInt8]` (6 elements) | PRG SOURCE flag for each level |

**Source flag colours in the UI:**

| Value | Source  | Colour |
|-------|---------|--------|
| `0`   | RAM     | Green  |
| `1`   | Library | Purple |
| `2`   | Library (saved CROM return address) | Purple |
| `8`   | ROM     | Yellow |

---

### Debug output API (LOG tab)

The LOG is a `RingLog` (`Shared/DebugLog.hpp`, 2000 lines) held by
`DebugModel`; it is kept across model switches. `SessionController` writes
the dumps into it and refreshes `logText()` at 1 Hz (Swift:
`vm.debugDisplayText`).

| `SessionController` (Swift `EmulatorViewModel`) | Shared formatter | Output |
|---------------|------------------|--------|
| `dumpVars()` (`debugDumpVars()`) | `cu59::dumpVars` | Non-zero data registers within the current partition |
| `dumpScom()` (`debugDumpSCOM()`) | `cu59::dumpScom` | All 16 SCOM rows as hex nibble strings (`S00 0000000000000000`), nibble[15] first |
| `dumpProg()` (`debugDumpProg()`) | `cu59::dumpProg` | Program RAM registers as raw nibble pairs in storage order (`R00: 67 11 24 00…`) |
| `dumpMemory()` (`debugDumpMemory()`) | `cu59::dumpMemory` | Entire RAM: non-zero registers only, physical indices (`R000:`, …); same format as `ti58c.mem` |
| `dumpStepCounterAnalysis()` (`debugDumpStepCounterAnalysis()`) | `cu59::dumpStepCounterAnalysis` | Step-counter analysis |
| `cycleDebugLevel()` / `clearLog()` (`toggleDebug()` / `clearDebug()`) | — | Cycle debug level (OFF→INFO→DEBUG→OFF); clear the log |

`debugLevel()` is `DebugLevel::Off`, `Info` or `Debug`; it is passed to the
core (`TI59Machine::setDebugLevel`). New output from Shared code goes through
`SessionController::log(lines)` (or `EmulatorSession::Listener::logLine`).

---

### C-core debug events

The CPU core (`TMC0501`) can emit `DebugEvent` messages that are drained in
the 60 Hz frame and appended to the LOG — no manual polling required.

#### Mechanism

1. `TMC0501::emitDebug(level, fmt, ...)` — appends a `DebugEvent` to an internal
   vector.  The call is a no-op when `level > m_debugLevel`, so there is zero
   overhead when the panel is OFF or at a lower level.
2. `TI59Machine::drainDebugEvents()` — called by `FrameSampler::tick`
   (`EmulatorSession::tick`); swaps and returns the accumulated events, keeping
   those at or below the current level.
3. `SessionController::tick` writes the lines into the LOG ring.

#### Levels

| C constant | Value | Shown when button is |
|-----------|-------|----------------------|
| `1` (INFO)  | 1 | INFO or DEBUG (orange or red) |
| `2` (DEBUG) | 2 | DEBUG only (red) |

#### Adding output in C

Inside any `TMC0501` member function, call:

```cpp
emitDebug(2, "MY_OP target=%d value=%s", addr, fmtNibs(data, buf));
```

- Use level `2` (DEBUG) for high-frequency per-instruction events such as
  register writes.  Use level `1` (INFO) for infrequent events such as
  mode changes.
- `fmtNibs(const uint8_t* d, char* buf, bool reverse = false)` is a file-local
  helper in `TMC0501.cpp` that formats 16 nibbles into a 17-byte char buffer.
  Pass `reverse = true` to print nibble[15] first (MSD-first, as used for SCOM).
- The message buffer is 80 characters; `vsnprintf` silently truncates longer strings.
- `emitDebug` may only be called from `TMC0501` member functions — it is private.
  To emit events from `TI59Machine`, add a public helper or call through `m_cpu`;
  Shared code logs through `SessionController` instead.

#### Current DEBUG-level events

| Message format | Trigger |
|----------------|---------|
| `STO SCOM[NN] = XXXXXXXXXXXXXXXX` | SCOM register written (STO / STOF / STOG), nibble[15] first |
| `MEMWR RAM[NNN] = XXXXXXXXXXXXXXXX` | RAM register written (MEMWR instruction or RAM_OP write), nibble[0] first |
| `RAM_OP CLR1 RAM[NNN]` | RAM_OP clear-1 (op=2) |
| `RAM_OP CLR10 RAM[NNN]` | RAM_OP clear-10 (op=4) |

---

## CPU / Trace API (Layer 1)

### Trace flags

Set with `TI59Machine::setTraceFlags` (`Core/TraceTypes.hpp`). In the apps only
`EmulatorSession` sets them, from `traceFlagsFor(TraceConsumers)`: any consumer
(CPU panel visible, frozen, an armed freeze, manual or scripted trace) gives
`TRACE_PC | TRACE_REGS_FULL`, none gives `TRACE_NONE` (the fast path).

| Flag | Cost | Records |
|------|------|---------|
| `TRACE_PC` | Low | pc, opcode, digit, cycleWeight, seqno |
| `TRACE_REGS_LIGHT` | Medium | adds KR, SR, fA, fB, R5, cpuFlags |
| `TRACE_REGS_FULL` | High | adds A–E, SCOM[16][16], Sout |
| `TRACE_BREAKPOINTS` | Low | armed breakpoint check per step (headless tools only) |

### CpuFrame fields

A unified `CpuFrame` struct combines all CPU state into one 397-byte structure,
eliminating the parallel TraceEvent + CPUSnapshot mismatch risk.

All emitted `CpuFrame` entries (UI and binary trace) use post-execution semantics.
`COND` is finalized after jump-chain auto-restore handling and then written into
the previous frame together with the rest of the CPU state.

**Identity fields (always captured):**
```
seqno         monotonically increasing; gaps indicate ring overflow
pc            ROM address of the instruction
opcode        13-bit word fetched from ROM
digit         digit-counter value (0–15) when the instruction ran
cycleWeight   1 (active) or 4 (idle)
```

**Light registers (captured when TRACE_REGS_LIGHT is set):**
```
KR, SR        address / return registers
fA, fB        flag registers A and B
cpuFlags      internal CPU flags (bit 0 = IDLE, bit 11 = COND)
R5            4-bit scratch / decimal-point pointer
```

**Full snapshot (captured when TRACE_REGS_FULL is set):**
```
A, B, C, D, E 16-nibble working registers (index 0 = LSN)
SCOM[16][16]  serial common I/O memory
Sout[16]      printer output register
EXT           exponent register
PREG          pointer register (4-bit)
m_libAddr     ROM address pointer (master library)
m_libAddrReadPos nibble sub-address within ROM word
REG_ADDR      register address for current operation
RAM_ADDR      RAM address for current operation
RAM_OP        RAM operation code
dispFilter    display blanking filter counter (0–3; ≥3 = blanked during compute)
```

### Breakpoints

Core breakpoints (`TI59Machine::addBreakpoint`, `TRACE_BREAKPOINTS`, step
bit 31) are used only by the headless tools (`tools/headless/`). Neither app
sets them; the run loop just stops if one is hit.

### CPU Inspector

The CPU tab shows instruction-level execution history with post-execution
register snapshots. One list, `DebugModel::cpuHistory()`, serves both modes:

- **Running** (CPU panel visible): the newest 32 instructions,
  `cu59::recentInstructions(readTraceRing(m))`, the last one current —
  rebuilt in the 60 Hz frame only when the ring's newest `seqno` changed.
- **Frozen**: `cu59::inspectorHistory(m)` on every freeze and step — every
  frame still in the trace ring (read, not drained, up to 1024) plus the
  certain next instruction (`isHistory = false`, zeroed frame), shown even at
  the same PC (WAIT/KEY loops re-execute one instruction).

Both are in `Shared/DebugSnapshots.hpp`:

```cpp
struct InspectorEntry {
    uint16_t pc;
    uint16_t opcode;
    std::string disasm;
    CpuFrame frame;   // state AFTER the instruction (zeroed for the next one)
    bool isHistory;   // executed; false for the next instruction
    bool isCurrent;   // the last executed instruction
};
```

The Swift app receives them as `TIInspectorEntry` (`Bridge/TISessionController.h`,
frame as `TICpuFrame` from `Bridge/TITypes.h`) and copies them into
`vm.cpuHistory` (`[InspectorSnapshot]`); `vm.cpuHistoryUpdateID` is
incremented on every change, which `CPUInspectorView` observes to scroll to
the current entry. The ROM heatmap (`DebugModel::heatmapCounts()`, Swift
`vm.romHitCount`) is fed from the same ring reads.

### Disassembler

```cpp
static std::string TI59Machine::disassemble(uint16_t pc, uint16_t opcode);
```

Pure function — requires no machine state. Returns a mnemonic string for any
13-bit opcode, e.g. `"ADD A, C [MANT]"` or `"BR 0x03A2"`.

### ASM Overlay

Injects raw TMC0501 machine code into a debug-only ROM region and executes it
in a single synchronous burst — intended for ROM-level experimentation:
testing small snippets, probing CPU behavior, or exercising the emulator with
precisely crafted instruction sequences. Core entry points:
`TI59Machine::loadDebugOverlay` / `clearDebugOverlay` / `runDebugOverlay`;
the shared flow is `cu59::parseAsmWords` and `cu59::runAsmOverlay`
(`Shared/AsmOverlay.hpp`) driven by `SessionController::loadAsm` / `runAsm` /
`clearAsm`. If the CPU's FREEZE ON START is armed, Run freezes in place at
the `0x1800` entry (`freezeInPlace(FreezeOwner::Cpu)`) instead of running.

**Address range.** The overlay occupies ROM addresses `0x1800–0x1FFF` (2048
words), outside the TI-59's normal ROM and reserved for debug use. 16-bit
file words are masked to 13 bits (`& 0x1FFF`) before being written.

**File format.** `.asm` files with two sections; example programs derived
from Hynek Sladký's *Calculators TI-58/59 HW Programming Guide* live in
`examples/assembly/` (see that directory's own `README.md` for the loader's
exact tokenizing rules).

```
PROGRAM:
; human-readable assembly listing, ignored entirely by the loader
1800:   01D8    MOV     A.ALL,#0
        ...

HEX:
01D8 01DB 0D00 0A37 1805 1007
```

The `HEX:` marker line is where the loader starts parsing; everything before
it (including the whole `PROGRAM:` section) is free-form and ignored. Within
`HEX:`, both `0xHHHH` (explicit prefix) and bare 4-hex-digit runs are
accepted; all other characters are skipped. Max 2048 words; no `HEX:` section
is a load error.

**Run semantics.** Run hijacks the ROM's HOLD mechanism rather than jumping
to `0x1800` directly: the emulator forces `PREG = 0x1800` on every step and
waits for the ROM's *currently executing* instruction to assert HOLD (raised
naturally by the keyscan scan-all instruction on digit ticks 1–15, and by
`WAIT Dn` instructions). The moment HOLD fires, `addr` snaps to `0x1800` and
normal emulation resumes from there, running the overlay sequentially in real
time. A run that finds no HOLD within 8,192 steps times out with no state
change — the two common causes are the calculator not being in the IDLE
keyscan loop when Run is pressed, or landing on digit-counter tick 0 (the one
scan-all tick that doesn't assert HOLD). Reset then Run again resolves both,
since the ROM's startup routine always lands in the IDLE loop where HOLD
fires on nearly every step.

Endless-loop overlay programs (stopwatches, counters, animators) don't need a
HOLD instruction at all — they run forever until the calculator is reset.
`0x0C00` (HOLD) is only needed when an overlay program wants to hand control
back to normal ROM execution on completion.

**Persistence.** The loaded overlay survives calculator reset and model
switch (re-injected into the new machine's ROM on switch, discarded only if
too large for that variant's overlay area) — one loaded file shared across
all models, not one per model. This makes "load once, reset, type an input,
Run" a stable workflow for overlay programs that read the current display
state.

---

## Trace File Format (CALCU59_TRACE.bin, CALCU58_TRACE.bin, CALCU58C_TRACE.bin)

The binary trace file captures instruction-level CPU state at 60 Hz. It is used by
`tools/read_trace.py` to generate human-readable logs and JSON exports.

**Version Stability:**
- **v1** (released in v1.0.0): Stable and backwards-compatible. Breaking changes require major version bump.
- **v2+** (after v1.0.0): Volatile. May change without backwards-compatibility guarantees between v2 revisions.
  Implementations should upgrade conservatively and handle both versions.

### File Structure

```
[File Header (16 bytes)]
[Record 1 (3 + N bytes)]
[Record 2 (3 + N bytes)]
...
[Record N (3 + N bytes)]
```

### File Header (16 bytes)

**Version 1 (released in v1.0.0, stable):**
```
Offset  Size  Type   Field        Description
0       4     LE U32 magic        Magic: 0x54493539 ('TI59' in little-endian ASCII)
4       2     LE U16 version      Format version: 1
6       10    —      reserved     Reserved; ignore for forward compatibility
```

**Version 2 (volatile, may change without backwards-compat guarantees):**
```
Offset  Size  Type   Field        Description
0       4     LE U32 magic        Magic: 0x54493539 ('TI59' in little-endian ASCII)
4       2     LE U16 version      Format version: 2
6       2     LE U16 model        Calculator model: 0=TI-59, 1=TI-58, 2=TI-58C
8       8     —      reserved     Reserved; ignore for forward compatibility
```

### Record Structure

All records follow a 3-byte header:

```
Offset  Size  Type   Field           Description
0       1     U8     type            Record type (see table below)
1       2     LE U16 payload_length  Length of payload in bytes (0 allowed)
3       N     —      payload         Type-specific data (N = payload_length)
```

### Record Types

| Type | Name              | Payload (v1 / v2+) | Purpose |
|------|-------------------|--------------------|---------|
| 0x01 | SESSION_START     | 8 / 9 bytes | Session boundary marker with optional model |
| 0x02 | TRACE_EVENT       | 125 bytes | Unified CPU frame snapshot (combined instruction + state) |
| 0x03 | SESSION_END       | 8 bytes | Session terminator with counts |
| 0x04 | USER_EVENT        | ≥4 bytes | User input (key press, card insert) |
| 0x05 | TRACE_GAP         | 4 bytes | Ring overflow marker: UInt32 LE count of lost frames |

Unknown record types are silently skipped (forward-compatible).

### Record Type Details

#### SESSION_START (0x01)

Marks the start of a trace session (e.g., app launch or emulator reset).

**Payload v1 (8 bytes):**

```
Offset  Size  Type   Field       Description
0       8     LE U64 timestamp   Unix timestamp (seconds since epoch) when session began
```

**Payload v2+ (9 bytes):**

```
Offset  Size  Type   Field       Description
0       8     LE U64 timestamp   Unix timestamp (seconds since epoch) when session began
8       1     U8     model       Calculator model: 0=TI-59, 1=TI-58, 2=TI-58C
```

#### TRACE_EVENT (0x02)

Captures a unified CPU frame (instruction + full state) at a single instruction.
**Payload is exactly 124 bytes.** (v1 baseline; any future changes require binary format version increment).

Frame state is post-execution for the recorded instruction.

**Fixed fields (first 36 bytes):**

```
Offset  Size  Type   Field              Description
0       4     LE U32 suppressed         Instruction count suppressed before this event
4       4     LE U32 seqno              Monotonically increasing sequence number; gaps = ring overflow
8       2     LE U16 pc                 ROM address (0–0xFFF)
10      2     LE U16 opcode            13-bit instruction (upper 3 bits unused)
12      2     LE U16 fA                Flag register A (16-bit bitmask)
14      2     LE U16 fB                Flag register B (16-bit bitmask)
16      2     LE U16 KR                Address register (16-bit)
18      2     LE U16 SR                Return address register (16-bit)
20      2     LE U16 EXT               Exponent register, upper nibble at bits 12–15
22      2     LE U16 PREG              Pointer register (4-bit)
24      2     LE U16 cpu_flags         Internal CPU flags (bit 0 = IDLE, bit 11 = COND)
26      2     LE U16 m_libAddr         ROM address pointer (absolute offset in ROM)
28      1     U8     R5                Scratch/decimal pointer (4-bit)
29      1     U8     digit             Digit counter (0–15)
30      1     U8     RAM_ADDR          RAM address for current operation
31      1     U8     RAM_OP            RAM operation code
32      1     U8     REG_ADDR          Register address for SCOM/register ops
33      1     U8     m_libAddrReadPos  Sub-address within ROM word (nibble index)
34      1     U8     cycle_weight      Cycle weight (1 = active, 4 = idle cycle)
35      1     U8     dispFilter        Display blanking filter counter (0–3; ≥3 = blanked during compute)
```

**Register A–E (80 bytes):** Unpacked 16-bit nibble arrays (index 0 = LSN, index 15 = MSN).

```
Offset  Size  Type   Field    Description
36      16    U8[16] A_regs   Register A: 16 nibbles (index 0 = LSN)
52      16    U8[16] B_regs   Register B: 16 nibbles
68      16    U8[16] C_regs   Register C: 16 nibbles
84      16    U8[16] D_regs   Register D: 16 nibbles
100     16    U8[16] E_regs   Register E: 16 nibbles
```

Each nibble (4-bit value 0–15) occupies one byte.

**Output register Sout (8 bytes):** Nibble-packed (2 nibbles per byte).

```
Offset  Size  Type   Field    Description
116     8     U8[8]  sout     Printer output: nibbles packed as (high_nibble << 4) | low_nibble
                              sout[i] & 0x0F = Sout[2i], (sout[i] >> 4) = Sout[2i+1]
```

**Total payload:** 36 + 80 + 8 = 124 bytes.

**Flag bit definitions (cpu_flags):**

```
Bit  Name    Meaning
0    IDLE    1 = idle cycle (keyscan loop); 0 = active
11   COND    1 = condition code set; 0 = clear
```

#### SESSION_END (0x03)

Marks the end of a trace session (e.g., app quit or emulator pause).

**Payload (8 bytes):**

```
Offset  Size  Type   Field            Description
0       4     LE U32 eventCount       Total TRACE_EVENT records written in this session
4       4     LE U32 suppressedTotal  Deprecated; now always zero (dedup removed in v5; ring overflows
                                      are recorded via TRACE_GAP records instead)
```

#### USER_EVENT (0x04)

Records user input (keyboard, card insert/eject).

**Payload (≥4 bytes):**

```
Offset  Size  Type   Field    Description
0       1     U8     kind     Event kind (see table below)
1       1     U8     p1       Parameter 1 (row for KEY events)
2       1     U8     p2       Parameter 2 (col for KEY events)
3       1     U8     —        Reserved
```

**Kind codes:**

| Value | Label        | p1 | p2 | Meaning |
|-------|--------------|----|----|---------|
| 0x01  | KEY DOWN     | row| col| Key pressed (row=1–9, col=1–5) |
| 0x02  | KEY UP       | row| col| Key released |
| 0x03  | CARD INSERT  | —  | —  | Magnetic card inserted |
| 0x04  | CARD EJECT   | —  | —  | Magnetic card ejected |

#### TRACE_GAP (0x05)

Indicates that the ring buffer overflowed and some frames were lost.

**Payload (4 bytes):**

```
Offset  Size  Type   Field       Description
0       4     LE U32 lostFrames  Number of CPU frames that were overwritten in the ring
```

This record appears in the trace when the emulation runs faster than the trace drain
thread can write to disk, causing the 1024-frame ring buffer to wrap. The `seqno`
field in subsequent TRACE_EVENT records will have a gap showing exactly how many
frames were lost. When parsing, accumulate the loss counts to understand the true
instruction count across gaps.

### Parsing Notes

- **Byte order:** All multi-byte fields use little-endian unless stated otherwise.
- **Nibble representation:** Most fields use packed hex (one 4-bit value per byte for readability).
- **Ring buffer and overflow:** The trace ring holds up to 1024 unified CPU frames. When
  emulation runs faster than the trace drain thread, frames are lost. Lost frames are
  reported via TRACE_GAP records (type 0x05). Check for `seqno` gaps in TRACE_EVENT
  records to detect overflow; the gap size equals the number of lost frames.
- **Record types:** Unknown record types are silently skipped (forward-compatible).

---

## .ti59 State File Format

The file format grammar (sections, PARTITION formula and per-model defaults,
PROGRAM/REGISTERS notation, matrix codes, CUECARD fields) is documented in
`reference/StateFileFormat.md` — that document, not this one, is the format
reference. What's unique to this API doc is the exact call sequence
`SessionController::loadStateFile` (both apps) uses to apply a parsed file to
a live `TI59Machine`. It stops the run loop, clears any freeze
(`EmulatorSession::clearFreeze`), switches model first if the file asks for
another, and runs `cu59::applyState` (`Shared/StateApplier.cpp`) on the
emulation thread:

1. `reset()` — clears CPU state
2. `stepN(300'000)` — lets the ROM complete its power-on / master-clear routine
3. `setPartitionProgramRegs(…)` — sets the partition via SCOM (default 239 on
   the TI-58/58C when the file gives none)
4. RAM cleared with `writeRAMReg` — on the TI-58C keeping the extra registers
   (raw RAM 60–63), whose RAM[60] the ROM needs
5. `writeProgram(…)` — the program zero-padded to the model's physical capacity
6. Per register: normal registers via `writeDataRegister(…)`; the TI-58C's
   4 extra registers (H00–H03 — not normal registers "60"–"63", see
   `reference/CoreArchitecture.md` § "TI-58C Extra (Constant Memory) Registers")
   via `writeRAMReg(kExtraRegisterBase + regNum, …)` to bypass the reversed
   data-register mapping — the branch is driven by an explicit `isHidden` flag
   carried alongside each parsed register, never by testing whether
   `regNum >= 60` (ordinary TI-59 registers legitimately reach 99)

Then the controller restarts the loop, cuts the paper, applies module,
printer and cue card, persists TI-58C memory, and plays KEYSTROKES
asynchronously (`EmulatorSession::playKeystrokes`, `Shared/KeySequencer`).
`SKIP-RESET` files use `applySkipResetState` instead.

---

## TI-58C Constant Memory File Format (`ti58c.mem`)

The TI-58C emulator persists RAM contents between sessions in a human-readable text file called `ti58c.mem`.
`SessionController` loads it when a TI-58C machine starts and writes it (debounced) when RAM changes, through `Platform::readConstantMemory` / `writeConstantMemory`; each app chooses the location (Swift: next to the cards, `CardStorage.directoryURL`).

**Format:**
```
── Memory (non-zero registers) ──
R000: 67 11 96 00 10 00 00 96
R001: 10 20 00 00 00 30 00 00
R003: 60 00 00 96 30 70 00 00
R063: 24 00 79 10 21 19 00 00
```

**Rules:**

- Each line represents one 16-nibble register (8 bytes in hex)
- Format: `RXXX: HH HH HH HH HH HH HH HH` where XXX is the register number (000–063)
- Only non-zero registers are written to keep file size small
- Registers are specified in any order; gaps are initialized to zero on load
- All-zero registers can be omitted entirely
- Unspecified registers (0–63) silently initialize to zero

**Backward compatibility:**

Old binary `.mem` files (exactly 120 × 16 = 1920 bytes) are automatically detected and loaded.
If a load error occurs for any reason, the file is silently ignored and RAM initializes to all zeros.
