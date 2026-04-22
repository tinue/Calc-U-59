#pragma once
#include <cstdint>
#include <cstddef>
#include <array>

/// ROM for TI-58/59: up to 6144 × 13-bit words.
class ROM {
public:
    static constexpr size_t TI59_WORDS = 6144;
    static constexpr size_t TI58_WORDS = 5120;
    static constexpr uint16_t OVERLAY_BASE = 0x1800;
    static constexpr uint16_t OVERLAY_END  = 0x1FFF;
    static constexpr size_t OVERLAY_WORDS  = OVERLAY_END - OVERLAY_BASE + 1;

    ROM() = default;

    /// Load words into ROM. count must be TI58_WORDS or TI59_WORDS.
    void load(const uint16_t* data, size_t count);

    /// Read a 13-bit word at address. Returns 0 for out-of-range.
    uint16_t read(uint16_t addr) const;

    /// Load debug overlay words at linear address 0x1800 and above.
    /// Returns false when count exceeds the overlay address range.
    bool loadOverlay(const uint16_t* data, size_t count);

    /// Clear all debug overlay words.
    void clearOverlay();

    size_t size() const { return m_size; }

private:
    uint16_t m_data[TI59_WORDS]{};
    size_t   m_size{0};
    std::array<uint16_t, OVERLAY_WORDS> m_overlayWords{};
    std::array<uint8_t, OVERLAY_WORDS>  m_overlayValid{};
};
