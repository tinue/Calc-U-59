#import <Foundation/Foundation.h>
#import "TITypes.h"
#import "TIFileFormats.h"

NS_ASSUME_NONNULL_BEGIN

// Swift face of Shared/SessionController: the calculator, presets, cards,
// printer, cue card, debugger and traces both apps drive the same way. Type
// translation only. Main thread only; the platform delegate is called on the
// main thread.

/// SessionController::Change bits (Shared/SessionController.hpp).
typedef NS_OPTIONS(uint32_t, TIChange) {
    TIChangeModel     NS_SWIFT_NAME(model)     = 1u << 0,
    TIChangeDisplay   NS_SWIFT_NAME(display)   = 1u << 1,
    TIChangeCueCard   NS_SWIFT_NAME(cueCard)   = 1u << 2,
    TIChangePrinter   NS_SWIFT_NAME(printer)   = 1u << 3,
    TIChangePaperCut  NS_SWIFT_NAME(paperCut)  = 1u << 4,
    TIChangeCard      NS_SWIFT_NAME(card)      = 1u << 5,
    TIChangeRunState  NS_SWIFT_NAME(runState)  = 1u << 6,
    TIChangeLive      NS_SWIFT_NAME(live)      = 1u << 7,
    TIChangeCpu       NS_SWIFT_NAME(cpu)       = 1u << 8,
    TIChangeHeatmap   NS_SWIFT_NAME(heatmap)   = 1u << 9,
    TIChangeLog       NS_SWIFT_NAME(log)       = 1u << 10,
    TIChangeAsm       NS_SWIFT_NAME(asm)       = 1u << 11,
    TIChangeTrace     NS_SWIFT_NAME(trace)     = 1u << 12,
    TIChangeListing   NS_SWIFT_NAME(listing)   = 1u << 13,
};

/// The debug panel that owns a freeze (FreezeOwner; None when running).
typedef NS_ENUM(NSInteger, TIFreezeOwner) {
    TIFreezeOwnerNone = -1,
    TIFreezeOwnerCpu = 0,
    TIFreezeOwnerCalculator = 1,
};

/// SessionController::Platform, implemented by the app (main thread).
@protocol TIPlatform <NSObject>
- (nullable NSString *)readConstantMemory;
- (void)writeConstantMemory:(NSString *)text;
- (BOOL)writeCard:(NSString *)text toPath:(NSString *)path;
@property (nonatomic, readonly) NSString *traceDirectory;
@property (nonatomic, readonly) uint64_t traceMaxBytes;
@property (nonatomic, readonly) BOOL traceAvailable;
- (void)saveLastUsedModel:(NSInteger)model;
- (void)saveModuleID:(NSString *)moduleID;
- (void)showErrorTitle:(NSString *)title message:(NSString *)message;
- (void)diagnostic:(NSString *)message;
- (void)changed:(TIChange)changes;
@end

/// One printed line's dot codes (Core PrinterCodeLine).
@interface TIPrinterLine : NSObject
@property (nonatomic, readonly, copy) NSData *codes;   ///< 20 character codes (0–63)
@property (nonatomic, readonly) NSInteger rowCount;    ///< dot rows printed: 7 complete, 1–6 cut short
@end

/// ProgramSource raw values follow the C++ enumerator order:
/// 0 userProgram, 1 solidState, 2 solidStateReturn, 3 fastMode, 4 rom.
@interface TIStepEntry : NSObject
@property (nonatomic, readonly) NSInteger stepNum;
@property (nonatomic, readonly) uint8_t keycode;
@property (nonatomic, readonly, copy) NSString *mnemonic;
@property (nonatomic, readonly) BOOL isCurrent;
@end

@interface TIRegEntry : NSObject
@property (nonatomic, readonly) NSInteger num;
@property (nonatomic, readonly) double value;
@property (nonatomic, readonly) BOOL isHidden;
@end

/// The CALCULATOR tab's snapshot (Shared/DebugSnapshots.hpp LiveDebugSnapshot).
@interface TILiveDebugSnapshot : NSObject
@property (nonatomic, readonly, copy) NSArray<TIRegEntry *> *nonZeroRegs;
@property (nonatomic, readonly) NSInteger dataRegCount;
@property (nonatomic, readonly) NSInteger programRegCount;
@property (nonatomic, readonly, copy) NSArray<TIStepEntry *> *programWindow;
@property (nonatomic, readonly) NSInteger currentStep;
@property (nonatomic, readonly, copy) NSArray<NSNumber *> *hir;          ///< HIR 1–8
@property (nonatomic, readonly) double tRegister;
@property (nonatomic, readonly) double xValue;
@property (nonatomic, readonly, copy) NSString *xRaw;
@property (nonatomic, readonly, copy) NSArray<NSNumber *> *calcFlags;    ///< 10 BOOLs
@property (nonatomic, readonly, copy) NSString *fixIndicator;
@property (nonatomic, readonly, copy) NSString *statusRegister;
@property (nonatomic, readonly) uint16_t fA;
@property (nonatomic, readonly) uint16_t fB;
@property (nonatomic, readonly, copy) NSString *engIndicator;
@property (nonatomic, readonly, copy) NSString *secondIndicator;
@property (nonatomic, readonly, copy) NSString *invIndicator;
@property (nonatomic, readonly) NSInteger angleMode;       ///< -1 none, 0 deg, 1 rad, 2 grad
@property (nonatomic, readonly) uint8_t prSourceFlag;
@property (nonatomic, readonly) NSInteger programSource;
@property (nonatomic, readonly) NSInteger pendingOpsCount;
@property (nonatomic, readonly, copy) NSArray<NSString *> *scomRows;
@property (nonatomic, readonly, copy) NSData *returnAddressSourceFlags;  ///< 6 bytes, L1–L6
@property (nonatomic, readonly, copy) NSArray<NSNumber *> *returnAddresses;
@end

/// One CPU-inspector row (frame zeroed for the predicted next instruction).
@interface TIInspectorEntry : NSObject
@property (nonatomic, readonly) uint16_t pc;
@property (nonatomic, readonly) uint16_t opcode;
@property (nonatomic, readonly, copy) NSString *disasm;
@property (nonatomic, readonly) TICpuFrame frame;
@property (nonatomic, readonly) BOOL isHistory;
@property (nonatomic, readonly) BOOL isCurrent;
@end

@interface TISessionController : NSObject

/// `platform` is held weakly.
- (instancetype)initWithReader:(TIResourceReader)reader cuecards:(NSString *)cuecards
                      moduleID:(NSString *)moduleID platform:(id<TIPlatform>)platform;

// ── Machine (model = MachineModel raw value) ─────────────────────────────────
/// NO on a ROM error (reported to the platform); the previous machine keeps running.
- (BOOL)startMachine:(NSInteger)model;
@property (nonatomic, readonly) BOOL hasMachine;
@property (nonatomic, readonly) NSInteger model;
- (void)resetMachine;
- (void)cleanResetMachine;
- (void)suspend;
- (void)resumeAfterSuspend;
/// The 60 Hz frame.
- (void)tick;
@property (nonatomic, readonly) NSString *moduleID;
/// Swap to a different module and soft-reset (the Settings choice).
- (void)changeModule:(NSString *)moduleID;

// ── Display, keys, speed ─────────────────────────────────────────────────────
@property (nonatomic, readonly) TIDisplaySnapshot display;
@property (nonatomic, readonly) double calcIndicatorOpacity;
- (void)pressKey:(uint8_t)matrixCode;
- (void)releaseKey:(uint8_t)matrixCode;
- (void)keyboardDown:(NSData *)codes;
- (void)keyboardUp;
- (void)keyboardRelease;
@property (nonatomic, readonly) NSInteger heldKey;   ///< row×5 + col, -1 none
@property (nonatomic) BOOL fullSpeed;
@property (nonatomic, readonly) BOOL keystrokesPlaying;

// ── Cue card, printer ────────────────────────────────────────────────────────
@property (nonatomic, readonly, nullable) TICueCard *cueCard;
@property (nonatomic, readonly) NSInteger printerLineCount;
/// Lines from index `start` on (text and dot codes are parallel; codes can lag a frame).
- (NSArray<NSString *> *)printerLinesFrom:(NSInteger)start;
@property (nonatomic, readonly) NSInteger printerCodeLineCount;
- (NSArray<TIPrinterLine *> *)printerCodeLinesFrom:(NSInteger)start;
/// The strip's height in dot pitches (for copy-as-image).
@property (nonatomic, readonly) double printerStripHeightUnits;
@property (nonatomic, readonly) BOOL printerConnected;
@property (nonatomic, readonly) BOOL printerTrace;
- (void)setPrinterConnected:(BOOL)connected;
- (void)togglePrinterTrace;
- (void)pressPrinterPrint:(BOOL)pressed;
- (void)pressPrinterAdv:(BOOL)pressed;
- (void)cutPaper;

// ── Card reader ──────────────────────────────────────────────────────────────
@property (nonatomic, readonly) BOOL cardSwiping;
@property (nonatomic, readonly) NSString *cardFileName;
/// raw nil: the file could not be read.
- (void)insertCard:(nullable NSData *)raw path:(NSString *)path fileName:(NSString *)fileName;
- (void)insertBlankCard:(NSString *)savePath fileName:(NSString *)fileName;
- (void)ejectCard;

// ── State files ──────────────────────────────────────────────────────────────
- (void)loadStateFile:(nullable NSData *)raw;

// ── Debugger ─────────────────────────────────────────────────────────────────
- (void)setLiveDebugEnabled:(BOOL)on;
- (void)setCpuDebugEnabled:(BOOL)on;
@property (nonatomic, readonly) BOOL frozen;
@property (nonatomic, readonly) TIFreezeOwner freezeOwner;
@property (nonatomic, readonly) BOOL pcChangeArmed;
@property (nonatomic, readonly) BOOL scanLoopExitArmed;
- (void)freeze:(TIFreezeOwner)owner;
- (void)resume;
- (void)armPcChange;
- (void)armScanLoopExit;
- (void)disarmPcChange;
- (void)disarmScanLoopExit;
- (void)stepKeycode;
- (void)stepInstruction;
@property (nonatomic, readonly) TILiveDebugSnapshot *liveSnapshot;
@property (nonatomic, readonly) NSArray<TIStepEntry *> *programListing;
@property (nonatomic, readonly) NSInteger programListingSource;
@property (nonatomic, readonly) NSInteger programListingCurrentIndex;   ///< -1 none
@property (nonatomic, readonly) NSArray<TIInspectorEntry *> *cpuHistory;
@property (nonatomic, readonly) NSData *heatmapCounts;   ///< 0x1400 uint32 counts
- (void)clearHeatmap;

@property (nonatomic, readonly) NSInteger debugLevel;   ///< 0 off, 1 info, 2 debug
- (void)cycleDebugLevel;
@property (nonatomic, readonly) NSString *logText;
- (void)clearLog;
- (void)dumpVars;
- (void)dumpScom;
- (void)dumpProg;
- (void)dumpMemory;

@property (nonatomic, readonly) BOOL manualTrace;
- (void)setManualTrace:(BOOL)on;

// ── ASM overlay ──────────────────────────────────────────────────────────────
/// text nil: the file could not be read.
- (void)loadAsm:(nullable NSString *)text fileName:(NSString *)fileName;
- (void)runAsm;
- (void)clearAsm;
@property (nonatomic, readonly) NSString *asmFileName;
@property (nonatomic, readonly) NSInteger asmWordCount;
@property (nonatomic, readonly) NSString *asmStatus;
@property (nonatomic, readonly) BOOL asmActive;

@end

NS_ASSUME_NONNULL_END
