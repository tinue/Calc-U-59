#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Plain C mirrors of the Core structs Swift reads: the display snapshot and
// a CPU trace frame (TICpuFrame matches CpuFrame field for field; the layout
// is checked in BridgeConvert.h).

/// The display (Core DisplaySnapshot).
typedef struct {
    uint8_t  digits[12];      ///< A[2..13] BCD digit values
    uint8_t  ctrl[12];        ///< B[2..13] display control nibbles
    uint8_t  dpPos;           ///< R5 — current decimal-point position index (0 = none, 2..13 valid)
    uint16_t dpAfterglowMask; ///< Bitmask of positions with active afterglow: bit (pos-2) for pos 2..13.
                              ///<   Includes current dpPos. Zero when display is blanked.
    uint16_t suppressedMask;  ///< Zero-suppression circuit output: bit i suppresses display index i.
} TIDisplaySnapshot;

/// One instruction's CPU state (Core CpuFrame).
typedef struct {
    // Identity (always captured)
    uint32_t seqno;
    uint16_t pc;
    uint16_t opcode;
    uint8_t  digit;
    uint8_t  postDigit;
    uint8_t  cycleWeight;
    // Light registers
    uint16_t KR, SR, fA, fB, cpuFlags;
    uint8_t  R5;
    // Full snapshot
    uint8_t  A[16], B[16], C[16], D[16], E[16];
    uint8_t  SCOM[16][16];
    uint8_t  Sout[16];
    uint16_t EXT, PREG, flags, m_libAddr;
    uint8_t  REG_ADDR, RAM_ADDR, RAM_OP, m_libAddrReadPos;
    uint8_t  displayOn;
    uint8_t  maxDigitDecay;
} TICpuFrame;

NS_ASSUME_NONNULL_END
