#pragma once
#include <cstdint>

/// TMC0598 RAM: 120 registers × 16 BCD nibbles.
/// TI-59 uses all 120; TI-58/58C uses 0–59 only.
class RAM {
public:
    static constexpr int TOTAL_REGS  = 120;
    static constexpr int NIBBLES     = 16;

    RAM() = default;

    void    clear();
    uint8_t read(int reg, int nibble) const;
    void    write(int reg, int nibble, uint8_t val);

    /// Read/write/clear an entire 16-nibble register.
    const uint8_t* readReg(int reg) const;
    void           writeReg(int reg, const uint8_t* src);
    void           clearReg(int reg, int count = 1);  // clear `count` consecutive regs

    /// Limit accessible registers (60 for TI-58/58C, 120 for TI-59).
    void setLimit(int n) { m_maxRegs = (n > 0 && n <= TOTAL_REGS) ? n : TOTAL_REGS; }

    /// Returns the accessible register count for the current model.
    int size() const { return m_maxRegs; }

    /// Serialise / deserialise all 120 registers (for TI-58C persistence).
    void serialise(uint8_t* dst) const;   // dst must be 120*16 bytes
    void deserialise(const uint8_t* src);

private:
    int     m_maxRegs{TOTAL_REGS};
    uint8_t m_data[TOTAL_REGS][NIBBLES]{};
};
