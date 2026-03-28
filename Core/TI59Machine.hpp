#pragma once
#include "ROM.hpp"
#include "RAM.hpp"
#include "TMC0501.hpp"
#include <cstdint>
#include <mutex>
#include <vector>

enum class MachineVariant { TI59, TI58, TI58C };

class TI59Machine {
public:
    explicit TI59Machine(MachineVariant variant);

    void loadROM(const uint16_t* data, size_t count);
    void loadLibrary(const uint8_t* data, size_t count);
    void reset();

    /// Execute one CPU instruction.
    uint32_t step();

    /// Key input — thread-safe.
    void pressKey(int row, int col);
    void releaseKey(int row, int col);

    /// Display — safe to call from any thread.
    DisplaySnapshot getDisplay() const;

    /// TI-58C persistence helpers.
    void serialiseRAM(uint8_t* dst) const;   // 120*16 bytes
    void deserialiseRAM(const uint8_t* src);

    // ── State file load helpers ───────────────────────────────────────────────
    /// Write keycodes[0..count-1] to program RAM starting at step 0.
    void writeProgram(const uint8_t* keycodes, int count);

    /// Write 16 nibbles to RAM[partitionProgramRegs + regNum].
    void writeDataRegister(int regNum, const uint8_t* nibbles16);

    /// Current program-register count read live from SCOM[9][0] * 10.
    /// Reflects whatever the ROM last set via OP 17.
    int partitionProgramRegs() const;

    /// Write the partition directly into SCOM (SCOM[9][0] and SCOM[13][8..9]).
    /// programRAMregs must be a multiple of 10 in the range 0–120.
    void setPartitionProgramRegs(int programRAMregs);

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
    std::vector<std::string>             drainPrinterLines();
    std::vector<std::array<uint8_t,20>> drainPrinterCodeLines();
    void pressPrinterPrint(bool pressed);
    void pressPrinterAdv(bool pressed);
    void setPrinterTrace(bool enabled);

    // ── Trace / debug API ─────────────────────────────────────────────────────
    void     setTraceFlags(uint32_t flags);
    uint32_t traceFlags() const;

    void addBreakpoint(uint16_t pc);
    void removeBreakpoint(uint16_t pc);
    void clearBreakpoints();

    uint32_t drainTraceEvents(TraceEvent* out, CPUSnapshot* outSnaps, uint32_t max);
    bool     peekLastEvent(TraceEvent& out, CPUSnapshot* outSnap) const;

    /// Run up to n steps under a single mutex lock; returns count actually executed.
    /// Stops early if a breakpoint is hit (when TRACE_BREAKPOINTS is set).
    uint32_t stepN(uint32_t n, bool stopOnBreakpoint = true);

    /// Current program counter (for CLI inspection between stepN calls).
    uint16_t pc() const;

    static std::string disassemble(uint16_t pc, uint16_t opcode);

    // ── Calculator-level API ──────────────────────────────────────────────────

    /// Decode a 16-nibble TI-59 BCD register to a double.
    static double decodeBCD(const uint8_t* nibbles16);

    /// Read data register regNum (0–58) decoded as double.
    double readDataReg(int regNum) const;

    /// Read program step stepAddr (0–479) as 2-digit keycode (0–99).
    uint8_t readProgramStep(int stepAddr) const;

    /// Capture a snapshot of all CPU registers at the current instant.
    CPUSnapshot snapshotCPU() const;

    /// Raw RAM access — reads/writes a complete 16-nibble register.
    /// reg must be in [0, RAM::TOTAL_REGS).
    const uint8_t* readRAMReg(int reg) const { return m_ram.readReg(reg); }
    void           writeRAMReg(int reg, const uint8_t* nibbles16) { m_ram.writeReg(reg, nibbles16); }
    int            ramRegCount() const { return m_ram.size(); }

    /// Content currently held in the printer character buffer (not yet printed).
    std::string printerBufferContent() const;

    MachineVariant variant() const { return m_variant; }

private:
    MachineVariant m_variant;
    ROM            m_rom;
    RAM            m_ram;
    TMC0501        m_cpu;
    mutable std::mutex m_keyMutex;

    int cardSwitchCol() const; // Digit-counter column for the card-switch key.
};
