#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


/// Display snapshot passed from C++ core to Swift.
typedef struct {
    uint8_t digits[12];      ///< A[2..13] BCD digit values
    uint8_t ctrl[12];        ///< B[2..13] display control nibbles
    uint8_t dpPos;           ///< R5 — decimal-point position index
    bool    calcIndicator;   ///< true whenever the CPU is not in IDLE/display mode
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
    uint16_t pc, opcode;
    uint8_t  digit, cycleWeight;
    uint32_t seqno;
    uint16_t KR, SR, fA, fB, cpuFlags;
    uint8_t  R5, snapshotIndex;
} TITraceEvent;

typedef struct {
    uint8_t  A[16], B[16], C[16], D[16], E[16];
    uint8_t  SCOM[16][16];
    uint8_t  Sout[16];
    uint16_t KR, SR, fA, fB, EXT, PREG, flags;
    uint8_t  R5, digit, REG_ADDR, RAM_ADDR, RAM_OP;
} TICPUSnapshot;

@interface TI59MachineWrapper : NSObject

- (instancetype)initWithModel:(NSInteger)model;

/// Load ROM words (NSData containing uint16_t little-endian array).
- (void)loadROM:(NSData*)romData;

/// Load Library module (NSData containing 5000 uint8_t bytes).
- (void)loadLibrary:(NSData*)libData;

/// Reset the CPU to power-on state (PC=0, registers cleared, card absent).
- (void)reset;

/// Execute one CPU instruction. Returns cycle count.
- (uint32_t)step;

/// Execute up to n CPU instructions under a single mutex lock. Returns count executed.
- (uint32_t)stepN:(uint32_t)n;

/// Key input. row 0–6, col 0–15.
- (void)pressKeyRow:(int)row col:(int)col;
- (void)releaseKeyRow:(int)row col:(int)col;

/// Read current display state.
- (TIDisplaySnapshot)getDisplay;

/// TI-58C: serialise/deserialise RAM (returns/accepts 1920-byte NSData).
- (NSData*)serialiseRAM;
- (void)deserialiseRAM:(NSData*)data;

// ── State file load helpers ───────────────────────────────────────────────────

/// Write program steps (one byte per step, keycode 0–99) starting at step 0.
- (void)writeProgramSteps:(NSData*)keycodes;

/// Write a data register (regNum 00–58) from exactly 16 nibble bytes.
- (void)writeDataRegister:(NSInteger)regNum nibbles:(NSData*)nibbles16;

/// Current program register count (= data register base index).
@property NSInteger partitionProgramRegs;

// ── Magnetic card reader ─────────────────────────────────────────────────────

/// Insert a card immediately.  Non-empty data = read card (fed via IN CRD);
/// empty/nil data = blank write card (OUT CRD bytes captured).
- (void)insertCard:(NSData*)data;

/// Eject the card; returns bytes captured by OUT CRD (empty for read swipes).
- (NSData*)cardEject;

/// YES while the card is physically passing through the reader slot.
@property (readonly) BOOL isCardPresent;

/// YES while the ROM is polling TST BUSY waiting for a card to be inserted.
@property (readonly) BOOL isWaitingForCard;

/// 0 = no card operation pending, 1 = read, 2 = write.
@property (readonly) NSInteger cardMode;

// ── Printer ───────────────────────────────────────────────────────────────────

/// Drain all pending printer output lines (call at 60 Hz from the UI thread).
- (NSArray<NSString*>*)drainPrinterLines;
/// Drain raw 6-bit character codes for dot-matrix rendering, parallel to drainPrinterLines.
/// Each NSData is 20 bytes (code 0–63 per column). Feed lines are 20 zero bytes.
- (NSArray<NSData*>*)drainPrinterCodeLines;

/// Simulate pressing/releasing the PRINT button on the PC-100A.
- (void)pressPrinterPrint:(BOOL)pressed;

/// Simulate pressing/releasing the ADV (paper advance) button.
- (void)pressPrinterAdv:(BOOL)pressed;

/// Enable or disable TRACE mode on the printer.
- (void)setPrinterTrace:(BOOL)enabled;

// ── Trace / debug API ─────────────────────────────────────────────────────────

@property (nonatomic) TITraceFlags traceFlags;
@property (readonly)  uint16_t currentPC;

- (void)addBreakpoint:(uint16_t)pc;
- (void)removeBreakpoint:(uint16_t)pc;
- (void)clearBreakpoints;

/// Drain up to `max` trace events.  If outSnaps is non-nil, the pointed-to
/// NSArray* is set to a parallel array of TICPUSnapshot NSValues (may be empty
/// if TRACE_REGS_FULL was not set).  Returns an array of TITraceEvent NSValues.
- (NSArray<NSValue*>*)drainTraceEventsMax:(NSUInteger)max
                                snapshots:(NSArray<NSValue*>* _Nullable * _Nullable)outSnaps
    NS_SWIFT_NAME(drainTraceEvents(max:snapshots:));

/// Convenience: drain up to `max` events without capturing CPU register snapshots.
- (NSArray<NSValue*>*)drainTraceEventsMax:(NSUInteger)max
    NS_SWIFT_NAME(drainTraceEvents(max:));

+ (NSString*)disassemblePC:(uint16_t)pc opcode:(uint16_t)opcode;

// ── Calculator-level API ──────────────────────────────────────────────────────

/// Press/release a key by matrix code: row*10 + col,
/// row 1–9 (top→bottom), col 1–5 (left→right). Invalid codes are ignored.
- (void)pressMatrixKey:(uint8_t)matrixCode
    NS_SWIFT_NAME(pressMatrixKey(_:));
- (void)releaseMatrixKey:(uint8_t)matrixCode
    NS_SWIFT_NAME(releaseMatrixKey(_:));

/// Read data register regNum (0–58) decoded as a Double.
- (double)dataRegister:(NSInteger)regNum
    NS_SWIFT_NAME(dataRegister(_:));

/// Read all program steps as keycodes (one byte per step, value 0–99).
/// The returned data length is partitionProgramRegs × 8 (e.g. 480 bytes for OP 17).
- (NSData*)allProgramSteps;

/// Capture a snapshot of all CPU registers at the current instant.
- (TICPUSnapshot)snapshotCPU;

/// Decode a 16-nibble BCD register to a Double (pure, no machine state needed).
+ (double)decodeBCDNibbles:(NSData*)nibbles16
    NS_SWIFT_NAME(decodeBCD(_:));

// ── Raw RAM access ────────────────────────────────────────────────────────────

/// Number of accessible RAM registers (120 for TI-59, 60 for TI-58/58C).
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
