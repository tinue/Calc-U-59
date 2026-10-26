#pragma once
#include "DebugSnapshots.hpp"
#include <cstdint>
#include <optional>
#include <string>

// Text and colours of the two debug panels (CALCULATOR and CPU) that both
// apps show identically. Colours are packed 0xRRGGBB, as in RomHeatmap.

namespace cu59 {

/// Base font size of both panels by their width: compact / normal / large.
int debugPanelFontSize(double width);

/// iOS window layouts (the Swift app on iPhone and iPad).
enum class MobileLayout {
    Paged,               ///< one page at a time: calculator, printer, debugger (if enabled)
    CalcPrinter,         ///< side by side, no room for the debugger (iPhone in landscape)
    CalcPrinterDebugger, ///< all three side by side (iPad, open iPhone Duo)
};

/// The layout for a window of width × height points. Taller-than-wide windows
/// page; so does a wide one split by a horizontal fold (iPhone Duo half open,
/// "laptop" pose), as its upper half alone is too short. A wide window takes
/// the debugger when it is tall enough to set the three panels side by side
/// (calculator face about 340 pt wide at the Duo's height, printer at least
/// 290, debugger 220). The size is the safe area: iPhone Duo open is 951 ×
/// 669 pt less its status-bar column and home indicator, the widest plain
/// iPhone in landscape about 830 × 420 pt.
MobileLayout mobileLayout(double width, double height, bool horizontalFold);

/// Width range (points) of the printer column in a side-by-side layout. Beside
/// the debugger in a window under 1100 pt (iPhone Duo) the tape is narrow and
/// its print scales down, so the debugger keeps room for its button rows;
/// otherwise (iPad, iPhone landscape) 290–360 pt.
struct WidthRange {
    double min, max;
};
WidthRange mobilePrinterWidth(MobileLayout layout, double width);

/// Space (points) above a side-by-side layout. A window with no top inset
/// (iPhone Duo open, iOS 27.1 simulator) doesn't deliver touches in its top
/// ~30 pt — measured: controls centred at y ≤ 29 dead, ≥ 35 working — so the
/// tabs and printer header keep clear of it.
double mobileTopMargin(double topInset);

/// "Steps: 480, Registers: 60 (479.59)" — "(479.)" when no data registers.
std::string partitionLine(int programRegCount, int dataRegCount);

/// "DEG" / "RAD" / "GRAD", "?" when SCOM doesn't say.
std::string angleModeLabel(std::optional<AngleMode> mode);

/// "R05 = 2.5" (H for the TI-58C's extra registers), the full 13 digits:
/// rounding to the display's 10 can hide stored-value bugs.
std::string registerLine(const LiveDebugSnapshot::RegEntry& r);

/// "1: 3.1416" — HIR n (1–8).
std::string hirLine(int n, double value);

/// "T: 2.71828".
std::string tRegisterLine(double value);

/// "X: 1.414213562373" (all 13 digits), or "X: C=…" when X's register holds no number.
std::string xRegisterLine(double value, const std::string& raw);

/// X's text colour: grey as T (dimmer at 0), amber when shown raw.
uint32_t xRegisterColor(double value, const std::string& raw);

/// Return-stack level colour by its source flag: green user RAM, purple
/// module (2 = saved CROM return address), yellow ROM, grey otherwise;
/// dimmer when the level's address is 0.
uint32_t returnLevelColor(uint8_t sourceFlag, bool zeroAddress);

/// Marker after the current program step: "← next" when frozen (the step
/// about to execute), "← running" while running.
std::string currentStepMarker(bool frozen);

/// A program step: "038  42  STO", with the current-step marker on the current one.
std::string programStepLine(const StepEntry& e, bool frozen);

/// Return-stack level n (1–6): "L1:038".
std::string returnLevelLine(int level, int address);

/// A CPU inspector row: "0837  0A12  " and the disassembly.
std::string inspectorLine(const InspectorEntry& e);

/// Background of the current program step: yellow ROM, blue module, green otherwise.
uint32_t stepHighlightColor(ProgramSource source);

/// CPU inspector: COND and IDLE from the CPU flags word.
inline bool condFlag(uint16_t flags) { return (flags & 0x0800) != 0; }
inline bool idleFlag(uint16_t flags) { return (flags & 0x0001) != 0; }

/// A 16-nibble register as hex, most significant nibble first: "00000000000000A5".
std::string registerNibbles(const uint8_t nibbles[16]);

/// "1F0A [0001 1111 0000 1010]".
std::string hexBin16(uint16_t v);

} // namespace cu59
