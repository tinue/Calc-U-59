// Shared/ file formats against the Swift originals (tests/golden/formats.txt,
// produced by tools/goldens/formats_main.swift): state files, card files,
// cue cards, BCD encoders, register lines and math tokens. Also round trips
// for the card and ti58c.mem encoders.

#include "TestHarness.hpp"
#include "TestRoms.hpp"
#include "../Shared/CardFile.hpp"
#include "../Shared/ConstantMemory.hpp"
#include "../Shared/ModuleCatalog.hpp"
#include "../Shared/SettingsKeys.hpp"
#include "../Shared/StateFile.hpp"
#include "../Shared/TextUtil.hpp"
#include <cstdio>
#include <map>

using namespace cu59;

namespace {

std::string hexNib(const uint8_t* b, size_t n) {
    static const char* d = "0123456789ABCDEF";
    std::string s;
    for (size_t i = 0; i < n; ++i) {
        if (b[i] >= 16) { char buf[4]; std::snprintf(buf, sizeof buf, "%X", b[i]); s += buf; }
        else s += d[b[i]];
    }
    return s;
}

std::string num(double d) {
    char b[64];
    std::snprintf(b, sizeof b, "%.17g", d);
    return b;
}

void dumpCue(const CueCardContent& c, std::string& out) {
    auto opt = [](const std::optional<int>& v) { return v ? std::to_string(*v) : std::string("-"); };
    out += std::string("cue template ") + toString(c.template_) + "\n";
    out += "cue title " + c.title + "\n";
    out += "cue banks " + opt(c.bankLeft) + " " + opt(c.bankRight) + "\n";
    out += "cue id " + c.id + "\n";
    for (size_t i = 0; i < 10; ++i) out += "cue label" + std::to_string(i) + " " + c.labels[i] + "\n";
    out += "cue row1 " + c.row1 + "\ncue row1Align " + toString(c.row1Align) + "\n";
    out += "cue row2 " + c.row2 + "\ncue row2Align " + toString(c.row2Align) + "\n";
    out += "cue row2R " + c.row2R + "\ncue row2RAlign " + toString(c.row2RAlign) + "\n";
    out += std::string("cue style ") + toString(c.style) + "\ncue color " + toString(c.color) + "\n";
    for (auto& l : c.encodeToLines(CueCardTemplate::MagnetCard)) out += "enc " + l + "\n";
    for (auto& l : c.encodeToLines()) out += "enc0 " + l + "\n";
}

std::string dumpState(const LoadStateResult& r) {
    std::string out;
    out += "partition " + std::to_string(r.partitionMaxStep) + " " + (r.partitionWasExplicit ? "1" : "0") + "\n";
    for (auto& s : r.programSteps) out += "step " + std::to_string(s.stepAddr) + " " + std::to_string(s.keycode) + "\n";
    for (auto& g : r.registers)
        out += "reg " + std::to_string(g.regNum) + " " + (g.isHidden ? "1" : "0") + " " + hexNib(g.nibbles.data(), 16) + "\n";
    using K = KeystrokeEvent::Kind;
    for (auto& k : r.keystrokes) {
        switch (k.kind) {
        case K::Key: out += "key " + std::to_string(k.code) + "\n"; break;
        case K::Wait: out += "wait " + num(k.seconds) + "\n"; break;
        case K::Trace: out += "trace " + k.traceName.value_or("-") + "\n"; break;
        case K::FullSpeed: out += "fullSpeed\n"; break;
        case K::RegularSpeed: out += "regularSpeed\n"; break;
        case K::ZeroElapseTime: out += "zeroElapseTime\n"; break;
        case K::ReportElapseTime: out += "reportElapseTime\n"; break;
        case K::Reload: {
            const ReloadStage& st = *k.reload;
            out += "reload partition " + (st.partitionMaxStep ? std::to_string(*st.partitionMaxStep) : "-") + "\n";
            for (auto& s : st.programSteps)
                out += "reload step " + std::to_string(s.stepAddr) + " " + std::to_string(s.keycode) + "\n";
            for (auto& g : st.registers)
                out += "reload reg " + std::to_string(g.regNum) + " " + hexNib(g.nibbles.data(), 16) + "\n";
            if (st.cueCard) out += "reload cue " + st.cueCard->title + "\n";
            break;
        }
        case K::ArmCard: out += "armCard " + k.cardName + (k.card ? " defined" : "") + "\n"; break;
        case K::InsertCard: out += "insertCard " + k.cardName + (k.card ? " defined" : "") + "\n"; break;
        case K::PrinterTrace: out += std::string("printerTrace ") + (k.on ? "on" : "off") + "\n"; break;
        case K::CutPaper: out += "cutPaper\n"; break;
        case K::ShowPanel: out += "debugPanel " + std::to_string(int(k.panel)) + "\n"; break;
        case K::Freeze: out += "freeze " + std::to_string(int(k.panel)) + "\n"; break;
        case K::FreezeOnStart:
            out += "freezeOnStart " + (k.on ? std::to_string(int(k.panel)) : std::string("off")) + "\n";
            break;
        case K::Step: out += "step " + std::to_string(int(k.panel)) + " " + std::to_string(k.count) + "\n"; break;
        case K::Resume: out += "resume\n"; break;
        }
    }
    if (r.cueCard) dumpCue(*r.cueCard, out);
    out += "module " + r.solidStateModuleID.value_or("-") + "\n";
    out += std::string("printer ") + (r.printerConnected ? (*r.printerConnected ? "1" : "0") : "-") + "\n";
    out += std::string("model ") + (r.model ? info(*r.model).displayName : "-") + "\n";
    for (auto& e : r.errors) out += "error " + e + "\n";
    return out;
}

/// Golden records: header line → body (lines up to END).
struct Record { std::string header, body; };

std::vector<Record> records(const std::string& golden, std::vector<std::string>& singles) {
    std::vector<Record> out;
    Record* cur = nullptr;
    for (std::string_view line : splitLines(golden)) {
        if (cur) {
            if (line == "END") { cur = nullptr; continue; }
            cur->body += std::string(line) + "\n";
            continue;
        }
        if (startsWith(line, "STATE ") || startsWith(line, "CARD ")) {
            out.push_back({std::string(line), ""});
            cur = &out.back();
        } else if (!line.empty()) {
            singles.emplace_back(line);
        }
    }
    return out;
}

const std::string& golden() {
    static std::string g = testroms::readFile("tests/golden/formats.txt").value_or("");
    return g;
}

} // namespace

TEST(formats_golden_present) {
    CHECK(!golden().empty());
}

TEST(state_and_card_files_match_swift) {
    std::vector<std::string> singles;
    int states = 0, cards = 0;
    for (auto& rec : records(golden(), singles)) {
        auto w = splitWords(rec.header);
        auto text = testroms::readFile(std::string(w[1]));
        CHECK(text.has_value());
        if (!text) continue;
        std::string got;
        if (w[0] == "STATE") {
            ++states;
            got = dumpState(parseStateFile(*text, static_cast<int>(*parseDec(w[2])), w[3] == "1"));
        } else {
            ++cards;
            auto r = parseCardText(*text);
            if (!r) got = "nil\n";
            else {
                got = "data " + hexNib(r->data.data(), r->data.size()) + "\n";
                if (r->cueCard) dumpCue(*r->cueCard, got);
            }
        }
        if (got != rec.body) {
            std::fprintf(stderr, "MISMATCH %s\n--- swift\n%s--- c++\n%s", rec.header.c_str(), rec.body.c_str(), got.c_str());
        }
        CHECK(got == rec.body);
    }
    CHECK(states >= 140);
    CHECK(cards >= 5);
}

TEST(keystroke_directives_unknown_or_without_unit_are_errors) {
    auto r = parseStateFile("KEYSTROKES:\nWait: 15\nWaitFullSpeed: 2s\nFoo-Bar: 1\nWait: 2s\n11\n");
    CHECK_EQ(r.errors.size(), size_t{3});
    CHECK(r.errors.size() == 3 && r.errors[1].find("FullSpeed:") != std::string::npos);
    CHECK_EQ(r.keystrokes.size(), size_t{2});  // Wait: 2s and key 11; "Wait: 15" is not key 15
    CHECK(r.keystrokes.size() == 2 && r.keystrokes[0].kind == KeystrokeEvent::Kind::Wait);
}

TEST(bcd_regline_math_match_swift) {
    std::vector<std::string> singles;
    records(golden(), singles);
    int n = 0;
    for (auto& line : singles) {
        std::string_view l = line;
        if (startsWith(l, "BCDT [")) {
            size_t close = l.find("] ");
            auto nib = encodeBcd(l.substr(6, close - 6));
            CHECK_EQ(hexNib(nib.data(), 16), std::string(l.substr(close + 2)));
            ++n;
        } else if (startsWith(l, "BCDD ")) {
            auto w = splitWords(l);
            auto nib = encodeBcd(*parseDouble(w[1]));
            CHECK_EQ(hexNib(nib.data(), 16), std::string(w[2]));
            ++n;
        } else if (startsWith(l, "REG ")) {
            auto w = splitWords(l);
            Nibbles16 nib{};
            for (size_t i = 0; i < 16; ++i) nib[i] = static_cast<uint8_t>(hexDigit(w[1][i]));
            auto enc = encodeRegisterLine(nib);
            std::string encHex;
            for (uint8_t b : enc) { char buf[4]; std::snprintf(buf, sizeof buf, "%02X", b); encHex += buf; }
            CHECK_EQ(encHex, std::string(w[2]));
            auto dec = decodeRegisterLine(enc);
            CHECK_EQ(hexNib(dec.data(), 16), std::string(w[3]));
            ++n;
        } else if (startsWith(l, "MATH ")) {
            auto w = splitWords(l);
            CHECK_EQ(expandMathTokens(w[1]), std::string(w.size() > 2 ? w[2] : ""));
            ++n;
        }
    }
    CHECK(n > 400);
}

TEST(card_text_round_trip) {
    std::vector<uint8_t> bank(246);
    for (size_t i = 0; i < bank.size(); ++i) bank[i] = static_cast<uint8_t>((i * 37 + 11) & 0xFF);
    bank[0] = 0x1C; bank[1] = 0x10; bank[2] = 0x16; bank[3] = 0x10; bank[245] = bank[244];
    CueCardContent cue;
    cue.title = "ROUND TRIP";
    cue.labels[5] = kCueCardInvisibleMarker;
    std::string text = encodeCardText(bank, &cue);
    auto back = parseCardText(text);
    CHECK(back.has_value());
    if (!back) return;
    CHECK(back->data == bank);
    CHECK(back->cueCard.has_value());
    if (back->cueCard) {
        CHECK_EQ(back->cueCard->title, std::string("ROUND TRIP"));
        CHECK_EQ(back->cueCard->labels[5], std::string(kCueCardInvisibleMarker));
        CHECK(back->cueCard->bankLeft == 3);
    }
}

TEST(card_decode_layouts) {
    auto bytes = [](const std::string& s) { return std::vector<uint8_t>(s.begin(), s.end()); };
    auto legacy = decodeCardFile(std::vector<uint8_t>(984, 7), "x.bin");
    CHECK(legacy.card && legacy.card->data.size() == 984);
    auto headered = bytes("Calc-U-59-CRD") ;
    headered.resize(13 + 246, 1);
    auto h = decodeCardFile(headered, "h.u59");
    CHECK(h.card && h.card->data.size() == 246 && h.card->data[0] == 1);
    headered.push_back(0);
    CHECK_EQ(decodeCardFile(headered, "h.u59").error,
             std::string("Card file \"h.u59\" has wrong size (247 bytes after header; expected 246)."));
    CHECK_EQ(decodeCardFile(std::vector<uint8_t>(10), "s.u59").error,
             std::string("Card file \"s.u59\" has unrecognised size (10 bytes)."));
    auto badText = decodeCardFile(bytes("Calc-U-59 Card 1.0\nHEADER:\n"), "t.u59");
    CHECK(badText.isText && !badText.card);
    CHECK_EQ(badText.error, std::string("Card file \"t.u59\" could not be parsed."));
}

TEST(constant_memory_round_trip) {
    std::vector<uint8_t> ram(kConstantMemoryBytes, 0);
    for (size_t i = 16 * 5; i < 16 * 6; ++i) ram[i] = static_cast<uint8_t>(i % 10);
    for (size_t i = 16 * 63; i < 16 * 64; ++i) ram[i] = 9;
    CueCardContent cue;
    cue.title = "MEM";
    cue.row1 = "R: line starting with R";
    std::string text = encodeConstantMemory(ram, &cue);
    CHECK(text.find("R005: ") != std::string::npos);
    CHECK(text.find("R000") == std::string::npos);  // zero registers are omitted
    auto back = decodeConstantMemory(text);
    CHECK(back.has_value());
    if (!back) return;
    CHECK(back->ram == ram);
    CHECK(back->cueCard && back->cueCard->row1 == "R: line starting with R");
    CHECK(!decodeConstantMemory("R999: 00 00 00 00 00 00 00 00").has_value());
    CHECK(!decodeConstantMemory("R001: 00 00").has_value());
}

TEST(state_file_model) {
    CHECK(stateFileModel("MODEL: TI-58C\nPROGRAM:\n1 2\n", Model::TI59) == Model::TI58C);
    CHECK(stateFileModel("PROGRAM:\n1 2\n", Model::TI58) == Model::TI58);
    CHECK(stateFileModel("MODEL: TI-57\n", Model::TI58) == Model::TI58);
}

TEST(retired_skip_reset_and_key_99_are_errors) {
    auto r = parseStateFile("SKIP-RESET: on\nREGISTERS:\n01 = 1\nKEYSTROKES:\n99 82\n");
    CHECK_EQ(r.errors.size(), size_t{2});
    CHECK(r.errors.size() == 2 && r.errors[0].find("reload") != std::string::npos);
    CHECK(r.errors.size() == 2 && r.errors[1].find("PrinterTrace:") != std::string::npos);
    CHECK_EQ(r.registers.size(), size_t{1});   // the rest still loads
    CHECK_EQ(r.keystrokes.size(), size_t{1});  // key 82
}

TEST(control_directives) {
    using K = KeystrokeEvent::Kind;
    auto r = parseStateFile("KEYSTROKES:\nPrinterTrace: on\nPrinterTrace: OFF\nCutPaper:\nDebugPanel: log\n"
                            "Freeze: CPU\nFreezeOnStart: Calculator\nFreezeOnStart: off\nStep: cpu 3\nStep: Calculator\n"
                            "Resume:\n");
    CHECK(r.errors.empty());
    std::vector<K> kinds;
    for (auto& e : r.keystrokes) kinds.push_back(e.kind);
    CHECK(kinds == (std::vector<K>{K::PrinterTrace, K::PrinterTrace, K::CutPaper, K::ShowPanel, K::Freeze,
                                   K::FreezeOnStart, K::FreezeOnStart, K::Step, K::Step, K::Resume}));
    if (r.keystrokes.size() == 10) {
        CHECK(r.keystrokes[0].on && !r.keystrokes[1].on);
        CHECK(r.keystrokes[3].panel == DebugPanel::Log);
        CHECK(r.keystrokes[4].panel == DebugPanel::Cpu);
        CHECK(r.keystrokes[5].on && r.keystrokes[5].panel == DebugPanel::Calculator);
        CHECK(!r.keystrokes[6].on);
        CHECK(r.keystrokes[7].panel == DebugPanel::Cpu && r.keystrokes[7].count == 3);
        CHECK(r.keystrokes[8].count == 1);
    }
    auto bad = parseStateFile("KEYSTROKES:\nPrinterTrace:\nDebugPanel: ASM\nFreeze: Log\nStep: CPU 0\nResume: now\n");
    CHECK_EQ(bad.errors.size(), size_t{5});
    CHECK(bad.keystrokes.empty());
}

TEST(module_catalog_from_cuecards_txt) {
    auto text = testroms::readFile("roms/solid-state/cuecards.txt");
    CHECK(text.has_value());
    if (!text) return;
    auto all = allModuleMetadata(*text);
    CHECK_EQ(static_cast<int>(all.size()), 14);
    CHECK_EQ(all[0].id, std::string("ML"));
    CHECK_EQ(all[0].menuTitle, std::string("Master Library"));
    CHECK_EQ(all[1].id, std::string("LE"));  // menu sort 1; the rest are 5 (file order kept)
    for (size_t i = 1; i < all.size(); ++i) CHECK(all[i - 1].menuSort <= all[i].menuSort);

    CHECK(moduleRomFile(*text, "ML") == std::optional<std::string>("TMC0541.txt"));
    CHECK(moduleRomFile(*text, "RP") == std::optional<std::string>("TMC0555.txt"));
    CHECK(!moduleRomFile(*text, "XX").has_value());

    auto ml = moduleCards(*text, "ML");
    CHECK_EQ(static_cast<int>(ml.cards.size()), 25);
    CHECK_EQ(ml.metadata.title, std::string("MASTER LIBRARY MODULE -1-"));
    CHECK(ml.cards.count(1) && ml.cards[1].id == "ML-01" && ml.cards[1].template_ == CueCardTemplate::SolidState);
    CHECK(ml.cards.count(2) && ml.cards[2].labels[3] == kCueCardInvisibleMarker);
    CHECK_EQ(ml.cards[2].labels[1], std::string("→ A⁻¹"));
    auto le = moduleCards(*text, "LE");
    CHECK(le.cards.count(1) && le.cards[1].id == "LE-01");
    auto rp = moduleCards(*text, "RP");  // last module, no cue cards
    CHECK(rp.cards.empty());
    CHECK_EQ(rp.metadata.menuTitle, std::string("RPN Simulator"));
    auto eof = moduleCards("MODULE-ID: Z\nCUECARD: 3\nTitle: LAST\n", "Z");  // flushed at end of text
    CHECK(eof.cards.count(3) && eof.cards[3].title == "LAST");
}

TEST(card_file_names) {
    CHECK(isCardFileName("a.u59") && isCardFileName("A.U59") && isCardFileName("b.BIN") && isCardFileName("c.Bin"));
    CHECK(!isCardFileName("a.txt") && !isCardFileName("u59") && !isCardFileName(".a.u59.icloud") && !isCardFileName(".hidden.u59"));
    CHECK_EQ(withDefaultCardExtension("prog"), std::string("prog.U59"));
    CHECK_EQ(withDefaultCardExtension("prog.bin"), std::string("prog.bin"));
}

TEST(settings_resolve) {
    using namespace cu59::settings;
    CHECK(resolveStartupModel(std::nullopt, std::nullopt) == Model::TI59);
    CHECK(resolveStartupModel(2, 1) == Model::TI58C);
    CHECK(resolveStartupModel(-1, 1) == Model::TI58);   // last used
    CHECK(resolveStartupModel(7, 2) == Model::TI58C);   // out of range → last used
    CHECK(resolveStartupModel(-1, 9) == Model::TI59);
    CHECK_EQ(resolveTraceMaxMB(std::nullopt), 50);
    CHECK_EQ(resolveTraceMaxMB(0), 50);
    CHECK_EQ(resolveTraceMaxMB(12), 12);
    CHECK_EQ(resolveModuleID(std::nullopt), std::string("ML"));
    CHECK_EQ(resolveModuleID(std::string("LE")), std::string("LE"));
}

TEST(cue_card_geometry) {
    CueCardContent c;
    c.template_ = CueCardTemplate::MagnetCard;
    c.title = "Interest";
    const double w = 800, h = 200;
    const CueCardLayout& L = cueCardLayout(c.template_);
    CueCardGeometry g = cueCardGeometry(c, w, h);
    double charW = L.gridFontSize * 0.64;
    CHECK_EQ(g.gridLeft, w * (L.xFractions[0] - L.cellWidthFraction / 2) + charW * 0.5);
    CHECK_EQ(g.gridRight, w * (L.xFractions[4] + L.cellWidthFraction / 2) - charW);
    CHECK_EQ(g.titleFontSize, L.titleFontSize);   // short title: no shrink
    CHECK_EQ(g.bankLeft.cx, w * 0.08);
    CHECK_EQ(g.bankRight.height, h * 0.15);
    CHECK_EQ(g.row2Left.width + g.row2Right.width, g.gridWidth);
    CHECK_EQ(g.washHeight, h * 0.28);
    c.title = std::string(80, 'W');
    CHECK(cueCardGeometry(c, w, h).titleFontSize < L.titleFontSize);
    CHECK_EQ(cueCardInk(c), 0u);
    c.color = CueCardInkColor::Sharpie;
    CHECK_EQ(cueCardInk(c), 0x702A48u);
    c.template_ = CueCardTemplate::SolidState;
    CHECK_EQ(cueCardInk(c), 0xC49223u);   // printed gold whatever PencilColor says
}
