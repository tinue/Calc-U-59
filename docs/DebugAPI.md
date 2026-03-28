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

Exponent is stored as an unsigned magnitude (0–99); the sign is encoded in nibble[0] bit 0.
All-zero encodes 0.0.

Swift helpers: `encodeTI59BCD(_ value: Double) → [UInt8]` (in `StateFileLoader.swift`)
and `TI59MachineWrapper.decodeBCD(_ nibbles16: Data) → Double`.

### Debug panel functions (ViewModel)

These append formatted output to `debugLines`, displayed in the macOS Debug panel.
They are no-ops when `debugEnabled` is `false`.

| Function | Description |
|----------|-------------|
| `debugDumpVars()` | Non-zero data registers within the current partition, shown as `R00 = 3.14159…` |
| `debugDumpSCOM()` | All 16 SCOM rows as compact hex nibble strings (`S00 0000000000000000`) |
| `toggleDebug()` / `clearDebug()` | Enable/disable output; clear the log |

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

KEYSTROKES:
21 84 65 83 95           # [2nd][π] × 2 =  (0.5 s between each key)
Wait: 1s                 # pause 1 s before next line
42 92 92                 # STO 0 0
```

Matrix code format: `row*10 + col`, row 1–9 (top→bottom), col 1–5 (left→right).
Valid range: 11–95.  These are **physical key positions**, not TI manual keycodes
(which are program-memory values like π=89, STO=42).  Mnemonic labels are silently
ignored (e.g. `21 2nd` presses the 2nd key; `21` alone is sufficient).
`Wait:` accepts `s` or `ms` units.

Loading sequence (in `EmulatorViewModel.loadStateFile`):
1. `machine.reset()` — clears CPU state
2. `machine.stepN(300_000)` — lets the ROM complete its master-clear routine
3. `machine.partitionProgramRegs = …` — sets partition via SCOM
4. `machine.writeProgramSteps(…)` — writes zero-padded step array
5. `machine.writeDataRegister(…)` per register — writes BCD nibbles
6. KEYSTROKES played back asynchronously via `playKeystrokes(_:)` — 0.5 s per key
