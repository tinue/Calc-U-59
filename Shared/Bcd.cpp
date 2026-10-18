#include "Bcd.hpp"
#include "TextUtil.hpp"
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <string>

namespace cu59 {

namespace {
bool isPureInteger(std::string_view s) {
    if (!s.empty() && s[0] == '-') s.remove_prefix(1);
    if (s.empty()) return false;
    for (char c : s)
        if (c < '0' || c > '9') return false;
    return true;
}
} // namespace

Nibbles16 encodeBcd(std::string_view text) {
    std::string_view t = trim(text);
    if (!isPureInteger(t)) {
        auto v = parseDouble(t);
        return v ? encodeBcd(*v) : Nibbles16{};
    }
    bool negative = t[0] == '-';
    if (negative) t.remove_prefix(1);
    while (t.size() > 1 && t[0] == '0') t.remove_prefix(1);
    if (t == "0") return {};

    Nibbles16 n{};
    size_t exp = t.size() - 1;  // normalised so the first digit is the mantissa MSD
    n[0] = negative ? 2 : 0;
    n[1] = static_cast<uint8_t>(exp % 10);
    n[2] = static_cast<uint8_t>(exp / 10);
    // nibble[15..3]: 13 mantissa digits. Digits past the 13th significant
    // figure don't fit and are dropped — the same limit the hardware imposes.
    for (size_t offset = 0; offset < 13 && offset < t.size(); ++offset)
        n[15 - offset] = static_cast<uint8_t>(t[offset] - '0');
    return n;
}

Nibbles16 encodeBcd(double value) {
    Nibbles16 n{};
    if (!std::isfinite(value) || value == 0.0) return n;

    bool negative = value < 0.0;
    // %e always emits one leading digit in [1,9] and bumps the exponent itself
    // on rounding overflow (9.9999999999995e8 → 1.000000000000e9).
    char buf[64];
    std::snprintf(buf, sizeof buf, "%.12e", std::fabs(value));
    std::string digits;
    const char* p = buf;
    for (; *p && *p != 'e'; ++p)
        if (*p >= '0' && *p <= '9') digits += *p;
    int exp = *p == 'e' ? std::atoi(p + 1) : 0;

    n[0] = static_cast<uint8_t>((negative ? 2 : 0) | (exp < 0 ? 4 : 0));
    int expMag = std::abs(exp);
    n[1] = static_cast<uint8_t>(expMag % 10);
    n[2] = static_cast<uint8_t>(expMag / 10);
    for (size_t offset = 0; offset < 13 && offset < digits.size(); ++offset)
        n[15 - offset] = static_cast<uint8_t>(digits[offset] - '0');
    return n;
}

std::array<uint8_t, 8> encodeRegisterLine(const Nibbles16& nibbles) {
    std::array<uint8_t, 8> bytes{};
    for (size_t k = 0; k < 8; ++k) {
        size_t i = 14 - 2 * k;
        bytes[k] = static_cast<uint8_t>((nibbles[i] << 4) | nibbles[i + 1]);
    }
    return bytes;
}

std::string registerLineHex(const Nibbles16& nibbles) {
    std::string out;
    char buf[4];
    for (uint8_t b : encodeRegisterLine(nibbles)) {
        std::snprintf(buf, sizeof buf, "%02X", b);
        if (!out.empty()) out += ' ';
        out += buf;
    }
    return out;
}

std::optional<std::array<uint8_t, 8>> parseRegisterLineHex(std::string_view s) {
    auto tokens = splitWords(s);
    if (tokens.size() != 8) return std::nullopt;
    std::array<uint8_t, 8> out{};
    for (size_t i = 0; i < 8; ++i) {
        auto v = parseHex(tokens[i]);
        if (!v || *v > 0xFF) return std::nullopt;
        out[i] = static_cast<uint8_t>(*v);
    }
    return out;
}

std::string nibbleHex(const uint8_t* nibbles, bool msdFirst) {
    static const char* kHex = "0123456789abcdef";
    std::string s(16, '0');
    for (int i = 0; i < 16; ++i) s[static_cast<size_t>(msdFirst ? 15 - i : i)] = kHex[nibbles[i] & 0xF];
    return s;
}

Nibbles16 decodeRegisterLine(const std::array<uint8_t, 8>& bytes) {
    Nibbles16 n{};
    for (size_t i = 0; i < 8; ++i) {
        n[14 - 2 * i] = bytes[i] >> 4;
        n[15 - 2 * i] = bytes[i] & 0x0F;
    }
    return n;
}

} // namespace cu59
