#include "DebugSnapshots.hpp"
#include "Bcd.hpp"
#include "CueCard.hpp"
#include "KeyNames.hpp"
#include <algorithm>
#include <cstdio>

namespace cu59 {

namespace {

std::string twoDigits(uint8_t kc) {
    char b[8];
    std::snprintf(b, sizeof b, "%02u", static_cast<unsigned>(kc));
    return b;
}

std::string stepMnemonic(uint8_t kc, bool isArgument) { return isArgument ? twoDigits(kc) : mnemonic(kc); }

/// Return-stack level: PRG SOURCE at `at`, then the Base-80 address read right to left.
int base80(const uint8_t* n, int at) { return n[at + 4] * 800 + n[at + 3] * 80 + n[at + 2] * 8 + n[at + 1]; }

} // namespace

int decodeProgramCounter(const CpuFrame& cpu) {
    return cpu.SCOM[0][7] * 800 + cpu.SCOM[0][6] * 80 + cpu.SCOM[0][5] * 8 + cpu.SCOM[0][4];
}

std::vector<uint8_t> programSteps(const TI59Machine& m) {
    int count = std::min(m.partitionProgramRegs(), m.ramRegCount()) * 8;
    std::vector<uint8_t> steps(static_cast<size_t>(std::max(count, 0)));
    for (int i = 0; i < count; ++i) steps[static_cast<size_t>(i)] = m.readProgramStep(i);
    return steps;
}

std::vector<uint8_t> romKeycodes(const TI59Machine& m) {
    std::vector<uint8_t> k(384);
    for (int i = 0; i < 384; ++i) k[static_cast<size_t>(i)] = m.readROMKeycode(i);
    return k;
}

std::vector<StepEntry> programListing(const std::vector<uint8_t>& keycodes, const std::set<int>& argSteps,
                                      int currentStep) {
    std::vector<StepEntry> out;
    out.reserve(keycodes.size());
    for (size_t i = 0; i < keycodes.size(); ++i) {
        int n = static_cast<int>(i);
        out.push_back({n, keycodes[i], stepMnemonic(keycodes[i], argSteps.count(n) > 0), n == currentStep});
    }
    return out;
}

bool LiveDebugSnapshot::operator==(const LiveDebugSnapshot& o) const {
    return nonZeroRegs == o.nonZeroRegs && dataRegCount == o.dataRegCount && programRegCount == o.programRegCount &&
           programWindow == o.programWindow && currentStep == o.currentStep && hir == o.hir &&
           tRegister == o.tRegister && calcFlags == o.calcFlags && fixIndicator == o.fixIndicator &&
           ioUserFlags == o.ioUserFlags && lastKey == o.lastKey && fA == o.fA && fB == o.fB &&
           engIndicator == o.engIndicator && secondIndicator == o.secondIndicator && invIndicator == o.invIndicator &&
           angleMode == o.angleMode && prSourceFlag == o.prSourceFlag && programSource == o.programSource &&
           pendingOpsCount == o.pendingOpsCount && scomRows == o.scomRows &&
           returnAddressSourceFlags == o.returnAddressSourceFlags && returnAddresses == o.returnAddresses;
}

std::vector<CpuFrame> readTraceRing(const TI59Machine& m) {
    std::vector<CpuFrame> frames(1024);
    frames.resize(m.readCpuFrames(frames.data(), 1024));
    return frames;
}

std::vector<InspectorEntry> inspectorHistory(const TI59Machine& m) {
    std::vector<CpuFrame> frames = readTraceRing(m);
    std::vector<InspectorEntry> out;
    out.reserve(frames.size() + 1);
    for (size_t i = 0; i < frames.size(); ++i) {
        const CpuFrame& f = frames[i];
        out.push_back({f.pc, f.opcode, TI59Machine::disassemble(f.pc, f.opcode), f, true, i + 1 == frames.size()});
    }
    // snapshotCPU() carries the real next opcode.
    uint16_t pc = m.pc();
    uint16_t next = m.snapshotCPU().opcode;
    out.push_back({pc, next, TI59Machine::disassemble(pc, next), CpuFrame{}, false, false});
    return out;
}

std::vector<InspectorEntry> recentInstructions(const std::vector<CpuFrame>& frames, size_t count) {
    std::vector<InspectorEntry> out;
    size_t first = frames.size() > count ? frames.size() - count : 0;
    for (size_t i = first; i < frames.size(); ++i) {
        const CpuFrame& f = frames[i];
        out.push_back({f.pc, f.opcode, TI59Machine::disassemble(f.pc, f.opcode), f, true, i + 1 == frames.size()});
    }
    return out;
}

LiveDebugBuild buildLiveSnapshot(const TI59Machine& m, Model model, const ModuleImage& module,
                                 std::vector<uint8_t>& romCache, bool frozen) {
    LiveDebugBuild out;
    LiveDebugSnapshot& snap = out.snap;
    const int partitionProgramRegs = m.partitionProgramRegs();
    const int totalRegs = m.ramRegCount();  // 60 (TI-58), 64 (TI-58C) or 120 (TI-59)
    const int displayableRegs = info(model).hasConstantMemory ? 60 : totalRegs;
    // Quirky partitions may claim more registers than physically exist.
    const int programRegs = std::min(partitionProgramRegs, totalRegs);
    snap.programRegCount = partitionProgramRegs;
    snap.dataRegCount = std::max(0, displayableRegs - programRegs);

    // Non-zero data registers: visible ones as Rnn, the TI-58C's extra ones as Hnn.
    for (int ramIdx = programRegs; ramIdx < totalRegs; ++ramIdx) {
        uint8_t n[16];
        m.copyRAMReg(ramIdx, n);
        if (std::all_of(n, n + 16, [](uint8_t v) { return v == 0; })) continue;
        double value = TI59Machine::decodeBCD(n);
        if (ramIdx < displayableRegs) snap.nonZeroRegs.push_back({displayableRegs - 1 - ramIdx, value, false});
        else snap.nonZeroRegs.push_back({ramIdx - displayableRegs, value, true});
    }

    const CpuFrame cpu = m.snapshotCPU();
    const auto& S = cpu.SCOM;

    for (int h = 1; h <= 8; ++h) snap.hir[static_cast<size_t>(h - 1)] = TI59Machine::decodeBCD(S[h]);  // HIR n in SCOM[n]
    snap.tRegister = TI59Machine::decodeBCD(S[11]);

    snap.prSourceFlag = S[0][3];
    snap.programSource = programSourceFrom(snap.prSourceFlag, cpu.pc);

    // Angle mode in SCOM[13] nibble 0: 0 = DEG, 1 = GRAD, C = RAD.
    switch (S[13][0] & 0x0F) {
    case 0x0: snap.angleMode = AngleMode::Deg; break;
    case 0x1: snap.angleMode = AngleMode::Grad; break;
    case 0xC: snap.angleMode = AngleMode::Rad; break;
    default: break;
    }
    snap.pendingOpsCount = S[13][0];  // exact bit position TBD

    // User flags 0–9 in SCOM[0] nibbles 11–15: flag n is nibble 11 + n%5, bit 1 (n<5) or 2.
    for (int f = 0; f < 10; ++f) snap.calcFlags[static_cast<size_t>(f)] = (S[0][11 + f % 5] & (f < 5 ? 1 : 2)) != 0;

    // FIX (nibble 0: 0 shows a dash, else (raw − 2) mod 10), IO user flags, last key.
    int fixRaw = S[0][0];
    snap.fixIndicator = fixRaw == 0 ? "-" : std::to_string((((fixRaw - 2) % 10) + 10) % 10);
    char buf[64];
    std::snprintf(buf, sizeof buf, "%d%d%d%d%d", S[0][1], S[0][2], S[0][3], S[0][4], S[0][5]);
    snap.ioUserFlags = buf;
    std::snprintf(buf, sizeof buf, "%d%d", S[0][13], S[0][14]);
    snap.lastKey = buf;

    // 2nd/INV: fA nibble 2 (bits 11–8), bit 1 / bit 0. Eng: fB bits 7–4, bit 3.
    snap.fA = cpu.fA;
    snap.fB = cpu.fB;
    int faNibble = (cpu.fA >> 8) & 0xF;
    snap.invIndicator = (faNibble & 0x1) ? "INV" : "";
    snap.secondIndicator = (faNibble & 0x2) ? "2nd" : "";
    snap.engIndicator = (((cpu.fB >> 4) & 0xF) & 0x8) ? "Eng" : "";

    // Current step: Solid State from the library exec latch (the SCOM PC does
    // not move during module execution); user programs and ROM from the SCOM PC.
    const int decodedPC = decodeProgramCounter(cpu);
    std::optional<ModuleImage::LibStep> lib;
    if (snap.programSource == ProgramSource::SolidState) lib = module.libraryStep(m.libExecPC());
    if (lib) {
        // The latch points at the byte being dispatched: already the "last
        // executed" step when frozen, no −1 adjustment.
        snap.currentStep = lib->step;
        int scomProgram = activeLibraryProgram(S[9]);
        if (scomProgram != lib->program) out.libProgramMismatch = std::make_pair(lib->program, scomProgram);
    } else if (stepsFromScomPC(snap.programSource)) {
        snap.currentStep = frozen ? std::max(0, decodedPC - 1) : decodedPC;
    }

    // Keycodes of the active source; operands are classified over the whole
    // listing so a window starting mid-instruction doesn't misread them.
    switch (snap.programSource) {
    case ProgramSource::UserProgram:
    case ProgramSource::FastMode:
        out.sourceKeycodes = programSteps(m);
        break;
    case ProgramSource::Rom:
        if (romCache.size() != 384) romCache = romKeycodes(m);
        out.sourceKeycodes = romCache;
        break;
    case ProgramSource::SolidState:
        if (lib) out.sourceKeycodes.assign(module.keycodes.begin() + lib->begin, module.keycodes.begin() + lib->end);
        break;
    case ProgramSource::SolidStateReturn:
        break;
    }
    out.argSteps = argumentSteps(out.sourceKeycodes);

    if (!out.sourceKeycodes.empty()) {
        int center = std::max(snap.currentStep, 0);
        int lo = std::max(0, center - 5);
        int hi = std::min(static_cast<int>(out.sourceKeycodes.size()) - 1, center + 5);
        for (int i = lo; i <= hi; ++i) {
            uint8_t kc = out.sourceKeycodes[static_cast<size_t>(i)];
            snap.programWindow.push_back({i, kc, stepMnemonic(kc, out.argSteps.count(i) > 0), i == snap.currentStep});
        }
    }

    // Return stack: SCOM[15] nibble 0 = count; levels 1–3 in SCOM[15], 4–6 in
    // SCOM[14], 5 nibbles each (PRG SOURCE + Base-80 address).
    uint8_t n15[16], n14[16];
    for (int i = 0; i < 16; ++i) { n15[i] = S[15][i] & 0xF; n14[i] = S[14][i] & 0xF; }
    const int levelAt[6] = {1, 6, 11, 1, 6, 11};
    for (int l = 0; l < 6; ++l) {
        const uint8_t* row = l < 3 ? n15 : n14;
        snap.returnAddressSourceFlags[static_cast<size_t>(l)] = row[levelAt[l]];
        snap.returnAddresses[static_cast<size_t>(l)] = base80(row, levelAt[l]);
    }

    for (int r = 0; r < 16; ++r) snap.scomRows[static_cast<size_t>(r)] = nibbleHex(S[r]);
    return out;
}

} // namespace cu59
