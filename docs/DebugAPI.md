# Debug API Reference

This document describes the two-layer debug API available in the TI-59 emulator.

- **Layer 1 — CPU / trace API**: instruction-level tracing, breakpoints, disassembler.
  Operates at the TMC0501 CPU level; useful for ROM debugging.
- **Layer 2 — Calculator API**: read/write data registers, program steps, and internal
  state at the TI-59 user level; useful for debugging calculator programs.

Both layers are thread-safe. All Swift entry points live in `EmulatorViewModel`;
the underlying C++ is in `TI59Machine` and `TMC0501`.

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
    var cpu:          TICPUSnapshot // raw CPU register state
}
```

#### `rawRegister(_ reg: Int) → [UInt8]?`

Read a raw 16-nibble RAM register. `reg` is the **physical** RAM index (0–119),
not the user-visible register number. Use `119 − nn` to address data register Rnn.

#### `machine.dataRegister(_ regNum: Int) → Double`  *(ObjC bridge)*

Read data register Rnn decoded as a Double. Equivalent to `RCL nn` on the keyboard.

#### `machine.allProgramSteps() → Data`  *(ObjC bridge)*

Read all program steps as raw keycodes. Length = `partitionProgramRegs × 8`.

#### `machine.snapshotCPU() → TICPUSnapshot`  *(ObjC bridge)*

Capture a snapshot of all CPU registers (A–E, SCOM, KR, SR, fA, fB, …) at the
current instant. Safe to call while the emulation loop is running.

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

### Debug panel — level button

The **D** button in the debug toolbar cycles through three levels:

| Dot colour | Level | `DebugLevel` value | Effect |
|------------|-------|--------------------|--------|
| Gray       | OFF   | `.off` (0)         | No output written; C-core event buffer not drained |
| Orange     | INFO  | `.info` (1)        | Swift-side `debugAppend` calls at level `.info` are shown |
| Red        | DEBUG | `.debug` (2)       | All INFO output **plus** C-core write events (STO, MEMWR, RAM OP) |

Each click advances one step; after DEBUG it wraps back to OFF.

The current level is exposed as `vm.debugLevel: DebugLevel` and as the convenience
computed property `vm.debugEnabled: Bool` (true when level ≠ OFF).

### Debug panel functions (ViewModel)

These append formatted output to `debugLines`, displayed in the macOS Debug panel.
Each call accepts an implicit `level:` parameter (default `.info`); output is
suppressed when `vm.debugLevel < level`.

| Function | Description |
|----------|-------------|
| `debugDumpVars()` | Non-zero data registers within the current partition, shown as `R00 = 3.14159…` |
| `debugDumpSCOM()` | All 16 SCOM rows as hex nibble strings (`S00 0000000000000000`), nibble[15] first |
| `toggleDebug()` / `clearDebug()` | Cycle debug level (OFF→INFO→DEBUG→OFF); clear the log |

When adding new Swift-side debug output, call `debugAppend([...], level: .info)` or
`debugAppend([...], level: .debug)` as appropriate.

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

Set via `viewModel.setTraceEnabled(_:fullRegs:)` or directly on the machine wrapper.

| Flag | Swift name | Cost | Records |
|------|------------|------|---------|
| `TRACE_PC` | `.pc` | Low | pc, opcode, digit, cycleWeight, seqno |
| `TRACE_REGS_LIGHT` | `.regsLight` | Medium | adds KR, SR, fA, fB, R5, cpuFlags |
| `TRACE_REGS_FULL` | `.regsFull` | High | adds A–E, SCOM[16][16], Sout |
| `TRACE_BREAKPOINTS` | `.breakpoints` | Low | armed breakpoint check per step |

Flags are combined: `[.pc, .regsLight]` is the default when tracing is enabled.

### TraceEvent fields

```
pc            ROM address of the instruction
opcode        13-bit word fetched from ROM
digit         digit-counter value (0–15) when the instruction ran
cycleWeight   1 (active) or 4 (idle)
seqno         monotonically increasing; gaps indicate ring overflow
KR, SR        address / return registers
fA, fB        flag registers A and B
R5            4-bit scratch / decimal-point pointer
cpuFlags      internal emulator flags (FLG_* bitmask)
snapshotIndex index into CPUSnapshot ring (0xFF = no snapshot)
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

### Disassembler

```swift
TI59MachineWrapper.disassemblePC(_ pc: UInt16, opcode: UInt16) → String
```

Pure function — requires no machine state. Returns a mnemonic string for any
13-bit opcode, e.g. `"ADD A, C [MANT]"` or `"BR 0x03A2"`.

---

## .ti59 State File Format

State files load programs and data registers in a single operation.
See `App/StateFileLoader.swift` for the full format description; summary:

```
# comment

PARTITION: 479.59        # last step number.last register (sets program/data split)

PROGRAM:
76 11                    # Format 1: bare keycodes
002  42 00               # Format 2: step-number prefix
003  RCL  00             # Format 3: printer listing (mnemonics ignored)
...                      # gap marker: steps in between remain 00
110  42 05               # resumes at step 110

REGISTERS:
00 = 3.141592653589793
05 = -1.5e-3
H01 = 7.77E22           # TI-58C only: hidden register (loads into RAM slot 061)

KEYSTROKES:
21 84 65 83 95           # [2nd][π] × 2 =  (0.5 s between each key)
Wait: 1s                 # pause 1 s before next line
42 92 92                 # STO 0 0
```

**PARTITION section:**

- The number before the dot is the last visible step number; total steps = that number + 1.
- Total steps must be a multiple of 80; the parser rounds up to the nearest valid boundary.
- The `.xx` suffix (e.g. `.59`) is accepted for documentation purposes and ignored by the parser.
- **Default when omitted:**
  - TI-59: 479 (480 steps, 60 program-RAM registers)
  - TI-58 / TI-58C: 239 (240 steps, 30 program-RAM registers)
- **TI-58 / TI-58C cap:** if an explicit `PARTITION:` value exceeds 479, the load is aborted with an error.

**REGISTERS section:**

- **Normal registers:** `NN = value` where NN is 00–99 (valid for all models)
- **Hidden registers (TI-58C only):** `HNN = value` where NN is 00–03
  - Maps to RAM slots 060–063 (the TI-58C's special constant-memory registers)
  - `H00` → slot 060, `H01` → slot 061, `H02` → slot 062, `H03` → slot 063
  - Used to store partition settings, ln(10) validation byte, and FIX mode
  - Using H00–H03 in `.ti59` or `.ti58` files generates a parse error

Any register (normal or hidden) not listed defaults to zero on load.

**Matrix code format:** `row*10 + col`, row 1–9 (top→bottom), col 1–5 (left→right).
Valid range: 11–95.  These are **physical key positions**, not TI manual keycodes
(which are program-memory values like π=89, STO=42).  Mnemonic labels are silently
ignored (e.g. `21 2nd` presses the 2nd key; `21` alone is sufficient).
`Wait:` accepts `s` or `ms` units.

Loading sequence (in `EmulatorViewModel.loadStateFile`):
1. `machine.reset()` — clears CPU state
2. `machine.stepN(300_000)` — lets the ROM complete its master-clear routine
3. `machine.partitionProgramRegs = …` — sets partition via SCOM
4. `machine.writeProgramSteps(…)` — writes zero-padded step array
5. Per register: normal registers via `machine.writeDataRegister(…)`; hidden registers
   (H00–H03, TI-58C only) via `machine.setRawRegister(regNum + 60, …)` to bypass the
   reversed data-register mapping
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
