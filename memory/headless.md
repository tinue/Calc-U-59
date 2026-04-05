---
name: Headless runner plan
description: Implementation plan for Python-driven headless TI-59 trace capture using .ti59 scenario files, without the Xcode/SwiftUI app
type: project
---

Goal: run a controlled calculator lifecycle (turn on → press key → capture trace) from Python without the GUI.

**Why:** Enables reproducible regression tests and programmatic trace capture. Currently the only way to produce a trace is via the GUI with the C-DBG toggle.

**How to apply:** Use this as the blueprint when implementing the headless runner or any scripted/automated emulator control.

---

## New Files (zero changes to existing files)

| File | Purpose |
|------|---------|
| `CMakeLists.txt` | Builds `Core/` as static lib + `Headless/ti59-run` binary |
| `Headless/TraceWriter.hpp/.cpp` | C++ port of `App/TraceWriter.swift`; byte-identical binary format |
| `Headless/StateFileParser.hpp/.cpp` | Subset `.ti59` parser (PARTITION, PROGRAM, KEYSTROKES sections) |
| `Headless/ti59-run.cpp` | Headless runner entry point |
| `tools/run_scenario.py` | Python orchestrator: build-if-needed → run → parse |
| `examples/press1.ti59` | Scenario definition file (press key "1") |

---

## Scenario Format

Scenarios are **`.ti59` state files** using the existing `KEYSTROKES:` section — no raw matrix codes in Python or CLI args.

```
# examples/press1.ti59
KEYSTROKES:
82   1
```

Python entry point:
```
python3 tools/run_scenario.py examples/press1.ti59 [--output scenario.bin]
```

---

## Key Facts

**Matrix codes** — decimal, formula `row * 10 + col` (both 1-based, row top-to-bottom):
- Key "1" = **82** (row 8, col 2), confirmed in `examples/example.ti59`
- Valid range: **11–95** (same guard as `App/StateFileLoader.swift`)
- `Wait: Ns` / `Wait: Nms` between keystrokes

**Key → `pressKey()` translation** (mirrors `Bridge/TI59MachineWrapper.mm`):
```cpp
static const int kbits[] = {0, 1, 2, 3, 5, 6};
// matrixCode = row*10 + col  (1-based)
machine.pressKey(kbits[col], row);    // press
machine.releaseKey(kbits[col], row);  // release
```

**IDLE detection:** `machine.snapshotCPU().flags & 0x0001`

**Runner lifecycle per key:**
1. Boot → wait for IDLE (phase 0, stepN(256) batches)
2. Press key → wait for IDLE exit (CPU detects key, stepN(64) batches)
3. Release key → wait for IDLE return (processing done, stepN(64) batches)
4. Drain trace events + write after every batch

**TraceWriter format:** identical to `App/TraceWriter.swift` — 16-byte header, 3-byte record envelopes, 120-byte TRACE_EVENT payloads, same dedup key `(pc, opcode, fA, fB, KR, SR, flags, R5, A–E)`. Output is compatible with `read_trace.py` and `compare_trace.py`.

**ROM format** (`roms/rom-59.hex`): flat hex string, 4 chars per `uint16_t` word, 6 144 words total.

---

## Reference Files (read before implementing)

- `Core/TI59Machine.hpp` — machine API: `stepN`, `pressKey`, `releaseKey`, `snapshotCPU`, `drainTraceEvents`, `setTraceFlags`, `writeProgram`
- `Core/TraceTypes.hpp` — `TraceEvent`, `CPUSnapshot` structs; `TRACE_*` flag constants
- `App/TraceWriter.swift` — authoritative binary format (field offsets, dedup logic)
- `App/StateFileLoader.swift` — authoritative `.ti59` parser (keycode range, Wait syntax)
- `Bridge/TI59MachineWrapper.mm` — `kbits[]` table; matrixCode → K-line mapping

---

## Verification

```bash
cmake -B build . && cmake --build build
python3 tools/run_scenario.py examples/press1.ti59 --output scenario.bin
python3 tools/read_trace.py scenario.bin | head -40
python3 tools/compare_trace.py --bin 1.LOG scenario.bin
```

Expected: USER_EVENT records for key 82 down/up visible in dump; IDLE transitions present; path matches reference.
