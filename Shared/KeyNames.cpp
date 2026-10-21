#include "KeyNames.hpp"
#include <cstdio>

namespace cu59 {

namespace {

const char* const kMnemonics[100] = {
    // Basic digits (0–9)
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    // Extended digits (10–19)
    "E'", "A", "B", "C", "D", "E", "A'", "B'", "C'", "D'",
    // Function row 1 (20–29)
    "CLR", "2ND", "INV", "LNX", "CE", "CLR", "2ND", "INV", "LOG", "CP",
    // Function row 2 (30–39)
    "TAN", "LRN", "X⇄T", "X²", "√X", "1/X", "PGM", "P/R", "SIN", "COS",
    // Function row 3 (40–49)
    "IND", "SST", "STO", "RCL", "SUM", "Yˣ", "INS", "CMS", "EXC", "PRD",
    // Function row 4 (50–59)
    "IxI", "BST", "EE", "(", ")", "÷", "DEL", "ENG", "FIX", "INT",
    // Function row 5 (60–69)
    "DEG", "GTO", "PG*", "EX*", "PD*", "|x|", "PAU", "EQ", "NOP", "OP",
    // Function row 6 (70–79)
    "RAD", "SBR", "ST*", "RC*", "SM*", "-", "LBL", "GE", "∑+", "x̄",
    // Function row 7 (80–89)
    "GRD", "RST", "HIR", "GO*", "OP*", "+", "STF", "IFF", "DMS", "π",
    // Function row 8 (90–99)
    "LST", "R/S", "RTN", ".", "+/-", "=", "WRT", "DSZ", "ADV", "PRT",
};

bool hasOneOperand(uint8_t kc) {
    switch (kc) {
    case 36:  // PGM
    case 42:  // STO
    case 43:  // RCL
    case 44:  // SUM
    case 48:  // EXC
    case 49:  // PRD
    case 58:  // FIX
    case 62:  // PG* (Pgm Ind)
    case 63:  // EX* (Exc Ind)
    case 64:  // PD* (Prd Ind)
    case 69:  // OP
    case 72:  // ST* (STO Ind)
    case 73:  // RC* (RCL Ind)
    case 74:  // SM* (SUM Ind)
    case 82:  // HIR
    case 83:  // GO* (GTO Ind)
    case 84:  // OP* (Op Ind)
    case 86:  // STF
        return true;
    default:
        return false;
    }
}

/// Consume a flag/register-number operand: a single digit, or IND + register.
size_t consumeNumber(const std::vector<uint8_t>& steps, size_t start, std::set<int>& args) {
    if (start >= steps.size()) return start;
    if (steps[start] == 40) {  // IND → register number follows
        if (start + 1 < steps.size()) args.insert(static_cast<int>(start + 1));
        return start + 2;
    }
    args.insert(static_cast<int>(start));
    return start + 1;
}

/// Consume a branch destination: 2-step address, IND + register, or 1-step label.
size_t consumeDestination(const std::vector<uint8_t>& steps, size_t start, std::set<int>& args) {
    if (start >= steps.size()) return start;
    uint8_t first = steps[start];
    if (first <= 9) {  // leading zero → 2-step absolute address
        args.insert(static_cast<int>(start));
        if (start + 1 < steps.size()) args.insert(static_cast<int>(start + 1));
        return start + 2;
    }
    if (first == 40) {  // IND → register number follows
        if (start + 1 < steps.size()) args.insert(static_cast<int>(start + 1));
        return start + 2;
    }
    return start + 1;  // label → shown as mnemonic
}

} // namespace

std::string mnemonic(uint8_t keycode) {
    if (keycode < 100) return kMnemonics[keycode];
    char buf[8];
    std::snprintf(buf, sizeof buf, "?%02u", static_cast<unsigned>(keycode));
    return buf;
}

int stepsAfter(uint8_t keycode) { return hasOneOperand(keycode) ? 1 : 0; }

std::set<int> argumentSteps(const std::vector<uint8_t>& steps) {
    std::set<int> args;
    size_t i = 0;
    bool previousWasInv = false;
    while (i < steps.size()) {
        uint8_t kc = steps[i++];
        switch (kc) {
        case 61: case 67: case 71: case 77:              // GTO, EQ, SBR, GE
            if (kc == 71 && previousWasInv) break;       // INV SBR = RTN, no operand
            i = consumeDestination(steps, i, args);
            break;
        case 87: case 97:                                // IFF, DSZ: flag/register, then destination
            i = consumeNumber(steps, i, args);
            i = consumeDestination(steps, i, args);
            break;
        default: {
            int n = stepsAfter(kc);
            for (int j = 0; j < n; ++j)
                if (i + static_cast<size_t>(j) < steps.size()) args.insert(static_cast<int>(i) + j);
            i += static_cast<size_t>(n);
        }
        }
        previousWasInv = (kc == 22 || kc == 27);
    }
    return args;
}

} // namespace cu59
