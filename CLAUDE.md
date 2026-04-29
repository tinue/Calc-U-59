# Project Context

## Key Architecture

### SCOM Memory Map (from TI-59 Manual)

| SCOM Row | Content |
|----------|---------|
| 0 | IO user flags (3 bits), Last key, Prg Src Flag, RAM address, Second ROM address, Fixed PT |
| 1–8 | **Hierarchy registers 1–8** (mantissa bits 15–3, exponent 2–1, sign 0) |
| 11 | **T register** (stack top / last-X) |
| 13 | **Pending ops count**, **Deg/Rad/Grad mode** (nibble 0: 0=DEG, 1=GRAD, C=RAD) |

### Program Counter Encoding (SCOM[0] nibbles 4–7)

The ROM reads the current PC from SCOM[0] nibbles 4–7 to encode return addresses before subroutine calls.

**Encoding formula:**
```
PC = n7×800 + n6×80 + n5×8 + n4
```

**Reverse (used in TMC0501.cpp to encode):**
- n4 = PC % 8
- n5 = (PC / 8) % 10
- n6 = (PC / 80) % 10
- n7 = (PC / 800) % 2

This must be updated on every instruction in `TMC0501.cpp:step()` before ROM code executes.

## Critical Implementation Details

### TI-58C Memory Instructions
TI-58C uses dedicated MEMWR (0xA76) and MEMRD (0xA86) opcodes instead of TI-59's generic RAM_OP (0xAF8). Implementation in `Core/TMC0501.cpp` checks machine variant to distinguish these instructions from MOV R5.

### Dynamic Type Accessibility (UIKit/SwiftUI)
The app intentionally **caps Dynamic Type to .small ... .large** at the top of `CalculatorView.body`. This keeps the calculator UI (buttons, printer, card reader) at consistent scale. Ignores accessibility sizes "XL" and above because buttons become oversized and break the layout (especially TI-59 with card reader bar).

### Live Debug Architecture (60 Hz Real-Time)
- **Value timing**: All register values shown are **pre-execution** (what exists before instruction runs)
- **Frozen display**: When frozen, current step = decodedPC - 1 (the last executed instruction), with registers showing post-execution of that instruction
- **Next statement**: Shows PC and mnemonic of next (not-yet-executed) statement, with empty/blank register state
- **Bridge optimization**: Use `nonZeroDataRegisterIndices()` to fetch non-zero data registers in a single call, not 100 individual bridge calls per frame

### IDLE/SCOM Synchronization (Hardware Detail)
The SCOM chip (TMC0571) has its **own digit counter** that must be synchronized with the CPU's digit counter via the RUN→IDLE transition. Per hardware manual:

> "Transition from RUN to IDLE mode is used to synchronize SCOM digit counter to CPU digit counter. If this instruction is not executed in the right digit cycle, digit counter in CPU and SCOM differ; display and keyboard results are unpredictable."

The CPU must execute `WAIT D1` **before** `SET IDLE` to ensure both counters are at D1 when the transition occurs. If `SET IDLE` is issued at the wrong digit phase, display positions and keyboard rows become misaligned.

**Emulator simplification:** The emulator does not explicitly model the SCOM's independent digit counter. Instead, it:
- Assumes the ROM always uses the correct `WAIT D1` + `SET IDLE` pattern (verified in actual TI-59/58 ROM)
- Seeds afterglow at digit==0 boundaries during IDLE, which naturally coincides with Display Mode multiplexing cycles (~4.5 ms per complete scan)
- Approximates the dual-counter synchronization as a CPU-cycle-based model
- Uses a "phase-independent snapshot" at digit==0, capturing the full A/B register arrays unconditionally

This works for correctly-written ROM code but **cannot handle programs that intentionally misalign counters** (e.g., `examples/assembly/Decoder.asm`), which exploit phase-dependent display behavior. See `CPU_SCOM_Interconnect.md` for details on this known limitation.

### Mnemonics Workflow
- **Single source of truth**: `tools/mnemonics.tsv`
- **Python**: Auto-reads TSV at runtime (disasm.py, read_trace.py), no regeneration needed
- **C++**: Hard-coded arrays in `Core/TMC0501.cpp` must be regenerated after TSV changes:
  ```bash
  python3 tools/disasm.py --emit-cpp > /tmp/generated.cpp
  # Copy generated arrays (~line 1389) and paste into TMC0501.cpp
  ```

## Headless Runner Plan

Goal: run controlled calculator scenarios from Python without the GUI, producing trace files for regression tests.

**Key components:**
- `CMakeLists.txt` builds `Core/` as static lib
- `Headless/ti59-run` C++ binary with TraceWriter and StateFileParser
- `tools/run_scenario.py` orchestrator
- Scenarios use `.ti59` state files with `KEYSTROKES:` section
- Matrix codes: decimal, 1-based row×10+col (e.g., key "1" = 82)

**Lifecycle:**
1. Load ROM → boot to IDLE
2. For each keystroke: press → wait for IDLE exit → release → wait for IDLE return
3. Drain trace events and write to `.bin` after each batch

**IDLE detection:** `machine.snapshotCPU().flags & 0x0001`

## User Preferences (from prior sessions)

- Real-time updates at 60 Hz, not snapshots
- Calculator-level state (registers, flags, SCOM), not CPU internals
- HIR registers as Double (user variables), not hex
- Pre-execution value semantics in debug panel
