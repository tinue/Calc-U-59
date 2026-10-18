#import "TISession.h"
#import "TI59MachineWrapper+Cpp.h"
#import "TIFileFormats+Cpp.h"
#import "TITraceWriter+Cpp.h"
#include "../Shared/EmulatorSession.hpp"
#include <memory>

namespace {

NSString* ns(const std::string& s) { return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding] ?: @""; }

cu59::ResourceReader readerFrom(TIResourceReader block) {
    return [block](const std::string& name) -> std::optional<std::string> {
        NSString* text = block(ns(name));
        if (!text) return std::nullopt;
        return std::string(text.UTF8String);
    };
}

/// Forwards session events to the (weak) delegate.
struct DelegateListener : cu59::EmulatorSession::Listener {
    __weak id<TISessionDelegate> delegate;
    void breakpointHit(uint16_t pc) override { [delegate sessionBreakpointHit:pc]; }
    void freezeFired(cu59::FreezeOwner o) override {
        [delegate sessionFreezeFired:o == cu59::FreezeOwner::Cpu ? 0 : 1];
    }
    void heldKeyChanged(int id) override { [delegate sessionHeldKeyChanged:id]; }
    void fullSpeedChanged(bool on) override { [delegate sessionFullSpeedChanged:on]; }
    void playbackStarted() override { [delegate sessionPlaybackStarted]; }
    void playbackFinished() override { [delegate sessionPlaybackFinished]; }
    void togglePrinterTrace() override { [delegate sessionTogglePrinterTrace]; }
    void logLine(const std::string& l) override { [delegate sessionLogLine:ns(l)]; }
    void scriptedTraceFailed(const std::string& f) override { [delegate sessionScriptedTraceFailed:ns(f)]; }
    void scriptedTraceChanged(bool open) override { [delegate sessionScriptedTraceChanged:open]; }
    void batchDone() override { [delegate sessionBatchDone]; }
};

} // namespace

@interface TIFrameUpdate ()
@property (nonatomic, readwrite) BOOL displayUpdated;
@property (nonatomic, readwrite) TIDisplaySnapshot display;
@property (nonatomic, readwrite) double calcIndicatorOpacity;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *printerLines;
@property (nonatomic, readwrite, copy) NSArray<NSData *> *printerCodeLines;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *logLines;
@property (nonatomic, readwrite) BOOL cardAutoEjected;
@end
@implementation TIFrameUpdate
@end

@implementation TISession {
    DelegateListener _listener;
    std::unique_ptr<cu59::EmulatorSession> _session;
    TI59MachineWrapper* _machine;
    TITraceWriter* _manualTrace;
    TITraceWriter* _scriptedTrace;
}

- (instancetype)initWithModel:(NSInteger)model reader:(TIResourceReader)reader
                moduleRomFile:(NSString *)moduleRomFile delegate:(id<TISessionDelegate>)delegate
                        error:(NSError **)error {
    if (!(self = [super init])) return nil;
    _listener.delegate = delegate;
    try {
        std::optional<std::string> module;
        if (moduleRomFile) module = std::string(moduleRomFile.UTF8String);
        _session = std::make_unique<cu59::EmulatorSession>(static_cast<cu59::Model>(model), readerFrom(reader),
                                                           module, _listener);
    } catch (const std::exception& e) {
        if (error) *error = [NSError errorWithDomain:@"Calc-U-59.ROMLoader" code:1
                                            userInfo:@{NSLocalizedDescriptionKey: ns(e.what())}];
        return nil;
    }
    _machine = [[TI59MachineWrapper alloc] initWithSharedMachine:_session->sharedMachine()];
    _manualTrace = [[TITraceWriter alloc] initWithWriter:&_session->manualTrace()];
    _scriptedTrace = [[TITraceWriter alloc] initWithWriter:&_session->scriptedTrace()];
    return self;
}

- (void)dealloc {
    _session.reset();  // joins the session threads before the listener goes away
}

- (TI59MachineWrapper *)machine { return _machine; }
- (NSData *)moduleImage {
    const auto& m = _session->moduleImage();
    return [NSData dataWithBytes:m.data() length:m.size()];
}
- (BOOL)loadModule:(NSString *)romFile reader:(TIResourceReader)reader {
    return _session->loadModule(romFile.UTF8String, readerFrom(reader));
}

- (void)start { _session->start(); }
- (void)stop { _session->stop(); }
- (BOOL)isRunning { return _session->isRunning(); }
- (void)post:(dispatch_block_t)job { _session->post([job] { job(); }); }
- (void)sync:(dispatch_block_t)job { _session->sync([job] { job(); }); }
- (BOOL)fullSpeed { return _session->isFullSpeed(); }
- (void)setFullSpeed:(BOOL)on { _session->setFullSpeed(on); }
- (BOOL)frozen { return _session->frozen(); }
- (void)setFrozen:(BOOL)frozen { _session->setFrozen(frozen); }

- (void)armScanLoopExit { _session->freezeControl().armScanLoopExit(_session->machine().pc()); }
- (void)armPcChange { _session->freezeControl().armPcChange(_session->machine()); }
- (void)disarmScanLoopExit { _session->freezeControl().disarmScanLoopExit(); }
- (void)disarmPcChange { _session->freezeControl().disarmPcChange(); }

- (void)pressKey:(uint8_t)matrixCode { _session->pressKey(matrixCode); }
- (void)releaseKey:(uint8_t)matrixCode { _session->releaseKey(matrixCode); }
- (void)keyboardDown:(NSData *)matrixCodes {
    const auto* p = static_cast<const uint8_t*>(matrixCodes.bytes);
    _session->keyboardDown(std::vector<uint8_t>(p, p + matrixCodes.length));
}
- (void)keyboardUp { _session->keyboardUp(); }
- (void)keyboardRelease { _session->keyboardRelease(); }
- (void)playKeystrokesOf:(TIStateFileResult *)stateFile { _session->playKeystrokes(stateFile.cppResult.keystrokes); }
- (void)cancelKeystrokes { _session->cancelKeystrokes(); }

- (TIFrameUpdate *)tickWithDebugLevel:(NSInteger)level cardSwiping:(BOOL)cardSwiping {
    cu59::FrameUpdate u = _session->tick(static_cast<int>(level), cardSwiping == YES);
    TIFrameUpdate* t = [[TIFrameUpdate alloc] init];
    t.displayUpdated = u.displayUpdated;
    TIDisplaySnapshot d{};
    memcpy(d.digits, u.display.digits, 12);
    memcpy(d.ctrl, u.display.ctrl, 12);
    d.dpPos = u.display.dpPos;
    d.dpAfterglowMask = u.display.dpAfterglowMask;
    d.suppressedMask = u.display.suppressedMask;
    d.calcIndicator = u.display.calcIndicator;
    t.display = d;
    t.calcIndicatorOpacity = u.calcIndicatorOpacity;
    NSMutableArray* lines = [NSMutableArray arrayWithCapacity:u.printerLines.size()];
    for (const auto& l : u.printerLines) [lines addObject:ns(l)];
    t.printerLines = lines;
    NSMutableArray* codes = [NSMutableArray arrayWithCapacity:u.printerCodeLines.size()];
    for (const auto& c : u.printerCodeLines) {
        // 21 bytes, as TI59MachineWrapper.drainPrinterCodeLines: codes[0..19] + rowCount.
        uint8_t buf[21];
        memcpy(buf, c.codes.data(), 20);
        buf[20] = c.rowCount;
        [codes addObject:[NSData dataWithBytes:buf length:21]];
    }
    t.printerCodeLines = codes;
    NSMutableArray* logs = [NSMutableArray arrayWithCapacity:u.logLines.size()];
    for (const auto& l : u.logLines) [logs addObject:ns(l)];
    t.logLines = logs;
    t.cardAutoEjected = u.cardAutoEjected;
    return t;
}

- (TITraceWriter *)manualTrace { return _manualTrace; }
- (TITraceWriter *)scriptedTrace { return _scriptedTrace; }
- (void)setTraceDirectory:(NSString *)path maxBytes:(uint64_t)maxBytes {
    _session->setTraceLocation(std::filesystem::path(path.fileSystemRepresentation), maxBytes);
}
- (void)drainTraceManualLimit:(BOOL *)manualLimit scriptedLimit:(BOOL *)scriptedLimit {
    auto r = _session->drainTrace();
    if (manualLimit) *manualLimit = r.manualLimit;
    if (scriptedLimit) *scriptedLimit = r.scriptedLimit;
}

+ (TITraceFlags)traceFlagsForCpuPanel:(BOOL)cpuPanel frozen:(BOOL)frozen manualTrace:(BOOL)manual
                          freezeArmed:(BOOL)armed scriptedTrace:(BOOL)scripted breakpoints:(BOOL)breakpoints {
    cu59::TraceConsumers c;
    c.cpuPanelVisible = cpuPanel;
    c.frozen = frozen;
    c.manualTrace = manual;
    c.freezeArmed = armed;
    c.scriptedTrace = scripted;
    c.breakpoints = breakpoints;
    return static_cast<TITraceFlags>(cu59::traceFlagsFor(c));
}

@end
