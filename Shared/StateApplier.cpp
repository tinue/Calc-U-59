#include "StateApplier.hpp"
#include <vector>

namespace cu59 {

namespace {

/// The ROM's power-on routine (master clear, display init) reaches idle well
/// within this; skipping it leaves SCOM uninitialised, which confuses the AOS
/// stack and display driver once program/data are written.
constexpr uint32_t kStartupSteps = 300'000;

/// Program steps zero-padded to the model's physical capacity — not the
/// PARTITION boundary: some listings deliberately load registers as programs
/// and programs as registers (examples/calendar-05-vanderburgh.ti59), so
/// PROGRAM: and REGISTERS: are trusted as written.
void writeProgram(TI59Machine& m, const LoadStateResult& r, Model model) {
    int physicalMaxStep = info(model).hasLargeMemory ? 959 : 479;
    std::vector<uint8_t> program(static_cast<size_t>(physicalMaxStep + 1), 0);
    for (const auto& s : r.programSteps)
        if (s.stepAddr >= 0 && s.stepAddr <= physicalMaxStep) program[static_cast<size_t>(s.stepAddr)] = s.keycode;
    m.writeProgram(program.data(), static_cast<int>(program.size()));
}

/// Extra (H) registers go straight to raw RAM 60–63; branch on isHidden, not
/// the number's range — normal TI-59 registers go up to 99.
void writeRegisters(TI59Machine& m, const LoadStateResult& r) {
    for (const auto& g : r.registers) {
        if (g.isHidden) m.writeRAMReg(kExtraRegisterBase + g.regNum, g.nibbles.data());
        else m.writeDataRegister(g.regNum, g.nibbles.data());
    }
}

/// SCOM holds program registers = (max step + 1) / 8.
void setPartition(TI59Machine& m, int partitionMaxStep) { m.setPartitionProgramRegs((partitionMaxStep + 1) / 8); }

} // namespace

std::optional<std::string> stateFilePartitionError(const LoadStateResult& r, Model model) {
    if (!info(model).hasLargeMemory && r.partitionWasExplicit && r.partitionMaxStep > 479) {
        return "State file partition (" + std::to_string(r.partitionMaxStep) + ") exceeds " +
               info(model).displayName + " maximum (479) — load aborted.";
    }
    return std::nullopt;
}

void applyState(TI59Machine& m, const LoadStateResult& r, Model model) {
    const ModelInfo& mi = info(model);
    int partitionMaxStep = (!mi.hasLargeMemory && !r.partitionWasExplicit) ? 239 : r.partitionMaxStep;

    m.reset();
    m.stepN(kStartupSteps);
    setPartition(m, partitionMaxStep);

    // Clear RAM, but keep the TI-58C's extra registers (raw RAM 60–63,
    // E000–E003 / H00–H03): RAM[60] holds SCOM reconstruction data and
    // clearing it triggers the ROM's memory-clear routine. See
    // reference/CoreArchitecture.md § "TI-58C Extra (Constant Memory) Registers".
    const uint8_t zero[16] = {};
    int clearUpTo = mi.hasConstantMemory ? kExtraRegisterBase : 120;
    for (int reg = 0; reg < clearUpTo; ++reg) m.writeRAMReg(reg, zero);

    writeProgram(m, r, model);
    writeRegisters(m, r);
}

void applySkipResetState(TI59Machine& m, const LoadStateResult& r, Model model) {
    if (r.partitionWasExplicit) setPartition(m, r.partitionMaxStep);
    if (!r.programSteps.empty()) writeProgram(m, r, model);
    writeRegisters(m, r);
}

} // namespace cu59
