// ObjC++-only access to the C++ results behind TIFileFormats objects, for the
// other Bridge/ wrappers. Never import from the Swift bridging header.
#import "TIFileFormats.h"
#include "../Shared/StateFile.hpp"

@interface TIStateFileResult (Cpp)
@property (nonatomic, readonly) const cu59::LoadStateResult &cppResult;
@end
