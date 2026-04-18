import Foundation

enum ROMLoaderError: Error {
    case fileNotFound
    case parseError(String)
    case checksumMismatch(String)
    case wrongWordCount(Int)
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

    /// Load MasterLibrary.hex from the app bundle.
    static func loadLibrary() -> Data? {
        guard let url = Bundle.main.url(forResource: "MasterLibrary", withExtension: "hex"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        // Decode the hex bytes directly (no longer using decodeHex helper)
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
}
