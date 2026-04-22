#include "ROM.hpp"
#include <cstring>
#include <cassert>

void ROM::load(const uint16_t* data, size_t count) {
    assert(count == TI58_WORDS || count == TI59_WORDS);
    memcpy(m_data, data, count * sizeof(uint16_t));
    m_size = count;
}

uint16_t ROM::read(uint16_t addr) const {
    if (addr >= OVERLAY_BASE && addr <= OVERLAY_END) {
        const size_t idx = static_cast<size_t>(addr - OVERLAY_BASE);
        if (m_overlayValid[idx]) {
            return m_overlayWords[idx] & 0x1FFF;
        }
    }
    if (addr >= m_size) return 0;
    // Opcodes are 13 bits wide (bits 12:0).  The storage array uses uint16_t
    // for alignment; mask off the unused upper 3 bits on every read.
    return m_data[addr] & 0x1FFF;
}

bool ROM::loadOverlay(const uint16_t* data, size_t count) {
    if (count > OVERLAY_WORDS) return false;
    clearOverlay();
    for (size_t i = 0; i < count; i++) {
        m_overlayWords[i] = static_cast<uint16_t>(data[i] & 0x1FFFu);
        m_overlayValid[i] = 1;
    }
    return true;
}

void ROM::clearOverlay() {
    m_overlayWords.fill(0);
    m_overlayValid.fill(0);
}
