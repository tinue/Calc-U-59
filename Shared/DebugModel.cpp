#include "DebugModel.hpp"
#include <algorithm>

namespace cu59 {

void DebugModel::attach(const EmulatorSession& session) {
    moduleChanged(session);
    m_live = {};
    m_listing.clear();
    m_listingSource = ProgramSource::UserProgram;
    m_cpuHistory.clear();
    m_cpuHistorySeqno.reset();
    m_lastLibMismatch = -1;
}

void DebugModel::moduleChanged(const EmulatorSession& session) {
    m_moduleError.clear();
    m_module = ModuleImage::parse(session.moduleImage(), &m_moduleError);
    m_romCache.clear();
}

DebugModel::Update DebugModel::tick(const TI59Machine& m, Model model, bool livePanel, bool cpuPanel, bool frozen) {
    Update u;
    if (livePanel && !frozen) u |= rebuildLive(m, model, false);
    if (cpuPanel || frozen) {
        std::vector<CpuFrame> frames = readTraceRing(m);
        m_heatmap.ingest(frames.data(), frames.size());
        u.heatmap = m_heatmap.publishTick();
        // Running: rebuild the list only when new instructions ran.
        uint32_t newest = frames.empty() ? 0 : frames.back().seqno;
        if (!frozen && newest != m_cpuHistorySeqno) {
            m_cpuHistorySeqno = newest;
            m_cpuHistory = recentInstructions(frames);
            u.cpu = true;
        }
    }
    return u;
}

DebugModel::Update DebugModel::frozenView(const TI59Machine& m, Model model, FrozenViewReason reason) {
    Update u;
    if (reason == FrozenViewReason::StepKeycode) {
        CpuFrame cpu = m.snapshotCPU();
        if (programSourceFrom(cpu.SCOM[0][3], cpu.pc) == ProgramSource::SolidStateReturn) {
            advanceListingCurrent();
            u.live = true;
        }
    }
    if (reason != FrozenViewReason::StepInstruction) u |= rebuildLive(m, model, true);
    u |= captureInspector(m);
    return u;
}

DebugModel::Update DebugModel::rebuildLive(const TI59Machine& m, Model model, bool frozen) {
    Update u;
    LiveDebugBuild b = buildLiveSnapshot(m, model, m_module, m_romCache, frozen);
    if (b.libProgramMismatch && b.libProgramMismatch->second != m_lastLibMismatch) {
        m_lastLibMismatch = b.libProgramMismatch->second;
        u.diagnostic = "Library exec PC resolves to Pgm " + std::to_string(b.libProgramMismatch->first) +
                       " but SCOM[9] says Pgm " + std::to_string(b.libProgramMismatch->second);
    }
    // solidStateReturn shows a raw CROM address: keep the listing (a keycode step advances it).
    if (b.snap.programSource != ProgramSource::SolidStateReturn) {
        auto listing = programListing(b.sourceKeycodes, b.argSteps, b.snap.currentStep);
        if (listing != m_listing || b.snap.programSource != m_listingSource) {
            m_listing = std::move(listing);
            m_listingSource = b.snap.programSource;
            u.live = true;
        }
    }
    if (b.snap != m_live) {
        m_live = std::move(b.snap);
        u.live = true;
    }
    return u;
}

DebugModel::Update DebugModel::captureInspector(const TI59Machine& m) {
    m_cpuHistory = inspectorHistory(m);
    m_cpuHistorySeqno.reset();  // the next running frame rebuilds the list
    Update u;
    u.cpu = true;
    return u;
}

void DebugModel::advanceListingCurrent() {
    auto it = std::find_if(m_listing.begin(), m_listing.end(), [](const StepEntry& e) { return e.isCurrent; });
    if (it == m_listing.end() || it + 1 == m_listing.end()) return;
    it->isCurrent = false;
    (it + 1)->isCurrent = true;
}

int DebugModel::listingCurrentIndex() const {
    auto it = std::find_if(m_listing.begin(), m_listing.end(), [](const StepEntry& e) { return e.isCurrent; });
    return it == m_listing.end() ? -1 : static_cast<int>(it - m_listing.begin());
}

void DebugModel::resetHeatmapBaseline(const TI59Machine& m) {
    m_heatmap.clear();
    auto frames = readTraceRing(m);
    if (!frames.empty()) m_heatmap.resetBaseline(frames.back().seqno);
}

} // namespace cu59
