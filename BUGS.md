# Emulator Bug Tracker

## BUG-001 — Test-row key scan falsely detects key at digit 0

**Status:** Suspected — identified via execution trace comparison with reference emulator.
**Priority:** High — causes complete execution-path divergence on every key press.

### Symptom

When the ROM executes a test-row `KEY n,Dm` instruction after a `WAIT D1`,
the emulator incorrectly clears COND ("key found") where the reference keeps COND=1
("key not found").

First observed sequence:
```
#16  068B 0A10  WAIT D1          [both match]
#17  068C 08FB  KEY 15,D3        [both match — same state entering the scan]
#18  068D 182A  BRC 06A2 +015   ← DIVERGENCE
     ref:  COND=1 → branch taken  → continues at 06A2 (normal key-dispatch path)
     mine: COND=0 → branch missed → falls through to 068E (wrong path)
```

### Root-cause hypothesis

File: `Core/TMC0501.cpp`, keyboard case `0x0800`, test-row branch (line ~544):

```cpp
// Test-row mode: check only the current row
if (key[digit] & kmask) flags &= ~FLG_COND;
```

After `WAIT D1` completes with `digit=1`, the next `step()` decrements digit to **0**.
`KEY 15,D3` (opcode `0x08FB`) then evaluates `key[0] & 0x04`.

`key[0]` should always be zero — digit 0 is the display-latch moment, not a keyboard row.
Somehow it has bit 2 set, causing a spurious key detection.

### Alternative hypotheses

**A — Wrong row for pressed key:**
`pressKey(row, col)` stores the key at `key[row]`.  If the UI-to-matrix mapping places
1/x at row 0 (or pressKey is called with row=0 for some key), `key[0]` gets polluted.
Check: what matrix code does the 1/x button emit? What row does that map to?

**B — `KEY n,Dm` should use the opcode-encoded digit, not the current counter:**
The mnemonic is `KEY 15,D3` — `D3` appears to name a specific digit row.
If the hardware always tests row 3 regardless of the current digit counter,
the implementation should be `key[(opcode & 7)] & kmask` instead of `key[digit] & kmask`.
With that fix, `key[3] & 0x04` would be tested. Since 1/x is at column 5 (K-line KT,
bit 6), `key[3] & 0x04` (bit 2) is still 0 → COND stays 1 → matches reference.
Needs TI-59 hardware documentation confirmation.

**C — Digit counter is not 0 when the instruction runs:**
If there is an off-by-one in WAIT Dn completion logic, `digit` might be 3 (the actual
row of the 1/x key) instead of 0. Then `key[3] & 0x04` would be 0 (key is at bit 6,
not bit 2), still matching the reference. But digit=0 is what the arithmetic implies.

### Next diagnostic steps

1. Add `snap.digit` to the trace log output (currently omitted — not in reference format,
   but valuable for this investigation). Inspect the digit counter value at PC `068C`.
2. Log `key[]` array contents at the moment `?KEY FB` executes.
3. Verify the matrix code and row for the 1/x key in the UI layer.
4. Check TI-59 hardware guide §keyboard-scan for `KEY n,Dm` semantics.

### How to reproduce

```
python3 compare_trace.py 1overx.LOG TI59_TRACE.LOG
```

Expected output: first divergence at instruction #18, PC `068D`.
