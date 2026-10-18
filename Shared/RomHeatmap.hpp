#pragma once
#include "../Core/TraceTypes.hpp"
#include <cstdint>
#include <vector>

// Execution counts per ROM code address (0x0000–0x13FF) for the CPU tab's
// heatmap, accumulated from the trace ring. Frames are read non-destructively
// each tick, so the newest counted seqno guards against double counting.
// Published to the UI at ~10 Hz (every 6th tick) to keep redraws cheap.

namespace cu59 {

/// Display grid: 80 × 64 cells, one per code address (row-major).
inline constexpr int kHeatmapCols = 80;
inline constexpr int kHeatmapRows = 64;

/// Fixed absolute thresholds: the first hit is immediately visible (step 1);
/// steps only grow, so a renderer can repaint cells incrementally.
inline constexpr uint8_t heatStep(uint32_t count) {
    return count == 0 ? 0 : count <= 2 ? 1 : count <= 9 ? 2 : count <= 49 ? 3 : count <= 249 ? 4 : 5;
}

struct Rgb { uint8_t r, g, b; };
/// Cold dark gray to bright yellow (HSB hue 0.06–0.14, sat 0.9–1.0, bri 0.35–1.0).
inline constexpr Rgb kHeatColors[6] = {
    {46, 46, 46}, {89, 38, 9}, {140, 67, 0}, {191, 115, 0}, {230, 165, 0}, {255, 214, 0},
};

class RomHeatmap {
public:
    static constexpr int kCodeWords = 0x1400;

    /// Count the frames newer than the last one counted.
    void ingest(const CpuFrame* frames, size_t count);

    /// Call once per UI tick; true when the counts should be republished.
    bool publishTick();

    /// Zero the counts.
    void clear();

    /// Zero the counts and start counting after `newestSeqno` (skips frames
    /// still in the ring from before, e.g. after a reset or model switch).
    void resetBaseline(uint32_t newestSeqno);

    const std::vector<uint32_t>& counts() const { return m_counts; }

private:
    std::vector<uint32_t> m_counts = std::vector<uint32_t>(kCodeWords, 0);
    uint32_t m_lastSeqno = 0;
    bool m_dirty = false;
    int m_tick = 0;
};

} // namespace cu59
