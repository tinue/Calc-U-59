#include "TMC0540.hpp"
#include <algorithm>

uint8_t TMC0540::bcdDecode(uint8_t byte) {
    uint8_t high = (byte >> 4) & 0xF;
    uint8_t low  = byte & 0xF;
    return (high * 10) + low;
}

void TMC0540::parseHeader() {
    m_header.programCount = 0;
    m_header.totalSize = 0;
    std::memset(m_header.startAddresses, 0, sizeof(m_header.startAddresses));

    if (m_data[0] == 0 || m_data[0] > 0x50) {
        // Invalid program count or none loaded
        return;
    }

    m_header.programCount = bcdDecode(m_data[0]);

    // Parse start addresses (2 BCD bytes each, up to m_header.programCount programs)
    for (int i = 0; i < m_header.programCount && i < 50; i++) {
        int offset = 2 + (i * 2);
        int byte1 = m_data[offset];
        int byte2 = m_data[offset + 1];
        int addr = (bcdDecode(byte1) * 100) + bcdDecode(byte2);
        m_header.startAddresses[i] = addr;
    }

    // Parse total size (2 BCD bytes after all start addresses)
    int totalSizeOffset = 2 + (m_header.programCount * 2);
    m_header.totalSize = (bcdDecode(m_data[totalSizeOffset]) * 100) +
                         bcdDecode(m_data[totalSizeOffset + 1]);
}

void TMC0540::reset() {
    m_addr = 0;
    m_addrReadPos = 0;
    m_addrWasWriting = false;
}

void TMC0540::loadLibrary(const uint8_t* data, size_t count) {
    count = std::min(count, static_cast<size_t>(5000));
    std::memcpy(m_data, data, count);
    if (count < 5000) {
        std::memset(m_data + count, 0, 5000 - count);
    }
    parseHeader();
    reset();
}

int TMC0540::addrAsDecimal() const {
    // Convert hex nibbles (BCD-encoded) to decimal address.
    // m_addr is stored with each nibble as a decimal digit (e.g., 0x1234 → 1234).
    uint8_t n3 = (m_addr >> 12) & 0xF;
    uint8_t n2 = (m_addr >> 8) & 0xF;
    uint8_t n1 = (m_addr >> 4) & 0xF;
    uint8_t n0 = m_addr & 0xF;
    return (((((n3 * 10) + n2) * 10) + n1) * 10) + n0;
}

uint16_t TMC0540::inLib() {
    if (m_addrWasWriting) m_addrReadPos = 0;  // Reset if switching from write to read
    m_addrWasWriting = false;
    int decimalAddr = addrAsDecimal();
    uint8_t byte = m_data[decimalAddr];

    // Post-increment the address (in BCD hex representation)
    m_addr = (m_addr + 1) % 0x10000;  // Hex increment with 16-bit wraparound
    if (addrAsDecimal() >= 5000) m_addr = 0;  // Wrap at 5000

    return static_cast<uint16_t>(byte);
}

void TMC0540::outLibPc(uint16_t KR) {
    if (!m_addrWasWriting) m_addrReadPos = 0;  // Reset if switching from read to write
    m_addrWasWriting = true;

    // Extract digit from KR[7:4]
    uint8_t digit = (KR >> 4) & 0xF;

    // Write digit at position m_addrReadPos into m_addr
    uint16_t shift = (3 - m_addrReadPos) * 4;
    uint16_t mask = 0xF << shift;
    m_addr = (m_addr & ~mask) | (digit << shift);

    m_addrReadPos = (m_addrReadPos + 1) % 4;
}

uint16_t TMC0540::inLibPc() {
    if (m_addrWasWriting) m_addrReadPos = 0;  // Reset if switching from write to read
    m_addrWasWriting = false;

    uint16_t shift = (3 - m_addrReadPos) * 4;
    uint8_t digit = (m_addr >> shift) & 0xF;

    m_addrReadPos = (m_addrReadPos + 1) % 4;

    return static_cast<uint16_t>(digit);
}

uint16_t TMC0540::inLibHigh() const {
    // Peek at high nibble of the byte at current address (no advance)
    int decimalAddr = addrAsDecimal();
    uint8_t byte = m_data[decimalAddr];
    return static_cast<uint16_t>(byte & 0xF0U);
}

uint8_t TMC0540::libKeycode(int addr) const {
    if (addr < 0 || addr >= 5000) return 0;
    return bcdDecode(m_data[addr]);
}

int TMC0540::findProgramRange(int addr, int& outStart, int& outEnd) const {
    for (int i = 0; i < m_header.programCount; i++) {
        int start = m_header.startAddresses[i];
        int end = (i + 1 < m_header.programCount) ? m_header.startAddresses[i + 1]
                                                   : m_header.totalSize;
        if (addr >= start && addr < end) {
            outStart = start;
            outEnd = end;
            return i;
        }
    }
    return -1;
}

int TMC0540::getVirtualLibPc() const {
    if (m_addr == 0) return -1;  // Not in any program (initial state)

    // Correct for post-increment: subtract 1 from the decimal address
    int decimalAddr = addrAsDecimal() - 1;
    int start = 0, end = 0;
    int progIdx = findProgramRange(decimalAddr, start, end);
    if (progIdx < 0) {
        return -1;  // addr is in header or other non-program data
    }
    return decimalAddr - start;  // Program-relative offset
}

int TMC0540::getCurrentProgramKeycodes(uint8_t* out, int maxOut) const {
    if (m_addr == 0 || maxOut <= 0) return 0;

    // Correct for post-increment: subtract 1 from the decimal address
    int decimalAddr = addrAsDecimal() - 1;
    int start = 0, end = 0;
    int progIdx = findProgramRange(decimalAddr, start, end);
    if (progIdx < 0) {
        return 0;  // Not in any program
    }

    // Extract keycodes from start to end
    int count = 0;
    for (int i = start; i < end && count < maxOut; i++) {
        out[count++] = libKeycode(i);
    }
    return count;
}
