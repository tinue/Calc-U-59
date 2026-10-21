#pragma once
#include "../Core/TI59Machine.hpp"
#include <cstdint>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

// Debug ASM overlay: hand-assembled TMC0501 code loaded at 0x1800–0x1FFF and
// entered from a keycode boundary (examples/assembly/*.asm). The file's
// opcode words follow a "HEX:" line.

namespace cu59 {

struct AsmParseError : std::runtime_error {
    using std::runtime_error::runtime_error;
};

/// Opcode words after the "HEX:" line: tokens "0x…" or runs of 4+ hex digits,
/// split into 4-digit words masked to 13 bits. At most 2048 words. Throws
/// AsmParseError with a user-facing message.
std::vector<uint16_t> parseAsmWords(std::string_view text);

struct AsmRunResult {
    bool loaded = false;    ///< false: the words exceed the overlay range
    bool entered = false;   ///< execution reached the entry point
    uint32_t steps = 0;
};

/// Park the CPU at a keycode boundary (so the digit counter is mid-cycle),
/// load the overlay and enter it at 0x1800. Run on the emulation thread with
/// the run loop stopped.
AsmRunResult runAsmOverlay(TI59Machine& m, const std::vector<uint16_t>& words);

} // namespace cu59
