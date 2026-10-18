#include "FreezeController.hpp"
#include "DebugSnapshots.hpp"

namespace cu59 {

void FreezeController::armScanLoopExit(uint16_t currentPC) {
    m_pcArmed = false;
    m_seenLoop = false;
    m_armPC = currentPC;
    m_scanArmed = true;
}

void FreezeController::armPcChange(const TI59Machine& m) {
    disarmScanLoopExit();
    m_lastScomPC = static_cast<uint16_t>(decodeProgramCounter(m.snapshotCPU()));
    m_lastLibPC = m.libExecPC();
    m_pcArmed = true;
}

void FreezeController::disarmScanLoopExit() {
    m_seenLoop = false;
    m_scanArmed = false;
}

void FreezeController::disarmPcChange() { m_pcArmed = false; }

void FreezeController::disarmAll() {
    disarmPcChange();
    disarmScanLoopExit();
}

bool FreezeController::checkStep(uint16_t pc) {
    if (!m_scanArmed.load(std::memory_order_relaxed)) return false;
    if (m_scanLoop.contains(pc)) {
        m_seenLoop = true;
        return false;
    }
    if (m_seenLoop || (pc == 0x0000 && m_armPC != 0x0000)) {
        disarmScanLoopExit();
        return true;
    }
    return false;
}

bool FreezeController::checkBatch(const TI59Machine& m) {
    if (!m_pcArmed.load(std::memory_order_relaxed)) return false;
    // Solid-state programs never move the SCOM PC, so the exec latch is a second trigger.
    auto scomPC = static_cast<uint16_t>(decodeProgramCounter(m.snapshotCPU()));
    if (scomPC == m_lastScomPC && m.libExecPC() == m_lastLibPC) return false;
    m_pcArmed = false;
    return true;
}

} // namespace cu59
