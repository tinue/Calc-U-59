#pragma once
#include "../Core/TI59Machine.hpp"
#include "EmulationRunner.hpp"
#include "FrameSampler.hpp"
#include "FreezeController.hpp"
#include "KeySequencer.hpp"
#include "MachineModelInfo.hpp"
#include "RomLoader.hpp"
#include "StateFile.hpp"
#include "TraceWriter.hpp"
#include <atomic>
#include <filesystem>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

// One running calculator: the machine plus the runtime around it that both
// frontends share — the paced run loop and its thread, armed freezes, timed
// key input and KEYSTROKES playback, the 60 Hz frame sampler and the two
// binary trace writers (manual and scripted). A frontend owns one session per
// machine (a model switch builds a new one), forwards user actions to it,
// calls tick() at 60 Hz, and receives asynchronous events through Listener —
// on the session's threads, so it hops to its UI thread itself.
// See reference/SharedArchitecture.md.

namespace cu59 {

/// Which consumers currently need the core's trace ring (TRACE_* flags).
struct TraceConsumers {
    bool cpuPanelVisible = false;
    bool frozen = false;
    bool manualTrace = false;      ///< the "C" indicator / trace toggle
    bool freezeArmed = false;      ///< FREEZE ON START or next-PC-change armed
    bool scriptedTrace = false;
    bool breakpoints = false;
};

/// The trace flags for those consumers; with none active the core runs on its
/// TRACE_NONE fast path.
uint32_t traceFlagsFor(const TraceConsumers& c);

class EmulatorSession : private KeySequencer::Host {
public:
    struct Listener {
        virtual ~Listener() = default;
        virtual void breakpointHit(uint16_t /*pc*/) {}
        virtual void freezeFired(FreezeOwner) {}
        virtual void heldKeyChanged(int /*highlightID*/) {}
        virtual void fullSpeedChanged(bool) {}
        virtual void playbackStarted() {}
        virtual void playbackFinished() {}
        virtual void togglePrinterTrace() {}
        virtual void logLine(const std::string&) {}
        /// A scripted "Trace:" file could not be created.
        virtual void scriptedTraceFailed(const std::string& /*fileName*/) {}
        /// The session's scripted trace opened or closed (trace flags may change).
        virtual void scriptedTraceChanged(bool /*open*/) {}
        virtual void batchDone() {}
    };

    /// Build the machine from ROM text files: the model's ROM and constants
    /// and, if given, a solid-state module image. Throws RomError.
    EmulatorSession(Model model, const ResourceReader& roms, const std::optional<std::string>& moduleRomFile,
                    Listener& listener);
    ~EmulatorSession();
    EmulatorSession(const EmulatorSession&) = delete;
    EmulatorSession& operator=(const EmulatorSession&) = delete;

    Model model() const { return m_model; }
    TI59Machine& machine() { return *m_machine; }
    const std::shared_ptr<TI59Machine>& sharedMachine() const { return m_machine; }
    /// The module image loaded at construction or by loadModule() (empty if none).
    const std::vector<uint8_t>& moduleImage() const { return m_moduleImage; }
    /// Swap the solid-state module (no reset). False if the file can't be read.
    bool loadModule(const std::string& romFile, const ResourceReader& roms);

    // ── Run loop ─────────────────────────────────────────────────────────────
    void start() { m_runner->start(); }
    void stop() { m_runner->stop(); }
    bool isRunning() const { return m_runner->isRunning(); }
    void post(std::function<void()> job) { m_runner->post(std::move(job)); }
    /// Stop first, or this waits for the run loop.
    void sync(const std::function<void()>& job) { m_runner->sync(job); }
    void setFullSpeed(bool on) override;
    bool isFullSpeed() const { return m_runner->fullSpeed(); }

    /// The frontend's freeze state (key playback stops waiting when frozen).
    void setFrozen(bool frozen) { m_frozen = frozen; }
    bool frozen() const { return m_frozen.load(); }
    FreezeController& freezeControl() { return m_freeze; }

    // ── Keys ─────────────────────────────────────────────────────────────────
    /// Press / release a matrix code (logged to the manual trace).
    void pressKey(uint8_t matrixCode) override;
    void releaseKey(uint8_t matrixCode) override;
    void keyboardDown(const std::vector<uint8_t>& codes) { m_keys->keyDown(codes); }
    void keyboardUp() { m_keys->keyUp(); }
    void keyboardRelease() { m_keys->releaseAll(); }
    void playKeystrokes(std::vector<KeystrokeEvent> events) { m_keys->play(std::move(events)); }
    void cancelKeystrokes() { m_keys->cancel(); }
    bool keystrokesPlaying() const { return m_keys->isPlaying(); }

    // ── Frames ───────────────────────────────────────────────────────────────
    FrameUpdate tick(int debugLevel, bool cardSwiping) { return m_sampler.tick(*m_machine, debugLevel, cardSwiping); }

    // ── Traces ───────────────────────────────────────────────────────────────
    TraceWriter& manualTrace() { return m_manualTrace; }
    TraceWriter& scriptedTrace() { return m_scriptedTrace; }
    /// Where scripted "Trace:" files go, and the session size limit.
    void setTraceLocation(const std::filesystem::path& dir, uint64_t maxBytes);
    /// Move the core's trace ring into the open writers (both share the one
    /// ring cursor). Returns which writers hit their size limit and closed.
    struct DrainResult { bool manualLimit = false; bool scriptedLimit = false; };
    DrainResult drainTrace();

    /// "Elapsed: m:ss.mmm" since the last zeroElapseTime (or reset).
    std::string elapsedReport() const;

private:
    // KeySequencer::Host (pressKey, releaseKey and setFullSpeed are public above)
    uint16_t pc() override { return m_machine->pc(); }
    bool isFrozen() override { return m_frozen.load(); }
    void heldKeyChanged(int id) override { m_listener.heldKeyChanged(id); }
    bool fullSpeed() override { return m_runner->fullSpeed(); }
    void togglePrinterTrace() override { m_listener.togglePrinterTrace(); }
    void scriptedTrace(const std::optional<std::string>& fileName) override;
    void zeroElapseTime() override { m_elapseBaseline = m_machine->elapsedTicks(); }
    void reportElapseTime() override { m_listener.logLine(elapsedReport()); }
    void playbackStarted() override { m_listener.playbackStarted(); }
    void playbackFinished() override;

    const Model m_model;
    Listener& m_listener;
    std::shared_ptr<TI59Machine> m_machine;
    std::vector<uint8_t> m_moduleImage;
    FreezeController m_freeze;
    FrameSampler m_sampler;
    TraceWriter m_manualTrace;
    TraceWriter m_scriptedTrace;
    std::mutex m_traceMutex;           ///< serialises drainTrace with scripted open/close
    std::filesystem::path m_traceDir;
    uint64_t m_traceMaxBytes = 50'000'000;
    std::vector<CpuFrame> m_drainBuf = std::vector<CpuFrame>(1024);  ///< drainTrace scratch, under m_traceMutex
    std::atomic<bool> m_frozen{false};
    std::atomic<uint64_t> m_elapseBaseline{0};
    std::unique_ptr<EmulationRunner> m_runner;
    std::unique_ptr<KeySequencer> m_keys;   ///< last: its threads stop first
};

} // namespace cu59
