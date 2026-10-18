#pragma once
#include <cstdint>
#include <optional>
#include <string>
#include <utility>
#include <vector>

// Where the running program's steps come from, and the solid-state module
// image's program table — what the live debugger needs to show the current
// step. See reference/AppArchitecture.md § "Solid-State Program Display".

namespace cu59 {

/// The PRG SOURCE flag (SCOM[0] nibble 3) decoded the way the firmware tests
/// it: the run loop (ROM 07C9) only asks "non-zero?", the step fetch (08B7,
/// 0B98) tests bit 0 (module) before bit 3 (constant-ROM keycode table).
/// There is no fast-mode flag value: fast mode is any non-zero flag that
/// selects neither table (2, 4, 6) — see rom/TI59-ROM-Guide.md § "Fast mode".
enum class ProgramSource {
    UserProgram,       ///< 0: RAM program or keyboard.
    SolidState,        ///< bit 0 set (1 official; 3, 5, 7, 9 fetch from the module too).
    /// 2 inside RTN_POP → LIB_RETURN (ROM 1193–1194, 14F9–1506, all variants):
    /// RTN has written the popped library level into SCOM[0], so nibbles 4–7
    /// hold the saved CROM return address (plain BCD, not a step number) until
    /// 1506 sets the flag back to 1. Lasts 16 instructions — visible only when
    /// frozen, since stepUntilNextKeycode stops at 1192.
    SolidStateReturn,
    FastMode,          ///< 2, 4 or 6 elsewhere: RAM program on the sub-program fast path.
    Rom,               ///< bit 3 set, bit 0 clear (8 official): constant-ROM keycode sub-program.
};

ProgramSource programSourceFrom(uint8_t flag, uint16_t romPC);

/// Debugger label, e.g. "Prg Source: ROM Program". Undocumented flag values
/// that decode like an official one (3, 5, 7, 9 → Solid State; A, C, E → ROM)
/// show the raw value; fast mode always does (it has no value of its own).
std::string programSourceLabel(ProgramSource source, uint8_t flag);

/// Steps are fetched from program RAM.
inline bool isUserProgram(ProgramSource s) { return s == ProgramSource::UserProgram || s == ProgramSource::FastMode; }

/// The step is the SCOM[0] PC (user programs and ROM). Solid State shows
/// steps through the CROM exec latch instead.
inline bool stepsFromScomPC(ProgramSource s) { return isUserProgram(s) || s == ProgramSource::Rom; }

/// A solid-state module image with its header parsed into per-program byte
/// ranges. Header layout (https://www.datamath.org/Chips/TMC0540.htm): byte 0
/// = program count (BCD), byte 1 = copy-protect flag, then one 2-byte BCD
/// start address per program, followed by a pointer one past the last keycode
/// of the final program.
struct ModuleImage {
    /// Module bytes decoded from BCD (0x76 → keycode 76).
    std::vector<uint8_t> keycodes;
    /// Program n (1-based) = programRanges[n-1], half-open [first, second).
    std::vector<std::pair<int, int>> programRanges;

    /// Parse an image. A malformed program table leaves programRanges empty
    /// and sets `error` (the keycodes are still decoded).
    static ModuleImage parse(const std::vector<uint8_t>& raw, std::string* error = nullptr);

    struct LibStep { int program; int step; int begin; int end; };

    /// Resolve the latched library execution address (TI59Machine::libExecPC)
    /// to its program: 1-based program number and program-relative step.
    std::optional<LibStep> libraryStep(uint16_t libExecPC) const;
};

} // namespace cu59
