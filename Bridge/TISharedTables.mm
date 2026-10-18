#import "TISharedTables.h"
#include "../Shared/Bcd.hpp"
#include "../Shared/KeyNames.hpp"
#include "../Shared/KeyboardLayout.hpp"
#include "../Shared/KeyboardMap.hpp"
#include "../Shared/MachineModelInfo.hpp"
#include "../Shared/PrinterFont.hpp"
#include "../Shared/SevenSegment.hpp"

namespace {
CGRect toCG(const cu59::NRect& r) { return CGRectMake(r.x, r.y, r.w, r.h); }
NSRange toNS(const cu59::PcRange& r) { return NSMakeRange(r.lo, r.hi - r.lo + 1); }
const cu59::ModelInfo& modelInfo(NSInteger model) { return cu59::info(static_cast<cu59::Model>(model)); }
}

@implementation TISharedTables

+ (NSString *)mnemonicForKeycode:(uint8_t)keycode {
    return [NSString stringWithUTF8String:cu59::mnemonic(keycode).c_str()];
}

+ (NSInteger)stepsAfterKeycode:(uint8_t)keycode {
    return cu59::stepsAfter(keycode);
}

+ (NSIndexSet *)argumentStepsIn:(NSData *)keycodes {
    const auto* p = static_cast<const uint8_t*>(keycodes.bytes);
    std::vector<uint8_t> steps(p, p + keycodes.length);
    NSMutableIndexSet* set = [NSMutableIndexSet indexSet];
    for (int i : cu59::argumentSteps(steps)) [set addIndex:static_cast<NSUInteger>(i)];
    return set;
}

+ (NSString *)registerLineHex:(NSData *)nibbles {
    cu59::Nibbles16 n{};
    memcpy(n.data(), nibbles.bytes, MIN(nibbles.length, n.size()));
    return [NSString stringWithUTF8String:cu59::registerLineHex(n).c_str()];
}

+ (NSData *)matrixCodesForKey:(uint32_t)key produced:(uint32_t)produced
                     isLetter:(BOOL)isLetter shift:(BOOL)shift command:(BOOL)command {
    auto codes = cu59::matrixCodesFor({key, produced, isLetter == YES, shift == YES, command == YES});
    return [NSData dataWithBytes:codes.data() length:codes.size()];
}

+ (uint8_t)segmentsForDigit:(uint8_t)digit ctrl:(uint8_t)ctrl suppressed:(BOOL)suppressed {
    return cu59::segmentsFor(digit, ctrl, suppressed == YES);
}

+ (uint8_t)segmentsC { return cu59::kSegmentsC; }

+ (uint8_t)printerFontRowForCode:(uint8_t)code row:(NSInteger)row {
    if (code >= 64 || row < 0 || row >= 7) return 0;
    return cu59::kPC100CFont[code][row];
}

+ (CGFloat)canvasAspect   { return cu59::kCanvasAspect; }
+ (CGRect)displayRect     { return toCG(cu59::kDisplayRect); }
+ (CGRect)cardRect        { return toCG(cu59::kCardRect); }
+ (CGFloat)keyboardYStart { return cu59::kKeyboardYStart; }
+ (CGFloat)keyboardYScale { return cu59::kKeyboardYScale; }

+ (CGRect)keyRectAtRow:(NSInteger)row col:(NSInteger)col {
    if (row < 0 || row >= 9 || col < 0 || col >= 5) return CGRectZero;
    return toCG(cu59::kKeyRects[row][col]);
}

+ (NSInteger)keyIndexAtX:(CGFloat)nx y:(CGFloat)ny {
    cu59::KeyHit hit{};
    return cu59::keyAt(nx, ny, hit) ? hit.row * 5 + hit.col : -1;
}

+ (double)instructionHzForModel:(NSInteger)model { return modelInfo(model).instructionHz; }
+ (NSRange)scanLoopRangeForModel:(NSInteger)model { return toNS(modelInfo(model).scanLoop); }
+ (NSRange)idleAndKeyDetectRangeForModel:(NSInteger)model { return toNS(modelInfo(model).idleAndKeyDetect); }

@end
