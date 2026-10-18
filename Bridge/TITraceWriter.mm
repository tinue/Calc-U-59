#import "TITraceWriter+Cpp.h"
#include "../Shared/TraceWriter.hpp"
#import "BridgeConvert.h"


@implementation TITraceWriter {
    cu59::TraceWriter* _writer;
}

- (instancetype)initWithWriter:(cu59::TraceWriter *)writer {
    if ((self = [super init])) _writer = writer;
    return self;
}

+ (NSString *)baseFileNameForModel:(NSInteger)model {
    return ns(cu59::TraceWriter::baseFileName(static_cast<cu59::Model>(model)));
}

- (BOOL)openAtPath:(NSString *)path maxBytes:(uint64_t)maxBytes {
    return _writer->open(std::filesystem::path(path.fileSystemRepresentation), maxBytes);
}

- (void)close { _writer->close(); }
- (BOOL)isOpen { return _writer->isOpen(); }

- (void)writeCardInsert { _writer->writeCardInsert(); }
- (void)writeCardEject { _writer->writeCardEject(); }

@end
