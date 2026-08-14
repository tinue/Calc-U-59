# Debug API Reference

This document describes the two-layer debug API available in the TI-59 emulator.

- **Layer 1 — CPU / trace API**: instruction-level tracing, breakpoints, disassembler.
  Operates at the TMC0501 CPU level; useful for ROM debugging.
- **Layer 2 — Calculator API**: read/write data registers, program steps, and internal
  state at the TI-59 user level; useful for debugging calculator programs.

Both layers are thread-safe. All Swift entry points live in `EmulatorViewModel`;
the underlying C++ is in `TI59Machine` and `TMC0501`.

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

Reading or writing `m.partitionProgramRegs` (Swift/ObjC) accesses these SCOM
nibbles directly — no key simulation required.

---

## Calculator-Level API (Layer 2)

### Reading state

#### `getCalcSnapshot() → CalcSnapshot?`

Returns a point-in-time snapshot of the calculator's user-visible state.
Returns `nil` if the machine has not yet started.

```swift
struct CalcSnapshot {
    var registers:    [Double]      // R00…Rnn per current partition
    var programSteps: [UInt8]       // keycodes 0–99; length = totalSteps
    var printerBuffer: String       // characters not yet committed to a line
    var cpu:          TICpuFrame    // raw CPU register state (unified frame struct)
}
```

#### `rawRegister(_ reg: Int) → [UInt8]?`

Read a raw 16-nibble RAM register. `reg` is the **physical** RAM index (0–119),
not the user-visible register number. Use `119 − nn` to address data register Rnn.

#### `machine.dataRegister(_ regNum: Int) → Double`  *(ObjC bridge)*

Read data register Rnn decoded as a Double. Equivalent to `RCL nn` on the keyboard.

#### `machine.allProgramSteps() → Data`  *(ObjC bridge)*

Read all program steps as raw keycodes. Length = `partitionProgramRegs × 8`.

#### `machine.snapshotCPU() → TICpuFrame`  *(ObjC bridge)*

Capture a unified snapshot of all CPU registers (A–E, SCOM, KR, SR, fA, fB, …) at the
current instant. Safe to call while the emulation loop is running. Returns the same
`TICpuFrame` struct used in the trace ring buffer, with identity fields (pc, opcode, seqno)
set to zero (not meaningful for standalone snapshots).

#### `machine.printerBufferContent → String`  *(ObjC bridge)*

Characters currently in the 20-character printer accumulator (not yet flushed
to a print line). Empty string when the buffer has been committed or is blank.

### Writing state

#### `setRawRegister(_ reg: Int, nibbles: [UInt8])`

Write a raw 16-nibble RAM register. `reg` is the physical index (0–119).
`nibbles` must be exactly 16 bytes.

#### `machine.writeProgramSteps(_ keycodes: Data)`  *(ObjC bridge)*

Write program steps from a byte array (one byte per step, value 0–99) starting
at step 0. Typically called after `stepN(300_000)` to let the ROM complete its
master-clear before overwriting program RAM.

#### `machine.writeDataRegister(_ regNum: Int, nibbles: Data)`  *(ObjC bridge)*

Write data register Rnn from 16 BCD nibbles. Use `encodeTI59BCD(_:)` in
`StateFileLoader.swift` to encode a Double.

#### `machine.partitionProgramRegs` (read/write)  *(ObjC bridge)*

Get or set the program/data partition boundary by reading/writing the SCOM
nibbles directly. Value is the number of RAM registers allocated to program
storage; must be a multiple of 10 in [0, 120].

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

Swift helpers: `encodeTI59BCD(_ value: Double) → [UInt8]` (in `StateFileLoader.swift`)
and `TI59MachineWrapper.decodeBCD(_ nibbles16: Data) → Double`.

---

## Freeze / Step Controls

The live debug panel can pause the emulator at a keycode boundary, letting you
inspect and single-step through program execution.

### State properties (`EmulatorViewModel`)

| Property | Type | Description |
|----------|------|-------------|
| `isFrozen` | `Bool` | `true` when emulation is halted (read-only; derived from `freezeReason`) |
| `freezeReason` | `FreezeReason?` | `nil` = running; non-nil = frozen (`.manual`, `.breakpoint`) |
| `pendingFreezeOnPCChange` | `Bool` | `true` when "FREEZE ON START" is armed; auto-clears on first PC change |

### Methods

#### `freeze(reason: FreezeReason = .manual)`

Stops the emulation loop and waits (on `emulQueue`) for the CPU to reach the next
keycode boundary.  On return, `isFrozen` is `true` and the following caches are
built once for the frozen view:

- `frozenRAMCache` — full user-RAM program listing with `isCurrent` markers
- `frozenROMCache` — full main-ROM listing (when `prSourceFlag == 8`)
- `cachedPrSourceFlag` — which cache is currently valid

#### `unfreeze()`

Clears `freezeReason` and all program caches, then restarts the emulation and
display refresh loops.

#### `freezeOnNextPCChange()`

Arms a one-shot freeze that fires as soon as the decoded program counter (from
SCOM[0] nibbles 4–7) changes.  The current decoded PC is recorded in
`lastObservedPC`; `pendingFreezeOnPCChange` is set to `true`.  The check runs
inside the 60 Hz tick loop.

#### `stepKeycode()`

Advances one keycode boundary while frozen.  After the step:

1. Rebuilds live debug and CPU inspector snapshots.
2. If `prSourceFlag` changed (e.g. a library call), the appropriate program cache
   is rebuilt and the other cache is cleared.
3. If `prSourceFlag` is unchanged, only the `isCurrent` markers are updated
   in-place (cheaper than a full rebuild).

### Frozen-display semantics

When frozen, `currentStep` and `nextStepNum` in `LiveDebugSnapshot` use the
following convention:

```
currentStep = decodedPC − 1   (last fully executed step)
nextStepNum = decodedPC       (next step to execute, from PC)
```

The frozen program window shows the full program listing (built once on freeze) and
scrolls to `currentStep` automatically.  The "next" step is rendered below the
current step with dimmed styling.

### Frozen program cache access

```swift
var frozenCachedProgram: [LiveDebugSnapshot.StepEntry]?  // nil when not frozen
var frozenCachedCurrentIndex: Int                         // index of isCurrent entry, or -1
```

---

## Live Debug Snapshot

`LiveDebugSnapshot` is a value type (`struct`) that carries a complete point-in-time
view of the calculator's user-visible and SCOM-derived state.  It is rebuilt by
`buildLiveSnapshot()` at 60 Hz when `vm.liveDebugEnabled` is `true`, and is also
captured once on each `freeze()` / `stepKeycode()` call.

The snapshot is stored in `vm.liveDebugSnapshot` and read by `LiveDebugView`.

### Partition fields

| Field | Type | Description |
|-------|------|-------------|
| `programRegCount` | `Int` | RAM registers allocated to program storage (from SCOM[9][0]) |
| `dataRegCount` | `Int` | Displayable data registers (varies by model) |

### Program steps

| Field | Type | Description |
|-------|------|-------------|
| `programWindow` | `[StepEntry]` | ±5 steps around `currentStep` when running; not used when frozen (full cache used instead) |
| `currentStep` | `Int` | Decoded program counter; −1 = unknown.  When frozen: last executed step (decodedPC − 1) |
| `nextStepNum` | `Int` | Step number of next-to-execute instruction (from PC when frozen); −1 when running |
| `nextStepKeycode` | `UInt8` | Keycode at `nextStepNum` |
| `nextStepMnemonic` | `String` | Mnemonic of `nextStepNum` |

`StepEntry` fields: `stepNum: Int`, `keycode: UInt8`, `mnemonic: String`, `isCurrent: Bool`.

The program source (RAM vs. ROM) is selected by `prSourceFlag`:

| `prSourceFlag` | Source | Steps decoded from |
|----------------|--------|--------------------|
| `0` | User RAM | `machine.allProgramSteps()` |
| `8` | Main ROM constants | `machine.romKeycode(at:)` (indices 0–383) |

### HIR registers (SCOM[1..8])

The eight hierarchy registers are decoded as `Double` values from their 16-nibble
BCD representation in SCOM rows 1–8.

| Field | SCOM row | Description |
|-------|----------|-------------|
| `hir1`–`hir8` | SCOM[1]–SCOM[8] | Hierarchy registers 1–8 |

Each HIR nibble layout: bits 15–3 = mantissa, 2–1 = exponent, 0 = sign (same
format as data registers).

### T register

| Field | SCOM row | Description |
|-------|----------|-------------|
| `tRegister` | SCOM[11] | Stack top / last-X equivalent; decoded as `Double` |

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
| `ioUserFlags` | nibbles 1–5 | Five IO user flag nibbles as a decimal string, e.g. `"00100"` |
| `lastKey` | nibbles 13–14 | Last key pressed as two-digit decimal string, e.g. `"67"` |
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
the previously displayed program (held frozen cache) with the highlight on the
just-executed RTN.
| `pendingOpsCount` | SCOM[13][0] | Number of pending operations in hierarchy stack (exact bit position TBD) |

### SCOM display

| Field | Type | Description |
|-------|------|-------------|
| `scomRows` | `[String]` | All 16 SCOM rows as 16-character lowercase hex strings (nibble[0] first) |
| `printerSCOM` | `[String]` | First 4 rows of `scomRows` (SCOM[0]–SCOM[3], the printer region) |

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

### Debug output API (ViewModel)

These append formatted lines to `vm.debugLines` (displayed in the LOG tab). Each
call accepts an implicit `level:` parameter (default `.info`); output is suppressed
when `vm.debugLevel < level`.

| Function | Description |
|----------|-------------|
| `debugDumpVars()` | Non-zero data registers within the current partition, shown as `R00 = 3.14159…` |
| `debugDumpSCOM()` | All 16 SCOM rows as hex nibble strings (`S00 0000000000000000`), nibble[15] first |
| `debugDumpProg()` | Program RAM registers R00–Rnn as raw nibble pairs in storage order (`R00: 67 11 24 00…`); length = `partitionProgramRegs` |
| `debugDumpMemory()` | Entire RAM: non-zero registers only, using physical indices (`R000:`, `R001:`, …); same format as `ti58c.mem` |
| `toggleDebug()` / `clearDebug()` | Cycle debug level (OFF→INFO→DEBUG→OFF); clear the log |

`vm.debugLevel: DebugLevel` — current level (`.off`, `.info`, `.debug`).
`vm.debugEnabled: Bool` — convenience; `true` when level ≠ OFF.

When adding new Swift-side debug output, call `debugAppend([...], level: .info)` or
`debugAppend([...], level: .debug)` as appropriate.

---

### C-core debug events

The CPU core (`TMC0501`) can emit `DebugEvent` messages that are drained by
`tick()` at 60 Hz and forwarded to the debug panel — no manual polling required.

#### Mechanism

1. `TMC0501::emitDebug(level, fmt, ...)` — appends a `DebugEvent` to an internal
   vector.  The call is a no-op when `level > m_debugLevel`, so there is zero
   overhead when the panel is OFF or at a lower level.
2. `TI59Machine::drainDebugEvents()` — called by the Swift tick loop under
   `m_keyMutex`; swaps and returns the accumulated events.
3. `tick()` in `EmulatorViewModel` decodes the level prefix and calls
   `debugAppend` with the matching `DebugLevel`.

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
  To emit events from `TI59Machine` or the Obj-C wrapper, add a public helper or
  call through `m_cpu`.

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

Set via `machine.traceFlags` property. The UI manages this automatically when
the trace window is opened/closed and when the full-registers toggle is clicked.

| Flag | Swift name | Cost | Records |
|------|------------|------|---------|
| `TRACE_PC` | `.pc` | Low | pc, opcode, digit, cycleWeight, seqno |
| `TRACE_REGS_LIGHT` | `.regsLight` | Medium | adds KR, SR, fA, fB, R5, cpuFlags |
| `TRACE_REGS_FULL` | `.regsFull` | High | adds A–E, SCOM[16][16], Sout |
| `TRACE_BREAKPOINTS` | `.breakpoints` | Low | armed breakpoint check per step |

Flags are combined: `[.pc, .regsLight]` is the default when tracing is enabled.

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

```swift
viewModel.addBreakpoint(_ pc: UInt16)
viewModel.removeBreakpoint(_ pc: UInt16)
viewModel.resumeFromBreakpoint()
viewModel.singleStep()
```

When a breakpoint is hit, the emulation loop stops and `isPausedOnBreakpoint`
becomes `true`. `breakpointPC` holds the address. Use `resumeFromBreakpoint()`
to continue or `singleStep()` to advance one instruction at a time.

### CPU Inspector

The CPU inspector provides a deep view of instruction-level execution history with
post-execution register snapshots.  It is active when the **CPU** tab is selected
and the emulator is frozen.

#### `CPUDebugSnapshot`

Stored in `vm.cpuDebugSnapshot`; rebuilt by `buildCPUDebugSnapshot()` at 60 Hz
when the CPU tab is active and the emulator is **running**.

```swift
struct CPUDebugSnapshot {
    struct Instruction {
        var pc:     UInt16    // ROM address
        var opcode: UInt16    // 13-bit instruction word
        var disasm: String    // disassembly mnemonic
    var frame:  TICpuFrame  // CPU state AFTER this instruction executed
    }
    var recentInstructions: [Instruction]  // last ≤32 instructions
    var currentPC:  UInt16
    var isPaused:   Bool
    var pausedPC:   UInt16?
}
```

Trace flags `[.pc, .regsFull]` are automatically enabled when this snapshot is
being built.

#### `InspectorSnapshot`

Used by `CPUInspectorView` (frozen mode only).  Stored in `vm.cpuInspectorHistory`.

```swift
struct InspectorSnapshot {
    var pc:        UInt16
    var opcode:    UInt16
    var disasm:    String
    var frame:     TICpuFrame  // CPU state AFTER this instruction (empty for speculative future)
    var isHistory: Bool        // true = executed; false = speculative look-ahead
    var isCurrent: Bool        // true = the instruction frozen at
}
```

Built by `captureInspectorSnapshot()`, which is called on every `freeze()`,
`stepKeycode()`, and `singleStep()`.  It reads (without draining) up to 1024 frames
from the ring buffer via `readCpuFrames(max: 1024)`, then appends a speculative
"next instruction" entry derived from `snapshotCPU().opcode`.

`vm.cpuInspectorUpdateID` is incremented each time a new inspector snapshot is
captured; views observe this to trigger a scroll-to-current update.

### Disassembler

```swift
TI59MachineWrapper.disassemblePC(_ pc: UInt16, opcode: UInt16) → String
```

Pure function — requires no machine state. Returns a mnemonic string for any
13-bit opcode, e.g. `"ADD A, C [MANT]"` or `"BR 0x03A2"`.

### ASM Overlay

Injects raw TMC0501 machine code into a debug-only ROM region and executes it
in a single synchronous burst — intended for ROM-level experimentation:
testing small snippets, probing CPU behavior, or exercising the emulator with
precisely crafted instruction sequences. Bridge entry points:
`loadDebugOverlayWords:` / `clearDebugOverlay` / `runDebugOverlayAt:maxSteps:steps:`
(see `Bridge/TI59MachineWrapper.h`).

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
reference. What's unique to this API doc is the exact bridge/Swift call
sequence `EmulatorViewModel.loadStateFile` uses to apply a parsed file to a
live `TI59Machine`:

1. `machine.reset()` — clears CPU state
2. `machine.stepN(300_000)` — lets the ROM complete its master-clear routine
3. `machine.partitionProgramRegs = …` — sets partition via SCOM
4. `machine.writeProgramSteps(…)` — writes zero-padded step array
5. Per register: normal registers via `machine.writeDataRegister(…)`; the TI-58C's
   4 extra registers (H00–H03 — not normal registers "60"–"63", see
   `reference/CoreArchitecture.md` § "TI-58C Extra (Constant Memory) Registers")
   via `machine.setRawRegister(MachineModel.extraRegisterBase + regNum, …)` to
   bypass the reversed data-register mapping entirely — the branch is driven by
   an explicit `isHidden` flag carried alongside each parsed register, never by
   testing whether `regNum >= 60` (ordinary TI-59 registers legitimately reach 99)
6. Out-of-range data registers (those that fall inside the program area for the loaded
   partition) are zeroed via `machine.setRawRegister(…)` to prevent stale-state corruption
7. KEYSTROKES played back asynchronously via `playKeystrokes(_:)` — 0.5 s per key

---

## TI-58C Constant Memory File Format (`ti58c.mem`)

The TI-58C emulator persists RAM contents between sessions in a human-readable text file called `ti58c.mem`.
This file is stored in the app's Application Support directory and is automatically loaded on startup.

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
