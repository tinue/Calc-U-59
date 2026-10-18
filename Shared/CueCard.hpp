#pragma once
#include <array>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

// Cue card model: the strip above the keyboard naming the A–E / A′–E′ user
// keys. Parsed from CUECARD: sections (state files, card files, ti58c.mem,
// roms/solid-state/cuecards.txt) and encoded back. Field grammar and
// math-token table: reference/StateFileFormat.md § CUECARD. How each frontend
// draws it: reference/AppArchitecture.md § "Cue Card Rendering".

namespace cu59 {

/// Zero-width space marking a grid cell as merged into the preceding label's
/// span. Written as `\blank` on disk: the raw character does not survive a
/// round trip through a file.
inline constexpr const char* kCueCardInvisibleMarker = "​";

/// Expand math-notation shorthand (`\lambda` → λ, `^{2}` → ², `_{i}` → ᵢ, …).
std::string expandMathTokens(std::string_view input);

enum class TextAlign { Left, Center, Right };
enum class CueCardTemplate { CueCard, MagnetCard, SolidState };
enum class CardButtonStyle { None, Button };
enum class CueCardInkColor { Black, Pencil, Sharpie };

const char* toString(TextAlign a);          ///< "left" / "center" / "right"
const char* toString(CueCardTemplate t);    ///< "CueCard" / "MagnetCard" / "SolidStateCard"
const char* toString(CardButtonStyle s);    ///< "none" / "button"
const char* toString(CueCardInkColor c);    ///< "black" / "pencil" / "sharpie"

struct CueCardContent {
    CueCardTemplate template_ = CueCardTemplate::CueCard;
    std::string title;
    std::optional<int> bankLeft, bankRight;   ///< MagnetCard badges; nullopt = blank
    std::string id;                           ///< SolidState: right of the program-name row
    std::array<std::string, 10> labels{};     ///< [A′,B′,C′,D′,E′, A,B,C,D,E]
    std::string row1;
    TextAlign row1Align = TextAlign::Center;
    std::string row2;
    TextAlign row2Align = TextAlign::Left;
    std::string row2R;
    TextAlign row2RAlign = TextAlign::Left;
    CardButtonStyle style = CardButtonStyle::None;
    CueCardInkColor color = CueCardInkColor::Black;

    /// Built-in Master Library diagnostic card (shown when nothing else applies).
    static CueCardContent ml01Default();

    /// Apply one "Key: value" line. Unknown keys and values are ignored.
    void parseLine(std::string_view line);

    /// "Key: value" lines. With a template, a "Template:" line comes first, and
    /// "Banks:" is written only for MagnetCard.
    std::vector<std::string> encodeToLines(std::optional<CueCardTemplate> writeTemplate = std::nullopt) const;

    bool operator==(const CueCardContent& o) const;
    bool operator!=(const CueCardContent& o) const { return !(*this == o); }
};

} // namespace cu59
