#import "TI59MachineWrapper+Cpp.h"
#import "BridgeConvert.h"
#include <memory>

@implementation TI59MachineWrapper {
    std::shared_ptr<TI59Machine> _machine;
}

- (void)reset {
    _machine->reset();
}

- (uint32_t)step {
    return _machine->step();
}

- (uint32_t)stepUntilNextKeycode {
    return _machine->stepUntilNextKeycode();
}

- (NSData*)serialiseRAM {
    uint8_t buf[120 * 16];
    _machine->serialiseRAM(buf);
    return [NSData dataWithBytes:buf length:sizeof(buf)];
}

- (void)insertCard:(NSData*)data {
    if (data.length > 0)
        _machine->insertCard((const uint8_t*)data.bytes, data.length);
    else
        _machine->insertCard(nullptr, 0);
}

- (NSData*)cardEject {
    auto bytes = _machine->cardEject();
    return [NSData dataWithBytes:bytes.data() length:bytes.size()];
}

- (NSInteger)cardMode    { return _machine->cardMode(); }

// ── Printer ───────────────────────────────────────────────────────────────────

- (void)pressPrinterPrint:(BOOL)pressed       { _machine->pressPrinterPrint(pressed == YES); }
- (void)pressPrinterAdv:(BOOL)pressed         { _machine->pressPrinterAdv(pressed == YES); }
- (void)setPrinterTrace:(BOOL)enabled         { _machine->setPrinterTrace(enabled == YES); }
- (void)setPrinterConnected:(BOOL)connected   { _machine->setPrinterConnected(connected == YES); }

// ── Debug event log ───────────────────────────────────────────────────────────

- (void)setDebugLevel:(uint8_t)level {
    _machine->setDebugLevel(level);
}

// ── Trace / debug API ─────────────────────────────────────────────────────────

- (TITraceFlags)traceFlags {
    return (TITraceFlags)_machine->traceFlags();
}

- (void)setTraceFlags:(TITraceFlags)flags {
    _machine->setTraceFlags((uint32_t)flags);
}

- (uint16_t)currentPC {
    return _machine->pc();
}


- (BOOL)loadDebugOverlayWords:(NSData*)words {
    if ((words.length % sizeof(uint16_t)) != 0) return NO;
    const uint16_t* data = (const uint16_t*)words.bytes;
    size_t count = words.length / sizeof(uint16_t);
    return _machine->loadDebugOverlay(data, count) ? YES : NO;
}

- (void)clearDebugOverlay {
    _machine->clearDebugOverlay();
}

// ── New CPU frame API ────────────────────────────────────────────────────────


- (NSArray<NSValue*>*)readCpuFramesMax:(NSUInteger)max {
    if (max == 0) return @[];

    const uint32_t cap = (uint32_t)MIN(max, 1024u);
    std::vector<CpuFrame> frames(cap);

    uint32_t n = _machine->readCpuFrames(frames.data(), cap);
    if (n == 0) return @[];

    NSMutableArray<NSValue*>* result = [NSMutableArray arrayWithCapacity:n];
    for (uint32_t i = 0; i < n; i++) {
        TICpuFrame frame = tiCpuFrame(frames[i]);
        [result addObject:[NSValue valueWithBytes:&frame objCType:@encode(TICpuFrame)]];
    }
    return result;
}

// ── Calculator-level API ──────────────────────────────────────────────────────

- (TICpuFrame)snapshotCPU {
    return tiCpuFrame(_machine->snapshotCPU());
}

- (void)beginNextStep {
    _machine->beginNextStep();
}

@end

@implementation TI59MachineWrapper (Cpp)
- (instancetype)initWithSharedMachine:(std::shared_ptr<TI59Machine>)machine {
    if ((self = [super init])) _machine = std::move(machine);
    return self;
}
- (TI59Machine *)cppMachine { return _machine.get(); }
@end
