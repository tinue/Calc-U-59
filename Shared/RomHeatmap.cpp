#include "RomHeatmap.hpp"
#include <algorithm>

namespace cu59 {

void RomHeatmap::ingest(const CpuFrame* frames, size_t count) {
    bool any = false;
    uint32_t last = m_lastSeqno;
    for (size_t i = 0; i < count; ++i) {
        if (frames[i].seqno <= m_lastSeqno) continue;
        if (frames[i].pc < kCodeWords) ++m_counts[frames[i].pc];
        last = frames[i].seqno;
        any = true;
    }
    if (any) {
        m_lastSeqno = last;
        m_dirty = true;
    }
}

bool RomHeatmap::publishTick() {
    if (++m_tick < 6) return false;
    m_tick = 0;
    if (!m_dirty) return false;
    m_dirty = false;
    return true;
}

void RomHeatmap::clear() {
    std::fill(m_counts.begin(), m_counts.end(), 0);
    m_lastSeqno = 0;
    m_dirty = false;
    m_tick = 0;
}

void RomHeatmap::resetBaseline(uint32_t newestSeqno) {
    clear();
    m_lastSeqno = newestSeqno;
}

} // namespace cu59
