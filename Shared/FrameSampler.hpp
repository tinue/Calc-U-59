#pragma once
#include "../Core/TI59Machine.hpp"
#include <string>
#include <vector>

// What the UI picks up from the machine on each 60 Hz frame: printer output,
// core log messages, whether the card reader auto-ejected, and the display —
// held while the display is lit but the CPU has left IDLE (afterglow in RUN
// mode would otherwise flash stale values such as R5) — plus the smoothed
// "C" (calculating) indicator.

namespace cu59 {

struct FrameUpdate {
    /// False while the display is held (lit, not IDLE): keep showing the last frame.
    bool displayUpdated = false;
    DisplaySnapshot display;
    double calcIndicatorOpacity = 0;      ///< 0–0.65, see FrameSampler
    std::vector<std::string> printerLines;
    std::vector<PrinterCodeLine> printerCodeLines;
    std::vector<std::string> logLines;    ///< core debug messages at or below debugLevel
    /// The card was passing and the core ejected it (at CRD_OFF, as the real
    /// card leaves the reader after each pass): the frontend saves written data.
    bool cardAutoEjected = false;
};

class FrameSampler {
public:
    /// debugLevel: 0 off, 1 info, 2 debug. cardSwiping: the frontend's card state.
    FrameUpdate tick(TI59Machine& m, int debugLevel, bool cardSwiping);

    /// Forget the indicator history (new machine).
    void reset();

    /// Advance the C-indicator smoothing by one frame with the core's duty
    /// cycle (DisplaySnapshot::calcIndicator); returns the new opacity.
    double updateCalcIndicator(float duty);

private:
    double m_calcOpacity = 0;
    int m_zeroFrames = 0;
};

} // namespace cu59
