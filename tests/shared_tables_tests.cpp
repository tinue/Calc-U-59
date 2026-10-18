// Shared/ data tables: key names (against the Swift golden), keyboard map,
// 7-segment patterns, printer font, key layout and model info.

#include "TestHarness.hpp"
#include "TestRoms.hpp"
#include "../Shared/KeyNames.hpp"
#include "../Shared/KeyboardLayout.hpp"
#include "../Shared/KeyboardMap.hpp"
#include "../Shared/PrinterFont.hpp"
#include "../Shared/SevenSegment.hpp"
#include "../Shared/TextUtil.hpp"

using namespace cu59;

TEST(keynames_match_swift_golden) {
    auto text = testroms::readFile("tests/golden/keynames.txt");
    CHECK(text.has_value());
    if (!text) return;
    int lines = 0;
    for (std::string_view line : splitLines(*text)) {
        if (line.empty()) continue;
        ++lines;
        if (line[0] == 'M') {
            auto w = splitWords(line);
            CHECK(w.size() == 4);
            if (w.size() != 4) continue;
            auto kc = static_cast<uint8_t>(*parseDec(w[1]));
            CHECK_EQ(mnemonic(kc), std::string(w[2]));
            CHECK_EQ(stepsAfter(kc), static_cast<int>(*parseDec(w[3])));
        } else if (line[0] == 'A') {
            size_t bar = line.find('|');
            std::vector<uint8_t> steps;
            for (auto t : splitWords(line.substr(2, bar - 2))) steps.push_back(static_cast<uint8_t>(*parseDec(t)));
            std::set<int> expected;
            for (auto t : splitWords(line.substr(bar + 1))) expected.insert(static_cast<int>(*parseDec(t)));
            CHECK(argumentSteps(steps) == expected);
        }
    }
    CHECK(lines > 400);
}

TEST(keyboard_map_rules) {
    auto codes = [](char32_t key, char32_t produced, bool letter, bool shift = false, bool cmd = false) {
        return matrixCodesFor({key, produced, letter, shift, cmd});
    };
    using V = std::vector<uint8_t>;
    CHECK(codes('a', 'a', true) == V{11});
    CHECK(codes('a', 'A', true, true) == (V{21, 11}));        // Shift+A → 2nd A = A′
    CHECK(codes('E', 'E', true, true) == (V{21, 15}));
    CHECK(codes('f', 'f', true).empty());                      // unbound letter
    CHECK(codes('x', 'x', true) == V{65});                     // × via x
    CHECK(codes('x', 'X', true, true) == (V{21, 65}));         // Shift rule applies to every bound letter
    CHECK(codes('.', '>', false, true) == V{52});              // Shift+. → '>' → EE
    CHECK(codes(',', '<', false, true) == V{94});              // Shift+, → '<' → +/−
    CHECK(codes('8', '*', false, true) == V{65});              // produced char wins
    CHECK(codes(kKeyEscape, 0, false) == V{25});
    CHECK(codes(kKeyReturn, 0, false) == V{95});
    CHECK(codes(kKeyEnter, 0, false) == V{95});
    CHECK(codes('5', '5', false) == V{73});
    CHECK(codes('a', 'a', true, false, true).empty());         // Command chords never reach the calculator
    CHECK(codes(0x00E4, 0x00E4, true).empty());                // non-ASCII letter
}

TEST(seven_segment_decode) {
    CHECK_EQ(segmentsFor(8, 0, false), 0x7F);
    CHECK_EQ(segmentsFor(7, 9, false), 0b0000111);  // 7 lights A B C only
    CHECK_EQ(segmentsFor(3, 0, true), 0);           // zero-suppressed
    CHECK_EQ(segmentsFor(0, 5, false), kSegmentsMinus);
    CHECK_EQ(segmentsFor(1, 5, false), kSegmentsDegree);
    CHECK_EQ(segmentsFor(4, 6, false), kSegmentsMinus);
    CHECK_EQ(segmentsFor(4, 7, false), 0);
    CHECK_EQ(segmentsFor(4, 3, false), 0);
    CHECK_EQ(segmentsFor(0xA, 0, false), kDigitSegments[0]);  // A–F digits wrap mod 10
}

TEST(printer_font_shape) {
    CHECK_EQ(kPC100CFont[0][3], 0x00);   // space
    CHECK_EQ(kPC100CFont[1][0], 0x0E);   // 0
    CHECK_EQ(kPC100CFont[63][6], 0x1F);  // Sigma
}

TEST(keyboard_layout_hit_test) {
    KeyHit hit{};
    const NRect& r = kKeyRects[8][4];  // '=' key
    CHECK(keyAt(r.x + r.w / 2, r.y + r.h / 2, hit));
    CHECK(hit.row == 8 && hit.col == 4);
    // Just above a key, inside the 35% vertical expansion.
    const NRect& k = kKeyRects[3][2];
    CHECK(keyAt(k.x + k.w / 2, k.y - k.h * 0.3, hit));
    CHECK(hit.row == 3 && hit.col == 2);
    CHECK(!keyAt(0.18, 0.0, hit));  // gap between columns, above row 0's expansion
}

TEST(model_info) {
    CHECK_EQ(info(Model::TI59).instructionHz, 14218.75);
    CHECK_EQ(info(Model::TI58C).instructionHz, 12000.0);
    CHECK(info(Model::TI59).hasCardReader && !info(Model::TI58).hasCardReader);
    CHECK(info(Model::TI58C).scanLoop.contains(0x0A2E));
    CHECK(!info(Model::TI59).idleAndKeyDetect.contains(0x0661));
}
