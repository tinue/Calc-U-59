#include "Pacing.hpp"

namespace cu59 {

BatchResult runBatch(TI59Machine& m, int32_t& carry, int32_t targetCycles, FreezeController& freeze) {
    BatchResult r;
    while (carry < targetCycles) {
        uint32_t result = m.step();
        if (result & 0x8000'0000u) {
            r.stop = BatchResult::Stop::Breakpoint;
            return r;
        }
        if (result & 0x4000'0000u) r.polledHardware = true;
        carry += static_cast<int32_t>(result & 0x3FFF'FFFFu);
        if (freeze.checkStep(m.pc())) {
            r.stop = BatchResult::Stop::Freeze;
            r.freezeOwner = FreezeOwner::Cpu;
            return r;
        }
    }
    // Subtract rather than reset: the overshoot carries into the next batch.
    carry -= targetCycles;
    if (freeze.checkBatch(m)) {
        r.stop = BatchResult::Stop::Freeze;
        r.freezeOwner = FreezeOwner::Calculator;
    }
    return r;
}

bool shouldSleep(bool fullSpeed, uint16_t pc, bool polledHardware, Model model) {
    if (!fullSpeed) return true;
    return info(model).idleAndKeyDetect.contains(pc) || polledHardware;
}

} // namespace cu59
