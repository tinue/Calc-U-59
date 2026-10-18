// Shared/ debug model: program source decoding, module image, live snapshot,
// program listing, ROM heatmap, ASM overlay parser, ring log and dumps.

#include "TestHarness.hpp"
#include "TestRoms.hpp"
#include "../Shared/AsmOverlay.hpp"
#include "../Shared/Bcd.hpp"
#include "../Shared/DebugLog.hpp"
#include "../Shared/DebugSnapshots.hpp"
#include "../Shared/DebugText.hpp"
#include "../Shared/RomHeatmap.hpp"
#include <filesystem>

using namespace cu59;

namespace {
/// X as the CALCULATOR tab shows it after tapping `keys` (matrix codes) on a fresh TI-59.
std::string xAfter(std::initializer_list<int> keys) {
    auto m = testroms::makeMachine(Model::TI59);
    testroms::runToScanLoop(*m, Model::TI59);
    for (int k : keys) testroms::tap(*m, Model::TI59, k);
    std::vector<uint8_t> romCache;
    auto s = buildLiveSnapshot(*m, Model::TI59, ModuleImage{}, romCache).snap;
    return xRegisterLine(s.xValue, s.xRaw);
}
} // namespace

// Matrix codes: digits 0 92, 1 82, 2 83, 3 84, 5 73, 7 62; . 93, +/- 94, EE 52,
// INV 22, = 95, + 85, / 55, √x 34.
TEST(x_register_entry_and_result) {
    CHECK_EQ(xAfter({}), std::string("X: 0"));
    // Number entry: the image in A.
    CHECK_EQ(xAfter({82, 83, 93, 73}), std::string("X: 12.5"));
    CHECK_EQ(xAfter({82, 83, 93, 73, 94}), std::string("X: -12.5"));
    CHECK_EQ(xAfter({92, 93, 92, 92, 73}), std::string("X: 0.005"));
    CHECK_EQ(xAfter({82, 93, 73, 52, 84}), std::string("X: 1500"));                 // EE display form
    CHECK_EQ(xAfter({82, 83, 94, 52, 84, 94}), std::string("X: -0.012"));
    CHECK_EQ(xAfter({82, 93, 73, 52, 84, 22, 52, 83}), std::string("X: 1520"));     // INV EE keeps the exponent
    CHECK_EQ(xAfter({82, 85, 83}), std::string("X: 2"));
    CHECK_EQ(xAfter({73, 94, 85, 84, 95, 62}), std::string("X: 7"));                // fB's stale minus is ignored
    // Result on display: C, all 13 digits.
    CHECK_EQ(xAfter({83, 34}), std::string("X: 1.414213562373"));
    CHECK_EQ(xAfter({82, 55, 84, 95}), std::string("X: 0.3333333333333"));
    CHECK_EQ(xAfter({82, 52, 73, 94, 95}), std::string("X: 1e-05"));
    CHECK_EQ(xAfter({73, 94, 85, 84, 95}), std::string("X: -2"));
    CHECK_EQ(xAfter({82, 55, 92, 95}), std::string("X: 9.999999999999e+99"));        // overflow clamp
}

namespace {
/// The CALCULATOR tab's current step and X after each debugger STEP through
/// `prog` (started with A, so it begins with LBL A), until step `last` is next.
std::vector<std::string> stepThrough(const std::vector<uint8_t>& prog, int last, Model model = Model::TI59) {
    auto m = testroms::makeMachine(model);
    testroms::runToScanLoop(*m, model);
    m->writeProgram(prog.data(), prog.size());
    pressMatrix(*m, 11);  // A
    m->stepUntilNextKeycode();
    releaseMatrix(*m, 11);
    std::vector<uint8_t> romCache;
    std::vector<std::string> steps;
    for (int i = 0; i < 40; ++i) {
        m->stepUntilNextKeycode();
        m->beginNextStep();
        CHECK_EQ(m->pc(), m->stepDispatchPC());
        auto snap = buildLiveSnapshot(*m, model, ModuleImage{}, romCache).snap;
        steps.push_back(std::to_string(snap.currentStep) + " " + xRegisterLine(snap.xValue, snap.xRaw));
        if (snap.currentStep >= last) break;
    }
    return steps;
}
} // namespace

// Each STEP stops at the step dispatch and shows the next step, one byte at a
// time (operands included), as LRN does after each SST: the GTO completes in
// its last byte and lands on its target, with X intact.
TEST(step_shows_the_next_step) {
    // LBL A, 1, +, GTO 00 17 (GTO at 004, operands at 005/006), Nop…, 2, =, R/S
    std::vector<uint8_t> prog = {76, 11, 1, 85, 61, 0, 17};
    prog.resize(17, 68);
    prog.insert(prog.end(), {2, 95, 91});
    CHECK(stepThrough(prog, 19) ==
          (std::vector<std::string>{"3 X: 1", "4 X: 1", "5 X: 1", "6 X: 1", "17 X: 1", "18 X: 2", "19 X: 3"}));
    // An entry with EE inside a program: A is realigned before each dispatch.
    // LBL A, 1, ., 5, EE, 3, +, 2, =, R/S
    CHECK(stepThrough({76, 11, 1, 93, 5, 52, 3, 85, 2, 95, 91}, 10) ==
          (std::vector<std::string>{"3 X: 1", "4 X: 1", "5 X: 1.5", "6 X: 1.5", "7 X: 1500", "8 X: 1500", "9 X: 2",
                                    "10 X: 1502"}));
    // The TI-58C's ROM has its dispatch elsewhere (082B).
    CHECK(stepThrough(prog, 19, Model::TI58C) ==
          (std::vector<std::string>{"3 X: 1", "4 X: 1", "5 X: 1", "6 X: 1", "17 X: 1", "18 X: 2", "19 X: 3"}));
}

// At idle the cursor is what LRN shows after SST: the counter + 1, or the
// counter itself after RST or a jump (fB[11]).
TEST(idle_cursor_matches_lrn_after_sst) {
    auto m = testroms::makeMachine(Model::TI59);
    testroms::runToScanLoop(*m, Model::TI59);
    std::vector<uint8_t> prog = {1, 85, 61, 0, 17};  // 1 + GTO 00 17 Nop… 2 = R/S
    prog.resize(17, 68);
    prog.insert(prog.end(), {2, 95, 91});
    m->writeProgram(prog.data(), prog.size());
    std::vector<uint8_t> romCache;
    auto next = [&] { return buildLiveSnapshot(*m, Model::TI59, ModuleImage{}, romCache).snap.currentStep; };
    testroms::tap(*m, Model::TI59, 81);  // RST
    CHECK_EQ(next(), 0);
    const int expected[] = {1, 2, 3, 4, 17, 18};
    for (int e : expected) {
        testroms::tap(*m, Model::TI59, 41);  // SST
        CHECK_EQ(next(), e);
    }
}

TEST(program_source_decoding) {
    CHECK(programSourceFrom(0, 0x0100) == ProgramSource::UserProgram);
    CHECK(programSourceFrom(1, 0x0100) == ProgramSource::SolidState);
    CHECK(programSourceFrom(9, 0x0100) == ProgramSource::SolidState);   // bit 0 wins over bit 3
    CHECK(programSourceFrom(8, 0x0100) == ProgramSource::Rom);
    CHECK(programSourceFrom(2, 0x0100) == ProgramSource::FastMode);
    CHECK(programSourceFrom(4, 0x1193) == ProgramSource::FastMode);     // only flag 2 is the return window
    CHECK(programSourceFrom(2, 0x1194) == ProgramSource::SolidStateReturn);
    CHECK(programSourceFrom(2, 0x1500) == ProgramSource::SolidStateReturn);
    CHECK(programSourceFrom(2, 0x1507) == ProgramSource::FastMode);
    CHECK(stepsFromScomPC(ProgramSource::Rom) && !stepsFromScomPC(ProgramSource::SolidState));
}

TEST(module_image_program_table) {
    auto raw = loadModule("TMC0541.txt", testroms::reader());
    CHECK(raw.has_value());
    if (!raw) return;
    std::string err;
    auto img = ModuleImage::parse(*raw, &err);
    CHECK(err.empty());
    CHECK_EQ(img.keycodes.size(), raw->size());
    CHECK(img.programRanges.size() >= 20);
    for (size_t i = 1; i < img.programRanges.size(); ++i)
        CHECK(img.programRanges[i - 1].second <= img.programRanges[i].first);
    auto first = img.programRanges[0];
    auto step = img.libraryStep(static_cast<uint16_t>(first.first + 3));
    CHECK(step && step->program == 1 && step->step == 3);
    CHECK(!img.libraryStep(0xFFFF));
    CHECK_EQ(img.keycodes[0], static_cast<uint8_t>(((*raw)[0] >> 4) * 10 + ((*raw)[0] & 0xF)));  // BCD-decoded

    auto bad = ModuleImage::parse({0x02, 0x00, 0x00, 0x10, 0x00, 0x05, 0x00, 0x20}, &err);
    CHECK(bad.programRanges.empty());
    CHECK(!err.empty());
}

TEST(live_snapshot_and_listing) {
    auto m = testroms::makeMachine(Model::TI59);
    testroms::runToScanLoop(*m, Model::TI59);
    // LBL A, STO 12, RCL 12, GTO 01 23, R/S
    const uint8_t prog[] = {76, 11, 42, 12, 43, 12, 61, 1, 23, 91};
    m->writeProgram(prog, sizeof prog);
    auto reg = encodeBcd(std::string_view("2.5"));
    m->writeDataRegister(3, reg.data());

    std::vector<uint8_t> romCache;
    auto lib = ModuleImage::parse(*loadModule("TMC0541.txt", testroms::reader()));
    auto b = buildLiveSnapshot(*m, Model::TI59, lib, romCache);
    const auto& s = b.snap;
    CHECK(s.programSource == ProgramSource::UserProgram);
    CHECK_EQ(s.currentStep, 0);
    CHECK_EQ(static_cast<int>(s.programWindow.size()), 6);  // steps 0–5
    CHECK_EQ(s.programWindow[1].mnemonic, std::string("A"));
    CHECK_EQ(s.programWindow[3].mnemonic, std::string("12"));  // STO operand
    CHECK(s.angleMode == AngleMode::Deg);
    CHECK_EQ(static_cast<int>(s.nonZeroRegs.size()), 1);
    if (!s.nonZeroRegs.empty()) {
        CHECK_EQ(s.nonZeroRegs[0].num, 3);
        CHECK_EQ(s.nonZeroRegs[0].value, 2.5);
    }
    for (const auto& row : s.scomRows) CHECK_EQ(row.size(), size_t{16});
    CHECK_EQ(s.statusRegister, std::string(s.scomRows[0].rbegin(), s.scomRows[0].rend()));  // SCOM[0], nibble 15 first
    CHECK(b.argSteps == (std::set<int>{3, 5, 7, 8}));

    auto listing = programListing(b.sourceKeycodes, b.argSteps, s.currentStep);
    CHECK_EQ(listing.size(), b.sourceKeycodes.size());
    CHECK(listing[0].isCurrent && !listing[1].isCurrent);
    CHECK_EQ(listing[7].mnemonic, std::string("01"));
    CHECK_EQ(listing[9].mnemonic, std::string("R/S"));
    CHECK(buildLiveSnapshot(*m, Model::TI59, lib, romCache).snap == s);
}

TEST(rom_heatmap_counts_new_frames_once) {
    std::vector<CpuFrame> f(3);
    f[0].seqno = 1; f[0].pc = 0x10;
    f[1].seqno = 2; f[1].pc = 0x10;
    f[2].seqno = 3; f[2].pc = 0x1500;  // beyond code ROM: ignored
    RomHeatmap h;
    h.ingest(f.data(), f.size());
    h.ingest(f.data(), f.size());  // same frames again: not recounted
    CHECK_EQ(h.counts()[0x10], 2u);
    int published = 0;
    for (int i = 0; i < 12; ++i) published += h.publishTick();
    CHECK_EQ(published, 1);
    h.resetBaseline(5);
    f[0].seqno = 5; f[1].seqno = 6;
    h.ingest(f.data(), 2);
    CHECK_EQ(h.counts()[0x10], 1u);
}

TEST(asm_overlay_parser) {
    int files = 0;
    for (const auto& e : std::filesystem::directory_iterator("examples/assembly")) {
        if (e.path().extension() != ".asm") continue;
        auto text = testroms::readFile(e.path().string());
        auto words = parseAsmWords(*text);
        CHECK(!words.empty());
        for (uint16_t w : words) CHECK(w <= 0x1FFF);
        ++files;
    }
    CHECK(files >= 1);
    auto words = parseAsmWords("title\nHEX:\n0x0A01 1987abcd\nfoo 12 0x1FFFF000\n");
    // "1987abcd" splits into two words; "12" is too short; words are masked to 13 bits.
    CHECK(words == (std::vector<uint16_t>{0x0A01, 0x1987, 0xABCD & 0x1FFF, 0x1FFF, 0x1000}));
    auto message = [](const char* t) {
        try { parseAsmWords(t); } catch (const AsmParseError& e) { return std::string(e.what()); }
        return std::string();
    };
    CHECK_EQ(message("0A01\n"), std::string("No HEX: section found in ASM file."));
    CHECK_EQ(message("HEX:\nno words\n"), std::string("No hex opcode words found after HEX: in ASM file."));
    CHECK_EQ(message("HEX:\n0x123\n"), std::string("Invalid token in HEX section: 123"));
}

TEST(asm_overlay_runs) {
    auto m = testroms::makeMachine(Model::TI59);
    testroms::runToScanLoop(*m, Model::TI59);
    auto r = runAsmOverlay(*m, {0x0A01, 0x0A01});
    CHECK(r.loaded);
    CHECK(r.entered);
    CHECK(!runAsmOverlay(*m, std::vector<uint16_t>(3000, 0)).loaded);
}

TEST(ring_log_display_pages) {
    RingLog log;
    CHECK_EQ(log.displayText(), std::string());
    log.write("a");
    log.write("b");
    CHECK_EQ(log.displayText(), std::string("a\nb"));
    for (int i = 0; i < 100; ++i) log.write("x" + std::to_string(i));
    std::string page = log.displayText();  // > one page new: only the newest page
    CHECK_EQ(std::count(page.begin(), page.end(), '\n'), 39);
    CHECK(page.substr(page.size() - 3) == "x99");
    log.write("y");
    std::string slow = log.displayText();  // one new line: up to 10 pages
    CHECK_EQ(std::count(slow.begin(), slow.end(), '\n'), 102);
    log.clear();
    CHECK_EQ(log.displayText(), std::string());
}

TEST(debug_dumps) {
    auto m = testroms::makeMachine(Model::TI59);
    testroms::runToScanLoop(*m, Model::TI59);
    auto v = encodeBcd(std::string_view("42"));
    m->writeDataRegister(7, v.data());
    auto vars = dumpVars(*m, Model::TI59);
    CHECK(vars.size() >= 2);
    bool found = std::find(vars.begin(), vars.end(), std::string("V07 = 42")) != vars.end();
    if (!found) for (auto& l : vars) std::fprintf(stderr, "  vars: %s\n", l.c_str());
    CHECK(found);
    auto scom = dumpScom(*m);
    CHECK_EQ(scom.size(), size_t{17});
    CHECK_EQ(scom[1].substr(0, 4), std::string("S00 "));
    auto mem = dumpMemory(*m);
    CHECK(mem.size() >= 2);
    CHECK_EQ(dumpStepCounterAnalysis(*m).size(), size_t{15});
    CHECK(dumpProg(*m)[0].rfind("── Prog P000–P", 0) == 0);
}

TEST(debug_panel_text) {
    CHECK_EQ(debugPanelFontSize(300), 9);
    CHECK_EQ(debugPanelFontSize(400), 11);
    CHECK_EQ(debugPanelFontSize(800), 13);
    CHECK_EQ(partitionLine(60, 60), std::string("Steps: 480, Registers: 60 (479.59)"));
    CHECK_EQ(partitionLine(120, 0), std::string("Steps: 960, Registers: 0 (959.)"));
    CHECK_EQ(angleModeLabel(std::nullopt), std::string("?"));
    CHECK_EQ(angleModeLabel(AngleMode::Grad), std::string("GRAD"));
    CHECK_EQ(registerLine({5, 2.5, false}), std::string("R05 = 2.5"));
    CHECK_EQ(registerLine({2, 1731371734.99909, true}), std::string("H02 = 1731371734.999"));  // 13 digits
    CHECK_EQ(hirLine(1, 3.14159265), std::string("1: 3.1416"));
    CHECK_EQ(tRegisterLine(0), std::string("T: 0"));
    CHECK_EQ(xRegisterLine(-2.5, ""), std::string("X: -2.5"));
    CHECK_EQ(xRegisterLine(0, "C=000000000000000a"), std::string("X: C=000000000000000a"));
    CHECK(xRegisterColor(0, "") != xRegisterColor(1, "") && xRegisterColor(1, "") != xRegisterColor(1, "A=f"));
    CHECK_EQ(returnLevelColor(0, false), 0x409940u);
    CHECK_EQ(returnLevelColor(2, true), returnLevelColor(1, true));
    CHECK_EQ(returnLevelColor(5, false), 0xCCCCCCu);
    CHECK_EQ(currentStepMarker(true), std::string("← next"));
    CHECK_EQ(stepHighlightColor(ProgramSource::FastMode), stepHighlightColor(ProgramSource::UserProgram));
    CHECK(condFlag(0x0800) && !condFlag(0x0001) && idleFlag(0x0001));
    uint8_t n[16] = {0x15, 0xA};  // high bits are masked
    CHECK_EQ(registerNibbles(n), std::string("00000000000000A5"));
    CHECK_EQ(hexBin16(0x1F0A), std::string("1F0A [0001 1111 0000 1010]"));
}
