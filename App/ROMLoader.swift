import Foundation

enum ROMLoaderError: Error {
    case fileNotFound
    case parseError(String)
    case checksumMismatch(String)
    case wrongWordCount(Int)
}

struct ModuleMetadata {
    var title: String = ""
    var sort: String = ""
    var id: String = ""
}

struct ROMLoader {
    /// Load the appropriate ROM files from the app bundle and return a [UInt16] array of 13-bit words.
    /// TI-58C uses CD2400, CD2401, TMC0573; TI-59 and TI-58 use TMC0582, TMC0583, TMC0571B.
    static func load(model: MachineModel) throws -> [UInt16] {
        let chipNames: [String] = model.hasConstantMemory
            ? ["CD2400", "CD2401", "TMC0573"]
            : ["TMC0582", "TMC0583", "TMC0571B"]
        var words = [UInt16]()
        words.reserveCapacity(model.romWordCount)
        for name in chipNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "txt") else {
                throw ROMLoaderError.fileNotFound
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            words += try parseRomTxt(text)
        }
        guard words.count == model.romWordCount else {
            throw ROMLoaderError.wrongWordCount(words.count)
        }
        if model.hasLargeMemory {
            // Sentinel values from the known-good TI-59 ROM image.
            // words[0]    = 0x0A01 — the first instruction at address 0 (CLR IDL)
            // words[6143] = 0x1987 — the last instruction; the value also encodes
            //               the chip revision year (1987) in its bit pattern.
            // A mismatch means the ROM file is corrupt, truncated, or wrong variant.
            if words[0] != 0x0A01 {
                throw ROMLoaderError.checksumMismatch(
                    "words[0] expected 0x0A01, got 0x\(String(words[0], radix: 16, uppercase: true))")
            }
            if words[6143] != 0x1987 {
                throw ROMLoaderError.checksumMismatch(
                    "words[6143] expected 0x1987, got 0x\(String(words[6143], radix: 16, uppercase: true))")
            }
        }
        return words
    }

    /// Parse a ROM .txt file (format: header block terminated by ---, then AAAA: WWWW WWWW ... lines).
    static func parseRomTxt(_ text: String) throws -> [UInt16] {
        var words = [UInt16]()
        var inData = false
        for line in text.components(separatedBy: .newlines) {
            let s = line.trimmingCharacters(in: .whitespaces)
            if !inData {
                if s.hasPrefix("---") {
                    inData = true
                }
                continue
            }
            guard !s.isEmpty else { continue }
            let parts = s.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let addrStr = String(parts[0]).trimmingCharacters(in: .whitespaces)
            // Verify the address part is exactly 4 hex digits
            guard addrStr.count == 4, UInt16(addrStr, radix: 16) != nil else { continue }
            let wordParts = parts[1].split(separator: " ")
            for wordStr in wordParts {
                guard let word = UInt16(wordStr, radix: 16) else {
                    throw ROMLoaderError.parseError("invalid hex word: \(wordStr)")
                }
                words.append(word & 0x1FFF)
            }
        }
        return words
    }

    /// Load constants from the appropriate CONST-K files based on model.
    /// Returns a flat Data buffer of 64 × 16 bytes (1024 bytes total).
    static func loadConstants(model: MachineModel) throws -> Data {
        let chipNames: [String] = model.hasConstantMemory
            ? ["CD2400-CONST-K", "CD2401-CONST-K"]
            : ["TMC0582-CONST-K", "TMC0583-CONST-K"]
        var constRows: [[UInt8]] = []
        for name in chipNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "txt") else {
                throw ROMLoaderError.fileNotFound
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            constRows += try parseConstantsTxt(text)
        }
        guard constRows.count == 64 else {
            throw ROMLoaderError.parseError("expected 64 constant rows, got \(constRows.count)")
        }
        var bytes = [UInt8]()
        for row in constRows {
            bytes.append(contentsOf: row)
        }
        return Data(bytes)
    }

    /// Parse a CONST-K .txt file and extract the NUMBER section (32 rows of 16 nibbles each).
    /// Nibbles are reversed to match hardware register order.
    static func parseConstantsTxt(_ text: String) throws -> [[UInt8]] {
        var rows: [[UInt8]] = []
        var inNumberSection = false
        for line in text.components(separatedBy: .newlines) {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.contains("CONSTANT ROM (NUMBER)") {
                inNumberSection = true
                continue
            }
            if s.hasPrefix("---") {
                if inNumberSection { break }
                continue
            }
            guard inNumberSection && !s.isEmpty else { continue }
            let parts = s.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let addrStr = String(parts[0]).trimmingCharacters(in: .whitespaces)
            // Verify the address part is 1-3 decimal digits (0-63 for 64 entries)
            guard !addrStr.isEmpty, Int(addrStr) != nil else { continue }
            let hexStr = String(parts[1]).trimmingCharacters(in: .whitespaces)
            guard hexStr.count == 16 else { continue }
            var nibbles = [UInt8]()
            for char in hexStr.reversed() {
                guard let nibble = UInt8(String(char), radix: 16) else {
                    throw ROMLoaderError.parseError("invalid hex nibble: \(char)")
                }
                nibbles.append(nibble)
            }
            rows.append(nibbles)
        }
        return rows
    }

    /// Decode a hex text file into Data.
    /// Each line contains pairs of hex digits (no spaces), which decode to bytes.
    /// Blank lines and comment lines are skipped.
    private static func decodeHexFile(_ text: String) -> Data? {
        var bytes = [UInt8]()
        for line in text.components(separatedBy: .newlines) {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { continue }
            var i = s.startIndex
            while i < s.endIndex {
                let j = s.index(i, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
                guard j > i, let b = UInt8(s[i..<j], radix: 16) else { break }
                bytes.append(b)
                i = j
            }
        }
        return bytes.isEmpty ? nil : Data(bytes)
    }

    /// Load library ROM for LE07 (the only supported solid-state module).
    /// Searches for LE07-*.hex in the bundle.
    static func loadModuleLibrary() -> Data? {
        let prefix = "LE07-"
        // Search the entire bundle for matching files (no subdirectory constraint)
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "hex",
                                          subdirectory: nil) else { return nil }
        guard let url = urls.first(where: { $0.lastPathComponent.hasPrefix(prefix) }),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return decodeHexFile(text)
    }

    /// Load per-program cue cards for ML01 from the bundle.
    /// Returns dict: program number → CueCardContent.
    /// Key 0 (module default) is included but not used in the new display logic.
    static func loadModuleCueCards() -> [Int: CueCardContent] {
        let (cards, _) = loadModuleCardsAndMetadata()
        return cards
    }

    /// Load per-program cue cards and module metadata for LE07.
    /// Returns (cards dict, metadata).
    static func loadModuleCardsAndMetadata() -> ([Int: CueCardContent], ModuleMetadata) {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "txt", subdirectory: nil),
              let url = urls.first(where: { $0.lastPathComponent.hasPrefix("LE07") && $0.lastPathComponent.contains("cuecards") }),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return ([:], ModuleMetadata()) }
        return parseCueCardFile(text)
    }

    /// Parse a cue cards text file.
    /// Format: MODULE-* metadata lines, then CUECARD: or CUECARD: N for program N.
    /// Returns (cards dict, metadata).
    private static func parseCueCardFile(_ text: String) -> ([Int: CueCardContent], ModuleMetadata) {
        var result: [Int: CueCardContent] = [:]
        var current: CueCardContent? = nil
        var currentKey: Int = 0
        var metadata = ModuleMetadata()

        for rawLine in text.components(separatedBy: .newlines) {
            // Strip comments and leading/trailing whitespace
            let line = rawLine.components(separatedBy: "#").first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard !line.isEmpty else { continue }

            let upper = line.uppercased()

            // Parse module-level metadata
            if upper.hasPrefix("MODULE-TITLE:") {
                let value = String(line.dropFirst("MODULE-TITLE:".count))
                    .trimmingCharacters(in: .whitespaces)
                metadata.title = value
                continue
            }
            if upper.hasPrefix("MODULE-SORT:") {
                let value = String(line.dropFirst("MODULE-SORT:".count))
                    .trimmingCharacters(in: .whitespaces)
                metadata.sort = value
                continue
            }
            if upper.hasPrefix("MODULE-ID:") {
                let value = String(line.dropFirst("MODULE-ID:".count))
                    .trimmingCharacters(in: .whitespaces)
                metadata.id = value
                continue
            }

            if upper.hasPrefix("CUECARD:") {
                // Save the previous card if one exists
                if let card = current {
                    result[currentKey] = card
                }
                // Parse the program number (if any) from the header
                let rest = String(line.dropFirst("CUECARD:".count))
                    .trimmingCharacters(in: .whitespaces)
                currentKey = Int(rest) ?? 0
                current = CueCardContent()
                continue
            }

            // Feed non-header lines to the current card
            current?.parseLine(line)
        }

        // Don't forget the last card
        if let card = current {
            result[currentKey] = card
        }
        return (result, metadata)
    }
}
