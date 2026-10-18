#import "TISessionController.h"
#import "BridgeConvert.h"
#import "TIFileFormats+Cpp.h"
#include "../Shared/SessionController.hpp"
#include <memory>

// ── Value objects ────────────────────────────────────────────────────────────

@interface TIPrinterLine ()
@property (nonatomic, readwrite, copy) NSData *codes;
@property (nonatomic, readwrite) NSInteger rowCount;
@end
@implementation TIPrinterLine
@end

@interface TIStepEntry ()
@property (nonatomic, readwrite) NSInteger stepNum;
@property (nonatomic, readwrite) uint8_t keycode;
@property (nonatomic, readwrite, copy) NSString *mnemonic;
@property (nonatomic, readwrite) BOOL isCurrent;
@end
@implementation TIStepEntry
@end

@interface TIRegEntry ()
@property (nonatomic, readwrite) NSInteger num;
@property (nonatomic, readwrite) double value;
@property (nonatomic, readwrite) BOOL isHidden;
@end
@implementation TIRegEntry
@end

@interface TILiveDebugSnapshot ()
@property (nonatomic, readwrite, copy) NSArray<TIRegEntry *> *nonZeroRegs;
@property (nonatomic, readwrite) NSInteger dataRegCount;
@property (nonatomic, readwrite) NSInteger programRegCount;
@property (nonatomic, readwrite, copy) NSArray<TIStepEntry *> *programWindow;
@property (nonatomic, readwrite) NSInteger currentStep;
@property (nonatomic, readwrite, copy) NSArray<NSNumber *> *hir;
@property (nonatomic, readwrite) double tRegister;
@property (nonatomic, readwrite, copy) NSArray<NSNumber *> *calcFlags;
@property (nonatomic, readwrite, copy) NSString *fixIndicator;
@property (nonatomic, readwrite, copy) NSString *statusRegister;
@property (nonatomic, readwrite) uint16_t fA;
@property (nonatomic, readwrite) uint16_t fB;
@property (nonatomic, readwrite, copy) NSString *engIndicator;
@property (nonatomic, readwrite, copy) NSString *secondIndicator;
@property (nonatomic, readwrite, copy) NSString *invIndicator;
@property (nonatomic, readwrite) NSInteger angleMode;
@property (nonatomic, readwrite) uint8_t prSourceFlag;
@property (nonatomic, readwrite) NSInteger programSource;
@property (nonatomic, readwrite) NSInteger pendingOpsCount;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *scomRows;
@property (nonatomic, readwrite, copy) NSData *returnAddressSourceFlags;
@property (nonatomic, readwrite, copy) NSArray<NSNumber *> *returnAddresses;
@end
@implementation TILiveDebugSnapshot
@end

@interface TIInspectorEntry ()
@property (nonatomic, readwrite) uint16_t pc;
@property (nonatomic, readwrite) uint16_t opcode;
@property (nonatomic, readwrite, copy) NSString *disasm;
@property (nonatomic, readwrite) TICpuFrame frame;
@property (nonatomic, readwrite) BOOL isHistory;
@property (nonatomic, readwrite) BOOL isCurrent;
@end
@implementation TIInspectorEntry
@end

namespace {

cu59::ResourceReader readerFrom(TIResourceReader block) {
    return [block](const std::string& name) -> std::optional<std::string> {
        NSString* text = block(ns(name));
        if (!text) return std::nullopt;
        return cpp(text);
    };
}

std::optional<std::vector<uint8_t>> optionalBytes(NSData* d) {
    return d ? std::optional<std::vector<uint8_t>>(bytes(d)) : std::nullopt;
}

NSArray<TIStepEntry*>* stepEntries(const std::vector<cu59::StepEntry>& v) {
    NSMutableArray* a = [NSMutableArray arrayWithCapacity:v.size()];
    for (const auto& e : v) {
        TIStepEntry* t = [[TIStepEntry alloc] init];
        t.stepNum = e.stepNum;
        t.keycode = e.keycode;
        t.mnemonic = ns(e.mnemonic);
        t.isCurrent = e.isCurrent;
        [a addObject:t];
    }
    return a;
}

TILiveDebugSnapshot* snapshotFrom(const cu59::LiveDebugSnapshot& s) {
    TILiveDebugSnapshot* t = [[TILiveDebugSnapshot alloc] init];
    NSMutableArray* regs = [NSMutableArray arrayWithCapacity:s.nonZeroRegs.size()];
    for (const auto& r : s.nonZeroRegs) {
        TIRegEntry* e = [[TIRegEntry alloc] init];
        e.num = r.num;
        e.value = r.value;
        e.isHidden = r.isHidden;
        [regs addObject:e];
    }
    t.nonZeroRegs = regs;
    t.dataRegCount = s.dataRegCount;
    t.programRegCount = s.programRegCount;
    t.programWindow = stepEntries(s.programWindow);
    t.currentStep = s.currentStep;
    NSMutableArray* hir = [NSMutableArray arrayWithCapacity:8];
    for (double v : s.hir) [hir addObject:@(v)];
    t.hir = hir;
    t.tRegister = s.tRegister;
    NSMutableArray* flags = [NSMutableArray arrayWithCapacity:10];
    for (bool f : s.calcFlags) [flags addObject:@(f)];
    t.calcFlags = flags;
    t.fixIndicator = ns(s.fixIndicator);
    t.statusRegister = ns(s.statusRegister);
    t.fA = s.fA;
    t.fB = s.fB;
    t.engIndicator = ns(s.engIndicator);
    t.secondIndicator = ns(s.secondIndicator);
    t.invIndicator = ns(s.invIndicator);
    t.angleMode = s.angleMode ? static_cast<NSInteger>(*s.angleMode) : -1;
    t.prSourceFlag = s.prSourceFlag;
    t.programSource = static_cast<NSInteger>(s.programSource);
    t.pendingOpsCount = s.pendingOpsCount;
    NSMutableArray* rows = [NSMutableArray arrayWithCapacity:16];
    for (const auto& r : s.scomRows) [rows addObject:ns(r)];
    t.scomRows = rows;
    t.returnAddressSourceFlags = [NSData dataWithBytes:s.returnAddressSourceFlags.data() length:6];
    NSMutableArray* ra = [NSMutableArray arrayWithCapacity:6];
    for (int a : s.returnAddresses) [ra addObject:@(a)];
    t.returnAddresses = ra;
    return t;
}

NSArray<TIInspectorEntry*>* inspectorEntries(const std::vector<cu59::InspectorEntry>& v) {
    NSMutableArray* out = [NSMutableArray arrayWithCapacity:v.size()];
    for (const auto& e : v) {
        TIInspectorEntry* t = [[TIInspectorEntry alloc] init];
        t.pc = e.pc;
        t.opcode = e.opcode;
        t.disasm = ns(e.disasm);
        t.frame = tiCpuFrame(e.frame);
        t.isHistory = e.isHistory;
        t.isCurrent = e.isCurrent;
        [out addObject:t];
    }
    return out;
}

/// SessionController::Platform over the app's (weak) TIPlatform.
struct PlatformAdapter : cu59::SessionController::Platform {
    __weak id<TIPlatform> platform;

    void runOnUiThread(std::function<void()> job) override {
        auto shared = std::make_shared<std::function<void()>>(std::move(job));
        dispatch_async(dispatch_get_main_queue(), ^{ (*shared)(); });
    }
    std::optional<std::string> readConstantMemory() override {
        NSString* text = [platform readConstantMemory];
        return text ? std::optional<std::string>(cpp(text)) : std::nullopt;
    }
    void writeConstantMemory(const std::string& text) override { [platform writeConstantMemory:ns(text)]; }
    bool writeCard(const std::string& path, const std::string& text) override {
        return [platform writeCard:ns(text) toPath:ns(path)] == YES;
    }
    cu59::SessionController::TraceLocation traceLocation() override {
        id<TIPlatform> p = platform;
        return {std::filesystem::path(p.traceDirectory.fileSystemRepresentation), p.traceMaxBytes};
    }
    bool traceAvailable() override { return [platform traceAvailable] == YES; }
    void saveLastUsedModel(cu59::Model model) override { [platform saveLastUsedModel:static_cast<NSInteger>(model)]; }
    void saveModuleID(const std::string& moduleID) override { [platform saveModuleID:ns(moduleID)]; }
    void error(const std::string& title, const std::string& message) override {
        [platform showErrorTitle:ns(title) message:ns(message)];
    }
    void diagnostic(const std::string& message) override { [platform diagnostic:ns(message)]; }
    void changed(uint32_t changes) override { [platform changed:static_cast<TIChange>(changes)]; }
};

} // namespace

@implementation TISessionController {
    PlatformAdapter _platform;
    std::unique_ptr<cu59::SessionController> _c;
}

- (instancetype)initWithReader:(TIResourceReader)reader cuecards:(NSString *)cuecards
                      moduleID:(NSString *)moduleID platform:(id<TIPlatform>)platform {
    if ((self = [super init])) {
        _platform.platform = platform;
        _c = std::make_unique<cu59::SessionController>(_platform, readerFrom(reader), cpp(cuecards), cpp(moduleID));
    }
    return self;
}

- (void)dealloc { _c.reset(); }

// ── Machine ──────────────────────────────────────────────────────────────────

- (BOOL)startMachine:(NSInteger)model { return _c->startMachine(static_cast<cu59::Model>(model)); }
- (BOOL)hasMachine { return _c->hasMachine(); }
- (NSInteger)model { return static_cast<NSInteger>(_c->model()); }
- (void)resetMachine { _c->resetMachine(); }
- (void)cleanResetMachine { _c->cleanResetMachine(); }
- (void)suspend { _c->suspend(); }
- (void)resumeAfterSuspend { _c->resumeAfterSuspend(); }
- (void)tick { _c->tick(std::chrono::steady_clock::now()); }
- (NSString *)moduleID { return ns(_c->moduleID()); }
- (void)changeModule:(NSString *)moduleID { _c->changeModule(cpp(moduleID)); }

// ── Display, keys, speed ─────────────────────────────────────────────────────

- (TIDisplaySnapshot)display {
    const DisplaySnapshot& s = _c->display();
    TIDisplaySnapshot d{};
    memcpy(d.digits, s.digits, sizeof d.digits);
    memcpy(d.ctrl, s.ctrl, sizeof d.ctrl);
    d.dpPos = s.dpPos;
    d.dpAfterglowMask = s.dpAfterglowMask;
    d.suppressedMask = s.suppressedMask;
    return d;
}
- (double)calcIndicatorOpacity { return _c->calcIndicatorOpacity(); }
- (void)pressKey:(uint8_t)code { _c->pressKey(code); }
- (void)releaseKey:(uint8_t)code { _c->releaseKey(code); }
- (void)keyboardDown:(NSData *)codes { _c->keyboardDown(bytes(codes)); }
- (void)keyboardUp { _c->keyboardUp(); }
- (void)keyboardRelease { _c->keyboardRelease(); }
- (NSInteger)heldKey { return _c->heldKey(); }
- (BOOL)fullSpeed { return _c->fullSpeed(); }
- (void)setFullSpeed:(BOOL)on { _c->setFullSpeed(on == YES); }
- (BOOL)keystrokesPlaying { return _c->keystrokesPlaying(); }

// ── Cue card, printer ────────────────────────────────────────────────────────

- (TICueCard *)cueCard { return _c->cueCard() ? TICueCardFrom(*_c->cueCard()) : nil; }
- (NSInteger)printerLineCount { return static_cast<NSInteger>(_c->printerLines().size()); }
- (NSArray<NSString *> *)printerLinesFrom:(NSInteger)start {
    const auto& lines = _c->printerLines();
    NSMutableArray* out = [NSMutableArray array];
    for (size_t i = static_cast<size_t>(MAX(start, 0)); i < lines.size(); ++i) [out addObject:ns(lines[i])];
    return out;
}
- (NSInteger)printerCodeLineCount { return static_cast<NSInteger>(_c->printerCodeLines().size()); }
- (NSArray<TIPrinterLine *> *)printerCodeLinesFrom:(NSInteger)start {
    const auto& lines = _c->printerCodeLines();
    NSMutableArray* out = [NSMutableArray array];
    for (size_t i = static_cast<size_t>(MAX(start, 0)); i < lines.size(); ++i) {
        TIPrinterLine* line = [[TIPrinterLine alloc] init];
        line.codes = [NSData dataWithBytes:lines[i].codes.data() length:lines[i].codes.size()];
        line.rowCount = lines[i].rowCount;
        [out addObject:line];
    }
    return out;
}
- (double)printerStripHeightUnits { return _c->printerStripHeightUnits(); }
- (BOOL)printerConnected { return _c->printerConnected(); }
- (BOOL)printerTrace { return _c->printerTrace(); }
- (void)setPrinterConnected:(BOOL)connected { _c->setPrinterConnected(connected == YES); }
- (void)togglePrinterTrace { _c->togglePrinterTrace(); }
- (void)pressPrinterPrint:(BOOL)pressed { _c->pressPrinterPrint(pressed == YES); }
- (void)pressPrinterAdv:(BOOL)pressed { _c->pressPrinterAdv(pressed == YES); }
- (void)cutPaper { _c->cutPaper(); }

// ── Card reader ──────────────────────────────────────────────────────────────

- (BOOL)cardSwiping { return _c->cardState() == cu59::SessionController::CardState::Swiping; }
- (NSString *)cardFileName { return ns(_c->cardFileName()); }
- (void)insertCard:(NSData *)raw path:(NSString *)path fileName:(NSString *)fileName {
    _c->insertCard(optionalBytes(raw), cpp(path), cpp(fileName));
}
- (void)insertBlankCard:(NSString *)savePath fileName:(NSString *)fileName {
    _c->insertBlankCard(cpp(savePath), cpp(fileName));
}
- (void)ejectCard { _c->ejectCard(); }

// ── State files ──────────────────────────────────────────────────────────────

- (void)loadStateFile:(NSData *)raw { _c->loadStateFile(optionalBytes(raw)); }

// ── Debugger ─────────────────────────────────────────────────────────────────

- (void)setLiveDebugEnabled:(BOOL)on { _c->setLiveDebugEnabled(on == YES); }
- (void)setCpuDebugEnabled:(BOOL)on { _c->setCpuDebugEnabled(on == YES); }
- (BOOL)frozen { return _c->isFrozen(); }
- (TIFreezeOwner)freezeOwner {
    auto owner = _c->debugState().owner;
    if (!owner) return TIFreezeOwnerNone;
    return *owner == cu59::FreezeOwner::Cpu ? TIFreezeOwnerCpu : TIFreezeOwnerCalculator;
}
- (BOOL)pcChangeArmed { return _c->debugState().pcChangeArmed; }
- (BOOL)scanLoopExitArmed { return _c->debugState().scanLoopExitArmed; }
- (void)freeze:(TIFreezeOwner)owner {
    if (owner != TIFreezeOwnerNone)
        _c->freeze(owner == TIFreezeOwnerCpu ? cu59::FreezeOwner::Cpu : cu59::FreezeOwner::Calculator);
}
- (void)resume { _c->resume(); }
- (void)armPcChange { _c->armPcChange(); }
- (void)armScanLoopExit { _c->armScanLoopExit(); }
- (void)disarmPcChange { _c->disarmPcChange(); }
- (void)disarmScanLoopExit { _c->disarmScanLoopExit(); }
- (void)stepKeycode { _c->stepKeycode(); }
- (void)stepInstruction { _c->stepInstruction(); }
- (TILiveDebugSnapshot *)liveSnapshot { return snapshotFrom(_c->debug().live()); }
- (NSArray<TIStepEntry *> *)programListing { return stepEntries(_c->debug().listing()); }
- (NSInteger)programListingSource { return static_cast<NSInteger>(_c->debug().listingSource()); }
- (NSInteger)programListingCurrentIndex { return _c->debug().listingCurrentIndex(); }
- (NSArray<TIInspectorEntry *> *)cpuHistory { return inspectorEntries(_c->debug().cpuHistory()); }
- (NSData *)heatmapCounts {
    const auto& c = _c->debug().heatmapCounts();
    return [NSData dataWithBytes:c.data() length:c.size() * sizeof(uint32_t)];
}
- (void)clearHeatmap { _c->clearHeatmap(); }

- (NSInteger)debugLevel { return static_cast<NSInteger>(_c->debugLevel()); }
- (void)cycleDebugLevel { _c->cycleDebugLevel(); }
- (NSString *)logText { return ns(_c->logText()); }
- (void)clearLog { _c->clearLog(); }
- (void)dumpVars { _c->dumpVars(); }
- (void)dumpScom { _c->dumpScom(); }
- (void)dumpProg { _c->dumpProg(); }
- (void)dumpMemory { _c->dumpMemory(); }
- (void)dumpStepCounterAnalysis { _c->dumpStepCounterAnalysis(); }

- (BOOL)manualTrace { return _c->manualTrace(); }
- (void)setManualTrace:(BOOL)on { _c->setManualTrace(on == YES); }

// ── ASM overlay ──────────────────────────────────────────────────────────────

- (void)loadAsm:(NSString *)text fileName:(NSString *)fileName {
    _c->loadAsm(text ? std::optional<std::string>(cpp(text)) : std::nullopt, cpp(fileName));
}
- (void)runAsm { _c->runAsm(); }
- (void)clearAsm { _c->clearAsm(); }
- (NSString *)asmFileName { return ns(_c->asmFileName()); }
- (NSInteger)asmWordCount { return _c->asmWordCount(); }
- (NSString *)asmStatus { return ns(_c->asmStatus()); }
- (BOOL)asmActive { return _c->asmActive(); }

@end
