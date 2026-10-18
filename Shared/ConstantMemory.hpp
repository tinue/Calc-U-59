#pragma once
#include "CueCard.hpp"
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

// TI-58C constant memory file (ti58c.mem): the RAM that survives power-off,
// as text — an optional CUECARD: section, then a "── Registers (raw values) ──"
// line and one "Rnnn: HH HH HH HH HH HH HH HH" register line per non-zero
// register. Where the file lives is the frontend's choice (iCloud Documents in
// the Swift app, a local documents folder in the Qt app).

namespace cu59 {

inline constexpr size_t kConstantMemoryBytes = 120 * 16;  ///< TI59Machine::serialiseRAM size

/// Encode serialised RAM (120 registers × 16 nibbles) and the user's cue card.
std::string encodeConstantMemory(const std::vector<uint8_t>& ram, const CueCardContent* cueCard);

struct ConstantMemoryContents {
    std::vector<uint8_t> ram;               ///< kConstantMemoryBytes
    std::optional<CueCardContent> cueCard;
};

/// Decode the text; nullopt if any register line is malformed.
std::optional<ConstantMemoryContents> decodeConstantMemory(std::string_view text);

} // namespace cu59
