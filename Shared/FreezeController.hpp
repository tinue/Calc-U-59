#pragma once
#include "../Core/TI59Machine.hpp"
#include "MachineModelInfo.hpp"
#include <atomic>
#include <cstdint>

// The debugger's armed freezes, checked from the run loop:
//  - FREEZE ON START (CPU tab): fires when the CPU leaves the steady keyboard
//    scan loop — a key press, or a reset (PC jumps to 0000) while running.
//  - Freeze on next PC change (CALCULATOR tab): fires when the calculator PC
//    (SCOM[0]) or the solid-state exec latch moves.
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
    /// Freeze on the next calculator-PC change, from the current SCOM PC and exec latch.
    void armPcChange(const TI59Machine& m);
    void disarmScanLoopExit();
    void disarmPcChange();
    void disarmAll();

    bool scanLoopExitArmed() const { return m_scanArmed.load(); }
    bool pcChangeArmed() const { return m_pcArmed.load(); }

    /// Per instruction (exact PC: a per-batch check lands hundreds of
    /// instructions late after a reset clears the loop in one burst). True
    /// when FREEZE ON START fires; it disarms itself.
    bool checkStep(uint16_t pc);

    /// Per batch. True when the PC-change freeze fires; it disarms itself.
    bool checkBatch(const TI59Machine& m);

private:
    const PcRange m_scanLoop;
    std::atomic<bool> m_scanArmed{false};
    std::atomic<bool> m_seenLoop{false};
    std::atomic<uint16_t> m_armPC{0xFFFF};
    std::atomic<bool> m_pcArmed{false};
    std::atomic<uint16_t> m_lastScomPC{0};
    std::atomic<uint16_t> m_lastLibPC{0xFFFF};
};

} // namespace cu59
