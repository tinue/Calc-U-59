#pragma once
#include "DebugLog.hpp"
#include "DebugSnapshots.hpp"
#include "EmulatorSession.hpp"
#include "ModuleImage.hpp"
#include "RomHeatmap.hpp"
#include <optional>
#include <string>
#include <vector>

// The debugger's state on the UI side, for the panels to draw: the
// CALCULATOR tab's snapshot and program listing, the CPU tab's instruction
// history and ROM heatmap, and the LOG tab's ring. Rebuilt at 60 Hz while
// running (only for visible panels) and once per freeze / step while
// frozen. UI thread only; reads the machine while the run loop is running
// (as the panels always have) or stopped. SessionController owns it.

namespace cu59 {

class DebugModel {
public:
    /// What a call changed, for the panels to redraw.
    struct Update {
        bool live = false, listing = false, cpu = false, heatmap = false;
        std::optional<std::string> diagnostic;  ///< developer log line
        Update& operator|=(const Update& o) {
            live |= o.live;
            listing |= o.listing;
            cpu |= o.cpu;
            heatmap |= o.heatmap;
            if (o.diagnostic) diagnostic = o.diagnostic;
            return *this;
        }
    };

    /// A new machine: its module program table, a fresh listing, history and
    /// heatmap. The LOG is kept across machines.
    void attach(const EmulatorSession& session);
    /// The session's module changed (no reset).
    void moduleChanged(const EmulatorSession& session);
    /// Why the module's program table couldn't be read, or empty.
    const std::string& moduleImageError() const { return m_moduleError; }

    /// The 60 Hz frame: the CALCULATOR snapshot while running and its panel
    /// shows; the heatmap while the CPU panel shows or frozen (steps add
    /// frames); the running CPU history.
    Update tick(const TI59Machine& m, Model model, bool livePanel, bool cpuPanel, bool frozen);
    /// The machine stopped at a point to show (freeze, armed freeze, step).
    Update frozenView(const TI59Machine& m, Model model, FrozenViewReason reason);
    /// The CALCULATOR snapshot now, and when frozen the listing (only a frozen
    /// panel shows it).
    Update rebuildLive(const TI59Machine& m, Model model, bool frozen);

    void resetHeatmapBaseline(const TI59Machine& m);
    void clearHeatmap() { m_heatmap.clear(); }

    RingLog& log() { return m_log; }

    const LiveDebugSnapshot& live() const { return m_live; }
    /// The whole program of the source at the last freeze (the frozen PROGRAM STEPS view).
    const std::vector<StepEntry>& listing() const { return m_listing; }
    ProgramSource listingSource() const { return m_listingSource; }
    int listingCurrentIndex() const;
    /// Running: the newest 32 instructions; frozen: the trace ring plus the next.
    const std::vector<InspectorEntry>& cpuHistory() const { return m_cpuHistory; }
    const std::vector<uint32_t>& heatmapCounts() const { return m_heatmap.counts(); }

private:
    Update captureInspector(const TI59Machine& m);
    /// solidStateReturn: SCOM[0] holds a raw CROM return address, so the
    /// listing stays and its highlight moves onto the RTN just executed.
    void advanceListingCurrent();

    ModuleImage m_module;
    std::string m_moduleError;
    std::vector<uint8_t> m_romCache;
    RomHeatmap m_heatmap;
    RingLog m_log;
    LiveDebugSnapshot m_live;
    std::vector<StepEntry> m_listing;
    ProgramSource m_listingSource = ProgramSource::UserProgram;
    std::vector<InspectorEntry> m_cpuHistory;
    std::vector<CpuFrame> m_frames;  ///< the 60 Hz trace-ring read, reused
    std::optional<uint32_t> m_cpuHistorySeqno;  ///< newest frame in a running history
    int m_lastLibMismatch = -1;
};

} // namespace cu59
