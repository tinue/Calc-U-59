#pragma once
#include "MachineModelInfo.hpp"
#include <cstdint>
#include <functional>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

// Parsers for the plaintext ROM dumps in roms/ (Datamath museum format:
// header block, a "---" separator line, then address-prefixed data rows).
// File access is the frontend's job: it passes a ResourceReader that returns
// a file's text by bare file name (Swift: Bundle.main; Qt: the :/roms/ qrc).

namespace cu59 {

struct RomError : std::runtime_error {
    using std::runtime_error::runtime_error;
};

/// Returns the full text of a bundled resource by bare file name (e.g.
/// "TMC0582.txt"), or nullopt if it doesn't exist.
using ResourceReader = std::function<std::optional<std::string>(const std::string& fileName)>;

/// A ResourceReader over plain directories, searched in order — the layout of
/// roms/ (calculator/, then solid-state/) for tests and headless tools.
ResourceReader directoryReader(std::vector<std::string> dirs);

/// Parse a ROM .txt file: "AAAA: WWWW WWWW ..." rows after the separator.
/// Rows without a 4-hex-digit address are skipped; words are masked to 13 bits.
/// Throws RomError on an invalid hex word.
std::vector<uint16_t> parseRomTxt(std::string_view text);

/// Parse a CONST-K .txt file: the 16-nibble rows of the "CONSTANT ROM (NUMBER)"
/// section, nibbles reversed into hardware register order.
std::vector<std::vector<uint8_t>> parseConstantsTxt(std::string_view text);

/// Parse a solid-state module TMC*.txt file: "dddd: bb bb ..." rows of BCD
/// bytes ("21" is 0x21). Returns bytes up to the highest address written
/// (max 5000), or nullopt if no data rows were found.
std::optional<std::vector<uint8_t>> parseModuleTxt(std::string_view text);

/// Load and concatenate the model's three ROM chips (6144 words). On the TI-59
/// the image is checked against the known-good sentinels: word 0 = 0x0A01
/// (CLR IDL) and word 6143 = 0x1987. Throws RomError on any failure.
std::vector<uint16_t> loadRom(Model model, const ResourceReader& read);

/// Load the model's 64 constant rows as a flat 64×16-byte buffer.
std::vector<uint8_t> loadConstants(Model model, const ResourceReader& read);

/// Load a solid-state module image by ROM file name (cuecards.txt MODULE-ROM).
std::optional<std::vector<uint8_t>> loadModule(const std::string& romFile, const ResourceReader& read);

} // namespace cu59
