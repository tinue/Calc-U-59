#include "ModuleImage.hpp"
#include <cstdio>

namespace cu59 {

ProgramSource programSourceFrom(uint8_t flag, uint16_t romPC) {
    if (flag & 0x1) return ProgramSource::SolidState;
    if (flag & 0x8) return ProgramSource::Rom;
    if (flag == 0) return ProgramSource::UserProgram;
    if (flag == 2 && ((romPC >= 0x1193 && romPC <= 0x1194) || (romPC >= 0x14F9 && romPC <= 0x1506)))
        return ProgramSource::SolidStateReturn;
    return ProgramSource::FastMode;
}

std::string programSourceLabel(ProgramSource source, uint8_t flag) {
    char raw[8];
    std::snprintf(raw, sizeof raw, "%X", flag);
    switch (source) {
    case ProgramSource::UserProgram: return "Prg Source: User Program";
    case ProgramSource::SolidState:
        return std::string("Prg Source: Solid State Program") + (flag == 1 ? "" : std::string(" (") + raw + ")");
    case ProgramSource::SolidStateReturn: return "Prg Source: Solid State Return (PC Reload)";
    case ProgramSource::FastMode: return std::string("Prg Source: User Program (Fast Mode, ") + raw + ")";
    case ProgramSource::Rom:
        return std::string("Prg Source: ROM Program") + (flag == 8 ? "" : std::string(" (") + raw + ")");
    }
    return "";
}

ModuleImage ModuleImage::parse(const std::vector<uint8_t>& raw, std::string* error) {
    auto bcd = [](uint8_t b) { return (b >> 4) * 10 + (b & 0xF); };
    ModuleImage m;
    m.keycodes.reserve(raw.size());
    for (uint8_t b : raw) m.keycodes.push_back(static_cast<uint8_t>(bcd(b)));
    if (raw.size() <= 2) return m;

    int programCount = bcd(raw[0]);
    if (programCount <= 0) return m;
    // Program n's start pointer lives at bytes 2n/2n+1; the entry after the
    // last program's pointer marks the end of the last program.
    std::vector<int> boundaries;
    for (int n = 1; n <= programCount + 1; ++n) {
        size_t off = static_cast<size_t>(2 * n);
        if (off + 1 >= raw.size()) return m;
        boundaries.push_back(bcd(raw[off]) * 100 + bcd(raw[off + 1]));
    }
    std::vector<std::pair<int, int>> ranges;
    for (int i = 0; i < programCount; ++i) {
        if (!(boundaries[i] < boundaries[i + 1] && boundaries[i + 1] <= static_cast<int>(m.keycodes.size()))) {
            if (error) *error = "Module header has non-monotonic program table; solid-state step view disabled";
            return m;
        }
        ranges.emplace_back(boundaries[i], boundaries[i + 1]);
    }
    m.programRanges = std::move(ranges);
    return m;
}

std::optional<ModuleImage::LibStep> ModuleImage::libraryStep(uint16_t libExecPC) const {
    if (libExecPC == 0xFFFF) return std::nullopt;
    int pc = libExecPC;
    for (size_t i = 0; i < programRanges.size(); ++i) {
        auto [lo, hi] = programRanges[i];
        if (pc >= lo && pc < hi) return LibStep{static_cast<int>(i) + 1, pc - lo, lo, hi};
    }
    return std::nullopt;
}

} // namespace cu59
