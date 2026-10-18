#pragma once
#include "../Core/TI59Machine.hpp"
#include "MachineModelInfo.hpp"
#include <atomic>
#include <cstdint>
#include <optional>

// The debugger's armed freezes, checked from the run loop:
//  - FREEZE ON START (CPU tab): fires when the CPU leaves the steady keyboard
//    scan loop — a key press, or a reset (PC jumps to 0000) while running.
//  - Freeze on next PC change (CALCULATOR tab): fires at the next step
//    boundary (TI59Machine::kStepBoundary), where a debugger STEP stops too.
// The two are mutually exclusive: arming one disarms the other. Arming happens
// on the UI thread, checking on the emulation thread.

namespace cu59 {

/// Which debug panel owns a freeze (RESUME/STEP are enabled only there).
enum class FreezeOwner { Cpu, Calculator };

class FreezeController {
public:
    explicit FreezeController(Model model) : m_scanLoop(info(model).scanLoop) {}

    /// FREEZE ON START. `currentPC` guards against an immediate re-trigger at 0000.
    void armScanLoopExit(uint16_t currentPC);
    /// Freeze before the next program byte executes (CALCULATOR FREEZE ON START).
    void armPcChange();
    void disarmScanLoopExit();
    void disarmPcChange();

    bool scanLoopExitArmed() const { return m_scanArmed.load(); }
    bool pcChangeArmed() const { return m_pcArmed.load(); }

    /// Per instruction, with the PC of the next one and whether it is a step
    /// boundary (a per-batch check lands hundreds of instructions late). The
    /// panel whose armed freeze fires; it disarms itself.
    std::optional<FreezeOwner> checkStep(uint16_t pc, bool stepBoundary);

private:
    const PcRange m_scanLoop;
    std::atomic<bool> m_scanArmed{false};
    std::atomic<bool> m_seenLoop{false};
    std::atomic<uint16_t> m_armPC{0xFFFF};
    std::atomic<bool> m_pcArmed{false};
};

} // namespace cu59
