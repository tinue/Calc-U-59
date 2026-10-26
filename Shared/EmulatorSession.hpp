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
#include <deque>
#include <filesystem>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

// One running calculator: the machine plus the runtime around it that both
// frontends share — the paced run loop and its thread, the debugger's freeze
// state (frozen, owner, armed freezes, stepping), the trace flags, timed key
// input and KEYSTROKES playback, the 60 Hz frame sampler and the two binary
// trace writers (manual and scripted). One session per machine (a model
// switch builds a new one); SessionController owns it. Listener events come
// on the session's threads — with Threading::Cooperative, from pump(). See
// reference/SharedArchitecture.md.

namespace cu59 {

/// Which consumers currently need the core's trace ring (TRACE_* flags).
struct TraceConsumers {
    bool cpuPanelVisible = false;
    bool frozen = false;
    bool manualTrace = false;      ///< the "C" indicator / trace toggle
    bool freezeArmed = false;      ///< FREEZE ON START or next-PC-change armed
    bool scriptedTrace = false;
};

/// The debugger's freeze state. `generation` changes on every freeze, resume
/// and clear, so a view built for an earlier freeze can be recognised.
struct DebugState {
    bool frozen = false;
    std::optional<FreezeOwner> owner;   ///< the panel whose RESUME / STEP apply
    bool pcChangeArmed = false;         ///< CALCULATOR: FREEZE ON START (next step boundary)
    bool scanLoopExitArmed = false;     ///< CPU: FREEZE ON START (scan-loop exit)
    uint64_t generation = 0;
    bool operator==(const DebugState& o) const {
        return frozen == o.frozen && owner == o.owner && pcChangeArmed == o.pcChangeArmed &&
               scanLoopExitArmed == o.scanLoopExitArmed && generation == o.generation;
    }
};

/// Why a frozen machine is ready to be shown.
enum class FrozenViewReason {
    Freeze,           ///< FREEZE: at the next keycode boundary
    FreezeFired,      ///< an armed freeze fired
    StepKeycode,      ///< STEP in the CALCULATOR panel
    StepInstruction,  ///< STEP in the CPU panel
};

/// The trace flags for those consumers; with none active the core runs on its
/// TRACE_NONE fast path.
uint32_t traceFlagsFor(const TraceConsumers& c);

/// A card queued by KEYSTROKES ArmCard: / InsertCard:, waiting to be fed.
struct QueuedCard {
    std::string name;                                 ///< mem:… or a card file name
    std::shared_ptr<const CardDefinition> definition; ///< the file's CARD: block, if any
    bool insertNow = false;                           ///< InsertCard: fed at idle, playback waits for it
};

class EmulatorSession : private KeySequencer::Host {
public:
    struct Listener {
        virtual ~Listener() = default;
        /// debugState() changed off the caller's thread (an armed freeze fired).
        virtual void debugStateChanged() {}
        /// The machine is stopped at a point to show (after beginNextStep); on
        /// the emulation thread. Ignore it if debugState().generation moved on.
        virtual void frozenViewReady(uint64_t /*generation*/, FrozenViewReason) {}
        virtual void heldKeyChanged(int /*highlightID*/) {}
        virtual void fullSpeedChanged(bool) {}
        virtual void playbackStarted() {}
        virtual void playbackFinished() {}
        virtual void togglePrinterTrace() {}
        virtual void logLine(const std::string&) {}
        /// A scripted "Trace:" file could not be created.
        virtual void scriptedTraceFailed(const std::string& /*fileName*/) {}
        /// KEYSTROKES reached a reload; call hostDone() once it is applied.
        virtual void reloadRequested(const std::shared_ptr<const ReloadStage>&) {}
    };

    /// Build the machine from ROM text files: the model's ROM and constants
    /// and, if given, a solid-state module image. Throws RomError.
    EmulatorSession(Model model, const ResourceReader& roms, const std::optional<std::string>& moduleRomFile,
                    Listener& listener, Threading threading = Threading::Threads);
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
    /// Cooperative only: run the batches, key input and jobs due by `now`.
    void pump(std::chrono::steady_clock::time_point now);

    /// Since the last call: a batch ran (TI-58C RAM may have changed).
    bool takeRamDirty() { return m_ramDirty.exchange(false); }

    // ── Debugger: freeze and step (UI thread) ────────────────────────────────
    DebugState debugState() const;
    bool frozen() const { return m_frozen.load(); }
    /// Stop, freeze for `owner`, disarm both armed freezes; the machine runs on
    /// to the next keycode boundary, then frozenViewReady(Freeze).
    void freeze(FreezeOwner owner);
    /// Freeze where the machine stands (stopped already), no step.
    void freezeInPlace(FreezeOwner owner);
    /// Unfreeze and start the run loop.
    void resume();
    /// Unfreeze without starting (the caller has stopped the loop to change state).
    void clearFreeze();
    /// Freeze before the next program byte executes (CALCULATOR) or when the
    /// keyboard scan loop exits (CPU); arming one disarms the other.
    void armPcChange();
    void armScanLoopExit();
    void disarmPcChange();
    void disarmScanLoopExit();
    /// While frozen: one keycode (→ StepKeycode) or one instruction, stepping
    /// through a HOLD (WAIT Dn) of up to 32 instructions (→ StepInstruction).
    void stepKeycode();
    void stepInstruction();
    /// The CPU panel is visible (it needs the trace ring).
    void setCpuPanelVisible(bool visible);

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
    /// The next queued card the machine takes where it stands: the first
    /// InsertCard card in the idle scan loop, the first ArmCard card in the
    /// card wait of Write / INV Write (ModelInfo::cardWait). UI thread.
    std::optional<QueuedCard> takeQueuedCard();
    /// A reload has been applied, or an InsertCard card has passed (or failed).
    void hostDone();
    /// Drop the queued cards (a new preset, a reset); returns their names.
    std::vector<std::string> clearQueuedCards();

    // ── Frames ───────────────────────────────────────────────────────────────
    FrameUpdate tick(int debugLevel, bool cardSwiping) {
        return m_sampler.tick(*m_machine, info(m_model).instructionHz, debugLevel, cardSwiping);
    }

    // ── Traces ───────────────────────────────────────────────────────────────
    TraceWriter& manualTrace() { return m_manualTrace; }
    TraceWriter& scriptedTrace() { return m_scriptedTrace; }
    /// The manual ("C" indicator) trace: a fresh file at `path`.
    bool openManualTrace(const std::filesystem::path& path, uint64_t maxBytes);
    /// Drain what is left and close it.
    void closeManualTrace();
    /// A trace writer is open: drainTrace() at 60 Hz.
    bool needsDrain() const { return m_manualTrace.isOpen() || m_scriptedTrace.isOpen(); }
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
    void togglePrinterTrace() override { m_listener.togglePrinterTrace(); }
    void scriptedTrace(const std::optional<std::string>& fileName) override;
    void zeroElapseTime() override { m_elapseBaseline = m_machine->elapsedTicks(); }
    void onFreezeFired(FreezeOwner owner);       // emulation thread
    /// Set the frozen state (and owner, generation); disarms both armed freezes when freezing.
    uint64_t setFrozenState(bool frozen, std::optional<FreezeOwner> owner);
    void applyTraceFlags();
    void reportElapseTime() override { m_listener.logLine(elapsedReport()); }
    void playbackStarted() override { m_listener.playbackStarted(); }
    void playbackFinished() override;
    void applyReload(const std::shared_ptr<const ReloadStage>& stage) override;
    void queueCard(const KeystrokeEvent& event) override;
    bool hostPending() override { return m_hostPending.load() > 0; }

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
    mutable std::mutex m_stateMutex;   ///< m_state, m_cpuPanelVisible, trace-flag updates
    DebugState m_state;
    bool m_cpuPanelVisible = false;
    std::atomic<bool> m_frozen{false};  ///< m_state.frozen, for the key sequencer
    std::atomic<bool> m_ramDirty{false};
    std::atomic<uint64_t> m_elapseBaseline{0};
    std::mutex m_cardMutex;            ///< m_queuedCards
    std::deque<QueuedCard> m_queuedCards;
    std::atomic<int> m_hostPending{0}; ///< reloads and InsertCard cards not done yet
    std::unique_ptr<EmulationRunner> m_runner;
    std::unique_ptr<KeySequencer> m_keys;   ///< last: its threads stop first
};

} // namespace cu59
