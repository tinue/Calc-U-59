#include "DisplayPov.hpp"
#include <algorithm>
#include <cmath>

namespace cu59 {

double DisplayPov::Channel::step(double polled, double maxDuty, double seconds) {
    // Share: time-weighted means over the position's first polls, so it is
    // right at once, then running averages carried across dark phases. Time
    // weighting makes the ratio follow the integrated driven time, whatever
    // the poll length (a poll shorter than a sweep drives positions unevenly).
    if (polled > 0 && maxDuty >= kShareMinDuty) {
        shareSeconds += seconds;
        const double a = std::max(seconds / shareSeconds, 1.0 - std::exp(-seconds / kShareSeconds));
        duty += (polled - duty) * a;
        bestDuty += (maxDuty - bestDuty) * a;
    }
    const double d = std::min(1.0, polled / share() / kFullDuty);
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
    const double maxDuty = *std::max_element(std::begin(d.digitDuty), std::end(d.digitDuty));
    double best = 0;
    for (int i = 0; i < 12; ++i) {
        m_digit[i].step(d.digitDuty[i], maxDuty, seconds);
        m_dp[i].step(d.dpDuty[i], maxDuty, seconds);
        if (m_digit[i].level > 0) best = std::max(best, m_digit[i].share());
    }
    if (best > 0) m_bestShare = best;
}

} // namespace cu59
