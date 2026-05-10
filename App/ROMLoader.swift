import Foundation

enum ROMLoaderError: Error {
    case fileNotFound
    case parseError(String)
    case checksumMismatch(String)
    case wrongWordCount(Int)
}

// Module ID to load (set to a constant for easy testing; can be changed quickly)
private let moduleIDToLoad = "LE"

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

    /// Parse a solid-state module TMC*.txt file (decimal address + BCD byte values).
    /// Format: header (5 lines), dashes separator, "ADDR: BCD DATA" column header, then lines like "0000: 21 00 ... (20 bytes)"
    /// Each value is a 2-digit BCD number (00-99), stored as the hex representation (0x00-0x99).
    static func parseTMCTxt(_ text: String) -> Data? {
        var bytes = [UInt8](repeating: 0, count: 5000)
        var maxAddr = 0
        var pastHeader = false

        for line in text.components(separatedBy: .newlines) {
            let s = line.trimmingCharacters(in: .whitespaces)
            if !pastHeader {
                if s.hasPrefix("ADDR:") && s.contains("DATA") {
                    pastHeader = true
                }
                continue
            }
            guard !s.isEmpty else { continue }

            let parts = s.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            guard let addr = Int(parts[0].trimmingCharacters(in: .whitespaces)) else { continue }

            // Parse BCD values: "21" means 0x21, not decimal 21
            let values = parts[1].split(separator: " ").compactMap { UInt8(String($0), radix: 16) }
            for (i, v) in values.enumerated() {
                let idx = addr + i
                if idx < 5000 {
                    bytes[idx] = v
                    maxAddr = max(maxAddr, idx + 1)
                }
            }
        }

        guard maxAddr > 0 else { return nil }
        return Data(bytes[0..<maxAddr])
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

/// Load library ROM for the solid-state module specified by moduleIDToLoad.
    /// Gets the ROM filename from cuecards.txt and loads the corresponding TMC*.txt file.
    static func loadModuleLibrary() -> Data? {
        guard let filename = romFilename(forModuleID: moduleIDToLoad) else { return nil }
        let name = (filename as NSString).deletingPathExtension
        let ext  = (filename as NSString).pathExtension
        guard let url  = Bundle.main.url(forResource: name, withExtension: ext),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parseTMCTxt(text)
    }

    /// Get the ROM filename for a given module ID from cuecards.txt.
    private static func romFilename(forModuleID id: String) -> String? {
        guard let url = Bundle.main.url(forResource: "cuecards", withExtension: "txt") else { return nil }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        var currentModuleID: String? = nil
        for line in text.components(separatedBy: .newlines) {
            let s = line.components(separatedBy: "#").first?.trimmingCharacters(in: .whitespaces) ?? ""
            if s.uppercased().hasPrefix("MODULE-ID:") {
                currentModuleID = String(s.dropFirst("MODULE-ID:".count)).trimmingCharacters(in: .whitespaces)
            } else if s.uppercased().hasPrefix("MODULE-ROM:"), currentModuleID == id {
                return String(s.dropFirst("MODULE-ROM:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Load per-program cue cards for ML01 from the bundle.
    /// Returns dict: program number → CueCardContent.
    /// Key 0 (module default) is included but not used in the new display logic.
    static func loadModuleCueCards() -> [Int: CueCardContent] {
        let (cards, _) = loadModuleCardsAndMetadata()
        return cards
    }

    /// Load per-program cue cards and module metadata from cuecards.txt.
    /// Returns (cards dict, metadata) for the module specified by moduleIDToLoad.
    static func loadModuleCardsAndMetadata() -> ([Int: CueCardContent], ModuleMetadata) {
        guard let url = Bundle.main.url(forResource: "cuecards", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return ([:], ModuleMetadata()) }
        return parseCueCardFile(text, moduleID: moduleIDToLoad)
    }

    /// Parse cuecards.txt and extract cards and metadata for a specific module ID.
    /// MODULE-ID is now the first line of each module section; this enables a simple state machine with no buffering.
    private static func parseCueCardFile(_ text: String, moduleID: String) -> ([Int: CueCardContent], ModuleMetadata) {
        var result: [Int: CueCardContent] = [:]
        var current: CueCardContent? = nil
        var currentKey: Int = 0
        var metadata = ModuleMetadata()
        var inTargetModule = false

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.components(separatedBy: "#").first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard !line.isEmpty else { continue }

            let upper = line.uppercased()

            // MODULE-ID signals the start of a new module section.
            // If we were already in the target module, flush the last card and stop.
            if upper.hasPrefix("MODULE-ID:") {
                if inTargetModule {
                    if let card = current { result[currentKey] = card }
                    break  // Done with target module
                }
                let id = String(line.dropFirst("MODULE-ID:".count)).trimmingCharacters(in: .whitespaces)
                inTargetModule = (id == moduleID)
                metadata.id = id
                continue
            }

            guard inTargetModule else { continue }

            // Parse module metadata (only when in target module)
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
            if upper.hasPrefix("MODULE-ROM:") {
                // Skip; only used by romFilename(forModuleID:) lookup
                continue
            }

            if upper.hasPrefix("CUECARD:") {
                if let card = current { result[currentKey] = card }
                let rest = String(line.dropFirst("CUECARD:".count))
                    .trimmingCharacters(in: .whitespaces)
                currentKey = Int(rest) ?? 0
                current = CueCardContent()
                continue
            }

            current?.parseLine(line)
        }

        if inTargetModule, let card = current {
            result[currentKey] = card
        }
        return (result, metadata)
    }
}
