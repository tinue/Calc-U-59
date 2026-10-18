#pragma once
#include <cctype>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

// Small string helpers mirroring the Foundation calls the Swift parsers were
// written against (components(separatedBy: .newlines), trimming .whitespaces,
// split(separator: " "), Int(_:radix:)), so the C++ ports keep their edge cases.

namespace cu59 {

/// Split on \n and \r (every newline character is a separator, as with
/// Foundation's .newlines — so CRLF yields an extra empty line, which callers skip).
inline std::vector<std::string_view> splitLines(std::string_view text) {
    std::vector<std::string_view> out;
    size_t start = 0;
    for (size_t i = 0; i < text.size(); ++i) {
        if (text[i] == '\n' || text[i] == '\r') {
            out.push_back(text.substr(start, i - start));
            start = i + 1;
        }
    }
    out.push_back(text.substr(start));
    return out;
}

/// Trim spaces and tabs (Foundation's .whitespaces), not newlines.
inline std::string_view trim(std::string_view s) {
    size_t b = 0, e = s.size();
    while (b < e && (s[b] == ' ' || s[b] == '\t')) ++b;
    while (e > b && (s[e - 1] == ' ' || s[e - 1] == '\t')) --e;
    return s.substr(b, e - b);
}

/// Split on single spaces, dropping empty pieces (Swift's split(separator: " ")).
inline std::vector<std::string_view> splitWords(std::string_view s) {
    std::vector<std::string_view> out;
    size_t start = 0;
    for (size_t i = 0; i <= s.size(); ++i) {
        if (i == s.size() || s[i] == ' ') {
            if (i > start) out.push_back(s.substr(start, i - start));
            start = i + 1;
        }
    }
    return out;
}

inline bool startsWith(std::string_view s, std::string_view prefix) {
    return s.size() >= prefix.size() && s.compare(0, prefix.size(), prefix) == 0;
}

inline std::string toUpper(std::string_view s) {
    std::string out(s);
    for (char& c : out) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    return out;
}

inline int hexDigit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/// Whole-string hex parse (an optional leading '+' is accepted, as Swift does).
inline std::optional<unsigned long> parseHex(std::string_view s) {
    if (!s.empty() && s[0] == '+') s.remove_prefix(1);
    if (s.empty() || s.size() > 8) return std::nullopt;
    unsigned long v = 0;
    for (char c : s) {
        int d = hexDigit(c);
        if (d < 0) return std::nullopt;
        v = v * 16 + static_cast<unsigned long>(d);
    }
    return v;
}

/// Whole-string decimal parse with optional sign (Swift's Int(_:)).
inline std::optional<long> parseDec(std::string_view s) {
    bool neg = false;
    if (!s.empty() && (s[0] == '+' || s[0] == '-')) { neg = s[0] == '-'; s.remove_prefix(1); }
    if (s.empty() || s.size() > 18) return std::nullopt;
    long v = 0;
    for (char c : s) {
        if (c < '0' || c > '9') return std::nullopt;
        v = v * 10 + (c - '0');
    }
    return neg ? -v : v;
}

} // namespace cu59
