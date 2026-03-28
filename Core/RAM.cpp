#include "RAM.hpp"
#include <cstring>
#include <cassert>

void RAM::clear() {
    memset(m_data, 0, sizeof(m_data));
}

uint8_t RAM::read(int reg, int nibble) const {
    assert(reg >= 0 && reg < TOTAL_REGS);
    assert(nibble >= 0 && nibble < NIBBLES);
    return m_data[reg][nibble];
}

void RAM::write(int reg, int nibble, uint8_t val) {
    assert(reg >= 0 && reg < TOTAL_REGS);
    assert(nibble >= 0 && nibble < NIBBLES);
    m_data[reg][nibble] = val & 0x0F;  // clamp to 4 bits; callers may pass raw BCD bytes
}

const uint8_t* RAM::readReg(int reg) const {
    assert(reg >= 0 && reg < TOTAL_REGS);
    return m_data[reg];
}

void RAM::writeReg(int reg, const uint8_t* src) {
    assert(reg >= 0 && reg < TOTAL_REGS);
    memcpy(m_data[reg], src, NIBBLES);
}

void RAM::clearReg(int reg, int count) {
    if (reg < 0 || reg >= TOTAL_REGS) return;
    if (reg + count > TOTAL_REGS) count = TOTAL_REGS - reg;
    memset(m_data[reg], 0, count * NIBBLES);
}

void RAM::serialise(uint8_t* dst) const {
    memcpy(dst, m_data, sizeof(m_data));
}

void RAM::deserialise(const uint8_t* src) {
    memcpy(m_data, src, sizeof(m_data));
}
