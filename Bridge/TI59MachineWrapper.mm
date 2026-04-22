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

- (void)loadConstants:(NSData*)constData {
    const uint8_t* bytes = (const uint8_t*)constData.bytes;
    size_t count = constData.length;
    _machine->loadConstants(bytes, count);
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

- (uint32_t)stepUntilNextKeycode {
    return _machine->stepUntilNextKeycode();
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

// ── Debug event log ───────────────────────────────────────────────────────────

- (void)setDebugLevel:(uint8_t)level {
    _machine->setDebugLevel(level);
}

- (NSArray<NSString*>*)drainDebugMessages {
    auto events = _machine->drainDebugEvents();
    if (events.empty()) return @[];
    NSMutableArray<NSString*>* result = [NSMutableArray arrayWithCapacity:events.size()];
    for (const auto& ev : events) {
        // Prefix: "I:" for INFO (1), "D:" for DEBUG (2).
        char prefix = (ev.level == 1) ? 'I' : 'D';
        NSString* s = [NSString stringWithFormat:@"%c:%s", prefix, ev.msg];
        [result addObject:s];
    }
    return result;
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

- (BOOL)runDebugOverlayAt:(uint16_t)startAddr
                 maxSteps:(uint32_t)maxSteps
                    steps:(uint32_t*)outSteps
                  sawHold:(BOOL*)outSawHold {
    uint32_t steps = 0;
    bool sawHold = false;
    bool ok = _machine->runDebugOverlay(startAddr, maxSteps, &steps, &sawHold);
    if (outSteps) *outSteps = steps;
    if (outSawHold) *outSawHold = sawHold ? YES : NO;
    return ok ? YES : NO;
}

// ── New CPU frame API ────────────────────────────────────────────────────────

// Helper: convert C++ CpuFrame to Objective-C TICpuFrame struct.
static TICpuFrame marshalCpuFrame(const CpuFrame& f) {
    TICpuFrame frame;
    // Identity
    frame.seqno = f.seqno;
    frame.pc = f.pc;
    frame.opcode = f.opcode;
    frame.digit = f.digit;
    frame.cycleWeight = f.cycleWeight;
    // Light registers
    frame.KR = f.KR; frame.SR = f.SR; frame.fA = f.fA; frame.fB = f.fB;
    frame.cpuFlags = f.cpuFlags; frame.R5 = f.R5;
    // Full snapshot
    memcpy(frame.A, f.A, 16);
    memcpy(frame.B, f.B, 16);
    memcpy(frame.C, f.C, 16);
    memcpy(frame.D, f.D, 16);
    memcpy(frame.E, f.E, 16);
    memcpy(frame.SCOM, f.SCOM, sizeof(f.SCOM));
    memcpy(frame.Sout, f.Sout, 16);
    frame.EXT = f.EXT; frame.PREG = f.PREG; frame.flags = f.flags;
    frame.m_libAddr = f.m_libAddr;
    frame.REG_ADDR = f.REG_ADDR; frame.RAM_ADDR = f.RAM_ADDR; frame.RAM_OP = f.RAM_OP;
    frame.m_libAddrReadPos = f.m_libAddrReadPos;
    frame.dispFilter = f.dispFilter;
    return frame;
}

- (NSArray<NSValue*>*)drainCpuFramesMax:(NSUInteger)max
                                   lost:(NSUInteger*)outLost {
    if (max == 0) { if (outLost) *outLost = 0; return @[]; }

    const uint32_t cap = (uint32_t)MIN(max, 1024u);
    std::vector<CpuFrame> frames(cap);
    uint32_t lostCount = 0;

    uint32_t n = _machine->drainCpuFrames(frames.data(), cap, &lostCount);
    if (outLost) *outLost = lostCount;
    if (n == 0) return @[];

    NSMutableArray<NSValue*>* result = [NSMutableArray arrayWithCapacity:n];
    for (uint32_t i = 0; i < n; i++) {
        TICpuFrame frame = marshalCpuFrame(frames[i]);
        [result addObject:[NSValue valueWithBytes:&frame objCType:@encode(TICpuFrame)]];
    }
    return result;
}

- (NSArray<NSValue*>*)readCpuFramesMax:(NSUInteger)max {
    if (max == 0) return @[];

    const uint32_t cap = (uint32_t)MIN(max, 1024u);
    std::vector<CpuFrame> frames(cap);

    uint32_t n = _machine->readCpuFrames(frames.data(), cap);
    if (n == 0) return @[];

    NSMutableArray<NSValue*>* result = [NSMutableArray arrayWithCapacity:n];
    for (uint32_t i = 0; i < n; i++) {
        TICpuFrame frame = marshalCpuFrame(frames[i]);
        [result addObject:[NSValue valueWithBytes:&frame objCType:@encode(TICpuFrame)]];
    }
    return result;
}

// ── Old trace API (deprecated; kept for binary compatibility) ────────────────

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

- (uint8_t)romKeycodeAt:(NSInteger)addr {
    return _machine->readROMKeycode((int)addr);
}

- (NSIndexSet*)nonZeroDataRegisterIndices {
    NSMutableIndexSet* result = [NSMutableIndexSet indexSet];
    int programRegs = (int)_machine->partitionProgramRegs();
    int totalRegs   = _machine->ramRegCount();
    int dataRegCount = MAX(0, totalRegs - programRegs);
    for (int regNum = 0; regNum < dataRegCount; regNum++) {
        const uint8_t* n = _machine->readRAMReg(totalRegs - 1 - regNum);
        for (int i = 0; i < 16; i++) {
            if (n[i] != 0) {
                [result addIndex:regNum];
                break;
            }
        }
    }
    return result;
}

- (TICpuFrame)snapshotCPU {
    CpuFrame frame = _machine->snapshotCPU();
    TICpuFrame out;
    out.seqno = frame.seqno;
    out.pc = frame.pc;
    out.opcode = frame.opcode;
    out.digit = frame.digit;
    out.cycleWeight = frame.cycleWeight;
    out.KR = frame.KR; out.SR = frame.SR; out.fA = frame.fA; out.fB = frame.fB;
    out.cpuFlags = frame.cpuFlags;
    out.R5 = frame.R5;
    memcpy(out.A, frame.A, 16); memcpy(out.B, frame.B, 16); memcpy(out.C, frame.C, 16);
    memcpy(out.D, frame.D, 16); memcpy(out.E, frame.E, 16);
    memcpy(out.SCOM, frame.SCOM, 16 * 16);
    memcpy(out.Sout, frame.Sout, 16);
    out.EXT = frame.EXT; out.PREG = frame.PREG; out.flags = frame.flags;
    out.m_libAddr = frame.m_libAddr;
    out.REG_ADDR = frame.REG_ADDR; out.RAM_ADDR = frame.RAM_ADDR; out.RAM_OP = frame.RAM_OP;
    out.m_libAddrReadPos = frame.m_libAddrReadPos;
    out.dispFilter = frame.dispFilter;
    return out;
}

- (void)beginNextStep {
    _machine->beginNextStep();
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
