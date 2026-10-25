#include "StateFile.hpp"
#include "TextUtil.hpp"
#include <cctype>

namespace cu59 {

namespace {

enum class Section { None, Partition, Program, Registers, Keystrokes, CueCard };

bool isOn(std::string_view value) {
    std::string v = toLower(trim(value));
    return v == "on" || v == "true" || v == "1";
}

/// Count of Unicode characters (Swift's String.count for these tokens).
size_t charCount(std::string_view s) {
    size_t n = 0;
    for (unsigned char c : s)
        if ((c & 0xC0) != 0x80) ++n;
    return n;
}

/// One program line → (step address set by a prefix, keycodes). A token of 3+
/// characters at the start that is a valid step address is a position prefix.
/// The notation is per line: a prefixed line (format 2) carries exactly one
/// keycode — the token after the prefix — and anything after it is a label,
/// even a numeric one (digit keys are their own mnemonic: "473 00 0"). An
/// un-prefixed line (format 1) treats every 1–2 digit token 0–99 as a keycode.
void parseProgLine(std::string_view line, int maxStepAddr, std::optional<int>& start, std::vector<uint8_t>& codes) {
    auto tokens = splitWhitespace(line);
    if (tokens.empty()) return;
    if (charCount(tokens[0]) >= 3) {
        auto n = parseDec(tokens[0]);
        if (n && *n >= 0 && *n <= maxStepAddr) {
            start = static_cast<int>(*n);
            if (tokens.size() > 1 && charCount(tokens[1]) <= 2) {
                auto k = parseDec(tokens[1]);
                if (k && *k >= 0 && *k <= 99) codes.push_back(static_cast<uint8_t>(*k));
            }
            return;
        }
    }
    for (auto t : tokens) {
        if (charCount(t) > 2) continue;
        auto n = parseDec(t);
        if (n && *n >= 0 && *n <= 99) codes.push_back(static_cast<uint8_t>(*n));
    }
}

/// "NN = value" (normal register 00–99) or "HNN = value" (TI-58C extra 00–03).
void parseRegLine(std::string_view line, bool allowHidden, LoadStateResult& r) {
    size_t eq = line.find('=');
    if (eq == std::string_view::npos) return;
    std::string_view nn = trim(line.substr(0, eq));
    std::string_view val = trim(line.substr(eq + 1));

    int regNum;
    bool isHidden = false;
    auto n = parseDec(nn);
    if (n && *n >= 0 && *n <= 99) {
        regNum = static_cast<int>(*n);
    } else if (!nn.empty() && (nn[0] == 'H' || nn[0] == 'h') && parseDec(nn.substr(1)) &&
               *parseDec(nn.substr(1)) >= 0 && *parseDec(nn.substr(1)) <= 3) {
        if (!allowHidden) {
            r.errors.push_back("Extra register " + std::string(nn) + " is only valid for TI-58C files.");
            return;
        }
        regNum = static_cast<int>(*parseDec(nn.substr(1)));
        isHidden = true;
    } else {
        return;
    }
    if (!parseDouble(val)) {
        r.errors.push_back("Cannot parse register " + std::string(nn) + " value: \"" + std::string(val) + "\"");
        return;
    }
    r.registers.push_back({regNum, encodeBcd(val), isHidden});
}

/// Matrix codes 11–95 → Key, 99 → ToggleTrace; everything else ignored.
void parseKeystrokeLine(std::string_view line, std::vector<KeystrokeEvent>& out) {
    for (auto t : splitWhitespace(line)) {
        if (charCount(t) > 2) continue;
        auto n = parseDec(t);
        if (!n) continue;
        KeystrokeEvent e;
        if (*n == 99) {
            e.kind = KeystrokeEvent::Kind::ToggleTrace;
        } else if (*n >= 11 && *n <= 95) {
            e.kind = KeystrokeEvent::Kind::Key;
            e.code = static_cast<uint8_t>(*n);
        } else {
            continue;
        }
        out.push_back(e);
    }
}

/// "Word:" at the start of a KEYSTROKES line: a directive, never key codes —
/// an unknown one is an error rather than read as keys ("Wait: 15" is not E).
bool isDirectiveLine(std::string_view line) {
    size_t colon = line.find(':');
    if (colon == std::string_view::npos || colon == 0) return false;
    for (char c : line.substr(0, colon))
        if (!std::isalpha(static_cast<unsigned char>(c)) && c != '-') return false;
    return true;
}

/// "<prefix> <value>s" or "<prefix> <value>ms" (case-insensitive) → seconds.
std::optional<double> parseWaitInterval(std::string_view line, std::string_view upper, std::string_view prefix) {
    if (!startsWith(upper, prefix)) return std::nullopt;
    std::string_view rest = trim(line.substr(prefix.size()));
    std::string restUpper = toUpper(rest);
    if (restUpper.size() >= 2 && restUpper.compare(restUpper.size() - 2, 2, "MS") == 0) {
        if (auto v = parseDouble(trim(rest.substr(0, rest.size() - 2)))) return *v / 1000.0;
    }
    if (!restUpper.empty() && restUpper.back() == 'S') {
        if (auto v = parseDouble(trim(rest.substr(0, rest.size() - 1)))) return *v;
    }
    return std::nullopt;
}

/// "Trace: <filename>" / "Trace: Off". The whole remainder is the filename.
void parseTraceLine(std::string_view line, LoadStateResult& r) {
    std::string_view rest = trim(line.substr(6));
    KeystrokeEvent e;
    e.kind = KeystrokeEvent::Kind::Trace;
    if (toUpper(rest) == "OFF") {
        r.keystrokes.push_back(e);
        return;
    }
    if (rest.empty()) {
        r.errors.push_back("Trace: requires a filename or \"Off\".");
        return;
    }
    if (rest.find('/') != std::string_view::npos || rest.find('\\') != std::string_view::npos) {
        r.errors.push_back("Trace: filename \"" + std::string(rest) + "\" must not contain a path separator.");
        return;
    }
    e.traceName = std::string(rest);
    r.keystrokes.push_back(e);
}

KeystrokeEvent simple(KeystrokeEvent::Kind k) {
    KeystrokeEvent e;
    e.kind = k;
    return e;
}

} // namespace

std::optional<Model> modelFromName(std::string_view name) {
    std::string v = toUpper(trim(name));
    for (Model m : {Model::TI59, Model::TI58, Model::TI58C})
        if (v == info(m).displayName) return m;
    return std::nullopt;
}

LoadStateResult parseStateFile(std::string_view text, int maxStepAddr, bool allowHiddenRegisters) {
    LoadStateResult r;
    Section section = Section::None;
    int currentStep = 0;

    for (std::string_view raw : splitLines(text)) {
        std::string_view line = stripInlineComment(raw);
        if (line.empty()) continue;
        std::string upper = toUpper(line);

        // Inline-value directives: not section headers, may appear anywhere.
        if (startsWith(upper, "SOLID-STATE-MODULE:")) {
            std::string_view id = trim(line.substr(19));
            if (!id.empty()) r.solidStateModuleID = std::string(id);
            continue;
        }
        if (startsWith(upper, "PRINTER:")) { r.printerConnected = isOn(line.substr(8)); continue; }
        if (startsWith(upper, "SKIP-RESET:")) { r.skipReset = isOn(line.substr(11)); continue; }
        if (startsWith(upper, "MODEL:")) {
            std::string val = toUpper(trim(line.substr(6)));
            if (auto m = modelFromName(val)) {
                r.model = m;
            } else {
                r.errors.push_back("Unknown MODEL: '" + val + "' — expected TI-59, TI-58, TI-58C");
            }
            continue;
        }

        if (startsWith(upper, "PARTITION:")) {
            section = Section::Partition;
            std::string_view rest = trim(line.substr(10));
            // The part before the dot; the ".xx" register count is documentation only.
            if (auto n = parseDec(trim(rest.substr(0, rest.find('.'))))) {
                // Round up to a valid boundary: multiples of 80 steps from 80 to 960
                // (10 program-RAM registers = 80 steps; max 120 registers).
                long steps = *n + 1;
                long rounded = 960;
                for (long b = 80; b <= 960; b += 80)
                    if (b >= steps) { rounded = b; break; }
                r.partitionMaxStep = static_cast<int>(rounded - 1);
            }
            r.partitionWasExplicit = true;
            continue;
        }
        if (startsWith(upper, "PROGRAM:"))    { section = Section::Program; continue; }
        if (startsWith(upper, "REGISTERS:"))  { section = Section::Registers; continue; }
        if (startsWith(upper, "KEYSTROKES:")) { section = Section::Keystrokes; continue; }
        if (startsWith(upper, "CUECARD:"))    { section = Section::CueCard; r.cueCard = CueCardContent(); continue; }

        switch (section) {
        case Section::None:
        case Section::Partition:
            break;
        case Section::Program: {
            if (line == "...") break;  // gap marker: steps in between stay 00
            std::optional<int> start;
            std::vector<uint8_t> codes;
            parseProgLine(line, maxStepAddr, start, codes);
            if (start) currentStep = *start;
            for (uint8_t c : codes) r.programSteps.push_back({currentStep++, c});
            break;
        }
        case Section::Registers:
            parseRegLine(line, allowHiddenRegisters, r);
            break;
        case Section::Keystrokes:
            if (auto w = parseWaitInterval(line, upper, "WAIT:")) {
                KeystrokeEvent e = simple(KeystrokeEvent::Kind::Wait);
                e.seconds = *w;
                r.keystrokes.push_back(e);
            } else if (startsWith(upper, "WAIT:")) {
                r.errors.push_back("\"" + std::string(line) + "\": Wait: needs a time with its unit, e.g. 2s or 500ms.");
            } else if (startsWith(upper, "TRACE:")) {
                parseTraceLine(line, r);
            } else if (startsWith(upper, "FULLSPEED:")) {
                r.keystrokes.push_back(simple(KeystrokeEvent::Kind::FullSpeed));
            } else if (startsWith(upper, "REGULARSPEED:")) {
                r.keystrokes.push_back(simple(KeystrokeEvent::Kind::RegularSpeed));
            } else if (startsWith(upper, "ZEROELAPSETIME:")) {
                r.keystrokes.push_back(simple(KeystrokeEvent::Kind::ZeroElapseTime));
            } else if (startsWith(upper, "REPORTELAPSETIME:")) {
                r.keystrokes.push_back(simple(KeystrokeEvent::Kind::ReportElapseTime));
            } else if (startsWith(upper, "WAITFULLSPEED:")) {
                r.errors.push_back("WaitFullSpeed: no longer exists: put FullSpeed: before the key that starts the "
                                   "program; playback waits until it stops, and the script ends at regular speed.");
            } else if (isDirectiveLine(line)) {
                r.errors.push_back("Unknown KEYSTROKES directive: \"" + std::string(line) + "\"");
            } else {
                parseKeystrokeLine(line, r.keystrokes);
            }
            break;
        case Section::CueCard:
            r.cueCard->parseLine(line);
            break;
        }
    }
    return r;
}

StateFilePrescan prescanStateFile(std::string_view text, Model current) {
    StateFilePrescan p{false, current};
    for (std::string_view raw : splitLines(text)) {
        std::string_view line = stripInlineComment(raw);
        std::string upper = toUpper(line);
        if (startsWith(upper, "SKIP-RESET:")) {
            p.skipReset = isOn(line.substr(11));
        } else if (!p.skipReset && startsWith(upper, "MODEL:")) {
            p.targetModel = modelFromName(line.substr(6)).value_or(current);
        }
    }
    return p;
}

} // namespace cu59
