#pragma once
#include "../Core/TMC0501.hpp"

// Persistence of vision for the LED display. The real LEDs have no afterglow
// worth modelling; what the eye sees is the multiplexed display integrated
// over time. The core reports per position how much of each 60 Hz poll it was
// driven (DisplaySnapshot::digitDuty/dpDuty); this turns that into a
// brightness 0..1 per position:
//   • a driven position is at full brightness at once — a steadily multiplexed
//     display (duty ≈ 1, or ≥ kFullDuty while a few cycles of each pass run
//     in RUN mode, as in the error blink) is simply on;
//   • once it is no longer driven it stays on for kHoldSeconds, then fades
//     with time constant kFadeSeconds and goes out at kCutoff. Only the
//     undriven part of each poll counts towards the hold.
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

    /// Advance by one poll covering `seconds` of emulated time.
    void update(const DisplaySnapshot& d, double seconds);
    float digit(int i) const { return static_cast<float>(m_digit[i].level); }
    float dp(int i) const { return static_cast<float>(m_dp[i].level); }
    void reset();

    /// One position: duty (0..1) over `seconds` → brightness (0..1).
    struct Channel {
        double level = 0;
        double dark = 0;  ///< seconds without being driven
        double step(double duty, double seconds);
    };

private:
    Channel m_digit[12];
    Channel m_dp[12];
};

} // namespace cu59
