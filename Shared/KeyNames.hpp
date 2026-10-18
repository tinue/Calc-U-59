#pragma once
#include <cstdint>
#include <set>
#include <string>
#include <vector>

// Program-step keycodes (0–99) → mnemonics, and the keycode grammar that
// tells operand steps from opcodes. Keycodes are what program memory stores;
// they are not the row×10+col matrix codes of KeyMatrix.hpp — see
// reference/StateFileFormat.md § "Matrix Code Table".

namespace cu59 {

/// Mnemonic for a program keycode ("STO", "2ND", "x̄", …); "?NN" if unknown.
std::string mnemonic(uint8_t keycode);

/// Number of fixed operand steps after this opcode (STO 12, FIX 2, OP 06, …).
/// Branches (GTO, EQ, SBR, GE, IFF, DSZ) have variable-length destinations
/// and are handled by argumentSteps().
int stepsAfter(uint8_t keycode);

/// Indices of steps that are numeric arguments of a preceding opcode
/// (rendered as "NN" instead of a mnemonic). Walks the program sequentially
/// so operand bytes are never misread as opcodes.
///
/// Branch destinations follow the TI-59 keycode grammar: a first operand byte
/// of 00–09 is a 2-step absolute address (SBR 01 23), 40 is IND followed by a
/// register number (SBR IND 25), anything else is a 1-step label rendered as
/// its key mnemonic (SBR CE). Label and IND steps are not marked, so they keep
/// their mnemonic rendering.
std::set<int> argumentSteps(const std::vector<uint8_t>& steps);

} // namespace cu59
