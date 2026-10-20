#pragma once
#include "../Core/TMC0501.hpp"
#include <algorithm>
#include <cmath>

// Persistence of vision for the LED display. The real LEDs have no afterglow
// worth modelling; what the eye sees is the multiplexed display integrated
// over time. The core reports per position how much of each 60 Hz poll it was
// driven (DisplaySnapshot::digitDuty/dpDuty); this turns that into a
// brightness 0..1 per position, the product of two parts:
//   • presence: a driven position is on at once — a steadily multiplexed
//     display (duty ≈ 1, or ≥ kFullDuty while a few cycles of each pass run
//     in RUN mode, as in the error blink) is simply on. Once it is no longer
//     driven it stays on for kHoldSeconds, then fades with time constant
//     kFadeSeconds and goes out at kCutoff. Only the undriven part of each
//     poll counts towards the hold.
//   • share: the position's part of the multiplex — its mean duty over the
//     best-driven position's, averaged the way the eye does (kShareSeconds) —
//     relative to the best share on the display. In the error blink each pass
//     leaves IDLE before the sweep reaches the right-hand digits every time,
//     so they get less of it (TI-59 75%, TI-58 50%): on a real TI-59 they look
//     a little dimmer, steadily. Perceived brightness goes with the square
//     root of the light (Stevens' power law for brightness), so 75% looks
//     like 87%. Which 60 Hz polls catch the short sweeps varies, so the share
//     is averaged instead of taken per poll, and presence counts a position
//     as fully driven at its usual share. A computation darkens every
//     position alike and leaves the shares alone.
// Integrating over the whole poll removes the aliasing between the multiplex
// rhythm and the 60 Hz poll. Calibrated on a real TI-59: the ≈ 11 ms a digit
// key keeps the display dark is invisible, x² and 1/x (50–63 ms) are at the
// threshold, sin (≈ 350 ms) visibly darkens, and the 0.45 s error-blink phases
// stay crisp. The "C" indicator has its own path (FrameSampler).

namespace cu59 {

class DisplayPov {
public:
    static constexpr double kHoldSeconds = 0.055;
    static constexpr double kFadeSeconds = 0.03;
    static constexpr double kFullDuty = 0.75;
    static constexpr double kCutoff = 0.15;   ///< below this the eye sees the digit as off
    static constexpr double kShareSeconds = 0.1;
    static constexpr double kShareMinDuty = 0.8;  ///< polls that teach the share: display multiplexed nearly throughout
    static constexpr double kShareFull = 0.95;    ///< a share this close to the best is full: averaging noise never shows

    /// Advance by one poll covering `seconds` of emulated time.
    void update(const DisplaySnapshot& d, double seconds);
    float digit(int i) const { return static_cast<float>(m_digit[i].brightness(m_bestShare)); }
    float dp(int i) const { return static_cast<float>(m_dp[i].brightness(m_bestShare)); }

    /// One position: duty (0..1) over `seconds`, with the best-driven
    /// position's duty in the same poll → presence and share.
    struct Channel {
        double level = 0;     ///< presence
        double dark = 0;      ///< seconds without being driven
        double duty = 1;      ///< averaged own duty …
        double bestDuty = 1;  ///< … and the best-driven position's, over the same polls
        double shareSeconds = 0;  ///< time the averages have seen
        double step(double polled, double maxDuty, double seconds);
        double share() const { return duty / bestDuty; }
        /// Brightness as seen next to the display's best-driven position.
        double brightness(double bestShare) const {
            const double rel = share() / bestShare;
            const double b = level * (rel >= kShareFull ? 1.0 : std::sqrt(rel));
            return b < kCutoff ? 0 : b;
        }
    };

private:
    Channel m_digit[12];
    Channel m_dp[12];
    double m_bestShare = 1;
};

} // namespace cu59
