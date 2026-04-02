#pragma once
#include <array>
#include <cstdint>
#include <cstring>
#include <atomic>
#include <mutex>
#include <string>
#include <vector>
#include "TraceTypes.hpp"

class ROM;
class RAM;

// ── Display snapshot ──────────────────────────────────────────────────────────
//
// Atomic copy of the display state, written by the CPU thread on every SET IDLE
// and read by the UI thread at 60 Hz.  All 12 visible digit positions come from
// the A and B registers; decimal point and the "C" annunciator are separate.

struct DisplaySnapshot {
    uint8_t digits[12]{};        ///< A[2..13] — BCD digit values (0–9, A–F)
    uint8_t ctrl[12]{};          ///< B[2..13] — display-control nibbles (select digit vs. minus/degree/blank)
    uint8_t dpPos{0};            ///< R5 — decimal-point position within the mantissa
    float   calcIndicator{0.0f}; ///< fraction of the last poll interval where C LED was driven:
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
    FLG_DISP      = 0x1000, // Display active flag (set at reset alongside FLG_COND).
    FLG_DISP_C    = 0x4000, // (Unused internal mirror — same bit value as fA[14], the hardware
                            //  SH-pin driver in IDLE mode per TI-58/59 HW guide §digit-12.)
    FLG_BUSY      = 0x8000, // Printer / peripheral busy signal; tested by TST BUSY.
};

// ── TMC0501 CPU ───────────────────────────────────────────────────────────────
//
// 4-bit BCD digit-serial processor at the heart of the TI-59/58/58C.
// All arithmetic operates on 16-digit (64-bit) BCD registers, processing one
// digit per instruction cycle via a serial ALU.  Field masks select which
// subset of the 16 digits are actually written back to the destination.
//
// Clock: 455 kHz oscillator ÷ 2 (two-phase) ÷ 16 (digit-serial cycle)
//        ≈ 14,219 instructions/sec in active mode; ÷4 further in idle mode.

class TMC0501 {
public:
    explicit TMC0501(ROM& rom, RAM& ram);

    void reset();

    /// Execute one instruction at the current program counter.
    ///
    /// Returns the cycle weight of this instruction for emulation pacing:
    ///   0 — PREG computed-jump redirect (no ROM fetch, no real work)
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

    // ── Magnetic card reader ─────────────────────────────────────────────────
    // The ROM polls TST BUSY in a tight loop after the user presses 2nd-Read
    // or 2nd-Write.  TST BUSY sets m_waitingForCard when it sees the card-switch
    // key asserted at digit == m_cardSwitchCol.  The Swift layer polls this flag
    // at 60 Hz; when it goes true the UI inserts the card after a short delay
    // by calling insertCard(), which releases the key and activates I/O.

    /// Tell the CPU which digit-counter slot the card-switch occupies.
    /// Must be called once at machine construction before any step().
    void setCardSwitchCol(uint8_t col) { m_cardSwitchCol = col; }

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
    /// Each array is 20 bytes (one per column, code 0–63).  Feed lines are zero-filled.
    std::vector<std::array<uint8_t,20>> drainPrinterCodeLines();

    // ── Trace / debug API ─────────────────────────────────────────────────────
    // Zero overhead when disabled: step() hot path costs one atomic<uint32_t>
    // load; falls through with no extra work when traceFlags == TRACE_NONE.

    void     setTraceFlags(uint32_t flags);
    uint32_t traceFlags() const;

    void addBreakpoint(uint16_t pc);
    void removeBreakpoint(uint16_t pc);
    void clearBreakpoints();
    /// Returns true once per hit; called by TI59Machine after each step().
    bool consumeBreakpointHit();

    /// Drain up to `max` trace events into caller-supplied buffers.
    /// outSnaps may be nullptr if TRACE_REGS_FULL snapshots are not needed.
    /// Returns the number of events written.
    uint32_t drainTraceEvents(TraceEvent* out, CPUSnapshot* outSnaps, uint32_t max);

    /// Peek at the last event written without consuming it (thread-safe).
    bool peekLastEvent(TraceEvent& out, CPUSnapshot* outSnap) const;

    /// Pure function — disassembles one 13-bit opcode to a mnemonic string.
    static std::string disassemble(uint16_t pc, uint16_t opcode);

    // ── Printer hardware buttons ──────────────────────────────────────────────
    void pressPrinterPrint(bool pressed);
    void pressPrinterAdv(bool pressed);
    void setPrinterTrace(bool enabled);

    /// Return the content currently held in the printer character buffer.
    std::string printerBufferContent() const;

    /// Return the last stable display snapshot.
    /// The snapshot is captured on every SET IDLE when the digit counter
    /// reaches 0.  If the CPU has been active (not idling) for 3+ consecutive
    /// digit-counter cycles the display is blanked — matching the hardware
    /// behaviour where the LEDs go dark during heavy computation.
    /// calcIndicator is true whenever the CPU is not in IDLE/display mode.
    DisplaySnapshot getDisplay() const;

    uint16_t pc()       const { return addr; }
    uint16_t cpuFlags() const { return flags; }

    /// Capture a snapshot of all CPU registers at the current instant.
    CPUSnapshot snapshotCPU() const;

    /// Direct SCOM nibble access (row 0–15, col 0–15).
    uint8_t  scomNibble(int row, int col) const { return SCOM[row][col]; }
    void setSCOMNibble(int row, int col, uint8_t val) { SCOM[row][col] = val & 0xF; }

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
    uint16_t PREG{};    // Computed-jump latch.  SET KR[1] loads a rotated KR here;
                        // on the next step() call the PC is replaced with PREG>>3
                        // and PREG is cleared (return value 0, no ROM fetch).
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

    // ── Library module state ──────────────────────────────────────────
    uint16_t m_libAddr{};       // Current read position within the loaded library image.
    uint8_t  m_libData[5000]{}; // Library module byte image (up to 5,000 bytes).

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
    std::vector<std::string>             m_prnLines;      // Thread-safe text output queue
    std::vector<std::array<uint8_t,20>> m_prnCodeLines;  // Parallel raw-code queue
    mutable std::mutex                   m_prnMutex;

    // ── Display state (shared between CPU thread and UI thread) ───────
    mutable std::mutex m_displayMutex;
    DisplaySnapshot m_display{};       // Last stable snapshot, updated at digit=0 on SET IDLE.
    bool     m_pendingDisplayUpdate{}; // SET IDLE was executed; snapshot will be captured
                                       // at the next digit=0 boundary.
    uint8_t  m_dispFilter{};   // Counts digit-counter wrap-arounds since the last IDLE.
                                // At 3, the display is blanked (CPU is busy computing).
    mutable std::atomic<bool>     m_calcLatch{false};   // Fired on CLR IDL; consumed by getDisplay() (legacy, kept for reset).
    mutable std::atomic<uint32_t> m_cSteps{0};          // Steps (IDLE or non-IDLE) where fA≠0 since last getDisplay().
    mutable std::atomic<uint32_t> m_pollSteps{0};       // Weighted step count since last getDisplay() (non-IDLE=1, IDLE=4).

    // ── Keyboard matrix ───────────────────────────────────────────────
    // key[col] holds a bitmask of which rows are pressed for that digit-counter
    // column.  Bit positions correspond to K-line indices (KO=1…KT=6).
    // col = digit-counter slot (0–15); only slots 1–9 connect to keyboard rows.
    uint8_t  key[16]{};

    // ── Trace / debug state ───────────────────────────────────────────
    std::atomic<uint32_t> m_traceFlags{TRACE_NONE};
    uint32_t m_traceSeqno{0};

    static constexpr uint32_t kTraceRingMask = 511u; // ring size 512
    TraceEvent  m_traceRing[512]{};
    CPUSnapshot m_snapRing[512]{};
    uint32_t    m_traceHead{0};     // write index (emulation thread only)
    uint32_t    m_traceTail{0};     // read index (drain caller under m_traceMutex)

    mutable std::mutex    m_traceMutex;
    std::vector<uint16_t> m_breakpoints; // sorted ascending; protected by m_traceMutex
    bool m_breakpointHit{false};

    // Saved during tracePreStep; consumed by tracePostStep.
    uint16_t m_tracePC{};
    uint16_t m_traceOpcode{};

    void tracePreStep(uint32_t tf, uint16_t opcode, uint8_t& snapIdx);
    void tracePostStep(uint32_t tf, uint8_t snapIdx, int weight);

    // ── ALU support tables ────────────────────────────────────────────

    // Field mask descriptor.  Each ALU instruction carries a 4-bit field-mask
    // index that selects a contiguous range of digits to operate on.
    // start/end: first and last digit index updated in the destination register.
    // cpos/cval: digit position and value of an implicit BCD constant injected
    //            into every operation (e.g. "#1" in "ADD C.DPT, C, #1").
    //            start=0xFF marks an invalid/unused mask entry.
    struct MaskInfo { uint8_t start, end, cpos, cval; };
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
    static const uint8_t CONSTANT[64][16];

    // ALU operation selector passed to alu().
    // SUB and SHR are ≥ ALU_SUB, which the alu() function uses to choose
    // between add/negate and shift-right paths.
    enum { ALU_ADD=0, ALU_SHL=1, ALU_SUB=2, ALU_SHR=3 };

    // Perform a BCD digit-serial ALU operation over the masked field.
    // srcX and srcY are the two source operands (either may be nullptr = zero).
    // Results are written to Sout[] (always) and to dst (when non-null).
    // Carry out of the field clears FLG_COND.
    void alu(uint8_t* dst, const uint8_t* srcX, const uint8_t* srcY,
             const MaskInfo& m, int op);

    // Swap digits in the masked field between registers a and b.
    void xch(uint8_t* a, uint8_t* b, const MaskInfo& m);

    // Decode and execute all ALU-class opcodes (bits 12=0, hi nibble ∉ {0,8,A}).
    void execALU(uint16_t opcode);
};
