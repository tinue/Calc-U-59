#include "DebugText.hpp"
#include <cmath>
#include <cstdio>

namespace cu59 {

namespace {
uint32_t rgb(double r, double g, double b) {
    auto c = [](double v) { return static_cast<uint32_t>(std::lround(v * 255)); };
    return c(r) << 16 | c(g) << 8 | c(b);
}
} // namespace

int debugPanelFontSize(double width) { return width < 350 ? 9 : width < 500 ? 11 : 13; }

std::string partitionLine(int programRegCount, int dataRegCount) {
    int totalSteps = programRegCount * 8;
    int lastStep = totalSteps > 0 ? totalSteps - 1 : 0;
    std::string part = "(" + std::to_string(lastStep) + "." +
                       (dataRegCount > 0 ? std::to_string(dataRegCount - 1) : std::string()) + ")";
    return "Steps: " + std::to_string(totalSteps) + ", Registers: " + std::to_string(dataRegCount) + " " + part;
}

std::string angleModeLabel(std::optional<AngleMode> mode) {
    if (!mode) return "?";
    switch (*mode) {
    case AngleMode::Deg: return "DEG";
    case AngleMode::Rad: return "RAD";
    case AngleMode::Grad: return "GRAD";
    }
    return "?";
}

std::string registerLine(const LiveDebugSnapshot::RegEntry& r) {
    char buf[48];
    std::snprintf(buf, sizeof buf, "%c%02d = %.13g", r.isHidden ? 'H' : 'R', r.num, r.value);
    return buf;
}

std::string hirLine(int n, double value) {
    char buf[40];
    std::snprintf(buf, sizeof buf, "%d: %.5g", n, value);
    return buf;
}

std::string tRegisterLine(double value) {
    char buf[40];
    std::snprintf(buf, sizeof buf, "T: %.13g", value);
    return buf;
}

std::string xRegisterLine(double value, const std::string& raw) {
    if (!raw.empty()) return "X: " + raw;
    char buf[40];
    std::snprintf(buf, sizeof buf, "X: %.13g", value);
    return buf;
}

uint32_t xRegisterColor(double value, const std::string& raw) {
    if (!raw.empty()) return rgb(0.85, 0.6, 0.25);
    return value == 0 ? rgb(0.6, 0.6, 0.6) : rgb(0.85, 0.85, 0.85);
}

std::string currentStepMarker(bool frozen) { return frozen ? "← next" : "← running"; }

std::string programStepLine(const StepEntry& e, bool frozen) {
    char buf[16];
    std::snprintf(buf, sizeof buf, "%03d  %02d  ", e.stepNum, e.keycode);
    std::string s = buf + e.mnemonic;
    if (e.isCurrent) s += "  " + currentStepMarker(frozen);
    return s;
}

std::string returnLevelLine(int level, int address) {
    char buf[16];
    std::snprintf(buf, sizeof buf, "L%d:%03d", level, address);
    return buf;
}

std::string inspectorLine(const InspectorEntry& e) {
    char buf[16];
    std::snprintf(buf, sizeof buf, "%04X  %04X  ", e.pc, e.opcode);
    return buf + e.disasm;
}

uint32_t returnLevelColor(uint8_t sourceFlag, bool zero) {
    switch (sourceFlag) {
    case 0: return zero ? rgb(0.10, 0.30, 0.10) : rgb(0.25, 0.60, 0.25);
    case 1: case 2: return zero ? rgb(0.30, 0.10, 0.30) : rgb(0.60, 0.25, 0.60);
    case 8: return zero ? rgb(0.35, 0.28, 0.10) : rgb(0.70, 0.60, 0.25);
    default: return zero ? rgb(0.6, 0.6, 0.6) : rgb(0.8, 0.8, 0.8);
    }
}

uint32_t stepHighlightColor(ProgramSource source) {
    if (source == ProgramSource::Rom) return rgb(0.35, 0.28, 0.10);
    if (source == ProgramSource::SolidState) return rgb(0.10, 0.24, 0.35);
    return rgb(0.10, 0.30, 0.10);
}

std::string registerNibbles(const uint8_t nibbles[16]) {
    static const char* kHex = "0123456789ABCDEF";
    std::string s(16, '0');
    for (int i = 0; i < 16; ++i) s[static_cast<size_t>(15 - i)] = kHex[nibbles[i] & 0xF];
    return s;
}

std::string hexBin16(uint16_t v) {
    char buf[8];
    std::snprintf(buf, sizeof buf, "%04X", v);
    std::string s = std::string(buf) + " [";
    for (int i = 15; i >= 0; --i) {
        s += ((v >> i) & 1) ? '1' : '0';
        if (i % 4 == 0 && i) s += ' ';
    }
    return s + "]";
}

} // namespace cu59
