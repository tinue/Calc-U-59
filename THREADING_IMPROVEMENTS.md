# Threading Architecture Improvements (v1.3+)

## Overview

This document tracks improvements to Calc-U-59's threading model, identified during a deep architectural review. The current design evolved incrementally and contained unnecessary complexity, oversized critical sections, and — most importantly — an entirely unguarded read API. Fixes are prioritised by impact and effort.

**Status (v1.3 dev)**: Fixes 1, 2, 8, 9 and 10 are **COMPLETE**. Fixes 3–6 remain open but their original designs contained factual errors; the corrected analysis is recorded below so future work does not build on wrong premises.

---

## Completed Fixes

### ✅ Fix 1: Decouple Frame Drain from Key Mutex (DONE, v1.2)

**Location**: `Core/TI59Machine.cpp` (`drainCpuFrames` / `readCpuFrames`)

`drainCpuFrames()` and `readCpuFrames()` call directly into `m_cpu` without acquiring `m_keyMutex`, delegating locking to `m_traceMutex` internally. Eliminates the false dependency between keyboard input and trace frame buffering.

### ✅ Fix 2: Revert Recursive Trace Mutex (DONE, v1.3)

**Location**: `Core/TMC0501.hpp` (`m_traceMutex`) and all eight `lock_guard` sites in `TMC0501.cpp`

`m_traceMutex` is a plain `std::mutex` again. The original analysis assumed `beginNextStep()` re-acquired the lock held by `tracePreStep()`; in the current code **no acquisition site re-enters** — `beginNextStep()`'s lock scope (the previous-frame patch block) closes before it calls `tracePreStep()`, which takes the lock fresh, and `tracePostStep()` is a third independent scope. The revert was therefore a pure type change with no refactor needed.

### ✅ Fix 8: Lock the Calculator-Level Read API (DONE, v1.3) — *was missing from this document*

**Location**: `Core/TI59Machine.cpp/.hpp`

The largest real-world race surface was never listed here: the entire calculator-level read API was called from the UI thread at 60 Hz with **no lock at all** while `step()` mutated the same state under `m_keyMutex`:

- `snapshotCPU()`, `readDataReg()`, `readProgramStep()`, `partitionProgramRegs()`, `insertedModuleNumber()`, `pc()`
- `isCardPresent()` / `isWaitingForCard()` / `cardMode()` — card state is mutated *inside* `step()` (IN CRD / OUT CRD / CRD_OFF)
- `printerBufferContent()` — copied `std::string`s while the emulation thread assigned them (genuine crash potential, not just torn reads)
- `readRAMReg()` — returned a raw pointer, which no internal lock can protect

All of these now take `m_keyMutex`. `readRAMReg()` was replaced by `copyRAMReg(reg, out16)`, which copies under the lock; the ObjC++ bridge was migrated. The write-side state-file helpers (`writeProgram`, `writeDataRegister`, `setPartitionProgramRegs`, `serialiseRAM`/`deserialiseRAM`) are locked as well. The full lock-ownership policy is documented at `m_keyMutex` in `TI59Machine.hpp`.

### ✅ Fix 9: Printer Drain Decoupled from Key Mutex (DONE, v1.3)

`drainPrinterLines()` / `drainPrinterCodeLines()` no longer take `m_keyMutex`; the line queues are protected by `m_prnMutex` inside `TMC0501` (same pattern as Fix 1). Note this is the *opposite* of removing `m_prnMutex` (see corrected Fix 6).

### ✅ Fix 10: Trace Generation Gated on Panel Visibility (DONE, v1.3, Swift)

**Location**: `App/EmulatorViewModel.swift`, `App/Views/LiveDebugView.swift`, `App/Views/CPUInspectorView.swift`

Previously `liveDebugEnabled`/`cpuDebugEnabled` were hard-coded `true` and `buildCPUDebugSnapshot()` force-enabled `TRACE_REGS_FULL` on every tick — so the core paid the full per-instruction trace cost (~397-byte snapshot + three `m_traceMutex` acquisitions, ~14,200×/s) **permanently**, even on iPhone portrait where no debug panel exists. This single issue dominated the contention that Fixes 2/4/5 were written to address.

Now:
- The flags track actual panel visibility (`onAppear`/`onDisappear`).
- `updateDebugTraceFlags()` in `EmulatorViewModel` is the **single owner** of `machine.traceFlags`, derived from: CPU panel visible, frozen, armed freeze-on-start, binary-trace toggle, breakpoint set. With no consumer the core runs at `TRACE_NONE` — its zero-overhead fast path.
- `buildLiveSnapshot()` uses `nonZeroDataRegisterIndices()` (one bridge call) instead of up to 120 `rawRegister` calls per frame.
- **ROM heatmap**: tracing is off while the CPU panel is hidden, so no hits can be collected in the background. By design the heatmap now **resets when the panel becomes visible** (it shows activity *since the panel was opened*) and skips the stale ring backlog via a seqno baseline (`resetHeatmapBaseline()`).
- Bridge `-snapshotCPU` no longer leaves `displayOn`/`maxDigitDecay` uninitialized (it marshals via `marshalCpuFrame`); the Swift display-freeze logic was reading stack garbage.

---

## Open Fixes (corrected analysis)

### Fix 3: Split `m_keyMutex` Into Focused Locks — **original design unsafe; deprioritised**

The original plan ("migrate `insertCard()`, `cardEject()`, `isCardPresent()`, `isWaitingForCard()` to `m_cardMutex`") would have **introduced** races: card state (`m_cardPresent`, `m_cardPtr`, `m_cardBankBuffer`, `key[m_cardSwitchCol]`) is mutated *inside `step()`* by IN CRD / OUT CRD / CRD_OFF. A card mutex not taken by `step()` protects nothing, and "card I/O blocks keyboard input (they don't conflict)" was wrong — both touch `key[]`.

Any future split must therefore move the *card state itself* out from under the step path or have `step()` take the card lock at the card opcodes. Given that every card operation is human-speed (one insert/eject per swipe) the practical benefit is near zero. **Recommendation: keep the single `m_keyMutex`; the ownership comment in `TI59Machine.hpp` now serves the "guard fatigue" concern.**

### Fix 4: Display Mutex → Lock-Free Snapshot (MEDIUM, design corrected)

Corrections to the original claims:
- `m_displayMutex` is **not** read-only / 60 Hz. The emulation thread takes it in `postOperation()` for every IDLE strobe (12 of every 16 instructions) and at every digit==0 boundary, and `computeDisplayTraceState()` takes it once per traced instruction. Real acquisition rate is thousands per second — though with Fix 10, the traced-instruction component is zero whenever the debug panels are closed.
- The proposed two-buffer pointer swap **tears**: the writer updates at ~889 Hz (digit-0 boundaries) while the reader copies at 60 Hz, so the writer wraps onto the buffer the reader is mid-copy in. A correct design needs a **seqlock** (version counter, retry on odd/changed) or **triple buffering**.
- `getDisplay()` is not a passive read: it consumes `m_cSteps`/`m_pollSteps` via `exchange` to integrate `calcIndicator`. That consume-on-read semantic must move to the writer side (accumulate per published snapshot) before any snapshot-swap design works, and it already means a second concurrent reader would steal duty cycle from the first.

### Fix 5: Trace Cursor Atomics (MEDIUM, design corrected)

The original analysis had the roles backwards:
- `m_diskCursor` is touched **only by the drain side** (single consumer) — it does not race with trace logic at all.
- `m_frameHead` is written by the emulation thread **and read by the UI drain/read paths** — it is the variable that races.
- The frame payloads themselves race under any lock-free scheme: the drain copies a ~397-byte frame the writer may be overwriting. Lock-free requires an atomic `m_frameHead` *plus* per-frame validation (e.g. re-check a frame seqno after copying) or it will deliver torn frames.

With Fix 10 the mutex is uncontended whenever no debug consumer is active, so this is now a polish item.

### Fix 6: Lock-Free Printer Output (LOW, claim corrected)

"`m_prnMutex` adds latency without preventing any actual races" was wrong: it is exactly what makes the `std::vector` push (emulation thread) safe against the UI drain. Removing it without a double-buffer would be UB. The cheap win — dropping the *redundant outer* `m_keyMutex` from the drain calls — is done (Fix 9). The remaining double-buffer idea is valid but optional; the printer emits a few lines per second at most.

### Fix 7: ViewModel Locking Simplification (LOW, documentation-only)

Unchanged and still accurate: the emulation loop's `m.step()` acquiring `m_keyMutex` internally while UI key operations also acquire it is correct, just worth a comment if the bridge is ever refactored.

---

## Remaining Known Gaps (Swift side, not yet fixed)

- `isRunning`, `isFullSpeedMode`, `persistPending` (and `@Observable` properties written from the emulation queue in the breakpoint/pending-freeze paths) are plain Swift properties shared between the main thread and `emulQueue` without synchronisation. Works in practice; formally racy. A generation-counter or `@MainActor`-with-detached-loop design would clean this up.
- Rapid freeze→unfreeze (<20 ms) can strand the queued freeze block behind a still-running loop (serial-queue ordering vs. non-atomic `isRunning`).
- `EmulatorViewModel.init`'s `Task { await start(...) }` does not inherit the main actor, so the *initial* `start()` mutates observable state off-main (the model-picker path is main-actor and fine).

---

## Lock Ownership Map (current)

| Mutex | Protects | Acquisition points |
|-------|----------|-------------------|
| `m_keyMutex` | step/key/card/RAM/SCOM/printer-buffer state, debug events, breakpoint registration, reset, overlay, **and all calculator-level read accessors** | emulation loop + every UI accessor (see `TI59Machine.hpp` policy comment) |
| `m_displayMutex` | display strobe/afterglow state | `postOperation()` (CPU thread), `getDisplay()` + `computeDisplayTraceState()` |
| `m_traceMutex` (std::mutex) | frame ring (`m_frameRing`, `m_frameHead`, `m_diskCursor`), breakpoint vector | `tracePreStep`/`tracePostStep`/`beginNextStep` patch block (CPU thread); drains + breakpoint edits (UI thread) |
| `m_prnMutex` | printer line queues | printer push (CPU thread), drains (UI thread, no outer lock) |
| (atomics) | `m_traceFlags`, `m_cSteps`, `m_pollSteps` | everywhere |

Lock ordering (always this direction; no deadlock): `m_keyMutex` → { `m_traceMutex`, `m_displayMutex`, `m_prnMutex` }. The three inner locks are never nested with each other.

---

## Testing Strategy

For each fix:
1. Run existing unit tests (trace, display, printer)
2. Manual testing: verify 60 Hz display refresh, trace drain, keyboard responsiveness; open/close the CALCULATOR and CPU debug tabs and confirm tracing starts/stops (heatmap resets on open)
3. Check for regressions in debug panel live update
4. Profile: measure lock contention using `Instruments` before/after

---

## Timeline

- **v1.2**: Fix 1
- **v1.3** (current dev): Fixes 2, 8, 9, 10 — done. Fixes 4–5 optional polish (contention largely removed by Fix 10).
- **v1.4** (polish): Fix 6 double-buffer (optional), Fix 7 documentation, Swift-side gaps above.

---

## References

- [Lock Granularity Anti-Patterns](https://preshing.com/20111124/always-use-a-lightweight-lock/)
- [Seqlock](https://en.wikipedia.org/wiki/Seqlock) — required for a correct lock-free display snapshot (see Fix 4)
- [Double-Buffer Pattern](https://en.wikipedia.org/wiki/Multiple_buffering)
- [Atomic Operations in C++](https://en.cppreference.com/w/cpp/atomic/atomic)
- Project memory: [[Live Debug Panel (60 Hz)]] — discusses the display timing model
