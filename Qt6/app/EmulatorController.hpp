#pragma once
#include "AsmOverlay.hpp"
#include "CardFile.hpp"
#include "CueCard.hpp"
#include "DebugLog.hpp"
#include "DebugSnapshots.hpp"
#include "EmulatorSession.hpp"
#include "ModuleCatalog.hpp"
#include "ModuleImage.hpp"
#include "RomHeatmap.hpp"
#include "StateFile.hpp"
#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVector>
#include <array>
#include <memory>
#include <optional>

// The Qt counterpart of App/EmulatorViewModel.swift: owns one
// cu59::EmulatorSession per machine, forwards user actions to it, polls it at
// 60 Hz and publishes state through signals. Session events arrive on the
// session's threads and are re-posted to the GUI thread. Everything that
// isn't UI state comes from Shared/ — see CLAUDE.md § "Frontend Parity".
class EmulatorController : public QObject {
    Q_OBJECT
public:
    enum class CardState { NoCard, Swiping };
    enum class DebugLevel { Off = 0, Info = 1, Debug = 2 };
    enum class FreezePanel { None, Cpu, Calculator };

    explicit EmulatorController(QObject* parent = nullptr);
    ~EmulatorController() override;

    // ── Machine ──────────────────────────────────────────────────────────────
    void start(cu59::Model model);
    cu59::Model model() const { return m_model; }
    void resetMachine();
    void cleanResetMachine();
    void persistConstantMemory();
    QString moduleID() const { return m_moduleID; }
    void selectModule(const QString& moduleID);
    QVector<cu59::ModuleMetadata> allModules() const;

    // ── Display ──────────────────────────────────────────────────────────────
    const DisplaySnapshot& display() const { return m_display; }
    double calcIndicatorOpacity() const { return m_calcOpacity; }
    void setFullSpeed(bool on);
    bool fullSpeed() const { return m_fullSpeed; }
    bool keystrokesPlaying() const { return m_keystrokesPlaying; }
    const std::optional<cu59::CueCardContent>& cueCard() const { return m_cueCard; }

    // ── Keys (0-based row 0–8, col 0–4, or matrix codes) ─────────────────────
    void pressKey(int row, int col);
    void releaseKey(int row, int col);
    void keyboardDown(const std::vector<uint8_t>& codes);
    void keyboardUp();
    void keyboardRelease();
    int keyboardHeldKey() const { return m_heldKey; }

    // ── Printer ──────────────────────────────────────────────────────────────
    const QStringList& printerLines() const { return m_printerLines; }
    const QVector<PrinterCodeLine>& printerCodeLines() const { return m_printerCodeLines; }
    bool printerConnected() const { return m_printerConnected; }
    bool printerTrace() const { return m_printerTrace; }
    void setPrinterConnected(bool connected);
    void togglePrinterTrace();
    void pressPrinterPrint(bool pressed);
    void pressPrinterAdv(bool pressed);
    void cutPaper();

    // ── Card reader ──────────────────────────────────────────────────────────
    CardState cardState() const { return m_cardState; }
    QString cardFileName() const { return m_cardFileName; }
    void insertCard(const QString& path);
    void insertBlankCard(const QString& savePath);
    void ejectCard();

    // ── State files ──────────────────────────────────────────────────────────
    void loadStateFile(const QString& path);

    // ── Debugger ─────────────────────────────────────────────────────────────
    void setLiveDebugEnabled(bool on);
    void setCpuDebugEnabled(bool on);
    bool isFrozen() const { return m_freezePanel != FreezePanel::None; }
    FreezePanel freezeOwner() const { return m_freezePanel; }
    bool pendingFreezeOnPCChange() const { return m_pendingPcFreeze; }
    bool pendingCpuScanLoopFreeze() const { return m_pendingScanFreeze; }
    void freeze(FreezePanel owner);
    void unfreeze();
    void freezeOnNextPCChange();
    void freezeOnScanLoopExit();
    void disarmPcChangeFreeze();
    void disarmScanLoopFreeze();
    void stepKeycode();
    void stepFrozen();

    const cu59::LiveDebugSnapshot& liveSnapshot() const { return m_liveSnapshot; }
    const std::vector<cu59::StepEntry>& programListing() const { return m_programListing; }
    cu59::ProgramSource programListingSource() const { return m_listingSource; }
    /// Running: the last 32 instructions; frozen: the whole ring plus the next.
    const std::vector<cu59::InspectorEntry>& cpuHistory() const { return m_cpuHistory; }
    const std::vector<uint32_t>& heatmapCounts() const { return m_heatmap.counts(); }
    void clearHeatmap();

    DebugLevel debugLevel() const { return m_debugLevel; }
    void cycleDebugLevel();
    QString logText() const { return m_logText; }
    void clearLog();
    void dumpVars();
    void dumpScom();
    void dumpProg();
    void dumpMemory();

    bool traceAvailable() const { return true; }
    bool manualTrace() const { return m_manualTrace; }
    void setManualTrace(bool on);

    QString asmFileName() const { return m_asmFileName; }
    int asmWordCount() const { return static_cast<int>(m_asmWords.size()); }
    QString asmStatus() const { return m_asmStatus; }
    bool asmOverlayActive() const { return m_asmActive; }
    void loadAsmFile(const QString& path);
    void runAsmOverlay();
    void clearAsmOverlay();

signals:
    void modelChanged();
    void displayChanged();
    void cueCardChanged();
    void printerChanged();
    void cardStateChanged();
    void heldKeyChanged();
    void runStateChanged();      ///< freeze, armed freezes, full speed, playback
    void liveSnapshotChanged();
    void cpuChanged();
    void heatmapChanged();
    void logChanged();
    void asmChanged();
    void traceChanged();
    void errorOccurred(const QString& title, const QString& message);

private:
    /// Session events, called on the session's threads; each re-posts itself
    /// to the GUI thread.
    struct SessionListener : cu59::EmulatorSession::Listener {
        EmulatorController* c;
        explicit SessionListener(EmulatorController* controller) : c(controller) {}
        void breakpointHit(uint16_t pc) override;
        void freezeFired(cu59::FreezeOwner owner) override;
        void heldKeyChanged(int highlightID) override;
        void fullSpeedChanged(bool on) override;
        void playbackStarted() override;
        void playbackFinished() override;
        void togglePrinterTrace() override;
        void logLine(const std::string& line) override;
        void scriptedTraceFailed(const std::string& fileName) override;
        void scriptedTraceChanged(bool open) override;
        void batchDone() override;
    };
    SessionListener m_listener{this};

    template <class F> void onGui(F&& f) { QMetaObject::invokeMethod(this, std::forward<F>(f), Qt::QueuedConnection); }

    void tick();
    void checkProgramNumber();
    void refreshLog();
    void updateTraceFlags();
    void resetHeatmapBaseline();
    void refreshCueCard();
    void buildLive();
    void captureInspector();
    void applyParsedState(const cu59::LoadStateResult& parsed);
    void error(const QString& title, const QString& message) { emit errorOccurred(title, message); }
    void logLines(const std::vector<std::string>& lines);
    std::optional<std::vector<uint8_t>> loadConstantMemory();
    void saveCard(const std::vector<uint8_t>& data, const QString& path);
    cu59::ResourceReader romReader() const;

    cu59::Model m_model = cu59::Model::TI59;
    std::unique_ptr<cu59::EmulatorSession> m_session;
    QString m_moduleID;
    cu59::ModuleImage m_moduleImage;
    std::map<int, cu59::CueCardContent> m_moduleCards;
    cu59::ModuleMetadata m_moduleMetadata;
    std::vector<uint8_t> m_romCache;

    QTimer m_frameTimer, m_programTimer, m_logTimer, m_persistTimer;
    std::atomic<bool> m_persistPending{false};

    DisplaySnapshot m_display{};
    double m_calcOpacity = 0;
    bool m_fullSpeed = false;
    bool m_keystrokesPlaying = false;
    int m_heldKey = -1;

    std::optional<cu59::CueCardContent> m_cueCard;
    std::optional<cu59::CueCardContent> m_userCueCard;
    int m_activeProgram = 0;

    QStringList m_printerLines;
    QVector<PrinterCodeLine> m_printerCodeLines;
    bool m_printerConnected = true;
    bool m_printerTrace = false;

    CardState m_cardState = CardState::NoCard;
    QString m_cardFileName = QStringLiteral("card.U59");
    QString m_pendingSavePath;

    bool m_liveDebugEnabled = false;
    bool m_cpuDebugEnabled = false;
    FreezePanel m_freezePanel = FreezePanel::None;
    bool m_pendingPcFreeze = false;
    bool m_pendingScanFreeze = false;
    bool m_scriptedTraceOpen = false;
    bool m_manualTrace = false;
    cu59::LiveDebugSnapshot m_liveSnapshot;
    std::vector<cu59::StepEntry> m_programListing;
    cu59::ProgramSource m_listingSource = cu59::ProgramSource::UserProgram;
    int m_lastLibMismatch = -1;
    std::vector<cu59::InspectorEntry> m_cpuHistory;
    cu59::RomHeatmap m_heatmap;

    DebugLevel m_debugLevel = DebugLevel::Off;
    cu59::RingLog m_log;
    QString m_logText;

    std::vector<uint16_t> m_asmWords;
    QString m_asmFileName = QStringLiteral("No file selected");
    QString m_asmStatus = QStringLiteral("Load a hex opcode file and press Run.");
    bool m_asmActive = false;
};
