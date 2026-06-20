import Foundation

/// Maps TI-59 program step keycodes (0–99) to human-readable mnemonics.
/// Keycodes are laid out as row*10+col for the 9×5 key grid (rows 0–8 = keys 00–44),
/// plus additional two-character operations (45–99).
enum TI59KeyNames {
    static func mnemonic(for keycode: UInt8) -> String {
        table[Int(keycode)] ?? String(format: "?%02d", keycode)
    }

    /// Number of additional steps required after this opcode (fixed-argument
    /// opcodes only: STO 12, FIX 2, OP 06, …). Branch instructions (GTO, EQ,
    /// SBR, GE, IFF, DSZ) have variable-length destinations and are handled
    /// by `argumentSteps(in:)`.
    static func stepsAfter(for keycode: UInt8) -> Int {
        stepsAfterTable[Int(keycode)] ?? 0
    }

    /// Indices of steps that are numeric arguments of a preceding opcode
    /// (rendered as "NN" instead of a mnemonic). Walks the program
    /// sequentially so operand bytes are never misread as opcodes.
    ///
    /// Branch destinations follow the TI-59 keycode grammar: a first operand
    /// byte of 00–09 is a 2-step absolute address (SBR 01 23), 40 is IND
    /// followed by a register number (SBR IND 25), anything else is a 1-step
    /// label rendered as its key mnemonic (SBR CE). Label and IND steps are
    /// not marked, so they keep their mnemonic rendering.
    static func argumentSteps(in steps: [UInt8]) -> Set<Int> {
        var args = Set<Int>()
        var i = 0
        var previousWasInv = false
        while i < steps.count {
            let kc = steps[i]
            i += 1
            switch kc {
            case 61, 67, 71, 77:                        // GTO, EQ, SBR, GE
                if kc == 71 && previousWasInv { break } // INV SBR = RTN, no operand
                i = consumeDestination(steps, from: i, into: &args)
            case 87, 97:                                // IFF, DSZ: flag/register, then destination
                i = consumeNumber(steps, from: i, into: &args)
                i = consumeDestination(steps, from: i, into: &args)
            default:
                let n = stepsAfter(for: kc)
                for j in 0..<n where i + j < steps.count { args.insert(i + j) }
                i += n
            }
            previousWasInv = (kc == 22 || kc == 27)
        }
        return args
    }

    /// Consume a flag/register-number operand: a single digit, or IND + register.
    private static func consumeNumber(_ steps: [UInt8], from start: Int,
                                      into args: inout Set<Int>) -> Int {
        guard start < steps.count else { return start }
        if steps[start] == 40 {                  // IND → register number follows
            if start + 1 < steps.count { args.insert(start + 1) }
            return start + 2
        }
        args.insert(start)
        return start + 1
    }

    /// Consume a branch destination: 2-step address, IND + register, or 1-step label.
    private static func consumeDestination(_ steps: [UInt8], from start: Int,
                                           into args: inout Set<Int>) -> Int {
        guard start < steps.count else { return start }
        switch steps[start] {
        case 0...9:                              // leading zero → 2-step absolute address
            args.insert(start)
            if start + 1 < steps.count { args.insert(start + 1) }
            return start + 2
        case 40:                                 // IND → register number follows
            if start + 1 < steps.count { args.insert(start + 1) }
            return start + 2
        default:                                 // label → shown as mnemonic
            return start + 1
        }
    }

    private static let stepsAfterTable: [Int: Int] = [
        36: 1,   // PGM
        42: 1,   // STO
        43: 1,   // RCL
        44: 1,   // SUM
        48: 1,   // EXC
        49: 1,   // PRD
        58: 1,   // FIX
        62: 1,   // PG* (Pgm Ind)
        63: 1,   // EX* (Exc Ind)
        64: 1,   // PD* (Prd Ind)
        69: 1,   // OP
        72: 1,   // ST* (STO Ind)
        73: 1,   // RC* (RCL Ind)
        74: 1,   // SM* (SUM Ind)
        82: 1,   // HIR
        83: 1,   // GO* (GTO Ind)
        84: 1,   // OP* (Op Ind)
        86: 1,   // STF
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
