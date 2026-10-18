// ObjC++-only: wrap a trace writer owned elsewhere (EmulatorSession). Never
// import from the Swift bridging header.
#import "TITraceWriter.h"
#include "../Shared/TraceWriter.hpp"

@interface TITraceWriter (Cpp)
/// Non-owning: `writer` must outlive the wrapper.
- (instancetype)initWithWriter:(cu59::TraceWriter *)writer;
@end
