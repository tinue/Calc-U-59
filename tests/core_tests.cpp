// Smoke tests for Core/TI59Machine driven through the real ROMs in roms/:
// every model boots to the keyboard scan loop, keys reach the firmware,
// and the TI-58C RAM, card reader, printer and breakpoint paths respond.

#include "TestHarness.hpp"
#include "TestRoms.hpp"

#include <vector>

using cu59::Model;

namespace {

// Matrix codes (reference/StateFileFormat.md): 2 = 83, 3 = 84, + = 85, = = 95, CLR = 25.
constexpr int kKey2 = 83, kKey3 = 84, kPlus = 85, kEquals = 95, kClr = 25;
constexpr int kKey0 = 92, kRecip = 35;

} // namespace

TEST(rom_sentinels_and_sizes) {
    for (Model m : {Model::TI59, Model::TI58, Model::TI58C}) {
        auto words = cu59::loadRom(m, testroms::reader());
        CHECK_EQ(static_cast<int>(words.size()), 6144);
        auto k = cu59::loadConstants(m, testroms::reader());
        CHECK_EQ(static_cast<int>(k.size()), 64 * 16);
    }
    auto ti59 = cu59::loadRom(Model::TI59, testroms::reader());
    CHECK_EQ(ti59[0], 0x0A01);
    CHECK_EQ(ti59[6143], 0x1987);
}

TEST(rom_missing_file_throws) {
    bool threw = false;
    try {
        cu59::loadRom(Model::TI59, [](const std::string&) { return std::optional<std::string>(); });
    } catch (const cu59::RomError&) { threw = true; }
    CHECK(threw);
}

TEST(module_master_library_parses) {
    auto lib = cu59::loadModule("TMC0541.txt", testroms::reader());
    CHECK(lib.has_value());
    if (lib) CHECK(lib->size() > 4000 && lib->size() <= 5000);
}

TEST(boot_reaches_scan_loop_all_models) {
    for (Model model : {Model::TI59, Model::TI58, Model::TI58C}) {
        auto m = testroms::makeMachine(model);
        CHECK(testroms::runToScanLoop(*m, model));
        CHECK_EQ(testroms::displayText(*m), std::string("0"));
    }
}

TEST(two_plus_three_equals_five) {
    for (Model model : {Model::TI59, Model::TI58C}) {
        auto m = testroms::makeMachine(model);
        testroms::runToScanLoop(*m, model);
        for (int k : {kClr, kKey2, kPlus, kKey3, kEquals}) testroms::tap(*m, model, k);
        CHECK_EQ(testroms::displayText(*m), std::string("5"));
    }
}

// Error-blink period (0 1/x) of the TI-59 ROM in seconds: 0x0655 SET.IDLE
// re-lights the display once per lit pass; a lit phase starts at the first one
// after a dark phase (≥ 2000 ticks without it).
static double errorBlinkPeriod(Model model, bool printer) {
    auto m = testroms::makeMachine(model);
    m->setPrinterConnected(printer);
    testroms::runToScanLoop(*m, model);
    for (int k : {kKey0, kRecip}) testroms::tap(*m, model, k);
    std::vector<uint64_t> litStarts;
    uint64_t lastSetIdle = 0;
    for (int i = 0; i < 400'000 && litStarts.size() < 4; ++i) {
        m->step();
        if (m->pc() != 0x0655) continue;
        uint64_t t = m->elapsedTicks();
        if (lastSetIdle == 0 || t - lastSetIdle > 2000) litStarts.push_back(t);
        lastSetIdle = t;
    }
    CHECK_EQ(litStarts.size(), size_t{4});
    if (litStarts.size() < 4) return 0;
    return double(litStarts[3] - litStarts[1]) / 2 / cu59::info(model).instructionHz;
}

// The error blink of a real TI-59 (0 1/x), filmed next to a stopwatch on the
// PC-100C: 0.899 s per period; stand-alone, 0.449 s. The printer's KP line at
// D0 sends every idle pass through the confirmation scan (0x0659–0x0660).
TEST(ti59_error_blink_period_matches_hardware) {
    double period = errorBlinkPeriod(Model::TI59, true);
    CHECK(period > 0.899 * 0.98 && period < 0.899 * 1.02);
    period = errorBlinkPeriod(Model::TI59, false);
    CHECK(period > 0.449 * 0.98 && period < 0.449 * 1.02);
}

// A real TI-58's error blink (Pavel's unit, 384.6 kHz): 0.6801 s per period
// stand-alone, 1.2122 s on the PC-100C. Every idle pass detours through the
// TI-58's card veto (digit 7, the 0x0459 card poll); with the printer also
// through the KP·D0 confirmation scan. Emulated: 0.681 s and 1.215 s.
TEST(ti58_error_blink_period_matches_hardware) {
    double period = errorBlinkPeriod(Model::TI58, false);
    CHECK(period > 0.6801 * 0.99 && period < 0.6801 * 1.01);
    period = errorBlinkPeriod(Model::TI58, true);
    CHECK(period > 1.2122 * 0.99 && period < 1.2122 * 1.01);
}

// The TI-58C blink counts idle passes at full speed, so its length in
// instructions is fixed by the ROM path alone; a real unit's blink in seconds
// gives that unit's clock, to which its other measurements are normalised.
static double ti58cErrorBlinkTicks(bool printer) {
    auto m = testroms::makeMachine(Model::TI58C);
    m->setPrinterConnected(printer);
    testroms::runToScanLoop(*m, Model::TI58C);
    for (int k : {kKey0, kRecip}) testroms::tap(*m, Model::TI58C, k);
    const double hz = cu59::info(Model::TI58C).instructionHz;
    // The multiplex leaves short gaps in a lit phase; a lit phase starts after
    // ≥ 10 ms without any driven digit.
    const uint64_t gap = static_cast<uint64_t>(0.010 * hz);
    std::vector<uint64_t> litStarts;
    uint64_t lastLit = 0;
    m->takeDisplay();
    for (int i = 0; i < 40'000 && litStarts.size() < 4; ++i) {
        m->stepN(5, false);
        DisplaySnapshot d = m->takeDisplay();
        bool lit = false;
        for (float duty : d.digitDuty) lit = lit || duty > 0.0f;
        if (!lit) continue;
        uint64_t t = m->elapsedTicks();
        if (lastLit == 0 || t - lastLit > gap) litStarts.push_back(t);
        lastLit = t;
    }
    CHECK_EQ(litStarts.size(), size_t{4});
    if (litStarts.size() < 4) return 0;
    return double(litStarts[3] - litStarts[1]) / 2;
}

// Pavel's TI-58C measured PHI 194.7 kHz on the scope (389.4 kHz resonator) and
// blinks 0.9185 s stand-alone, 0.7234 s on the PC-100C (faster with the
// printer, unlike the TI-59 and TI-58). At its clock that is 11,177 and 8,803
// instructions. (Another unit blinks 0.896 s
// stand-alone, as at 400 kHz.)
TEST(ti58c_error_blink_period_matches_hardware) {
    const double unitHz = 389400.0 / 32;
    double measured = 0.9185 * unitHz;
    double ticks = ti58cErrorBlinkTicks(false);
    CHECK(ticks > measured * 0.99 && ticks < measured * 1.01);
    measured = 0.7234 * unitHz;
    ticks = ti58cErrorBlinkTicks(true);
    CHECK(ticks > measured * 0.99 && ticks < measured * 1.01);
}

// takeDisplay() reports how long each position was driven: a steady IDLE display
// reads 1.0 for lit positions and 0 for suppressed ones, a computing CPU 0.
TEST(display_duty_is_normalised_to_the_multiplex) {
    for (Model model : {Model::TI59, Model::TI58C}) {
        auto m = testroms::makeMachine(model);
        testroms::runToScanLoop(*m, model);
        for (int k : {kKey2, kKey3}) testroms::tap(*m, model, k);  // shows "23"
        m->takeDisplay();
        m->stepN(20000, false);
        DisplaySnapshot d = m->takeDisplay();
        int lit = 0, dark = 0;
        for (float duty : d.digitDuty) {
            if (duty > 0.95f && duty <= 1.0f) ++lit;
            if (duty == 0.0f) ++dark;                           // leading zeros, exponent: not driven
        }
        CHECK_EQ(lit, 2);
        CHECK_EQ(dark, 10);
        CHECK(d.pollTicks > 0);
        CHECK_EQ(m->takeDisplay().pollTicks, d.pollTicks);       // no cycle since: same snapshot
    }
}

TEST(ti58c_ram_round_trip) {
    auto m = testroms::makeMachine(Model::TI58C);
    testroms::runToScanLoop(*m, Model::TI58C);
    std::vector<uint8_t> a(1920), b(1920);
    m->serialiseRAM(a.data());
    uint8_t reg[16] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6};
    m->writeRAMReg(5, reg);
    m->serialiseRAM(b.data());
    CHECK(a != b);
    m->deserialiseRAM(a.data());
    std::vector<uint8_t> c(1920);
    m->serialiseRAM(c.data());
    CHECK(a == c);
}

TEST(card_insert_and_eject) {
    auto m = testroms::makeMachine(Model::TI59);
    testroms::runToScanLoop(*m, Model::TI59);
    // The mode (read/write) is set later by the ROM's card opcodes, not by insertion.
    m->insertCard(nullptr, 0);  // blank card
    CHECK(m->isCardPresent());
    m->cardEject();
    CHECK(!m->isCardPresent());
    CHECK_EQ(m->cardMode(), 0);
}

TEST(printer_print_key_emits_line) {
    auto m = testroms::makeMachine(Model::TI59);
    m->setPrinterConnected(true);
    testroms::runToScanLoop(*m, Model::TI59);
    testroms::tap(*m, Model::TI59, kKey2);
    m->pressPrinterPrint(true);
    m->stepN(3000, false);
    m->pressPrinterPrint(false);
    m->stepN(200000, false);
    auto lines = m->drainPrinterLines();
    CHECK(!lines.empty());
}

TEST(breakpoint_sets_step_bit31) {
    auto m = testroms::makeMachine(Model::TI59);
    testroms::runToScanLoop(*m, Model::TI59);
    uint16_t target = m->pc();
    m->setTraceFlags(m->traceFlags() | TRACE_BREAKPOINTS);
    m->addBreakpoint(target);
    bool hit = false;
    for (int i = 0; i < 20000 && !hit; ++i) hit = (m->step() & 0x80000000u) != 0;
    CHECK(hit);
}
