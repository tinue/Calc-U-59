# Plan: Display keycodes from ROM sources in PROGRAM STEPS

## Context

The PROGRAM STEPS debug panel currently shows keycodes sourced from user RAM (PRG SOURCE = 0). When PRG SOURCE transitions to non-zero, the code freezes the display at the last user-RAM step. The user wants real keycodes from the active source:

- **PRG SOURCE = 0**: user RAM (existing behavior) ✓
- **PRG SOURCE = 1**: solid-state library module (5000-byte `m_libData` in TMC0501) — *TODO*
- **PRG SOURCE = 8**: main ROM (384 keycode programs from constants) ← **THIS PHASE**

## Key Discovery

ROM keycode programs are **pre-decoded and stored in `m_constant[64][16]`**:
- Rows 0–15: mathematical constants (NUMBER section)
- Rows 16–63: keycode programs (KEY CODE section) = 48 rows × 8 keycodes/row = 384 keycodes
- Stored as nibble pairs (packed-BCD): each keycode = `(high_nibble * 10) + low_nibble`

**Mapping formula** (PC 0–383 → keycode):
```
row = 16 + (pc / 8)
offset = (pc % 8) * 2
keycode = (m_constant[row][offset+1] * 10) + m_constant[row][offset]
```

## Files to change (ROM phase only)

1. `Core/TMC0501.hpp` — add `romKeycode()` accessor
2. `Core/TI59Machine.hpp` / `.cpp` — add `readROMKeycode()`
3. `Bridge/TI59MachineWrapper.h` / `.mm` — expose `romKeycode(at:)` to Swift
4. `App/EmulatorViewModel.swift` — add PRG SOURCE = 8 case in program-steps block

## Changes

### 1. `Core/TMC0501.hpp` — add public accessor
After the existing public methods, add:
```cpp
/// Read a ROM keycode (PRG SOURCE = 8) by address 0–383.
/// Returns 0 for out-of-range addresses.
uint8_t romKeycode(int addr) const {
    if (addr < 0 || addr >= 384) return 0;
    int row = 16 + (addr / 8);
    int offset = (addr % 8) * 2;
    uint8_t units = m_constant[row][offset];
    uint8_t tens = m_constant[row][offset + 1];
    return (uint8_t)(tens * 10 + units);
}
```

### 2. `Core/TI59Machine.hpp` — declare method
Add to the public section:
```cpp
/// Read a ROM keycode at address 0–383.
uint8_t readROMKeycode(int addr) const;
```

### 3. `Core/TI59Machine.cpp` — implement
Add after the existing `readProgramStep()` method:
```cpp
uint8_t TI59Machine::readROMKeycode(int addr) const {
    return m_cpu.romKeycode(addr);
}
```

### 4. `Bridge/TI59MachineWrapper.h` — declare method
Add to the `@interface`:
```objc
/// Read a ROM keycode at address 0–383.
- (uint8_t)romKeycodeAt:(NSInteger)addr
    NS_SWIFT_NAME(romKeycode(at:));
```

### 5. `Bridge/TI59MachineWrapper.mm` — implement
Add after the `allProgramSteps` method:
```objc
- (uint8_t)romKeycodeAt:(NSInteger)addr {
    return _machine->readROMKeycode((int)addr);
}
```

### 6. `App/EmulatorViewModel.swift` — add ROM case
In `buildLiveSnapshot()`, find the `// Program steps window` block (~line 802).

**Replace** with a switch on `snap.prSourceFlag`:

```swift
// Program steps window — source depends on PRG SOURCE flag
switch snap.prSourceFlag {

case 0:
    // User RAM — existing behavior
    let steps = Array(m.allProgramSteps() as Data)
    snap.currentStep = decodeProgramCounter(from: cpu)
    if !steps.isEmpty { buildRAMWindow(into: &snap, steps: steps) }

case 8:
    // Main ROM (384 keycode programs from constants)
    snap.currentStep = decodeProgramCounter(from: cpu)
    let romCenter = snap.currentStep
    let lo = max(0, romCenter - 5)
    let hi = min(383, romCenter + 5)
    for addr in lo...hi {
        let keycode = m.romKeycode(at: addr)
        let mnemonic = TI59KeyNames.mnemonic(for: keycode)
        snap.programWindow.append(.init(
            stepNum: addr, keycode: keycode, mnemonic: mnemonic,
            isCurrent: addr == romCenter))
    }

default:
    // PRG SOURCE = 1 (library) or other: TBD
    break
}
```

**Also remove** from the same file:
- `private var lastPrSourceFlag: UInt8 = 0` (if it exists)
- `private var frozenProgramCounter: Int? = nil` (if it exists)
- Any `if let frozen = ...` blocks referencing frozen program counter

## Verification

1. **ROM test**: boot to main ROM and press keys; confirm PROGRAM STEPS shows decoded keycodes (0–99) with correct mnemonics.
2. **Boundary**: ensure no crash at edges (addr 0, addr 383).
3. **Baseline**: run user program (PRG SOURCE = 0) to confirm existing RAM behavior untouched.
