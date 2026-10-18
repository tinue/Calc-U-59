#import "TIViewRules.h"
#import "TI59MachineWrapper+Cpp.h"
#import "TIFileFormats+Cpp.h"
#include "../Shared/DebugSnapshots.hpp"
#include "../Shared/LedGeometry.hpp"
#include "../Shared/ModuleImage.hpp"
#include "../Shared/PrinterFont.hpp"
#include "../Shared/RomHeatmap.hpp"
#include "../Shared/StateApplier.hpp"
#include <cstring>

namespace {
NSString* ns(const std::string& s) { return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding] ?: @""; }
std::string cpp(NSString* s) { return s ? std::string(s.UTF8String) : std::string(); }
CpuFrame cpuFrame(const TICpuFrame& f) {
    CpuFrame c;
    std::memcpy(&c, &f, sizeof c);  // layouts checked in TITraceWriter.mm
    return c;
}
} // namespace

@interface TILabelSpan ()
@property (nonatomic, readwrite) NSInteger startCol;
@property (nonatomic, readwrite) NSInteger endCol;
@property (nonatomic, readwrite, copy) NSString *label;
@end
@implementation TILabelSpan
@end

@interface TICueCardLayout ()
@property (nonatomic, readwrite) CGFloat titleFontSize, gridFontSize, bankFontSize;
@property (nonatomic, readwrite) CGFloat titleYFraction, titleWidthFraction, gridY0Fraction, gridY1Fraction;
@property (nonatomic, readwrite, copy) NSArray<NSNumber *> *xFractions;
@property (nonatomic, readwrite) CGFloat cellWidthFraction;
@property (nonatomic, readwrite) BOOL drawsDividers;
@property (nonatomic, readwrite) BOOL hasId;
@property (nonatomic, readwrite) CGFloat referenceWidth;
@end
@implementation TICueCardLayout
@end

@interface TILedStyle ()
@property (nonatomic, readwrite) CGFloat slant;
@property (nonatomic, readwrite) CGFloat activeR, activeG, activeB;
@property (nonatomic, readwrite) CGFloat inactiveR, inactiveG, inactiveB, inactiveAlpha;
@property (nonatomic, readwrite) CGFloat glowBlurPerWidth, glowOpacity, bloomBlurPerWidth;
@end
@implementation TILedStyle
@end

@interface TILedDotSegment ()
@property (nonatomic, readwrite, copy) NSArray<NSValue *> *centres;
@property (nonatomic, readwrite) CGFloat radius;
@end
@implementation TILedDotSegment
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

static std::vector<cu59::LabelSpan> spansFrom(NSArray<TILabelSpan*>* spans) {
    std::vector<cu59::LabelSpan> out;
    for (TILabelSpan* s in spans) out.push_back({static_cast<int>(s.startCol), static_cast<int>(s.endCol), cpp(s.label)});
    return out;
}

static NSArray<TIInspectorEntry*>* entriesFrom(const std::vector<cu59::InspectorEntry>& v) {
    NSMutableArray* out = [NSMutableArray arrayWithCapacity:v.size()];
    for (const auto& e : v) {
        TIInspectorEntry* t = [[TIInspectorEntry alloc] init];
        t.pc = e.pc;
        t.opcode = e.opcode;
        t.disasm = ns(e.disasm);
        TICpuFrame f;
        std::memcpy(&f, &e.frame, sizeof f);
        t.frame = f;
        t.isHistory = e.isHistory;
        t.isCurrent = e.isCurrent;
        [out addObject:t];
    }
    return out;
}

@implementation TIViewRules

+ (NSArray<TILabelSpan *> *)labelSpansOf:(TICueCard *)card row:(NSInteger)row {
    NSMutableArray* out = [NSMutableArray array];
    for (const auto& s : cu59::labelSpans(CueCardFrom(card), static_cast<int>(row))) {
        TILabelSpan* t = [[TILabelSpan alloc] init];
        t.startCol = s.startCol;
        t.endCol = s.endCol;
        t.label = ns(s.label);
        [out addObject:t];
    }
    return out;
}

+ (NSArray<NSNumber *> *)dividersBetween:(NSArray<TILabelSpan *> *)spans {
    NSMutableArray* out = [NSMutableArray array];
    for (int i : cu59::dividersBetween(spansFrom(spans))) [out addObject:@(i)];
    return out;
}

+ (TICueCardLayout *)cueCardLayoutFor:(NSInteger)templateKind {
    const cu59::CueCardLayout& l = cu59::cueCardLayout(static_cast<cu59::CueCardTemplate>(templateKind));
    TICueCardLayout* t = [[TICueCardLayout alloc] init];
    t.titleFontSize = l.titleFontSize;
    t.gridFontSize = l.gridFontSize;
    t.bankFontSize = l.bankFontSize;
    t.titleYFraction = l.titleYFraction;
    t.titleWidthFraction = l.titleWidthFraction;
    t.gridY0Fraction = l.gridY0Fraction;
    t.gridY1Fraction = l.gridY1Fraction;
    t.xFractions = @[@(l.xFractions[0]), @(l.xFractions[1]), @(l.xFractions[2]), @(l.xFractions[3]), @(l.xFractions[4])];
    t.cellWidthFraction = l.cellWidthFraction;
    t.drawsDividers = l.drawsDividers;
    t.hasId = l.hasId;
    t.referenceWidth = l.referenceWidth;
    return t;
}

+ (CGFloat)cellFittingFontSize:(NSArray<TILabelSpan *> *)spans templateKind:(NSInteger)templateKind
                     cardWidth:(CGFloat)cardWidth scaledGridFontSize:(CGFloat)scaled {
    return cu59::cellFittingFontSize(spansFrom(spans), cu59::cueCardLayout(static_cast<cu59::CueCardTemplate>(templateKind)),
                                     cardWidth, scaled);
}

+ (NSInteger)displayLength:(NSString *)text { return cu59::displayLength(cpp(text)); }

+ (TICueCard *)resolveCueCardForProgram:(NSInteger)program moduleCards:(NSDictionary<NSNumber *, TICueCard *> *)cards
                            moduleTitle:(NSString *)title moduleID:(NSString *)moduleID userCard:(TICueCard *)userCard {
    std::map<int, cu59::CueCardContent> moduleCards;
    for (NSNumber* n in cards) moduleCards[n.intValue] = CueCardFrom(cards[n]);
    std::optional<cu59::CueCardContent> user;
    if (userCard) user = CueCardFrom(userCard);
    auto r = cu59::resolveCueCard(static_cast<int>(program), moduleCards, cpp(title), cpp(moduleID), user);
    return r ? TICueCardFrom(*r) : nil;
}

+ (NSInteger)activeLibraryProgram:(TICpuFrame)frame { return cu59::activeLibraryProgram(frame.SCOM[9]); }

+ (TILedStyle *)ledStyle:(NSInteger)style {
    const cu59::LedStyleParams& p = cu59::ledStyleParams(static_cast<cu59::LedStyle>(style));
    TILedStyle* t = [[TILedStyle alloc] init];
    t.slant = p.slant;
    t.activeR = p.activeR; t.activeG = p.activeG; t.activeB = p.activeB;
    t.inactiveR = p.inactiveR; t.inactiveG = p.inactiveG; t.inactiveB = p.inactiveB; t.inactiveAlpha = p.inactiveAlpha;
    t.glowBlurPerWidth = p.glowBlurPerWidth;
    t.glowOpacity = p.glowOpacity;
    t.bloomBlurPerWidth = p.bloomBlurPerWidth;
    return t;
}

+ (NSArray<NSArray<NSValue *> *> *)modernizedSegmentsWidth:(CGFloat)w height:(CGFloat)h {
    NSMutableArray* out = [NSMutableArray arrayWithCapacity:7];
    for (const auto& poly : cu59::modernizedSegments(w, h)) {
        NSMutableArray* pts = [NSMutableArray arrayWithCapacity:poly.size()];
        for (const auto& p : poly) {
            CGPoint pt = CGPointMake(p.x, p.y);
            [pts addObject:[NSValue valueWithBytes:&pt objCType:@encode(CGPoint)]];
        }
        [out addObject:pts];
    }
    return out;
}

+ (CGFloat)modernizedSegmentWidth:(CGFloat)w { return cu59::modernizedSegmentWidth(w); }

+ (NSArray<TILedDotSegment *> *)classicSegmentsWidth:(CGFloat)w height:(CGFloat)h {
    NSMutableArray* out = [NSMutableArray arrayWithCapacity:7];
    for (const auto& seg : cu59::classicSegments(w, h)) {
        TILedDotSegment* t = [[TILedDotSegment alloc] init];
        NSMutableArray* pts = [NSMutableArray arrayWithCapacity:seg.centres.size()];
        for (const auto& c : seg.centres) {
            CGPoint p = CGPointMake(c.x, c.y);
            [pts addObject:[NSValue valueWithBytes:&p objCType:@encode(CGPoint)]];
        }
        t.centres = pts;
        t.radius = seg.radius;
        [out addObject:t];
    }
    return out;
}

+ (CGRect)decimalPointWidth:(CGFloat)w height:(CGFloat)h {
    cu59::LedDot d = cu59::decimalPoint(w, h);
    return CGRectMake(d.cx - d.diameter / 2, d.cy - d.diameter / 2, d.diameter, d.diameter);
}

+ (CGFloat)decimalGlowBlurPerDiameter { return cu59::kDecimalGlowBlurPerDiameter; }
+ (CGFloat)decimalGlowOpacity { return cu59::kDecimalGlowOpacity; }

+ (CGFloat)printerCharGap { return cu59::PrinterGeometry::charGap; }
+ (CGFloat)printerDotPitchMM { return cu59::PrinterGeometry::dotPitchMM; }
+ (CGFloat)printerWidthUnits { return cu59::PrinterGeometry::widthUnits; }
+ (CGFloat)printerHeightUnits { return cu59::PrinterGeometry::heightUnits; }
+ (CGFloat)printerFeedHeightUnits { return cu59::PrinterGeometry::feedHeightUnits; }
+ (CGFloat)printerInterLineGap { return cu59::PrinterGeometry::interLineGap; }
+ (CGFloat)printerDotRadiusFraction { return cu59::PrinterGeometry::dotRadiusFraction; }

+ (NSInteger)heatmapCols { return cu59::kHeatmapCols; }
+ (NSInteger)heatmapRows { return cu59::kHeatmapRows; }
+ (uint8_t)heatStep:(uint32_t)count { return cu59::heatStep(count); }
+ (uint32_t)heatColor:(uint8_t)step {
    const cu59::Rgb& c = cu59::kHeatColors[step < 6 ? step : 5];
    return (static_cast<uint32_t>(c.r) << 16) | (static_cast<uint32_t>(c.g) << 8) | c.b;
}

+ (NSString *)programSourceLabel:(NSInteger)source flag:(uint8_t)flag {
    return ns(cu59::programSourceLabel(static_cast<cu59::ProgramSource>(source), flag));
}

+ (NSArray<TIInspectorEntry *> *)inspectorHistory:(TI59MachineWrapper *)machine {
    return entriesFrom(cu59::inspectorHistory(*machine.cppMachine));
}

+ (NSArray<TIInspectorEntry *> *)recentInstructions:(NSArray<NSValue *> *)frames count:(NSInteger)count {
    std::vector<CpuFrame> v;
    v.reserve(frames.count);
    for (NSValue* value in frames) {
        TICpuFrame f;
        [value getValue:&f size:sizeof f];
        v.push_back(cpuFrame(f));
    }
    return entriesFrom(cu59::recentInstructions(v, static_cast<size_t>(count)));
}

+ (void)softReset:(TI59MachineWrapper *)machine model:(NSInteger)model savedRam:(NSData *)savedRam {
    std::vector<uint8_t> ram;
    if (savedRam) {
        const auto* p = static_cast<const uint8_t*>(savedRam.bytes);
        ram.assign(p, p + savedRam.length);
    }
    cu59::softReset(*machine.cppMachine, static_cast<cu59::Model>(model), savedRam ? &ram : nullptr);
}

+ (void)cleanReset:(TI59MachineWrapper *)machine { cu59::cleanReset(*machine.cppMachine); }

@end
