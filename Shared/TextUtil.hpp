#pragma once
#include <cctype>
#include <clocale>
#include <cmath>
#include <cstdlib>
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

/// Length of a UTF-8 encoded Unicode space separator (category Zs, which with
/// tab is Foundation's .whitespaces) at s[i], or 0.
inline size_t spaceAt(std::string_view s, size_t i) {
    auto u = [&](size_t k) { return k < s.size() ? static_cast<unsigned char>(s[k]) : 0u; };
    unsigned c = u(i);
    if (c == ' ' || c == '\t') return 1;
    if (c == 0xC2 && u(i + 1) == 0xA0) return 2;                         // U+00A0
    if (c == 0xE1 && u(i + 1) == 0x9A && u(i + 2) == 0x80) return 3;     // U+1680
    if (c == 0xE2 && u(i + 1) == 0x80 && (u(i + 2) <= 0x8A || u(i + 2) == 0xAF)) return 3;  // U+2000–200A, 202F
    if (c == 0xE2 && u(i + 1) == 0x81 && u(i + 2) == 0x9F) return 3;     // U+205F
    if (c == 0xE3 && u(i + 1) == 0x80 && u(i + 2) == 0x80) return 3;     // U+3000
    return 0;
}

/// Length of a space separator ending at s[e-1], or 0.
inline size_t spaceBefore(std::string_view s, size_t e) {
    for (size_t len = 1; len <= 3 && len <= e; ++len)
        if (spaceAt(s, e - len) == len) return len;
    return 0;
}

/// Trim Foundation's .whitespaces (tab and Unicode space separators), not newlines.
inline std::string_view trim(std::string_view s) {
    size_t b = 0, e = s.size();
    while (b < e) { size_t n = spaceAt(s, b); if (!n) break; b += n; }
    while (e > b) { size_t n = spaceBefore(s, e); if (!n) break; e -= n; }
    return s.substr(b, e - b);
}

/// Split on any .whitespaces character, dropping empty pieces
/// (components(separatedBy: .whitespaces).filter { !$0.isEmpty }).
inline std::vector<std::string_view> splitWhitespace(std::string_view s) {
    std::vector<std::string_view> out;
    size_t start = 0, i = 0;
    while (i < s.size()) {
        if (size_t n = spaceAt(s, i)) {
            if (i > start) out.push_back(s.substr(start, i - start));
            i += n;
            start = i;
        } else {
            ++i;
        }
    }
    if (start < s.size()) out.push_back(s.substr(start));
    return out;
}

/// Split on a separator, keeping empty pieces (components(separatedBy:)).
inline std::vector<std::string_view> splitOn(std::string_view s, std::string_view sep) {
    std::vector<std::string_view> out;
    size_t start = 0;
    for (;;) {
        size_t p = s.find(sep, start);
        if (p == std::string_view::npos) { out.push_back(s.substr(start)); return out; }
        out.push_back(s.substr(start, p - start));
        start = p + sep.size();
    }
}

/// Text before the first '#', trimmed (the state-file inline-comment rule).
inline std::string_view stripInlineComment(std::string_view line) {
    return trim(line.substr(0, line.find('#')));
}

inline std::string toLower(std::string_view s) {
    std::string out(s);
    for (char& c : out) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return out;
}

/// Swift's Double(String): the whole string must be a strtod-style literal —
/// decimal with optional exponent, inf/infinity/nan (any case, optional sign)
/// or a hex float — with no surrounding whitespace. Parsed independently of
/// the process locale (Qt sets LC_NUMERIC from the environment).
inline std::optional<double> parseDouble(std::string_view s) {
    if (s.empty() || std::isspace(static_cast<unsigned char>(s[0]))) return std::nullopt;
    std::string buf(s);
    if (buf.find(',') != std::string::npos) return std::nullopt;
    const char* dp = std::localeconv()->decimal_point;
    if (dp && dp[0] != '.' && dp[0] != 0) {
        for (char& c : buf) if (c == '.') c = dp[0];
    }
    char* end = nullptr;
    double v = std::strtod(buf.c_str(), &end);
    if (end != buf.c_str() + buf.size()) return std::nullopt;
    return v;
}

/// Whether the bytes are well-formed UTF-8 (Foundation's String(data:encoding: .utf8) != nil).
inline bool isValidUtf8(std::string_view s) {
    size_t i = 0;
    while (i < s.size()) {
        auto c = static_cast<unsigned char>(s[i]);
        size_t n = c < 0x80 ? 1 : (c >> 5) == 0x6 ? 2 : (c >> 4) == 0xE ? 3 : (c >> 3) == 0x1E ? 4 : 0;
        if (n == 0 || i + n > s.size()) return false;
        unsigned cp = n == 1 ? c : c & (0x7F >> n);
        for (size_t k = 1; k < n; ++k) {
            auto cc = static_cast<unsigned char>(s[i + k]);
            if ((cc & 0xC0) != 0x80) return false;
            cp = (cp << 6) | (cc & 0x3F);
        }
        // Reject overlong forms, surrogates and out-of-range code points.
        if ((n == 2 && cp < 0x80) || (n == 3 && cp < 0x800) || (n == 4 && (cp < 0x10000 || cp > 0x10FFFF)) ||
            (cp >= 0xD800 && cp <= 0xDFFF))
            return false;
        i += n;
    }
    return true;
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
