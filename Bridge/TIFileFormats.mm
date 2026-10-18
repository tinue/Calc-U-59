#import "TIFileFormats+Cpp.h"
#import "TI59MachineWrapper+Cpp.h"
#import "BridgeConvert.h"
#include "../Shared/CardFile.hpp"
#include "../Shared/ConstantMemory.hpp"
#include "../Shared/ModuleCatalog.hpp"
#include "../Shared/StateApplier.hpp"
#include "../Shared/StateFile.hpp"
#include <memory>

// ── Cue card conversion ──────────────────────────────────────────────────────

@implementation TICueCard
- (instancetype)init {
    if ((self = [super init])) {
        _title = @""; _cardID = @""; _row1 = @""; _row2 = @""; _row2R = @"";
        _labels = @[@"", @"", @"", @"", @"", @"", @"", @"", @"", @""];
        _row1Align = 1;  // center
    }
    return self;
}
+ (TICueCard *)ml01Default { return TICueCardFrom(cu59::CueCardContent::ml01Default()); }
@end

TICueCard* TICueCardFrom(const cu59::CueCardContent& c) {
    TICueCard* t = [[TICueCard alloc] init];
    t.templateKind = static_cast<NSInteger>(c.template_);
    t.title = ns(c.title);
    t.bankLeft = c.bankLeft ? @(*c.bankLeft) : nil;
    t.bankRight = c.bankRight ? @(*c.bankRight) : nil;
    t.cardID = ns(c.id);
    NSMutableArray* labels = [NSMutableArray arrayWithCapacity:10];
    for (const auto& l : c.labels) [labels addObject:ns(l)];
    t.labels = labels;
    t.row1 = ns(c.row1);
    t.row1Align = static_cast<NSInteger>(c.row1Align);
    t.row2 = ns(c.row2);
    t.row2Align = static_cast<NSInteger>(c.row2Align);
    t.row2R = ns(c.row2R);
    t.row2RAlign = static_cast<NSInteger>(c.row2RAlign);
    t.style = static_cast<NSInteger>(c.style);
    t.color = static_cast<NSInteger>(c.color);
    return t;
}

cu59::CueCardContent CueCardFrom(TICueCard* t) {
    cu59::CueCardContent c;
    c.template_ = static_cast<cu59::CueCardTemplate>(t.templateKind);
    c.title = cpp(t.title);
    if (t.bankLeft) c.bankLeft = t.bankLeft.intValue;
    if (t.bankRight) c.bankRight = t.bankRight.intValue;
    c.id = cpp(t.cardID);
    for (NSUInteger i = 0; i < 10 && i < t.labels.count; ++i) c.labels[i] = cpp(t.labels[i]);
    c.row1 = cpp(t.row1);
    c.row1Align = static_cast<cu59::TextAlign>(t.row1Align);
    c.row2 = cpp(t.row2);
    c.row2Align = static_cast<cu59::TextAlign>(t.row2Align);
    c.row2R = cpp(t.row2R);
    c.row2RAlign = static_cast<cu59::TextAlign>(t.row2RAlign);
    c.style = static_cast<cu59::CardButtonStyle>(t.style);
    c.color = static_cast<cu59::CueCardInkColor>(t.color);
    return c;
}

static TICueCard* _Nullable optionalCard(const std::optional<cu59::CueCardContent>& c) {
    return c ? TICueCardFrom(*c) : nil;
}

// ── Result objects ───────────────────────────────────────────────────────────

@interface TIStateFileResult ()
@property (nonatomic, readwrite) BOOL hasKeystrokes;
@property (nonatomic, readwrite, nullable) TICueCard *cueCard;
@property (nonatomic, readwrite, copy, nullable) NSString *solidStateModuleID;
@property (nonatomic, readwrite, copy, nullable) NSNumber *printerConnected;
@property (nonatomic, readwrite) NSInteger model;
@property (nonatomic, readwrite) BOOL skipReset;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *errors;
@end
@implementation TIStateFileResult {
@public
    std::shared_ptr<const cu59::LoadStateResult> _cpp;  // the parse, for the applier and playback
}
- (const cu59::LoadStateResult &)cppResult { return *_cpp; }
@end

@interface TICardFile ()
@property (nonatomic, readwrite, copy, nullable) NSData *data;
@property (nonatomic, readwrite, nullable) TICueCard *cueCard;
@property (nonatomic, readwrite) BOOL isText;
@property (nonatomic, readwrite, copy) NSString *error;
@end
@implementation TICardFile
@end

@interface TIConstantMemory ()
@property (nonatomic, readwrite, copy) NSData *ram;
@property (nonatomic, readwrite, nullable) TICueCard *cueCard;
@end
@implementation TIConstantMemory
@end

@interface TIModuleMetadata ()
@property (nonatomic, readwrite, copy) NSString *title;
@property (nonatomic, readwrite, copy) NSString *moduleID;
@property (nonatomic, readwrite, copy) NSString *menuTitle;
@end
@implementation TIModuleMetadata
@end

static TIModuleMetadata* metadataFrom(const cu59::ModuleMetadata& m) {
    TIModuleMetadata* t = [[TIModuleMetadata alloc] init];
    t.title = ns(m.title);
    t.moduleID = ns(m.id);
    t.menuTitle = ns(m.menuTitle);
    return t;
}

@interface TIModuleCards ()
@property (nonatomic, readwrite, copy) NSDictionary<NSNumber *, TICueCard *> *cards;
@property (nonatomic, readwrite) TIModuleMetadata *metadata;
@end
@implementation TIModuleCards
@end

// ── Entry points ─────────────────────────────────────────────────────────────

@implementation TIFileFormats

+ (TIStateFileResult *)parseStateFile:(NSString *)text maxStepAddr:(NSInteger)maxStepAddr
                 allowHiddenRegisters:(BOOL)allowHidden {
    cu59::LoadStateResult r = cu59::parseStateFile(cpp(text), static_cast<int>(maxStepAddr), allowHidden == YES);
    TIStateFileResult* t = [[TIStateFileResult alloc] init];
    t.hasKeystrokes = !r.keystrokes.empty();
    t.cueCard = optionalCard(r.cueCard);
    t.solidStateModuleID = r.solidStateModuleID ? ns(*r.solidStateModuleID) : nil;
    t.printerConnected = r.printerConnected ? @(*r.printerConnected) : nil;
    t.model = r.model ? static_cast<NSInteger>(*r.model) : -1;
    t.skipReset = r.skipReset;
    NSMutableArray* errors = [NSMutableArray array];
    for (const auto& e : r.errors) [errors addObject:ns(e)];
    t.errors = errors;
    t->_cpp = std::make_shared<const cu59::LoadStateResult>(std::move(r));
    return t;
}

+ (NSString *)partitionErrorFor:(TIStateFileResult *)result model:(NSInteger)model {
    auto e = cu59::stateFilePartitionError(*result->_cpp, static_cast<cu59::Model>(model));
    return e ? ns(*e) : nil;
}

+ (void)applyState:(TIStateFileResult *)result to:(TI59MachineWrapper *)machine model:(NSInteger)model {
    cu59::applyState(*machine.cppMachine, *result->_cpp, static_cast<cu59::Model>(model));
}

+ (void)applySkipResetState:(TIStateFileResult *)result to:(TI59MachineWrapper *)machine model:(NSInteger)model {
    cu59::applySkipResetState(*machine.cppMachine, *result->_cpp, static_cast<cu59::Model>(model));
}

+ (NSInteger)prescanStateFile:(NSString *)text currentModel:(NSInteger)current skipReset:(BOOL *_Nullable)skipReset {
    auto p = cu59::prescanStateFile(cpp(text), static_cast<cu59::Model>(current));
    if (skipReset) *skipReset = p.skipReset;
    return static_cast<NSInteger>(p.targetModel);
}

+ (TICardFile *)decodeCardFile:(NSData *)raw fileName:(NSString *)fileName {
    auto r = cu59::decodeCardFile(bytes(raw), cpp(fileName));
    TICardFile* t = [[TICardFile alloc] init];
    t.data = r.card ? nsData(r.card->data) : nil;
    t.cueCard = r.card ? optionalCard(r.card->cueCard) : nil;
    t.isText = r.isText;
    t.error = ns(r.error);
    return t;
}

+ (NSString *)encodeCardText:(NSData *)bank cueCard:(TICueCard *)cueCard {
    std::optional<cu59::CueCardContent> c;
    if (cueCard) c = CueCardFrom(cueCard);
    return ns(cu59::encodeCardText(bytes(bank), c ? &*c : nullptr));
}

+ (NSString *)encodeConstantMemory:(NSData *)ram cueCard:(TICueCard *)cueCard {
    std::optional<cu59::CueCardContent> c;
    if (cueCard) c = CueCardFrom(cueCard);
    return ns(cu59::encodeConstantMemory(bytes(ram), c ? &*c : nullptr));
}

+ (TIConstantMemory *)decodeConstantMemory:(NSString *)text {
    auto r = cu59::decodeConstantMemory(cpp(text));
    if (!r) return nil;
    TIConstantMemory* t = [[TIConstantMemory alloc] init];
    t.ram = nsData(r->ram);
    t.cueCard = optionalCard(r->cueCard);
    return t;
}

+ (BOOL)isCardFileName:(NSString *)name { return cu59::isCardFileName(cpp(name)); }
+ (NSString *)withDefaultCardExtension:(NSString *)name { return ns(cu59::withDefaultCardExtension(cpp(name))); }

+ (NSArray<TIModuleMetadata *> *)allModuleMetadata:(NSString *)cuecardsTxt {
    NSMutableArray* out = [NSMutableArray array];
    for (const auto& m : cu59::allModuleMetadata(cpp(cuecardsTxt))) [out addObject:metadataFrom(m)];
    return out;
}

+ (NSString *)moduleRomFile:(NSString *)cuecardsTxt moduleID:(NSString *)moduleID {
    auto f = cu59::moduleRomFile(cpp(cuecardsTxt), cpp(moduleID));
    return f ? ns(*f) : nil;
}

+ (TIModuleCards *)moduleCards:(NSString *)cuecardsTxt moduleID:(NSString *)moduleID {
    auto mc = cu59::moduleCards(cpp(cuecardsTxt), cpp(moduleID));
    TIModuleCards* t = [[TIModuleCards alloc] init];
    NSMutableDictionary* cards = [NSMutableDictionary dictionary];
    for (const auto& [n, c] : mc.cards) cards[@(n)] = TICueCardFrom(c);
    t.cards = cards;
    t.metadata = metadataFrom(mc.metadata);
    return t;
}

@end
