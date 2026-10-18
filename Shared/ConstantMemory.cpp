#include "ConstantMemory.hpp"
#include "Bcd.hpp"
#include "TextUtil.hpp"
#include <algorithm>
#include <cstdio>

namespace cu59 {

std::string encodeConstantMemory(const std::vector<uint8_t>& ram, const CueCardContent* cueCard) {
    std::vector<std::string> lines;
    if (cueCard) {
        lines.emplace_back("CUECARD:");
        for (auto& l : cueCard->encodeToLines(CueCardTemplate::CueCard)) lines.push_back(l);
        lines.emplace_back();
    }
    lines.emplace_back("── Registers (raw values) ──");
    for (size_t reg = 0; reg < 120; ++reg) {
        size_t off = reg * 16;
        if (off + 16 > ram.size()) break;
        Nibbles16 nib{};
        std::copy(ram.begin() + static_cast<long>(off), ram.begin() + static_cast<long>(off + 16), nib.begin());
        if (std::all_of(nib.begin(), nib.end(), [](uint8_t v) { return v == 0; })) continue;
        char label[16];
        std::snprintf(label, sizeof label, "R%03zu: ", reg);
        lines.push_back(label + registerLineHex(nib));
    }
    std::string out;
    for (size_t i = 0; i < lines.size(); ++i) {
        if (i) out += '\n';
        out += lines[i];
    }
    return out;
}

std::optional<ConstantMemoryContents> decodeConstantMemory(std::string_view text) {
    ConstantMemoryContents c;
    c.ram.assign(kConstantMemoryBytes, 0);
    bool inCueCard = false;
    for (std::string_view raw : splitLines(text)) {
        std::string_view line = trim(raw);
        if (line.empty()) continue;
        if (startsWith(line, "CUECARD:")) {
            inCueCard = true;
            c.cueCard = CueCardContent();
            continue;
        }
        if (startsWith(line, "──")) {
            inCueCard = false;
            continue;
        }
        if (inCueCard) {
            c.cueCard->parseLine(line);
            continue;
        }
        if (line[0] != 'R') continue;
        auto parts = splitOn(line, ":");
        if (parts.size() != 2) return std::nullopt;
        auto reg = parseDec(parts[0].substr(1));
        if (!reg || *reg < 0 || *reg >= 120) return std::nullopt;
        auto tokens = splitWords(trim(parts[1]));
        if (tokens.size() != 8) return std::nullopt;
        std::array<uint8_t, 8> bytes{};
        for (size_t i = 0; i < 8; ++i) {
            auto v = parseHex(tokens[i]);
            if (!v || *v > 0xFF) return std::nullopt;
            bytes[i] = static_cast<uint8_t>(*v);
        }
        Nibbles16 nib = decodeRegisterLine(bytes);
        std::copy(nib.begin(), nib.end(), c.ram.begin() + *reg * 16);
    }
    return c;
}

} // namespace cu59
