#pragma once
#include "../Core/MachineVariant.hpp"
#include <cstdint>

// Per-model facts the frontends need above the hardware level: instruction
// rate for real-time pacing, RAM layout, ROM file names, and the ROM address
// ranges the run loop and debugger key off. Shared by the Swift app (via
// Bridge/) and the Qt6 app; see reference/SharedArchitecture.md.

namespace cu59 {

/// Raw values match MachineModel (Swift) and the TI59MachineWrapper model code.
enum class Model : int { TI59 = 0, TI58 = 1, TI58C = 2 };

inline MachineVariant toVariant(Model m) {
    switch (m) {
    case Model::TI59:  return MachineVariant::TI59;
    case Model::TI58:  return MachineVariant::TI58;
    case Model::TI58C: return MachineVariant::TI58C;
    }
    return MachineVariant::TI59;
}

/// Inclusive ROM address range, with an optional second span.
struct PcRange {
    uint16_t lo, hi;
    uint16_t extraLo = 1, extraHi = 0;  ///< empty unless set
    bool contains(uint16_t pc) const {
        return (pc >= lo && pc <= hi) || (pc >= extraLo && pc <= extraHi);
    }
};

/// TI-58: every idle pass detours through the card veto 0x0459–0x045B (digit 10
/// open, D7-KR asserted → JNC 0641) — see rom/TI59-commented.asm at 0x063C.
inline constexpr uint16_t kCardVetoLo = 0x0459, kCardVetoHi = 0x045B;

/// TI-58C with a printer: every idle pass rescans below the printer line at D10
/// (0x0A25–0x0A2E; through 0x0A30 it confirms a key) — rom/TI58C-commented.asm at 0x0A25.
inline constexpr uint16_t kPrinterRescanLo = 0x0A25, kPrinterRescanHi = 0x0A2E, kPrinterConfirmHi = 0x0A30;

struct ModelInfo {
    const char* displayName;

    /// Instructions/sec in active (RUN) mode: instructionHz() (Core/MachineVariant.hpp).
    /// IDLE divides this further by 4 except on the TI-58C — see
    /// TMC0501::getStepWeight() in Core/TMC0501.cpp.
    double instructionHz;

    int  romWordCount;
    bool hasConstantMemory;  ///< TI-58C: RAM survives power-off (ti58c.mem).
    bool hasLargeMemory;     ///< TI-59: 120 registers.
    bool hasCardReader;      ///< TI-59 only.

    /// TI-58C only: extra constant-memory registers E000…E003 (H00…H03 in state
    /// files) starting at raw RAM index 60 — see reference/CoreArchitecture.md
    /// § "TI-58C Extra (Constant Memory) Registers".
    int extraRegisterCount;

    /// Steady-state keyboard scan loop (FREEZE ON START). With a printer it
    /// includes the confirmation scan, which the printer line (TI-59/58 D0,
    /// TI-58C D10) sends every pass through.
    PcRange scanLoop;

    /// Full keyboard scan/detect cycle — release-gate spin (0x0627) through key
    /// acceptance (0x0661 CLR.IDLE; TI-58C 0x065A). See rom/TI59-commented.asm (0x0620-0x0661)
    /// and ideas/KeypressLatch.md. Used wherever a held key or full-speed racing
    /// must not outrun real scanning/debouncing time.
    PcRange idleAndKeyDetect;

    const char* romFiles[3];    ///< Concatenated in order into the 6144-word image.
    const char* constFiles[2];  ///< CONST-K files, 32 rows each.

    /// Highest program step the RAM can hold (all registers partitioned to program).
    int maxStep() const { return hasLargeMemory ? 959 : 479; }
};

inline constexpr int kExtraRegisterBase = 60;

inline const ModelInfo& info(Model m) {
    static const ModelInfo kTI59 {
        "TI-59", instructionHz(MachineVariant::TI59), 6144, false, true, true, 0,
        {0x063C, 0x0660}, {0x0627, 0x0660},
        {"TMC0582.txt", "TMC0583.txt", "TMC0571B.txt"},
        {"TMC0582-CONST-K.txt", "TMC0583-CONST-K.txt"},
    };
    static const ModelInfo kTI58 {
        "TI-58", instructionHz(MachineVariant::TI58), 6144, false, false, false, 0,
        {0x063C, 0x0660, kCardVetoLo, kCardVetoHi}, {0x0627, 0x0660, kCardVetoLo, kCardVetoHi},
        {"TMC0582.txt", "TMC0583.txt", "TMC0571B.txt"},
        {"TMC0582-CONST-K.txt", "TMC0583-CONST-K.txt"},
    };
    static const ModelInfo kTI58C {
        "TI-58C", instructionHz(MachineVariant::TI58C), 6144, true, false, false, 4,
        {0x063D, 0x0659, kPrinterRescanLo, kPrinterRescanHi},
        {0x0627, 0x0659, kPrinterRescanLo, kPrinterConfirmHi},
        {"CD2400.txt", "CD2401.txt", "TMC0573.txt"},
        {"CD2400-CONST-K.txt", "CD2401-CONST-K.txt"},
    };
    switch (m) {
    case Model::TI59:  return kTI59;
    case Model::TI58:  return kTI58;
    case Model::TI58C: return kTI58C;
    }
    return kTI59;
}

} // namespace cu59
