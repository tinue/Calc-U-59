#include "RomLoader.hpp"
#include "TextUtil.hpp"
#include <algorithm>
#include <fstream>
#include <sstream>

namespace cu59 {

std::vector<uint16_t> parseRomTxt(std::string_view text) {
    std::vector<uint16_t> words;
    bool inData = false;
    for (std::string_view line : splitLines(text)) {
        std::string_view s = trim(line);
        if (!inData) {
            if (startsWith(s, "---")) inData = true;
            continue;
        }
        if (s.empty()) continue;
        size_t colon = s.find(':');
        if (colon == std::string_view::npos) continue;
        std::string_view addr = trim(s.substr(0, colon));
        if (addr.size() != 4 || !parseHex(addr)) continue;
        for (std::string_view w : splitWords(s.substr(colon + 1))) {
            auto v = parseHex(w);
            if (!v || *v > 0xFFFF) throw RomError("invalid hex word: " + std::string(w));
            words.push_back(static_cast<uint16_t>(*v & 0x1FFF));
        }
    }
    return words;
}

std::vector<std::vector<uint8_t>> parseConstantsTxt(std::string_view text) {
    std::vector<std::vector<uint8_t>> rows;
    bool inNumber = false;
    for (std::string_view line : splitLines(text)) {
        std::string_view s = trim(line);
        if (s.find("CONSTANT ROM (NUMBER)") != std::string_view::npos) {
            inNumber = true;
            continue;
        }
        if (startsWith(s, "---")) {
            if (inNumber) break;
            continue;
        }
        if (!inNumber || s.empty()) continue;
        size_t colon = s.find(':');
        if (colon == std::string_view::npos) continue;
        std::string_view addr = trim(s.substr(0, colon));
        if (addr.empty() || !parseDec(addr)) continue;
        std::string_view hex = trim(s.substr(colon + 1));
        if (hex.size() != 16) continue;
        std::vector<uint8_t> nibbles;
        for (auto it = hex.rbegin(); it != hex.rend(); ++it) {
            int n = hexDigit(*it);
            if (n < 0) throw RomError(std::string("invalid hex nibble: ") + *it);
            nibbles.push_back(static_cast<uint8_t>(n));
        }
        rows.push_back(std::move(nibbles));
    }
    return rows;
}

std::optional<std::vector<uint8_t>> parseModuleTxt(std::string_view text) {
    constexpr int kMaxBytes = 5000;
    std::vector<uint8_t> bytes(kMaxBytes, 0);
    int maxAddr = 0;
    bool inData = false;
    for (std::string_view line : splitLines(text)) {
        std::string_view s = trim(line);
        if (!inData) {
            if (startsWith(s, "---")) inData = true;
            continue;
        }
        // Some dumps include an "ADDR: BCD DATA" header; others start with rows.
        std::string upper = toUpper(s);
        if (startsWith(upper, "ADDR:") && upper.find("DATA") != std::string::npos) continue;
        if (s.empty()) continue;
        size_t colon = s.find(':');
        if (colon == std::string_view::npos) continue;
        auto addr = parseDec(trim(s.substr(0, colon)));
        if (!addr) continue;
        // BCD values: "21" means 0x21, not decimal 21. Unparseable tokens are dropped.
        int i = 0;
        for (std::string_view tok : splitWords(s.substr(colon + 1))) {
            auto v = parseHex(tok);
            if (!v || *v > 0xFF) continue;
            long idx = *addr + i++;
            if (idx >= 0 && idx < kMaxBytes) {
                bytes[static_cast<size_t>(idx)] = static_cast<uint8_t>(*v);
                maxAddr = std::max(maxAddr, static_cast<int>(idx) + 1);
            }
        }
    }
    if (maxAddr == 0) return std::nullopt;
    bytes.resize(static_cast<size_t>(maxAddr));
    return bytes;
}

namespace {

std::string readOrThrow(const std::string& name, const ResourceReader& read) {
    auto text = read(name);
    if (!text) throw RomError("ROM file not found: " + name);
    return *text;
}

std::string hex4(uint16_t v) {
    static const char* digits = "0123456789ABCDEF";
    std::string s;
    for (int sh = 12; sh >= 0; sh -= 4) s += digits[(v >> sh) & 0xF];
    return s;
}

} // namespace

std::vector<uint16_t> loadRom(Model model, const ResourceReader& read) {
    const ModelInfo& mi = info(model);
    std::vector<uint16_t> words;
    words.reserve(static_cast<size_t>(mi.romWordCount));
    for (const char* name : mi.romFiles) {
        auto part = parseRomTxt(readOrThrow(name, read));
        words.insert(words.end(), part.begin(), part.end());
    }
    if (static_cast<int>(words.size()) != mi.romWordCount)
        throw RomError("wrong ROM word count: " + std::to_string(words.size()));
    if (mi.hasLargeMemory) {
        // Sentinels from the known-good TI-59 ROM image: words[0] = 0x0A01 (the
        // first instruction, CLR IDL); words[6143] = 0x1987 (the last). A
        // mismatch means the file is corrupt, truncated or the wrong variant.
        if (words[0] != 0x0A01)
            throw RomError("words[0] expected 0x0A01, got 0x" + hex4(words[0]));
        if (words[6143] != 0x1987)
            throw RomError("words[6143] expected 0x1987, got 0x" + hex4(words[6143]));
    }
    return words;
}

std::vector<uint8_t> loadConstants(Model model, const ResourceReader& read) {
    std::vector<std::vector<uint8_t>> rows;
    for (const char* name : info(model).constFiles) {
        auto part = parseConstantsTxt(readOrThrow(name, read));
        rows.insert(rows.end(), part.begin(), part.end());
    }
    if (rows.size() != 64)
        throw RomError("expected 64 constant rows, got " + std::to_string(rows.size()));
    std::vector<uint8_t> bytes;
    bytes.reserve(64 * 16);
    for (const auto& r : rows) bytes.insert(bytes.end(), r.begin(), r.end());
    return bytes;
}

ResourceReader directoryReader(std::vector<std::string> dirs) {
    return [dirs = std::move(dirs)](const std::string& name) -> std::optional<std::string> {
        for (const auto& dir : dirs) {
            std::ifstream f(dir + "/" + name, std::ios::binary);
            if (!f) continue;
            std::ostringstream ss;
            ss << f.rdbuf();
            return ss.str();
        }
        return std::nullopt;
    };
}

std::optional<std::vector<uint8_t>> loadModule(const std::string& romFile, const ResourceReader& read) {
    auto text = read(romFile);
    if (!text) return std::nullopt;
    return parseModuleTxt(*text);
}

} // namespace cu59
