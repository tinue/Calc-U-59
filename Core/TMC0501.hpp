#pragma once
#include <array>
#include <cstdint>
#include <cstring>
#include <atomic>
#include <mutex>
#include <string>
#include <vector>
#include "TraceTypes.hpp"
#include "MachineVariant.hpp"

class ROM;
class RAM;

// ── Printer output line ───────────────────────────────────────────────────────
//
// Each printed character-line produces one PrinterCodeLine.  rowCount is 7 for
// a complete line; 1–6 when the print was aborted mid-stroke (a new PRT_PRINT
// arrived before the previous line's 197 ms BUSY window elapsed).
struct PrinterCodeLine {
    std::array<uint8_t, 20> codes{};
    uint8_t rowCount{7};   // dot-rows physically printed (1–7); 7 = complete
};

// ── Display snapshot ──────────────────────────────────────────────────────────
//
// Atomic copy of the display state, written by the CPU thread at every digit==0
// when IDLE is set, and read by the UI thread at 60 Hz.  All 12 visible digit
// positions come from the A and B registers; decimal point (R5) and the "C"
// annunciator are captured and buffered the same way.

struct DisplaySnapshot {
    uint8_t  digits[12]{};        ///< A[2..13] — BCD digit values (0–9, A–F)
    uint8_t  ctrl[12]{};          ///< B[2..13] — display-control nibbles (select digit vs. minus/degree/blank)
    uint8_t  dpPos{0};            ///< R5 — decimal-point position within the mantissa (0 = none, 2–13 valid)
    uint16_t dpAfterglowMask{0};  ///< Bitmask of dp positions with active afterglow: bit (pos-2) for positions 2..13.
                                  ///< Includes the current dpPos plus any recently-vacated positions still glowing.
                                  ///< Zero when no afterglow counter is active.
    uint16_t suppressedMask{0};   ///< Zero-suppression circuit output: bit i suppresses digit index i (0..11).
    float    calcIndicator{0.0f}; ///< fraction of the last poll interval where C LED was driven:
                                  ///<   RUN mode: any fA≠0; IDLE mode: fA bit 14 (SH pin, per HW guide). (0.0–1.0)
};

// ── Internal CPU flags ────────────────────────────────────────────────────────
//
// These are emulator-internal; they are NOT the hardware fA/fB flag registers
// (those are programmer-visible 16-bit registers).
//
// FLG_COND MUST stay at bit 11 (value 0x0800) so that the branch condition test
// "flags ^ opcode" works directly against opcode bit 11.

enum : uint16_t {
    // ── Execution control ───────────────────────────────────────────────
    FLG_IDLE      = 0x0001, // CPU is in display/idle mode.  SET by SET IDL, cleared by CLR IDL.
                            // While set, step() returns 4 instead of 1, implementing the
                            // hardware's 4× clock division in idle/low-power mode.
    FLG_HOLD      = 0x0002, // Freeze program counter — re-execute the same instruction next
                            // cycle.  Used by WAIT Dn (sync to digit counter) and KEY scan-all
                            // (holds until digit 0 or key detected).  Cleared at top of step().
    FLG_JUMP      = 0x0004, // Set after any branch executes (taken or not).  When the following
                            // non-branch instruction runs, COND is automatically restored to 1
                            // and this flag is cleared.  Implements the hardware's COND
                            // auto-restore behaviour between branch chains.

    // ── Deferred memory operations ─────────────────────────────────────
    // These implement two-cycle sequences where one instruction initiates a
    // store/recall and the next ALU instruction completes it.
    FLG_RECALL    = 0x0010, // Pending SCOM recall: next ALU const-read delivers SCOM[REG_ADDR].
    FLG_STORE     = 0x0020, // Pending SCOM store: after the next ALU, write Sout → SCOM[REG_ADDR].
    FLG_RAM_OP    = 0x0040, // Next Sout value is a RAM operation specifier (encodes address + opcode).
    FLG_RAM_READ  = 0x0080, // Pending RAM read: next ALU const-read delivers RAM[RAM_ADDR].
    FLG_RAM_WRITE = 0x0100, // Pending RAM write: after the next ALU, write Sout → RAM[RAM_ADDR].

    // ── One-cycle validity windows ──────────────────────────────────────
    // Some results are only valid for the cycle immediately following the
    // instruction that produced them; these flags gate that one-cycle window.
    FLG_EXT_VALID = 0x0200, // EXT register holds a valid result from IN CRD / IN LIB for one more cycle.
    FLG_IO_VALID  = 0x0400, // Sout holds a valid IO-bus result for one more cycle (destination code 1).

    // ── Condition flag ──────────────────────────────────────────────────
    // Active-high: COND=1 means "condition true".  TST/CMP/KEY/ALU-carry CLEAR
    // it (setting it false).  Branch instructions test bit 11 of the opcode
    // against this flag; the XOR trick requires it to sit at bit 11 exactly.
    FLG_COND      = 0x0800, // ← bit 11 — must match opcode bit 11 for the jump test

    // ── Miscellaneous ───────────────────────────────────────────────────
    FLG_BUSY      = 0x8000, // Printer / peripheral busy signal; tested by TST BUSY.
};

// ── TMC0501 CPU ───────────────────────────────────────────────────────────────
//
// 4-bit BCD digit-serial processor at the heart of the TI-59/58/58C.
// All arithmetic operates on 16-digit (64-bit) BCD registers, processing one
// digit per instruction cycle via a serial ALU.  Field masks select which
// subset of the 16 digits are actually written back to the destination.
//
// Clock: TI-59: 455 kHz oscillator ÷ 2 (two-phase) ÷ 16 (digit-serial cycle)
//        ≈ 14,219 instructions/sec in active mode; ÷4 further in idle mode.
//        TI-58/58C: 384 kHz oscillator ÷ 2 ÷ 16 ≈ 12,000 instructions/sec
//        (TI-58C runs at constant speed, no idle divisor).

class TMC0501 {
public:
    // Field mask descriptor (moved here for use in member variables)
    struct MaskInfo { uint8_t start, end, cpos, cval; };

    explicit TMC0501(ROM& rom, RAM& ram);

    void reset();

    /// Execute one instruction at the current program counter.
    ///
    /// Returns the cycle weight of this instruction for emulation pacing:
    ///   1 — normal instruction (active / computing mode)
    ///   4 — normal instruction while FLG_IDLE is set (idle/display mode runs
    ///       at 1/4 clock speed, matching the hardware's power-saving divider)
    int step();

    /// Press / release a key by hardware matrix coordinates.
    /// row = K-line bit index (KO=1 KP=2 KQ=3 KS=5 KT=6)
    /// col = digit-counter slot (D1–D9 for the 9 keyboard rows)
    void pressKey(int row, int col);
    void releaseKey(int row, int col);

    /// Load a library module image (up to 5,000 bytes).
    /// Used by the TI-59 magnetic card reader / solid-state library modules.
    void loadLibrary(const uint8_t* data, size_t count);

    /// Load constants from data (must be 1024 bytes for 64×16 rows).
    void loadConstants(const uint8_t* data, size_t count);

    // ── Magnetic card reader ─────────────────────────────────────────────────
    // The ROM polls TST BUSY in a tight loop after the user presses 2nd-Read
    // or 2nd-Write.  TST BUSY sets m_waitingForCard when it sees the card-switch
    // key asserted at digit == m_cardSwitchCol.  The Swift layer polls this flag
    // at 60 Hz; when it goes true the UI inserts the card after a short delay
    // by calling insertCard(), which releases the key and activates I/O.

    /// Tell the CPU which digit-counter slot the card-switch occupies.
    /// Must be called once at machine construction before any step().
    void setCardSwitchCol(uint8_t col) { m_cardSwitchCol = col; }

    /// Tell the CPU which machine variant is running (TI-59, TI-58, or TI-58C).
    /// Must be called once at machine construction before any step().
    void setMachineVariant(MachineVariant v) { m_variant = v; }

    /// Insert a card immediately.  data/count non-zero → read card (IN CRD
    /// feeds those bytes); zero → blank card (write-only, OUT CRD captured).
    /// Releases the card-switch key so the ROM exits its wait loop.
    void insertCard(const uint8_t* data, size_t count);

    /// Eject the card.  Restores the card-switch key; returns captured bytes.
    std::vector<uint8_t> cardEject();

    bool isCardPresent()    const { return m_cardPresent; }
    bool isWaitingForCard() const { return m_waitingForCard; }
    int  cardMode()         const { return m_cardMode; }  ///< 0=none, 1=read, 2=write

    /// Drain all pending printer output lines (called at 60 Hz by the UI thread).
    std::vector<std::string> drainPrinterLines();
    /// Drain raw 6-bit character codes for dot-matrix rendering, parallel to drainPrinterLines().
    /// Each entry is 20 codes (one per column, 0–63) plus a rowCount (1–7).  Feed lines are zero-filled.
    std::vector<PrinterCodeLine> drainPrinterCodeLines();

    // ── Trace / debug API ─────────────────────────────────────────────────────
    // Zero overhead when disabled: step() hot path costs one atomic<uint32_t>
    // load; falls through with no extra work when traceFlags == TRACE_NONE.

    void     setTraceFlags(uint32_t flags);
    uint32_t traceFlags() const;

    // ── Debug event log ───────────────────────────────────────────────────────
    // The CPU emits DebugEvents for write operations when debugLevel > 0.
    // Events are drained by TI59Machine under m_keyMutex at 60 Hz.
    void setDebugLevel(uint8_t level) { m_debugLevel = level; }
    uint8_t debugLevel() const { return m_debugLevel; }
    std::vector<DebugEvent> drainDebugEvents();

    void addBreakpoint(uint16_t pc);
    void removeBreakpoint(uint16_t pc);
    void clearBreakpoints();
    /// Returns true once per hit; called by TI59Machine after each step().
    bool consumeBreakpointHit();

    /// Drain up to `max` CPU frames. If ring overflow occurred since last drain,
    /// *outLost is set to the count of lost frames. Returns number of frames written.
    uint32_t drainCpuFrames(CpuFrame* out, uint32_t max, uint32_t* outLost);

    /// Read (without draining) the last up to `max` CPU frames from the ring.
    /// Returns number of frames read.
    uint32_t readCpuFrames(CpuFrame* out, uint32_t max) const;

    /// Pure function — disassembles one 13-bit opcode to a mnemonic string.
    static std::string disassemble(uint16_t pc, uint16_t opcode);

    // ── Printer hardware buttons ──────────────────────────────────────────────
    void pressPrinterPrint(bool pressed);
    void pressPrinterAdv(bool pressed);
    void setPrinterTrace(bool enabled);
    void setPrinterConnected(bool connected);   ///< Controls KP.D0 (printer-present sense line)

    /// Return the content currently held in the printer character buffer.
    std::string printerBufferContent() const;

    /// Debug-only helper: repeatedly force PREG redirect to startAddr until
    /// addr reaches startAddr. Returns true when entry succeeded.
    bool runDebugInjectedProgram(uint16_t startAddr, uint32_t maxSteps,
                                 uint32_t* outSteps);

    /// Return the last stable display snapshot.
    /// The snapshot is captured on every SET IDLE when the digit counter
    /// reaches 0.  If the CPU has been active (not idling) for 3+ consecutive
    /// digit-counter cycles the display is blanked — matching the hardware
    /// behaviour where the LEDs go dark during heavy computation.
    /// calcIndicator is true whenever the CPU is not in IDLE/display mode.
    DisplaySnapshot getDisplay() const;

    uint16_t pc()       const { return addr; }
    uint16_t cpuFlags() const { return flags; }

    /// Latched solid-state library execution address: the module byte address
    /// (0–4999) of the keycode byte most recently dispatched by the main ROM's
    /// program interpreter.  kLibExecPCNone until a module keycode executes.
    /// Unlike m_libAddr, this is NOT disturbed by header reads or label
    /// searches — see the IN LIB handler for the latch rule.
    uint16_t libExecPC() const { return m_libExecPC; }

    static constexpr uint16_t kLibExecPCNone = 0xFFFF;

    /// Capture a snapshot of all CPU registers at the current instant.
    CpuFrame snapshotCPU() const;

    /// Pre-execution phase: COND auto-restore, patch previous ring entry, capture snapshot.
    /// Called at the start of step(); also exposed for debugger use after freeze/step boundaries.
    void beginNextStep();

    /// Direct SCOM nibble access (row 0–15, col 0–15).
    uint8_t  scomNibble(int row, int col) const { return SCOM[row][col]; }
    void setSCOMNibble(int row, int col, uint8_t val) { SCOM[row][col] = val & 0xF; }

    /// Read a ROM keycode (PRG SOURCE = 8) by address 0–383.
    /// Returns 0 for out-of-range addresses.
    uint8_t romKeycode(int addr) const {
        if (addr < 0 || addr >= 384) return 0;
        int row = 16 + (addr / 8);
        int offset = (addr % 8) * 2;
        uint8_t units = m_constant[row][offset];
        uint8_t tens = m_constant[row][offset + 1];
        return static_cast<uint8_t>((tens * 10) + units);
    }

private:
    ROM& rom;
    RAM& ram;

    // ── BCD data registers (16 × 4-bit BCD digits each) ──────────────
    // A–D are the primary working registers; E is the implicit stack top
    // used by exchange instructions (XCH A,E).
    // A[2..13] and B[2..13] drive the 12-digit LED display when FLG_IDLE
    // is set.  Register layout: D[0]=DPT, D[1..2]=EXP, D[3..15]=MANT.
    uint8_t  A[16]{}, B[16]{}, C[16]{}, D[16]{}, E[16]{};

    // ── SCOM internal registers ───────────────────────────────────────
    // 16 scratch registers, 16 BCD digits each.  Used by the ROM for the
    // AOS operator-precedence stack, display state, RAM addressing, etc.
    // Not the same as user RAM (which lives in the external TMC0599 chip).
    uint8_t  SCOM[16][16]{};

    // ── Control / address registers ───────────────────────────────────
    uint16_t KR{};      // Key Register — multi-purpose: key-scan result,
                        // SCOM constant address (bits 10:4), PREG trigger (bit 1),
                        // and function-dispatch flags.
    uint16_t SR{};      // Subroutine Return — swap partner for XCH KR,SR.
                        // The ROM saves return addresses here (no CALL/RET hardware).
    uint16_t fA{};      // Flag register A — 16 individual mode/status bits visible
                        // to the ROM (INV mode, overflow, error, C-indicator, …).
    uint16_t fB{};      // Flag register B — second set of 16 ROM-visible flag bits.
    uint16_t EXT{};     // External data latch — holds one nibble read from the card
                        // reader or library module; valid for one cycle after IN CRD/LIB.
    uint16_t PREG{};    // Latched program address when SET KR[1] executes.
                        // Non-zero means redirect is pending. After the next
                        // instruction completes, PC is redirected to this address
                        // and PREG is cleared.
    uint8_t  Sout[16]{}; // ALU output bus — 16 BCD digits written after every ALU op.
                         // Also serves as the IO bus for STO/RCL address encoding.
    uint16_t flags{};   // Internal emulator state flags (see FLG_* enum above).
    uint8_t  R5{};      // 4-bit scratch nibble.  Receives the digit at mask.start
                        // after every ALU operation; also used as decimal-point
                        // pointer and as argument register for MOV R5,#n.
    uint8_t  digit{};   // Digit-counter — 4-bit counter cycling 15→0, one step per
                        // instruction.  Maps to hardware display multiplexing and
                        // keyboard row scanning (rows at digits 1–9, display latch
                        // at digit 0).
    uint16_t addr{};    // Program counter (13 bits, addresses 0x0000–0x1FFF).
    uint8_t  REG_ADDR{};  // SCOM register address latched by STO/RCL instructions.
    uint8_t  RAM_ADDR{};  // User-RAM register address decoded from Sout (Sout[3]*10 + Sout[2]).
    uint8_t  RAM_OP{};    // RAM operation code from Sout[0] (0=read, 1=write, 2=clear, 4=clear×10).
    MaskInfo RAM_MASK{0xFF, 0, 0, 0};  // Field mask for current RAM read/write operation.

    // ── Library module state ──────────────────────────────────────────
    uint16_t m_libAddr{};       // Current address within the loaded library image.
    uint8_t  m_libAddrReadPos{}; // Position counter for reading address digits (0-3, cycles).
    bool     m_libAddrWasWriting{}; // Track direction: true=writing (OUT), false=reading (IN)
    uint8_t  m_libData[5000]{}; // Library module byte image (up to 5,000 bytes).

    // ROM address of the single IN LIB instruction inside the main ROM's
    // keycode-interpreter fetch loop.  The interpreter fetches every executed
    // program byte (keycodes and operands) from this site; module header reads
    // and label searches use different IN LIB sites that we deliberately
    // ignore.  Verified by execution trace per ROM variant (see
    // reference/CPU_SCOM_Interconnect.md; module layout per
    // https://www.datamath.org/Chips/TMC0540.htm).  TI-58 shares the TI-59
    // ROM; TI-58C uses a different ROM set (CD2400/CD2401/TMC0573) where
    // the interpreter loop lives at a different address.
    uint16_t libExecFetchPC() const {
        return m_variant == MachineVariant::TI58C ? 0x0823 : 0x082F;
    }
    uint16_t m_libExecPC{kLibExecPCNone}; // User-visible solid-state program counter (see libExecPC()).

    // ── Machine variant ───────────────────────────────────────────────
    MachineVariant       m_variant{};           // TI-59, TI-58, or TI-58C (affects instruction decoding).

    // ── Magnetic card reader ──────────────────────────────────────────
    // Each OUT CRD stores the current KR value (2 bytes, little-endian).
    // Each IN CRD reconstructs KR from the next 2 bytes and places the
    // value into EXT so the ROM's "MOV KR,EXT[4..15]" can retrieve it.
    // Bits are stored verbatim; no interpretation is applied.
    uint8_t              m_cardSwitchCol{10};   // Digit-counter slot of the card-switch key.
    bool                 m_cardPresent{false};  // Card is currently passing through reader.
    bool                 m_waitingForCard{false}; // ROM is polling TST BUSY for a card.

    uint8_t              m_cardFullData[984]{}; // 4 banks * 246 bytes/bank.
    uint8_t              m_cardBankBuffer[246]{}; // Current active swipe buffer.
    size_t               m_cardPtr{0};         // Current index in m_cardBankBuffer.
    int                  m_cardMode{0};        // 0=none, 1=read, 2=write
    int                  m_lastWrittenBank{-1};  // Bank index written by last write swipe (-1 = none).

    // ── Printer state ─────────────────────────────────────────────────
    std::string m_prnBuf[20];        // 20-slot accumulator (right-to-left on output); init to spaces in ctor/reset
    uint8_t  m_prnCodeBuf[20]{};     // Raw 6-bit char codes, parallel to m_prnBuf
    uint8_t  m_prnPtr{0};            // Write position in buffer
    bool     m_prnReady{false};      // True after first PRT_CLEAR; gates OUT PRT/FUNC/STEP/PRINT
    uint32_t m_prnBusyCycles{0};     // Countdown for FLG_BUSY assertion
    PrinterCodeLine  m_prnPending{};      // Code-line in progress (deferred until BUSY expires or aborted)
    bool             m_prnHasPending{false};
    std::vector<std::string>      m_prnLines;      // Thread-safe text output queue
    std::vector<PrinterCodeLine>  m_prnCodeLines;  // Parallel raw-code queue (deferred commits)
    mutable std::mutex            m_prnMutex;
    void flushPendingCodeLine(int rowCount);  // commit m_prnPending with the given rowCount

    // ── Display state (shared between CPU thread and UI thread) ───────
    // Per-digit live buffers: updated during each digit's strobe phase when IDLE.
    // getDisplay() reads these directly at query time (no stale batch snapshot).
    // IMPORTANT: All access to display state members (below) must be guarded by
    // m_displayMutex. Updated exclusively by postOperation() (CPU thread), read only
    // by getDisplay() (UI thread, ~60 Hz) and computeDisplayTraceState() (CPU thread).
    mutable std::mutex m_displayMutex;
    uint8_t  m_digitSegmentsA[12]{};  // A[2..13] → m_digitSegmentsA[0..11] per strobe (CPU thread write, UI thread read)
    uint8_t  m_digitSegmentsB[12]{};  // B[2..13] → m_digitSegmentsB[0..11] per strobe (CPU thread write, UI thread read)
    uint8_t  m_digitAfterglowCounters[12]{}; // Digit (segment) afterglow counter per position.
                                             // counter[i] → position (i+2); decrement each digit==0 cycle.
                                             // Seeded when the position is actively driven (not suppressed) during IDLE scan.
    uint8_t  m_dpAfterglowCounters[12]{};    // Decimal-point afterglow counter per position.
                                             // Seeded only when R5 matches the currently strobed position.
    bool     m_digitLitInLastStrobe[12]{};   // Per-position segment lit state from previous strobe.
    bool     m_dpLitInLastStrobe[12]{};      // Per-position decimal-point lit state from previous strobe.
    uint8_t  m_currentDpPos{0};       // Live R5 DP position (updated per strobe capture)
    uint16_t m_digitSuppressedMask{0}; // Zero-suppression circuit output bitmask for indices 0..11.
    bool     m_zeroSuppressRunning{true}; // Scan-chain running state for leading-zero suppression.


    mutable std::atomic<uint32_t> m_cSteps{0};          // Steps (IDLE or non-IDLE) where fA≠0 since last getDisplay().
    mutable std::atomic<uint32_t> m_pollSteps{0};       // Weighted step count since last getDisplay() (non-IDLE=1, IDLE=4).

    // ── Keyboard matrix ───────────────────────────────────────────────
    // key[col] holds a bitmask of which rows are pressed for that digit-counter
    // column.  Bit positions correspond to K-line indices (KO=1…KT=6).
    // col = digit-counter slot (0–15); only slots 1–9 connect to keyboard rows.
    uint8_t  key[16]{};

    // ── Debug event log ───────────────────────────────────────────────
    uint8_t m_debugLevel{0};
    std::vector<DebugEvent> m_debugEvents;
    void emitDebug(uint8_t level, const char* fmt, ...) __attribute__((format(printf, 3, 4)));

    // ── Trace / debug state ───────────────────────────────────────────
    std::atomic<uint32_t> m_traceFlags{TRACE_NONE};
    uint32_t m_traceSeqno{0};
    uint16_t m_pendingOpcode{};  // opcode cached by beginNextStep, consumed by step()

    static constexpr uint32_t kFrameRingSize = 1024u;
    static constexpr uint32_t kFrameRingMask = kFrameRingSize - 1u;
    CpuFrame m_frameRing[kFrameRingSize]{};
    uint32_t m_frameHead{0};     // write index (emulation thread only, always advancing)
    uint32_t m_diskCursor{0};    // drain read cursor (protected by m_traceMutex)

    // Non-recursive: no acquisition site re-enters.  beginNextStep() releases its
    // lock scope before calling tracePreStep(), which takes the lock fresh.
    mutable std::mutex m_traceMutex;
    std::vector<uint16_t> m_breakpoints; // sorted ascending; protected by m_traceMutex
    bool m_breakpointHit{false};

    void tracePreStep(uint32_t tf, uint16_t opcode);
    void tracePostStep(uint32_t tf, int weight);

    // ── Helper methods for masked operations ──────────────────────────
    // Read only the nibbles specified by the field mask from RAM
    void readRegMasked(uint8_t* dst, int addr, const MaskInfo& m);
    // Write only the nibbles specified by the field mask to RAM
    void writeRegMasked(int addr, const uint8_t* src, const MaskInfo& m);
    // Read only the nibbles specified by the field mask from SCOM
    void readScomMasked(uint8_t* dst, int addr, const MaskInfo& m);

    // ── ALU support tables ────────────────────────────────────────────

    // Field mask descriptor table.  Each ALU instruction carries a 4-bit field-mask
    // index that selects a contiguous range of digits to operate on.
    // start/end: first and last digit index updated in the destination register.
    // cpos/cval: digit position and value of an implicit BCD constant injected
    //            into every operation (e.g. "#1" in "ADD C.DPT, C, #1").
    //            start=0xFF marks an invalid/unused mask entry.
    static const MaskInfo mask_info[16];

    // 64 × 16-digit BCD constant table, stored in the SCOM chip (TMC0571).
    // Selected by KR bits 10:4 via the ADD/SUB … const ALU instructions.
    //
    // Entries 0–15: mathematical constants for transcendental functions
    //   (ln 10, ln 2, π/2, π, 180/π, and partial-product table entries used
    //   by the CORDIC-style algorithms for sin/cos/tan/exp/ln).
    // Entries 16–63: 6-bit keystroke display codes used in programming mode
    //   to render key names on the LED display (e.g. SIN, STO, RCL, …).
    //
    // The constant is accessed by loading KR with the desired index via the
    // INC KR chain at 0x139A–0x13A8, then using an ADD/SUB…const opcode.
    uint8_t m_constant[64][16];

    // ALU operation selector passed to alu().
    // SUB and SHR are ≥ ALU_SUB, which the alu() function uses to choose
    // between add/negate and shift-right paths.
    enum : uint8_t { ALU_ADD=0, ALU_SHL=1, ALU_SUB=2, ALU_SHR=3 };

    // Perform a BCD digit-serial ALU operation over the masked field.
    // srcX and srcY are the two source operands (either may be nullptr = zero).
    // Results are written to Sout[] (always) and to dst (when non-null).
    // Carry out of the field clears FLG_COND.
    void alu(uint8_t* dst, const uint8_t* srcX, const uint8_t* srcY,
             const MaskInfo& m, int op);

    // Swap digits in the masked field between registers a and b.
    static void xch(uint8_t* a, uint8_t* b, const MaskInfo& m);

    // Decode and execute all ALU-class opcodes (bits 12=0, hi nibble ∉ {0,8,A}).
    void execALU(uint16_t opcode);

    // Per-step post-execution work that must run for every instruction.
    void postOperation();

    // Compute trace-facing display state from per-position afterglow counters.
    void computeDisplayTraceState(uint8_t& displayOn, uint8_t& maxDigitDecay) const;

    uint32_t getPrinterBusyCycles() const;

    int getStepWeight() const;
};
