// Flat C API over TI59Machine (plus Shared/'s ROM loader) for the Python headless harness
// (tools/headless/ti59.py, loaded via ctypes). Built by
// tools/headless/build.sh into tools/headless/build/libti59headless.dylib.
//
// The surface is deliberately small: lifecycle, keys, single steps, and a
// bulk "run n steps and record each one" call so tracing a keystroke does
// not pay a ctypes round trip per instruction.

#include "../../Core/TI59Machine.hpp"
#include "../../Shared/MachineModelInfo.hpp"
#include "../../Shared/ModuleCatalog.hpp"
#include "../../Shared/RomLoader.hpp"
#include <cstring>
#include <string>

namespace {

// One recorded instruction: identity of the instruction executed, then the
// CPU state *after* it ran (same post-exec semantics as the app's trace ring).
#pragma pack(push, 1)
struct HRec {
    uint16_t pc, opcode;
    uint16_t KR, SR, fA, fB, flags, PREG, EXT, libAddr;
    uint8_t  R5, digit, weight, pad;
    uint8_t  A[16], B[16], C[16], D[16], E[16];
    uint8_t  SCOM[16][16];
};
#pragma pack(pop)

void fill(HRec& r, uint16_t pc, uint16_t op, const CpuFrame& f, int w) {
    r.pc = pc; r.opcode = op;
    r.KR = f.KR; r.SR = f.SR; r.fA = f.fA; r.fB = f.fB; r.flags = f.cpuFlags;
    r.PREG = f.PREG; r.EXT = f.EXT; r.libAddr = f.m_libAddr;
    r.R5 = f.R5; r.digit = f.digit; r.weight = static_cast<uint8_t>(w & 0xFF); r.pad = 0;
    memcpy(r.A, f.A, 16); memcpy(r.B, f.B, 16); memcpy(r.C, f.C, 16);
    memcpy(r.D, f.D, 16); memcpy(r.E, f.E, 16);
    memcpy(r.SCOM, f.SCOM, sizeof(r.SCOM));
}

// The roms/ text dumps, as the apps bundle them: calculator/ then solid-state/.
cu59::ResourceReader romReader(const std::string& romsDir) {
    return cu59::directoryReader({romsDir + "/calculator", romsDir + "/solid-state"});
}

} // namespace

extern "C" {

int h_rec_size() { return static_cast<int>(sizeof(HRec)); }

// Shared/MachineModelInfo.hpp facts of `model`, so Python keeps no copies.
double h_instruction_hz(int model) { return cu59::info(static_cast<cu59::Model>(model)).instructionHz; }
// Printer BUSY in instruction cycles: a printed line, or one PRT.FEED.
uint32_t h_printer_busy_cycles(int feed) { return feed ? TMC0501::kPrinterFeedCycles : TMC0501::kPrinterLineCycles; }
// The idle/key-detect range: out = {lo, hi, extraLo, extraHi} (extra empty when lo > hi).
void h_idle_range(int model, int* out) {
    const cu59::PcRange& r = cu59::info(static_cast<cu59::Model>(model)).idleAndKeyDetect;
    out[0] = r.lo; out[1] = r.hi; out[2] = r.extraLo; out[3] = r.extraHi;
}

void* h_new(int variant) { return new TI59Machine(static_cast<MachineVariant>(variant)); }
void  h_free(void* m) { delete static_cast<TI59Machine*>(m); }

// ROM and constants of `model` (Shared Model: 0 TI-59, 1 TI-58, 2 TI-58C) and
// a solid-state module by its cuecards.txt id, read from `romsDir` through
// Shared/RomLoader like the apps. 0 on success, -1 on a missing or bad file.
int h_load_model_roms(void* mv, int model, const char* romsDir) {
    auto* m = static_cast<TI59Machine*>(mv);
    try {
        auto read = romReader(romsDir);
        auto words = cu59::loadRom(static_cast<cu59::Model>(model), read);
        auto constants = cu59::loadConstants(static_cast<cu59::Model>(model), read);
        m->loadROM(words.data(), words.size());
        m->loadConstants(constants.data(), constants.size());
        return 0;
    } catch (const std::exception&) {
        return -1;
    }
}

int h_load_module(void* mv, const char* moduleID, const char* romsDir) {
    auto read = romReader(romsDir);
    auto catalog = read("cuecards.txt");
    if (!catalog) return -1;
    auto file = cu59::moduleRomFile(*catalog, moduleID);
    if (!file) return -1;
    try {
        auto image = cu59::loadModule(*file, read);
        if (!image) return -1;
        static_cast<TI59Machine*>(mv)->loadLibrary(image->data(), image->size());
        return 0;
    } catch (const std::exception&) {
        return -1;
    }
}

void h_reset(void* m) { static_cast<TI59Machine*>(m)->reset(); }

void h_press(void* m, int kbit, int digit)   { static_cast<TI59Machine*>(m)->pressKey(kbit, digit); }
void h_release(void* m, int kbit, int digit) { static_cast<TI59Machine*>(m)->releaseKey(kbit, digit); }
void h_printer(void* m, int connected)  { static_cast<TI59Machine*>(m)->setPrinterConnected(connected != 0); }
void h_trace_sw(void* m, int on)        { static_cast<TI59Machine*>(m)->setPrinterTrace(on != 0); }
void h_printer_print(void* m, int down) { static_cast<TI59Machine*>(m)->pressPrinterPrint(down != 0); }
void h_printer_adv(void* m, int down)   { static_cast<TI59Machine*>(m)->pressPrinterAdv(down != 0); }

uint32_t h_stepn(void* m, uint32_t n) { return static_cast<TI59Machine*>(m)->stepN(n, false); }
uint16_t h_pc(void* m) { return static_cast<TI59Machine*>(m)->pc(); }
uint64_t h_elapsed(void* m) { return static_cast<TI59Machine*>(m)->elapsedTicks(); }

// Run n steps, recording each into out[0..n). Stops early (returning the
// count recorded) when stopPC >= 0 and the next PC equals it.
int h_record(void* mv, HRec* out, int n, int stopPC) {
    auto* m = static_cast<TI59Machine*>(mv);
    for (int i = 0; i < n; ++i) {
        CpuFrame pre = m->snapshotCPU();
        int w = static_cast<int>(m->step() & 0xFF);
        CpuFrame post = m->snapshotCPU();
        fill(out[i], pre.pc, pre.opcode, post, w);
        if (stopPC >= 0 && post.pc == stopPC) return i + 1;
    }
    return n;
}

void h_snapshot(void* m, HRec* out) {
    CpuFrame f = static_cast<TI59Machine*>(m)->snapshotCPU();
    fill(*out, f.pc, f.opcode, f, 0);
}

void h_ram_read(void* m, int reg, uint8_t* out16)        { static_cast<TI59Machine*>(m)->copyRAMReg(reg, out16); }
void h_ram_write(void* m, int reg, const uint8_t* in16)  { static_cast<TI59Machine*>(m)->writeRAMReg(reg, in16); }
void h_write_program(void* m, const uint8_t* k, int n)   { static_cast<TI59Machine*>(m)->writeProgram(k, n); }
uint16_t h_lib_exec_pc(void* m) { return static_cast<TI59Machine*>(m)->libExecPC(); }

// Positions not driven since the last call read as blank (ctrl 7).
// masks[0] = decimal points driven, masks[1] = zero-suppressed mask.
void h_display(void* m, uint8_t* digits12, uint8_t* ctrl12, uint16_t* masks) {
    DisplaySnapshot d = static_cast<TI59Machine*>(m)->takeDisplay();
    memcpy(digits12, d.digits, 12);
    memcpy(ctrl12, d.ctrl, 12);
    masks[0] = 0;
    for (int i = 0; i < 12; ++i) {
        if (d.digitDuty[i] == 0) ctrl12[i] = 7;
        if (d.dpDuty[i] > 0) masks[0] |= static_cast<uint16_t>(1u << i);
    }
    masks[1] = d.suppressedMask;
}

// Magnetic card: insert (count 0 = blank card for writing), eject (returns the
// bytes written, up to cap), and the reader's state.
void h_card_insert(void* m, const uint8_t* b, int n) { static_cast<TI59Machine*>(m)->insertCard(b, n); }
int  h_card_eject(void* m, uint8_t* out, int cap) {
    std::vector<uint8_t> v = static_cast<TI59Machine*>(m)->cardEject();
    int n = static_cast<int>(v.size()) < cap ? static_cast<int>(v.size()) : cap;
    if (n) memcpy(out, v.data(), n);
    return n;
}
int  h_card_present(void* m) { return static_cast<TI59Machine*>(m)->isCardPresent() ? 1 : 0; }
int  h_card_mode(void* m)    { return static_cast<TI59Machine*>(m)->cardMode(); }

// Printer output lines, joined with '\n'. Returns bytes written (truncated to cap).
int h_printer_lines(void* m, char* out, int cap) {
    std::string s;
    for (auto& l : static_cast<TI59Machine*>(m)->drainPrinterLines()) { s += l; s += '\n'; }
    int n = static_cast<int>(s.size()) < cap ? static_cast<int>(s.size()) : cap;
    memcpy(out, s.data(), n);
    return n;
}

// Printer code lines (the dot-matrix queue, separate from the text lines):
// 23 bytes each: the 20 character codes, the complete rows (0-7), the
// columns of the next row started before a cut (0-5), and the cycles the
// leftmost of them was heated (capped at 255). Returns the number of lines
// written; the queue is drained, so lines beyond cap are lost.
int h_printer_code_lines(void* m, uint8_t* out, int cap) {
    int n = 0;
    for (auto& l : static_cast<TI59Machine*>(m)->drainPrinterCodeLines()) {
        if (n == cap) break;
        memcpy(out + 23 * n, l.codes.data(), 20);
        out[23 * n + 20] = l.rowCount;
        out[23 * n + 21] = l.partialColumns;
        out[23 * n + 22] = l.partialHeat;
        ++n;
    }
    return n;
}

int h_disasm(uint16_t pc, uint16_t op, char* out, int cap) {
    std::string s = TI59Machine::disassemble(pc, op);
    int n = static_cast<int>(s.size()) < cap - 1 ? static_cast<int>(s.size()) : cap - 1;
    memcpy(out, s.data(), n);
    out[n] = 0;
    return n;
}

} // extern "C"
