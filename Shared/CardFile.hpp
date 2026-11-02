#pragma once
#include "CueCard.hpp"
#include "StateFile.hpp"
#include <array>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

// Magnetic card files: the 246-byte bank images the TI-59 card reader reads
// and writes. New cards are text version 2.0: one file for a card's two sides,
// one cue card (reference/StateFileFormat.md § "Card files"). Version 1.0 text
// files and two older binary layouts hold one side and stay as they are.
//
//   Calc-U-59 Card 2.0
//   CUECARD:                    ← optional; no Banks: (the corners show each side's Bank:)
//   SIDE: 1                     ← 1 or 2; a side not written yet is left out
//       HEADER: … DATA: …       ← as in 1.0, every HEADER key required, 30 rows
//   SIDE: 2
//       HEADER: … DATA: …
//   END-CARD                    ← required: a version 1.0 reader fails on it, so an
//                                 older app can't read a card and write it back as 1.0
//
// Version 1.0:
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
// case-insensitive. A card's cue card is always a MagnetCard. In 1.0 its badges
// come from the cue card's Banks: line, never from the header's Bank:.

namespace cu59 {

inline constexpr size_t kCardBankBytes = 246;

struct CardFileResult {
    std::vector<uint8_t> data;           ///< the 246-byte bank image
    std::optional<CueCardContent> cueCard;
};

/// A card file as the controller holds it while the card is fitted.
struct CardDocument {
    int version = 2;                      ///< 2: two sides. 1: one side (text 1.0 and the binary layouts).
    std::optional<CueCardContent> cueCard;
    std::array<std::optional<std::vector<uint8_t>>, 2> sides;  ///< version 2: nullopt = not written yet
    std::vector<uint8_t> singleSide;      ///< version 1: the bytes as read (246, or 984 for the oldest layout)

    /// The bank number in a side's header (`side` 0 or 1); nullopt for a blank side or version 1.
    std::optional<int> sideBank(int side) const;
    /// The bytes a side (0 or 1) feeds into the reader, empty if blank. Version 1 has
    /// one side, used for either corner.
    std::vector<uint8_t> bank(int side) const;
    void setBank(int side, std::vector<uint8_t> bytes);
};

/// Parse the version 1.0 text format; nullopt if it is malformed or another version.
std::optional<CardFileResult> parseCardText(std::string_view text);

/// Encode a 246-byte bank image (and optional cue card) as version 1.0 text.
std::string encodeCardText(const std::vector<uint8_t>& bank246, const CueCardContent* cueCard);

/// Encode a card in its own version; a version 1 card stays version 1.
std::string encodeCardDocument(const CardDocument& doc);

/// The cue card of a fresh card: only a Title, the file name without extension.
CueCardContent freshCardCue(const std::string& fileName);

/// A preset's CARD: block as the 246-byte bank the ROM would write
/// (rom/TI59-ROM-Guide.md § "Magnetic cards"). The header's partition is
/// `programRegs` (program registers, a multiple of 10) unless the block sets one.
std::vector<uint8_t> buildCardBank(const CardDefinition& card, int programRegs);

/// Decode a card file's raw bytes in any supported layout:
///  - text ("Calc-U-59 Card " first line, version 1 or 2),
///  - "Calc-U-59-CRD" header + exactly 246 bytes,
///  - legacy headerless 246 bytes (one bank) or 984 bytes (four banks).
/// On failure `error` holds a user-facing message naming `fileName`.
struct CardDecodeResult {
    std::optional<CardDocument> card;
    std::string error;
};
CardDecodeResult decodeCardFile(const std::vector<uint8_t>& raw, const std::string& fileName);

/// A file the card pickers list: extension .u59 or .bin in any case; not a
/// hidden file (which also skips iCloud's ".name.u59.icloud" placeholders).
bool isCardFileName(std::string_view name);

/// The name a new card is saved under: ".U59" appended when it has no extension.
std::string withDefaultCardExtension(std::string name);

} // namespace cu59
