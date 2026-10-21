#pragma once
#include "ROM.hpp"
#include "RAM.hpp"
#include "TMC0501.hpp"
#include "MachineVariant.hpp"
#include <cstdint>
#include <mutex>
#include <vector>

class TI59Machine {
public:
    explicit TI59Machine(MachineVariant variant);

    void loadROM(const uint16_t* data, size_t count);
    void loadLibrary(const uint8_t* data, size_t count);
    void loadConstants(const uint8_t* data, size_t count);
    void reset();

    /// Execute one CPU instruction. Returns TMC0501::step()'s weight and bits
    /// (kStepBoundary: the next instruction is the step dispatch), plus
    /// kBreakpointHit when a breakpoint was hit.
    uint32_t step();
    static constexpr uint32_t kWeightMask = TMC0501::kWeightMask;
    static constexpr uint32_t kStepBoundary = TMC0501::kStepBoundary;
    static constexpr uint32_t kPolledHardware = TMC0501::kPolledHardware;
    static constexpr uint32_t kBreakpointHit = 0x8000'0000u;

    /// The CPU state latched at the last step boundary or idle entry (count 0: none since reset).
    TMC0501::StepBoundary lastStepBoundary() const;

    /// Key input — thread-safe.
    void pressKey(int row, int col);
    void releaseKey(int row, int col);

    /// Display since the previous call — safe from any thread, but it restarts
    /// the integration window: one consumer per machine (see TMC0501).
    DisplaySnapshot takeDisplay();

    /// TI-58C persistence helpers.
    void serialiseRAM(uint8_t* dst) const;   // 120*16 bytes
    void deserialiseRAM(const uint8_t* src);

    // ── State file load helpers ───────────────────────────────────────────────
    /// Write keycodes[0..count-1] to program RAM starting at step 0.
    void writeProgram(const uint8_t* keycodes, int count);

    /// Write 16 nibbles to data register regNum (see dataRegCount()).
    void writeDataRegister(int regNum, const uint8_t* nibbles16);

    /// Current program-register count read live from SCOM[9][0] * 10.
    /// Reflects whatever the ROM last set via OP 17.
    int partitionProgramRegs() const;

    /// Write the partition directly into SCOM (SCOM[9][0] and SCOM[13][8..9]).
    /// programRAMregs must be a multiple of 10 in the range 0–120.
    void setPartitionProgramRegs(int programRAMregs);

    /// Current solid-state module number from SCOM[9] nibbles 3 (units) and 4 (tens).
    /// Returns 0 for no module, 1–30 for ML01–ML30.
    int insertedModuleNumber() const;

    /// Latched solid-state library execution address: module byte address
    /// (0–4999) of the keycode most recently dispatched by the program
    /// interpreter.  0xFFFF until a module keycode executes.
    uint16_t libExecPC() const;

    /// Cumulative weighted instruction-step count since the last reset() — see
    /// TMC0501::elapsedTicks(). Divide by the machine's active-mode instruction rate
    /// to get elapsed wall-clock seconds.
    uint64_t elapsedTicks() const;

    // ── Magnetic card reader ─────────────────────────────────────────────────
    /// Insert a card immediately.  data/count non-zero = read card (feeds IN CRD);
    /// zero = blank write card (OUT CRD captured).
    void insertCard(const uint8_t* data, size_t count);

    /// Eject the card; returns bytes captured by OUT CRD (empty for read swipes).
    std::vector<uint8_t> cardEject();

    bool isCardPresent()    const;  ///< True while card is passing through reader.
    bool isWaitingForCard() const;  ///< True while ROM is polling TST BUSY for card.
    int  cardMode()         const;  ///< 0=none, 1=read, 2=write

    // ── Printer ──────────────────────────────────────────────────────────────
    std::vector<std::string>     drainPrinterLines();
    std::vector<PrinterCodeLine> drainPrinterCodeLines();
    void pressPrinterPrint(bool pressed);
    void pressPrinterAdv(bool pressed);
    void setPrinterTrace(bool enabled);
    bool printerTrace() const { return m_printerTrace; }  ///< the TRACE latch
    void setPrinterConnected(bool connected);
    bool isPrinterConnected() const { return m_printerConnected; }

    // ── Trace / debug API ─────────────────────────────────────────────────────
    void     setTraceFlags(uint32_t flags);
    uint32_t traceFlags() const;

    void setDebugLevel(uint8_t level);
    std::vector<DebugEvent> drainDebugEvents();

    void addBreakpoint(uint16_t pc);
    void removeBreakpoint(uint16_t pc);
    void clearBreakpoints();

    /// Load debug ASM words into overlay region 0x1800+. Returns false on overflow.
    bool loadDebugOverlay(const uint16_t* data, size_t count);

    /// Clear all debug ASM overlay words.
    void clearDebugOverlay();

    /// Force execution entry at startAddr. Returns true when entry succeeded.
    bool runDebugOverlay(uint16_t startAddr, uint32_t maxSteps,
                         uint32_t* outSteps);

    uint32_t drainCpuFrames(CpuFrame* out, uint32_t max, uint32_t* outLost);
    uint32_t readCpuFrames(CpuFrame* out, uint32_t max) const;

    /// Run up to n steps under a single mutex lock; returns count actually executed.
    /// Stops early if a breakpoint is hit (when TRACE_BREAKPOINTS is set).
    uint32_t stepN(uint32_t n, bool stopOnBreakpoint = true);

    /// Run until the interpreter is about to execute the next program byte (a
    /// step boundary, see step()), a breakpoint, or maxCycles cycle-equivalents
    /// (IDLE steps count as 4, active steps as 1) — e.g. when the program stops.
    /// One call per keycode, as SST: a jump completes inside the byte that
    /// causes it. Returns cycle-equivalents executed.
    uint32_t stepUntilNextKeycode(uint32_t maxCycles = 50000);

    /// Current program counter (for CLI inspection between stepN calls).
    uint16_t pc() const;

    static std::string disassemble(uint16_t pc, uint16_t opcode);

    // ── Calculator-level API ──────────────────────────────────────────────────

    /// Decode a 16-nibble TI-59 BCD register to a double.
    static double decodeBCD(const uint8_t* nibbles16);

    /// Read data register regNum (see dataRegCount()) decoded as double.
    double readDataReg(int regNum) const;

    /// Data registers as the ROM addresses them: Rnn = RAM[dataRegCount() - 1 - nn],
    /// descending to meet the program at the partition. 120 on the TI-59, 60 on
    /// the TI-58/58C, where the TI-58C's 4 extra registers (H00–H03, RAM 60–63)
    /// sit above R00 — unless the TI-58C is partitioned like a TI-59
    /// (examples/repartition.ti58c): then it is 120 and only R56–R59 exist, on
    /// the extra registers. Registers without RAM read 0 and ignore writes.
    int dataRegCount() const;

    /// Read program step stepAddr (0–479) as 2-digit keycode (0–99).
    uint8_t readProgramStep(int stepAddr) const;

    /// Read a ROM keycode at address 0–383.
    uint8_t readROMKeycode(int addr) const;

    /// Capture a snapshot of all CPU registers at the current instant.
    CpuFrame snapshotCPU() const;

    /// Pre-execution phase: COND restore, patch previous ring entry, capture snapshot.
    /// Call after stepUntilNextKeycode() or after step() in debugger mode.
    void beginNextStep();

    /// Raw RAM access — copies/writes a complete 16-nibble register under the lock.
    /// reg must be in [0, ramRegCount()).
    void copyRAMReg(int reg, uint8_t* out16) const;
    void writeRAMReg(int reg, const uint8_t* nibbles16);
    /// Constant after construction; safe to call without locking.
    int  ramRegCount() const { return m_ram.size(); }

    /// Content currently held in the printer character buffer (not yet printed).
    std::string printerBufferContent() const;

    MachineVariant variant() const { return m_variant; }

private:
    int dataRegCountLocked() const;
    int dataRegRAMIndexLocked(int regNum) const;  // -1: no RAM behind it
    MachineVariant m_variant;
    ROM            m_rom;
    RAM            m_ram;
    TMC0501        m_cpu;
    // ── Lock policy ───────────────────────────────────────────────────────
    // m_keyMutex serialises the emulation thread (step/stepN/…) against every
    // UI-thread access to CPU, SCOM, RAM, card and printer-buffer state —
    // including the read-only accessors (snapshotCPU, readDataReg, copyRAMReg,
    // partitionProgramRegs, card getters, printerBufferContent, pc).
    // Exceptions, each with their own synchronisation:
    //   takeDisplay()               → m_displayMutex inside TMC0501
    //   drainPrinterLines/CodeLines → m_prnMutex inside TMC0501
    //   drain/readCpuFrames         → m_traceMutex inside TMC0501
    //   setTraceFlags/traceFlags    → std::atomic
    //   readROMKeycode/disassemble  → immutable after load / pure
    mutable std::mutex m_keyMutex;
    bool           m_printerConnected = true;
    // The printer's TRACE button is a physical hardware latch: it stays pressed
    // until physically released, so it must survive a calculator reset (which
    // wipes key[]).  We track its state here and re-apply it in reset().  It is
    // released only when the printer is attached or detached (setPrinterConnected).
    bool           m_printerTrace     = false;

    int cardSwitchCol() const; // Digit-counter column for the card-switch key.
};
