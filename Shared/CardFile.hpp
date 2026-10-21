#pragma once
#include "CueCard.hpp"
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

// Magnetic card files: the 246-byte bank image the TI-59 card reader reads
// and writes, stored as text ("Calc-U-59 Card 1.0", written by the apps), or
// in two older binary layouts the apps still read. Text format:
//
//   Calc-U-59 Card 1.0          ← magic / version line (required, first line)
//   CUECARD:                    ← optional; same Key: value syntax as state files
//   HEADER:                     ← required; bank bytes 0–3 and 244–245
//       Partition: 1C           ← hex byte (0x1C = 959 steps, 0x13 = 239, …)
//       DataType: program       ← "program" | "data"
//       Bank: 1                 ← 1–4; page byte 0x10, 0x13, 0x16, 0x19
//       Protection: no          ← "yes" | "no"
//       Checksum: 02            ← hex byte, stored in bytes 244 and 245
//   DATA:                       ← required; 30 rows of 8 bytes (bank bytes 4–243)
//       R000: HH HH HH HH HH HH HH HH   ← register lines, bytes reversed
//                                         relative to ti58c.mem
//
// Comments (# …) are stripped; section keywords and HEADER keys are
// case-insensitive. A card's cue card is always a MagnetCard whose bank badge
// comes from Bank:.

namespace cu59 {

inline constexpr size_t kCardBankBytes = 246;

struct CardFileResult {
    std::vector<uint8_t> data;           ///< the 246-byte bank image
    std::optional<CueCardContent> cueCard;
};

/// Parse the text format; nullopt if it is malformed.
std::optional<CardFileResult> parseCardText(std::string_view text);

/// Encode a 246-byte bank image (and optional cue card) as text.
std::string encodeCardText(const std::vector<uint8_t>& bank246, const CueCardContent* cueCard);

/// Decode a card file's raw bytes in any supported layout:
///  - text ("Calc-U-59 Card " first line),
///  - "Calc-U-59-CRD" header + exactly 246 bytes,
///  - legacy headerless 246 bytes (one bank) or 984 bytes (four banks).
/// On failure `error` holds a user-facing message naming `fileName`.
struct CardDecodeResult {
    std::optional<CardFileResult> card;
    bool isText = false;
    std::string error;
};
CardDecodeResult decodeCardFile(const std::vector<uint8_t>& raw, const std::string& fileName);

/// A file the card pickers list: extension .u59 or .bin in any case; not a
/// hidden file (which also skips iCloud's ".name.u59.icloud" placeholders).
bool isCardFileName(std::string_view name);

/// The name a new card is saved under: ".U59" appended when it has no extension.
std::string withDefaultCardExtension(std::string name);

} // namespace cu59
