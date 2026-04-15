# Plan: Key Press Latch for Frozen/Step Mode

## Context
When stepping through code in the frozen CPU inspector, pressing a UI key then pressing
STEP doesn't work. The key is released (gesture ended) before STEP is tapped, so
`key[digit]` is already cleared. The CPU's KEY scan-all opcode sets FLG_HOLD and
re-executes for ~16 digit-counter cycles — it will never see the key.

The fix: latch the key in the ViewModel when released while frozen, keeping it held in
C++ `key[]` across **multiple steps** (WAIT instructions, branches, etc.), and only
release it once the CPU actually executes a `KEY_ALL` instruction (detected from the
trace buffer after each step).

## Key Background
- `KEY_ALL` scan (opcode `0x08xx` with bit 3 = 0) sets FLG_HOLD each cycle until a key
  matches or digit 0 is reached. Disasm: `"KEY_ALL %u"`
- `stepFrozen()` already auto-forwards through FLG_HOLD states — no extra looping needed
- `readTraceEvents(max:)` reads ring buffer **without draining** (safe on emulQueue,
  won't disturb `captureInspectorSnapshot`)
- Trace events include `pc`, `opcode`, `seqno`;
  `TI59MachineWrapper.disassemblePC(pc, opcode:)` gives disasm string

## Critical File
`App/EmulatorViewModel.swift` — only file that needs changes

---

## Changes

### 1. Add latch state (near frozen-state properties, ~line 78)
```swift
private var latchedMatrixKey: UInt8? = nil
```

### 2. Modify `releaseKey(row:col:)` (line 395)
When frozen, latch instead of releasing immediately. If a different key was already
latched (slide-off), release it first to avoid stale bits in `key[]`.
```swift
func releaseKey(row: Int, col: Int) {
    traceWriter.writeKeyUp(row: UInt8(row), col: UInt8(col))
    let matrixCode = UInt8((row + 1) * 10 + (col + 1))
    if isFrozen {
        if let old = latchedMatrixKey, old != matrixCode {
            machine?.releaseMatrixKey(old)   // clear previously latched key
        }
        latchedMatrixKey = matrixCode        // hold until KEY_ALL executes
    } else {
        machine?.releaseMatrixKey(matrixCode)
    }
}
```

### 3. Add `releaseLatchedKey()` private helper
```swift
private func releaseLatchedKey() {
    if let code = latchedMatrixKey {
        latchedMatrixKey = nil
        machine?.releaseMatrixKey(code)
    }
}
```

### 4. Modify `stepFrozen()` — detect KEY_ALL completion on emulQueue
After the HOLD loop (still on `emulQueue`), read the last trace event and check
if it was KEY_ALL. Pass result to main-thread callback.

```swift
// add after the existing HOLD loop, still inside emulQueue.async:
let lastIsKeyScan: Bool = {
    let events = m.readTraceEvents(max: 1) as [NSValue]
    guard let v = events.last else { return false }
    var e = TITraceEvent(); v.getValue(&e)
    return TI59MachineWrapper.disassemblePC(e.pc, opcode: e.opcode).hasPrefix("KEY_ALL")
}()

// replace the existing DispatchQueue.main.async block with:
DispatchQueue.main.async { [weak self] in
    guard let self else { return }
    self.captureInspectorSnapshot(machine: m)
    if lastIsKeyScan { self.releaseLatchedKey() }
}
```

### 5. Modify `stepKeycode()` — scan recent trace events for KEY_ALL
`stepUntilNextKeycode()` runs many instructions; KEY_ALL may occur mid-step.
Read the last 64 events and check if any were KEY_ALL.

```swift
// add after _ = m.stepUntilNextKeycode(), still inside emulQueue.async:
let hadKeyScan: Bool = {
    let events = m.readTraceEvents(max: 64) as [NSValue]
    return events.contains { v in
        var e = TITraceEvent(); v.getValue(&e)
        return TI59MachineWrapper.disassemblePC(e.pc, opcode: e.opcode).hasPrefix("KEY_ALL")
    }
}()

// add at end of the existing DispatchQueue.main.async block (after captureInspectorSnapshot):
if hadKeyScan { self.releaseLatchedKey() }
```

### 6. Modify `unfreeze()` — cleanup
Add at the very top of `unfreeze()`, before `freezeReason = nil`:
```swift
releaseLatchedKey()   // release before resuming live loop
```

---

## Edge Cases
| Scenario | Behavior |
|---|---|
| RESUME without stepping | `unfreeze()` releases latch before live loop starts |
| Multiple STEPs before KEY_ALL | Latch persists across all steps; released only when KEY_ALL executes |
| Slide to different key while frozen | Old latch released immediately; new key latched |
| KEY_ALL reaches digit 0 without detecting | Latch released anyway — scan completed, user can re-press |
| Breakpoint hit during step | `lastIsKeyScan` evaluated before breakpoint; latch released if KEY_ALL ran |
| `stepKeycode()` before idle loop reaches KEY_ALL | `hadKeyScan = false` → latch preserved for next STEP call |

## No Changes Needed
- `KeyboardView.swift` — calls `releaseKey(row:col:)` normally
- `TI59MachineWrapper.mm` / C++ — `releaseMatrixKey` is thread-safe via `m_keyMutex`

## Verification
1. Freeze while ROM is in the IDLE scan loop (KEY_ALL executing repeatedly)
2. Press a calculator key in the UI, release it, then press STEP
3. HOLD auto-forward should cycle through digits and detect the key
   (COND cleared, KR updated with key encoding in inspector)
4. Press STEP again — key should NOT be detected again (latch was released)
5. Press RESUME — verify no phantom key press in running emulation
6. Extended test: press key, then STEP through several WAIT instructions;
   confirm key detected only when KEY_ALL finally executes
