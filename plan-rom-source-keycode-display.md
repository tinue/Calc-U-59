# Plan: Display keycodes from ROM sources in PROGRAM STEPS

## Context

The PROGRAM STEPS debug panel currently shows keycodes sourced from user RAM (PRG SOURCE = 0). When PRG SOURCE transitions to non-zero, the code freezes the display at the last user-RAM step. The user wants real keycodes from the active source:

- **PRG SOURCE = 0**: user RAM (existing behavior)
- **PRG SOURCE = 1**: solid-state library module (5000-byte `m_libData` in TMC0501)
- **PRG SOURCE = 8**: main ROM (6144 × 13-bit words)

Library data is already loaded into `m_libData`; `m_libAddr` tracks the current read position. Library keycodes are stored as packed-BCD bytes: `(byte >> 4)*10 + (byte & 0xF)` = keycode 0–99. SCOM[0][4:7] (the step counter) updates during library execution — confirmed by `stepUntilNextKeycode()` comment.

## Files to change

1. `Core/TraceTypes.hpp` — add `libAddr` to `CPUSnapshot`
2. `Core/TMC0501.hpp` — add `libByte()` accessor
3. `Core/TMC0501.cpp` — populate `libAddr` in `snapshotCPU()`
4. `Core/TI59Machine.hpp` / `.cpp` — add `readLibraryBytes()` and `readROMWords()`
5. `Bridge/TI59MachineWrapper.h` — add `libAddr` to `TICPUSnapshot`, declare two new Bridge methods
6. `Bridge/TI59MachineWrapper.mm` — implement; update all 3 copy sites (lines ~214, ~276, ~353)
7. `App/EmulatorViewModel.swift` — rewrite program-steps block in `buildLiveSnapshot()`

## Changes

### 1. `Core/TraceTypes.hpp` — add field at end of `CPUSnapshot`
```cpp
struct CPUSnapshot {
    uint8_t  A[16], B[16], C[16], D[16], E[16];
    uint8_t  SCOM[16][16];
    uint8_t  Sout[16];
    uint16_t KR, SR, fA, fB, EXT, PREG, flags;
    uint8_t  R5, digit, REG_ADDR, RAM_ADDR, RAM_OP;
    uint16_t libAddr;   // ← NEW: library read pointer at snapshot time
};
```

### 2. `Core/TMC0501.hpp` — add public accessor
```cpp
uint8_t libByte(uint16_t addr) const {
    return (addr < 5000) ? m_libData[addr] : 0;
}
```

### 3. `Core/TMC0501.cpp` — populate in `snapshotCPU()`
After `s.RAM_OP = RAM_OP;`, add:
```cpp
s.libAddr = m_libAddr;
```

### 4. `Core/TI59Machine.hpp` — declare two new methods
```cpp
void readLibraryBytes(uint16_t addr, uint8_t* out, int count) const;
void readROMWords(uint16_t addr, uint16_t* out, int count) const;
```

### 5. `Core/TI59Machine.cpp` — implement
```cpp
void TI59Machine::readLibraryBytes(uint16_t startAddr, uint8_t* out, int count) const {
    for (int i = 0; i < count; i++)
        out[i] = m_cpu.libByte((startAddr + i) % 5000);
}

void TI59Machine::readROMWords(uint16_t startAddr, uint16_t* out, int count) const {
    for (int i = 0; i < count; i++)
        out[i] = m_rom.read(startAddr + i);
}
```
Note: `m_rom` is a private member accessible in this class; `ROM::read()` bounds-checks and returns 0 for out-of-range.

### 6. `Bridge/TI59MachineWrapper.h`
Add `libAddr` to `TICPUSnapshot` at the end (matching `CPUSnapshot`):
```objc
typedef struct {
    ...
    uint8_t  R5, digit, REG_ADDR, RAM_ADDR, RAM_OP;
    uint16_t libAddr;   // ← NEW
} TICPUSnapshot;
```

Add two new Bridge methods:
```objc
- (NSData*)libraryBytesAt:(uint16_t)addr count:(NSInteger)count
    NS_SWIFT_NAME(libraryBytes(at:count:));
- (NSData*)romWordsAt:(uint16_t)addr count:(NSInteger)count
    NS_SWIFT_NAME(romWords(at:count:));
```

### 7. `Bridge/TI59MachineWrapper.mm`
Add `out.libAddr = s.libAddr;` at all 3 copy sites (snapshotCPU ~line 353, drain loop ~214, read loop ~276).

Implement the two new methods:
```objc
- (NSData*)libraryBytesAt:(uint16_t)addr count:(NSInteger)count {
    NSMutableData* data = [NSMutableData dataWithLength:count];
    _machine->readLibraryBytes(addr, (uint8_t*)data.mutableBytes, (int)count);
    return data;
}
- (NSData*)romWordsAt:(uint16_t)addr count:(NSInteger)count {
    NSMutableData* data = [NSMutableData dataWithLength:count * 2];
    _machine->readROMWords(addr, (uint16_t*)data.mutableBytes, (int)count);
    return data;
}
```

### 8. `App/EmulatorViewModel.swift`

**Remove** `private var lastPrSourceFlag: UInt8 = 0` and `private var frozenProgramCounter: Int? = nil`.

**Replace** the entire `// Program steps window` block (~lines 802–850) with a 3-branch switch. Extract the existing RAM logic into a helper first:

```swift
private func buildRAMWindow(into snap: inout LiveDebugSnapshot, steps: [UInt8]) {
    let center = snap.currentStep >= 0 ? snap.currentStep : 0
    let lo = max(0, center - 5)
    let hi = min(steps.count - 1, center + 5)
    guard lo <= hi else { return }
    var argSteps = Set<Int>()
    for i in lo...hi {
        let n = TI59KeyNames.stepsAfter(for: steps[i])
        if n > 0 { for j in 1...n { if i + j <= hi { argSteps.insert(i + j) } } }
    }
    for i in lo...hi {
        let kc = steps[i]
        let mnemonic = argSteps.contains(i) ? String(format: "%02d", kc) : TI59KeyNames.mnemonic(for: kc)
        snap.programWindow.append(.init(stepNum: i, keycode: kc, mnemonic: mnemonic,
                                        isCurrent: i == snap.currentStep))
    }
}
```

Then replace the window block:
```swift
// Program steps window — source depends on PRG SOURCE flag
switch snap.prSourceFlag {

case 0:
    // User RAM — existing behavior
    let steps = Array(m.allProgramSteps() as Data)
    snap.currentStep = decodeProgramCounter(from: cpu)
    if !steps.isEmpty { buildRAMWindow(into: &snap, steps: steps) }

case 1:
    // Solid-state library: libAddr points to the *next* byte to read;
    // libAddr - 1 is the byte currently executing.
    let rawAddr = Int(cpu.libAddr)
    let centerAddr = rawAddr > 0 ? rawAddr - 1 : 0
    snap.currentStep = centerAddr
    let lo = max(0, centerAddr - 5)
    let count = min(11, 5000 - lo)
    let libData = Array(m.libraryBytes(at: UInt16(lo), count: count) as Data)
    for (offset, byte) in libData.enumerated() {
        let addr = lo + offset
        let keycode = UInt8((Int(byte) >> 4) * 10 + (Int(byte) & 0xF))
        snap.programWindow.append(.init(
            stepNum: addr, keycode: keycode,
            mnemonic: TI59KeyNames.mnemonic(for: keycode),
            isCurrent: addr == centerAddr))
    }

default:
    // Main ROM (PRG SOURCE = 8) or other: decoded SCOM step = ROM word address.
    // Try packed-BCD decode of low byte; fall back to raw hex with "R:" prefix.
    snap.currentStep = decodeProgramCounter(from: cpu)
    let romCenter = snap.currentStep
    let lo = max(0, romCenter - 5)
    let count = min(11, 6144 - lo)
    guard count > 0 else { break }
    let wordData = Array(m.romWords(at: UInt16(lo), count: count) as Data)
    for i in 0..<count {
        let addr = lo + i
        let word = UInt16(wordData[i * 2]) | (UInt16(wordData[i * 2 + 1]) << 8)
        let lowByte = UInt8(word & 0xFF)
        let tens = Int((lowByte >> 4) & 0xF)
        let units = Int(lowByte & 0xF)
        let bcdKc = tens * 10 + units
        let (keycode, mnemonic): (UInt8, String)
        if bcdKc <= 99 {
            keycode = UInt8(bcdKc)
            mnemonic = "R:\(TI59KeyNames.mnemonic(for: keycode))"
        } else {
            keycode = lowByte
            mnemonic = String(format: "R:%04X", word)
        }
        snap.programWindow.append(.init(
            stepNum: addr, keycode: keycode, mnemonic: mnemonic,
            isCurrent: addr == romCenter))
    }
}
```

Also remove the stale `frozenProgramCounter` usage lines (the `if let frozen = ...` block) since the switch replaces all of that.

## Edge-case notes

- **Library boundary**: `count = min(11, 5000 - lo)` prevents reads past byte 4999.
- **Library wrap**: `readLibraryBytes` wraps via `% 5000` in the C++ impl.
- **libAddr = 0 guard**: `rawAddr > 0 ? rawAddr - 1 : 0` avoids wrapping to 4999 at startup.
- **ROM: no mutex needed**: `m_libData`/`m_rom` are written only before emulation starts; reads are safe without lock.
- **Trace loop sites**: all 3 sites in TI59MachineWrapper.mm where `TICPUSnapshot` is filled need `libAddr` — lines ~214, ~276, ~353.

## Verification

1. **Baseline regression**: run a user program (PRG SOURCE = 0), confirm PROGRAM STEPS scrolls correctly.
2. **Library test**: load Master Library, run a library module program, confirm PROGRAM STEPS shows keycodes from library data with `libAddr - 1` as center.
3. **ROM test**: let the ROM take over (PRG SOURCE = 8), confirm panel switches away from frozen user-RAM steps and shows ROM-word data.
4. **Boundary**: step to very end of user RAM so ROM takes over naturally; confirm no crash or freeze.
