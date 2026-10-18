#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Swift face of the Shared/ data tables (keyboard map, 7-segment
/// patterns, printer font, canvas/key layout, per-model facts). Type
/// translation only — the tables and rules live in Shared/.
@interface TISharedTables : NSObject

// ── Physical keyboard (Shared/KeyboardMap.hpp) ──────────────────────────────
/// One or two matrix codes for a key press; empty if unbound.
/// `command` = any of Command / Control / Option held.
+ (NSData *)matrixCodesForKey:(uint32_t)key produced:(uint32_t)produced
                     isLetter:(BOOL)isLetter shift:(BOOL)shift command:(BOOL)command;

// ── LED display (Shared/SevenSegment.hpp) ───────────────────────────────────
+ (uint8_t)segmentsForDigit:(uint8_t)digit ctrl:(uint8_t)ctrl suppressed:(BOOL)suppressed;
@property (class, readonly) uint8_t segmentsC;

// ── PC-100C printer font (Shared/PrinterFont.hpp) ───────────────────────────
/// Row 0–6 of a 6-bit character code: bit 4 = leftmost column.
+ (uint8_t)printerFontRowForCode:(uint8_t)code row:(NSInteger)row;

// ── Canvas / key layout (Shared/KeyboardLayout.hpp) ─────────────────────────
@property (class, readonly) CGFloat canvasAspect;
@property (class, readonly) CGRect displayRect;
@property (class, readonly) CGRect cardRect;
@property (class, readonly) CGFloat keyboardYStart;
@property (class, readonly) CGFloat keyboardYScale;
/// Key rect in keyboard-image space; row 0–8, col 0–4.
+ (CGRect)keyRectAtRow:(NSInteger)row col:(NSInteger)col NS_SWIFT_NAME(keyRect(row:col:));
/// Matrix code (state-file key code) of the key at row 0–8, col 0–4.
+ (uint8_t)matrixCodeAtRow:(NSInteger)row col:(NSInteger)col NS_SWIFT_NAME(matrixCode(row:col:));
/// row×5 + col of the key whose widened hit rect contains the point, or -1.
+ (NSInteger)keyIndexAtX:(CGFloat)nx y:(CGFloat)ny NS_SWIFT_NAME(keyIndex(x:y:));

// ── Per-model facts (Shared/MachineModelInfo.hpp); model = MachineModel raw value
/// Highest program step the RAM can hold (959 or 479).
+ (NSInteger)maxStepForModel:(NSInteger)model;

@end

NS_ASSUME_NONNULL_END
