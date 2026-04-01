#include "TMC0501.hpp"
#include "ROM.hpp"
#include "RAM.hpp"
#include <algorithm>
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
        if (PRN_CODE[i][0] == (char)c && PRN_CODE[i][1] == '\0')
            return (uint8_t)i;
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
// 64 entries × 16 BCD digits, physically stored in the TMC0571 SCOM chip.
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
// Entries 16–63: 6-bit keystroke display codes used in programming mode.
//   When reviewing a stored program, the ROM reads these entries to convert
//   internal key codes into LED character patterns showing the key's label
//   (e.g. SIN, STO, RCL, LNX, x², …) on the 12-digit display.

const uint8_t TMC0501::CONSTANT[64][16] = {
  {0xc,0x0,0x0,0x4,0x9,0x9,0x2,0x9,0x0,0x5,0x8,0x5,0x2,0x0,0x3,0x2},
  {0x5,0x4,0x9,0x9,0x5,0x5,0x0,0x8,0x1,0x7,0x4,0x1,0x3,0x9,0x6,0x0},
  {0x5,0x2,0x3,0x4,0x0,0x8,0x9,0x7,0x1,0x0,0x1,0x3,0x5,0x9,0x0,0x0},
  {0x8,0x6,0x1,0x3,0x5,0x8,0x0,0x3,0x3,0x0,0x5,0x9,0x9,0x0,0x0,0x0},
  {0x4,0x8,0x0,0x3,0x3,0x3,0x0,0x0,0x5,0x9,0x9,0x9,0x0,0x0,0x0,0x0},
  {0x3,0x3,0x3,0x0,0x0,0x0,0x5,0x9,0x9,0x9,0x9,0x0,0x0,0x0,0x0,0x0},
  {0x0,0x0,0x0,0x0,0x5,0x9,0x9,0x9,0x9,0x9,0x0,0x0,0x0,0x0,0x0,0x0},
  {0x0,0x0,0x5,0x9,0x9,0x9,0x9,0x9,0x9,0x0,0x0,0x0,0x0,0x0,0x0,0x0},
  {0x0,0x5,0x4,0x7,0x9,0x3,0x3,0x6,0x1,0x8,0x9,0x3,0x5,0x8,0x7,0x0},
  {0x0,0x0,0x2,0x1,0x9,0x4,0x2,0x5,0x6,0x8,0x6,0x6,0x9,0x9,0x0,0x0},
  {0x0,0x7,0x6,0x6,0x8,0x6,0x6,0x6,0x6,0x9,0x9,0x9,0x9,0x0,0x0,0x0},
  {0x7,0x6,0x6,0x6,0x6,0x6,0x9,0x9,0x9,0x9,0x9,0x9,0x0,0x0,0x0,0x0},
  {0x7,0x6,0x6,0x9,0x9,0x9,0x9,0x9,0x9,0x9,0x9,0x0,0x0,0x0,0x0,0x0},
  {0xc,0x1,0x0,0x5,0x9,0x7,0x6,0x2,0x3,0x6,0x9,0x7,0x0,0x7,0x5,0x1},
  {0xc,0x0,0x0,0x0,0x9,0x5,0x3,0x5,0x6,0x2,0x9,0x5,0x1,0x4,0x1,0x3},
  {0xc,0x1,0x0,0x8,0x0,0x3,0x1,0x5,0x9,0x7,0x7,0x5,0x9,0x2,0x7,0x5},
  {0x2,0x8,0x8,0x0,0x3,0x5,0x3,0x5,0x3,0x4,0x6,0x0,0x5,0x7,0x3,0x4},
  {0x4,0x0,0x5,0x6,0x3,0x4,0x1,0x0,0x5,0x5,0x3,0x4,0x3,0x0,0x4,0x5},
  {0x5,0x5,0x3,0x5,0x3,0x4,0x5,0x0,0x5,0x7,0x3,0x4,0x4,0x0,0x3,0x3},
  {0x5,0x5,0x3,0x4,0x3,0x0,0x4,0x5,0x4,0x5,0x3,0x5,0x3,0x5,0x4,0x2},
  {0x5,0x6,0x2,0x3,0x3,0x4,0x4,0x0,0x4,0x9,0x5,0x8,0x3,0x4,0x1,0x0},
  {0x4,0x5,0x5,0x5,0x3,0x4,0x3,0x0,0x4,0x5,0x2,0x8,0x0,0x2,0x3,0x5},
  {0x3,0x5,0x4,0x9,0x5,0x8,0x2,0x8,0x8,0x1,0x4,0x5,0x5,0x5,0x2,0x3},
  {0x4,0x5,0x2,0x9,0x3,0x5,0x2,0x3,0x5,0x6,0x2,0x8,0x8,0x1,0x5,0x8},
  {0x2,0x3,0x4,0x5,0x2,0x9,0x3,0x5,0x3,0x4,0x4,0x0,0x5,0x5,0x3,0x4},
  {0x3,0x0,0x4,0x5,0x2,0x3,0x3,0x5,0x3,0x4,0x1,0x0,0x5,0x5,0x3,0x4},
  {0x3,0x0,0x4,0x5,0x2,0x8,0x0,0x2,0x3,0x3,0x3,0x5,0x4,0x9,0x5,0x8},
  {0x3,0x4,0x2,0x0,0x5,0x5,0x3,0x4,0x3,0x0,0x4,0x5,0x2,0x3,0x3,0x3},
  {0x3,0x5,0x4,0x9,0x5,0x8,0x3,0x4,0x5,0x0,0x5,0x5,0x3,0x4,0x3,0x0},
  {0x4,0x5,0x2,0x3,0x2,0x9,0x3,0x5,0x3,0x5,0x3,0x4,0x5,0x0,0x5,0x7},
  {0x3,0x4,0x4,0x0,0x3,0x3,0x5,0x5,0x3,0x4,0x3,0x0,0x4,0x5,0x5,0x5},
  {0x3,0x5,0x3,0x4,0x3,0x0,0x5,0x7,0x1,0x0,0x4,0x5,0x2,0x8,0x8,0x0},
  {0x4,0x5,0x4,0x3,0x2,0x3,0x3,0x5,0x3,0x5,0x3,0x4,0x2,0x0,0x5,0x7},
  {0x3,0x4,0x1,0x0,0x3,0x3,0x5,0x5,0x3,0x4,0x3,0x0,0x4,0x5,0x5,0x5},
  {0x2,0x8,0x8,0x1,0x4,0x5,0x4,0x3,0x2,0x9,0x3,0x5,0x3,0x5,0x3,0x4},
  {0x6,0x0,0x5,0x7,0x3,0x4,0x4,0x0,0x5,0x6,0x3,0x4,0x1,0x0,0x5,0x5},
  {0x3,0x4,0x3,0x0,0x4,0x5,0x5,0x5,0x3,0x5,0x3,0x5,0x3,0x4,0x5,0x0},
  {0x5,0x7,0x3,0x4,0x4,0x0,0x3,0x3,0x5,0x5,0x3,0x4,0x3,0x0,0x4,0x5},
  {0x5,0x6,0x3,0x5,0x3,0x4,0x2,0x0,0x5,0x7,0x3,0x4,0x1,0x0,0x3,0x3},
  {0x5,0x5,0x3,0x4,0x3,0x0,0x4,0x5,0x4,0x5,0x4,0x3,0x4,0x5,0x2,0x9},
  {0x4,0x4,0x1,0x0,0x2,0x8,0x8,0x0,0x3,0x3,0x4,0x4,0x2,0x0,0x2,0x3},
  {0x4,0x4,0x4,0x0,0x2,0x8,0x8,0x4,0x2,0x8,0x7,0x0,0x3,0x3,0x4,0x4},
  {0x5,0x0,0x1,0x0,0x1,0x6,0x2,0x0,0x6,0x3,0x4,0x9,0x4,0x4,0x1,0x0},
  {0x2,0x8,0x8,0x0,0x3,0x3,0x4,0x9,0x4,0x4,0x2,0x0,0x2,0x3,0x2,0x2},
  {0x4,0x4,0x4,0x0,0x2,0x8,0x8,0x4,0x2,0x8,0x7,0x0,0x3,0x3,0x4,0x9},
  {0x4,0x4,0x5,0x0,0x1,0x0,0x4,0x9,0x4,0x4,0x3,0x0,0x2,0x8,0x7,0x3},
  {0x2,0x8,0x8,0x1,0x4,0x4,0x6,0x0,0x2,0x8,0x7,0x1,0x2,0x3,0x3,0x4},
  {0x3,0x0,0x2,0x9,0x3,0x5,0x2,0x8,0x8,0x0,0x3,0x3,0x5,0x8,0x2,0x3},
  {0x2,0x8,0x7,0x0,0x3,0x3,0x4,0x5,0x4,0x3,0x2,0x3,0x3,0x5,0x3,0x5},
  {0x2,0x8,0x7,0x1,0x5,0x5,0x0,0x5,0x4,0x5,0x2,0x2,0x9,0x3,0x5,0x8},
  {0x3,0x5,0x2,0x8,0x8,0x1,0x5,0x5,0x2,0x8,0x7,0x1,0x4,0x5,0x2,0x2},
  {0x0,0x3,0x4,0x5,0x4,0x2,0x2,0x9,0x3,0x5,0x2,0x8,0x8,0x0,0x9,0x3},
  {0x5,0x6,0x2,0x3,0x2,0x8,0x7,0x0,0x4,0x5,0x2,0x3,0x3,0x5,0x2,0x8},
  {0x8,0x1,0x8,0x3,0x5,0x6,0x2,0x8,0x7,0x1,0x4,0x5,0x2,0x9,0x3,0x5},
  {0x3,0x5,0x3,0x5,0x2,0x8,0x8,0x0,0x9,0x5,0x5,0x6,0x6,0x0,0x0,0x0},
  {0x5,0x8,0x3,0x5,0x2,0x8,0x8,0x1,0x2,0x2,0x9,0x5,0x5,0x6,0x1,0x0},
  {0x0,0x0,0x0,0x0,0x4,0x5,0x2,0x8,0x8,0x0,0x9,0x5,0x4,0x5,0x5,0x6},
  {0x3,0x9,0x6,0x0,0x5,0x8,0x2,0x8,0x8,0x1,0x2,0x2,0x9,0x5,0x4,0x5},
  {0x5,0x5,0x3,0x0,0x6,0x0,0x4,0x5,0x2,0x9,0x3,0x5,0x3,0x5,0x2,0x8},
  {0x8,0x0,0x9,0x5,0x5,0x8,0x2,0x8,0x8,0x1,0x2,0x2,0x9,0x5,0x5,0x6},
  {0x3,0x9,0x6,0x0,0x4,0x5,0x5,0x6,0x1,0x0,0x0,0x0,0x0,0x0,0x4,0x5},
  {0x2,0x8,0x8,0x0,0x3,0x5,0x3,0x5,0x9,0x5,0x5,0x8,0x2,0x8,0x8,0x1},
  {0x2,0x2,0x9,0x5,0x5,0x6,0x3,0x9,0x6,0x0,0x4,0x5,0x5,0x6,0x3,0x9},
  {0x0,0x0,0x1,0x0,0x4,0x5,0x2,0x9,0x0,0x0,0x0,0x0,0x0,0x0,0x0,0x0},
};

// ── Constructor / reset ───────────────────────────────────────────────────────

TMC0501::TMC0501(ROM& r, RAM& m) : rom(r), ram(m) {
    for (auto& s : m_prnBuf) s = " ";
}

void TMC0501::reset() {
    memset(A, 0, sizeof(A));  memset(B, 0, sizeof(B));
    memset(C, 0, sizeof(C));  memset(D, 0, sizeof(D));  memset(E, 0, sizeof(E));
    memset(SCOM, 0, sizeof(SCOM));
    memset(Sout, 0, sizeof(Sout));
    memset(key,  0, sizeof(key));
    KR = SR = fA = fB = EXT = PREG = m_libAddr = 0;
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
    if (count > 5000) count = 5000;
    memcpy(m_libData, data, count);
}

// ── Key matrix ────────────────────────────────────────────────────────────────

void TMC0501::pressKey(int row, int col) {
    if (col >= 0 && col < 16 && row >= 0 && row < 7)
        key[col] |= (uint8_t)(1u << row);
}

void TMC0501::releaseKey(int row, int col) {
    if (col >= 0 && col < 16 && row >= 0 && row < 7)
        key[col] &= (uint8_t)~(1u << row);
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
    // Pin SH drives the "C" (calculating) annunciator with two distinct modes:
    //   IDLE mode:    SH = fA[14]  — only bit 14 controls C
    //   Compute mode: SH = (fA != 0) — C is on whenever any fA bit is set
    // During a long calculation fA carries working flags and is rarely zero,
    // so C glows most of the time with natural variation.  During a brief
    // keypress fA may be zero for most of the short computation → barely visible.
    const bool cOn = (flags & FLG_IDLE) ? ((fA >> 14) & 1) : (fA != 0);
    if (m_dispFilter >= 3) {
        DisplaySnapshot blank{};
        for (int i=0; i<12; ++i) blank.ctrl[i] = 7;
        blank.calcIndicator = cOn;
        return blank;
    }
    DisplaySnapshot s = m_display;
    s.calcIndicator = cOn;
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
        if (i == (int)m.start) { shl = carry = 0; }

        uint8_t sum = 0, shr = 0;
        if (srcY)              sum  = srcY[i];
        if (i == (int)m.cpos) sum |= m.cval;
        shr  = sum;
        sum  = (uint8_t)(sum + carry);
        if (op >= ALU_SUB)     sum  = (uint8_t)(-sum);
        if (srcX)            { sum  = (uint8_t)(sum + srcX[i]); shr |= srcX[i]; }

        // Real hardware drives Sout to 0 outside the active field.  Naively
        // propagating the carry chain into all 16 positions (the "obvious"
        // implementation) would leave source-register values in the out-of-mask
        // digits.  That stale data then gets written into SCOM via FLG_STORE,
        // corrupting registers used later as print-buffer indices and producing
        // spurious '8' characters in printer output (PRN_CODE[9] = '8').
        Sout[i] = (i >= (int)m.start && i <= (int)m.end) ? (sum & 0x0F) : 0;

        // BCD carry: digit 0 wraps at 16 (hex); digits 1–15 wrap at 10 (decimal)
        if (i == 0) {
            if ((carry = (sum >= 0x10 ? 1u : 0u))) sum &= 0x0Fu;
        } else {
            if ((carry = (sum >= 10 ? 1u : 0u))) {
                if (op < ALU_SUB) sum = (uint8_t)(sum - 10);
                else              sum = (uint8_t)(sum + 10);
            }
        }

        if (i >= (int)m.start && i <= (int)m.end) {
            if (i == (int)m.start) R5 = sum;  // R5 always captures the start digit
            if (dst) {
                if      (op == ALU_SHL)                    dst[i]   = shl;
                else if (op == ALU_SHR) {
                    if (i > (int)m.start)                  dst[i-1] = shr;
                    if (i == (int)m.end)                   dst[i]   = 0;
                } else                                     dst[i]   = sum;
                shl = sum;
            }
            // Carry out of the field clears COND (signals overflow to branches)
            if (i == (int)m.end && !(op & 0x1) && carry)
                flags &= ~FLG_COND;
        }
    }
}

void TMC0501::xch(uint8_t* a, uint8_t* b, const MaskInfo& m) {
    if (m.start == 0xFF) return;
    for (int i = (int)m.start; i <= (int)m.end; ++i) {
        uint8_t t = a[i]; a[i] = b[i]; b[i] = t;
    }
}

// ── Main instruction dispatch ─────────────────────────────────────────────────

int TMC0501::step() {
    // ── PREG computed-jump redirect ───────────────────────────────────
    // SET KR[1] deposits a rotated KR value into PREG on the previous cycle.
    // On the next call we redirect the PC without fetching a new opcode.
    // Returns 0 so this pseudo-cycle doesn't count toward the speed budget.
    if (PREG & 0x1) {
        addr = PREG >> 3;
        PREG = 0;
        return 0;
    }

    // ── Trace gate ────────────────────────────────────────────────────
    // One relaxed atomic load per step; falls through at zero cost when disabled.
    const uint32_t tf = m_traceFlags.load(std::memory_order_relaxed);
    uint8_t snapIdx = 0xFF;

    // ── Printer busy countdown ────────────────────────────────────────
    if (m_prnBusyCycles > 0) {
        if (--m_prnBusyCycles == 0) flags &= ~FLG_BUSY;
    }

    uint16_t opcode = rom.read(addr);

    // Capture pre-execution state for the trace ring.
    if (tf != TRACE_NONE) [[unlikely]] { tracePreStep(tf, opcode, snapIdx); }

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
            if (m_pendingDisplayUpdate) {
                m_pendingDisplayUpdate = false;
                std::lock_guard<std::mutex> lock(m_displayMutex);
                for (int i = 0; i < 12; ++i) {
                    m_display.digits[i] = A[i + 2] & 0x0F;
                    m_display.ctrl[i]   = B[i + 2] & 0x0F;
                }
                m_display.dpPos = R5 & 0x0F;
            }
        } else if (m_dispFilter < 3) {
            m_dispFilter++;
        }
    }

    // ── Clear HOLD ────────────────────────────────────────────────────
    // HOLD is re-asserted each cycle by WAIT Dn / KEY scan-all if the
    // condition isn't yet satisfied; clearing it here is the default.
    flags &= ~FLG_HOLD;

    // ── PREG latch (deferred PC redirect) ────────────────────────────
    // When KR bit 1 is set (by SET KR[1]), the current KR is rotated
    // right by 1 and stored in PREG.  The redirect fires on the next step().
    if (KR & 0x2) {
        PREG = (uint16_t)((KR >> 1) | (KR << 15));
        KR  &= ~(uint16_t)0x2;
    }

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
            if (opcode & 0x0001) addr = (uint16_t)(addr - offs);
            else                 addr = (uint16_t)(addr + offs);
        } else {
            addr++;
        }
        int w = (flags & FLG_IDLE) ? 4 : 1;
        if (tf != TRACE_NONE) [[unlikely]] { tracePostStep(tf, snapIdx, w); }
        return w;
    }

    // ── COND auto-restore after a branch sequence ─────────────────────
    // After a run of branch instructions, the first non-branch instruction
    // restores COND to 1 (true) so the next TST/CMP starts from a clean slate.
    if (flags & FLG_JUMP) {
        flags &= ~FLG_JUMP;
        flags |=  FLG_COND;
    }

    switch (opcode & 0x0F00) {

    // ── Flag operations (hi nibble = 0x0) ────────────────────────────
    // Operate on individual bits of the ROM-visible flag registers fA and fB,
    // or on individual bits of KR.  The bit index is encoded in opcode bits 7:4.
    case 0x0000: {
        unsigned bit  = (opcode >> 4) & 0x000Fu;
        uint16_t mask = (uint16_t)(1u << bit);
        switch (opcode & 0x000Fu) {
        case 0x0: if (fA & mask) flags &= ~FLG_COND; break;  // TST fA[b]  — clear COND if bit set
        case 0x1: fA |=  mask;                        break;  // SET fA[b]
        case 0x2: fA &= ~mask;                        break;  // CLR fA[b]
        case 0x3: fA ^=  mask;                        break;  // INV fA[b]
        case 0x4: if ((fA ^ fB) & mask) { fA ^= mask; fB ^= mask; } break; // XCH fA[b],fB[b]
        case 0x5: KR |= mask; break;  // SET KR[b]
        case 0x6: if ((fA ^ fB) & mask) fA ^= mask;  break;  // MOV fA[b],fB[b]  (copy fB→fA if different)
        case 0x7: fA = (uint16_t)((fA & ~0x001Eu) | ((R5 & 0x0Fu) << 1)); break; // MOV fA[1..4],R5
        case 0x8: if (fB & mask) flags &= ~FLG_COND; break;  // TST fB[b]
        case 0x9: fB |=  mask;                        break;  // SET fB[b]
        case 0xA: fB &= ~mask;                        break;  // CLR fB[b]
        case 0xB: fB ^=  mask;                        break;  // INV fB[b]
        case 0xC: if (!((fA ^ fB) & mask)) flags &= ~FLG_COND; break; // CMP fA[b],fB[b] — clear COND if equal
        case 0xD: KR &= ~mask;                        break;  // CLR KR[b]
        case 0xE: if ((fA ^ fB) & mask) fB ^= mask;  break;  // MOV fB[b],fA[b]  (copy fA→fB if different)
        case 0xF: fB = (uint16_t)((fB & ~0x001Eu) | ((R5 & 0x0Fu) << 1)); break; // MOV fB[1..4],R5
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
        uint8_t kmask = (uint8_t)(
            (((opcode & 0x07u) | ((opcode >> 1) & 0x78u)) ^ 0x7Fu) & key[digit]);
        // Reject simultaneous multi-key presses (hardware limitation)
        if (kmask & (kmask - 1u)) kmask = 0;

        if (!(opcode & 0x0008u)) {
            // Scan-all mode: hold and scan until digit 0 or key found
            if (key[digit] & kmask) {
                uint8_t bit = 0, m2 = kmask;
                while (!(m2 & 1)) { bit++; m2 >>= 1; }
                flags &= ~FLG_COND;
                KR = (uint16_t)((digit << 4) | ((bit << 8) & 0x0700u));
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

        case 0x1: flags &= ~FLG_IDLE; break;  // CLR IDL — exit idle/display mode; resume full speed

        case 0x2: fA = 0; break;  // CLR fA — clear all 16 fA flag bits at once

        case 0x3: /* WAIT BUSY — undocumented; treated as no-op */ break;

        case 0x4:  // INC KR — step the SCOM constant-table pointer
            // KR bits 7:4 index the current constant entry; incrementing
            // them walks through the 64-entry constant table.  When bits
            // 15:4 all reach zero, bit 0 toggles as an overflow indicator.
            KR = (uint16_t)(KR + 0x0010u);
            if (!(KR & 0xFFF0u)) KR ^= 0x0001u;
            break;

        case 0x5:  // TST KR[a] — clear COND if KR bit is set
            if (KR & (1u << ((opcode >> 4) & 0x000Fu))) flags &= ~FLG_COND;
            break;

        case 0x6:  // MOV R5,fA[1..4] or fB[1..4] — copy flag bits into R5
            R5 = (uint8_t)(((opcode & 0x0010u) ? fB : fA) >> 1) & 0x0Fu;
            break;

        case 0x7:  // MOV R5,#n — load 4-bit immediate into R5
            R5 = (uint8_t)((opcode >> 4) & 0x000Fu);
            break;

        case 0x8:  // Peripheral I/O (card reader, printer, RAM, library)
            switch (opcode & 0x00F0u) {
            case 0x00: R5 = (uint8_t)((KR >> 4) & 0x000Fu); break;  // MOV R5,KR[4..7]
            case 0x10: KR = (uint16_t)((KR & ~0x00F0u) | ((uint16_t)R5 << 4)); break; // MOV KR[4..7],R5
            case 0x20: // IN CRD — card read: fetch next nibble into EXT bits 4-7
                if (m_cardPresent && m_cardMode == 1 && m_cardPtr < 246) {
                    EXT = (uint16_t)m_cardBankBuffer[m_cardPtr++] << 4;
                } else {
                    EXT = 0;
                }
                flags |= FLG_EXT_VALID;
                break;
            case 0x30: // OUT CRD — card write: capture KR bits 4-11 (both nibbles) into bank buffer
                if (m_cardPresent && m_cardMode == 2 && m_cardPtr < 246) {
                    m_cardBankBuffer[m_cardPtr++] = (uint8_t)((KR >> 4) & 0xFFu);
                }
                break;
            case 0x40: // CRD_OFF — finalize bank operation; card exits reader
                if (m_cardMode == 2) {
                    // Flush bank buffer back to full card data based on bank index in byte 2.
                    // nibble index 2 -> byte 2 in our 1-byte-per-nibble mapping.
                    int bank = (m_cardBankBuffer[2] & 0x0Fu) / 3;
                    if (bank >= 0 && bank < 4) {
                        memcpy(m_cardFullData + bank * 246, m_cardBankBuffer, 246);
                        m_lastWrittenBank = bank;
                    }
                } else if (m_cardMode == 1) {
                    // Card banks 0–3 are encoded as nibble values 0,3,6,9; advance by 3 per read pass.
                    m_cardBankBuffer[2] = (uint8_t)((m_cardBankBuffer[2] + 3) & 0x0F);
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
                    int bank = (m_cardBankBuffer[2] & 0x0Fu) / 3;
                    if (bank >= 0 && bank < 4) {
                        memcpy(m_cardBankBuffer, m_cardFullData + bank * 246, 246);
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
                    uint8_t code = (uint8_t)((KR >> 4) & 0x3Fu);
                    uint8_t slot = m_prnPtr % 20;
                    m_prnBuf[slot]     = PRN_CODE[code];
                    m_prnCodeBuf[slot] = code;
                    m_prnPtr = slot + 1;
                }
                break;
            }
            case 0x70: { // OUT PRT_FUNC — load 3-char function mnemonic (stored reversed)
                if (m_prnReady) {
                    uint8_t code = (uint8_t)((KR >> 4) & 0x7Fu);
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
                    m_prnBusyCycles = 2133;  // (150ms * 455kHz) / 2 / 16 / 1000
                }
                break;
            }
            case 0xB0: // PRT_FEED — advance paper (blank line)
                // ADV button sends PRT_FEED continuously while held; BUSY gates the rate.
                {
                    std::lock_guard<std::mutex> lk(m_prnMutex);
                    m_prnLines.push_back(std::string{});
                    m_prnCodeLines.push_back(std::array<uint8_t,20>{});  // zero-filled
                }
                flags |= FLG_BUSY;
                m_prnBusyCycles = 2133;  // (150ms * 455kHz) / 2 / 16 / 1000
                break;
            case 0xF0: flags |= FLG_RAM_OP; break; // RAM_OP — next Sout is a RAM opcode
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
            KR = (uint16_t)((KR & 0x000Fu) | EXT);
            break;

        case 0xD:  // XCH KR,SR — swap KR and SR (primary subroutine return mechanism)
            { uint16_t t = KR; KR = SR; SR = t; }
            break;

        case 0xE:  // Library module operations
            switch (opcode & 0x00F0u) {
            case 0x00: // IN LIB — fetch one byte from library; advance pointer
                EXT = (uint16_t)m_libData[m_libAddr++] << 4;
                flags |= FLG_EXT_VALID;
                m_libAddr %= 5000;
                break;
            case 0x10: // OUT LIB_PC — load library pointer tens digit from KR[7:4]
                // The library address is encoded in BCD-like decimal: the ROM
                // shifts it one decimal digit at a time using OUT LIB_PC / IN LIB_PC
                // pairs.  OUT LIB_PC replaces the thousands+hundreds group:
                //   new_addr = (old_addr % 10)   ← preserve units digit already there
                //            + digit * 1000       ← inject new thousands digit
                // The ROM calls this instruction twice (tens then thousands) to load
                // a full 4-digit address.
                m_libAddr = (uint16_t)((m_libAddr / 10) + ((KR >> 4 & 0xFu) * 1000));
                break;
            case 0x20: // IN LIB_PC — read library pointer ones digit into EXT
                // Pops the lowest decimal digit of m_libAddr into EXT, shifting
                // the address right by one decimal place.  The ROM uses this to
                // read back the address one digit at a time for display or storage.
                EXT = (uint16_t)(m_libAddr % 10) << 4;
                flags |= FLG_EXT_VALID;
                m_libAddr /= 10;
                break;
            case 0x30: // IN LIB_HIGH — fetch high nibble of current byte (no advance)
                EXT = (uint16_t)(m_libData[m_libAddr] & 0xF0u);
                flags |= FLG_EXT_VALID;
                break;
            }
            break;

        case 0xF:  // STO / RCL — SCOM register store or recall
            // The register address was set by the preceding ALU IO operation
            // (Sout[0] encodes the SCOM register number 0–15).
            switch (opcode & 0x00F0u) {
            case 0x00: flags |= FLG_STORE;  REG_ADDR = Sout[0] & 0x0Fu; break; // STO
            case 0x10: flags |= FLG_RECALL; REG_ADDR = Sout[0] & 0x0Fu; break; // RCL
            }
            break;
        }
        break;

    // ── ALU operations ────────────────────────────────────────────────
    default:
        execALU(opcode);
        break;
    }

    if (!(flags & FLG_HOLD)) {
        addr++;
    }
    int w = (flags & FLG_IDLE) ? 4 : 1;
    if (tf != TRACE_NONE) [[unlikely]] { tracePostStep(tf, snapIdx, w); }
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
    int aluOp;
    int aluIdx = (opcode >> 3) & 0x1Fu;
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
    }

    // SCOM constant index — built from KR bits 10:4 (7 bits total).
    // The unusual bit arrangement mirrors the hardware's KR field layout.
    int constIdx = (int)(((KR >> 5) & 0x78u) | ((KR >> 4) & 0x07u));
    if (constIdx >= 64) constIdx = 0;
    const uint8_t* constPtr = CONSTANT[constIdx];

    // Special-case ALU operations (indices 24–31, opcode bits 7:3 = 0x18–0x1F)
    switch (opcode & 0x00F8u) {
    case 0x00C0: alu(dst, A, constPtr,       m, ALU_ADD); break; // ADD dst, A, const
    case 0x00C8: alu(dst, A, constPtr,       m, ALU_SUB); break; // SUB dst, A, const
    case 0x00D0:  // MOV dst, #0  — may be overridden by a pending recall
        if (flags & FLG_RECALL) {
            // SCOM recall: deliver SCOM[REG_ADDR] as srcY (set up by preceding RCL)
            flags &= ~FLG_RECALL;
            alu(dst, nullptr, SCOM[REG_ADDR], m, ALU_ADD);
        } else if ((flags & FLG_RAM_READ) && RAM_ADDR < ram.size()) {
            // RAM read: deliver RAM[RAM_ADDR] as srcY (set up by preceding RAM_OP)
            flags &= ~FLG_RAM_READ;
            alu(dst, nullptr, ram.readReg(RAM_ADDR), m, ALU_ADD);
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
            for (int i = (int)m.start + 1; i <= (int)m.end; ++i) dst[i] = 0;
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
    }

    // ── Deferred memory write-back ────────────────────────────────────
    // SCOM store: write Sout (the IO bus) into the SCOM register selected
    // by the preceding STO instruction.
    if (flags & FLG_STORE) {
        flags &= ~FLG_STORE;
        memcpy(SCOM[REG_ADDR], Sout, 16);
    }

    // RAM operation decode: Sout[0] = opcode (read/write/clear),
    // Sout[3]*10 + Sout[2] = register address.  Sets up FLG_RAM_READ or
    // FLG_RAM_WRITE for the following instruction.
    if (flags & FLG_RAM_OP) {
        flags &= ~FLG_RAM_OP;
        RAM_OP   = Sout[0] & 0x0Fu;
        RAM_ADDR = (uint8_t)(Sout[3] * 10u + Sout[2]);
        if (RAM_ADDR < ram.size()) {
            if      (RAM_OP == 2) ram.clearReg(RAM_ADDR, 1);
            else if (RAM_OP == 4) ram.clearReg(RAM_ADDR, 10);
            else if (RAM_OP == 1) flags |= FLG_RAM_WRITE;
            else if (RAM_OP == 0) flags |= FLG_RAM_READ;
        }
    } else if (flags & FLG_RAM_WRITE) {
        flags &= ~FLG_RAM_WRITE;
        if (RAM_ADDR < ram.size())
            ram.writeReg(RAM_ADDR, Sout);
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
    const uint8_t* bank = m_cardFullData + m_lastWrittenBank * 246;
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

// ── tracePreStep ──────────────────────────────────────────────────────────────
//
// Called at the top of step() when any trace flag is active.
// Saves pc, opcode, and digit for use by tracePostStep.
// If TRACE_REGS_FULL: writes a CPUSnapshot to the snap ring and returns its
// index in snapIdx; otherwise snapIdx remains 0xFF.

void TMC0501::tracePreStep(uint32_t tf, uint16_t opcode, uint8_t& snapIdx) {
    m_tracePC     = addr;
    m_traceOpcode = opcode;

    if (tf & TRACE_REGS_FULL) {
        uint32_t idx = m_traceHead & kTraceRingMask;
        CPUSnapshot& s = m_snapRing[idx];
        memcpy(s.A,    A,    16);
        memcpy(s.B,    B,    16);
        memcpy(s.C,    C,    16);
        memcpy(s.D,    D,    16);
        memcpy(s.E,    E,    16);
        memcpy(s.SCOM, SCOM, 16 * 16);
        memcpy(s.Sout, Sout, 16);
        s.KR = KR; s.SR = SR; s.fA = fA; s.fB = fB;
        s.EXT = EXT; s.PREG = PREG; s.flags = flags;
        s.R5 = R5; s.digit = digit;
        s.REG_ADDR = REG_ADDR; s.RAM_ADDR = RAM_ADDR; s.RAM_OP = RAM_OP;
        snapIdx = (uint8_t)(idx & 0xFF);
    }

    if (tf & TRACE_BREAKPOINTS) {
        std::lock_guard<std::mutex> lk(m_traceMutex);
        if (!m_breakpoints.empty()) {
            auto it = std::lower_bound(m_breakpoints.begin(), m_breakpoints.end(), addr);
            if (it != m_breakpoints.end() && *it == addr)
                m_breakpointHit = true;
        }
    }
}

// ── tracePostStep ─────────────────────────────────────────────────────────────
//
// Called at every return site in step() when tracing is active.
// Writes a TraceEvent to the ring.  Ring overflow: head advances unconditionally;
// seqno gaps in the output signal dropped events to the caller.

void TMC0501::tracePostStep(uint32_t tf, uint8_t snapIdx, int weight) {
    uint32_t idx = m_traceHead & kTraceRingMask;
    TraceEvent& ev = m_traceRing[idx];

    ev.pc          = m_tracePC;
    ev.opcode      = m_traceOpcode;
    ev.digit       = digit;  // post-decrement: matches digit seen during execution
    ev.cycleWeight = (uint8_t)weight;
    ev.seqno       = m_traceSeqno++;
    ev.snapshotIndex = snapIdx;

    if (tf & TRACE_REGS_LIGHT) {
        ev.KR       = KR;
        ev.SR       = SR;
        ev.fA       = fA;
        ev.fB       = fB;
        ev.cpuFlags = flags;
        ev.R5       = R5;
    } else {
        ev.KR = ev.SR = ev.fA = ev.fB = ev.cpuFlags = 0;
        ev.R5 = 0;
    }

    m_traceHead++;
}

uint32_t TMC0501::drainTraceEvents(TraceEvent* out, CPUSnapshot* outSnaps, uint32_t max) {
    std::lock_guard<std::mutex> lk(m_traceMutex);
    uint32_t head = m_traceHead;  // single read; emulation thread may advance concurrently
    if (head == m_traceTail || max == 0) return 0;

    uint32_t count = 0;
    while (m_traceTail != head && count < max) {
        uint32_t idx = m_traceTail & kTraceRingMask;
        out[count] = m_traceRing[idx];
        if (outSnaps && out[count].snapshotIndex != 0xFF)
            outSnaps[count] = m_snapRing[idx];
        m_traceTail++;
        count++;
    }
    return count;
}

bool TMC0501::peekLastEvent(TraceEvent& out, CPUSnapshot* outSnap) const {
    std::lock_guard<std::mutex> lk(m_traceMutex);
    if (m_traceHead == m_traceTail) return false;
    uint32_t idx = (m_traceHead - 1) & kTraceRingMask;
    out = m_traceRing[idx];
    if (outSnap && out.snapshotIndex != 0xFF)
        *outSnap = m_snapRing[idx];
    return true;
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

CPUSnapshot TMC0501::snapshotCPU() const {
    CPUSnapshot s{};
    memcpy(s.A, A, 16); memcpy(s.B, B, 16); memcpy(s.C, C, 16);
    memcpy(s.D, D, 16); memcpy(s.E, E, 16);
    memcpy(s.SCOM, SCOM, 16 * 16);
    memcpy(s.Sout, Sout, 16);
    s.KR = KR; s.SR = SR; s.fA = fA; s.fB = fB;
    s.EXT = EXT; s.PREG = PREG; s.flags = flags;
    s.R5 = R5; s.digit = digit;
    s.REG_ADDR = REG_ADDR; s.RAM_ADDR = RAM_ADDR; s.RAM_OP = RAM_OP;
    return s;
}

// ── disassemble() ─────────────────────────────────────────────────────────────
//
// Pure function: converts a 13-bit opcode to a mnemonic string.
// Mnemonic conventions follow the TMC0501 instruction set encoding.

static const char* const kMaskName[16] = {
    "INV","ALL","DPT","DPT,#1","DPT,#C","LLSD,#1",
    "EXP","EXP,#1","INV","MANT","INV","MLSD,#5",
    "MAEX","MAEX/MLSD,#1","MMSD,#1","MAEX,#1"
};

// ALU source-pair names: index → "srcX,srcY" or "srcX" or "srcY"
static const char* const kALUSrc[24] = {
    "A","A","B","B","C","C","D","D",
    "A","A","B","B","C","C","D","D",
    "A,B","A,B","C,B","C,B","C,D","C,D","A,D","A,D"
};
static const char* const kALUOp[24] = {
    "ADD","SUB","ADD","SUB","ADD","SUB","ADD","SUB",
    "SHL","SHR","SHL","SHR","SHL","SHR","SHL","SHR",
    "ADD","SUB","ADD","SUB","ADD","SUB","ADD","SUB"
};
static const char* const kDst[8] = { "A","IO","AxB","B","C","CxD","D","AxE" };

std::string TMC0501::disassemble(uint16_t pc, uint16_t opcode) {
    char buf[64];

    // ── Branch ────────────────────────────────────────────────────────
    if (opcode & 0x1000) {
        uint16_t offs  = (opcode >> 1) & 0x3FFu;
        bool     back  = (opcode & 0x0001) != 0;
        bool     cond  = (opcode & FLG_COND) != 0; // bit 11 of opcode
        uint16_t target = back ? (uint16_t)(pc - offs) : (uint16_t)(pc + offs);
        snprintf(buf, sizeof(buf), "%s %04X",
                 cond ? "BR_C" : "BR_NC", target);
        return buf;
    }

    uint8_t hi = (uint8_t)((opcode >> 8) & 0x0Fu);

    // ── Flag / control ops (hi nibble = 0) ────────────────────────────
    if (hi == 0x0) {
        static const char* const fOp[16] = {
            "TST","SET","CLR","INV","XCH","SET_KR","MOV","MOV_R5",
            "TST","SET","CLR","INV","CMP","CLR_KR","MOV","MOV_R5"
        };
        static const char* const fReg[16] = {
            "fA","fA","fA","fA","fA/fB","KR","fA<-fB","fA[1:4]",
            "fB","fB","fB","fB","fA,fB","KR","fB<-fA","fB[1:4]"
        };
        unsigned bit = (opcode >> 4) & 0x0Fu;
        unsigned op  = opcode & 0x0Fu;
        snprintf(buf, sizeof(buf), "%s %s[%u]", fOp[op], fReg[op], bit);
        return buf;
    }

    // ── Keyboard scan (hi nibble = 8) ─────────────────────────────────
    if (hi == 0x8) {
        bool single = (opcode & 0x0008) != 0;
        uint8_t kmask = (uint8_t)((opcode >> 4) & 0x0Fu);
        if (single) {
            snprintf(buf, sizeof(buf), "KEY %u,D%u", kmask, opcode & 7);
        } else {
            snprintf(buf, sizeof(buf), "KEY_ALL %u", kmask);
        }
        return buf;
    }

    // ── Misc / control (hi nibble = A) ──────────────────────────────────
    if (hi == 0xA) {
        uint8_t loNib = (uint8_t)(opcode & 0x000Fu);
        uint8_t arg   = (uint8_t)((opcode >> 4) & 0x000Fu);
        switch (loNib) {
        case 0x0: snprintf(buf, sizeof(buf), "WAIT D%u", arg); return buf;
        case 0x1: return "CLR IDL";
        case 0x2: return "CLR fA";
        case 0x3: return "WAIT_BUSY";
        case 0x4: return "INC KR";
        case 0x5: snprintf(buf, sizeof(buf), "TST KR[%u]", arg); return buf;
        case 0x6: snprintf(buf, sizeof(buf), "MOV R5,%s[1..4]", (opcode & 0x10) ? "fB" : "fA"); return buf;
        case 0x7: snprintf(buf, sizeof(buf), "MOV R5,#%u", arg); return buf;
        case 0x8: {
            // Peripheral I/O — sub-decoded by opcode bits 7:4
            switch (opcode & 0x00F0u) {
            case 0x00: return "MOV R5,KR[4..7]";
            case 0x10: return "MOV KR[4..7],R5";
            case 0x20: return "IN CRD";
            case 0x30: return "OUT CRD";
            case 0x40: return "CRD_OFF";
            case 0x50: return "CRD_READ";
            case 0x60: return "OUT PRT";
            case 0x70: return "OUT PRT_FUNC";
            case 0x80: return "PRT_CLEAR";
            case 0x90: return "PRT_STEP";
            case 0xA0: return "PRT_PRINT";
            case 0xB0: return "PRT_FEED";
            case 0xC0: return "CRD_WRITE";
            case 0xF0: return "RAM_OP";
            default: snprintf(buf, sizeof(buf), "IO_%02X", (uint8_t)(opcode & 0x00FFu)); return buf;
            }
        }
        case 0x9: return "SET IDL";
        case 0xA: return "CLR fB";
        case 0xB: return "TST BUSY";
        case 0xC: return "MOV KR,EXT";
        case 0xD: return "XCH KR,SR";
        case 0xE: {
            switch (opcode & 0x00F0u) {
            case 0x00: return "IN LIB";
            case 0x10: return "OUT LIB_PC";
            case 0x20: return "IN LIB_PC";
            case 0x30: return "IN LIB_HIGH";
            default:   snprintf(buf, sizeof(buf), "LIB_%02X", (uint8_t)(opcode >> 4 & 0xF)); return buf;
            }
        }
        case 0xF: {
            switch (opcode & 0x00F0u) {
            case 0x00: return "STO";
            case 0x10: return "RCL";
            default:   snprintf(buf, sizeof(buf), "MEM_%02X", (uint8_t)(opcode >> 4 & 0xF)); return buf;
            }
        }
        default: break;
        }
        snprintf(buf, sizeof(buf), "MISC %04X", opcode);
        return buf;
    }

    // ── ALU (everything else) ─────────────────────────────────────────
    const char* maskStr = kMaskName[hi];
    int aluIdx = (opcode >> 3) & 0x1Fu;
    int dstIdx = opcode & 0x07;
    const char* dstStr = kDst[dstIdx];

    // Special-case ops 24–31
    uint8_t spOp = (uint8_t)(opcode & 0x00F8u);
    if (spOp == 0xC0) { snprintf(buf, sizeof(buf), "ADD.%s %s,A,const", maskStr, dstStr); return buf; }
    if (spOp == 0xC8) { snprintf(buf, sizeof(buf), "SUB.%s %s,A,const", maskStr, dstStr); return buf; }
    if (spOp == 0xD0) { snprintf(buf, sizeof(buf), "MOV.%s %s,#0/RCL", maskStr, dstStr); return buf; }
    if (spOp == 0xD8) { snprintf(buf, sizeof(buf), "NEG.%s %s", maskStr, dstStr); return buf; }
    if (spOp == 0xE0) { snprintf(buf, sizeof(buf), "ADD.%s %s,C,const", maskStr, dstStr); return buf; }
    if (spOp == 0xE8) { snprintf(buf, sizeof(buf), "SUB.%s %s,C,const", maskStr, dstStr); return buf; }
    if (spOp == 0xF0 || spOp == 0xF8) { snprintf(buf, sizeof(buf), "MOV.%s %s,R5", maskStr, dstStr); return buf; }

    if (aluIdx < 24) {
        snprintf(buf, sizeof(buf), "%s.%s %s,%s",
                 kALUOp[aluIdx], maskStr, dstStr, kALUSrc[aluIdx]);
        return buf;
    }

    snprintf(buf, sizeof(buf), "ALU %04X", opcode);
    return buf;
}
