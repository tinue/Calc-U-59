#include "StateFile.hpp"
#include "TextUtil.hpp"
#include <algorithm>
#include <cctype>
#include <map>

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
void parseRegLine(std::string_view line, bool allowHidden, std::vector<RegisterValue>& out,
                  std::vector<std::string>& errors) {
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
            errors.push_back("Extra register " + std::string(nn) + " is only valid for TI-58C files.");
            return;
        }
        regNum = static_cast<int>(*parseDec(nn.substr(1)));
        isHidden = true;
    } else {
        return;
    }
    if (!parseDouble(val)) {
        errors.push_back("Cannot parse register " + std::string(nn) + " value: \"" + std::string(val) + "\"");
        return;
    }
    out.push_back({regNum, encodeBcd(val), isHidden});
}

/// Matrix codes 11–95 → Key; everything else ignored. 99, once the virtual
/// TRACE key, is an error.
void parseKeystrokeLine(std::string_view line, LoadStateResult& r) {
    for (auto t : splitWhitespace(line)) {
        if (charCount(t) > 2) continue;
        auto n = parseDec(t);
        if (!n) continue;
        if (*n == 99) {
            r.errors.push_back("Key 99 no longer toggles the printer's TRACE: use PrinterTrace: on / PrinterTrace: off.");
            continue;
        }
        if (*n < 11 || *n > 95) continue;
        KeystrokeEvent e;
        e.kind = KeystrokeEvent::Kind::Key;
        e.code = static_cast<uint8_t>(*n);
        r.keystrokes.push_back(e);
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

/// A PARTITION value's last step, rounded up to a multiple of 80 steps (10
/// program registers), 80 to 960. The ".xx" register count is documentation only.
std::optional<int> parsePartition(std::string_view rest) {
    auto n = parseDec(trim(rest.substr(0, rest.find('.'))));
    if (!n) return std::nullopt;
    long steps = *n + 1;
    long rounded = 960;
    for (long b = 80; b <= 960; b += 80)
        if (b >= steps) { rounded = b; break; }
    return static_cast<int>(rounded - 1);
}

/// "ArmCard: <name>" / "InsertCard: <name>": a memory card or a card file name.
void parseCardDirective(std::string_view line, size_t prefixLength, KeystrokeEvent::Kind kind, LoadStateResult& r) {
    std::string_view name = trim(line.substr(prefixLength));
    std::string_view word = line.substr(0, prefixLength);
    if (name.empty() || (isMemoryCardName(name) && memoryCardKey(name).empty())) {
        r.errors.push_back(std::string(word) + " needs a card name: a file in the card folder, or mem:<name>.");
        return;
    }
    if (!isMemoryCardName(name) && (name.find('/') != std::string_view::npos || name.find('\\') != std::string_view::npos)) {
        r.errors.push_back(std::string(word) + " card \"" + std::string(name) + "\" must not contain a path separator.");
        return;
    }
    KeystrokeEvent e = simple(kind);
    e.cardName = std::string(name);
    r.keystrokes.push_back(e);
    r.usesCardReader = true;
}

/// A card bank holds raw RAM registers 30·(bank−1)…+29: program steps
/// 240·(bank−1)…+239 and, counted from the top of the TI-59's 120 registers,
/// data registers 120 − 30·bank … 149 − 30·bank.
bool stepInBank(int step, int bank) { return step >= 240 * (bank - 1) && step < 240 * bank; }
bool registerInBank(int reg, int bank) { return reg >= 120 - 30 * bank && reg <= 149 - 30 * bank; }

/// Check a finished CARD: block; nullptr if it can't be used.
std::shared_ptr<CardDefinition> finishCard(std::shared_ptr<CardDefinition> card, std::vector<std::string>& errors) {
    const std::string what = "CARD: " + card->name;
    if (!isMemoryCardName(card->name) || memoryCardKey(card->name).empty()) {
        errors.push_back(what + ": only an in-memory card (mem:<name>) can be defined; a card file is used by its name.");
        return nullptr;
    }
    if (card->bank == 0) {
        errors.push_back(what + " needs Bank: 1–4.");
        return nullptr;
    }
    auto& steps = card->programSteps;
    for (const auto& s : steps)
        if (!stepInBank(s.stepAddr, card->bank))
            errors.push_back(what + ": step " + std::to_string(s.stepAddr) + " is not in bank " +
                             std::to_string(card->bank) + " (steps " + std::to_string(240 * (card->bank - 1)) + "–" +
                             std::to_string(240 * card->bank - 1) + ").");
    steps.erase(std::remove_if(steps.begin(), steps.end(), [&](const ProgramStep& s) { return !stepInBank(s.stepAddr, card->bank); }),
                steps.end());
    auto& regs = card->registers;
    for (const auto& g : regs)
        if (!registerInBank(g.regNum, card->bank))
            errors.push_back(what + ": register " + std::to_string(g.regNum) + " is not in bank " +
                             std::to_string(card->bank) + " (registers " + std::to_string(std::max(0, 120 - 30 * card->bank)) +
                             "–" + std::to_string(std::min(99, 149 - 30 * card->bank)) + ").");
    regs.erase(std::remove_if(regs.begin(), regs.end(), [&](const RegisterValue& g) { return !registerInBank(g.regNum, card->bank); }),
               regs.end());
    return card;
}

/// The GUI-control directives (PrinterTrace:, CutPaper:, DebugPanel:, Freeze:,
/// FreezeOnStart:, Step:, Resume:): appended to the keystrokes, or its error
/// recorded. False: not one of them.
bool parseControl(std::string_view line, std::string_view upper, LoadStateResult& r) {
    using K = KeystrokeEvent::Kind;
    static const std::pair<const char*, K> kWords[] = {
        {"PRINTERTRACE:", K::PrinterTrace}, {"CUTPAPER:", K::CutPaper}, {"DEBUGPANEL:", K::ShowPanel},
        {"FREEZEONSTART:", K::FreezeOnStart}, {"FREEZE:", K::Freeze}, {"STEP:", K::Step}, {"RESUME:", K::Resume},
    };
    const char* word = nullptr;
    K kind = K::Key;
    for (const auto& [w, k] : kWords)
        if (startsWith(upper, w)) { word = w; kind = k; break; }
    if (!word) return false;
    KeystrokeEvent e = simple(kind);
    const std::string name(line.substr(0, std::string_view(word).size()));
    auto args = splitWhitespace(line.substr(std::string_view(word).size()));
    auto fail = [&](const std::string& what) {
        r.errors.push_back("\"" + std::string(line) + "\": " + name + " " + what);
        return true;
    };
    // A panel name: Calculator, CPU or (DebugPanel: only) Log.
    auto panel = [&](std::string_view arg, bool allowLog) -> std::optional<DebugPanel> {
        std::string v = toLower(arg);
        if (v == "calculator") return DebugPanel::Calculator;
        if (v == "cpu") return DebugPanel::Cpu;
        if (allowLog && v == "log") return DebugPanel::Log;
        return std::nullopt;
    };
    switch (kind) {
    case K::PrinterTrace: {
        std::string v = args.size() == 1 ? toLower(args[0]) : "";
        if (v != "on" && v != "off") return fail("needs on or off.");
        e.on = v == "on";
        break;
    }
    case K::CutPaper:
    case K::Resume:
        if (!args.empty()) return fail("takes no value.");
        break;
    case K::ShowPanel: {
        auto p = args.size() == 1 ? panel(args[0], true) : std::nullopt;
        if (!p) return fail("needs Calculator, CPU or Log.");
        e.panel = *p;
        break;
    }
    case K::Freeze: {
        auto p = args.size() == 1 ? panel(args[0], false) : std::nullopt;
        if (!p) return fail("needs Calculator or CPU.");
        e.panel = *p;
        break;
    }
    case K::FreezeOnStart: {
        if (args.size() == 1 && toLower(args[0]) == "off") {
            e.on = false;
            break;
        }
        auto p = args.size() == 1 ? panel(args[0], false) : std::nullopt;
        if (!p) return fail("needs Calculator, CPU or Off.");
        e.panel = *p;
        break;
    }
    case K::Step: {
        auto p = !args.empty() && args.size() <= 2 ? panel(args[0], false) : std::nullopt;
        if (!p) return fail("needs Calculator or CPU, and optionally a count.");
        e.panel = *p;
        if (args.size() == 2) {
            auto n = parseDec(args[1]);
            if (!n || *n < 1 || *n > 100000) return fail("count must be 1–100000.");
            e.count = static_cast<int>(*n);
        }
        break;
    }
    default:
        break;
    }
    r.keystrokes.push_back(e);
    return true;
}

} // namespace

bool isMemoryCardName(std::string_view name) { return name.size() >= 4 && toLower(name.substr(0, 4)) == "mem:"; }

std::string_view memoryCardKey(std::string_view name) { return name.substr(4); }

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

    // Where PROGRAM / REGISTERS / CUECARD lines go: the initial load until the
    // first KEYSTROKES section, then a reload stage (a new one after each
    // KEYSTROKES section), or the open CARD: block.
    bool afterKeystrokes = false;
    std::shared_ptr<ReloadStage> reload;
    std::shared_ptr<CardDefinition> card;
    std::map<std::string, std::shared_ptr<CardDefinition>> cards;  // by memoryCardKey
    auto closeCard = [&] {
        if (auto c = finishCard(std::move(card), r.errors)) {
            std::string key(memoryCardKey(c->name));
            if (cards.count(key)) r.errors.push_back("CARD: " + c->name + " is defined twice; the last one counts.");
            cards[key] = std::move(c);
        }
        card = nullptr;
        section = Section::None;
    };
    // A reload section after KEYSTROKES: the first one opens the stage, played in turn.
    auto reloadStage = [&]() -> ReloadStage* {
        if (!afterKeystrokes) return nullptr;
        if (!reload) {
            reload = std::make_shared<ReloadStage>();
            KeystrokeEvent e = simple(KeystrokeEvent::Kind::Reload);
            e.reload = reload;
            r.keystrokes.push_back(e);
            currentStep = 0;
        }
        return reload.get();
    };

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
        if (startsWith(upper, "SKIP-RESET:")) {
            r.errors.push_back("SKIP-RESET: no longer exists: put the second file's sections after the first file's "
                               "KEYSTROKES: (a reload), in one file. This file loads with a reset.");
            continue;
        }
        if (startsWith(upper, "MODEL:")) {
            std::string val = toUpper(trim(line.substr(6)));
            if (auto m = modelFromName(val)) {
                r.model = m;
            } else {
                r.errors.push_back("Unknown MODEL: '" + val + "' — expected TI-59, TI-58, TI-58C");
            }
            continue;
        }

        if (startsWith(upper, "END-CARD")) {
            if (card) closeCard();
            else r.errors.push_back("END-CARD without CARD:");
            continue;
        }
        if (startsWith(upper, "CARD:")) {
            if (card) {
                r.errors.push_back("CARD: " + card->name + " has no END-CARD.");
                closeCard();
            }
            card = std::make_shared<CardDefinition>();
            card->name = std::string(trim(line.substr(5)));
            r.usesCardReader = true;
            continue;
        }
        if (card) {
            // Inside CARD: … END-CARD: the bank's header and contents.
            if (startsWith(upper, "BANK:")) {
                auto n = parseDec(trim(line.substr(5)));
                if (n && *n >= 1 && *n <= 4) card->bank = static_cast<int>(*n);
                else r.errors.push_back("CARD: " + card->name + ": Bank: must be 1–4.");
                continue;
            }
            if (startsWith(upper, "PROTECTED:")) {
                // yes / no as in card files, or on / true / 1 as elsewhere in presets
                card->protect = isOn(line.substr(10)) || toLower(trim(line.substr(10))) == "yes";
                continue;
            }
            if (startsWith(upper, "PARTITION:")) {
                card->partitionMaxStep = parsePartition(trim(line.substr(10)));
                if (!card->partitionMaxStep) r.errors.push_back("CARD: " + card->name + ": cannot read \"" + std::string(line) + "\".");
                continue;
            }
            if (startsWith(upper, "PROGRAM:")) {
                section = Section::Program;
                currentStep = card->bank ? 240 * (card->bank - 1) : 0;  // bare keycodes start at the bank's first step
                continue;
            }
            if (startsWith(upper, "REGISTERS:")) { section = Section::Registers; continue; }
            if (startsWith(upper, "CUECARD:"))   { section = Section::CueCard; card->cueCard = CueCardContent(); continue; }
            if (startsWith(upper, "KEYSTROKES:")) {
                r.errors.push_back("CARD: " + card->name + " has no END-CARD.");
                closeCard();
                // and on: KEYSTROKES: below
            } else if (section != Section::Program && section != Section::Registers && section != Section::CueCard) {
                r.errors.push_back("CARD: " + card->name + ": unexpected line \"" + std::string(line) + "\".");
                continue;
            }
        }

        if (startsWith(upper, "PARTITION:")) {
            section = Section::Partition;
            auto maxStep = parsePartition(trim(line.substr(10)));
            if (ReloadStage* stage = reloadStage()) {
                if (maxStep) stage->partitionMaxStep = maxStep;
            } else {
                if (maxStep) r.partitionMaxStep = *maxStep;
                r.partitionWasExplicit = true;
            }
            continue;
        }
        if (startsWith(upper, "PROGRAM:"))    { reloadStage(); section = Section::Program; continue; }
        if (startsWith(upper, "REGISTERS:"))  { reloadStage(); section = Section::Registers; continue; }
        if (startsWith(upper, "CUECARD:")) {
            if (ReloadStage* stage = reloadStage()) stage->cueCard = CueCardContent();
            else r.cueCard = CueCardContent();
            section = Section::CueCard;
            continue;
        }
        if (startsWith(upper, "KEYSTROKES:")) {
            afterKeystrokes = true;
            reload = nullptr;
            section = Section::Keystrokes;
            continue;
        }

        auto& steps = card ? card->programSteps : reload ? reload->programSteps : r.programSteps;
        auto& registers = card ? card->registers : reload ? reload->registers : r.registers;
        auto& cueCard = card ? card->cueCard : reload ? reload->cueCard : r.cueCard;
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
            for (uint8_t c : codes) steps.push_back({currentStep++, c});
            break;
        }
        case Section::Registers:
            parseRegLine(line, allowHiddenRegisters && !card, registers, r.errors);
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
            } else if (startsWith(upper, "ARMCARD:")) {
                parseCardDirective(line, 8, KeystrokeEvent::Kind::ArmCard, r);
            } else if (startsWith(upper, "INSERTCARD:")) {
                parseCardDirective(line, 11, KeystrokeEvent::Kind::InsertCard, r);
            } else if (parseControl(line, upper, r)) {
                // appended, or its error recorded
            } else if (startsWith(upper, "WAITFULLSPEED:")) {
                r.errors.push_back("WaitFullSpeed: no longer exists: put FullSpeed: before the key that starts the "
                                   "program; playback waits until it stops, and the script ends at regular speed.");
            } else if (isDirectiveLine(line)) {
                r.errors.push_back("Unknown KEYSTROKES directive: \"" + std::string(line) + "\"");
            } else {
                parseKeystrokeLine(line, r);
            }
            break;
        case Section::CueCard:
            cueCard->parseLine(line);
            break;
        }
    }
    if (card) {
        r.errors.push_back("CARD: " + card->name + " has no END-CARD.");
        closeCard();
    }
    // CARD: blocks may stand anywhere: attach each to the directives naming it.
    for (auto& e : r.keystrokes) {
        if (!isMemoryCardName(e.cardName)) continue;
        auto it = cards.find(std::string(memoryCardKey(e.cardName)));
        if (it != cards.end()) e.card = it->second;
    }
    return r;
}

Model stateFileModel(std::string_view text, Model current) {
    Model model = current;
    for (std::string_view raw : splitLines(text)) {
        std::string_view line = stripInlineComment(raw);
        if (startsWith(toUpper(line), "MODEL:")) model = modelFromName(line.substr(6)).value_or(current);
    }
    return model;
}

} // namespace cu59
