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
/// Example: bytes [17,20,63,00,00,00,00,00] → nibbles [0,0,0,0,0,0,0,0,0,0,6,3,2,0,1,7]
/// (restores nibbles to original positions: byte[0]=0x17 unpacks to nibbles[14]=1, nibbles[15]=7, etc.)
func decodeRegisterLine(_ bytes: [UInt8]) -> [UInt8] {
    guard bytes.count == 8 else { return [] }
    var result = [UInt8](repeating: 0, count: 16)
    for i in 0..<8 {
        let hi = bytes[i] >> 4
        let lo = bytes[i] & 0x0F
        result[14 - 2*i] = hi
        result[15 - 2*i] = lo
    }
    return result
}
