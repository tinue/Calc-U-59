#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "TI59MachineWrapper.h"
#import "TIFileFormats.h"

NS_ASSUME_NONNULL_BEGIN

// Swift face of the Shared/ view rules both frontends follow: cue-card spans
// and layout, LED segment geometry, PC-100C paper geometry, heatmap colours,
// program-source labels, CPU inspector history and the reset helpers. The
// drawing stays in SwiftUI; these give it the same shapes and numbers as the
// Qt6 app. Type translation only.

/// A cue-card label and the grid columns (0–4) it covers.
@interface TILabelSpan : NSObject
@property (nonatomic, readonly) NSInteger startCol;
@property (nonatomic, readonly) NSInteger endCol;
@property (nonatomic, readonly, copy) NSString *label;
@end

/// Per-template cue-card geometry (fractions of the card; fonts at reference width).
@interface TICueCardLayout : NSObject
@property (nonatomic, readonly) CGFloat titleFontSize, gridFontSize, bankFontSize;
@property (nonatomic, readonly) CGFloat titleYFraction, titleWidthFraction, gridY0Fraction, gridY1Fraction;
@property (nonatomic, readonly, copy) NSArray<NSNumber *> *xFractions;   ///< 5 column centres
@property (nonatomic, readonly) CGFloat cellWidthFraction;
@property (nonatomic, readonly) BOOL drawsDividers;
@property (nonatomic, readonly) BOOL hasId;
@property (nonatomic, readonly) CGFloat referenceWidth;
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

/// One CPU-inspector row (frame: TICpuFrame in an NSValue; zeroed for the next instruction).
@interface TIInspectorEntry : NSObject
@property (nonatomic, readonly) uint16_t pc;
@property (nonatomic, readonly) uint16_t opcode;
@property (nonatomic, readonly, copy) NSString *disasm;
@property (nonatomic, readonly) TICpuFrame frame;
@property (nonatomic, readonly) BOOL isHistory;
@property (nonatomic, readonly) BOOL isCurrent;
@end

@interface TIViewRules : NSObject

// ── Cue cards (Shared/CueCard.hpp) ───────────────────────────────────────────
+ (NSArray<TILabelSpan *> *)labelSpansOf:(TICueCard *)card row:(NSInteger)row;
+ (NSArray<NSNumber *> *)dividersBetween:(NSArray<TILabelSpan *> *)spans NS_SWIFT_NAME(dividers(between:));
+ (TICueCardLayout *)cueCardLayoutFor:(NSInteger)templateKind;
+ (CGFloat)cellFittingFontSize:(NSArray<TILabelSpan *> *)spans templateKind:(NSInteger)templateKind
                     cardWidth:(CGFloat)cardWidth scaledGridFontSize:(CGFloat)scaled;
+ (NSInteger)displayLength:(NSString *)text;
/// The card to show (nil = none): the active program's, a generic module card, or the user's.
+ (nullable TICueCard *)resolveCueCardForProgram:(NSInteger)program
                                     moduleCards:(NSDictionary<NSNumber *, TICueCard *> *)cards
                                     moduleTitle:(NSString *)title moduleID:(NSString *)moduleID
                                        userCard:(nullable TICueCard *)userCard;
/// Library program number from SCOM[9] digits 4 and 3 (0 = none).
+ (NSInteger)activeLibraryProgram:(TICpuFrame)frame;

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
/// Height of a strip line: PRT_FEED blank, complete, or cut short (rowCount 1–6).
+ (CGFloat)printerLineHeightUnitsFeed:(BOOL)isFeed rowCount:(NSInteger)rowCount;
/// Copy-as-image pixels per dot pitch: 600 dpi, capped at 16000 px for the whole strip.
+ (CGFloat)printerCopyPixelsPerUnit:(CGFloat)stripHeightUnits;

// ── Heatmap (Shared/RomHeatmap.hpp) ──────────────────────────────────────────
@property (class, readonly) NSInteger heatmapCols;
@property (class, readonly) NSInteger heatmapRows;
+ (uint8_t)heatStep:(uint32_t)count;
/// RGB of a heat step, packed 0xRRGGBB.
+ (uint32_t)heatColor:(uint8_t)step;

// ── Debugger (Shared/ModuleImage.hpp, Shared/DebugSnapshots.hpp) ────────────
+ (NSString *)programSourceLabel:(NSInteger)source flag:(uint8_t)flag;

// ── Debug-panel text and colours (Shared/DebugText.hpp); colours 0xRRGGBB ───
+ (CGFloat)debugPanelFontSize:(CGFloat)width;
+ (NSString *)partitionLineProgramRegs:(NSInteger)programRegs dataRegs:(NSInteger)dataRegs;
/// mode: TILiveDebugSnapshot.angleMode (-1 = unknown).
+ (NSString *)angleModeLabel:(NSInteger)mode;
+ (NSString *)registerLine:(NSInteger)num value:(double)value hidden:(BOOL)hidden;
+ (NSString *)hirLine:(NSInteger)n value:(double)value;
+ (NSString *)tRegisterLine:(double)value;
+ (uint32_t)returnLevelColor:(uint8_t)sourceFlag zeroAddress:(BOOL)zero;
+ (uint32_t)stepHighlightColor:(NSInteger)source;
+ (BOOL)condFlag:(uint16_t)flags;
+ (BOOL)idleFlag:(uint16_t)flags;
/// 16 nibbles, most significant first.
+ (NSString *)registerNibbles:(NSData *)nibbles;
+ (NSString *)hexBin16:(uint16_t)value;
/// Frozen CPU view: the trace ring plus the next instruction.
+ (NSArray<TIInspectorEntry *> *)inspectorHistory:(TI59MachineWrapper *)machine;
/// Running CPU view: the newest `count` of `frames` (TICpuFrame NSValues).
+ (NSArray<TIInspectorEntry *> *)recentInstructions:(NSArray<NSValue *> *)frames count:(NSInteger)count;

// ── Reset (Shared/StateApplier.hpp) ──────────────────────────────────────────
/// Fresh machine: TI-58C runs the ROM startup, then restores `savedRam` (nil = none).
+ (void)powerOn:(TI59MachineWrapper *)machine model:(NSInteger)model savedRam:(nullable NSData *)savedRam
    NS_SWIFT_NAME(powerOn(_:model:savedRam:));
/// Reset button: TI-58C restores `savedRam` (nil = none); others clear registers past the partition.
+ (void)softReset:(TI59MachineWrapper *)machine model:(NSInteger)model savedRam:(nullable NSData *)savedRam;
+ (void)cleanReset:(TI59MachineWrapper *)machine;

@end

NS_ASSUME_NONNULL_END
