#pragma once
#include "CardFile.hpp"
#include "CueCard.hpp"
#include "DebugModel.hpp"
#include "EmulatorSession.hpp"
#include "ModuleCatalog.hpp"
#include "StateFile.hpp"
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

// Everything a frontend does with a calculator that isn't drawing: one per
// app, on its UI thread. Owns the EmulatorSession (rebuilt on a model
// switch) and the debugger's DebugModel, and runs the flows both apps share
// — starting and switching machines, presets (state files), the TI-58C
// constant memory, the card reader, the printer strip, the cue card shown,
// freeze and step, traces, the ASM overlay and the LOG tab. The frontend
// supplies a Platform (its UI thread, files, settings, error alerts), calls
// tick() at 60 Hz and redraws what changed() names. With
// Threading::Cooperative (the web build) tick() also runs the emulation and
// key input itself: there are no other threads.
// See reference/SharedArchitecture.md § "SessionController".

namespace cu59 {

class SessionController {
public:
    /// What changed (Platform::changed), so the frontend redraws only that.
    enum Change : uint32_t {
        ModelChanged = 1u << 0,     ///< model, module, machine replaced or reset (card reader emptied)
        DisplayChanged = 1u << 1,   ///< display digits or the C indicator
        CueCardChanged = 1u << 2,
        PrinterChanged = 1u << 3,   ///< lines, connection, TRACE latch
        PaperCut = 1u << 4,         ///< the strip was cleared
        CardChanged = 1u << 5,      ///< card reader state or file name
        RunStateChanged = 1u << 6,  ///< freeze, armed freezes, full speed, playback, held key
        LiveChanged = 1u << 7,      ///< CALCULATOR tab snapshot
        CpuChanged = 1u << 8,       ///< CPU tab history
        HeatmapChanged = 1u << 9,
        LogChanged = 1u << 10,
        AsmChanged = 1u << 11,
        TraceChanged = 1u << 12,    ///< manual trace on/off
        ListingChanged = 1u << 13,  ///< CALCULATOR tab program listing (rebuilt when frozen)
    };

    struct TraceLocation {
        std::filesystem::path dir;  ///< manual and scripted traces go here
        uint64_t maxBytes = 0;      ///< per trace session
    };

    /// Implemented by each frontend. All calls arrive on the UI thread except
    /// runOnUiThread itself.
    struct Platform {
        virtual ~Platform() = default;
        /// Queue `job` on the UI thread (never run it inline).
        virtual void runOnUiThread(std::function<void()> job) = 0;
        /// ti58c.mem: nullopt when absent or unreadable.
        virtual std::optional<std::string> readConstantMemory() = 0;
        virtual void writeConstantMemory(const std::string& text) = 0;
        /// A card file the machine wrote (path as given to fitCard / fitBlankCard).
        virtual bool writeCard(const std::string& path, const std::string& text) = 0;
        /// A card file a preset names (KEYSTROKES ArmCard: / InsertCard:): the
        /// path of `fileName` in the card folder.
        virtual std::string cardFilePath(const std::string& fileName) = 0;
        /// `raw` is nullopt if there is no such file. `unreadable`: the file is
        /// there but can't be read now (not "missing": a blank card must not go
        /// in, or a write would replace the file).
        struct CardRead { std::optional<std::vector<uint8_t>> raw; bool unreadable = false; };
        /// The card file at `path` as it is now: when a preset names it, and
        /// again before a write merges a side into it.
        virtual CardRead readCard(const std::string& path) = 0;
        /// KEYSTROKES DebugPanel:: select that tab of the debugger, as a click
        /// would (the page stays where it is on paged layouts).
        virtual void showDebugPanel(DebugPanel panel) = 0;
        virtual TraceLocation traceLocation() = 0;
        /// false: e.g. iCloud is not reachable (asked only when a manual trace opens).
        virtual bool traceAvailable() { return true; }
        virtual void saveLastUsedModel(Model model) = 0;
        virtual void saveModuleID(const std::string& moduleID) = 0;
        virtual void error(const std::string& title, const std::string& message) = 0;
        /// Developer diagnostics (not shown in the app).
        virtual void diagnostic(const std::string& message) = 0;
        virtual void changed(uint32_t changes) = 0;
    };

    enum class CardState { NoCard, Swiping };
    enum class DebugLevel { Off = 0, Info = 1, Debug = 2 };
    /// What a file dropped on the calculator does (§ "Dropped Files").
    enum class DropAction {
        LoadPreset,   ///< as the Preset button
        FitCard,      ///< fitted into the calculator's card cutout
        Ignore,       ///< a card, and this model has no reader
        NotAccepted,  ///< not a preset or a card
    };

    /// `cuecards` is roms/solid-state/cuecards.txt; `moduleID` the saved module.
    SessionController(Platform& platform, ResourceReader roms, std::string cuecards, std::string moduleID,
                      Threading threading = Threading::Threads);
    ~SessionController();
    SessionController(const SessionController&) = delete;
    SessionController& operator=(const SessionController&) = delete;

    // ── Machine ──────────────────────────────────────────────────────────────
    /// Build a fresh machine of `model`. On a ROM error the previous one keeps
    /// running and false is returned.
    bool startMachine(Model model);
    bool hasMachine() const { return m_session != nullptr; }
    Model model() const { return m_model; }
    EmulatorSession* session() { return m_session.get(); }
    void resetMachine();
    void cleanResetMachine();
    /// TI-58C: write ti58c.mem now if its contents changed (also debounced in tick()).
    void persistConstantMemory();
    /// App to the background: persist and stop; resumeAfterSuspend() restarts only what ran.
    void suspend();
    void resumeAfterSuspend();
    /// The 60 Hz frame: display, printer, log, card auto-eject, the debugger,
    /// traces, and the slower checks (cue-card program 2 Hz, LOG text 1 Hz,
    /// TI-58C persist debounce 0.5 s).
    void tick(std::chrono::steady_clock::time_point now);

    const std::string& moduleID() const { return m_moduleID; }
    /// Swap the solid-state module (no reset); false (and an error) if it can't be loaded.
    bool selectModule(const std::string& moduleID);
    /// The Settings choice: swap to a different module, then soft-reset.
    void changeModule(const std::string& moduleID);
    std::vector<ModuleMetadata> allModules() const { return allModuleMetadata(m_cuecards); }

    // ── Display, keys, speed ─────────────────────────────────────────────────
    const LedFrame& display() const { return m_display; }
    double calcIndicatorOpacity() const { return m_calcOpacity; }
    void pressKey(uint8_t matrixCode);
    void releaseKey(uint8_t matrixCode);
    void keyboardDown(const std::vector<uint8_t>& codes);
    void keyboardUp();
    void keyboardRelease();
    int heldKey() const { return m_heldKey; }  ///< row×5 + col shown pressed, -1 none
    void setFullSpeed(bool on);
    bool fullSpeed() const { return m_fullSpeed; }
    bool keystrokesPlaying() const { return m_keystrokesPlaying; }

    // ── Cue card ─────────────────────────────────────────────────────────────
    const std::optional<CueCardContent>& cueCard() const { return m_cueCard; }

    // ── Printer ──────────────────────────────────────────────────────────────
    const std::vector<std::string>& printerLines() const { return m_printerLines; }
    const std::vector<PrinterCodeLine>& printerCodeLines() const { return m_printerCodeLines; }
    /// The strip's height in dot pitches (a text line without dot codes yet counts as complete).
    double printerStripHeightUnits() const;
    bool printerConnected() const { return m_printerConnected; }
    bool printerTrace() const { return m_session && m_session->machine().printerTrace(); }
    void setPrinterConnected(bool connected);
    /// The printer panel's connect button: plug the PC-100C in or out and reset the calculator.
    void togglePrinterConnection();
    void togglePrinterTrace();
    void pressPrinterPrint(bool pressed);
    void pressPrinterAdv(bool pressed);
    void cutPaper();

    // ── Card reader (reference/SharedArchitecture.md § "Card Reader Flow") ──────
    CardState cardState() const { return m_pass ? CardState::Swiping : CardState::NoCard; }
    const std::string& cardFileName() const { return m_cardFileName; }
    /// Fit a card file into the cutout, replacing the card there (nullopt bytes:
    /// it could not be read). Nothing goes into the reader yet. Written data goes
    /// back to `path`. False if it could not be fitted, or a card is in the reader.
    bool fitCard(const std::optional<std::vector<uint8_t>>& raw, const std::string& path, const std::string& fileName);
    /// Fit a fresh card; `savePath` is created or replaced by its first write.
    bool fitBlankCard(const std::string& savePath, const std::string& fileName);
    /// Feed a side (0 = top-left corner, 1 = top-right) of the fitted card into the reader.
    bool feedSide(int side);
    /// A press at canvas position (nx, ny): feeds a side if it hits a corner of
    /// the fitted card on show. True if the press hit such a corner.
    bool tapCard(double nx, double ny);
    bool cardFitted() const { return m_fitted.has_value(); }
    /// The corner to draw lit: the side of the fitted card in the reader, if that card is on show.
    std::optional<int> litCardCorner() const;
    void ejectCard();

    // ── State files ──────────────────────────────────────────────────────────
    /// A preset's bytes (nullopt: it could not be read).
    void loadStateFile(const std::optional<std::vector<uint8_t>>& raw);

    // ── Dropped files (reference/SharedArchitecture.md § "Dropped Files") ───────
    /// By the file's name and the current model.
    DropAction dropAction(const std::string& fileName) const;
    /// Load the preset or insert the card; false when nothing was done (a card
    /// is already in the reader, the file could not be read, or dropAction
    /// says no). A write to the card goes back to `path`.
    bool openDroppedFile(const std::optional<std::vector<uint8_t>>& raw, const std::string& path,
                         const std::string& fileName);

    // ── Debugger ─────────────────────────────────────────────────────────────
    void setLiveDebugEnabled(bool on);
    void setCpuDebugEnabled(bool on);
    bool liveDebugEnabled() const { return m_liveDebugEnabled; }
    bool cpuDebugEnabled() const { return m_cpuDebugEnabled; }
    DebugState debugState() const { return m_debugState; }
    bool isFrozen() const { return m_debugState.frozen; }
    void freeze(FreezeOwner owner);
    void resume();
    void armPcChange();
    void armScanLoopExit();
    void disarmPcChange();
    void disarmScanLoopExit();
    void stepKeycode();
    void stepInstruction();
    const DebugModel& debug() const { return m_debug; }
    void clearHeatmap();

    DebugLevel debugLevel() const { return m_debugLevel; }
    void cycleDebugLevel();
    const std::string& logText() const { return m_logText; }
    void clearLog();
    void dumpVars();
    void dumpScom();
    void dumpProg();
    void dumpMemory();

    bool manualTrace() const { return m_manualTrace; }
    void setManualTrace(bool on);

    // ── ASM overlay ──────────────────────────────────────────────────────────
    /// An overlay file's text (nullopt: it could not be read).
    void loadAsm(const std::optional<std::string>& text, const std::string& fileName);
    void runAsm();
    void clearAsm();
    const std::string& asmFileName() const { return m_asmFileName; }
    int asmWordCount() const { return static_cast<int>(m_asmWords.size()); }
    const std::string& asmStatus() const { return m_asmStatus; }
    bool asmActive() const { return m_asmActive; }

private:
    struct Events;
    void emitChanged(uint32_t c) { if (c) m_platform.changed(c); }
    /// Shared start of both resets: stop playback, unfreeze, drop the overlay, card and cue card.
    void beginReset();
    void refreshCueCard();
    void checkProgramNumber();
    void refreshLog();
    void log(const std::vector<std::string>& lines);
    std::optional<std::vector<uint8_t>> loadConstantMemory();
    void applyState(const LoadStateResult& parsed);
    void configureTraceLocation();
    void onFrozenView(uint64_t freezeGeneration, FrozenViewReason reason);
    void pullDebugState();
    /// The card in the reader now.
    struct CardPass {
        int side = 0;          ///< of the fitted card
        bool queued = false;   ///< a fitted card fed by ArmCard: / InsertCard:
        std::optional<std::string> memoryKey;  ///< a mem: card: a written bank goes to m_memoryCards
    };
    /// No card fitted or in the reader, no cue card, no program shown.
    void clearCardAndCue();
    /// A preset's cue card takes over the cutout, from any fitted card.
    void adoptPresetCue(const std::optional<CueCardContent>& cue);
    bool canFit() const;
    void fit(const std::string& path, const std::string& fileName, CardDocument doc, bool fresh);
    bool feed(int side, bool queued);
    /// A fitted card, not covered by a module's cue card.
    bool cardOnShow() const { return m_fitted && m_activeProgram <= 0; }
    /// The machine wrote `written` to a side of the fitted card: merge and save it.
    void writeFittedSide(int side, const std::vector<uint8_t>& written, bool queued);
    /// What the cutout shows for the fitted card: its cue card with the corners' numbers.
    CueCardContent fittedCueCard() const;
    /// Put a bank image (empty: a blank card) into the reader.
    void startSwipe(const std::vector<uint8_t>& data, const CardPass& pass);
    /// KEYSTROKES ArmCard: / InsertCard: — feed the next queued card when the machine takes it.
    void feedQueuedCard();
    /// A preset's card has left the reader (or never got in): tell playback if it waits.
    void queuedCardDone();
    /// A new preset or a reset: the previous preset's queued and mem: cards go (logged if unused).
    void dropPresetCards();
    void applyReloadStage(const ReloadStage& stage);
    /// A KEYSTROKES GUI control (PrinterTrace:, Freeze:, …), as its button does.
    void applyControl(const KeystrokeEvent& event);
    /// Run `f` on the UI thread unless the session that asked has been replaced
    /// (or this controller destroyed) by then.
    void onUi(uint64_t sessionGeneration, std::function<void()> f);

    Platform& m_platform;
    const Threading m_threading;
    ResourceReader m_roms;
    std::string m_cuecards;
    std::shared_ptr<bool> m_alive = std::make_shared<bool>(true);
    std::unique_ptr<Events> m_events;
    std::unique_ptr<EmulatorSession> m_session;
    uint64_t m_sessionGeneration = 0;
    Model m_model = Model::TI59;

    std::string m_moduleID;
    std::map<int, CueCardContent> m_moduleCards;
    ModuleMetadata m_moduleMetadata;
    std::optional<CueCardContent> m_cueCard;
    std::optional<CueCardContent> m_userCueCard;
    int m_activeProgram = 0;

    LedFrame m_display{};
    double m_calcOpacity = 0;
    bool m_fullSpeed = false;
    bool m_keystrokesPlaying = false;
    int m_heldKey = -1;
    bool m_suspendedRunning = false;

    std::vector<std::string> m_printerLines;
    std::vector<PrinterCodeLine> m_printerCodeLines;
    bool m_printerConnected = true;

    std::string m_cardFileName = "card.U59";  ///< the fitted card's, or the last one's in the reader
    /// The card in the cutout, while it is out of its sleeve.
    struct FittedCard {
        std::string path;
        CardDocument doc;
        bool fresh = false;  ///< no write yet: the first one replaces whatever is at `path`
    };
    std::optional<FittedCard> m_fitted;
    std::optional<CueCardContent> m_presetCue;  ///< the preset's own cue card: goes onto cards it writes
    std::optional<CardPass> m_pass;
    /// mem: cards of the loaded preset, by the name after "mem:": the bank
    /// last written to it, and the cue card shown then.
    struct MemoryCard { std::vector<uint8_t> bank; std::optional<CueCardContent> cueCard; };
    std::map<std::string, MemoryCard> m_memoryCards;
    bool m_queuedCardInReader = false;                ///< an InsertCard: card: playback waits for it

    bool m_liveDebugEnabled = false;
    bool m_cpuDebugEnabled = false;
    DebugState m_debugState;
    DebugModel m_debug;
    DebugLevel m_debugLevel = DebugLevel::Off;
    std::string m_logText;
    bool m_manualTrace = false;

    std::vector<uint16_t> m_asmWords;
    std::string m_asmFileName = "No file selected";
    std::string m_asmStatus = "Load a hex opcode file and press Run.";
    bool m_asmActive = false;

    using Clock = std::chrono::steady_clock;
    Clock::time_point m_nextProgramCheck, m_nextLogRefresh;
    std::optional<Clock::time_point> m_persistDue;
    std::string m_persistedText;
};

} // namespace cu59
