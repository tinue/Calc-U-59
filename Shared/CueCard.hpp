#pragma once
#include <array>
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

// Cue card model: the strip above the keyboard naming the A–E / A′–E′ user
// keys. Parsed from CUECARD: sections (state files, card files, ti58c.mem,
// roms/solid-state/cuecards.txt) and encoded back. Field grammar and
// math-token table: reference/StateFileFormat.md § CUECARD. How each frontend
// draws it: reference/SharedArchitecture.md § "Cue Card Rendering".

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

// ── Rendering rules (the drawing itself is per frontend) ─────────────────────

/// A label and the grid columns (0–4) it covers. A label extends only into
/// following columns explicitly blanked with `\blank`; trailing empty columns
/// do not span.
struct LabelSpan { int startCol; int endCol; std::string label; };

/// Spans of one label row: 0 = A′–E′ (top), 1 = A–E (bottom).
std::vector<LabelSpan> labelSpans(const CueCardContent& card, int row);

/// Column dividers (between column i and i+1, i = 0–3) not inside a span.
std::vector<int> dividersBetween(const std::vector<LabelSpan>& spans);

/// Characters as the eye counts them (combining marks such as the overline
/// in x̄ don't count), for shrink-to-fit.
int displayLength(std::string_view text);

/// Per-template geometry, as fractions of the card (reference width 800 px
/// for the font sizes; scale by width / 800).
struct CueCardLayout {
    double titleFontSize, gridFontSize, bankFontSize;
    double titleYFraction, titleWidthFraction;
    double gridY0Fraction, gridY1Fraction;
    double xFractions[5];
    double cellWidthFraction;
    bool drawsDividers;   ///< SolidState: printed gold ink with dividers
    bool hasId;           ///< SolidState: id right of the title
    double referenceWidth;
};
const CueCardLayout& cueCardLayout(CueCardTemplate t);

/// Largest font (≤ the grid size) at which every span fits its cells, using
/// the 0.64 × size bold character width; never below 40 % of the grid size.
double cellFittingFontSize(const std::vector<LabelSpan>& spans, const CueCardLayout& layout, double cardWidth,
                           double scaledGridFontSize);

/// A text frame by its centre, as both renderers position cue-card text.
struct CueCardFrame { double cx, cy, width, height; };

/// Everything a renderer needs to place a card's text on a w × h card,
/// beyond the per-template CueCardLayout: scaled fonts, the grid's usable
/// width (charW = 0.64 × grid font; ½ charW in from the left cell edge, one
/// charW in from the right), the title frames, MagnetCard bank badges, the
/// Row2 / Row2R 70 / 30 split, divider and top-wash heights.
struct CueCardGeometry {
    double titleFontSize, gridFontSize, bankFontSize;
    double titleY, gridY0, gridY1;
    double gridLeft, gridRight, gridCenter, gridWidth;
    double titleWidth;                    ///< centred title (no id): its frame width, centred at w / 2
    CueCardFrame bankLeft, bankRight;     ///< MagnetCard bank numbers (clip to the frame)
    CueCardFrame row2Left, row2Right;     ///< Row2 + Row2R on one line (height 0: one text line)
    double dividerHeight;                 ///< SolidState column dividers, centred on the row
    double washHeight;                    ///< the dark wash over the top of the card
    double buttonPadX, buttonPadY;        ///< Style: button box around row text
};
CueCardGeometry cueCardGeometry(const CueCardContent& card, double width, double height);

/// x of the divider between grid columns i and i + 1.
double cueCardDividerX(const CueCardLayout& layout, int i, double width);
/// Frame of a label span centred on row y (height 0: one text line).
CueCardFrame cueCardSpanFrame(const CueCardLayout& layout, const LabelSpan& span, double y, double width);

/// Colours, packed 0xRRGGBB: the text ink (SolidState cards are printed gold;
/// the others follow PencilColor:), the SolidState dividers and the top wash
/// (drawn at kCueCardWashAlpha).
uint32_t cueCardInk(const CueCardContent& card);
inline constexpr uint32_t kCueCardDividerColor = 0xBC9D60;
inline constexpr uint32_t kCueCardWashColor = 0x1A0505;
inline constexpr double kCueCardWashAlpha = 0.4;

/// Which cue card shows: the active library program's card, else a generic
/// card titled with the module's metadata, else the user's card (file, preset,
/// ti58c.mem), else none.
std::optional<CueCardContent> resolveCueCard(int activeProgram, const std::map<int, CueCardContent>& moduleCards,
                                             const std::string& moduleTitle, const std::string& moduleID,
                                             const std::optional<CueCardContent>& userCard);

/// The library program number from SCOM[9] (digits 4 and 3), 0 = none.
inline int activeLibraryProgram(const uint8_t scom9[16]) { return scom9[4] * 10 + scom9[3]; }

} // namespace cu59
