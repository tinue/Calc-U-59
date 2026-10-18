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

- (void)pressKeyRow:(int)row col:(int)col {
    _machine->pressKey(row, col);
}

- (void)releaseKeyRow:(int)row col:(int)col {
    _machine->releaseKey(row, col);
}

- (NSData*)serialiseRAM {
    uint8_t buf[120 * 16];
    _machine->serialiseRAM(buf);
    return [NSData dataWithBytes:buf length:sizeof(buf)];
}

// ── State file load helpers ───────────────────────────────────────────────────

- (NSInteger)partitionProgramRegs {
    return _machine->partitionProgramRegs();
}

- (void)setPartitionProgramRegs:(NSInteger)n {
    _machine->setPartitionProgramRegs((int)n);
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

- (BOOL)isWaitingForCard { return _machine->isWaitingForCard() ? YES : NO; }
- (NSInteger)cardMode    { return _machine->cardMode(); }

// ── Printer ───────────────────────────────────────────────────────────────────

- (void)pressPrinterPrint:(BOOL)pressed       { _machine->pressPrinterPrint(pressed == YES); }
- (void)pressPrinterAdv:(BOOL)pressed         { _machine->pressPrinterAdv(pressed == YES); }
- (void)setPrinterTrace:(BOOL)enabled         { _machine->setPrinterTrace(enabled == YES); }
- (void)setPrinterConnected:(BOOL)connected   { _machine->setPrinterConnected(connected == YES); }
- (BOOL)isPrinterConnected                    { return _machine->isPrinterConnected() ? YES : NO; }

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

- (void)addBreakpoint:(uint16_t)pc    { _machine->addBreakpoint(pc); }
- (void)removeBreakpoint:(uint16_t)pc { _machine->removeBreakpoint(pc); }
- (void)clearBreakpoints              { _machine->clearBreakpoints(); }

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

// ── Old trace API (deprecated; kept for binary compatibility) ────────────────

+ (NSString*)disassemblePC:(uint16_t)pc opcode:(uint16_t)opcode {
    std::string s = TI59Machine::disassemble(pc, opcode);
    return ns(s);
}

// ── Calculator-level API ──────────────────────────────────────────────────────

- (double)dataRegister:(NSInteger)regNum {
    return _machine->readDataReg((int)regNum);
}

- (NSData*)allProgramSteps {
    // The partition nibble can transiently claim more registers than the model
    // has (raw SCOM value up to 15 → 150 regs); clamp to the accessible RAM.
    int count = (int)MIN(_machine->partitionProgramRegs(), _machine->ramRegCount()) * 8;
    NSMutableData* data = [NSMutableData dataWithLength:count];
    uint8_t* bytes = (uint8_t*)data.mutableBytes;
    for (int i = 0; i < count; i++)
        bytes[i] = _machine->readProgramStep(i);
    return data;
}

- (TICpuFrame)snapshotCPU {
    return tiCpuFrame(_machine->snapshotCPU());
}

- (void)beginNextStep {
    _machine->beginNextStep();
}

// ── Raw RAM access ────────────────────────────────────────────────────────────

- (NSInteger)ramRegisterCount {
    return _machine->ramRegCount();
}

- (NSData*)rawRegister:(NSInteger)reg {
    uint8_t n[16];
    _machine->copyRAMReg((int)reg, n);
    return [NSData dataWithBytes:n length:16];
}

- (void)setRawRegister:(NSInteger)reg nibbles:(NSData*)nibbles {
    if (nibbles.length == 16)
        _machine->writeRAMReg((int)reg, (const uint8_t*)nibbles.bytes);
}

// ── Printer buffer ────────────────────────────────────────────────────────────

- (NSString*)printerBufferContent {
    std::string s = _machine->printerBufferContent();
    return ns(s);
}

@end

@implementation TI59MachineWrapper (Cpp)
- (instancetype)initWithSharedMachine:(std::shared_ptr<TI59Machine>)machine {
    if ((self = [super init])) _machine = std::move(machine);
    return self;
}
- (TI59Machine *)cppMachine { return _machine.get(); }
@end
