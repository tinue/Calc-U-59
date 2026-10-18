#import <Foundation/Foundation.h>
#import "TI59MachineWrapper.h"

NS_ASSUME_NONNULL_BEGIN

/// Swift face of Shared/TraceWriter (binary trace format v2). Type
/// translation only. Thread-safe.
@interface TITraceWriter : NSObject

/// model = MachineModel raw value.
- (instancetype)initWithModel:(NSInteger)model;

/// CALCU59_TRACE.bin / CALCU58_TRACE.bin / CALCU58C_TRACE.bin.
+ (NSString *)baseFileNameForModel:(NSInteger)model;

/// Fresh file at `path` with header and SESSION_START; the session stops at maxBytes.
- (BOOL)openAtPath:(NSString *)path maxBytes:(uint64_t)maxBytes;
- (void)close;
@property (readonly) BOOL isOpen;

/// NO if this frame reached the size limit and the session was closed.
- (BOOL)writeFrame:(TICpuFrame)frame;
- (void)writeLostGap:(uint32_t)count;
- (void)writeKeyDownRow:(uint8_t)row col:(uint8_t)col;
- (void)writeKeyUpRow:(uint8_t)row col:(uint8_t)col;
- (void)writeCardInsert;
- (void)writeCardEject;

@end

NS_ASSUME_NONNULL_END
