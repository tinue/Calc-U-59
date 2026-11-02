#include "CardFile.hpp"
#include "Bcd.hpp"
#include "TextUtil.hpp"
#include <algorithm>
#include <cstdio>

namespace cu59 {

namespace {

enum class Section { None, CueCard, Header, Data };

std::string hex2(unsigned v) {
    char b[8];
    std::snprintf(b, sizeof b, "%02X", v & 0xFF);
    return b;
}

constexpr std::string_view kTextMagic = "Calc-U-59 Card ";
constexpr std::string_view kTextMagicV1 = "Calc-U-59 Card 1";
constexpr std::string_view kTextMagicV2 = "Calc-U-59 Card 2";
constexpr std::string_view kBinaryHeader = "Calc-U-59-CRD";
constexpr std::string_view kEndCard = "END-CARD";

/// Bank 1–4 and the header's page byte (0x10, 0x13, 0x16, 0x19).
uint8_t pageByteOfBank(int bank) { return static_cast<uint8_t>(0x10 | ((bank - 1) * 3)); }
int bankOfPageByte(uint8_t pageByte) { return (pageByte & 0x0F) / 3 + 1; }

void appendCueLines(std::vector<std::string>& lines, const CueCardContent& cue) {
    lines.emplace_back();
    lines.emplace_back("CUECARD:");
    for (auto& l : cue.encodeToLines(CueCardTemplate::MagnetCard)) lines.push_back(l);
}

/// An "R###: …" row's 8 bank bytes; the label is informational only.
std::optional<std::array<uint8_t, 8>> decodeCardRow(std::string_view line) {
    if (line[0] != 'R') return std::nullopt;
    size_t colon = line.find(':');
    if (colon == std::string_view::npos) return std::nullopt;
    auto fileBytes = parseRegisterLineHex(trim(line.substr(colon + 1)));
    if (!fileBytes) return std::nullopt;
    // Card files reverse the bytes relative to ti58c.mem.
    std::array<uint8_t, 8> reversed{};
    std::reverse_copy(fileBytes->begin(), fileBytes->end(), reversed.begin());
    Nibbles16 nib = decodeRegisterLine(reversed);
    std::array<uint8_t, 8> bytes{};
    for (size_t i = 0; i < 8; ++i) bytes[i] = static_cast<uint8_t>((nib[2 * i] << 4) | nib[2 * i + 1]);
    return bytes;
}

/// One side's HEADER and DATA as text lines (the same for v1 and v2).
void appendSideLines(std::vector<std::string>& lines, const std::vector<uint8_t>& data) {
    auto at = [&](size_t i, uint8_t dflt) { return i < data.size() ? data[i] : dflt; };
    uint8_t partition = at(0, 0), dataType = at(1, 0x11), pageByte = at(2, 0x10);
    uint8_t protection = at(3, 0), checksum = at(244, 0);
    int bankNum = bankOfPageByte(pageByte);

    lines.emplace_back("HEADER:");
    lines.push_back("Partition: " + hex2(partition));
    lines.push_back(std::string("DataType: ") + (dataType == 0x11 ? "program" : "data"));
    lines.push_back("Bank: " + std::to_string(bankNum));
    lines.push_back(std::string("Protection: ") + (protection == 0x10 ? "yes" : "no"));
    lines.push_back("Checksum: " + hex2(checksum));

    lines.emplace_back();
    lines.emplace_back("DATA:");
    // 30 registers per bank: bank 1 → R000–R029, bank 2 → R030–R059, …
    int startReg = (bankNum - 1) * 30;
    for (int row = 0; row < 30; ++row) {
        Nibbles16 nib{};
        for (size_t i = 0; i < 8; ++i) {
            uint8_t b = at(4 + static_cast<size_t>(row) * 8 + i, 0);
            nib[2 * i] = b >> 4;
            nib[2 * i + 1] = b & 0x0F;
        }
        auto enc = encodeRegisterLine(nib);
        char label[16];
        std::snprintf(label, sizeof label, "R%03d:", startReg + row);
        std::string line = label;
        for (auto it = enc.rbegin(); it != enc.rend(); ++it) line += " " + hex2(*it);
        lines.push_back(line);
    }
}

std::string joinLines(const std::vector<std::string>& lines) {
    std::string out;
    for (size_t i = 0; i < lines.size(); ++i) {
        if (i) out += '\n';
        out += lines[i];
    }
    return out;
}

/// A side being read from a v2 file; every field is required.
struct SideBuilder {
    bool partition = false, dataType = false, bank = false, protection = false, checksum = false;
    std::vector<uint8_t> data = std::vector<uint8_t>(kCardBankBytes, 0);
    size_t rows = 0;

    bool headerLine(std::string_view line) {
        size_t colon = line.find(':');
        if (colon == std::string_view::npos) return false;
        std::string key = toLower(trim(line.substr(0, colon)));
        std::string val = toLower(trim(line.substr(colon + 1)));
        if (key == "partition") {
            auto v = parseHex(val);
            if (!v || *v > 0xFF) return false;
            data[0] = static_cast<uint8_t>(*v);
            partition = true;
        } else if (key == "datatype") {
            if (val != "program" && val != "data") return false;
            data[1] = val == "program" ? 0x11 : 0x10;
            dataType = true;
        } else if (key == "bank") {
            auto n = parseDec(val);
            if (!n || *n < 1 || *n > 4) return false;
            data[2] = pageByteOfBank(static_cast<int>(*n));
            bank = true;
        } else if (key == "protection") {
            if (val != "yes" && val != "no") return false;
            data[3] = val == "yes" ? 0x10 : 0x00;
            protection = true;
        } else if (key == "checksum") {
            auto v = parseHex(val);
            if (!v || *v > 0xFF) return false;
            data[244] = data[245] = static_cast<uint8_t>(*v);
            checksum = true;
        } else {
            return false;
        }
        return true;
    }

    bool dataLine(std::string_view line) {
        if (rows >= 30) return false;
        auto bytes = decodeCardRow(line);
        if (!bytes) return false;
        std::copy(bytes->begin(), bytes->end(), data.begin() + static_cast<long>(4 + rows * 8));
        ++rows;
        return true;
    }

    bool complete() const { return partition && dataType && bank && protection && checksum && rows == 30; }
};

/// The text after "Calc-U-59 Card 2…": refuses anything incomplete rather than blanking a side.
std::optional<CardDocument> parseCardTextV2(const std::vector<std::string_view>& lines) {
    enum class V2 { None, CueCard, Side, Header, Data };
    V2 section = V2::None;
    CardDocument doc;
    doc.version = 2;
    CueCardContent cue;
    bool hasCue = false, ended = false;
    std::optional<SideBuilder> side;
    int sideIndex = -1;
    auto finishSide = [&] {
        if (!side) return true;
        if (!side->complete()) return false;
        doc.sides[static_cast<size_t>(sideIndex)] = side->data;
        side.reset();
        return true;
    };
    for (size_t li = 1; li < lines.size() && !ended; ++li) {
        std::string_view line = stripInlineComment(lines[li]);
        if (line.empty()) continue;
        std::string upper = toUpper(line);
        if (upper == kEndCard) {
            if (!finishSide()) return std::nullopt;
            ended = true;
        } else if (upper == "CUECARD:") {
            if (side || hasCue) return std::nullopt;
            section = V2::CueCard;
            hasCue = true;
        } else if (startsWith(upper, "SIDE:")) {
            if (!finishSide()) return std::nullopt;
            auto n = parseDec(trim(line.substr(5)));
            if (!n || *n < 1 || *n > 2 || doc.sides[static_cast<size_t>(*n - 1)]) return std::nullopt;
            sideIndex = static_cast<int>(*n - 1);
            side.emplace();
            section = V2::Side;
        } else if (upper == "HEADER:") {
            if (section != V2::Side) return std::nullopt;
            section = V2::Header;
        } else if (upper == "DATA:") {
            if (section != V2::Header) return std::nullopt;
            section = V2::Data;
        } else {
            switch (section) {
            case V2::CueCard: cue.parseLine(line); break;
            case V2::Header: if (!side->headerLine(line)) return std::nullopt; break;
            case V2::Data: if (!side->dataLine(line)) return std::nullopt; break;
            case V2::None:
            case V2::Side: return std::nullopt;
            }
        }
    }
    if (!ended) return std::nullopt;
    if (hasCue) {
        cue.template_ = CueCardTemplate::MagnetCard;
        doc.cueCard = cue;
    }
    return doc;
}

} // namespace

std::optional<CardFileResult> parseCardText(std::string_view text) {
    auto lines = splitLines(text);
    if (lines.empty() || !startsWith(lines[0], kTextMagicV1)) return std::nullopt;

    Section section = Section::None;
    CueCardContent cue;
    bool hasCue = false, hasHeader = false, hasData = false;
    uint8_t partition = 0, dataType = 0x11, pageByte = 0x10, protection = 0x00, checksum = 0x00;
    std::array<uint8_t, 240> dataBytes{};  // bank bytes 4–243 (30 × 8)
    size_t row = 0;

    for (size_t li = 1; li < lines.size(); ++li) {
        std::string_view line = stripInlineComment(lines[li]);
        if (line.empty()) continue;
        std::string upper = toUpper(line);
        if (upper == "CUECARD:") { section = Section::CueCard; hasCue = true; continue; }
        if (upper == "HEADER:")  { section = Section::Header; continue; }
        if (upper == "DATA:")    { section = Section::Data; hasData = true; row = 0; continue; }

        switch (section) {
        case Section::None:
            break;
        case Section::CueCard:
            cue.parseLine(line);
            break;
        case Section::Header: {
            size_t colon = line.find(':');
            if (colon == std::string_view::npos) break;
            std::string key = toLower(trim(line.substr(0, colon)));
            std::string val = toLower(trim(line.substr(colon + 1)));
            if (key == "partition") {
                auto v = parseHex(val);
                if (!v || *v > 0xFF) return std::nullopt;
                partition = static_cast<uint8_t>(*v);
                hasHeader = true;
            } else if (key == "datatype") {
                dataType = val == "program" ? 0x11 : 0x10;
            } else if (key == "bank") {
                auto n = parseDec(val);
                if (!n || *n < 1 || *n > 4) return std::nullopt;
                pageByte = pageByteOfBank(static_cast<int>(*n));
            } else if (key == "protection") {
                protection = val == "yes" ? 0x10 : 0x00;
            } else if (key == "checksum") {
                auto v = parseHex(val);
                if (!v || *v > 0xFF) return std::nullopt;
                checksum = static_cast<uint8_t>(*v);
            }
            break;
        }
        case Section::Data: {
            // R### rows, 30 per bank; rows past those are ignored here.
            auto bytes = decodeCardRow(line);
            if (!bytes) return std::nullopt;
            if (row < 30) std::copy(bytes->begin(), bytes->end(), dataBytes.begin() + static_cast<long>(row * 8));
            ++row;
            break;
        }
        }
    }
    if (!hasHeader || !hasData) return std::nullopt;

    CardFileResult r;
    r.data.assign(kCardBankBytes, 0);
    r.data[0] = partition;
    r.data[1] = dataType;
    r.data[2] = pageByte;
    r.data[3] = protection;
    std::copy(dataBytes.begin(), dataBytes.end(), r.data.begin() + 4);
    r.data[244] = checksum;
    r.data[245] = checksum;
    if (hasCue) {
        cue.template_ = CueCardTemplate::MagnetCard;
        r.cueCard = cue;
    }
    return r;
}

std::string encodeCardText(const std::vector<uint8_t>& data, const CueCardContent* cueCard) {
    std::vector<std::string> lines{"Calc-U-59 Card 1.0"};
    if (cueCard) appendCueLines(lines, *cueCard);
    lines.emplace_back();
    appendSideLines(lines, data);
    return joinLines(lines);
}

std::string encodeCardDocument(const CardDocument& doc) {
    if (doc.version == 1) return encodeCardText(doc.singleSide, doc.cueCard ? &*doc.cueCard : nullptr);
    std::vector<std::string> lines{"Calc-U-59 Card 2.0"};
    if (doc.cueCard) {
        CueCardContent cue = *doc.cueCard;
        cue.bankLeft.reset();
        cue.bankRight.reset();
        appendCueLines(lines, cue);
    }
    for (size_t i = 0; i < doc.sides.size(); ++i) {
        if (!doc.sides[i]) continue;
        lines.emplace_back();
        lines.push_back("SIDE: " + std::to_string(i + 1));
        appendSideLines(lines, *doc.sides[i]);
    }
    lines.emplace_back();
    lines.emplace_back(kEndCard);
    return joinLines(lines);
}

std::optional<int> CardDocument::sideBank(int side) const {
    const auto& d = sides[static_cast<size_t>(side)];
    if (!d || d->size() < 3) return std::nullopt;
    return bankOfPageByte((*d)[2]);
}

std::vector<uint8_t> CardDocument::bank(int side) const {
    if (version == 1) return singleSide;
    const auto& d = sides[static_cast<size_t>(side)];
    return d ? *d : std::vector<uint8_t>{};
}

void CardDocument::setBank(int side, std::vector<uint8_t> bytes) {
    if (version == 1) singleSide = std::move(bytes);
    else sides[static_cast<size_t>(side)] = std::move(bytes);
}

CueCardContent freshCardCue(const std::string& fileName) {
    CueCardContent cue;
    cue.template_ = CueCardTemplate::MagnetCard;
    size_t dot = fileName.rfind('.');
    cue.title = dot == std::string::npos || dot == 0 ? fileName : fileName.substr(0, dot);
    std::replace(cue.title.begin(), cue.title.end(), '#', ' ');  // '#' would start a comment on reload
    return cue;
}

std::vector<uint8_t> buildCardBank(const CardDefinition& card, int programRegs) {
    if (card.partitionMaxStep) programRegs = (*card.partitionMaxStep + 1) / 8;
    const int bank = card.bank;
    const int firstReg = 30 * (bank - 1);
    // The bank's 30 raw RAM registers. A step is two nibbles of register
    // step / 8, units first (TI59Machine::writeProgram); data register n is
    // raw register 119 − n.
    std::vector<Nibbles16> regs(30, Nibbles16{});
    for (const auto& s : card.programSteps) {
        int reg = s.stepAddr / 8 - firstReg;
        if (reg < 0 || reg >= 30) continue;
        regs[reg][(s.stepAddr & 7) * 2] = s.keycode % 10;
        regs[reg][(s.stepAddr & 7) * 2 + 1] = s.keycode / 10;
    }
    for (const auto& g : card.registers) {
        int reg = 119 - g.regNum - firstReg;
        if (!g.isHidden && reg >= 0 && reg < 30) regs[reg] = g.nibbles;
    }

    const int partition = programRegs / 10;
    std::vector<uint8_t> d(kCardBankBytes, 0);
    d[0] = static_cast<uint8_t>(0x10 | partition);
    d[1] = static_cast<uint8_t>(0x10 | (partition >= 3 * bank ? 1 : 0));  // bank entirely in program memory
    d[2] = pageByteOfBank(bank);
    d[3] = card.protect ? 0x10 : 0x00;
    unsigned sum = (d[0] & 0xF) + (d[1] & 0xF) + (d[2] & 0xF);
    for (int r = 0; r < 30; ++r) {
        auto bytes = encodeRegisterLine(regs[r]);
        std::copy(bytes.begin(), bytes.end(), d.begin() + 4 + 8 * r);
        for (int nibble : regs[r]) sum += nibble;
    }
    d[244] = d[245] = static_cast<uint8_t>(sum & 0xF);
    return d;
}

CardDecodeResult decodeCardFile(const std::vector<uint8_t>& raw, const std::string& fileName) {
    CardDecodeResult r;
    auto singleSide = [](std::vector<uint8_t> data, std::optional<CueCardContent> cue) {
        CardDocument doc;
        doc.version = 1;
        doc.singleSide = std::move(data);
        doc.cueCard = std::move(cue);
        return doc;
    };
    std::string_view asText(reinterpret_cast<const char*>(raw.data()), raw.size());
    if (startsWith(asText, kTextMagic) && isValidUtf8(asText)) {
        if (startsWith(asText, kTextMagicV2)) {
            r.card = parseCardTextV2(splitLines(asText));
        } else if (auto v1 = parseCardText(asText)) {
            r.card = singleSide(std::move(v1->data), std::move(v1->cueCard));
        }
        if (!r.card) r.error = "Card file \"" + fileName + "\" could not be parsed.";
        return r;
    }
    if (startsWith(asText, kBinaryHeader)) {
        size_t payload = raw.size() - kBinaryHeader.size();
        if (payload != kCardBankBytes) {
            r.error = "Card file \"" + fileName + "\" has wrong size (" + std::to_string(payload) +
                      " bytes after header; expected 246).";
            return r;
        }
        r.card = singleSide(std::vector<uint8_t>(raw.begin() + static_cast<long>(kBinaryHeader.size()), raw.end()), std::nullopt);
        return r;
    }
    if (raw.size() != 246 && raw.size() != 984) {
        r.error = "Card file \"" + fileName + "\" has unrecognised size (" + std::to_string(raw.size()) + " bytes).";
        return r;
    }
    r.card = singleSide(raw, std::nullopt);
    return r;
}

bool isCardFileName(std::string_view name) {
    const std::string ext = lowerExtension(name);
    return ext == "u59" || ext == "bin";
}

std::string withDefaultCardExtension(std::string name) {
    if (name.find('.') == std::string::npos) name += ".U59";
    return name;
}

} // namespace cu59
