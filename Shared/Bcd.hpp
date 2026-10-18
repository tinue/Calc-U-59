#pragma once
#include <array>
#include <cstdint>
#include <string>
#include <string_view>

// TI-59 register BCD encoding and the hex "register line" form used by card
// files and ti58c.mem.
//
// Register layout (the TMC0598 RAM serial-BCD convention):
//   nibble[0]     = sign flags: bit 1 = mantissa negative, bit 2 = exponent negative (0/2/4/6)
//   nibble[1]     = exponent units digit (magnitude, not 10's complement)
//   nibble[2]     = exponent tens digit
//   nibble[3]     = mantissa LSD … nibble[15] = mantissa MSD (13 digits)
// The mantissa is normalised so its first digit is non-zero.

namespace cu59 {

using Nibbles16 = std::array<uint8_t, 16>;

/// Encode a REGISTERS: literal exactly as written. A pure decimal integer
/// (optional leading '-', digits only) is built digit by digit from the text,
/// never through a double: the register holds 13 significant digits and a
/// keyed-in integer never takes a binary detour on the real hardware. Any
/// other literal goes through encodeBcd(double). Unparseable text → zero.
Nibbles16 encodeBcd(std::string_view text);

/// Encode a double: 13 correctly rounded significant digits via %.12e (no
/// iterative digit extraction, which accumulates rounding error).
/// 0, NaN and ±Inf encode as all-zero.
Nibbles16 encodeBcd(double value);

/// 16 nibbles → 8 bytes in display order (nibble pairs swapped, bytes reversed):
/// [1,7,2,0,6,3,0…] → 17 20 63 00 00 00 00 00.
std::array<uint8_t, 8> encodeRegisterLine(const Nibbles16& nibbles);

/// Inverse of encodeRegisterLine.
Nibbles16 decodeRegisterLine(const std::array<uint8_t, 8>& bytes);

/// encodeRegisterLine as "17 20 63 00 00 00 00 00" (ti58c.mem and the RAM dump).
std::string registerLineHex(const Nibbles16& nibbles);

} // namespace cu59
