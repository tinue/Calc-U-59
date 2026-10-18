#import <Foundation/Foundation.h>
#import "TI59MachineWrapper.h"

NS_ASSUME_NONNULL_BEGIN

// Swift face of the Shared/ debug model (ModuleImage, DebugSnapshots,
// RomHeatmap, AsmOverlay, DebugLog). Type translation only.

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

@interface TILiveDebugSnapshot : NSObject
@property (nonatomic, readonly, copy) NSArray<TIRegEntry *> *nonZeroRegs;
@property (nonatomic, readonly) NSInteger dataRegCount;
@property (nonatomic, readonly) NSInteger programRegCount;
@property (nonatomic, readonly, copy) NSArray<TIStepEntry *> *programWindow;
@property (nonatomic, readonly) NSInteger currentStep;
@property (nonatomic, readonly, copy) NSArray<NSNumber *> *hir;          ///< HIR 1–8
@property (nonatomic, readonly) double tRegister;
@property (nonatomic, readonly, copy) NSArray<NSNumber *> *calcFlags;    ///< 10 BOOLs
@property (nonatomic, readonly, copy) NSString *fixIndicator;
@property (nonatomic, readonly, copy) NSString *ioUserFlags;
@property (nonatomic, readonly, copy) NSString *lastKey;
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

@interface TILiveDebugBuild : NSObject
@property (nonatomic, readonly) TILiveDebugSnapshot *snapshot;
@property (nonatomic, readonly, copy) NSData *sourceKeycodes;
@property (nonatomic, readonly, copy) NSIndexSet *argSteps;
/// Solid State only: the library range said program `libProgram`, SCOM[9] said `scomProgram` (-1 = agree).
@property (nonatomic, readonly) NSInteger libProgram;
@property (nonatomic, readonly) NSInteger scomProgram;
@end

/// Per-machine debug state: module image, ROM keycode cache, heatmap, log.
@interface TIDebugModel : NSObject

/// model = MachineModel raw value.
- (instancetype)initWithModel:(NSInteger)model;

// ── Program source / module image ───────────────────────────────────────────
+ (NSInteger)programSourceForFlag:(uint8_t)flag romPC:(uint16_t)romPC;
/// Parse the module image (nil = none). Returns an error message, or nil.
- (nullable NSString *)setModuleImage:(nullable NSData *)raw;

// ── Live snapshot ────────────────────────────────────────────────────────────
- (TILiveDebugBuild *)buildLiveSnapshotFor:(TI59MachineWrapper *)machine frozen:(BOOL)frozen;
+ (NSArray<TIStepEntry *> *)programListing:(NSData *)keycodes argSteps:(NSIndexSet *)argSteps
                               currentStep:(NSInteger)currentStep;

// ── ROM heatmap ──────────────────────────────────────────────────────────────
- (void)heatmapIngest:(NSArray<NSValue *> *)frames;
/// YES when the counts should be republished (every 6th tick, if changed).
- (BOOL)heatmapPublishTick;
- (void)heatmapClear;
- (void)heatmapResetBaseline:(uint32_t)newestSeqno;
/// 0x1400 uint32 counts.
@property (nonatomic, readonly) NSData *heatmapCounts;

// ── ASM overlay ──────────────────────────────────────────────────────────────
/// Opcode words (uint16 LE) or nil with a user-facing error.
+ (nullable NSData *)parseAsmWords:(NSString *)text error:(NSError *_Nullable *_Nullable)error;
/// Run on the emulation queue with the loop stopped. loaded = NO: words exceed the overlay.
+ (BOOL)runAsmOverlay:(TI59MachineWrapper *)machine words:(NSData *)words
               loaded:(BOOL *)loaded steps:(uint32_t *)steps;

// ── Log ──────────────────────────────────────────────────────────────────────
- (void)logWrite:(NSString *)line;
- (void)logWriteAll:(NSArray<NSString *> *)lines;
- (void)logClear;
- (NSString *)logDisplayText;
- (NSArray<NSString *> *)dumpVars:(TI59MachineWrapper *)machine;
+ (NSArray<NSString *> *)dumpScom:(TI59MachineWrapper *)machine;
+ (NSArray<NSString *> *)dumpProg:(TI59MachineWrapper *)machine;
+ (NSArray<NSString *> *)dumpMemory:(TI59MachineWrapper *)machine;
+ (NSArray<NSString *> *)dumpStepCounterAnalysis:(TI59MachineWrapper *)machine;

@end

NS_ASSUME_NONNULL_END
