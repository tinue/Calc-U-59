#import <Foundation/Foundation.h>
#import "TI59MachineWrapper.h"
#import "TIFileFormats.h"
#import "TITraceWriter.h"

NS_ASSUME_NONNULL_BEGIN

/// Events from the session. Called on the session's threads (emulation,
/// key sequencer) — hop to the main thread before touching UI state.
@protocol TISessionDelegate <NSObject>
- (void)sessionBreakpointHit:(uint16_t)pc;
/// owner: 0 = CPU panel (FREEZE ON START), 1 = CALCULATOR panel (next PC change).
- (void)sessionFreezeFired:(NSInteger)owner;
/// row×5 + col of the key shown pressed, -1 for none.
- (void)sessionHeldKeyChanged:(NSInteger)highlightID;
- (void)sessionFullSpeedChanged:(BOOL)on;
- (void)sessionPlaybackStarted;
- (void)sessionPlaybackFinished;
- (void)sessionTogglePrinterTrace;
- (void)sessionLogLine:(NSString *)line;
- (void)sessionScriptedTraceFailed:(NSString *)fileName;
- (void)sessionScriptedTraceChanged:(BOOL)open;
/// After every run-loop batch (≈50/s).
- (void)sessionBatchDone;
@end

/// One 60 Hz frame (Shared/FrameSampler.hpp).
@interface TIFrameUpdate : NSObject
@property (nonatomic, readonly) BOOL displayUpdated;
@property (nonatomic, readonly) TIDisplaySnapshot display;
@property (nonatomic, readonly) double calcIndicatorOpacity;
@property (nonatomic, readonly, copy) NSArray<NSString *> *printerLines;
@property (nonatomic, readonly, copy) NSArray<NSData *> *printerCodeLines;  ///< 20 codes + row count per line
@property (nonatomic, readonly, copy) NSArray<NSString *> *logLines;
@property (nonatomic, readonly) BOOL cardAutoEjected;
@end

/// Swift face of Shared/EmulatorSession: one running calculator and its
/// runtime (run loop, freezes, keys, frames, traces). Type translation only.
@interface TISession : NSObject

/// model = MachineModel raw value; moduleRomFile e.g. "TMC0541.txt" or nil.
- (nullable instancetype)initWithModel:(NSInteger)model
                                reader:(TIResourceReader)reader
                         moduleRomFile:(nullable NSString *)moduleRomFile
                              delegate:(id<TISessionDelegate>)delegate
                                 error:(NSError *_Nullable *_Nullable)error;

/// Shares the session's machine.
@property (nonatomic, readonly) TI59MachineWrapper *machine;
@property (nonatomic, readonly) NSData *moduleImage;
- (BOOL)loadModule:(NSString *)romFile reader:(TIResourceReader)reader;

// ── Run loop ─────────────────────────────────────────────────────────────────
- (void)start;
- (void)stop;
@property (nonatomic, readonly) BOOL isRunning;
/// Run on the emulation thread after the loop has exited.
- (void)post:(dispatch_block_t)job;
/// post + wait. Stop the loop first.
- (void)sync:(dispatch_block_t)job;
@property (nonatomic) BOOL fullSpeed;
/// The UI's freeze state (key playback stops waiting while frozen).
@property (nonatomic) BOOL frozen;

// ── Armed freezes ────────────────────────────────────────────────────────────
- (void)armScanLoopExit;
- (void)armPcChange;
- (void)disarmScanLoopExit;
- (void)disarmPcChange;

// ── Keys ─────────────────────────────────────────────────────────────────────
- (void)pressKey:(uint8_t)matrixCode;
- (void)releaseKey:(uint8_t)matrixCode;
- (void)keyboardDown:(NSData *)matrixCodes;
- (void)keyboardUp;
- (void)keyboardRelease;
- (void)playKeystrokesOf:(TIStateFileResult *)stateFile;
- (void)cancelKeystrokes;

// ── Frames and traces ────────────────────────────────────────────────────────
- (TIFrameUpdate *)tickWithDebugLevel:(NSInteger)level cardSwiping:(BOOL)cardSwiping;
@property (nonatomic, readonly) TITraceWriter *manualTrace;
@property (nonatomic, readonly) TITraceWriter *scriptedTrace;
- (void)setTraceDirectory:(NSString *)path maxBytes:(uint64_t)maxBytes;
/// Drain the trace ring into the open writers; reports writers that hit their size limit.
- (void)drainTraceManualLimit:(BOOL *_Nullable)manualLimit scriptedLimit:(BOOL *_Nullable)scriptedLimit;

/// TRACE_* flags for the active consumers (Shared/EmulatorSession.hpp traceFlagsFor).
+ (TITraceFlags)traceFlagsForCpuPanel:(BOOL)cpuPanel frozen:(BOOL)frozen manualTrace:(BOOL)manual
                          freezeArmed:(BOOL)armed scriptedTrace:(BOOL)scripted breakpoints:(BOOL)breakpoints;

@end

NS_ASSUME_NONNULL_END
