#ifndef TMC0540_HPP
#define TMC0540_HPP

#include <cstdint>
#include <cstring>

/// Solid-state ROM chip (TMC0540) with program header parsing and virtual PC tracking.
///
/// The library ROM stores programs sequentially with a header:
/// - data[0]: program count (BCD)
/// - data[1]: reserved
/// - data[2..2+count*2-1]: start addresses (2 BCD bytes each)
/// - data[2+count*2..]: program data (keycodes and arguments)
///
/// Virtual PC = logical program counter within the current program,
/// or -1 if m_addr points outside all program ranges (e.g., during header reads).
class TMC0540 {
public:
    TMC0540() = default;

    void reset();
    void loadLibrary(const uint8_t* data, size_t count);

    // Four instruction handlers (called by TMC0501's case 0xE:)
    uint16_t inLib();               // Fetch byte, post-increment, return as EXT bits
    void     outLibPc(uint16_t KR); // Write one address digit from KR[7:4]
    uint16_t inLibPc();             // Read one address digit into EXT
    uint16_t inLibHigh() const;     // Peek high nibble without advancing

    // Debug / bridge access
    uint16_t getAddr() const { return m_addr; }
    uint8_t  getAddrReadPos() const { return m_addrReadPos; }
    uint8_t  libKeycode(int addr) const;

    // Virtual PC (logical program counter relative to current program)
    int getVirtualLibPc() const;

    // Extract all keycodes from current program into buffer
    int getCurrentProgramKeycodes(uint8_t* out, int maxOut) const;

private:
    struct LibraryHeader {
        int programCount = 0;
        int startAddresses[50]{};  // BCD-decoded start addresses, up to 50 programs
        int totalSize = 0;
    };

    uint16_t m_addr{};              // Current hardware address counter
    uint8_t  m_addrReadPos{};       // Digit position for multi-call LIB.PC (0–3)
    bool     m_addrWasWriting{};    // Direction flag (read vs. write)
    uint8_t  m_data[5000]{};        // Loaded library image
    LibraryHeader m_header{};       // Parsed header (program count, start addresses, size)

    // Helpers
    static uint8_t bcdDecode(uint8_t byte);  // Decode BCD byte to 0–99
    void parseHeader();                       // Parse header from m_data[0..]
    int  findProgramRange(int addr, int& outStart, int& outEnd) const;  // Returns program index or -1
};

#endif // TMC0540_HPP
