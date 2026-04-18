import Foundation

/// Maps TI-59 program step keycodes (0–99) to human-readable mnemonics.
/// Keycodes are laid out as row*10+col for the 9×5 key grid (rows 0–8 = keys 00–44),
/// plus additional two-character operations (45–99).
enum TI59KeyNames {
    static func mnemonic(for keycode: UInt8) -> String {
        table[Int(keycode)] ?? String(format: "?%02d", keycode)
    }

    /// Number of additional steps required after this opcode (for GTO 23, LBL 00, etc.)
    /// Returns 0 if the opcode doesn't consume additional steps.
    static func stepsAfter(for keycode: UInt8) -> Int {
        stepsAfterTable[Int(keycode)] ?? 0
    }

    private static let stepsAfterTable: [Int: Int] = [
        36: 1,   // Yˣ
        42: 1,   // STO
        43: 1,   // RCL
        44: 1,   // SUM
        48: 1,   // EXC
        49: 1,   // PRD
        58: 1,   // FIX
        61: 2,   // GTO
        67: 2,   // EQ
        71: 2,   // SBR
        77: 2,   // GE
        82: 1,   // HIR
        86: 1,   // STF
        87: 1,   // IFF
        97: 1,   // DSZ
    ]

    private static let table: [Int: String] = [
        // Basic digits (0–9)
         0: "0",        1: "1",        2: "2",       3: "3",        4: "4",
         5: "5",        6: "6",        7: "7",       8: "8",        9: "9",
        // Extended digits (10–19)
        10: "E'",      11: "A",       12: "B",      13: "C",       14: "D",
        15: "E",       16: "A'",      17: "B'",     18: "C'",      19: "D'",
        // Function row 1 (20–29)
        20: "CLR",     21: "2ND",     22: "INV",    23: "LNX",     24: "CE",
        25: "CLR",     26: "2ND",     27: "INV",    28: "LOG",     29: "CP",
        // Function row 2 (30–39)
        30: "TAN",     31: "LRN",     32: "X⇄T",    33: "X²",      34: "√X",
        35: "1/X",     36: "PGM",     37: "P/R",    38: "SIN",     39: "COS",
        // Function row 3 (40–49)
        40: "IND",     41: "SST",     42: "STO",    43: "RCL",     44: "SUM",
        45: "Yˣ",      46: "INS",     47: "CMS",    48: "EXC",     49: "PRD",
        // Function row 4 (50–59)
        50: "IxI",     51: "BST",     52: "EE",     53: "(",       54: ")",
        55: "÷",       56: "DEL",     57: "ENG",    58: "FIX",     59: "INT",
        // Function row 5 (60–69)
        60: "DEG",     61: "GTO",     62: "PG*",    63: "EX*",     64: "PD*",
        65: "|x|",     66: "PAU",     67: "EQ",     68: "NOP",     69: "OP",
        // Function row 6 (70–79)
        70: "RAD",     71: "SBR",     72: "ST*",    73: "RC*",     74: "SM*",
        75: "-",       76: "LBL",     77: "GE",     78: "∑+",      79: "x̄",
        // Function row 7 (80–89)
        80: "GRD",     81: "RST",     82: "HIR",    83: "GO*",     84: "OP*",
        85: "+",       86: "STF",     87: "IFF",    88: "DMS",     89: "π",
        // Function row 8 (90–99)
        90: "LST",     91: "R/S",     92: "RTN",    93: ".",       94: "+/-",
        95: "=",       96: "WRT",     97: "DSZ",    98: "ADV",     99: "PRT",
    ]
}
