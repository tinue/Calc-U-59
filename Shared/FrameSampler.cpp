#include "FrameSampler.hpp"
#include <algorithm>

namespace cu59 {

FrameUpdate FrameSampler::tick(TI59Machine& m, int debugLevel, bool cardSwiping) {
    FrameUpdate u;
    u.cardAutoEjected = cardSwiping && !m.isCardPresent();
    u.printerLines = m.drainPrinterLines();
    if (debugLevel > 0) {
        for (const auto& e : m.drainDebugEvents())
            if (e.level <= debugLevel) u.logLines.emplace_back(e.msg);
    }
    u.printerCodeLines = m.drainPrinterCodeLines();

    u.display = m.getDisplay();
    CpuFrame cpu = m.snapshotCPU();
    bool idle = (cpu.flags & FLG_IDLE) != 0;
    bool displayOn = cpu.displayOn != 0;  // one or more digits or dots visible
    u.displayUpdated = !(displayOn && !idle);

    u.calcIndicatorOpacity = updateCalcIndicator(u.display.calcIndicator);
    return u;
}

void FrameSampler::reset() {
    m_calcOpacity = 0;
    m_zeroFrames = 0;
}

// The C indicator follows the core's integrated duty cycle. Hardware (Sladký
// 2014 HW guide): in IDLE, C is driven by fA[14] only; in RUN, by any fA bit.
// 60 Hz aliasing: the ROM's IDLE display scan lasts ~4.5 ms (16 IDLE steps ×
// 281 µs), so one 16.7 ms poll can see a single zero-duty frame although the
// real dark gap is imperceptible. Hence:
//   target > current        → rise instantly
//   target 0, first frame   → hold (aliasing artefact)
//   target 0, frame 2+      → decay fast (a real dark phase: error blink, …)
//   0 < target < current    → proportional fall
double FrameSampler::updateCalcIndicator(float duty) {
    double target = static_cast<double>(duty) * 0.65;
    if (target < 0.001) {
        ++m_zeroFrames;
        if (m_zeroFrames >= 2) {
            double decay = std::min(0.65, 0.35 * (m_zeroFrames - 1));
            m_calcOpacity = std::max(0.0, m_calcOpacity - decay);
        }
    } else if (target >= m_calcOpacity) {
        m_zeroFrames = 0;
        m_calcOpacity = target;
    } else {
        m_zeroFrames = 0;
        double alpha = std::min(0.5, target / std::max(0.001, m_calcOpacity));
        m_calcOpacity += alpha * (target - m_calcOpacity);
    }
    return m_calcOpacity;
}

} // namespace cu59
