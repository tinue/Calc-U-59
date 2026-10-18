// ObjC++-only access to the C++ results behind TIFileFormats objects, for the
// other Bridge/ wrappers. Never import from the Swift bridging header.
#import "TIFileFormats.h"
#include "../Shared/StateFile.hpp"

@interface TIStateFileResult (Cpp)
@property (nonatomic, readonly) const cu59::LoadStateResult &cppResult;
@end

/// TICueCard ↔ cu59::CueCardContent.
TICueCard* TICueCardFrom(const cu59::CueCardContent& c);
cu59::CueCardContent CueCardFrom(TICueCard* t);
