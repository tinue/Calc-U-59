// Smoke tests for Core/TI59Machine driven through the real ROMs in roms/:
// every model boots to the keyboard scan loop, keys reach the firmware,
// and the TI-58C RAM, card reader, printer and breakpoint paths respond.

#include "TestHarness.hpp"
#include "TestRoms.hpp"

using cu59::Model;

namespace {

/// Display as text, leftmost digit first, using the LED decode rules
/// (ctrl 0/1/8/9 = digit, 5/6 = minus/degree, others blank).
std::string displayText(const TI59Machine& m) {
    DisplaySnapshot d = m.getDisplay();
    std::string s;
    for (int i = 11; i >= 0; --i) {
        if (d.suppressedMask & (1u << i)) continue;
        switch (d.ctrl[i]) {
        case 0: case 1: case 8: case 9: s += static_cast<char>('0' + (d.digits[i] & 0xF) % 10); break;
        case 5: s += d.digits[i] == 0 ? '-' : 'o'; break;
        case 6: s += '-'; break;
        default: break;
        }
    }
    return s;
}

// Matrix codes (reference/StateFileFormat.md): 2 = 83, 3 = 84, + = 85, = = 95, CLR = 25.
constexpr int kKey2 = 83, kKey3 = 84, kPlus = 85, kEquals = 95, kClr = 25;

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
        CHECK_EQ(displayText(*m), std::string("0"));
    }
}

TEST(two_plus_three_equals_five) {
    for (Model model : {Model::TI59, Model::TI58C}) {
        auto m = testroms::makeMachine(model);
        testroms::runToScanLoop(*m, model);
        for (int k : {kClr, kKey2, kPlus, kKey3, kEquals}) testroms::tap(*m, model, k);
        CHECK_EQ(displayText(*m), std::string("5"));
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
