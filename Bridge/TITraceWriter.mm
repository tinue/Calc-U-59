#import "TITraceWriter+Cpp.h"
#include "../Shared/TraceWriter.hpp"
#include <cstddef>
#include <cstring>
#include <memory>

// TICpuFrame mirrors CpuFrame field for field, so a frame converts with one copy.
static_assert(sizeof(TICpuFrame) == sizeof(CpuFrame), "TICpuFrame must mirror CpuFrame");
#define SAME_OFFSET(f) static_assert(offsetof(TICpuFrame, f) == offsetof(CpuFrame, f), "TICpuFrame." #f)
SAME_OFFSET(seqno); SAME_OFFSET(pc); SAME_OFFSET(opcode); SAME_OFFSET(digit); SAME_OFFSET(postDigit);
SAME_OFFSET(cycleWeight); SAME_OFFSET(KR); SAME_OFFSET(SR); SAME_OFFSET(fA); SAME_OFFSET(fB);
SAME_OFFSET(cpuFlags); SAME_OFFSET(R5); SAME_OFFSET(A); SAME_OFFSET(B); SAME_OFFSET(C); SAME_OFFSET(D);
SAME_OFFSET(E); SAME_OFFSET(SCOM); SAME_OFFSET(Sout); SAME_OFFSET(EXT); SAME_OFFSET(PREG); SAME_OFFSET(flags);
SAME_OFFSET(m_libAddr); SAME_OFFSET(REG_ADDR); SAME_OFFSET(RAM_ADDR); SAME_OFFSET(RAM_OP);
SAME_OFFSET(m_libAddrReadPos); SAME_OFFSET(displayOn); SAME_OFFSET(maxDigitDecay);
#undef SAME_OFFSET

@implementation TITraceWriter {
    std::unique_ptr<cu59::TraceWriter> _owned;
    cu59::TraceWriter* _writer;
}

- (instancetype)initWithModel:(NSInteger)model {
    if ((self = [super init])) {
        _owned = std::make_unique<cu59::TraceWriter>(static_cast<cu59::Model>(model));
        _writer = _owned.get();
    }
    return self;
}

- (instancetype)initWithWriter:(cu59::TraceWriter *)writer {
    if ((self = [super init])) _writer = writer;
    return self;
}

+ (NSString *)baseFileNameForModel:(NSInteger)model {
    return [NSString stringWithUTF8String:cu59::TraceWriter::baseFileName(static_cast<cu59::Model>(model)).c_str()];
}

- (BOOL)openAtPath:(NSString *)path maxBytes:(uint64_t)maxBytes {
    return _writer->open(std::filesystem::path(path.fileSystemRepresentation), maxBytes);
}

- (void)close { _writer->close(); }
- (BOOL)isOpen { return _writer->isOpen(); }

- (BOOL)writeFrame:(TICpuFrame)frame {
    CpuFrame f;
    std::memcpy(&f, &frame, sizeof f);
    return _writer->write(f);
}

- (void)writeLostGap:(uint32_t)count { _writer->writeLostGap(count); }
- (void)writeKeyDownRow:(uint8_t)row col:(uint8_t)col { _writer->writeKeyDown(row, col); }
- (void)writeKeyUpRow:(uint8_t)row col:(uint8_t)col { _writer->writeKeyUp(row, col); }
- (void)writeCardInsert { _writer->writeCardInsert(); }
- (void)writeCardEject { _writer->writeCardEject(); }

@end
