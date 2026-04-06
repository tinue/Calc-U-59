#import "TI59MachineWrapper.h"
#include "../Core/TI59Machine.hpp"
#include <memory>

// Physical col 1–5 → TMC0501 K-line bit index (KO=1 KP=2 KQ=3 KS=5 KT=6)
static const int kbits[] = {0, 1, 2, 3, 5, 6};  // index 0 unused; index col

@implementation TI59MachineWrapper {
    std::unique_ptr<TI59Machine> _machine;
}

- (instancetype)initWithModel:(NSInteger)model {
    self = [super init];
    if (self) {
        MachineVariant v;
        switch (model) {
            case 1:  v = MachineVariant::TI58;  break;
            case 2:  v = MachineVariant::TI58C; break;
            default: v = MachineVariant::TI59;  break;
        }
        _machine = std::make_unique<TI59Machine>(v);
    }
    return self;
}

- (void)loadROM:(NSData*)romData {
    const uint16_t* words = (const uint16_t*)romData.bytes;
    size_t count = romData.length / sizeof(uint16_t);
    _machine->loadROM(words, count);
}

- (void)loadLibrary:(NSData*)libData {
    const uint8_t* bytes = (const uint8_t*)libData.bytes;
    size_t count = libData.length;
    _machine->loadLibrary(bytes, count);
}

- (void)reset {
    _machine->reset();
}

- (uint32_t)step {
    return _machine->step();
}

- (uint32_t)stepN:(uint32_t)n {
    return _machine->stepN(n);
}

- (void)pressKeyRow:(int)row col:(int)col {
    _machine->pressKey(row, col);
}

- (void)releaseKeyRow:(int)row col:(int)col {
    _machine->releaseKey(row, col);
}

- (TIDisplaySnapshot)getDisplay {
    DisplaySnapshot s = _machine->getDisplay();
    TIDisplaySnapshot out;
    _Static_assert(sizeof(s.digits) == sizeof(out.digits), "digits size mismatch");
    _Static_assert(sizeof(s.ctrl)   == sizeof(out.ctrl),   "ctrl size mismatch");
    memcpy(out.digits, s.digits, sizeof(out.digits));
    memcpy(out.ctrl,   s.ctrl,   sizeof(out.ctrl));
    out.dpPos         = s.dpPos;
    out.calcIndicator = s.calcIndicator;
    return out;
}

- (NSData*)serialiseRAM {
    uint8_t buf[120 * 16];
    _machine->serialiseRAM(buf);
    return [NSData dataWithBytes:buf length:sizeof(buf)];
}

- (void)deserialiseRAM:(NSData*)data {
    if (data.length == 120 * 16)
        _machine->deserialiseRAM((const uint8_t*)data.bytes);
}

// ── State file load helpers ───────────────────────────────────────────────────

- (void)writeProgramSteps:(NSData*)keycodes {
    _machine->writeProgram((const uint8_t*)keycodes.bytes, (int)keycodes.length);
}

- (void)writeDataRegister:(NSInteger)regNum nibbles:(NSData*)nibbles16 {
    if (nibbles16.length == 16)
        _machine->writeDataRegister((int)regNum, (const uint8_t*)nibbles16.bytes);
}

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

- (BOOL)isCardPresent    { return _machine->isCardPresent()    ? YES : NO; }
- (BOOL)isWaitingForCard { return _machine->isWaitingForCard() ? YES : NO; }
- (NSInteger)cardMode    { return _machine->cardMode(); }

// ── Printer ───────────────────────────────────────────────────────────────────

- (NSArray<NSString*>*)drainPrinterLines {
    auto lines = _machine->drainPrinterLines();
    NSMutableArray<NSString*>* result = [NSMutableArray arrayWithCapacity:lines.size()];
    for (const auto& s : lines)
        [result addObject:[NSString stringWithUTF8String:s.c_str()]];
    return result;
}

- (NSArray<NSData*>*)drainPrinterCodeLines {
    auto lines = _machine->drainPrinterCodeLines();
    NSMutableArray<NSData*>* result = [NSMutableArray arrayWithCapacity:lines.size()];
    for (const auto& arr : lines)
        [result addObject:[NSData dataWithBytes:arr.data() length:arr.size()]];
    return result;
}

- (void)pressPrinterPrint:(BOOL)pressed       { _machine->pressPrinterPrint(pressed == YES); }
- (void)pressPrinterAdv:(BOOL)pressed         { _machine->pressPrinterAdv(pressed == YES); }
- (void)setPrinterTrace:(BOOL)enabled         { _machine->setPrinterTrace(enabled == YES); }
- (void)setPrinterConnected:(BOOL)connected   { _machine->setPrinterConnected(connected == YES); }
- (BOOL)isPrinterConnected                    { return _machine->isPrinterConnected() ? YES : NO; }

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

- (NSArray<NSValue*>*)drainTraceEventsMax:(NSUInteger)max {
    return [self drainTraceEventsMax:max snapshots:nil];
}

- (NSArray<NSValue*>*)drainTraceEventsMax:(NSUInteger)max
                                snapshots:(NSArray<NSValue*>* _Nullable * _Nullable)outSnaps {
    if (max == 0) return @[];

    // Allocate temporary buffers on the stack for small drains; heap for large.
    const uint32_t cap = (uint32_t)MIN(max, 512u);
    std::vector<TraceEvent>   evBuf(cap);
    std::vector<CPUSnapshot>  snapBuf(cap);

    uint32_t n = _machine->drainTraceEvents(evBuf.data(), outSnaps ? snapBuf.data() : nullptr, cap);
    if (n == 0) {
        if (outSnaps) *outSnaps = @[];
        return @[];
    }

    NSMutableArray<NSValue*>* result  = [NSMutableArray arrayWithCapacity:n];
    NSMutableArray<NSValue*>* snaps   = outSnaps ? [NSMutableArray arrayWithCapacity:n] : nil;

    for (uint32_t i = 0; i < n; i++) {
        // Copy C++ struct into Obj-C counterpart (same layout, verified at compile time)
        TITraceEvent te;
        te.pc           = evBuf[i].pc;
        te.opcode       = evBuf[i].opcode;
        te.digit        = evBuf[i].digit;
        te.cycleWeight  = evBuf[i].cycleWeight;
        te.seqno        = evBuf[i].seqno;
        te.KR           = evBuf[i].KR;
        te.SR           = evBuf[i].SR;
        te.fA           = evBuf[i].fA;
        te.fB           = evBuf[i].fB;
        te.cpuFlags     = evBuf[i].cpuFlags;
        te.R5           = evBuf[i].R5;
        te.snapshotIndex = evBuf[i].snapshotIndex;
        [result addObject:[NSValue valueWithBytes:&te objCType:@encode(TITraceEvent)]];

        if (snaps && evBuf[i].snapshotIndex != 0xFF) {
            TICPUSnapshot ts;
            const CPUSnapshot& s = snapBuf[i];
            memcpy(ts.A,    s.A,    16);
            memcpy(ts.B,    s.B,    16);
            memcpy(ts.C,    s.C,    16);
            memcpy(ts.D,    s.D,    16);
            memcpy(ts.E,    s.E,    16);
            memcpy(ts.SCOM, s.SCOM, 16 * 16);
            memcpy(ts.Sout, s.Sout, 16);
            ts.KR = s.KR; ts.SR = s.SR; ts.fA = s.fA; ts.fB = s.fB;
            ts.EXT = s.EXT; ts.PREG = s.PREG; ts.flags = s.flags;
            ts.R5 = s.R5; ts.digit = s.digit;
            ts.REG_ADDR = s.REG_ADDR; ts.RAM_ADDR = s.RAM_ADDR; ts.RAM_OP = s.RAM_OP;
            [snaps addObject:[NSValue valueWithBytes:&ts objCType:@encode(TICPUSnapshot)]];
        } else if (snaps) {
            TICPUSnapshot empty{};
            [snaps addObject:[NSValue valueWithBytes:&empty objCType:@encode(TICPUSnapshot)]];
        }
    }

    if (outSnaps) *outSnaps = snaps;
    return result;
}

+ (NSString*)disassemblePC:(uint16_t)pc opcode:(uint16_t)opcode {
    std::string s = TI59Machine::disassemble(pc, opcode);
    return [NSString stringWithUTF8String:s.c_str()];
}

// ── Calculator-level API ──────────────────────────────────────────────────────

- (void)pressMatrixKey:(uint8_t)matrixCode {
    // Matrix code = row×10 + col (row 1–9 top→bottom, col 1–5 left→right).
    // TI59Machine::pressKey takes (kBit, digitSlot):
    //   kBit       = K-line bit index from kbits[], maps physical col → hardware line
    //   digitSlot  = row, which equals the digit-counter column for that keyboard row
    int row = matrixCode / 10;   // digit counter 1–9
    int col = matrixCode % 10;   // physical col 1–5
    if (col < 1 || col > 5 || row < 1 || row > 9) return;
    _machine->pressKey(kbits[col], row);
}

- (void)releaseMatrixKey:(uint8_t)matrixCode {
    int row = matrixCode / 10;
    int col = matrixCode % 10;
    if (col < 1 || col > 5 || row < 1 || row > 9) return;
    _machine->releaseKey(kbits[col], row);
}

- (double)dataRegister:(NSInteger)regNum {
    return _machine->readDataReg((int)regNum);
}

- (NSData*)allProgramSteps {
    int count = (int)_machine->partitionProgramRegs() * 8;
    NSMutableData* data = [NSMutableData dataWithLength:count];
    uint8_t* bytes = (uint8_t*)data.mutableBytes;
    for (int i = 0; i < count; i++)
        bytes[i] = _machine->readProgramStep(i);
    return data;
}

- (TICPUSnapshot)snapshotCPU {
    CPUSnapshot s = _machine->snapshotCPU();
    TICPUSnapshot out;
    memcpy(out.A, s.A, 16); memcpy(out.B, s.B, 16); memcpy(out.C, s.C, 16);
    memcpy(out.D, s.D, 16); memcpy(out.E, s.E, 16);
    memcpy(out.SCOM, s.SCOM, 16 * 16);
    memcpy(out.Sout, s.Sout, 16);
    out.KR = s.KR; out.SR = s.SR; out.fA = s.fA; out.fB = s.fB;
    out.EXT = s.EXT; out.PREG = s.PREG; out.flags = s.flags;
    out.R5 = s.R5; out.digit = s.digit;
    out.REG_ADDR = s.REG_ADDR; out.RAM_ADDR = s.RAM_ADDR; out.RAM_OP = s.RAM_OP;
    return out;
}

+ (double)decodeBCDNibbles:(NSData*)nibbles16 {
    if (nibbles16.length < 16) return 0.0;
    return TI59Machine::decodeBCD((const uint8_t*)nibbles16.bytes);
}

// ── Raw RAM access ────────────────────────────────────────────────────────────

- (NSInteger)ramRegisterCount {
    return _machine->ramRegCount();
}

- (NSData*)rawRegister:(NSInteger)reg {
    const uint8_t* n = _machine->readRAMReg((int)reg);
    return [NSData dataWithBytes:n length:16];
}

- (void)setRawRegister:(NSInteger)reg nibbles:(NSData*)nibbles {
    if (nibbles.length == 16)
        _machine->writeRAMReg((int)reg, (const uint8_t*)nibbles.bytes);
}

// ── Printer buffer ────────────────────────────────────────────────────────────

- (NSString*)printerBufferContent {
    std::string s = _machine->printerBufferContent();
    return [NSString stringWithUTF8String:s.c_str()];
}

@end
