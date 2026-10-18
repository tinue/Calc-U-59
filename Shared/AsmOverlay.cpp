#include "AsmOverlay.hpp"
#include "TextUtil.hpp"

namespace cu59 {

namespace {
bool isHex(char c) { return hexDigit(c) >= 0; }
} // namespace

std::vector<uint16_t> parseAsmWords(std::string_view text) {
    auto lines = splitLines(text);
    size_t hexLine = lines.size();
    for (size_t i = 0; i < lines.size(); ++i) {
        if (toUpper(trim(lines[i])) == "HEX:") { hexLine = i; break; }
    }
    if (hexLine == lines.size()) throw AsmParseError("No HEX: section found in ASM file.");
    std::string hexText;
    for (size_t i = hexLine + 1; i < lines.size(); ++i) {
        if (i > hexLine + 1) hexText += '\n';
        hexText += lines[i];
    }

    // Tokens as the regex 0[xX][0-9A-Fa-f]+|[0-9A-Fa-f]{4,} finds them (leftmost match).
    std::vector<uint16_t> words;
    size_t pos = 0;
    while (pos < hexText.size()) {
        std::string token;
        if (hexText[pos] == '0' && pos + 2 < hexText.size() && (hexText[pos + 1] == 'x' || hexText[pos + 1] == 'X') &&
            isHex(hexText[pos + 2])) {
            size_t e = pos + 2;
            while (e < hexText.size() && isHex(hexText[e])) ++e;
            token = hexText.substr(pos + 2, e - pos - 2);
            pos = e;
        } else {
            size_t e = pos;
            while (e < hexText.size() && isHex(hexText[e])) ++e;
            if (e - pos < 4) { ++pos; continue; }
            token = hexText.substr(pos, e - pos);
            pos = e;
        }
        if (token.size() % 4 != 0) throw AsmParseError("Invalid token in HEX section: " + token);
        for (size_t i = 0; i < token.size(); i += 4)
            words.push_back(static_cast<uint16_t>(*parseHex(std::string_view(token).substr(i, 4)) & 0x1FFF));
    }
    if (words.empty()) throw AsmParseError("No hex opcode words found after HEX: in ASM file.");
    if (words.size() > 2048)
        throw AsmParseError("ASM contains " + std::to_string(words.size()) + " words; maximum is 2048 (0x1800-0x1FFF).");
    return words;
}

AsmRunResult runAsmOverlay(TI59Machine& m, const std::vector<uint16_t>& words) {
    AsmRunResult r;
    m.stepUntilNextKeycode();
    if (!m.loadDebugOverlay(words.data(), words.size())) return r;
    r.loaded = true;
    r.entered = m.runDebugOverlay(0x1800, 8192, &r.steps);
    m.beginNextStep();
    return r;
}

} // namespace cu59
