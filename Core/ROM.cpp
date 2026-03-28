#include "ROM.hpp"
#include <cstring>
#include <cassert>

void ROM::load(const uint16_t* data, size_t count) {
    assert(count == TI58_WORDS || count == TI59_WORDS);
    memcpy(m_data, data, count * sizeof(uint16_t));
    m_size = count;
}

uint16_t ROM::read(uint16_t addr) const {
    if (addr >= m_size) return 0;
    // Opcodes are 13 bits wide (bits 12:0).  The storage array uses uint16_t
    // for alignment; mask off the unused upper 3 bits on every read.
    return m_data[addr] & 0x1FFF;
}
