#include "Pacing.hpp"

namespace cu59 {

BatchResult runBatch(TI59Machine& m, int32_t& carry, int32_t targetCycles, FreezeController& freeze) {
    BatchResult r;
    while (carry < targetCycles) {
        uint32_t result = m.step();
        if (result & TI59Machine::kBreakpointHit) {
            r.stop = BatchResult::Stop::Breakpoint;
            return r;
        }
        if (result & TI59Machine::kPolledHardware) r.polledHardware = true;
        carry += static_cast<int32_t>(result & TI59Machine::kWeightMask);
        if (auto owner = freeze.checkStep(m.pc(), (result & TI59Machine::kStepBoundary) != 0)) {
            r.stop = BatchResult::Stop::Freeze;
            r.freezeOwner = *owner;
            return r;
        }
    }
    // Subtract rather than reset: the overshoot carries into the next batch.
    carry -= targetCycles;
    return r;
}

bool shouldSleep(bool fullSpeed, uint16_t pc, bool polledHardware, Model model) {
    if (!fullSpeed) return true;
    return info(model).idleAndKeyDetect.contains(pc) || polledHardware;
}

} // namespace cu59
