#include "FreezeController.hpp"

namespace cu59 {

void FreezeController::armScanLoopExit(uint16_t currentPC) {
    m_pcArmed = false;
    m_seenLoop = false;
    m_armPC = currentPC;
    m_scanArmed = true;
}

void FreezeController::armPcChange() {
    disarmScanLoopExit();
    m_pcArmed = true;
}

void FreezeController::disarmScanLoopExit() {
    m_seenLoop = false;
    m_scanArmed = false;
}

void FreezeController::disarmPcChange() { m_pcArmed = false; }

std::optional<FreezeOwner> FreezeController::checkStep(uint16_t pc, bool stepBoundary) {
    if (stepBoundary && m_pcArmed.load(std::memory_order_relaxed)) {
        m_pcArmed = false;
        return FreezeOwner::Calculator;
    }
    if (!m_scanArmed.load(std::memory_order_relaxed)) return std::nullopt;
    if (m_scanLoop.contains(pc)) {
        m_seenLoop = true;
        return std::nullopt;
    }
    if (m_seenLoop || (pc == 0x0000 && m_armPC != 0x0000)) {
        disarmScanLoopExit();
        return FreezeOwner::Cpu;
    }
    return std::nullopt;
}

} // namespace cu59
