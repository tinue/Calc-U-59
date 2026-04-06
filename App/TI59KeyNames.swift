import Foundation

/// Maps TI-59 program step keycodes (0–99) to human-readable mnemonics.
/// Keycodes are laid out as row*10+col for the 9×5 key grid (rows 0–8 = keys 00–44),
/// plus additional two-character operations (45–99).
enum TI59KeyNames {
    static func mnemonic(for keycode: UInt8) -> String {
        table[Int(keycode)] ?? String(format: "?%02d", keycode)
    }

    private static let table: [Int: String] = [
        // Row 0 (keys 0–4)
         0: "0",        1: "1",        2: "2",       3: "3",        4: "4",
        // Row 1 (keys 5–9)
         5: "5",        6: "6",        7: "7",       8: "8",        9: "9",
        // Row 2 (keys 10–14) — A B C D E from 2nd row
        10: "A",       11: "B",       12: "C",      13: "D",       14: "E",
        // Row 3 (keys 15–19)
        15: "INV",     16: "lnx",     17: "CE",     18: "CLR",     19: "2nd",
        // Row 4 (keys 20–24)
        20: "pgm",     21: "SBR",     22: "INS",    23: "DEL",     24: "ARC",
        // Row 5 (keys 25–29)
        25: "sin",     26: "cos",     27: "tan",    28: "P→R",     29: "R→P",
        // Row 6 (keys 30–34)
        30: "x²",      31: "√x",      32: "GTO",    33: "EXC",     34: "Prd",
        // Row 7 (keys 35–39)
        35: "Sum",     36: "yˣ",      37: "1/x",    38: "SBR",     39: "BST",
        // Row 8 (keys 40–44)
        40: "SST",     41: "STO",     42: "RCL",    43: "CM",      44: "OP",
        // Extended ops (45–99)
        45: "×",       46: "÷",       47: "EE",     48: "+/-",     49: "(",
        50: ")",       51: "↔",       52: "FIX",    53: "INT",     54: "nPr",
        55: "+",       56: "-",       57: "=",      58: ".",        59: "π",
        60: "LBL",     61: "RST",     62: "R/S",    63: "NOP",     64: "Adv",
        65: "Prt",     66: "List",    67: "PGM",    68: "Pause",   69: "Ind",
        70: "Dsz",     71: "Fix",     72: "Eng",    73: "Sci",     74: "Deg",
        75: "Rad",     76: "Grad",    77: "Stat",   78: "Var",     79: "?",
        80: "Lrn",     81: "x̄",       82: "Σx²",    83: "Σx",      84: "n",
        85: "Σy²",     86: "Σy",      87: "Σxy",    88: "Lin",     89: "Log",
        90: "Exp",     91: "Pwr",     92: "nCr",    93: "xPr",     94: "P(t)",
        95: "t",       96: "z",       97: "mean",   98: "sdev",    99: "?99",
    ]
}
