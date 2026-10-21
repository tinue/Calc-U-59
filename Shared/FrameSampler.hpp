#pragma once
#include "../Core/TI59Machine.hpp"
#include "DisplayPov.hpp"
#include <string>
#include <vector>

// What the UI picks up from the machine on each 60 Hz frame: printer output,
// core log messages, whether the card reader auto-ejected, and the display —
// each position's last glyph with its brightness as the eye sees it
// (DisplayPov) — plus the smoothed "C" (calculating) indicator.

namespace cu59 {

/// The display as drawn: glyphs and per-position brightness 0–255.
struct LedFrame {
    uint8_t digits[12]{};     ///< last driven glyph per position (DisplaySnapshot::digits)
    uint8_t ctrl[12]{};
    uint8_t digitLevel[12]{}; ///< 0 = dark … 255 = fully lit
    uint8_t dpLevel[12]{};    ///< decimal point of each position
    bool operator==(const LedFrame& o) const;
    bool operator!=(const LedFrame& o) const { return !(*this == o); }
};

struct FrameUpdate {
    DisplaySnapshot display;  ///< the core's raw snapshot (duties, latched glyphs)
    LedFrame led;
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
    /// instructionHz converts the poll's weighted cycles to emulated seconds.
    FrameUpdate tick(TI59Machine& m, double instructionHz, int debugLevel, bool cardSwiping);

    /// Forget the indicator history (new machine).
    void reset();

    /// Advance the C-indicator smoothing by one frame with the core's duty
    /// cycle (DisplaySnapshot::calcIndicator); returns the new opacity.
    double updateCalcIndicator(float duty);

private:
    double m_calcOpacity = 0;
    int m_zeroFrames = 0;
    DisplayPov m_pov;
};

} // namespace cu59
