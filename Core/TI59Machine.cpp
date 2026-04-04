#include "TI59Machine.hpp"
#include <cmath>

TI59Machine::TI59Machine(MachineVariant variant)
    : m_variant(variant), m_cpu(m_rom, m_ram)
{
    if (variant == MachineVariant::TI58 || variant == MachineVariant::TI58C)
        m_ram.setLimit(60);
    // Card-reader switch: pressed = card absent (normal startup state).
    // TI-59 uses digit-counter slot 10; TI-58/58C uses slot 7; bit 4 in both.
    int col = cardSwitchCol();
    m_cpu.setCardSwitchCol((uint8_t)col);
    m_cpu.pressKey(4, col);
    m_cpu.setPrinterConnected(m_printerConnected);
}

void TI59Machine::loadROM(const uint16_t* data, size_t count) {
    m_rom.load(data, count);
}

void TI59Machine::loadLibrary(const uint8_t* data, size_t count) {
    m_cpu.loadLibrary(data, count);
}

void TI59Machine::reset() {
    std::lock_guard<std::mutex> lock(m_keyMutex);
    m_cpu.reset();
    m_cpu.pressKey(4, cardSwitchCol());  // restore card-absent state after key[] wipe
    m_cpu.setPrinterConnected(m_printerConnected);
}

uint32_t TI59Machine::step() {
    std::lock_guard<std::mutex> lock(m_keyMutex);
    uint32_t r = (uint32_t)m_cpu.step();
    if (m_cpu.consumeBreakpointHit())
        r |= 0x8000'0000u;
    return r;
}

void TI59Machine::pressKey(int row, int col) {
    std::lock_guard<std::mutex> lock(m_keyMutex);
    m_cpu.pressKey(row, col);
}

void TI59Machine::releaseKey(int row, int col) {
    std::lock_guard<std::mutex> lock(m_keyMutex);
    m_cpu.releaseKey(row, col);
}

DisplaySnapshot TI59Machine::getDisplay() const {
    return m_cpu.getDisplay();
}

void TI59Machine::serialiseRAM(uint8_t* dst) const {
    m_ram.serialise(dst);
}

void TI59Machine::deserialiseRAM(const uint8_t* src) {
    m_ram.deserialise(src);
}

// ── State file load helpers ────────────────────────────────────────────────────

void TI59Machine::writeProgram(const uint8_t* keycodes, int count) {
    for (int stepAddr = 0; stepAddr < count; stepAddr++) {
        uint8_t keycode = keycodes[stepAddr];
        // Keycodes are 2-digit decimal (00-99); ROM stores/reads them as BCD decimal digits.
        // nibble at (step&7)*2   = units digit (BCD LSD)
        // nibble at (step&7)*2+1 = tens  digit (BCD MSD)
        m_ram.write(stepAddr >> 3, (stepAddr & 7) * 2,     keycode % 10);
        m_ram.write(stepAddr >> 3, (stepAddr & 7) * 2 + 1, keycode / 10);
    }
}

void TI59Machine::writeDataRegister(int regNum, const uint8_t* nibbles16) {
    // Data registers descend from the top of RAM: R00=RAM[119], R01=RAM[118], ...
    m_ram.writeReg(RAM::TOTAL_REGS - 1 - regNum, nibbles16);
}

int TI59Machine::partitionProgramRegs() const {
    // The partition is stored live in two SCOM locations by the ROM's OP 17 handler.
    // SCOM[9][0] encodes programRAMregs / 10 as a single hex nibble (0–12).
    // E.g. value 6 → 60 program regs → 480 steps (the factory default "6 OP 17").
    // Discovered empirically: diffing SCOM across "0 OP 17", "5 OP 17", "10 OP 17".
    return (int)m_cpu.scomNibble(9, 0) * 10;
}

void TI59Machine::setPartitionProgramRegs(int programRAMregs) {
    // Mirror what the ROM's OP 17 handler writes.  Both SCOM locations must be
    // updated or the ROM's AOS stack / display code will use stale values.
    //
    // SCOM[9][0]     = n            (single nibble, range 0–12)
    // SCOM[13][8..9] = n as 2-digit BCD, LSD at nibble [8], MSD at nibble [9]
    //
    // where n = programRAMregs / 10.
    // programRAMregs must be a multiple of 10 in [0, 120].
    int n = programRAMregs / 10;
    m_cpu.setSCOMNibble(9,  0, (uint8_t)n);
    m_cpu.setSCOMNibble(13, 8, (uint8_t)(n % 10));  // BCD units
    m_cpu.setSCOMNibble(13, 9, (uint8_t)(n / 10));  // BCD tens
}

// ── Magnetic card reader ───────────────────────────────────────────────────────

int TI59Machine::cardSwitchCol() const {
    return (m_variant == MachineVariant::TI59) ? 10 : 7;
}

void TI59Machine::insertCard(const uint8_t* data, size_t count) {
    std::lock_guard<std::mutex> lock(m_keyMutex);
    m_cpu.insertCard(data, count);
}

std::vector<uint8_t> TI59Machine::cardEject() {
    std::lock_guard<std::mutex> lock(m_keyMutex);
    return m_cpu.cardEject();
}

bool TI59Machine::isCardPresent()    const { return m_cpu.isCardPresent(); }
bool TI59Machine::isWaitingForCard() const { return m_cpu.isWaitingForCard(); }
int  TI59Machine::cardMode()         const { return m_cpu.cardMode(); }

// ── Printer ────────────────────────────────────────────────────────────────────

std::vector<std::string> TI59Machine::drainPrinterLines() {
    std::lock_guard<std::mutex> lock(m_keyMutex);
    return m_cpu.drainPrinterLines();
}

std::vector<std::array<uint8_t,20>> TI59Machine::drainPrinterCodeLines() {
    std::lock_guard<std::mutex> lock(m_keyMutex);
    return m_cpu.drainPrinterCodeLines();
}

void TI59Machine::pressPrinterPrint(bool pressed) {
    std::lock_guard<std::mutex> lock(m_keyMutex);
    m_cpu.pressPrinterPrint(pressed);
}

void TI59Machine::pressPrinterAdv(bool pressed) {
    std::lock_guard<std::mutex> lock(m_keyMutex);
    m_cpu.pressPrinterAdv(pressed);
}

void TI59Machine::setPrinterTrace(bool enabled) {
    std::lock_guard<std::mutex> lock(m_keyMutex);
    m_cpu.setPrinterTrace(enabled);
}

void TI59Machine::setPrinterConnected(bool connected) {
    std::lock_guard<std::mutex> lock(m_keyMutex);
    m_printerConnected = connected;
    m_cpu.setPrinterConnected(connected);
}

// ── Trace / debug API ──────────────────────────────────────────────────────────

void TI59Machine::setTraceFlags(uint32_t f) { m_cpu.setTraceFlags(f); }
uint32_t TI59Machine::traceFlags() const    { return m_cpu.traceFlags(); }

void TI59Machine::addBreakpoint(uint16_t pc) {
    std::lock_guard<std::mutex> lock(m_keyMutex);
    m_cpu.addBreakpoint(pc);
}

void TI59Machine::removeBreakpoint(uint16_t pc) {
    std::lock_guard<std::mutex> lock(m_keyMutex);
    m_cpu.removeBreakpoint(pc);
}

void TI59Machine::clearBreakpoints() {
    std::lock_guard<std::mutex> lock(m_keyMutex);
    m_cpu.clearBreakpoints();
}

uint32_t TI59Machine::drainTraceEvents(TraceEvent* out, CPUSnapshot* outSnaps, uint32_t max) {
    std::lock_guard<std::mutex> lock(m_keyMutex);
    return m_cpu.drainTraceEvents(out, outSnaps, max);
}

bool TI59Machine::peekLastEvent(TraceEvent& out, CPUSnapshot* outSnap) const {
    return m_cpu.peekLastEvent(out, outSnap);
}

uint32_t TI59Machine::stepN(uint32_t n, bool stopOnBreakpoint) {
    std::lock_guard<std::mutex> lock(m_keyMutex);
    uint32_t done = 0;
    while (done < n) {
        int r = m_cpu.step();
        done++;
        if (stopOnBreakpoint && m_cpu.consumeBreakpointHit())
            break;
        (void)r;
    }
    return done;
}

uint16_t TI59Machine::pc() const {
    return m_cpu.pc();
}

std::string TI59Machine::disassemble(uint16_t pc, uint16_t opcode) {
    return TMC0501::disassemble(pc, opcode);
}

// ── Calculator-level read API ──────────────────────────────────────────────────

double TI59Machine::decodeBCD(const uint8_t* n) {
    // Check for zero / NaN / Inf (all-zero or all-zero mantissa)
    bool allZero = true;
    for (int i = 0; i < 16; i++) { if (n[i]) { allZero = false; break; } }
    if (allZero) return 0.0;

    // n[0]: bit 1 = mantissa sign (1=negative), bit 2 = exponent sign (1=negative)
    // n[1]: exponent units (BCD LSD), n[2]: exponent tens (BCD MSD) — magnitude 0–99
    // n[15]=mantissa MSD .. n[3]=mantissa LSD  (13 digits)
    bool negative = (n[0] & 2) != 0;   // bit 1 = mantissa sign
    bool negExp   = (n[0] & 4) != 0;   // bit 2 = exponent sign
    int  exp      = n[2] * 10 + n[1];  // exponent magnitude 0–99
    if (negExp) exp = -exp;

    // Reconstruct mantissa from D[15] (MSD) down to D[3] (LSD)
    double mantissa = 0.0;
    for (int i = 15; i >= 3; i--) {
        mantissa = mantissa * 10.0 + (n[i] & 0x0F);
    }
    // mantissa is now a 13-digit integer; scale to [1.0, 10.0)
    mantissa /= 1e12;

    double value = mantissa * std::pow(10.0, (double)exp);
    return negative ? -value : value;
}

double TI59Machine::readDataReg(int regNum) const {
    // Data registers descend from the top of RAM: R00=RAM[119], R01=RAM[118], ...
    return decodeBCD(m_ram.readReg(RAM::TOTAL_REGS - 1 - regNum));
}

uint8_t TI59Machine::readProgramStep(int stepAddr) const {
    uint8_t tens  = m_ram.read(stepAddr >> 3, (stepAddr & 7) * 2 + 1);
    uint8_t units = m_ram.read(stepAddr >> 3, (stepAddr & 7) * 2);
    return (uint8_t)(tens * 10 + units);
}

CPUSnapshot TI59Machine::snapshotCPU() const {
    return m_cpu.snapshotCPU();
}

std::string TI59Machine::printerBufferContent() const {
    return m_cpu.printerBufferContent();
}
