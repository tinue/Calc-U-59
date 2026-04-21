# Plan: Latched Key Press for CPU Inspector Frozen/Step Mode

## Context

When the CPU Inspector is frozen and the user taps a calculator key then presses STEP,
the key is already released by the time the CPU's KEY_ALL scan opcode executes. The
KEY_ALL opcode (0x08xx, bit 3 = 0) scans digit slots 14→1, setting FLG_HOLD each cycle
until a key match is found or digit 0 is reached. By the time `stepFrozen()` runs,
`key[col]` is already clear — the key is never detected.

The fix: a **C++ latch** inside `TMC0501`. Swift calls `latchMatrixKey:` on release
(instead of `releaseMatrixKey:`), which sets the latch in the C++ core. The core then
auto-releases the latch inside `step()` when the KEY_ALL scan completes — either
because a key was detected or digit 0 was reached. This works transparently for both
single-step and Resume, with no trace-buffer inspection or Swift-side polling.

**Why C++ over the existing Swift-only plan (plan-key-latch-frozen-step.md):**
- Auto-release is self-contained inside `step()` — no trace read needed
- Resume works automatically: the latch propagates to the live loop, KEY_ALL detects it
- Thread-safe: latch state is mutated only under `m_keyMutex` (same lock as `step()`)
- Simpler Swift side: only `releaseKey(row:col:)` changes

---

## KEY_ALL Scan Mechanics (Validated Against CALCU59_TRACE.ans)

The IDLE loop at 0x657 uses `WAIT D14` (0x656) to synchronize the digit counter to 14
before `KEY 20` (opcode 0x0820). On a full iteration, KEY 20 scans digit slots 13→1
under HOLD (13 cycles) then exits at digit 0 (1 more step) = **14 steps maximum**.

`stepFrozen()` already auto-forwards through FLG_HOLD with `limit = 32` — sufficient
for KEY_ALL's max 14 cycles. After the scan:
- Key detected (digit N matched): HOLD not set, COND cleared, KR updated, PC advances
- Digit 0 reached, no key: HOLD not set, PC advances

In both cases `!(flags & FLG_HOLD)` is the correct auto-release trigger.

---

## Critical Files

| File | Change |
|---|---|
| `Core/TMC0501.hpp` | Add latch state fields + method declarations |
| `Core/TMC0501.cpp` | Implement `latchKey`/`releaseLatch`; modify KEY_ALL handler and `releaseKey` |
| `Core/TI59Machine.hpp` | Declare `latchKey` / `releaseLatch` |
| `Core/TI59Machine.cpp` | Mutex-guarded wrappers (3 lines each) |
| `Bridge/TI59MachineWrapper.h` | Declare `-latchMatrixKey:` and `-releaseLatch` |
| `Bridge/TI59MachineWrapper.mm` | Implement (same kbits[] mapping as pressMatrixKey) |
| `App/EmulatorViewModel.swift` | Modify `releaseKey(row:col:)` only |

---

## Step-by-Step Changes

### 1. `Core/TMC0501.hpp` — add latch state after `key[16]` (line 322)

```cpp
// ── Latched key (for frozen/single-step mode) ─────────────────────
// When Swift calls latchKey(), the bit stays set in key[] until KEY_ALL
// completes (detected inside step()). Thread safety: accessed only under
// TI59Machine::m_keyMutex, which wraps every step()/pressKey()/releaseKey().
int  m_latchRow { -1 };
int  m_latchCol { -1 };
bool m_latchActive { false };
```

Also add method declarations alongside `pressKey`/`releaseKey`:
```cpp
void latchKey(int row, int col);   // arm latch; key bit stays set until KEY_ALL
void releaseLatch();               // force-clear latch (used on machine reset)
```

### 2. `Core/TMC0501.cpp` — new methods + KEY_ALL + releaseKey

**`latchKey`** (after `releaseKey` near line 255):
```cpp
void TMC0501::latchKey(int row, int col) {
    if (m_latchActive && (m_latchRow != row || m_latchCol != col))
        releaseKey(m_latchRow, m_latchCol);   // displace previous latch
    m_latchRow = row;
    m_latchCol = col;
    m_latchActive = true;
    pressKey(row, col);   // ensure bit set (idempotent)
}
```

**`releaseLatch`**:
```cpp
void TMC0501::releaseLatch() {
    if (m_latchActive) {
        releaseKey(m_latchRow, m_latchCol);
        m_latchActive = false;
    }
}
```

**Modify `releaseKey`** — if the released key is the latched key, clear flag too:
```cpp
void TMC0501::releaseKey(int row, int col) {
    if (col >= 0 && col < 16 && row >= 0 && row < 7) {
        key[col] &= static_cast<uint8_t>(~(1U << row));
        if (m_latchActive && m_latchRow == row && m_latchCol == col)
            m_latchActive = false;
    }
}
```

**KEY_ALL handler** — add one block after the `if/else if (digit)` block (line 525),
still inside `if (!(opcode & 0x0008u))`:
```cpp
// Auto-release latch when scan completes (key detected OR digit 0 reached).
if (!(flags & FLG_HOLD) && m_latchActive)
    releaseLatch();
```

### 3. `Core/TI59Machine.hpp` — add after `releaseKey` declaration (line 24)

```cpp
void latchKey(int row, int col);   ///< Latch a key — thread-safe.
void releaseLatch();               ///< Force-clear latch — thread-safe.
```

### 4. `Core/TI59Machine.cpp` — add after `releaseKey` (line 57)

```cpp
void TI59Machine::latchKey(int row, int col) {
    std::lock_guard<std::mutex> lock(m_keyMutex);
    m_cpu.latchKey(row, col);
}

void TI59Machine::releaseLatch() {
    std::lock_guard<std::mutex> lock(m_keyMutex);
    m_cpu.releaseLatch();
}
```

Also call `m_cpu.releaseLatch()` inside `reset()` (already acquires lock) to clear any
stale latch on machine reset.

### 5. `Bridge/TI59MachineWrapper.h` — add after `releaseMatrixKey:`

```objc
- (void)latchMatrixKey:(uint8_t)matrixCode;
- (void)releaseLatch;
```

### 6. `Bridge/TI59MachineWrapper.mm` — add after `releaseMatrixKey:` (line 279)

```objc
- (void)latchMatrixKey:(uint8_t)matrixCode {
    int row = matrixCode / 10;
    int col = matrixCode % 10;
    if (col < 1 || col > 5 || row < 1 || row > 9) return;
    _machine->latchKey(kbits[col], row);
}

- (void)releaseLatch {
    _machine->releaseLatch();
}
```

### 7. `App/EmulatorViewModel.swift` — modify `releaseKey` only (line 408)

```swift
func releaseKey(row: Int, col: Int) {
    traceWriter.writeKeyUp(row: UInt8(row), col: UInt8(col))
    let matrixCode = UInt8((row + 1) * 10 + (col + 1))
    if isFrozen {
        machine?.latchMatrixKey(matrixCode)   // C++ holds the bit until KEY_ALL fires
    } else {
        machine?.releaseMatrixKey(matrixCode)
    }
}
```

No changes to `pressKey`, `unfreeze`, `stepFrozen`, or `stepKeycode`.

---

## Edge Cases

| Scenario | Behavior |
|---|---|
| Single-step through KEY_ALL | `stepFrozen()` already auto-forwards through all HOLD cycles; latch auto-released when digit 0 or key found |
| Multiple STEPs before KEY_ALL | Latch persists in `key[]`; each STEP that doesn't hit KEY_ALL leaves latch intact |
| RESUME (unfreeze) | Latch stays active; live loop hits KEY_ALL and auto-releases — user's intended key press is delivered |
| Drag to different key while frozen | `latchKey()` releases old latch before recording new one |
| Key never detected (KEY_ALL at digit 0) | `releaseLatch()` is called anyway — scan completed, user can re-press |
| Machine reset | `reset()` calls `m_cpu.releaseLatch()` — clean state |
| Two rapid latches same key | `latchKey()` with same row/col is a no-op (condition `!=` is false) |

---

## Verification

1. Freeze while ROM is in the IDLE keyboard scan loop (KEY_ALL executing repeatedly)
2. Tap a calculator key, lift finger — key should visually release on screen
3. Press STEP — `stepFrozen()` auto-forwards through the HOLD cycles; inspector should show COND cleared and KR updated with the key's encoding
4. Press STEP again — key should NOT be detected (latch was auto-released after step 3)
5. Press RESUME — verify no phantom key press in running emulation (latch already gone)
6. Extended: tap key, press STEP multiple times through unrelated instructions (WAIT Dn, branches), verify key is only detected when KEY_ALL finally executes
7. Drag from key A to key B while frozen, then STEP — only key B should be detected
