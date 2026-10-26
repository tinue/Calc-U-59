// Multi-stage presets: reloads after KEYSTROKES, CARD: … END-CARD blocks and
// the ArmCard: / InsertCard: directives (Shared/StateFile), and the card bank
// a CARD: block builds (Shared/CardFile buildCardBank), checked byte for byte
// against banks the TI-59 ROM wrote (tests/fixtures/cards/).

#include "TestHarness.hpp"
#include "TestRoms.hpp"
#include "../Shared/CardFile.hpp"
#include "../Shared/StateFile.hpp"
#include "../Shared/TextUtil.hpp"

using namespace cu59;
using K = KeystrokeEvent::Kind;

namespace {

std::vector<K> kinds(const LoadStateResult& r) {
    std::vector<K> v;
    for (auto& e : r.keystrokes) v.push_back(e.kind);
    return v;
}

bool hasError(const LoadStateResult& r, const std::string& part) {
    for (auto& e : r.errors)
        if (e.find(part) != std::string::npos) return true;
    return false;
}

/// A tests/fixtures/cards/*.hex file: hex bytes, # comments.
std::vector<uint8_t> hexFixture(const std::string& name) {
    std::vector<uint8_t> out;
    auto file = testroms::readFile("tests/fixtures/cards/" + name);
    CHECK(file.has_value());
    const std::string text = file.value_or("");
    for (auto line : splitLines(text))
        for (auto t : splitWhitespace(stripInlineComment(line))) out.push_back(static_cast<uint8_t>(std::stoi(std::string(t), nullptr, 16)));
    return out;
}

RegisterValue reg(int n, const char* value) { return {n, encodeBcd(value), false}; }

} // namespace

TEST(stages_sections_after_keystrokes_are_reloads) {
    auto r = parseStateFile("PROGRAM:\n01\nKEYSTROKES:\n91\n"
                            "PROGRAM:\n02 03\nREGISTERS:\n05 = 2\nCUECARD:\nTitle: Part 2\n"
                            "KEYSTROKES:\n91\nREGISTERS:\n06 = 1\n");
    CHECK(r.errors.empty());
    CHECK_EQ(r.programSteps.size(), size_t{1});
    CHECK(!r.cueCard);
    CHECK(kinds(r) == (std::vector<K>{K::Key, K::Reload, K::Key, K::Reload}));
    const ReloadStage& a = *r.keystrokes[1].reload;
    CHECK_EQ(a.programSteps.size(), size_t{2});
    CHECK_EQ(a.programSteps[0].stepAddr, 0);  // a reload's program starts at step 000 again
    CHECK_EQ(int(a.programSteps[1].keycode), 3);
    CHECK_EQ(a.registers.size(), size_t{1});
    CHECK(a.cueCard && a.cueCard->title == "Part 2");
    const ReloadStage& b = *r.keystrokes[3].reload;
    CHECK(b.programSteps.empty() && b.registers.size() == 1 && !b.cueCard);
}

TEST(stages_partition_after_keystrokes_belongs_to_the_reload) {
    auto r = parseStateFile("PARTITION: 479.59\nKEYSTROKES:\n91\nPARTITION: 639.39\nREGISTERS:\n01 = 1\n");
    CHECK_EQ(r.partitionMaxStep, 479);
    CHECK(kinds(r) == (std::vector<K>{K::Key, K::Reload}));
    CHECK(r.keystrokes[1].reload->partitionMaxStep == std::optional<int>(639));
    CHECK_EQ(r.keystrokes[1].reload->registers.size(), size_t{1});
}

TEST(stages_card_block_and_directives) {
    auto r = parseStateFile("KEYSTROKES:\nArmCard: MEM:Vars\nInsertCard: Results\n91\n"
                            "CARD: mem:Vars\nBank: 3\nProtected: yes\nPartition: 719.29\n"
                            "PROGRAM:\n01 02\nREGISTERS:\n30 = 1.5\n29 = 2\nCUECARD:\nTitle: Vars\nEND-CARD\n");
    CHECK(r.usesCardReader);
    CHECK(kinds(r) == (std::vector<K>{K::ArmCard, K::InsertCard, K::Key}));  // a CARD: block is no reload
    CHECK_EQ(r.keystrokes[0].cardName, std::string("MEM:Vars"));
    CHECK(r.keystrokes[0].card != nullptr);  // the "mem:" prefix in any case
    CHECK(r.keystrokes[1].card == nullptr);
    const CardDefinition& c = *r.keystrokes[0].card;
    CHECK_EQ(c.bank, 3);
    CHECK(c.protect);
    CHECK(c.partitionMaxStep == std::optional<int>(719));
    CHECK_EQ(c.programSteps.size(), size_t{2});
    CHECK_EQ(c.programSteps[0].stepAddr, 480);  // bare keycodes start at the bank's first step
    CHECK_EQ(c.registers.size(), size_t{1});    // R29 lies in bank 4
    CHECK(hasError(r, "register 29 is not in bank 3"));
    CHECK(c.cueCard && c.cueCard->title == "Vars");
}

TEST(stages_card_errors) {
    CHECK(hasError(parseStateFile("CARD: Results\nBank: 1\nEND-CARD\n"), "only an in-memory card"));
    CHECK(hasError(parseStateFile("CARD: mem:x\nEND-CARD\n"), "needs Bank: 1–4"));
    CHECK(hasError(parseStateFile("CARD: mem:x\nBank: 5\nEND-CARD\n"), "Bank: must be 1–4"));
    CHECK(hasError(parseStateFile("END-CARD\n"), "END-CARD without CARD:"));
    CHECK(hasError(parseStateFile("CARD: mem:x\nBank: 1\nPROGRAM:\n240 01\nEND-CARD\n"), "step 240 is not in bank 1"));
    CHECK(hasError(parseStateFile("CARD: mem:x\nBank: 1\nCARD: mem:x\nBank: 2\nEND-CARD\n"), "is defined twice"));
    CHECK(hasError(parseStateFile("KEYSTROKES:\nArmCard:\n"), "needs a card name"));
    CHECK(hasError(parseStateFile("KEYSTROKES:\nInsertCard: mem:\n"), "needs a card name"));
    CHECK(hasError(parseStateFile("KEYSTROKES:\nArmCard: a/b\n"), "path separator"));
    auto open = parseStateFile("CARD: mem:x\nBank: 1\nKEYSTROKES:\n91\n");
    CHECK(hasError(open, "has no END-CARD"));
    CHECK(kinds(open) == (std::vector<K>{K::Key}));  // the keys still count
}

TEST(card_bank_matches_the_rom_data_bank) {
    CardDefinition c;
    c.name = "mem:A";
    c.bank = 4;
    c.registers = {reg(0, "1.5"), reg(29, "2.25e-7")};
    CHECK(buildCardBank(c, 60) == hexFixture("bank4-data.hex"));
}

TEST(card_bank_matches_the_rom_protected_program_bank) {
    CardDefinition c;
    c.name = "mem:B";
    c.bank = 1;
    c.protect = true;
    c.programSteps = {{0, 1}, {1, 94}, {2, 96}, {3, 91}};  // 1 +/- Write R/S
    CHECK(buildCardBank(c, 60) == hexFixture("bank1-protected.hex"));
    c.partitionMaxStep = 159;  // 20 program registers: bank 1 no longer lies entirely in program memory
    auto d = buildCardBank(c, 60);
    CHECK_EQ(int(d[0]), 0x12);
    CHECK_EQ(int(d[1]), 0x10);
}
