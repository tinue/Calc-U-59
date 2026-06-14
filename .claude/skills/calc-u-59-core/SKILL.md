---
name: calc-u-59-core
description: Use this skill when working on the C++ emulation core of Calc-U-59 (files in Core/). Covers the TMC0501 CPU emulator, BCD register model, SCOM memory, machine variants (TI-59/58/58C), ROM/RAM, instruction set changes, mnemonic workflow, and trace infrastructure. Trigger on any task that touches Core/*.cpp, Core/*.hpp, tools/mnemonics.tsv, ROM disassembly, trace debugging, or machine variant behaviour.
user-invocable: true
---

# Calc-U-59 Emulator Core

This skill covers all work inside `Core/` and the associated Python dev tools.

---

## Domain Primer (TI-59 background)

The TI-59, TI-58, and TI-58C are Texas Instruments handheld programmable calculators (1977–79). This project emulates them at the hardware level: **the original ROM firmware runs unmodified** on an emulated TMC0501 CPU, so calculator behaviour emerges from the firmware — debugging usually means tracing ROM execution, not reading emulator logic.

- **Keystroke programming**: users program the calculator by recording key presses. Each program step stores one two-digit **keycode**; the TI-59 holds up to 960 steps / 100 data registers, with RAM partitioned between the two.
- **Hardware chips**: TMC0501 (CPU), TMC0571 (SCOM — scratchpad RAM + display/keyboard scan), TMC0540 (CROM — plug-in "Solid State Software" library module).
- **Solid State Software modules**: plug-in ROM cartridges holding up to 5000 pre-recorded program steps (as keycodes). The user runs library program *n* with `2nd Pgm nn`. The Master Library module ships with the calculator and is loaded by default in the emulator.
- The display is a 12-digit LED; the firmware multiplexes it digit-by-digit during IDLE.

---

## Component Hierarchy

```
TI59Machine          (Core/TI59Machine.hpp/.cpp)   ← public façade
 ├─ ROM              (Core/ROM.hpp/.cpp)
 ├─ RAM              (Core/RAM.hpp/.cpp)
 └─ TMC0501          (Core/TMC0501.hpp/.cpp)        ← CPU + SCOM
      └─ TraceTypes  (Core/TraceTypes.hpp)
```

`TI59Machine` is the **only** public interface. Swift and CLI code call it exclusively — never touch `TMC0501` directly. All calls — including read accessors — go through `m_keyMutex` so the emulation thread and UI thread cannot race. Any new public accessor must take the lock too.

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

The user program step address (0–959) is encoded in nibbles 4–7 of SCOM[0] and must be kept in sync on every instruction in `TMC0501::step()` before ROM code executes. Full encoding formula: `reference/CoreArchitecture.md` § "Calculator PC Encoding".

---

## Program Source Flag and Solid-State (CROM) Execution

SCOM[0] nibble 3 holds the **PRG SOURCE** flag — where the currently executing user program lives:

| Value | Meaning |
|-------|---------|
| 0 | User program in RAM (or keyboard execution) |
| 1 | Solid-state module (CROM); the program counter lives **in the CROM chip**, not in SCOM |
| 2 | Transitional "solid-state return": after a RTN back into a module, SCOM[0] nibbles 4–7 hold the saved CROM address (raw BCD, **not** a step number); the firmware reloads the CROM PC from it on the next keycode dispatch and sets the flag back to 1. Lasts exactly one dispatch cycle. |
| 4 | Fast mode |
| 8 | ROM-resident keycode sub-program (e.g. P→R is implemented as a firmware keycode sequence using the SCOM PC) |

**CROM program counter** (`m_libAddr`): held in the module chip itself. `IN LIB` fetches a byte and auto-increments; `OUT LIB_PC` (called 4×, one BCD digit each) writes it; `IN LIB_PC` reads it back (used for SBR return addresses). SCOM[0]'s calculator PC is only used for RAM programs.

**User-visible solid-state PC** (`m_libExecPC`, sentinel `0xFFFF` = none): latched in the `IN LIB` handler only when the fetch comes from the firmware's execution-interpreter fetch site — `0x082F` on TI-59/TI-58 (they share the same ROM), `0x0823` on TI-58C (different ROM set: CD2400/CD2401/TMC0573). Implemented as the variant-aware member `libExecFetchPC()` in `TMC0501.hpp`. Header reads (ROM 1377/137C) and label searches (1390/1394) never move it. Exposed via `TI59Machine::libExecPC()` (locked); deliberately **not** part of `CpuFrame`, to avoid a trace-format change. Reset to the sentinel on machine reset and module change.

**Module image header layout**: addr 0000 = program count N, 0001 = copy-protect flag, then one 2-byte BCD start address per program, then a pointer to last-keycode+1; unused space is filled with keycode 92 (INV SBR). Label search scans byte-by-byte from the program start and never leaves the current program (labels duplicate across programs).

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
# Paste over the section marked "── Generated tables ──" in TMC0501.cpp (~line 1575)
```

---

## Trace Infrastructure (`TraceTypes.hpp`)

`CpuFrame` (397 bytes) holds ROM address, opcode, registers A–E, SCOM matrix, and flags. Frames in the ring use **post-execution semantics** — `beginNextStep()` patches the previous frame's registers after each instruction. Full field list and flag constants: `reference/DebugAPI.md` § "CpuFrame fields".

Python tools: `tools/read_trace.py` (parse binary → text), `tools/compare_trace.py` (find first divergence).

---

## IDLE/SCOM Synchronization

The emulator assumes the ROM always uses the correct `WAIT D1 + SET IDLE` pattern and does not model the SCOM's independent digit counter. This works for all real ROM code but cannot handle programs that deliberately misalign counters (e.g. `examples/assembly/Decoder.asm`). Full hardware background: `reference/CoreArchitecture.md` § "IDLE/SCOM Synchronization".

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
