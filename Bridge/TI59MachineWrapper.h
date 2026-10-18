#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


/// Display snapshot passed from C++ core to Swift.
typedef struct {
    uint8_t  digits[12];      ///< A[2..13] BCD digit values
    uint8_t  ctrl[12];        ///< B[2..13] display control nibbles
    uint8_t  dpPos;           ///< R5 — current decimal-point position index (0 = none, 2..13 valid)
    uint16_t dpAfterglowMask; ///< Bitmask of positions with active afterglow: bit (pos-2) for pos 2..13.
                              ///<   Includes current dpPos. Zero when display is blanked.
    uint16_t suppressedMask;  ///< Zero-suppression circuit output: bit i suppresses display index i.
    float    calcIndicator;   ///< fraction of last poll interval where C LED was driven (0.0–1.0)
                              ///<   RUN mode: any fA≠0; IDLE mode: fA bit 14 only (SH pin)
} TIDisplaySnapshot;

// ── Trace / debug types ───────────────────────────────────────────────────────

typedef NS_OPTIONS(uint32_t, TITraceFlags) {
    TITraceFlagsNone        NS_SWIFT_NAME(flagsNone)   = 0x0000,
    TITraceFlagsPC          NS_SWIFT_NAME(pc)          = 0x0001,
    TITraceFlagsRegsLight   NS_SWIFT_NAME(regsLight)   = 0x0002,
    TITraceFlagsRegsFull    NS_SWIFT_NAME(regsFull)    = 0x0004,
    TITraceFlagsBreakpoints NS_SWIFT_NAME(breakpoints) = 0x0008,
};

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

@interface TI59MachineWrapper : NSObject

/// Reset the CPU to power-on state (PC=0, registers cleared, card absent).
- (void)reset;

/// Execute one CPU instruction. Returns cycle count.
- (uint32_t)step;

/// Execute steps until the program-step counter (SCOM[0][4:7]) changes (keycode boundary).
/// Returns cycle-equivalents executed (IDLE steps count as 4, active steps as 1).
/// Stops at ~50,000 cycle-equivalents if no boundary is found.
- (uint32_t)stepUntilNextKeycode
    NS_SWIFT_NAME(stepUntilNextKeycode());

/// Key input. row 0–6, col 0–15.
- (void)pressKeyRow:(int)row col:(int)col;
- (void)releaseKeyRow:(int)row col:(int)col;

/// TI-58C: serialise RAM (1920-byte NSData).
- (NSData*)serialiseRAM;

// ── State file load helpers ───────────────────────────────────────────────────

/// Current program register count (= data register base index).
@property NSInteger partitionProgramRegs;

// ── Magnetic card reader ─────────────────────────────────────────────────────

/// Insert a card immediately.  Non-empty data = read card (fed via IN CRD);
/// empty/nil data = blank write card (OUT CRD bytes captured).
- (void)insertCard:(NSData*)data;

/// Eject the card; returns bytes captured by OUT CRD (empty for read swipes).
- (NSData*)cardEject;

/// YES while the ROM is polling TST BUSY waiting for a card to be inserted.
@property (readonly) BOOL isWaitingForCard;

/// 0 = no card operation pending, 1 = read, 2 = write.
@property (readonly) NSInteger cardMode;

// ── Printer ───────────────────────────────────────────────────────────────────

/// Simulate pressing/releasing the PRINT button on the PC-100A.
- (void)pressPrinterPrint:(BOOL)pressed;

/// Simulate pressing/releasing the ADV (paper advance) button.
- (void)pressPrinterAdv:(BOOL)pressed;

/// Enable or disable TRACE mode on the printer.
- (void)setPrinterTrace:(BOOL)enabled;

/// Attach or detach the printer.  When detached the ROM's printer-present
/// sense (KP.D0) reads low, so the ROM will not attempt to print.
- (void)setPrinterConnected:(BOOL)connected;
@property (nonatomic, readonly) BOOL isPrinterConnected;

// ── Trace / debug API ─────────────────────────────────────────────────────────

/// Set the debug event level. 0 = off, 1 = INFO, 2 = DEBUG.
/// When non-zero, the CPU emits DebugEvents for write operations.
- (void)setDebugLevel:(uint8_t)level;

@property (nonatomic) TITraceFlags traceFlags;
@property (readonly)  uint16_t currentPC;

- (void)addBreakpoint:(uint16_t)pc;
- (void)removeBreakpoint:(uint16_t)pc;
- (void)clearBreakpoints;

/// Load 13-bit opcodes into debug overlay region at linear address 0x1800.
/// `words` must contain little-endian UInt16 opcodes. Returns NO on overflow.
- (BOOL)loadDebugOverlayWords:(NSData*)words;

/// Clear all debug overlay words from 0x1800-0x1FFF.
- (void)clearDebugOverlay;

/// Read (without draining) up to `max` most recent CPU frames. Does not remove
/// frames from the ring buffer; safe to call repeatedly.
- (NSArray<NSValue*>*)readCpuFramesMax:(NSUInteger)max
    NS_SWIFT_NAME(readCpuFrames(max:));

// ── Old trace API (deprecated; kept for binary compatibility) ──

+ (NSString*)disassemblePC:(uint16_t)pc opcode:(uint16_t)opcode;

// ── Calculator-level API ──────────────────────────────────────────────────────

/// Read data register regNum (0–58) decoded as a Double.
- (double)dataRegister:(NSInteger)regNum
    NS_SWIFT_NAME(dataRegister(_:));

/// Read all program steps as keycodes (one byte per step, value 0–99).
/// The returned data length is partitionProgramRegs × 8 (e.g. 480 bytes for OP 17).
- (NSData*)allProgramSteps;

/// Capture a snapshot of all CPU registers at the current instant.
- (TICpuFrame)snapshotCPU;

/// Pre-execution phase for the next instruction. Call after freeze or after step() in debugger.
- (void)beginNextStep;

// ── Raw RAM access ────────────────────────────────────────────────────────────

/// Number of accessible RAM registers (120 for TI-59, 64 for TI-58C, 60 for TI-58).
@property (readonly) NSInteger ramRegisterCount;

/// Read a complete 16-nibble RAM register.  reg must be in [0, ramRegisterCount).
- (NSData*)rawRegister:(NSInteger)reg
    NS_SWIFT_NAME(rawRegister(_:));

/// Write a complete 16-nibble RAM register.  nibbles must be exactly 16 bytes.
- (void)setRawRegister:(NSInteger)reg nibbles:(NSData*)nibbles
    NS_SWIFT_NAME(setRawRegister(_:nibbles:));

// ── Printer buffer ────────────────────────────────────────────────────────────

/// Content currently held in the printer character accumulator (not yet committed to a line).
@property (readonly) NSString *printerBufferContent;

@end

NS_ASSUME_NONNULL_END
