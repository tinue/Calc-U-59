// ObjC++-only TICueCard conversion for the other Bridge/ wrappers. Never
// import from the Swift bridging header.
#import "TIFileFormats.h"
#include "../Shared/CueCard.hpp"

/// TICueCard ↔ cu59::CueCardContent.
TICueCard* TICueCardFrom(const cu59::CueCardContent& c);
cu59::CueCardContent CueCardFrom(TICueCard* t);
