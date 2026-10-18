#pragma once
#include "../Core/TraceTypes.hpp"
#include <cstdint>
#include <vector>

// Execution counts per ROM code address (0x0000–0x13FF) for the CPU tab's
// heatmap, accumulated from the trace ring. Frames are read non-destructively
// each tick, so the newest counted seqno guards against double counting.
// Published to the UI at ~10 Hz (every 6th tick) to keep redraws cheap.

namespace cu59 {

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
