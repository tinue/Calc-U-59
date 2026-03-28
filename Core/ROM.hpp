#pragma once
#include <cstdint>
#include <cstddef>

/// ROM for TI-58/59: up to 6144 × 13-bit words.
class ROM {
public:
    static constexpr size_t TI59_WORDS = 6144;
    static constexpr size_t TI58_WORDS = 5120;

    ROM() = default;

    /// Load words into ROM. count must be TI58_WORDS or TI59_WORDS.
    void load(const uint16_t* data, size_t count);

    /// Read a 13-bit word at address. Returns 0 for out-of-range.
    uint16_t read(uint16_t addr) const;

    size_t size() const { return m_size; }

private:
    uint16_t m_data[TI59_WORDS]{};
    size_t   m_size{0};
};
