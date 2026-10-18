// ObjC++-only extension of TI59MachineWrapper: hands the underlying machine to
// the other Bridge/ wrappers so they can call Shared/ functions on it. Never
// import from the Swift bridging header.
#import "TI59MachineWrapper.h"
#include "../Core/TI59Machine.hpp"

@interface TI59MachineWrapper (Cpp)
@property (nonatomic, readonly) TI59Machine *cppMachine;
@end
