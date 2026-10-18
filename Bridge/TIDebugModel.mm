#import "TIDebugModel.h"
#import "TI59MachineWrapper+Cpp.h"
#import "BridgeConvert.h"
#include "../Shared/AsmOverlay.hpp"
#include "../Shared/DebugLog.hpp"
#include "../Shared/DebugSnapshots.hpp"
#include "../Shared/RomHeatmap.hpp"

namespace {
NSArray<NSString*>* lines(const std::vector<std::string>& v) {
    NSMutableArray* a = [NSMutableArray arrayWithCapacity:v.size()];
    for (const auto& l : v) [a addObject:ns(l)];
    return a;
}
std::set<int> indexSet(NSIndexSet* s) {
    std::set<int> out;
    for (NSUInteger i = s.firstIndex; i != NSNotFound; i = [s indexGreaterThanIndex:i]) out.insert(static_cast<int>(i));
    return out;
}
}

@interface TIStepEntry ()
@property (nonatomic, readwrite) NSInteger stepNum;
@property (nonatomic, readwrite) uint8_t keycode;
@property (nonatomic, readwrite, copy) NSString *mnemonic;
@property (nonatomic, readwrite) BOOL isCurrent;
@end
@implementation TIStepEntry
@end

static NSArray<TIStepEntry*>* stepEntries(const std::vector<cu59::StepEntry>& v) {
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
@property (nonatomic, readwrite, copy) NSString *ioUserFlags;
@property (nonatomic, readwrite, copy) NSString *lastKey;
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

@interface TILiveDebugBuild ()
@property (nonatomic, readwrite) TILiveDebugSnapshot *snapshot;
@property (nonatomic, readwrite, copy) NSData *sourceKeycodes;
@property (nonatomic, readwrite, copy) NSIndexSet *argSteps;
@property (nonatomic, readwrite) NSInteger libProgram;
@property (nonatomic, readwrite) NSInteger scomProgram;
@end
@implementation TILiveDebugBuild
@end

static TILiveDebugSnapshot* snapshotFrom(const cu59::LiveDebugSnapshot& s) {
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
    t.ioUserFlags = ns(s.ioUserFlags);
    t.lastKey = ns(s.lastKey);
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

@implementation TIDebugModel {
    cu59::Model _model;
    cu59::ModuleImage _module;
    std::vector<uint8_t> _romCache;
    cu59::RomHeatmap _heatmap;
    cu59::RingLog _log;
}

- (instancetype)initWithModel:(NSInteger)model {
    if ((self = [super init])) _model = static_cast<cu59::Model>(model);
    return self;
}

+ (NSInteger)programSourceForFlag:(uint8_t)flag romPC:(uint16_t)romPC {
    return static_cast<NSInteger>(cu59::programSourceFrom(flag, romPC));
}

- (NSString *)setModuleImage:(NSData *)raw {
    _romCache.clear();
    std::string error;
    _module = cu59::ModuleImage::parse(raw ? bytes(raw) : std::vector<uint8_t>(), &error);
    return error.empty() ? nil : ns(error);
}

- (TILiveDebugBuild *)buildLiveSnapshotFor:(TI59MachineWrapper *)machine frozen:(BOOL)frozen {
    auto b = cu59::buildLiveSnapshot(*machine.cppMachine, _model, _module, _romCache, frozen == YES);
    TILiveDebugBuild* t = [[TILiveDebugBuild alloc] init];
    t.snapshot = snapshotFrom(b.snap);
    t.sourceKeycodes = [NSData dataWithBytes:b.sourceKeycodes.data() length:b.sourceKeycodes.size()];
    NSMutableIndexSet* args = [NSMutableIndexSet indexSet];
    for (int i : b.argSteps) [args addIndex:static_cast<NSUInteger>(i)];
    t.argSteps = args;
    t.libProgram = b.libProgramMismatch ? b.libProgramMismatch->first : -1;
    t.scomProgram = b.libProgramMismatch ? b.libProgramMismatch->second : -1;
    return t;
}

+ (NSArray<TIStepEntry *> *)programListing:(NSData *)keycodes argSteps:(NSIndexSet *)argSteps
                               currentStep:(NSInteger)currentStep {
    return stepEntries(cu59::programListing(bytes(keycodes), indexSet(argSteps), static_cast<int>(currentStep)));
}

- (void)heatmapIngest:(NSArray<NSValue *> *)frames {
    std::vector<CpuFrame> v(frames.count);
    for (NSUInteger i = 0; i < frames.count; ++i) [frames[i] getValue:&v[i] size:sizeof(CpuFrame)];
    _heatmap.ingest(v.data(), v.size());
}

- (BOOL)heatmapPublishTick { return _heatmap.publishTick(); }
- (void)heatmapClear { _heatmap.clear(); }
- (void)heatmapResetBaseline:(uint32_t)newestSeqno { _heatmap.resetBaseline(newestSeqno); }
- (NSData *)heatmapCounts {
    const auto& c = _heatmap.counts();
    return [NSData dataWithBytes:c.data() length:c.size() * sizeof(uint32_t)];
}

+ (NSData *)parseAsmWords:(NSString *)text error:(NSError **)error {
    try {
        auto w = cu59::parseAsmWords(cpp(text));
        return [NSData dataWithBytes:w.data() length:w.size() * sizeof(uint16_t)];
    } catch (const cu59::AsmParseError& e) {
        if (error) *error = [NSError errorWithDomain:@"Calc-U-59.AsmOverlay" code:1
                                            userInfo:@{NSLocalizedDescriptionKey: ns(e.what())}];
        return nil;
    }
}

+ (BOOL)runAsmOverlay:(TI59MachineWrapper *)machine words:(NSData *)words loaded:(BOOL *)loaded steps:(uint32_t *)steps {
    const auto* p = static_cast<const uint16_t*>(words.bytes);
    auto r = cu59::runAsmOverlay(*machine.cppMachine, std::vector<uint16_t>(p, p + words.length / 2));
    if (loaded) *loaded = r.loaded;
    if (steps) *steps = r.steps;
    return r.entered;
}

- (void)logWrite:(NSString *)line { _log.write(cpp(line)); }
- (void)logWriteAll:(NSArray<NSString *> *)ls { for (NSString* l in ls) _log.write(cpp(l)); }
- (void)logClear { _log.clear(); }
- (NSString *)logDisplayText { return ns(_log.displayText()); }
- (NSArray<NSString *> *)dumpVars:(TI59MachineWrapper *)machine { return lines(cu59::dumpVars(*machine.cppMachine, _model)); }
+ (NSArray<NSString *> *)dumpScom:(TI59MachineWrapper *)machine { return lines(cu59::dumpScom(*machine.cppMachine)); }
+ (NSArray<NSString *> *)dumpProg:(TI59MachineWrapper *)machine { return lines(cu59::dumpProg(*machine.cppMachine)); }
+ (NSArray<NSString *> *)dumpMemory:(TI59MachineWrapper *)machine { return lines(cu59::dumpMemory(*machine.cppMachine)); }
+ (NSArray<NSString *> *)dumpStepCounterAnalysis:(TI59MachineWrapper *)machine {
    return lines(cu59::dumpStepCounterAnalysis(*machine.cppMachine));
}

@end
