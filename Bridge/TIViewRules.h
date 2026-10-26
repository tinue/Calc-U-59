#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "TITypes.h"
#import "TIFileFormats.h"

NS_ASSUME_NONNULL_BEGIN

// Swift face of the Shared/ view rules both frontends follow: cue-card spans,
// layout and geometry, LED segment geometry, PC-100C paper geometry, heatmap
// colours, program-source decoding and labels, the debug panels' text. The
// drawing stays in SwiftUI; these give it the same shapes and numbers as the
// Qt6 app. Type translation only.

/// cu59::MobileLayout, same order.
typedef NS_ENUM(NSInteger, TIMobileLayout) {
    TIMobileLayoutPaged,
    TIMobileLayoutCalcPrinter,
    TIMobileLayoutCalcPrinterDebugger,
};

/// cu59::WidthRange, points.
typedef struct {
    CGFloat min, max;
} TIWidthRange;

/// A cue-card label and the grid columns (0–4) it covers.
@interface TILabelSpan : NSObject
@property (nonatomic, readonly) NSInteger startCol;
@property (nonatomic, readonly) NSInteger endCol;
@property (nonatomic, readonly, copy) NSString *label;
@end

/// Text placement on a w × h card (Shared/CueCard.hpp CueCardGeometry).
/// Frames: CGRect around the text's centre; height 0 = one text line.
@interface TICueCardGeometry : NSObject
@property (nonatomic, readonly) CGFloat titleFontSize, gridFontSize, bankFontSize;
@property (nonatomic, readonly) CGFloat titleY, gridY0, gridY1;
@property (nonatomic, readonly) CGFloat gridCenter, gridWidth, titleWidth;
@property (nonatomic, readonly) CGRect bankLeft, bankRight, row2Left, row2Right;
@property (nonatomic, readonly) CGFloat dividerHeight, washHeight, buttonPadX, buttonPadY;
@property (nonatomic, readonly) BOOL drawsDividers;   ///< the template's (Shared CueCardLayout)
@property (nonatomic, readonly) BOOL hasId;
@end

/// LED style parameters (Shared/LedGeometry.hpp); style 0 modernized, 1 classic.
@interface TILedStyle : NSObject
@property (nonatomic, readonly) CGFloat slant;
@property (nonatomic, readonly) CGFloat activeR, activeG, activeB;
@property (nonatomic, readonly) CGFloat inactiveR, inactiveG, inactiveB, inactiveAlpha;
@property (nonatomic, readonly) CGFloat glowBlurPerWidth, glowOpacity, bloomBlurPerWidth;
@end

/// A classic-style segment: dot centres (CGPoint values) of one radius.
@interface TILedDotSegment : NSObject
@property (nonatomic, readonly, copy) NSArray<NSValue *> *centres;
@property (nonatomic, readonly) CGFloat radius;
@end

@interface TIViewRules : NSObject

// ── Cue cards (Shared/CueCard.hpp) ───────────────────────────────────────────
+ (NSArray<TILabelSpan *> *)labelSpansOf:(TICueCard *)card row:(NSInteger)row;
+ (NSArray<NSNumber *> *)dividersBetween:(NSArray<TILabelSpan *> *)spans NS_SWIFT_NAME(dividers(between:));
+ (CGFloat)cellFittingFontSize:(NSArray<TILabelSpan *> *)spans templateKind:(NSInteger)templateKind
                     cardWidth:(CGFloat)cardWidth scaledGridFontSize:(CGFloat)scaled;
+ (TICueCardGeometry *)cueCardGeometry:(TICueCard *)card width:(CGFloat)width height:(CGFloat)height;
+ (CGFloat)cueCardDividerX:(NSInteger)index templateKind:(NSInteger)templateKind width:(CGFloat)width;
+ (CGRect)cueCardSpanFrame:(TILabelSpan *)span templateKind:(NSInteger)templateKind y:(CGFloat)y width:(CGFloat)width;
/// 0xRRGGBB: the card's ink, the SolidState dividers, the top wash (at cueCardWashAlpha).
+ (uint32_t)cueCardInk:(TICueCard *)card;
@property (class, readonly) uint32_t cueCardDividerColor;
@property (class, readonly) uint32_t cueCardWashColor;
@property (class, readonly) CGFloat cueCardWashAlpha;
// ── LED (Shared/LedGeometry.hpp, Shared/SevenSegment.hpp) ───────────────────
+ (TILedStyle *)ledStyle:(NSInteger)style;
/// Modernized: seven closed polygons (segments A–G) in a w × h digit cell.
+ (NSArray<NSArray<NSValue *> *> *)modernizedSegmentsWidth:(CGFloat)w height:(CGFloat)h NS_SWIFT_NAME(modernizedSegments(width:height:));
+ (CGFloat)modernizedSegmentWidth:(CGFloat)w;
+ (NSArray<TILedDotSegment *> *)classicSegmentsWidth:(CGFloat)w height:(CGFloat)h NS_SWIFT_NAME(classicSegments(width:height:));
/// Decimal point rect (unsheared) in a w × h digit cell.
+ (CGRect)decimalPointWidth:(CGFloat)w height:(CGFloat)h NS_SWIFT_NAME(decimalPoint(width:height:));
@property (class, readonly) CGFloat decimalGlowBlurPerDiameter;
@property (class, readonly) CGFloat decimalGlowOpacity;

// ── PC-100C paper (Shared/PrinterFont.hpp PrinterGeometry) ──────────────────
@property (class, readonly) CGFloat printerCharGap;
@property (class, readonly) CGFloat printerDotPitchMM;
@property (class, readonly) CGFloat printerWidthUnits;
@property (class, readonly) CGFloat printerHeightUnits;
@property (class, readonly) CGFloat printerFeedHeightUnits;
@property (class, readonly) CGFloat printerInterLineGap;
@property (class, readonly) CGFloat printerDotRadiusFraction;
@property (class, readonly) CGFloat printerPaperPaddingX;
@property (class, readonly) CGFloat printerPaperPaddingY;
/// Copy-as-image pixels per dot pitch: 600 dpi, capped at 16000 px for the whole strip.
+ (CGFloat)printerCopyPixelsPerUnit:(CGFloat)stripHeightUnits;

// ── Heatmap (Shared/RomHeatmap.hpp) ──────────────────────────────────────────
@property (class, readonly) NSInteger heatmapCols;
@property (class, readonly) NSInteger heatmapRows;
+ (uint8_t)heatStep:(uint32_t)count;
/// RGB of a heat step, packed 0xRRGGBB.
+ (uint32_t)heatColor:(uint8_t)step;

// ── Debugger (Shared/ModuleImage.hpp, Shared/DebugSnapshots.hpp) ────────────
/// ProgramSource raw value (C++ enumerator order) for a PRG SOURCE flag.
+ (NSInteger)programSourceForFlag:(uint8_t)flag romPC:(uint16_t)romPC;
+ (NSString *)programSourceLabel:(NSInteger)source flag:(uint8_t)flag;

// ── Debug-panel text and colours (Shared/DebugText.hpp); colours 0xRRGGBB ───
+ (CGFloat)debugPanelFontSize:(CGFloat)width;
/// cu59::mobileLayout — which panels an iOS window of this size shows.
+ (TIMobileLayout)mobileLayoutWidth:(CGFloat)width height:(CGFloat)height horizontalFold:(BOOL)fold;
/// cu59::mobilePrinterWidth — the printer column's width range in a side-by-side layout.
+ (TIWidthRange)mobilePrinterWidth:(TIMobileLayout)layout width:(CGFloat)width;
/// cu59::compactPrinterBar — short printer button labels for this tape width.
+ (BOOL)compactPrinterBar:(CGFloat)printerWidth;
/// cu59::mobileTopMargin — space above a side-by-side layout for a window's top inset.
+ (CGFloat)mobileTopMargin:(CGFloat)topInset;
+ (NSString *)partitionLineProgramRegs:(NSInteger)programRegs dataRegs:(NSInteger)dataRegs;
/// mode: TILiveDebugSnapshot.angleMode (-1 = unknown).
+ (NSString *)angleModeLabel:(NSInteger)mode;
+ (NSString *)registerLine:(NSInteger)num value:(double)value hidden:(BOOL)hidden;
+ (NSString *)hirLine:(NSInteger)n value:(double)value;
+ (NSString *)tRegisterLine:(double)value;
+ (NSString *)xRegisterLine:(double)value raw:(NSString *)raw;
+ (uint32_t)xRegisterColor:(double)value raw:(NSString *)raw;
+ (uint32_t)returnLevelColor:(uint8_t)sourceFlag zeroAddress:(BOOL)zero;
+ (uint32_t)stepHighlightColor:(NSInteger)source;
+ (NSString *)currentStepMarker:(BOOL)frozen;
+ (BOOL)condFlag:(uint16_t)flags;
+ (BOOL)idleFlag:(uint16_t)flags;
/// 16 nibbles, most significant first.
+ (NSString *)registerNibbles:(NSData *)nibbles;
+ (NSString *)hexBin16:(uint16_t)value;
@end

NS_ASSUME_NONNULL_END
