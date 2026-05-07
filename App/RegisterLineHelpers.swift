import Foundation

// MARK: - Register line encoding/decoding helpers

/// Convert 16 nibbles (register data) to 8 hex bytes in display format (swapped nibbles, reversed bytes).
/// Example: nibbles [1,7,2,0,6,3,0,0,0,0,0,0,0,0,0,0] → bytes [17,20,63,00,00,00,00,00]
func encodeRegisterLine(_ nibbles: [UInt8]) -> [UInt8] {
    guard nibbles.count == 16 else { return [] }
    let bytes = stride(from: 14, through: 0, by: -2).map { i in
        (nibbles[i] << 4) | nibbles[i + 1]
    }
    return Array(bytes)
}

/// Convert 8 hex bytes in display format back to 16 nibbles (register data).
/// Example: bytes [17,20,63,00,00,00,00,00] → nibbles [1,7,2,0,6,3,0,0,0,0,0,0,0,0,0,0]
func decodeRegisterLine(_ bytes: [UInt8]) -> [UInt8] {
    guard bytes.count == 8 else { return [] }
    let nibbles: [UInt8] = bytes.flatMap { b in [b >> 4, b & 0x0F] }
    let reversed = Array(nibbles.reversed())
    return (0..<8).map { i in
        (reversed[2*i] << 4) | reversed[2*i + 1]
    }
}
