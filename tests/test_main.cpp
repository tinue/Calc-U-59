#include "TestHarness.hpp"
#include <cstring>

// Runs every registered TEST. An optional argument filters by substring of
// the test name. Run from the repository root (CTest does) so tests can read
// roms/ and examples/.

int main(int argc, char** argv) {
    const char* filter = argc > 1 ? argv[1] : nullptr;
    int ran = 0;
    for (auto& c : testharness::registry()) {
        if (filter && !std::strstr(c.name, filter)) continue;
        int before = testharness::failCount();
        c.fn();
        ++ran;
        if (testharness::failCount() != before) std::fprintf(stderr, "  in %s\n", c.name);
    }
    std::printf("%d tests, %d checks passed, %d failed\n", ran, testharness::passCount(), testharness::failCount());
    return testharness::failCount() == 0 ? 0 : 1;
}
