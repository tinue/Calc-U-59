#include "TMC0501.hpp"
#include "ROM.hpp"
#include "RAM.hpp"
#include <algorithm>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>

// ── Field mask table ──────────────────────────────────────────────────────────
//
// One entry per 4-bit field-mask index embedded in every ALU opcode.
// Each entry describes a contiguous range of the 16-digit BCD register:
//   start — first digit updated (0xFF = invalid mask, operation is a no-op)
//   end   — last digit updated
//   cpos  — digit position where the implicit constant cval is injected
//   cval  — BCD constant injected at cpos (the "#N" in mnemonics like "ADD C.DPT,C,#1")
//
// Example: mask 9 = MANT covers digits 3–15 (the 13-digit mantissa).
//          mask 6 = EXP  covers digits 1–2  (the 2-digit exponent), no constant.
//          mask 3 = DPT #1 operates only on digit 0 and injects +1 (increment DPT).

// ── Printer character and function-code tables ────────────────────────────────
//
// PRN_CODE[64]: maps a 6-bit code (KR bits 10:4) to a printable UTF-8 character.
// PRN_STR[]:    maps a 7-bit function code to a 3-character mnemonic string.
//               The strings are stored right-to-left in the buffer (hardware
//               writes them reversed so that the print-buffer-reversal on output
//               restores the correct reading order).

static const char* const PRN_CODE[64] = {
    " ","0","1","2","3","4","5","6",
    "7","8","9","A","B","C","D","E",
    "-","F","G","H","I","J","K","L",
    "M","N","O","P","Q","R","S","T",
    ".","U","V","W","X","Y","Z","+",
    "x","*","√","π","e","(",")",",",
    "↑","%","⇄","/","=","'","ˣ","x̄",
    "²","?","÷","!","Ⅱ","▴","∏","∑"
};

// Reverse-map a single ASCII character to its PRN_CODE index (0 = space/fallback).
// Used to recover raw codes when function-mnemonic characters are stored in m_prnBuf.
static uint8_t prnCharToCode(char c) {
    for (int i = 0; i < 64; i++) {
        if (PRN_CODE[i][0] == c && PRN_CODE[i][1] == '\0')
            return static_cast<uint8_t>(i);
    }
    return 0;  // space
}

static const struct { uint8_t code; char str[4]; } PRN_STR[] = {
    {0x00, "   "},
    {0x11, " = "},
    {0x12, " - "},
    {0x13, " + "},
    {0x16, " / "},
    {0x17, " x "},
    {0x1A, "xsY"},
    {0x1B, "Y^x"},
    {0x21, "CLR"},
    {0x22, "INV"},
    {0x23, "DPT"},
    {0x26, "CE "},
    {0x27, "+/-"},
    {0x2D, "EE "},
    {0x31, "e^x"},
    {0x33, "x^2"},
    {0x36, "1/x"},
    {0x3C, "sX "},
    {0x3D, "X_Y"},
    {0x51, "LNX"},
    {0x53, "PRM"},
    {0x54, " % "},
    {0x56, "COS"},
    {0x57, "SIN"},
    {0x5D, "TAN"},
    {0x61, "SUM"},
    {0x66, "STO"},
    {0x67, "pi "},
    {0x68, "RCL"},
    {0x69, "S+ "},
    {0x70, "ERR"},
    {0x71, " { "},
    {0x72, " ) "},
    {0x73, "LRN"},
    {0x74, "RUN"},
    {0x76, "HLT"},
    {0x78, "STP"},
    {0x7A, "GTO"},
    {0x7C, "IF "},
    {0x00, ""}   // sentinel
};

const TMC0501::MaskInfo TMC0501::mask_info[16] = {
    {0xFF, 0,  0,    0},   // 0: invalid — no digits updated
    {  0, 15,  0,    0},   // 1: ALL     — all 16 digits
    {  0,  0,  0,    0},   // 2: DPT     — digit 0 only  (decimal-point position)
    {  0,  0,  0,    1},   // 3: DPT #1  — digit 0, inject +1
    {  0,  0,  0, 0x0C},   // 4: DPT #C  — digit 0, inject +0xC
    {  3,  3,  3,    1},   // 5: LLSD #1 — digit 3 only  (mantissa least-significant)
    {  1,  2,  1,    0},   // 6: EXP     — digits 1–2    (2-digit exponent)
    {  1,  2,  1,    1},   // 7: EXP #1  — digits 1–2, inject +1
    {0xFF, 0,  0,    0},   // 8: invalid
    {  3, 15,  3,    0},   // 9: MANT    — digits 3–15   (13-digit mantissa)
    {0xFF, 0,  0,    0},   // A: invalid
    {  3, 15,  3,    5},   // B: MLSD #5 — mantissa, inject +5 at digit 3
    {  1, 15,  1,    0},   // C: MAEX    — digits 1–15   (mantissa + exponent)
    {  1, 15,  3,    1},   // D: MAEX/MLSD #1 — mantissa+exp, inject +1 at digit 3
    {  1, 15, 15,    1},   // E: MMSD #1 — mantissa+exp, inject +1 at digit 15 (MSD)
    {  1, 15,  1,    1},   // F: MAEX #1 — mantissa+exp, inject +1 at digit 1
};

// ── SCOM mathematical and display constant table ──────────────────────────────
//
// 64 entries × 16 BCD digits, physically stored in the TMC0582/83 chip, SCOM area.
// Accessed by the CPU via ADD/SUB … const ALU instructions; the constant
// index is encoded in KR bits 10:4 and loaded by running through the
// INC KR chain at ROM addresses 0x139A–0x13A8.
//
// Entries 0–15: floating-point constants for transcendental math.
//   The algorithms use a table-driven CORDIC-style approach; most entries are
//   partial products or argument-reduction values, not simple named constants.
//   Notable entries:
//     [0]  ln(10) ≈ 2.302585092994…   (used for log₁₀ / 10^x)
//     [1]  ln(2)  ≈ 0.693147180559…   (used for 2^x)
//     [13] π/2    ≈ 1.570796326794…   (argument reduction for trig)
//     [14] π      ≈ 3.141592653589…
//     [15] 180/π  ≈ 57.2957795130…    (degree ↔ radian conversion)
//
// Entries 16–63: Keycode programs for routines such as Polar->Rec coordinates

// ── Constructor / reset ───────────────────────────────────────────────────────

TMC0501::TMC0501(ROM& r, RAM& m) : rom(r), ram(m) {
    memset(m_constant, 0, sizeof(m_constant));
    for (auto& s : m_prnBuf) s = " ";
}

void TMC0501::reset() {
    memset(A, 0, sizeof(A));  memset(B, 0, sizeof(B));
    memset(C, 0, sizeof(C));  memset(D, 0, sizeof(D));  memset(E, 0, sizeof(E));
    memset(SCOM, 0, sizeof(SCOM));
    memset(Sout, 0, sizeof(Sout));
    memset(key,  0, sizeof(key));
    KR = SR = fA = fB = EXT = PREG = m_libAddr = m_libAddrReadPos = 0;
    m_libAddrWasWriting = false;
    R5 = digit = RAM_ADDR = RAM_OP = REG_ADDR = 0;
    addr  = 0;
    flags = FLG_COND | FLG_DISP;  // COND starts true; display active
    m_display = {};
    m_dispFilter = 0;
    // Reset card state; caller (TI59Machine) re-presses the card-switch key.
    m_cardPresent    = false;
    m_waitingForCard = false;
    memset(m_cardFullData,   0, sizeof(m_cardFullData));
    memset(m_cardBankBuffer, 0, sizeof(m_cardBankBuffer));
    m_cardPtr         = 0;
    m_cardMode        = 0;
    m_lastWrittenBank = -1;
    for (auto& s : m_prnBuf) s = " ";
    m_prnPtr = 0;
    m_prnReady = false;
    m_prnBusyCycles = 0;
}

void TMC0501::loadLibrary(const uint8_t* data, size_t count) {
    count = std::min(count, size_t{5000});
    memcpy(m_libData, data, count);
}

void TMC0501::loadConstants(const uint8_t* data, size_t count) {
    count = std::min(count, sizeof(m_constant));
    memcpy(m_constant, data, count);
}

// ── Masked RAM read/write helpers ──────────────────────────────────────────────

void TMC0501::readRegMasked(uint8_t* dst, int addr, const MaskInfo& m) {
    // Read only the nibbles in the masked range from RAM, zero out others
    const auto* src = ram.readReg(addr);
    memset(dst, 0, 16);
    if (src && m.start != 0xFF) {
        for (int i = static_cast<int>(m.start); i <= static_cast<int>(m.end) && i < 16; i++) {
            dst[i] = src[i];
        }
    }
}

void TMC0501::writeRegMasked(int addr, const uint8_t* src, const MaskInfo& m) {
    // Write only the nibbles in the masked range to RAM, preserve others
    if (m.start != 0xFF && addr < ram.size()) {
        const auto* current = ram.readReg(addr);
        if (current) {
            uint8_t temp[16];
            memcpy(temp, current, 16);
            for (int i = static_cast<int>(m.start); i <= static_cast<int>(m.end) && i < 16; i++) {
                temp[i] = src[i];
            }
            ram.writeReg(addr, temp);
        }
    }
}

void TMC0501::readScomMasked(uint8_t* dst, int addr, const MaskInfo& m) {
    // Read only the nibbles in the masked range from SCOM, zero out others
    memset(dst, 0, 16);
    if (addr < 16 && m.start != 0xFF) {
        for (int i = static_cast<int>(m.start); i <= static_cast<int>(m.end) && i < 16; i++) {
            dst[i] = SCOM[addr][i];
        }
    }
}

// ── Debug event log ───────────────────────────────────────────────────────────

// Format 16 nibbles as a 16-character hex string into buf (must be ≥17 bytes).
// reverse=true outputs nibble[15] first (MSD first, matching SCOM display convention).
static const char* fmtNibs(const uint8_t* d, char* buf, bool reverse = false) {
    static const char H[] = "0123456789abcdef";
    for (int i = 0; i < 16; i++) buf[i] = H[d[reverse ? 15 - i : i] & 0xF];
    buf[16] = '\0';
    return buf;
}

void TMC0501::emitDebug(uint8_t level, const char* fmt, ...) {
    if (level > m_debugLevel) return;
    if (m_debugEvents.size() >= 8192) return;
    DebugEvent ev;
    ev.level = level;
    va_list args{};  // NOLINT(cppcoreguidelines-init-variables) -- initialized by va_start
    va_start(args, fmt);
    vsnprintf(ev.msg, sizeof(ev.msg), fmt, args);
    va_end(args);
    m_debugEvents.push_back(ev);
}

std::vector<DebugEvent> TMC0501::drainDebugEvents() {
    std::vector<DebugEvent> result;
    result.swap(m_debugEvents);
    return result;
}

// ── Key matrix ────────────────────────────────────────────────────────────────

void TMC0501::pressKey(int row, int col) {
    if (col >= 0 && col < 16 && row >= 0 && row < 7)
        key[col] |= static_cast<uint8_t>(1U << row);
}

void TMC0501::releaseKey(int row, int col) {
    if (col >= 0 && col < 16 && row >= 0 && row < 7)
        key[col] &= static_cast<uint8_t>(~(1U << row));
}

// ── Display read-out ──────────────────────────────────────────────────────────
//
// Called by the UI thread at ~60 Hz.  Returns a stable, mutex-protected copy
// of the last display snapshot.
//
// Blanking: if the CPU has been in active (non-idle) mode for 3 or more
// consecutive digit-counter cycles, the display is blanked to mimic the
// hardware behaviour where the LED segments go dark during computation.
// ctrl=7 for every digit signals "blank" to the LED renderer.

DisplaySnapshot TMC0501::getDisplay() const {
    std::lock_guard<std::mutex> lock(m_displayMutex);
    // Integrate the SH-pin (C indicator) signal over the polling interval rather
    // than sampling a boolean at one instant.
    //
    // Per the TI-58/59 hardware guide (Sladký 2014), the SH output at digit 12:
    //   • IDLE mode  — driven by fA bit 14 (0x4000) only.  The other fA bits
    //     are used for display state (e.g. bits 1–4 hold the decimal-point
    //     position loaded by MOV fA[1..4],R5) and must NOT light the C LED.
    //   • RUN mode   — driven by all fA bits (any fA ≠ 0 lights C).
    //
    // m_cSteps counts every step() call where that condition holds.
    // m_pollSteps counts all steps weighted by cycle cost (non-IDLE=1, IDLE=4).
    // The ratio is the fraction of real time the C LED was driven — matching
    // the hardware's kHz-rate duty cycle averaged down to the 60 Hz UI poll.
    // This naturally handles:
    //   • brief sub-frame computations      → small but non-zero duty cycle
    //   • long computations (e.g. 1/x)     → duty cycle near 1.0
    //   • IDLE with only decimal-point bits → duty cycle = 0.0 (no false C)
    //   • "A" blink bright phase in IDLE   → fA[14] set → duty cycle ≈ 0.25
    m_calcLatch.exchange(false, std::memory_order_relaxed);  // consume (kept for reset logic)
    const uint32_t cSteps    = m_cSteps.exchange(0, std::memory_order_relaxed);
    const uint32_t pollSteps = m_pollSteps.exchange(0, std::memory_order_relaxed);
    const float cLevel = pollSteps ? (float)cSteps / (float)pollSteps : 0.0f;

    if (m_dispFilter >= 3) {
        DisplaySnapshot blank{};
        for (auto& ctrl : blank.ctrl) ctrl = 7;
        blank.calcIndicator = cLevel;
        return blank;
    }
    DisplaySnapshot s = m_display;
    s.calcIndicator = cLevel;
    return s;
}

// ── BCD digit-serial ALU ──────────────────────────────────────────────────────
//
// Iterates over all 16 digit positions, propagating BCD carry.
// The field mask (m.start … m.end) gates which digits are written back to dst.
// srcX and srcY are the two addends; either may be nullptr (treated as zero).
// The constant m.cval is injected into srcY at position m.cpos.
//
// BCD correction: digit 0 is hexadecimal (base 16); digits 1–15 are decimal
// (base 10).  This reflects the hardware: D[0] is the DPT/special nibble,
// not a true BCD digit, so it wraps at 16 rather than 10.
//
// Carry out of the field (at m.end) clears FLG_COND for non-shift operations,
// signalling overflow to subsequent branch instructions.
//
// The IO bus (Sout[]) is always written regardless of the field mask — it
// receives the raw ALU output before BCD correction, allowing the ROM to
// read back pre-correction (hexadecimal) intermediate values.

void TMC0501::alu(uint8_t* dst, const uint8_t* srcX, const uint8_t* srcY,
                  const MaskInfo& m, int op) {
    uint8_t carry = 0, shl = 0;
    for (int i = 0; i <= 15; ++i) {
        if (i == static_cast<int>(m.start)) { shl = carry = 0; }

        uint8_t sum = 0, shr = 0;
        if (srcY)                                sum  = srcY[i];
        if (i == static_cast<int>(m.cpos))       sum |= m.cval;
        shr  = sum;
        sum  = static_cast<uint8_t>(sum + carry);
        if (op >= ALU_SUB)     sum  = static_cast<uint8_t>(-sum);
        if (srcX)            { sum  = static_cast<uint8_t>(sum + srcX[i]); shr |= srcX[i]; }

        // Real hardware drives Sout to 0 outside the active field.  Naively
        // propagating the carry chain into all 16 positions (the "obvious"
        // implementation) would leave source-register values in the out-of-mask
        // digits.  That stale data then gets written into SCOM via FLG_STORE,
        // corrupting registers used later as print-buffer indices and producing
        // spurious '8' characters in printer output (PRN_CODE[9] = '8').
        Sout[i] = (i >= static_cast<int>(m.start) && i <= static_cast<int>(m.end)) ? (sum & 0x0F) : 0;

        // BCD carry: digit 0 wraps at 16 (hex); digits 1–15 wrap at 10 (decimal)
        if (i == 0) {
            if ((carry = (sum >= 0x10 ? 1U : 0U))) sum &= 0x0FU;
        } else {
            if ((carry = (sum >= 10 ? 1U : 0U))) {
                if (op < ALU_SUB) sum = static_cast<uint8_t>(sum - 10);
                else              sum = static_cast<uint8_t>(sum + 10);
            }
        }

        if (i >= static_cast<int>(m.start) && i <= static_cast<int>(m.end)) {
            if (i == static_cast<int>(m.cpos)) R5 = sum;  // R5 captures result at constant position per manual
            if (dst) {
                if      (op == ALU_SHL)                              dst[i]   = shl;
                else if (op == ALU_SHR) {
                    if (i > static_cast<int>(m.start))               dst[i-1] = shr;
                    if (i == static_cast<int>(m.end))                dst[i]   = 0;
                } else                                               dst[i]   = sum;
                shl = sum;
            }
            // Carry out of the field clears COND (signals overflow to branches)
            if (i == static_cast<int>(m.end) && !(op & 0x1) && carry)
                flags &= ~FLG_COND;
        }
    }
}

void TMC0501::xch(uint8_t* a, uint8_t* b, const MaskInfo& m) {
    if (m.start == 0xFF) return;
    for (int i = static_cast<int>(m.start); i <= static_cast<int>(m.end); ++i) {
        uint8_t t = a[i]; a[i] = b[i]; b[i] = t;
    }
}

bool TMC0501::runDebugInjectedProgram(uint16_t startAddr, uint32_t maxSteps,
                                      uint32_t* outSteps, bool* outSawHold) {
    if (outSteps) *outSteps = 0;
    if (outSawHold) *outSawHold = false;

    const uint16_t target = static_cast<uint16_t>(startAddr & 0x1FFFu);
    for (uint32_t i = 0; i < maxSteps; i++) {
        // Emulate the external debugger forcing EXT/PREG lines until HOLD.
        EXT = target;
        PREG = target;
        (void)step();
        if (outSteps) *outSteps = i + 1;
        if (flags & FLG_HOLD) {
            if (outSawHold) *outSawHold = true;
            return true;
        }
    }
    return false;
}

// ── Main instruction dispatch ─────────────────────────────────────────────────

int TMC0501::step() {
    // ── Trace gate ────────────────────────────────────────────────────
    // One relaxed atomic load per step; falls through at zero cost when disabled.
    const uint32_t tf = m_traceFlags.load(std::memory_order_relaxed);

    // ── Printer busy countdown ────────────────────────────────────────
    if (m_prnBusyCycles > 0) {
        if (--m_prnBusyCycles == 0) flags &= ~FLG_BUSY;
    }

    // Pre-execution phase: COND auto-restore, patch previous ring entry, capture snapshot
    beginNextStep();
    uint16_t opcode = m_pendingOpcode;

    // ── Digit counter ─────────────────────────────────────────────────
    // 4-bit counter cycling 15→14→…→1→0→15.  One step per instruction.
    // Drives display multiplexing and keyboard row selection:
    //   digits 1–9  → keyboard rows D1–D9
    //   digit  0    → display latch point (snapshot captured here on IDLE)
    digit = digit ? (digit - 1) : 15;

    // ── Display snapshot / flicker filter ────────────────────────────
    // Sampled once per full digit-counter cycle (at digit == 0).
    // IDLE set:   reset filter and commit pending snapshot to the display buffer.
    // IDLE clear: increment filter; at 3 counts getDisplay() will blank the LEDs,
    //             reproducing the dark-display-during-computation hardware behaviour.
    if (digit == 0) {
        if (flags & FLG_IDLE) {
            m_dispFilter = 0;
            // Auto-update display every digit cycle while in IDLE mode.
            // This matches hardware behavior: display reflects A/B changes immediately
            // while idle (m_pendingDisplayUpdate tracks entry to IDLE for initial latch,
            // but display continuously refreshes).
            std::lock_guard<std::mutex> lock(m_displayMutex);
            for (int i = 0; i < 12; ++i) {
                m_display.digits[i] = A[i + 2] & 0x0F;
                m_display.ctrl[i]   = B[i + 2] & 0x0F;
            }
            m_display.dpPos = R5 & 0x0F;
        } else if (m_dispFilter < 3) {
            m_dispFilter++;
        }
    }

    // ── Clear HOLD ────────────────────────────────────────────────────
    // HOLD is re-asserted each cycle by WAIT Dn / KEY scan-all if the
    // condition isn't yet satisfied; clearing it here is the default.
    flags &= ~FLG_HOLD;


    // ── One-cycle validity windows ────────────────────────────────────
    // EXT and Sout are only valid for the single cycle after they are written.
    // The flags gate that window; on the second cycle they are zeroed out.
    if (flags & FLG_EXT_VALID) flags &= ~FLG_EXT_VALID;
    else                       EXT = 0;

    if (flags & FLG_IO_VALID) flags &= ~FLG_IO_VALID;
    else                      memset(Sout, 0, sizeof(Sout));

    // ─────────────────────────────────────────────────────────────────
    // Instruction decode
    // ─────────────────────────────────────────────────────────────────

    if (opcode & 0x1000) {
        // ── Branch (bit 12 set) ───────────────────────────────────────
        // Taken when COND flag (bit 11 of `flags`) matches bit 11 of the opcode.
        // The XOR trick: if (flags ^ opcode) bit 11 == 0, both agree → branch taken.
        // Offset is 10 bits (bits 10:1); bit 0 selects backward (1) or forward (0).
        flags |= FLG_JUMP;  // triggers COND auto-restore on the next non-branch
        if (!((flags ^ opcode) & FLG_COND)) {
            uint16_t offs = (opcode >> 1) & 0x3FFu;
            if (opcode & 0x0001) addr = static_cast<uint16_t>(addr - offs);
            else                 addr = static_cast<uint16_t>(addr + offs);
        } else {
            addr++;
        }
        int w = (flags & FLG_IDLE) ? 4 : 1;
        if (tf != TRACE_NONE) [[unlikely]] { tracePostStep(tf, w); }
        if ((flags & FLG_IDLE) ? (fA & 0x4000u) : fA) m_cSteps.fetch_add(1, std::memory_order_relaxed);
        m_pollSteps.fetch_add(static_cast<uint32_t>(w), std::memory_order_relaxed);
        return w;
    }


    switch (opcode & 0x0F00) {

    // ── Flag operations (hi nibble = 0x0) ────────────────────────────
    // Operate on individual bits of the ROM-visible flag registers fA and fB,
    // or on individual bits of KR.  The bit index is encoded in opcode bits 7:4.
    case 0x0000: {
        unsigned bit  = (opcode >> 4) & 0x000Fu;
        uint16_t mask = static_cast<uint16_t>(1u << bit);
        switch (opcode & 0x000Fu) {
        case 0x0: if (fA & mask) flags &= ~FLG_COND; break;  // TST fA[b]  — clear COND if bit set
        case 0x1: fA |=  mask;                        break;  // SET fA[b]
        case 0x2: fA &= ~mask;                        break;  // CLR fA[b]
        case 0x3: fA ^=  mask;                        break;  // INV fA[b]
        case 0x4: if ((fA ^ fB) & mask) { fA ^= mask; fB ^= mask; } break; // XCH fA[b],fB[b]
        case 0x5: KR |= mask; break;  // SET KR[b]
        case 0x6: if ((fA ^ fB) & mask) fA ^= mask;  break;  // MOV fA[b],fB[b]  (copy fB→fA if different)
        case 0x7: fA = static_cast<uint16_t>((fA & ~0x001Eu) | ((R5 & 0x0Fu) << 1)); break; // MOV fA[1..4],R5
        case 0x8: if (fB & mask) flags &= ~FLG_COND; break;  // TST fB[b]
        case 0x9: fB |=  mask;                        break;  // SET fB[b]
        case 0xA: fB &= ~mask;                        break;  // CLR fB[b]
        case 0xB: fB ^=  mask;                        break;  // INV fB[b]
        case 0xC: if (!((fA ^ fB) & mask)) flags &= ~FLG_COND; break; // CMP fA[b],fB[b] — clear COND if equal
        case 0xD: KR &= ~mask;                        break;  // CLR KR[b]
        case 0xE: if ((fA ^ fB) & mask) fB ^= mask;  break;  // MOV fB[b],fA[b]  (copy fA→fB if different)
        case 0xF: fB = static_cast<uint16_t>((fB & ~0x001Eu) | ((R5 & 0x0Fu) << 1)); break; // MOV fB[1..4],R5
        default: break;
        }
        break;
    }

    // ── Keyboard scan (hi nibble = 0x8) ──────────────────────────────
    // The opcode encodes a 7-bit column mask (K-lines KN…KT) to test against
    // key[digit] — the currently active keyboard row.
    // Mode bit (opcode bit 3):
    //   0 = scan-all: HOLD until digit 0 completes, scanning all 16 rows.
    //       If a key matches: update KR with {row, col}, clear COND.
    //   1 = test-row: test only the current digit's row; clear COND if pressed.
    case 0x0800: {
        // Reconstruct the 7-bit K-line mask from the opcode.  The hardware
        // packs the mask across two non-contiguous fields:
        //   bits 2:0 → K-lines KN/KO/KP  (low 3 bits of mask)
        //   bits 10:4 → K-lines KQ/KR/KS/KT  (high 4 bits, shifted down by 1)
        // XOR with 0x7F inverts all 7 bits because the key[] bitmask uses
        // active-high (bit set = key pressed), while the opcode encodes the
        // mask active-low (0 = "care about this line").
        uint8_t kmask = static_cast<uint8_t>(
            (((opcode & 0x07u) | ((opcode >> 1) & 0x78u)) ^ 0x7Fu) & key[digit]);
        // Reject simultaneous multi-key presses (hardware limitation)
        if (kmask & (kmask - 1u)) kmask = 0;

        if (!(opcode & 0x0008u)) {
            // Scan-all mode: hold and scan until digit 0 or key found.
            // Digit 0 is the termination sentinel only — it is NOT checked for
            // key state.  Signals wired at D0 (e.g. KP.D0 = PRN_CONNECTED) are
            // intentionally invisible to scan-all; the ROM detects them with a
            // dedicated test-row ?KEY executed when digit == 0.
            if (digit && (key[digit] & kmask)) {
                uint8_t bit = 0, m2 = kmask;
                while (!(m2 & 1)) { bit++; m2 >>= 1; }
                flags &= ~FLG_COND;
                KR = static_cast<uint16_t>((digit << 4) | ((bit << 8) & 0x0700u));
            } else if (digit) {
                flags |= FLG_HOLD;  // not at digit 0 yet — re-execute
            }
        } else {
            // Test-row mode: check only the current row
            if (key[digit] & kmask) flags &= ~FLG_COND;
        }
        break;
    }

    // ── Wait / Control (hi nibble = 0xA) ─────────────────────────────
    case 0x0A00:
        switch (opcode & 0x000Fu) {

        case 0x0:  // WAIT Dn — hold until digit counter == arg
            // The counter is decremented before this test (see above), so the
            // ROM encodes the target as n+1 (e.g. "WAIT D1" waits for digit 0).
            if (digit != ((opcode >> 4) & 0x000Fu)) {
                flags |= FLG_HOLD;
            }
            break;

        case 0x1:  // CLR IDL — exit idle/display mode; resume full speed
            flags &= ~FLG_IDLE;
            // Latch fires on every CLR IDL so getDisplay() (60 Hz) always sees
            // at least one frame of C=true, even for brief computations where
            // fA stays 0 throughout (e.g. simple digit entry like "1").
            m_calcLatch.store(true, std::memory_order_relaxed);
            break;

        case 0x2: fA = 0; break;  // CLR fA — clear all 16 fA flag bits at once

        case 0x3: /* WAIT BUSY — undocumented; treated as no-op */ break;

        case 0x4:  // INC KR — step the SCOM constant-table pointer
            // KR bits 7:4 index the current constant entry; incrementing
            // them walks through the 64-entry constant table.  When bits
            // 15:4 all reach zero, bit 0 toggles as an overflow indicator.
            KR = static_cast<uint16_t>(KR + 0x0010u);
            if (!(KR & 0xFFF0u)) KR ^= 0x0001u;
            break;

        case 0x5:  // TST KR[a] — clear COND if KR bit is set
            if (KR & (1u << ((opcode >> 4) & 0x000Fu))) flags &= ~FLG_COND;
            break;

        case 0x6: {
            // TI-58C uses 0xA76 (MEMWR) and 0xA86 (MEMRD); reserve bits 7:4 = 0x7/0x8
            // TI-59/58 use these bits for MOV R5 operand selection (bit 4 = fA/fB choice)
            uint8_t bits_7_4 = static_cast<uint8_t>((opcode >> 4) & 0x000Fu);
            if (hasConstantMemory(m_variant) && bits_7_4 == 0x7) {
                // MEMWR — deferred write: capture address from Sout now; the
                // actual data comes from the IO bus at the END of the next
                // instruction cycle (deferred to FLG_RAM_WRITE handler below).
                // If that instruction drives IO as output (FLG_IO_VALID), Sout
                // carries the data. Otherwise the bus is in input mode and reads
                // as zero — so zero is written. Address is Sout[1:0].
                RAM_ADDR = static_cast<uint8_t>((Sout[1] * 16u) + Sout[0]);
                if (RAM_ADDR < ram.size())
                    flags |= FLG_RAM_WRITE;
            } else if (hasConstantMemory(m_variant) && bits_7_4 == 0x8) {
                // MEMRD — read RAM[RAM_ADDR] into next MOV #0 as srcY (set up by preceding ALU opcode)
                // Address is encoded in Sout[1:0] as two hex nibbles.
                RAM_ADDR = static_cast<uint8_t>((Sout[1] * 16u) + Sout[0]);
                if (RAM_ADDR < ram.size())
                    flags |= FLG_RAM_READ;
            } else {
                // MOV R5,fA[1..4] or fB[1..4] — copy bits 1-4 into R5
                uint16_t flags = (opcode & 0x0010u) ? fB : fA;
                R5 = static_cast<uint8_t>((flags >> 1) & 0x0Fu);
            }
            break;
        }

        case 0x7:  // MOV R5,#n — load 4-bit immediate into R5
            R5 = static_cast<uint8_t>((opcode >> 4) & 0x000Fu);
            break;

        case 0x8:  // Peripheral I/O (card reader, printer, RAM, library)
            switch (opcode & 0x00F0u) {
            case 0x00: R5 = static_cast<uint8_t>((KR >> 4) & 0x000Fu); break;  // MOV R5,KR[4..7]
            case 0x10: KR = static_cast<uint16_t>((KR & ~0x00F0u) | (static_cast<uint16_t>(R5) << 4)); break; // MOV KR[4..7],R5
            case 0x20: // IN CRD — card read: fetch next nibble into EXT bits 4-7
                if (m_cardPresent && m_cardMode == 1 && m_cardPtr < 246) {
                    EXT = static_cast<uint16_t>(m_cardBankBuffer[m_cardPtr++]) << 4;
                } else {
                    EXT = 0;
                }
                flags |= FLG_EXT_VALID;
                break;
            case 0x30: // OUT CRD — card write: capture KR bits 4-11 (both nibbles) into bank buffer
                if (m_cardPresent && m_cardMode == 2 && m_cardPtr < 246) {
                    m_cardBankBuffer[m_cardPtr++] = static_cast<uint8_t>((KR >> 4) & 0xFFu);
                }
                break;
            case 0x40: // CRD_OFF — finalize bank operation; card exits reader
                if (m_cardMode == 2) {
                    // Flush bank buffer back to full card data based on bank index in byte 2.
                    // nibble index 2 -> byte 2 in our 1-byte-per-nibble mapping.
                    int bank = static_cast<int>((m_cardBankBuffer[2] & 0x0Fu) / 3);
                    if (bank >= 0 && bank < 4) {
                        memcpy(m_cardFullData + (static_cast<size_t>(bank) * 246), m_cardBankBuffer, 246);
                        m_lastWrittenBank = bank;
                    }
                } else if (m_cardMode == 1) {
                    // Card banks 0–3 are encoded as nibble values 0,3,6,9; advance by 3 per read pass.
                    m_cardBankBuffer[2] = static_cast<uint8_t>((m_cardBankBuffer[2] + 3) & 0x0F);
                }
                m_cardMode = 0;
                m_cardPtr  = 0;
                // Auto-eject: on real hardware the card physically exits the reader
                // after each pass (read or write).  Restore the card-absent key state
                // so the ROM doesn't loop back and start a second spurious operation.
                m_cardPresent = false;
                key[m_cardSwitchCol] |= (1u << 4);
                break;
            case 0x50: // CRD_READ — load requested bank into swipe buffer
                if (m_cardMode == 0) {
                    int bank = static_cast<int>((m_cardBankBuffer[2] & 0x0Fu) / 3);
                    if (bank >= 0 && bank < 4) {
                        memcpy(m_cardBankBuffer, m_cardFullData + (static_cast<size_t>(bank) * 246), 246);
                    }
                    m_cardMode = 1;
                    m_cardPtr  = 0;
                }
                break;
            case 0xC0: // CRD_WRITE — start writing to current bank
                if (m_cardMode == 0) {
                    m_cardMode = 2;
                    m_cardPtr  = 0;
                }
                break;
            case 0x60: { // OUT PRT — load one character into print buffer
                if (m_prnReady) {
                    uint8_t code = static_cast<uint8_t>((KR >> 4) & 0x3Fu);
                    uint8_t slot = m_prnPtr % 20;
                    m_prnBuf[slot]     = PRN_CODE[code];
                    m_prnCodeBuf[slot] = code;
                    m_prnPtr = slot + 1;
                }
                break;
            }
            case 0x70: { // OUT PRT_FUNC — load 3-char function mnemonic (stored reversed)
                if (m_prnReady) {
                    uint8_t code = static_cast<uint8_t>((KR >> 4) & 0x7Fu);
                    for (int i = 0; PRN_STR[i].str[0]; i++) {
                        if (code == PRN_STR[i].code) {
                            // Store chars reversed so print-reversal restores correct order
                            for (int k = 3; k > 0; ) {
                                --k;
                                uint8_t slot = m_prnPtr % 20;
                                m_prnBuf[slot]     = PRN_STR[i].str[k];
                                m_prnCodeBuf[slot] = prnCharToCode(PRN_STR[i].str[k]);
                                m_prnPtr = slot + 1;
                            }
                            break;
                        }
                    }
                }
                break;
            }
            case 0x80: // PRT_CLEAR — reset print buffer; arms the ready gate
                for (auto& s : m_prnBuf) s = " ";
                memset(m_prnCodeBuf, 0, sizeof(m_prnCodeBuf));
                m_prnPtr = 0;
                m_prnReady = true;
                break;
            case 0x90: // PRT_STEP — advance one position (blank)
                if (m_prnReady) {
                    uint8_t slot = m_prnPtr % 20;
                    m_prnBuf[slot]     = " ";
                    m_prnCodeBuf[slot] = 0;
                    m_prnPtr = slot + 1;
                }
                break;
            case 0xA0: { // PRT_PRINT — output buffer as a line
                if (m_prnReady) {
                    // Buffer is right-to-left: read from position 19 down to 0.
                    std::string line;
                    std::array<uint8_t,20> codes{};
                    for (int i = 19; i >= 0; --i) {
                        line += m_prnBuf[i];
                        codes[19 - i] = m_prnCodeBuf[i];
                    }
                    {
                        std::lock_guard<std::mutex> lk(m_prnMutex);
                        m_prnLines.push_back(std::move(line));
                        m_prnCodeLines.push_back(codes);
                    }
                    flags |= FLG_BUSY;
                    m_prnBusyCycles = 2808;  // (197.5ms * 455kHz) / 2 / 16 / 1000
                }
                break;
            }
            case 0xB0: // PRT_FEED — advance paper (blank line)
                // ADV button sends PRT_FEED continuously while held; BUSY gates the rate.
                // Measured on real PC-100C hardware: 40 ADV lines in 7.9s → 197.5ms/line.
                // Note: 40 LIST lines take 12.7s → 317.5ms/line; the extra 120ms/line is
                // communication overhead (serial transfer of ~13 characters at ~9.5ms each).
                // That overhead is not yet modelled — it requires per-output BUSY pulses that
                // only fire when the ROM polls TST BUSY between characters.
                {
                    std::lock_guard<std::mutex> lk(m_prnMutex);
                    m_prnLines.emplace_back();
                    m_prnCodeLines.emplace_back();  // zero-filled
                }
                flags |= FLG_BUSY;
                m_prnBusyCycles = 2808;  // (197.5ms * 455kHz) / 2 / 16 / 1000
                break;
            case 0xF0: // RAM_OP — deferred decode: next Sout encodes operation + address
                // Deferred operation: capture operation and address from Sout.
                // Sout[0] = opcode (0=read, 1=write, 2=clear, 4=clear×10);
                // Sout[3]*10 + Sout[2] = register address. If the next instruction
                // drives IO as output (FLG_IO_VALID), Sout carries the data.
                flags |= FLG_RAM_OP;
                break;
            default: break;
            }
            break;

        case 0x9:  // SET IDL — enter idle/display mode
            // Marks FLG_IDLE so step() returns 4 (1/4 speed) and schedules a
            // display snapshot at the next digit=0 boundary.
            flags |= FLG_IDLE;
            m_pendingDisplayUpdate = true;
            break;

        case 0xA: fB = 0; break;  // CLR fB — clear all 16 fB flag bits at once

        case 0xB:  // TST BUSY — clear COND if printer/peripheral is busy
            // Card sensor is on bit 4 of m_cardSwitchCol.
            // ROM polls this specifically when waiting for a card.
            if (!m_cardPresent && digit == m_cardSwitchCol && (key[digit] & (1u << 4)))
                m_waitingForCard = true;
            // Clear COND to signal "busy" to the ROM, but do NOT clear FLG_BUSY here —
            // m_prnBusyCycles is the sole mechanism that drops FLG_BUSY after the delay.
            if ((key[digit] & (1u << 4)) || (flags & FLG_BUSY))
                flags &= ~FLG_COND;
            break;

        case 0xC:  // MOV KR,EXT[4..15] — load KR upper bits from card/library read
            KR = static_cast<uint16_t>((KR & 0x000Fu) | EXT);
            break;

        case 0xD:  // XCH KR,SR — swap KR and SR (primary subroutine return mechanism)
            { uint16_t t = KR; KR = SR; SR = t; }
            break;

        case 0xE:  // Library module operations
            switch (opcode & 0x00F0u) {
            case 0x00: // IN LIB — fetch one byte from library; advance pointer
                EXT = static_cast<uint16_t>(m_libData[m_libAddr++]) << 4;
                flags |= FLG_EXT_VALID;
                m_libAddr %= 5000;
                break;
            case 0x10: // OUT LIB_PC — load library pointer digit from KR[7:4]
                // The library address is encoded in BCD-like decimal: the ROM
                // shifts it one decimal digit at a time using OUT LIB_PC / IN LIB_PC
                // pairs. OUT LIB_PC shifts the address right by one nibble, then
                // injects the new nibble into the most significant position:
                //   new_addr = (old_addr / 10)         ← shift right (discard LSN)
                //            + KR[7:4] * 1000          ← inject new MSN
                // The ROM calls this instruction four times to load a full
                // 4-digit address (once per BCD nibble, MSN first).
                if (!m_libAddrWasWriting) m_libAddrReadPos = 0;  // Reset if switching from read to write
                m_libAddr = static_cast<uint16_t>((m_libAddr / 10) + ((KR >> 4 & 0xFu) * 1000));
                m_libAddrReadPos = (m_libAddrReadPos + 1) % 4;
                m_libAddrWasWriting = true;
                break;
            case 0x20: // IN LIB_PC — read library pointer digit into EXT
                // Reads the current digit of m_libAddr based on m_libAddrReadPos (0-3).
                // Does not modify m_libAddr; only advances the read position counter.
                {
                    if (m_libAddrWasWriting) m_libAddrReadPos = 0;  // Reset if switching from write to read
                    uint16_t divisors[4] = {1, 10, 100, 1000};
                    EXT = static_cast<uint16_t>((m_libAddr / divisors[m_libAddrReadPos]) % 10) << 4;
                    flags |= FLG_EXT_VALID;
                    m_libAddrReadPos = (m_libAddrReadPos + 1) % 4;
                    m_libAddrWasWriting = false;
                }
                break;
            case 0x30: // IN LIB_HIGH — fetch high nibble of current byte (no advance)
                EXT = static_cast<uint16_t>(m_libData[m_libAddr] & 0xF0u);
                flags |= FLG_EXT_VALID;
                break;
            default: break;
            }
            break;

        case 0xF:  // STO / RCL — SCOM register store or recall
            // Deferred write: capture register address from Sout now; the actual
            // data comes from the IO bus at the END of the next instruction cycle
            // (deferred to FLG_STORE handler below). Sout[0] encodes the register
            // number 0–15. If that instruction drives IO as output (FLG_IO_VALID),
            // Sout carries the data. Otherwise the bus reads as zero.
            switch (opcode & 0x00F0u) {
            case 0x00: REG_ADDR = Sout[0] & 0x0Fu; flags |= FLG_STORE; break; // STO
            case 0x10: flags |= FLG_RECALL; REG_ADDR = Sout[0] & 0x0Fu; break; // RCL
            default: break;
            }
            break;
        default: break;
        }
        break;

    // ── ALU operations ────────────────────────────────────────────────
    default:
        execALU(opcode);
        break;
    }

    // ── PREG redirect (after instruction execution) ───────────────────
    // If PREG is set (SET KR[1] was executed in the previous instruction),
    // the next instruction has now completed. Redirect PC to the latched
    // address and clear PREG.
    if (PREG) {
        addr = PREG;
        PREG = 0;
    } else if (!(flags & FLG_HOLD)) {
        addr++;
    }
    int w = (flags & FLG_IDLE) ? 4 : 1;
    if (tf != TRACE_NONE) [[unlikely]] { tracePostStep(tf, w); }
    if ((flags & FLG_IDLE) ? (fA & 0x4000u) : fA) m_cSteps.fetch_add(1, std::memory_order_relaxed);
    m_pollSteps.fetch_add(static_cast<uint32_t>(w), std::memory_order_relaxed);

    // ── PREG latch (after instruction execution) ─────────────────────────
    // When KR bit 1 is set (by SET KR[1] instruction), store the address
    // in PREG and clear KR[1] immediately. The redirect will fire at the end
    // of the next instruction cycle.
    if (KR & 0x2) {
        PREG = (KR >> 4) | ((KR & 0x1) << 12);  // Store address
        KR  &= ~static_cast<uint16_t>(0x2);
    }

    return w;
}

// ── ALU opcode decoder ────────────────────────────────────────────────────────
//
// Decodes the source operands, destination register, and operation from the
// 13-bit ALU opcode, then calls alu() to execute the digit-serial computation.
//
// Opcode layout:  0 ffff ooooo ddd
//   ffff  (bits 11:8) — field mask index → mask_info[ffff]
//   ooooo (bits  7:3) — ALU operation and source pair (5-bit index)
//   ddd   (bits  2:0) — destination register (A/B/C/D/IO or exchange)

void TMC0501::execALU(uint16_t opcode) {
    const MaskInfo& m = mask_info[(opcode >> 8) & 0x0Fu];

    // Source operand pair — decoded from the 5-bit operation index (bits 7:3).
    // Operations 0–23 select two registers as srcX (augend) and srcY (addend).
    // Operations 24–31 are special cases handled below (constant, SCOM/RAM, R5).
    const uint8_t* srcX = nullptr;
    const uint8_t* srcY = nullptr;
    int aluOp = ALU_ADD;
    int aluIdx = static_cast<int>((opcode >> 3) & 0x1Fu);
    switch (aluIdx) {
    case  0: srcX=A;       srcY=nullptr; aluOp=ALU_ADD; break;
    case  1: srcX=A;       srcY=nullptr; aluOp=ALU_SUB; break;
    case  2: srcX=nullptr; srcY=B;       aluOp=ALU_ADD; break;
    case  3: srcX=nullptr; srcY=B;       aluOp=ALU_SUB; break;
    case  4: srcX=C;       srcY=nullptr; aluOp=ALU_ADD; break;
    case  5: srcX=C;       srcY=nullptr; aluOp=ALU_SUB; break;
    case  6: srcX=nullptr; srcY=D;       aluOp=ALU_ADD; break;
    case  7: srcX=nullptr; srcY=D;       aluOp=ALU_SUB; break;
    case  8: srcX=A;       srcY=nullptr; aluOp=ALU_SHL; break;
    case  9: srcX=A;       srcY=nullptr; aluOp=ALU_SHR; break;
    case 10: srcX=nullptr; srcY=B;       aluOp=ALU_SHL; break;
    case 11: srcX=nullptr; srcY=B;       aluOp=ALU_SHR; break;
    case 12: srcX=C;       srcY=nullptr; aluOp=ALU_SHL; break;
    case 13: srcX=C;       srcY=nullptr; aluOp=ALU_SHR; break;
    case 14: srcX=nullptr; srcY=D;       aluOp=ALU_SHL; break;
    case 15: srcX=nullptr; srcY=D;       aluOp=ALU_SHR; break;
    case 16: srcX=A;       srcY=B;       aluOp=ALU_ADD; break;
    case 17: srcX=A;       srcY=B;       aluOp=ALU_SUB; break;
    case 18: srcX=C;       srcY=B;       aluOp=ALU_ADD; break;
    case 19: srcX=C;       srcY=B;       aluOp=ALU_SUB; break;
    case 20: srcX=C;       srcY=D;       aluOp=ALU_ADD; break;
    case 21: srcX=C;       srcY=D;       aluOp=ALU_SUB; break;
    case 22: srcX=A;       srcY=D;       aluOp=ALU_ADD; break;
    case 23: srcX=A;       srcY=D;       aluOp=ALU_SUB; break;
    default: srcX=nullptr; srcY=nullptr; aluOp=ALU_ADD; break;
    }

    // Destination register — decoded from opcode bits 2:0.
    // Codes 2 (AxB), 5 (CxD), and 7 (AxE) are exchange instructions;
    // their dst is nullptr here and the xch() call below handles the swap.
    uint8_t* dst = nullptr;
    switch (opcode & 0x0007u) {
    case 0: dst = A; break;
    case 1: dst = nullptr; flags |= FLG_IO_VALID; break; // IO-only: result goes to Sout only
    case 2: dst = nullptr; break;  // XCH A,B
    case 3: dst = B; break;
    case 4: dst = C; break;
    case 5: dst = nullptr; break;  // XCH C,D
    case 6: dst = D; break;
    case 7: dst = nullptr; break;  // XCH A,E
    default: break;
    }

    // SCOM constant index — built from KR bits 10:4 (7 bits total).
    // The unusual bit arrangement mirrors the hardware's KR field layout.
    int constIdx = static_cast<int>(((KR >> 5) & 0x78u) | ((KR >> 4) & 0x07u));
    if (constIdx >= 64) constIdx = 0;
    const uint8_t* constPtr = m_constant[constIdx];

    // Special-case ALU operations (indices 24–31, opcode bits 7:3 = 0x18–0x1F)
    switch (opcode & 0x00F8u) {
    case 0x00C0: alu(dst, A, constPtr,       m, ALU_ADD); break; // ADD dst, A, const
    case 0x00C8: alu(dst, A, constPtr,       m, ALU_SUB); break; // SUB dst, A, const
    case 0x00D0:  // MOV dst, #0  — may be overridden by a pending recall
        if (flags & FLG_RECALL) {
            // SCOM recall: deliver SCOM[REG_ADDR] as srcY (set up by preceding RCL)
            // Only read the nibbles specified by the field mask to prevent carry
            // propagation from unmasked nibbles affecting the masked result.
            flags &= ~FLG_RECALL;
            uint8_t masked[16]{};
            readScomMasked(masked, REG_ADDR, m);
            alu(dst, nullptr, masked, m, ALU_ADD);
        } else if ((flags & FLG_RAM_READ) && RAM_ADDR < ram.size()) {
            // RAM read: deliver RAM[RAM_ADDR] as srcY (set up by preceding MEMRD)
            // Only read the nibbles specified by the field mask
            flags &= ~FLG_RAM_READ;
            uint8_t masked[16]{};
            readRegMasked(masked, RAM_ADDR, m);
            alu(dst, nullptr, masked, m, ALU_ADD);
        } else {
            alu(dst, nullptr, nullptr, m, ALU_ADD);  // plain zero-load
        }
        break;
    case 0x00D8: alu(dst, nullptr, nullptr,  m, ALU_SUB); break; // NEG dst (negate zero = zero in BCD)
    case 0x00E0: alu(dst, C, constPtr,       m, ALU_ADD); break; // ADD dst, C, const
    case 0x00E8: alu(dst, C, constPtr,       m, ALU_SUB); break; // SUB dst, C, const
    case 0x00F0: // MOV dst, R5 — load R5 into the start digit of the masked field
    case 0x00F8: // (0xF8 variant subtracts rather than adds for the BCD normalisation pass)
        if (dst) {
            // Zero all field digits except start, then inject the mask constant and R5.
            // Running the result through alu() applies BCD carry-correction, which is
            // needed when the field includes EXP or DPT digits with base-16 behaviour.
            for (int i = static_cast<int>(m.start) + 1; i <= static_cast<int>(m.end); ++i) dst[i] = 0;
            dst[m.cpos]  = m.cval;
            dst[m.start] = R5;
            alu(dst, nullptr, dst, m, (opcode & 0x0008u) ? ALU_SUB : ALU_ADD);
        }
        break;
    default:
        alu(dst, srcX, srcY, m, aluOp);
        break;
    }

    // Exchange instructions — swap the masked field between two registers
    switch (opcode & 0x0007u) {
    case 2: xch(A, B, m); break;
    case 5: xch(C, D, m); break;
    case 7: xch(A, E, m); break;
    default: break;
    }

    // ── Capture field mask for deferred RAM operations ────────────────
    // When an ALU instruction executes after MEMWR/MEMRD, capture its
    // field mask for use when the deferred write/read actually completes.
    if ((flags & FLG_RAM_WRITE) || (flags & FLG_RAM_READ)) {
        RAM_MASK = m;
    }

    // ── Deferred SCOM store (STO / STOF / STOG) ────────────────────────
    // Write Sout (the IO bus) into the SCOM register selected by the
    // preceding STO instruction. If the last instruction did not drive IO
    // (FLG_IO_VALID not set), the bus reads as zero — so zero is written.
    if (flags & FLG_STORE) {
        flags &= ~FLG_STORE;
        uint8_t io_data[16] = {};
        if (flags & FLG_IO_VALID) memcpy(io_data, Sout, sizeof(io_data));
        memcpy(SCOM[REG_ADDR], io_data, 16);
        char nb[17];
        emitDebug(2, "STO SCOM[%02d] = %s", REG_ADDR, fmtNibs(io_data, nb, true));
    }

    // ── Deferred RAM operation decode ───────────────────────────────────
    // Decode the operation and address from Sout. Sout[0] = opcode (read/write/
    // clear); Sout[3]*10 + Sout[2] = register address. If the last instruction
    // did not drive IO (FLG_IO_VALID not set), the bus reads as zero.
    if (flags & FLG_RAM_OP) {
        flags &= ~FLG_RAM_OP;
        uint8_t op_nibble = 0, addr_tens = 0, addr_units = 0;
        if (flags & FLG_IO_VALID) {
            op_nibble = Sout[0] & 0x0Fu;
            addr_tens = Sout[3];
            addr_units = Sout[2];
        }
        RAM_OP = op_nibble;
        RAM_ADDR = static_cast<uint8_t>((addr_tens * 10u) + addr_units);
        if (RAM_ADDR < ram.size()) {
            if      (RAM_OP == 2) { ram.clearReg(RAM_ADDR, 1);  emitDebug(2, "RAM_OP CLR1 RAM[%03d]",  RAM_ADDR); }
            else if (RAM_OP == 4) { ram.clearReg(RAM_ADDR, 10); emitDebug(2, "RAM_OP CLR10 RAM[%03d]", RAM_ADDR); }
            else if (RAM_OP == 1) flags |= FLG_RAM_WRITE;
            else if (RAM_OP == 0) flags |= FLG_RAM_READ;
        }
    } else if (flags & FLG_RAM_WRITE) {
        // ── Deferred RAM write (MEMWR / RAM_OP write) ────────────────
        // Write Sout (the IO bus) into RAM[RAM_ADDR] at the masked field.
        // If the last instruction did not drive IO (FLG_IO_VALID not set),
        // the bus reads as zero — so zero is written.
        flags &= ~FLG_RAM_WRITE;
        if (RAM_ADDR < ram.size()) {
            uint8_t io_data[16] = {};
            if (flags & FLG_IO_VALID) memcpy(io_data, Sout, sizeof(io_data));
            writeRegMasked(RAM_ADDR, io_data, RAM_MASK);
            char nb[17];
            emitDebug(2, "MEMWR RAM[%03d] = %s", RAM_ADDR, fmtNibs(io_data, nb));
        }
    }

    // Keep Sout zeroed between cycles unless FLG_IO_VALID is still active
    if (!(flags & FLG_IO_VALID))
        memset(Sout, 0, sizeof(Sout));

}

// ── Magnetic card reader ───────────────────────────────────────────────────────

void TMC0501::insertCard(const uint8_t* data, size_t count) {
    memset(m_cardFullData, 0, 984);
    if (data && count > 0) {
        if (count >= 984) {
            // Legacy 4-bank file: copy all banks verbatim.
            memcpy(m_cardFullData, data, 984);
        } else if (count == 246) {
            // Single-bank file: always place at slot 0.  CRD_READ starts at
            // m_cardBankBuffer[2]=0 (slot 0) on first swipe; the bank identity
            // is encoded inside the data itself (byte 2) and is what the ROM
            // uses to identify which bank was loaded — not the file offset.
            memcpy(m_cardFullData, data, 246);
        } else {
            // Partial or unknown size: store at offset 0.
            memcpy(m_cardFullData, data, count);
        }
    }
    // Start with a zeroed bank buffer; CRD_READ will load the correct bank on demand.
    memset(m_cardBankBuffer, 0, sizeof(m_cardBankBuffer));
    m_cardPtr         = 0;
    m_cardMode        = 0;
    m_lastWrittenBank = -1;
    m_cardPresent     = true;
    m_waitingForCard = false;
    key[m_cardSwitchCol] &= ~(1u << 4);  // release = card present
}

std::vector<uint8_t> TMC0501::cardEject() {
    m_cardPresent    = false;
    m_waitingForCard = false;
    key[m_cardSwitchCol] |= (1u << 4);   // press = card absent
    m_cardMode = 0;
    // Return only the single bank that was written, not all four banks.
    // If no write occurred (read swipe or no swipe), return empty.
    if (m_lastWrittenBank < 0 || m_lastWrittenBank > 3)
        return {};
    const uint8_t* bank = m_cardFullData + (static_cast<size_t>(m_lastWrittenBank) * 246);
    std::vector<uint8_t> result(bank, bank + 246);
    m_lastWrittenBank = -1;
    return result;
}

// ── Printer ────────────────────────────────────────────────────────────────────

std::vector<std::string> TMC0501::drainPrinterLines() {
    std::lock_guard<std::mutex> lk(m_prnMutex);
    return std::move(m_prnLines);
}

std::vector<std::array<uint8_t,20>> TMC0501::drainPrinterCodeLines() {
    std::lock_guard<std::mutex> lk(m_prnMutex);
    return std::move(m_prnCodeLines);
}

void TMC0501::pressPrinterPrint(bool pressed) {
    if (pressed) key[12] |=  (1u << 2);
    else         key[12] &= ~(1u << 2);
}

void TMC0501::pressPrinterAdv(bool pressed) {
    if (pressed) key[12] |=  (1u << 0);
    else         key[12] &= ~(1u << 0);
}

void TMC0501::setPrinterTrace(bool enabled) {
    if (enabled) key[15] |=  (1u << 2);
    else         key[15] &= ~(1u << 2);
}

void TMC0501::setPrinterConnected(bool connected) {
    // Printer-connected detection line: KP at the digit the ROM tests via
    // test-row ?KEY.  TI-59 uses WAIT D1 + KEY FB → executes at digit 0 (KP.D0).
    // TI-58C uses WAIT D11 + KEY FB → executes at digit 10 (KP.D10).
    // The printer connector is physically identical on both models, but the
    // TI-58C PCB routes the detection pin to a different digit-counter line.
    int d = hasConstantMemory(m_variant) ? 10 : 0;
    if (connected) key[d] |=  (1u << 2);
    else           key[d] &= ~(1u << 2);
}

// ── Trace / debug API ──────────────────────────────────────────────────────────

void TMC0501::setTraceFlags(uint32_t f) {
    m_traceFlags.store(f, std::memory_order_relaxed);
}

uint32_t TMC0501::traceFlags() const {
    return m_traceFlags.load(std::memory_order_relaxed);
}

void TMC0501::addBreakpoint(uint16_t pc) {
    std::lock_guard<std::mutex> lk(m_traceMutex);
    auto it = std::lower_bound(m_breakpoints.begin(), m_breakpoints.end(), pc);
    if (it == m_breakpoints.end() || *it != pc)
        m_breakpoints.insert(it, pc);
}

void TMC0501::removeBreakpoint(uint16_t pc) {
    std::lock_guard<std::mutex> lk(m_traceMutex);
    auto it = std::lower_bound(m_breakpoints.begin(), m_breakpoints.end(), pc);
    if (it != m_breakpoints.end() && *it == pc)
        m_breakpoints.erase(it);
}

void TMC0501::clearBreakpoints() {
    std::lock_guard<std::mutex> lk(m_traceMutex);
    m_breakpoints.clear();
}

bool TMC0501::consumeBreakpointHit() {
    if (m_breakpointHit) { m_breakpointHit = false; return true; }
    return false;
}

// ── beginNextStep ─────────────────────────────────────────────────────────────
//
// Pre-execution phase for the next instruction to run. Called at the very start
// of step() so the running loop gets it for free; also called explicitly by the
// debugger after freeze or a step, to ensure the ring buffer is display-ready.
//
// Safe to call multiple times for the same addr: observable state is idempotent
// (COND auto-restore only fires if FLG_JUMP set; ring patches write same values).
// However, repeated calls do redundant ROM reads and snapshot captures.

void TMC0501::beginNextStep() {
    const uint32_t tf = m_traceFlags.load(std::memory_order_relaxed);

    m_pendingOpcode = rom.read(addr);

    // COND auto-restore: first non-branch instruction after a jump sequence
    // restores COND to 1 so the next TST/CMP starts from a clean slate.
    if (!(m_pendingOpcode & 0x1000) && (flags & FLG_JUMP)) {
        flags &= ~FLG_JUMP;
        flags |=  FLG_COND;
    }

    // Patch the previous ring entry to the CPU's post-execution state.
    // This runs for every instruction (branch and non-branch), so every stored
    // frame uses the same post-exec semantics for UI and trace-file consumers,
    // including COND after auto-restore handling.
    if (tf != TRACE_NONE && m_frameHead > 0) {
        CpuFrame& prev = m_frameRing[(m_frameHead - 1) & kFrameRingMask];
        if (tf & (TRACE_REGS_LIGHT | TRACE_REGS_FULL)) {
            prev.KR       = KR;
            prev.SR       = SR;
            prev.fA       = fA;
            prev.fB       = fB;
            prev.cpuFlags = flags;
            prev.R5       = R5;
        }
        if (tf & TRACE_REGS_FULL) {
            memcpy(prev.A,    A,    16);
            memcpy(prev.B,    B,    16);
            memcpy(prev.C,    C,    16);
            memcpy(prev.D,    D,    16);
            memcpy(prev.E,    E,    16);
            memcpy(prev.SCOM, SCOM, sizeof(SCOM));
            memcpy(prev.Sout, Sout, 16);
            prev.EXT = EXT;
            prev.PREG = PREG ? 1 : 0;
            prev.flags = flags;
            prev.m_libAddr = m_libAddr;
            prev.m_libAddrReadPos = m_libAddrReadPos;
            prev.R5 = R5;
            prev.digit = digit;
            prev.REG_ADDR = REG_ADDR;
            prev.RAM_ADDR = RAM_ADDR;
            prev.RAM_OP = RAM_OP;
            prev.dispFilter = m_dispFilter;
        }
    }

    // Capture pre-execution snapshot for the instruction about to run.
    if (tf != TRACE_NONE) {
        tracePreStep(tf, m_pendingOpcode);
    }
}

// ── tracePreStep ──────────────────────────────────────────────────────────────
//
// Called at the top of step() when any trace flag is active.
// Captures instruction identity (pc/opcode) and a pre-execution baseline.
// On the following instruction boundary, beginNextStep() patches the previous
// frame to full post-execution state so all emitted entries share one semantic.

void TMC0501::tracePreStep(uint32_t tf, uint16_t opcode) {
    // Breakpoint check (unchanged)
    if (tf & TRACE_BREAKPOINTS) {
        std::lock_guard<std::mutex> lk(m_traceMutex);
        if (!m_breakpoints.empty()) {
            auto it = std::lower_bound(m_breakpoints.begin(), m_breakpoints.end(), addr);
            if (it != m_breakpoints.end() && *it == addr)
                m_breakpointHit = true;
        }
    }

    // Capture pre-execution snapshot into the ring slot
    CpuFrame& frame = m_frameRing[m_frameHead & kFrameRingMask];

    // Identity (pc and opcode available here; seqno/cycleWeight set post-step)
    frame.pc     = addr;
    frame.opcode = opcode;

    // Light registers (previously deferred to tracePostStep for non-branch)
    if (tf & (TRACE_REGS_LIGHT | TRACE_REGS_FULL)) {
        frame.KR       = KR;
        frame.SR       = SR;
        frame.fA       = fA;
        frame.fB       = fB;
        frame.cpuFlags = flags;
        frame.R5       = R5;
    }

    // Full registers (previously in mid-step block)
    if (tf & TRACE_REGS_FULL) {
        memcpy(frame.A,    A,    16);
        memcpy(frame.B,    B,    16);
        memcpy(frame.C,    C,    16);
        memcpy(frame.D,    D,    16);
        memcpy(frame.E,    E,    16);
        memcpy(frame.SCOM, SCOM, sizeof(SCOM));
        memcpy(frame.Sout, Sout, 16);
        frame.KR = KR; frame.SR = SR; frame.fA = fA; frame.fB = fB;
        frame.EXT = EXT; frame.PREG = PREG ? 1 : 0; frame.flags = flags;
        frame.m_libAddr = m_libAddr; frame.m_libAddrReadPos = m_libAddrReadPos;
        frame.R5 = R5; frame.digit = digit;
        frame.REG_ADDR = REG_ADDR; frame.RAM_ADDR = RAM_ADDR; frame.RAM_OP = RAM_OP;
        frame.dispFilter = m_dispFilter;
    }
}

// ── tracePostStep ─────────────────────────────────────────────────────────────
//
// Called at every return site in step() when tracing is active.
// Finalizes identity fields and advances the ring buffer.
// Full state patching is deferred to beginNextStep() at the next instruction
// boundary, where the previous frame is rewritten to post-execution state.

void TMC0501::tracePostStep(uint32_t tf, int weight) {
    CpuFrame& frame = m_frameRing[m_frameHead & kFrameRingMask];

    // Identity fields only known after execution
    frame.seqno       = m_traceSeqno++;
    frame.digit       = digit;
    frame.cycleWeight = static_cast<uint8_t>(weight);

    m_frameHead++;
}

uint32_t TMC0501::drainCpuFrames(CpuFrame* out, uint32_t max, uint32_t* outLost) {
    std::lock_guard<std::mutex> lk(m_traceMutex);
    if (max == 0) { if (outLost) *outLost = 0; return 0; }

    uint32_t head = m_frameHead;  // single read; emulation thread may advance concurrently

    // Detect ring overflow: if head has advanced beyond diskCursor + ring size,
    // frames were overwritten.
    uint32_t lostCount = 0;
    if (head - m_diskCursor > kFrameRingSize) {
        lostCount = (head - m_diskCursor) - kFrameRingSize;
        m_diskCursor = head - kFrameRingSize;  // jump to oldest frame still in ring
    }

    if (outLost) *outLost = lostCount;

    // Drain from m_diskCursor up to head (exclusive)
    if (m_diskCursor == head || max == 0) return 0;

    uint32_t available = head - m_diskCursor;
    uint32_t count = (available < max) ? available : max;

    for (uint32_t i = 0; i < count; i++) {
        uint32_t idx = (m_diskCursor + i) & kFrameRingMask;
        out[i] = m_frameRing[idx];
    }

    m_diskCursor += count;
    return count;
}

uint32_t TMC0501::readCpuFrames(CpuFrame* out, uint32_t max) const {
    std::lock_guard<std::mutex> lk(m_traceMutex);
    uint32_t head = m_frameHead;
    if (max == 0 || head == 0) return 0;

    // Return the last 'count' frames from the ring buffer (non-consuming).
    // This gives a snapshot of the most recent frames without removing them.
    uint32_t count = (head < max) ? head : max;  // Can't read more than we have

    // Read the last 'count' frames (starting from head - count)
    uint32_t startIdx = (head - count) & kFrameRingMask;
    for (uint32_t i = 0; i < count; i++) {
        uint32_t idx = (startIdx + i) & kFrameRingMask;
        out[i] = m_frameRing[idx];
    }
    return count;
}

// ── printerBufferContent() ────────────────────────────────────────────────────

std::string TMC0501::printerBufferContent() const {
    // Same read order as the print routine: position 19 (leftmost) → 0 (rightmost).
    std::string result;
    for (int i = 19; i >= 0; --i)
        result += m_prnBuf[i];
    return result;
}

// ── snapshotCPU() ─────────────────────────────────────────────────────────────

CpuFrame TMC0501::snapshotCPU() const {
    CpuFrame frame{};
    // Trace identity fields (not meaningful for a standalone snapshot, but initialized to 0)
    frame.seqno = 0;
    frame.pc = addr;
    frame.opcode = rom.read(addr);
    frame.digit = digit;
    frame.cycleWeight = 0;

    // Light registers
    frame.KR = KR;
    frame.SR = SR;
    frame.fA = fA;
    frame.fB = fB;
    frame.cpuFlags = flags;
    frame.R5 = R5;

    // Full registers
    memcpy(frame.A, A, 16);
    memcpy(frame.B, B, 16);
    memcpy(frame.C, C, 16);
    memcpy(frame.D, D, 16);
    memcpy(frame.E, E, 16);
    memcpy(frame.SCOM, SCOM, sizeof(SCOM));
    memcpy(frame.Sout, Sout, 16);

    // Control registers
    frame.EXT = EXT;
    frame.PREG = PREG ? 1 : 0;
    frame.flags = flags;
    frame.m_libAddr = m_libAddr;
    frame.REG_ADDR = REG_ADDR;
    frame.RAM_ADDR = RAM_ADDR;
    frame.RAM_OP = RAM_OP;
    frame.m_libAddrReadPos = 0;  // not meaningful for snapshot
    frame.dispFilter = m_dispFilter;

    return frame;
}

// ── disassemble() ─────────────────────────────────────────────────────────────
//
// Pure function: converts a 13-bit opcode to a mnemonic string.
// Mnemonic names follow tools/mnemonics.tsv in the ti59-research project.
// Regenerate the generated tables with: python3 tools/disasm.py --emit-cpp

// ── Generated tables (update via --emit-cpp) ─────────────────────────────────

// ── Auto-generated by: python3 tools/disasm.py --emit-cpp ──────────────────
// Do not edit by hand; update tools/mnemonics.tsv and re-run.

static const char* const kMaskName[16] = {
    "<flag>", "ALL", "DPT", "DPT1", "DPTC", "LLSD1", "EXP", "EXP1",
    "<keyboard>", "MANT", "<wait>", "MLSD5", "MAEX", "MLSD1", "MMSD1", "MAEX1"
};

static const char* const kFlagFmt[16] = {
    "TST fA[%u]", "SET fA[%u]", "CLR fA[%u]", "TOG fA[%u]",
    "SWAP fA[%u],fB[%u]", "SET KR[%u]", "MOV fA[%u],fB[%u]", "MOV fA[1..4],R5",
    "TST fB[%u]", "SET fB[%u]", "CLR fB[%u]", "TOG fB[%u]",
    "CMP fA[%u],fB[%u]", "CLR KR[%u]", "MOV fB[%u],fA[%u]", "MOV fB[1..4],R5"
};

static const char* const kBranch[2] = { "JNC", "JC" };

static const char* const kPrn[16] = {
    "MOV R5,KR[4..7]", "MOV KR[4..7],R5", "CRD.IN",  "CRD.OUT",
    "CRD.OFF",         "CRD.RD",           "PRT.OUT",  "PRT.FUNC",
    "PRT.CLR",         "PRT.STEP",         "PRT.GO",   "PRT.FEED",
    "CRD.WR",          "",                 "",         "RAM.OP"
};

static const char* const kLib[16] = {
    "LIB.IN", "LIB.PC", "LIB.PC.IN", "LIB.HI",
    "", "", "", "", "", "", "", "", "", "", "", ""
};

static const char* const kMem[2] = { "STOF", "RCLF" };

// ── Fixed ALU tables ──────────────────────────────────────────────────────────

// BCD constant N associated with each field mask (bits 11-8)
static const char* const kN[16] = {
    "?","0","0","1","xC","1","0","1",
    "?","0","?","5","0","1","1","1"
};

// Primary source register per ALU index 0-23
static const char* const kSrc1[24] = {
    "A","A","B","B","C","C","D","D",
    "A","A","B","B","C","C","D","D",
    "A","A","C","C","C","C","A","A"
};
// Secondary source for two-register entries (indices 16-23); empty otherwise
static const char* const kSrc2[24] = {
    "","","","","","","","",
    "","","","","","","","",
    "B","B","B","B","D","D","D","D"
};

// Destination base name; kDstXch is the exchange partner ("" if not an XCH dest)
static const char* const kDstBase[8] = { "A","IO","A","B","C","C","D","A" };
static const char* const kDstXch[8]  = { "","","B","","","D","","E" };

std::string TMC0501::disassemble(uint16_t pc, uint16_t opcode) {
    char buf[64];

    // ── Branch ────────────────────────────────────────────────────────
    if (opcode & 0x1000) {
        uint16_t offs   = (opcode >> 1) & 0x3FFu;
        bool     back   = (opcode & 0x0001) != 0;
        bool     cond   = (opcode & FLG_COND) != 0; // bit 11 of opcode
        uint16_t target = back ? static_cast<uint16_t>(pc - offs) : static_cast<uint16_t>(pc + offs);
        snprintf(buf, sizeof(buf), "%s %04X", kBranch[cond ? 1 : 0], target);
        return buf;
    }

    uint8_t hi = static_cast<uint8_t>((opcode >> 8) & 0x0Fu);

    // ── Flag / control ops (hi nibble = 0) ────────────────────────────
    if (hi == 0x0) {
        unsigned bit = (opcode >> 4) & 0x0Fu;
        unsigned op  = opcode & 0x0Fu;
        // Pass bit twice; SWAP/CMP/MOV templates use %u in both positions
        snprintf(buf, sizeof(buf), kFlagFmt[op], bit, bit);
        return buf;
    }

    // ── Keyboard scan (hi nibble = 8) ─────────────────────────────────
    if (hi == 0x8) {
        bool    single = (opcode & 0x0008) != 0;
        // Reconstruct the 7-bit K-line mask using the same formula as execution:
        // bits 2:0 → K-lines KN/KO/KP
        // bits 10:4 → K-lines KQ/KR/KS/KT (extracted via >> 1)
        uint8_t kmask_raw = static_cast<uint8_t>(
            (opcode & 0x07u) | ((opcode >> 1) & 0x78u));
        uint8_t kmask  = static_cast<uint8_t>(kmask_raw ^ 0x7Fu);
        if (single) {
            snprintf(buf, sizeof(buf), "KEY %u,D%u", kmask, opcode & 7u);
        } else {
            snprintf(buf, sizeof(buf), "KEY_ALL %u", kmask);
        }
        return buf;
    }

    // ── Misc / control (hi nibble = A) ──────────────────────────────────
    if (hi == 0xA) {
        uint8_t loNib = static_cast<uint8_t>(opcode & 0x000Fu);
        uint8_t arg   = static_cast<uint8_t>((opcode >> 4) & 0x000Fu);
        switch (loNib) {
        case 0x0: snprintf(buf, sizeof(buf), "WAIT D%u", arg); return buf;
        case 0x1: return "CLR.IDLE";
        case 0x2: return "CLR fA";
        case 0x3: return "WAIT.BUSY";
        case 0x4: return "INC KR";
        case 0x5: snprintf(buf, sizeof(buf), "TST KR[%u]", arg); return buf;
        case 0x6: {
            // TI-58C uses 0xA76 (MEMWR, bits 7:4=0x7) and 0xA86 (MEMRD, bits 7:4=0x8)
            // Reserve these patterns; TI-59/58 use them for MOV R5 with different arg meanings
            if (arg == 0x7) return "MEMWR";
            if (arg == 0x8) return "MEMRD";
            snprintf(buf, sizeof(buf), "MOV R5,%s[1..4]", (opcode & 0x10) ? "fB" : "fA");
            return buf;
        }
        case 0x7: snprintf(buf, sizeof(buf), "MOV R5,#%u", arg); return buf;
        case 0x8: {
            uint8_t prn = static_cast<uint8_t>((opcode & 0x00F0u) >> 4);
            const char* s = kPrn[prn];
            if (s && *s) return s;
            snprintf(buf, sizeof(buf), "IO_%02X", static_cast<uint8_t>(opcode & 0x00FFu));
            return buf;
        }
        case 0x9: return "SET.IDLE";
        case 0xA: return "CLR fB";
        case 0xB: return "TST.BUSY";
        case 0xC: return "MOV KR,EXT[4..15]";
        case 0xD: return "SWAP KR,SR";
        case 0xE: {
            uint8_t lib = static_cast<uint8_t>((opcode & 0x00F0u) >> 4);
            const char* s = kLib[lib];
            if (s && *s) return s;
            snprintf(buf, sizeof(buf), "LIB_%02X", lib);
            return buf;
        }
        case 0xF: {
            uint8_t m = (opcode & 0x0010u) ? 1 : 0;
            return kMem[m];
        }
        default: break;
        }
        snprintf(buf, sizeof(buf), "MISC %04X", opcode);
        return buf;
    }

    // ── ALU (everything else) — assignment notation ───────────────────
    const char* fld    = kMaskName[hi];
    int         aluIdx = static_cast<int>((opcode >> 3) & 0x1Fu);
    int         dstIdx = opcode & 0x07;
    const char* dstB   = kDstBase[dstIdx];
    const char* dstX   = kDstXch[dstIdx];
    const char* n      = kN[hi];

    // Exchange: kDstXch is non-empty and bits 7:4 == 0xD
    if (*dstX && (opcode & 0xF0u) == 0xD0u) {
        snprintf(buf, sizeof(buf), "%s<>%s %s", dstB, dstX, fld);
        return buf;
    }

    const char* dst = dstB;

    // Special-case entries 24-31 (opcode bits 7:3 = 11xxx)
    uint8_t spOp = static_cast<uint8_t>(opcode & 0x00F8u);
    if (spOp == 0xC0) { snprintf(buf, sizeof(buf), "%s=A+CON %s", dst, fld); return buf; }
    if (spOp == 0xC8) { snprintf(buf, sizeof(buf), "%s=A-CON %s", dst, fld); return buf; }
    if (spOp == 0xD0) { snprintf(buf, sizeof(buf), "%s=LOAD %s",  dst, fld); return buf; }
    if (spOp == 0xD8) { snprintf(buf, sizeof(buf), "%s=-%s %s",   dst, n,   fld); return buf; }
    if (spOp == 0xE0) { snprintf(buf, sizeof(buf), "%s=C+CON %s", dst, fld); return buf; }
    if (spOp == 0xE8) { snprintf(buf, sizeof(buf), "%s=C-CON %s", dst, fld); return buf; }
    if (spOp == 0xF0) { snprintf(buf, sizeof(buf), "%s=R5 %s",    dst, fld); return buf; }
    if (spOp == 0xF8) { snprintf(buf, sizeof(buf), "%s=-R5 %s",   dst, fld); return buf; }

    if (aluIdx >= 24) {
        snprintf(buf, sizeof(buf), "ALU %04X", opcode);
        return buf;
    }

    const char* s1 = kSrc1[aluIdx];
    const char* s2 = kSrc2[aluIdx];

    if (*s2) {
        // Two-register arithmetic (indices 16-23): D=S1±S2 FLD
        bool isAdd = (aluIdx & 1) == 0;
        snprintf(buf, sizeof(buf), "%s=%s%s%s %s", dst, s1, isAdd ? "+" : "-", s2, fld);
    } else if (aluIdx >= 8 && aluIdx <= 15) {
        // Shift (indices 8-15): D=SL/SRx FLD
        bool isShl = (aluIdx & 1) == 0;
        snprintf(buf, sizeof(buf), "%s=S%c%s %s", dst, isShl ? 'L' : 'R', s1, fld);
    } else if (aluIdx == 3 || aluIdx == 7) {
        // Negate: D=-S FLD
        snprintf(buf, sizeof(buf), "%s=-%s %s", dst, s1, fld);
    } else if (aluIdx == 2 || aluIdx == 6) {
        // Move register: D=S FLD
        snprintf(buf, sizeof(buf), "%s=%s %s", dst, s1, fld);
    } else {
        // Immediate ADD/SUB (indices 0,1,4,5): D=S±N FLD
        bool isAdd = (aluIdx == 0 || aluIdx == 4);
        snprintf(buf, sizeof(buf), "%s=%s%s%s %s", dst, s1, isAdd ? "+" : "-", n, fld);
    }
    return buf;
}
