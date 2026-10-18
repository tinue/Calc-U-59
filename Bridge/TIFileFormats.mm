#import "TIFileFormats+Cpp.h"
#import "BridgeConvert.h"
#include "../Shared/CardFile.hpp"
#include "../Shared/ModuleCatalog.hpp"

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

// ── Entry points ─────────────────────────────────────────────────────────────

@implementation TIFileFormats

+ (BOOL)isCardFileName:(NSString *)name { return cu59::isCardFileName(cpp(name)); }
+ (NSString *)withDefaultCardExtension:(NSString *)name { return ns(cu59::withDefaultCardExtension(cpp(name))); }

+ (NSArray<TIModuleMetadata *> *)allModuleMetadata:(NSString *)cuecardsTxt {
    NSMutableArray* out = [NSMutableArray array];
    for (const auto& m : cu59::allModuleMetadata(cpp(cuecardsTxt))) [out addObject:metadataFrom(m)];
    return out;
}

@end
