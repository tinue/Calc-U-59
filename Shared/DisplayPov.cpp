#include "DisplayPov.hpp"
#include <algorithm>
#include <cmath>

namespace cu59 {

double DisplayPov::Channel::step(double duty, double seconds) {
    const double d = std::min(1.0, duty / kFullDuty);
    if (d >= 1.0) {               // driven through the whole poll: simply on
        dark = 0;
        level = 1.0;
        return level;
    }
    // Only the undriven part of the poll counts towards the hold; the
    // brightness never drops below what this poll's own duty shows.
    const double before = dark;
    dark += seconds * (1.0 - d);
    const double fading = dark - std::max(before, kHoldSeconds);
    if (fading > 0) level *= std::exp(-fading / kFadeSeconds);
    level = std::max(level, d);
    if (level < kCutoff) level = 0;
    return level;
}

void DisplayPov::update(const DisplaySnapshot& d, double seconds) {
    for (int i = 0; i < 12; ++i) {
        m_digit[i].step(d.digitDuty[i], seconds);
        m_dp[i].step(d.dpDuty[i], seconds);
    }
}

} // namespace cu59
