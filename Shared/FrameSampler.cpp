#include "FrameSampler.hpp"
#include <algorithm>
#include <cmath>
#include <cstring>

namespace cu59 {

bool LedFrame::operator==(const LedFrame& o) const {
    return std::memcmp(digits, o.digits, sizeof digits) == 0 && std::memcmp(ctrl, o.ctrl, sizeof ctrl) == 0 &&
           std::memcmp(digitLevel, o.digitLevel, sizeof digitLevel) == 0 &&
           std::memcmp(dpLevel, o.dpLevel, sizeof dpLevel) == 0;
}

FrameUpdate FrameSampler::tick(TI59Machine& m, double instructionHz, int debugLevel, bool cardSwiping) {
    FrameUpdate u;
    u.cardAutoEjected = cardSwiping && !m.isCardPresent();
    u.printerLines = m.drainPrinterLines();
    if (debugLevel > 0) {
        for (const auto& e : m.drainDebugEvents())
            if (e.level <= debugLevel) u.logLines.emplace_back(e.msg);
    }
    u.printerCodeLines = m.drainPrinterCodeLines();

    u.display = m.takeDisplay();
    m_pov.update(u.display, u.display.pollTicks / instructionHz);
    auto level = [](float b) { return static_cast<uint8_t>(std::lround(b * 255.0f)); };
    for (int i = 0; i < 12; ++i) {
        u.led.digits[i] = u.display.digits[i];
        u.led.ctrl[i] = u.display.ctrl[i];
        u.led.digitLevel[i] = level(m_pov.digit(i));
        u.led.dpLevel[i] = level(m_pov.dp(i));
    }

    u.calcIndicatorOpacity = updateCalcIndicator(u.display.calcIndicator);
    return u;
}

void FrameSampler::reset() {
    m_calcOpacity = 0;
    m_zeroFrames = 0;
    m_pov = {};
}

// The C indicator follows the core's mean drive (DisplaySnapshot::calcIndicator):
// its brightness changes at once, as on a real TI-59, whose C visibly jumps
// while a program runs and between the phases of a blink. The one exception is
// 60 Hz aliasing: the ROM's IDLE display scan lasts ~4.5 ms (16 IDLE steps ×
// 281 µs), so one 16.7 ms poll can see a single zero-drive frame although the
// real dark gap is imperceptible. Hence:
//   target 0, first frame   → hold (aliasing artefact)
//   target 0, frame 2+      → decay fast (a real dark phase: error blink, …)
//   otherwise               → the target
// An opacity is not linear in light, hence the display gamma: drive 1 (one bit,
// the dark phase of a blink) gives 0.65, drive 0.09 (its lit phase) a very weak
// but visible C, and several bits at once reach full brightness.
double FrameSampler::updateCalcIndicator(float drive) {
    const double target = std::min(1.0, std::pow(static_cast<double>(drive), 1.0 / 2.2) * 0.65);
    if (target < 0.001) {
        ++m_zeroFrames;
        if (m_zeroFrames >= 2) {
            double decay = std::min(0.65, 0.35 * (m_zeroFrames - 1));
            m_calcOpacity = std::max(0.0, m_calcOpacity - decay);
        }
    } else {
        m_zeroFrames = 0;
        m_calcOpacity = target;
    }
    return m_calcOpacity;
}

} // namespace cu59
