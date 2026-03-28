import Foundation

enum ROMLoaderError: Error {
    case fileNotFound
    case parseError(String)
    case checksumMismatch(String)
    case wrongWordCount(Int)
}

struct ROMLoader {
    /// Decode a .hex file (plain lowercase hex bytes, 64 per line) into Data.
    static func decodeHex(_ text: String) throws -> Data {
        var bytes = [UInt8]()
        for line in text.components(separatedBy: .newlines) {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { continue }
            guard s.count % 2 == 0 else {
                throw ROMLoaderError.parseError("odd hex length on line: \(s)")
            }
            var i = s.startIndex
            while i < s.endIndex {
                let j = s.index(i, offsetBy: 2)
                guard let b = UInt8(s[i..<j], radix: 16) else {
                    throw ROMLoaderError.parseError("invalid hex byte: \(s[i..<j])")
                }
                bytes.append(b)
                i = j
            }
        }
        return Data(bytes)
    }

    /// Load rom-59.hex from the app bundle and return a [UInt16] array of 13-bit words.
    static func load(model: MachineModel) throws -> [UInt16] {
        guard let url = Bundle.main.url(forResource: "rom-59", withExtension: "hex") else {
            throw ROMLoaderError.fileNotFound
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let data = try decodeHex(text)
        return try wordsFromData(data, model: model)
    }

    /// Parse hex-decoded ROM data into a [UInt16] array of 13-bit words.
    static func wordsFromData(_ data: Data, model: MachineModel) throws -> [UInt16] {
        guard data.count % 2 == 0 else {
            throw ROMLoaderError.parseError("odd byte count: \(data.count)")
        }
        var words = [UInt16]()
        words.reserveCapacity(model.romWordCount)
        for i in stride(from: 0, to: data.count, by: 2) {
            words.append(((UInt16(data[i]) << 8) | UInt16(data[i + 1])) & 0x1FFF)
        }
        guard words.count == model.romWordCount else {
            throw ROMLoaderError.wrongWordCount(words.count)
        }
        if model == .ti59 {
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

    /// Load MasterLibrary.hex from the app bundle.
    static func loadLibrary() -> Data? {
        guard let url = Bundle.main.url(forResource: "MasterLibrary", withExtension: "hex"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let data = try? decodeHex(text) else { return nil }
        return data
    }
}
