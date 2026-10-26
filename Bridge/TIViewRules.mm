#import "TIViewRules.h"
#import "BridgeConvert.h"
#import "TIFileFormats+Cpp.h"
#include "../Shared/DebugSnapshots.hpp"
#include "../Shared/DebugText.hpp"
#include "../Shared/LedGeometry.hpp"
#include "../Shared/ModuleImage.hpp"
#include "../Shared/PrinterFont.hpp"
#include "../Shared/RomHeatmap.hpp"


@interface TILabelSpan ()
@property (nonatomic, readwrite) NSInteger startCol;
@property (nonatomic, readwrite) NSInteger endCol;
@property (nonatomic, readwrite, copy) NSString *label;
@end
@implementation TILabelSpan
@end

@interface TICueCardGeometry ()
@property (nonatomic, readwrite) CGFloat titleFontSize, gridFontSize, bankFontSize;
@property (nonatomic, readwrite) CGFloat titleY, gridY0, gridY1;
@property (nonatomic, readwrite) CGFloat gridCenter, gridWidth, titleWidth;
@property (nonatomic, readwrite) CGRect bankLeft, bankRight, row2Left, row2Right;
@property (nonatomic, readwrite) CGFloat dividerHeight, washHeight, buttonPadX, buttonPadY;
@property (nonatomic, readwrite) BOOL drawsDividers;
@property (nonatomic, readwrite) BOOL hasId;
@end
@implementation TICueCardGeometry
@end

static CGRect cgFrame(const cu59::CueCardFrame& f) {
    return CGRectMake(f.cx - f.width / 2, f.cy - f.height / 2, f.width, f.height);
}

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

static std::vector<cu59::LabelSpan> spansFrom(NSArray<TILabelSpan*>* spans) {
    std::vector<cu59::LabelSpan> out;
    for (TILabelSpan* s in spans) out.push_back({static_cast<int>(s.startCol), static_cast<int>(s.endCol), cpp(s.label)});
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

+ (CGFloat)cellFittingFontSize:(NSArray<TILabelSpan *> *)spans templateKind:(NSInteger)templateKind
                     cardWidth:(CGFloat)cardWidth scaledGridFontSize:(CGFloat)scaled {
    return cu59::cellFittingFontSize(spansFrom(spans), cu59::cueCardLayout(static_cast<cu59::CueCardTemplate>(templateKind)),
                                     cardWidth, scaled);
}

+ (TICueCardGeometry *)cueCardGeometry:(TICueCard *)card width:(CGFloat)width height:(CGFloat)height {
    cu59::CueCardContent c = CueCardFrom(card);
    cu59::CueCardGeometry g = cu59::cueCardGeometry(c, width, height);
    const cu59::CueCardLayout& l = cu59::cueCardLayout(c.template_);
    TICueCardGeometry* t = [[TICueCardGeometry alloc] init];
    t.titleFontSize = g.titleFontSize; t.gridFontSize = g.gridFontSize; t.bankFontSize = g.bankFontSize;
    t.titleY = g.titleY; t.gridY0 = g.gridY0; t.gridY1 = g.gridY1;
    t.gridCenter = g.gridCenter; t.gridWidth = g.gridWidth;
    t.titleWidth = g.titleWidth;
    t.bankLeft = cgFrame(g.bankLeft); t.bankRight = cgFrame(g.bankRight);
    t.row2Left = cgFrame(g.row2Left); t.row2Right = cgFrame(g.row2Right);
    t.dividerHeight = g.dividerHeight; t.washHeight = g.washHeight;
    t.buttonPadX = g.buttonPadX; t.buttonPadY = g.buttonPadY;
    t.drawsDividers = l.drawsDividers; t.hasId = l.hasId;
    return t;
}

+ (CGFloat)cueCardDividerX:(NSInteger)index templateKind:(NSInteger)templateKind width:(CGFloat)width {
    return cu59::cueCardDividerX(cu59::cueCardLayout(static_cast<cu59::CueCardTemplate>(templateKind)),
                                 static_cast<int>(index), width);
}

+ (CGRect)cueCardSpanFrame:(TILabelSpan *)span templateKind:(NSInteger)templateKind y:(CGFloat)y width:(CGFloat)width {
    cu59::LabelSpan s{static_cast<int>(span.startCol), static_cast<int>(span.endCol), cpp(span.label)};
    return cgFrame(cu59::cueCardSpanFrame(cu59::cueCardLayout(static_cast<cu59::CueCardTemplate>(templateKind)), s, y, width));
}

+ (uint32_t)cueCardInk:(TICueCard *)card { return cu59::cueCardInk(CueCardFrom(card)); }
+ (uint32_t)cueCardDividerColor { return cu59::kCueCardDividerColor; }
+ (uint32_t)cueCardWashColor { return cu59::kCueCardWashColor; }
+ (CGFloat)cueCardWashAlpha { return cu59::kCueCardWashAlpha; }

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
+ (CGFloat)printerPaperPaddingX { return cu59::PrinterGeometry::paperPaddingX; }
+ (CGFloat)printerPaperPaddingY { return cu59::PrinterGeometry::paperPaddingY; }
+ (CGFloat)printerCopyPixelsPerUnit:(CGFloat)stripHeightUnits {
    return cu59::PrinterGeometry::copyPixelsPerUnit(stripHeightUnits);
}
+ (CGFloat)printerInterLineGap { return cu59::PrinterGeometry::interLineGap; }
+ (CGFloat)printerDotRadiusFraction { return cu59::PrinterGeometry::dotRadiusFraction; }

+ (NSInteger)heatmapCols { return cu59::kHeatmapCols; }
+ (NSInteger)heatmapRows { return cu59::kHeatmapRows; }
+ (uint8_t)heatStep:(uint32_t)count { return cu59::heatStep(count); }
+ (uint32_t)heatColor:(uint8_t)step {
    const cu59::Rgb& c = cu59::kHeatColors[step < 6 ? step : 5];
    return (static_cast<uint32_t>(c.r) << 16) | (static_cast<uint32_t>(c.g) << 8) | c.b;
}

+ (NSInteger)programSourceForFlag:(uint8_t)flag romPC:(uint16_t)romPC {
    return static_cast<NSInteger>(cu59::programSourceFrom(flag, romPC));
}

+ (NSString *)programSourceLabel:(NSInteger)source flag:(uint8_t)flag {
    return ns(cu59::programSourceLabel(static_cast<cu59::ProgramSource>(source), flag));
}

+ (CGFloat)debugPanelFontSize:(CGFloat)width { return cu59::debugPanelFontSize(width); }
+ (TIMobileLayout)mobileLayoutWidth:(CGFloat)width height:(CGFloat)height horizontalFold:(BOOL)fold {
    return static_cast<TIMobileLayout>(cu59::mobileLayout(width, height, fold));
}
+ (TIWidthRange)mobilePrinterWidth:(TIMobileLayout)layout width:(CGFloat)width {
    auto r = cu59::mobilePrinterWidth(static_cast<cu59::MobileLayout>(layout), width);
    return {r.min, r.max};
}
+ (NSString *)partitionLineProgramRegs:(NSInteger)programRegs dataRegs:(NSInteger)dataRegs {
    return ns(cu59::partitionLine(static_cast<int>(programRegs), static_cast<int>(dataRegs)));
}
+ (NSString *)angleModeLabel:(NSInteger)mode {
    std::optional<cu59::AngleMode> m;
    if (mode >= 0 && mode <= 2) m = static_cast<cu59::AngleMode>(mode);
    return ns(cu59::angleModeLabel(m));
}
+ (NSString *)registerLine:(NSInteger)num value:(double)value hidden:(BOOL)hidden {
    return ns(cu59::registerLine({static_cast<int>(num), value, hidden == YES}));
}
+ (NSString *)hirLine:(NSInteger)n value:(double)value { return ns(cu59::hirLine(static_cast<int>(n), value)); }
+ (NSString *)tRegisterLine:(double)value { return ns(cu59::tRegisterLine(value)); }
+ (NSString *)xRegisterLine:(double)value raw:(NSString *)raw { return ns(cu59::xRegisterLine(value, raw.UTF8String)); }
+ (uint32_t)xRegisterColor:(double)value raw:(NSString *)raw { return cu59::xRegisterColor(value, raw.UTF8String); }
+ (uint32_t)returnLevelColor:(uint8_t)sourceFlag zeroAddress:(BOOL)zero { return cu59::returnLevelColor(sourceFlag, zero == YES); }
+ (NSString *)currentStepMarker:(BOOL)frozen { return ns(cu59::currentStepMarker(frozen == YES)); }
+ (uint32_t)stepHighlightColor:(NSInteger)source { return cu59::stepHighlightColor(static_cast<cu59::ProgramSource>(source)); }
+ (BOOL)condFlag:(uint16_t)flags { return cu59::condFlag(flags); }
+ (BOOL)idleFlag:(uint16_t)flags { return cu59::idleFlag(flags); }
+ (NSString *)registerNibbles:(NSData *)nibbles {
    uint8_t n[16] = {};
    memcpy(n, nibbles.bytes, MIN(nibbles.length, sizeof n));
    return ns(cu59::registerNibbles(n));
}
+ (NSString *)hexBin16:(uint16_t)value { return ns(cu59::hexBin16(value)); }

@end
