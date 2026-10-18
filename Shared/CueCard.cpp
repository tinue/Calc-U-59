#include "CueCard.hpp"
#include "TextUtil.hpp"
#include <utility>

namespace cu59 {

namespace {

// Applied in order, so longer tokens come before their prefixes.
const std::pair<const char*, const char*> kMathTokens[] = {
    {"\\lambda", "λ"},  // U+03BB
    {"\\Lambda", "Λ"},  // U+039B
    {"\\sigma", "σ"},  // U+03C3
    {"\\Sigma", "Σ"},  // U+03A3
    {"\\mu", "μ"},  // U+03BC
    {"\\theta", "θ"},  // U+03B8
    {"\\Theta", "Θ"},  // U+0398
    {"\\alpha", "α"},  // U+03B1
    {"\\beta", "β"},  // U+03B2
    {"\\epsilon", "ε"},  // U+03B5
    {"\\Epsilon", "Ε"},  // U+0395
    {"\\Delta", "Δ"},  // U+0394
    {"\\pi", "π"},  // U+03C0
    {"\\Pi", "Π"},  // U+03A0
    {"\\xbar", "x̄"},  // x + combining overline (U+0305)
    {"\\ybar", "ȳ"},  // y + combining overline
    {"\\zbar", "z̄"},  // z + combining overline
    {"\\nbar", "n̄"},  // n + combining overline
    {"\\mbar", "m̄"},  // m + combining overline
    {"\\leftrightarrows", "⇄"},  // U+21C4 (right arrow over left arrow)
    {"\\leftrightarrow", "↔"},  // U+2194 (bidirectional)
    {"\\updownarrow", "↕"},  // U+2195
    {"\\leftarrow", "←"},  // U+2190
    {"\\to", "→"},  // U+2192
    {"\\sqrt", "√"},  // U+221A (square root)
    {"\\cbrt", "∛"},  // U+221B (cube root)
    {"\\fourthroot", "∜"},  // U+221C (fourth root)
    {"\\triangle", "△"},  // U+25B3 (triangle)
    {"\\angle", "∠"},  // U+2220 (angle)
    {"\\inf", "∞"},  // U+221E
    {"\\sum", "∑"},  // U+2211
    {"\\product", "∏"},  // U+220F
    {"\\integral", "∫"},  // U+222B
    {"\\approx", "≈"},  // U+2248
    {"\\neq", "≠"},  // U+2260
    {"\\leq", "≤"},  // U+2264
    {"\\geq", "≥"},  // U+2265
    {"\\blank", kCueCardInvisibleMarker},  // Zero-width space for invisible columns
    {"^{-1}", "⁻¹"},  // U+207B + U+00B9
    {"^{-2}", "⁻²"},  // U+207B + U+00B2
    {"^{-3}", "⁻³"},  // U+207B + U+00B3
    {"^{-}", "⁻"},  // U+207B
    {"^{+}", "⁺"},  // U+207A
    {"^{*}", "ˣ"},  // U+02E3
    {"^{n}", "ⁿ"},  // U+207F
    {"^{T}", "ᵀ"},  // U+1D40 (transpose)
    {"^{x}", "ˣ"},  // U+02E3
    {"^{X}", "ˣ"},  // U+02E3 (capital X → superscript x)
    {"^{y}", "ʸ"},  // U+02B8
    {"^{Y}", "ʸ"},  // U+02B8 (capital Y → superscript y)
    {"^{z}", "ᶻ"},  // U+1D7A
    {"^{Z}", "ᶻ"},  // U+1D7A (capital Z → superscript z)
    {"^{0}", "⁰"},  // U+2070
    {"^{1}", "¹"},  // U+00B9
    {"^{2}", "²"},  // U+00B2
    {"^{3}", "³"},  // U+00B3
    {"^{4}", "⁴"},  // U+2074
    {"^{5}", "⁵"},  // U+2075
    {"^{6}", "⁶"},  // U+2076
    {"^{7}", "⁷"},  // U+2077
    {"^{8}", "⁸"},  // U+2078
    {"^{9}", "⁹"},  // U+2079
    {"_{-1}", "₋₁"},  // U+2215 + U+2081
    {"_{-}", "₋"},  // U+2215
    {"_{+}", "₊"},  // U+208A
    {"_{0}", "₀"},  // U+2080
    {"_{1}", "₁"},  // U+2081
    {"_{2}", "₂"},  // U+2082
    {"_{3}", "₃"},  // U+2083
    {"_{4}", "₄"},  // U+2084
    {"_{5}", "₅"},  // U+2085
    {"_{6}", "₆"},  // U+2086
    {"_{7}", "₇"},  // U+2087
    {"_{8}", "₈"},  // U+2088
    {"_{9}", "₉"},  // U+2089
    {"_{i}", "ᵢ"},  // U+1D62
    {"_{j}", "ⱼ"},  // U+1D6A
    {"_{a}", "ₐ"},  // U+2090
    {"_{e}", "ₑ"},  // U+2091
    {"_{o}", "ₒ"},  // U+2092
    {"_{x}", "ₓ"},  // U+2093
    {"_{X}", "ₓ"},  // U+2093 (uppercase X → subscript x)
    {"_{y}", "ᵧ"},  // U+1D67 (subscript y)
    {"_{Y}", "ᵧ"},  // U+1D67 (uppercase Y → subscript y)
    {"_{n}", "ₙ"},  // U+2099
    {"_{m}", "ₘ"},  // U+2098
    {"_{k}", "ₖ"},  // U+2096
};

void replaceAll(std::string& s, std::string_view from, std::string_view to) {
    if (from.empty()) return;
    size_t pos = 0;
    while ((pos = s.find(from, pos)) != std::string::npos) {
        s.replace(pos, from.size(), to);
        pos += to.size();
    }
}

TextAlign parseAlignment(std::string_view value) {
    std::string v = toLower(value);
    if (v == "right") return TextAlign::Right;
    if (v == "center") return TextAlign::Center;
    return TextAlign::Left;
}

std::optional<int> parseInt(std::string_view s) {
    auto v = parseDec(trim(s));
    if (!v) return std::nullopt;
    return static_cast<int>(*v);
}

/// Label key → index: A′–E′ → 0–4, A–E → 5–9 (both apostrophe styles).
int labelIndex(const std::string& key) {
    static const std::pair<const char*, int> kMap[] = {
        {"a", 5}, {"b", 6}, {"c", 7}, {"d", 8}, {"e", 9},
        {"a'", 0}, {"a\u2032", 0}, {"b'", 1}, {"b\u2032", 1}, {"c'", 2}, {"c\u2032", 2},
        {"d'", 3}, {"d\u2032", 3}, {"e'", 4}, {"e\u2032", 4},
    };
    for (const auto& [k, i] : kMap)
        if (key == k) return i;
    return -1;
}

} // namespace

std::string expandMathTokens(std::string_view input) {
    std::string result(input);
    for (const auto& [token, unicode] : kMathTokens) replaceAll(result, token, unicode);
    return result;
}

const char* toString(TextAlign a) {
    switch (a) {
    case TextAlign::Left: return "left";
    case TextAlign::Center: return "center";
    case TextAlign::Right: return "right";
    }
    return "left";
}

const char* toString(CueCardTemplate t) {
    switch (t) {
    case CueCardTemplate::CueCard: return "CueCard";
    case CueCardTemplate::MagnetCard: return "MagnetCard";
    case CueCardTemplate::SolidState: return "SolidStateCard";
    }
    return "CueCard";
}

const char* toString(CardButtonStyle s) { return s == CardButtonStyle::Button ? "button" : "none"; }

const char* toString(CueCardInkColor c) {
    switch (c) {
    case CueCardInkColor::Black: return "black";
    case CueCardInkColor::Pencil: return "pencil";
    case CueCardInkColor::Sharpie: return "sharpie";
    }
    return "black";
}

CueCardContent CueCardContent::ml01Default() {
    CueCardContent c;
    c.template_ = CueCardTemplate::SolidState;
    c.title = "MASTER LIBRARY DIAGNOSTIC";
    c.id = "ML-01";
    c.row1 = "DIAGNOSTIC: SBR =";
    c.row1Align = TextAlign::Center;
    c.row2 = "L.R. INIT: SBR CLR";
    c.row2Align = TextAlign::Left;
    c.row2R = "PRINT: mm STO 00";
    c.row2RAlign = TextAlign::Right;
    return c;
}

void CueCardContent::parseLine(std::string_view line) {
    size_t colon = line.find(':');
    if (colon == std::string_view::npos) return;
    std::string key = toLower(trim(line.substr(0, colon)));
    std::string_view value = trim(line.substr(colon + 1));

    if (key == "template") {
        for (auto t : {CueCardTemplate::CueCard, CueCardTemplate::MagnetCard, CueCardTemplate::SolidState})
            if (value == toString(t)) template_ = t;
    } else if (key == "title") {
        title = expandMathTokens(value);
    } else if (key == "banks") {
        auto parts = splitOn(value, ",");
        bankLeft = parts.size() > 0 ? parseInt(parts[0]) : std::nullopt;
        bankRight = parts.size() > 1 ? parseInt(parts[1]) : std::nullopt;
    } else if (key == "id") {
        id = expandMathTokens(value);
    } else if (key == "idalign") {
        // Deprecated: the id is always rendered right-aligned.
    } else if (key == "row1") {
        row1 = expandMathTokens(value);
    } else if (key == "row2") {
        row2 = expandMathTokens(value);
    } else if (key == "row2r") {
        row2R = expandMathTokens(value);
    } else if (key == "style") {
        std::string v = toLower(value);
        if (v == "none") style = CardButtonStyle::None;
        else if (v == "button") style = CardButtonStyle::Button;
    } else if (key == "row1align") {
        row1Align = parseAlignment(value);
    } else if (key == "row2align") {
        row2Align = parseAlignment(value);
    } else if (key == "row2ralign") {
        row2RAlign = parseAlignment(value);
    } else if (key == "pencilcolor") {
        std::string v = toLower(value);
        for (auto c : {CueCardInkColor::Black, CueCardInkColor::Pencil, CueCardInkColor::Sharpie})
            if (v == toString(c)) color = c;
    } else if (int idx = labelIndex(key); idx >= 0) {
        labels[static_cast<size_t>(idx)] = expandMathTokens(value);
    }
}

std::vector<std::string> CueCardContent::encodeToLines(std::optional<CueCardTemplate> writeTemplate) const {
    std::vector<std::string> lines;
    auto add = [&](const char* key, const std::string& v) { lines.push_back(std::string(key) + ": " + v); };

    if (writeTemplate) add("Template", toString(*writeTemplate));
    if (!title.empty()) add("Title", title);
    // Banks only for the MagnetCard template.
    if (writeTemplate == CueCardTemplate::MagnetCard && (bankLeft || bankRight)) {
        add("Banks", (bankLeft ? std::to_string(*bankLeft) : "") + ", " +
                     (bankRight ? std::to_string(*bankRight) : ""));
    }
    if (!id.empty()) add("ID", id);

    // The invisible-column marker round-trips as literal "\blank" text.
    auto encoded = [](const std::string& l) { return l == kCueCardInvisibleMarker ? std::string("\\blank") : l; };
    static const char* const kPrimeKeys[] = {"A'", "B'", "C'", "D'", "E'"};
    static const char* const kPlainKeys[] = {"A", "B", "C", "D", "E"};
    for (size_t i = 0; i < 5; ++i)
        if (!labels[i].empty()) add(kPrimeKeys[i], encoded(labels[i]));
    for (size_t i = 0; i < 5; ++i)
        if (!labels[i + 5].empty()) add(kPlainKeys[i], encoded(labels[i + 5]));

    if (!row1.empty()) add("Row1", row1);
    if (row1Align != TextAlign::Center) add("Row1Align", toString(row1Align));
    if (!row2.empty()) add("Row2", row2);
    if (row2Align != TextAlign::Left) add("Row2Align", toString(row2Align));
    if (!row2R.empty()) add("Row2R", row2R);
    if (row2RAlign != TextAlign::Left) add("Row2RAlign", toString(row2RAlign));
    if (style != CardButtonStyle::None) add("Style", toString(style));
    if (color != CueCardInkColor::Black) add("PencilColor", toString(color));
    return lines;
}

bool CueCardContent::operator==(const CueCardContent& o) const {
    return template_ == o.template_ && title == o.title && bankLeft == o.bankLeft &&
           bankRight == o.bankRight && id == o.id && labels == o.labels && row1 == o.row1 &&
           row1Align == o.row1Align && row2 == o.row2 && row2Align == o.row2Align &&
           row2R == o.row2R && row2RAlign == o.row2RAlign && style == o.style && color == o.color;
}

} // namespace cu59
