# Threading Architecture Improvements (v1.3+)

## Overview

This document tracks planned improvements to Calc-U-59's threading model, identified during a deep architectural review. The current design evolved incrementally and contains unnecessary complexity and oversized critical sections. Fixes are prioritized by impact and effort.

**Status**: First fix (remove `m_keyMutex` from frame drain) is **COMPLETE** (already applied).

---

## Completed Fixes

### ✅ Fix 1: Decouple Frame Drain from Key Mutex (DONE)

**Location**: `Core/TI59Machine.cpp:217–223`

**What was fixed**: `drainCpuFrames()` and `readCpuFrames()` now call directly into `m_cpu` without acquiring `m_keyMutex`, delegating locking to `m_traceMutex` internally.

**Impact**: 
- Eliminates false dependency between keyboard input and trace frame buffering
- Reduces contention on `m_keyMutex` during trace drain operations
- Fixes incorrect lock ordering (trace frames should use only `m_traceMutex`)

---

## Planned Fixes (v1.3+)

### HIGH PRIORITY

#### Fix 2: Revert Recursive Mutex; Refactor `beginNextStep()` (Est. 30 min)

**Location**: 
- `Core/TMC0501.hpp`: `m_traceMutex` declaration
- `Core/TMC0501.cpp`: Lines 1195–1218, 1245–1248, 1387–1405, 1443, 1456, 1487

**Current Problem**:
- `m_traceMutex` was upgraded to `std::recursive_mutex` to allow `beginNextStep()` to re-acquire the same lock
- `tracePreStep()` acquires the lock
- `beginNextStep()` acquires it again (nested)
- `tracePostStep()` acquires it again
- This masks a deeper design flaw: lock boundaries are not cleanly separated

**Why it matters**:
- Recursive mutexes are slower than normal mutexes (overhead per acquisition)
- Nested lock design is hard to reason about and maintain
- Makes future optimization difficult

**Better approach**:
1. Keep `m_traceMutex` as `std::mutex` (non-recursive)
2. Refactor `beginNextStep()` to not need the lock—it only patches the *previous* frame, which belongs to the emulation thread
3. If `beginNextStep()` must be called within `tracePreStep()`, extract the locking logic so the loop calls:
   ```cpp
   std::lock_guard<std::mutex> lock(m_traceMutex);
   {
       tracePreStep();
       beginNextStep();  // now shares the same lock scope
       // ...
   }
   ```

**Verification**: Ensure trace frame buffer (`m_frames[]`, `m_frameHead`) is never accessed outside the lock.

---

#### Fix 3: Split `m_keyMutex` Into Focused Locks (Est. 45 min)

**Location**: `Core/TI59Machine.hpp:148` and all call sites (16+ locations)

**Current Problem**:
- Single `m_keyMutex` guards 8 unrelated subsystems:
  1. Key press/release
  2. `step()` execution
  3. Card insertion/eject
  4. Printer output drain
  5. Debug event drain
  6. Breakpoint add/remove
  7. Reset
  8. Debug overlay load/run

- This creates "guard fatigue": hard to know which operations actually conflict

**Why it matters**:
- Artificial serialization: card I/O blocks keyboard input (they don't conflict)
- Harder to add new I/O without adding more locks
- Potential hidden deadlock risk if code evolves

**Better approach**:
Split into three focused mutexes:
- `m_keyInputMutex`: Only key press/release (tightest critical section)
- `m_cardMutex`: Card insertion/eject
- Keep `m_traceMutex` for trace frame buffer (already separate)
- Leave printer/debug operations under `m_keyInputMutex` for now (they're not frequent enough to warrant separate mutexes)

**Implementation order**:
1. Add `std::mutex m_cardMutex` to TI59Machine.hpp
2. Migrate `insertCard()`, `cardEject()`, `isCardPresent()`, `isWaitingForCard()` to use `m_cardMutex`
3. Rename `m_keyMutex` comment to clarify it guards step/key/display state
4. Document which operations use which mutex in TI59Machine.hpp comments

---

### MEDIUM PRIORITY

#### Fix 4: Replace Display Mutex with Double-Buffer + Atomic Swap (Est. 60 min)

**Location**: 
- `Core/TMC0501.hpp`: `m_displayMutex`, `m_digitAfterglowCounters[12]`, etc.
- `Core/TMC0501.cpp:303–355` (`getDisplay()`) and lines 1309, 1371

**Current Problem**:
- `m_displayMutex` only protects **reads** (UI thread calls `getDisplay()` at 60 Hz)
- Writes happen during `step()` on emulation thread (single-threaded, no write-write race)
- Lock is acquired 60 times per second even when display is static
- Creates unnecessary contention: UI thread can stall while waiting for display mutex

**Why it matters**:
- Display updates are on the hot path (every frame, every digit boundary)
- 60 Hz polling × 16.7 ms = contention with emulation thread
- Lock-free reads are possible with careful atomic operations

**Better approach**: Double-buffer strategy
1. Maintain two `DisplaySnapshot` buffers: `m_displayCurrent` and `m_displayNext`
2. During `step()` at digit==0 when IDLE updates the display, atomically swap pointers
3. `getDisplay()` reads from current buffer without any lock
4. No race: only the swap point needs atomic operations

**Implementation**:
```cpp
// In TMC0501.hpp
DisplaySnapshot m_displayBuffers[2]{};
std::atomic<int> m_displayReadIdx{0};  // which buffer to read from

// In getDisplay()
int idx = m_displayReadIdx.load();
return m_displayBuffers[idx];

// In step() at digit==0 boundary (where display updates)
// ... update m_displayBuffers[1-idx] ...
m_displayReadIdx.store(1 - idx);  // atomic swap
```

---

#### Fix 5: Simplify Trace Mutex for Actual Concurrent Access (Est. 30 min)

**Location**: `Core/TMC0501.hpp:360–364` and trace function calls

**Current Problem**:
- `m_frameHead` (write-only by emulation thread) is protected by a recursive mutex
- `m_diskCursor` (written by drain, read by trace logic) is the only actual concurrent variable
- Recursive lock is overkill for the single variable that actually races

**Why it matters**:
- Masks the real synchronization problem: only `m_diskCursor` needs protection
- Adds overhead from recursive lock even when no actual re-entrancy occurs

**Better approach**:
- Use `std::atomic<uint32_t> m_diskCursor` instead of a protected variable
- Eliminate most trace locks; use atomic CAS or simple increments for cursor updates
- Keep `m_traceMutex` only for ring buffer resizes (if they happen)

---

### LOW PRIORITY

#### Fix 6: Lock-Free Printer Output (Est. 30 min)

**Location**: `Core/TMC0501.cpp:767–770, 784–787, 1152, 1157` and `m_prnMutex`

**Current Problem**:
- Single-producer (emulation), single-consumer (UI at 60 Hz) pattern
- `m_prnMutex` adds latency without preventing any actual races
- Printer is not on the hot path but lock still acquired on every drain

**Better approach**: Atomic swap
- Use two printer buffers: one being filled by CPU, one drained by UI
- Swap atomically at 60 Hz tick (no lock needed during regular operation)

---

#### Fix 7: ViewModel Locking Simplification (Est. 20 min, documentation-only)

**Location**: `App/EmulatorViewModel.swift:307–374`

**Current Problem**:
- Emulation loop calls `m.step()` which acquires `m_keyMutex` internally
- Key operations from UI also acquire `m_keyMutex`
- Results in correct but unnecessarily nested locking

**Note**: This is **functional and safe as-is**. The "fix" is purely a documentation/clarity improvement for future maintainers. Only tackle if you're refactoring the Swift/C++ bridge.

---

## Lock Ownership Map (Current + Post-Fixes)

### Current (v1.2)

| Mutex | Protects | Acquisition Points |
|-------|----------|-------------------|
| `m_keyMutex` | step, keys, card, printer drain, debug, breakpoints, reset | 16 places in TI59Machine |
| `m_displayMutex` | display snapshot read | `getDisplay()` only |
| `m_traceMutex` | frame ring buffer (recursive) | `tracePreStep/PostStep/beginNextStep` (nested) |
| `m_prnMutex` | printer buffer lock | printer drain operations |

### Post-Fixes (v1.3+)

| Mutex | Protects | Acquisition Points |
|-------|----------|-------------------|
| `m_keyInputMutex` | step, keys, printer drain, debug, breakpoints, reset | emulation loop + UI actions |
| `m_cardMutex` | card I/O state | card insertion/eject only |
| `m_traceMutex` (std::mutex) | frame ring buffer | single critical section in step loop |
| (none) | display snapshot | atomic swap in getDisplay() |
| (none) | printer buffer | atomic swap at 60 Hz tick |

---

## Testing Strategy

For each fix:
1. Run existing unit tests (trace, display, printer)
2. Manual testing: verify 60 Hz display refresh, trace drain, keyboard responsiveness
3. Check for regressions in debug panel live update (should be smoother, not jankier)
4. Profile: measure lock contention using `DTrace` or `Instruments` before/after

---

## Timeline

- **v1.2** (current): Fix 1 (done)
- **v1.3** (next release): Fixes 2–5 (high + medium priority)
- **v1.4** (polish): Fixes 6–7 (low priority / documentation)

---

## References

- [Lock Granularity Anti-Patterns](https://preshing.com/20111124/always-use-a-lightweight-lock/)
- [Double-Buffer Pattern](https://en.wikipedia.org/wiki/Multiple_buffering)
- [Atomic Operations in C++](https://en.cppreference.com/w/cpp/atomic/atomic)
- Project memory: [[Live Debug Panel (60 Hz)]] — discusses the display timing model

