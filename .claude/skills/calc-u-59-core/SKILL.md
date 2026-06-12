---
name: calc-u-59-core
description: Use this skill when working on the C++ emulation core of Calc-U-59 (files in Core/). Covers the TMC0501 CPU emulator, BCD register model, SCOM memory, machine variants (TI-59/58/58C), ROM/RAM, instruction set changes, mnemonic workflow, and trace infrastructure. Trigger on any task that touches Core/*.cpp, Core/*.hpp, tools/mnemonics.tsv, ROM disassembly, trace debugging, or machine variant behaviour.
user-invocable: true
---

# Calc-U-59 Emulator Core

This skill covers all work inside `Core/` and the associated Python dev tools.

---

## Component Hierarchy

```
TI59Machine          (Core/TI59Machine.hpp/.cpp)   ← public façade
 ├─ ROM              (Core/ROM.hpp/.cpp)
 ├─ RAM              (Core/RAM.hpp/.cpp)
 └─ TMC0501          (Core/TMC0501.hpp/.cpp)        ← CPU + SCOM
      └─ TraceTypes  (Core/TraceTypes.hpp)
```

`TI59Machine` is the **only** public interface. Swift and CLI code call it exclusively — never touch `TMC0501` directly. All calls go through `m_keyMutex` so the emulation thread and UI thread cannot race.

---

## Register Model

- **BCD registers A–E**: 16 nibbles each (nibble 0 = LSB).
- **SCOM**: 16×16 matrix of nibbles (`scom[row][nibble]`).

### Terminology: two different "PCs"

| Term | Meaning |
|------|---------|
| **ROM address** (CPU PC) | The 13-bit address in ROM that the TMC0501 is currently fetching/executing (0x0000–0x17FF). Internal to the CPU; never user-visible. |
| **Calculator PC** (user step address) | The step number (0–959) of the currently selected step in the user's keystroke program. User-visible on the display; stored externally in SCOM[0] nibbles 4–7. |

The two are completely independent. A single calculator step (one keycode) typically causes dozens or hundreds of ROM instructions to execute.

### SCOM Key Rows

| Row | Content |
|-----|---------|
| 0 | IO user flags (3 bits), Last key, Prg Src Flag, **RAM address**, Second ROM address, Fixed PT, **calculator PC / user step address (nibbles 4–7)** |
| 1–8 | Hierarchy registers 1–8 (mantissa bits 15–3, exp 2–1, sign 0) |
| 11 | T register (stack top / last-X) |
| 13 | Pending ops count; Deg/Rad/Grad mode (nibble 0: `0`=DEG, `1`=GRAD, `C`=RAD) |

### Calculator PC Encoding (SCOM[0] nibbles 4–7)

This is the **user program step address** (0–959), not the CPU's ROM address. The ROM firmware reads and writes nibbles 4–7 of SCOM row 0 to track and encode return addresses at the calculator-program level before subroutine calls. It must be kept in sync on every instruction in `TMC0501::step()` before ROM code executes.

```
calculator_pc = n7×800 + n6×80 + n5×8 + n4

Encode:
  n4 = calculator_pc % 8
  n5 = (calculator_pc / 8)  % 10
  n6 = (calculator_pc / 80) % 10
  n7 = (calculator_pc / 800) % 2
```

---

## Machine Variants

Defined in `Core/MachineVariant.hpp`: `TI59 | TI58 | TI58C`.

| Variant | RAM registers | Card reader | Constant memory |
|---------|--------------|-------------|-----------------|
| TI-59   | 120          | yes         | no              |
| TI-58   | 60           | no          | no              |
| TI-58C  | 60           | no          | yes (MEMWR/MEMRD) |

**TI-58C memory instructions**: uses dedicated opcodes `0xA76` (MEMWR) and `0xA86` (MEMRD) instead of TI-59's generic `RAM_OP` (`0xAF8`). `TMC0501.cpp` checks the machine variant to distinguish these.

---

## Mnemonics Workflow

`tools/mnemonics.tsv` is the **single source of truth** for all TMC0501 instruction mnemonics.

- Python tools (`disasm.py`, `read_trace.py`) read the TSV at runtime — no regeneration needed.
- C++ arrays in `TMC0501.cpp` are hard-coded and must be regenerated after any TSV change:

```bash
python3 tools/disasm.py --emit-cpp > /tmp/generated.cpp
# Copy the generated arrays (~line 1389) and paste into TMC0501.cpp
```

---

## Trace Infrastructure (`TraceTypes.hpp`)

- `CpuFrame` — 397-byte snapshot: ROM address (CPU PC), opcode, registers A–E, SCOM matrix, flags.
- `DebugEvent` — wraps a `CpuFrame` with event metadata.
- Trace feature flags: `PC_ONLY`, `LIGHT_REGS`, `FULL_SNAPSHOT`.

Python tools for post-processing traces:
- `tools/read_trace.py` — parses `TI59_TRACE.bin` → human-readable text or JSON.
- `tools/compare_trace.py` — finds first divergence between two traces.

---

## IDLE/SCOM Synchronization

The SCOM chip (TMC0571) has its own digit counter that must synchronize with the CPU's on the RUN→IDLE transition. The CPU must execute `WAIT D1` before `SET IDLE`; otherwise display positions and keyboard rows become misaligned.

The emulator simplification: assumes the ROM always uses the correct `WAIT D1 + SET IDLE` pattern, seeds afterglow at `digit==0` boundaries, and captures a phase-independent snapshot there. This works for correct ROM code but cannot handle programs that deliberately misalign counters (see `examples/assembly/Decoder.asm`).

---

## Dev Tools Quick Reference

| Tool | Purpose |
|------|---------|
| `tools/disasm.py` | ROM disassembler; `--emit-cpp` regenerates C++ mnemonic arrays |
| `tools/read_trace.py` | Parse binary trace → text/JSON |
| `tools/compare_trace.py` | Find divergence between two trace files |
| `tools/compare_logs.py` | Align two log files on matching ROM address sequence |
| `tools/count_disp_phases.py` | Analyze DISP ON/OFF timing from a trace |

---

## Reference

Deep architecture documentation: `reference/CoreArchitecture.md`

---

## Global Rules

1. **Compile, don't run.** Use `clang++` or `xcodebuild` to iterate on syntax and type errors. Do not launch the Xcode iOS Simulator or run the built Mac app — that is the user's job. When runtime verification is needed, ask the user to launch the app and explain precisely what behaviour or output to look for.

   Quick syntax check:
   ```bash
   clang++ -Wall -Wextra -fPIC -c Core/TMC0501.cpp -o /tmp/test.o
   ```
   Full build:
   ```bash
   xcodebuild -project Calc-U-59.xcodeproj -scheme "Calc-U-59" build
   ```

2. **Commit often, never push.** Commit after each logical unit of work. Never run `git push`.

3. **iOS and macOS both must work.** Every change must leave both platforms building. If there is any doubt, make two explicit builds before declaring the task done.

4. **Cite your sources.** When referencing a hardware spec, standard, or external document, include the https URL (or a pointer to the local reference file) in the relevant code comment or documentation.
