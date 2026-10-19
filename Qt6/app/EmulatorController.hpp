#pragma once
#include "SessionController.hpp"
#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVector>
#include <memory>

// The Qt face of Shared/SessionController (the Swift app's is
// App/EmulatorViewModel.swift): implements its Platform — the GUI thread,
// files in AppPaths, QSettings, error alerts — runs its 60 Hz tick and turns
// its change notifications into signals. Everything that isn't UI state
// lives in Shared/ — see CLAUDE.md § "Frontend Parity".
class EmulatorController : public QObject, private cu59::SessionController::Platform {
    Q_OBJECT
public:
    using CardState = cu59::SessionController::CardState;
    using DebugLevel = cu59::SessionController::DebugLevel;

    explicit EmulatorController(QObject* parent = nullptr);
    ~EmulatorController() override;

    // ── Machine ──────────────────────────────────────────────────────────────
    void start(cu59::Model model) { m_c->startMachine(model); }
    cu59::Model model() const { return m_c->model(); }
    void resetMachine() { m_c->resetMachine(); }
    void cleanResetMachine() { m_c->cleanResetMachine(); }
    void persistConstantMemory() { m_c->persistConstantMemory(); }
    QString moduleID() const { return QString::fromStdString(m_c->moduleID()); }
    /// Swap to a different module and soft-reset (no-op if unchanged).
    void changeModule(const QString& moduleID) { m_c->changeModule(moduleID.toStdString()); }
    QVector<cu59::ModuleMetadata> allModules() const;

    // ── Display ──────────────────────────────────────────────────────────────
    const cu59::LedFrame& display() const { return m_c->display(); }
    double calcIndicatorOpacity() const { return m_c->calcIndicatorOpacity(); }
    void setFullSpeed(bool on) { m_c->setFullSpeed(on); }
    const std::optional<cu59::CueCardContent>& cueCard() const { return m_c->cueCard(); }

    // ── Keys (0-based row 0–8, col 0–4, or matrix codes) ─────────────────────
    void pressKey(int row, int col);
    void releaseKey(int row, int col);
    void keyboardDown(const std::vector<uint8_t>& codes) { m_c->keyboardDown(codes); }
    void keyboardUp() { m_c->keyboardUp(); }
    void keyboardRelease() { m_c->keyboardRelease(); }
    int keyboardHeldKey() const { return m_c->heldKey(); }

    // ── Printer ──────────────────────────────────────────────────────────────
    const QStringList& printerLines() const { return m_printerLines; }
    const std::vector<PrinterCodeLine>& printerCodeLines() const { return m_c->printerCodeLines(); }
    double printerStripHeightUnits() const { return m_c->printerStripHeightUnits(); }
    bool printerConnected() const { return m_c->printerConnected(); }
    bool printerTrace() const { return m_c->printerTrace(); }
    void setPrinterConnected(bool connected) { m_c->setPrinterConnected(connected); }
    void togglePrinterTrace() { m_c->togglePrinterTrace(); }
    void pressPrinterPrint(bool pressed) { m_c->pressPrinterPrint(pressed); }
    void pressPrinterAdv(bool pressed) { m_c->pressPrinterAdv(pressed); }
    void cutPaper() { m_c->cutPaper(); }

    // ── Card reader ──────────────────────────────────────────────────────────
    CardState cardState() const { return m_c->cardState(); }
    QString cardFileName() const { return QString::fromStdString(m_c->cardFileName()); }
    void insertCard(const QString& path);
    void insertBlankCard(const QString& savePath);
    void ejectCard() { m_c->ejectCard(); }

    // ── State files ──────────────────────────────────────────────────────────
    void loadStateFile(const QString& path);

    // ── Debugger ─────────────────────────────────────────────────────────────
    void setLiveDebugEnabled(bool on) { m_c->setLiveDebugEnabled(on); }
    void setCpuDebugEnabled(bool on) { m_c->setCpuDebugEnabled(on); }
    bool isFrozen() const { return m_c->isFrozen(); }
    /// The panel that owns the freeze (none while running).
    std::optional<cu59::FreezeOwner> freezeOwner() const { return m_c->debugState().owner; }
    bool pendingFreezeOnPCChange() const { return m_c->debugState().pcChangeArmed; }
    bool pendingCpuScanLoopFreeze() const { return m_c->debugState().scanLoopExitArmed; }
    void freeze(cu59::FreezeOwner owner) { m_c->freeze(owner); }
    void unfreeze() { m_c->resume(); }
    void freezeOnNextPCChange() { m_c->armPcChange(); }
    void freezeOnScanLoopExit() { m_c->armScanLoopExit(); }
    void disarmPcChangeFreeze() { m_c->disarmPcChange(); }
    void disarmScanLoopFreeze() { m_c->disarmScanLoopExit(); }
    void stepKeycode() { m_c->stepKeycode(); }
    void stepFrozen() { m_c->stepInstruction(); }

    const cu59::LiveDebugSnapshot& liveSnapshot() const { return m_c->debug().live(); }
    const std::vector<cu59::StepEntry>& programListing() const { return m_c->debug().listing(); }
    cu59::ProgramSource programListingSource() const { return m_c->debug().listingSource(); }
    /// Running: the last 32 instructions; frozen: the whole ring plus the next.
    const std::vector<cu59::InspectorEntry>& cpuHistory() const { return m_c->debug().cpuHistory(); }
    const std::vector<uint32_t>& heatmapCounts() const { return m_c->debug().heatmapCounts(); }
    void clearHeatmap() { m_c->clearHeatmap(); }

    DebugLevel debugLevel() const { return m_c->debugLevel(); }
    void cycleDebugLevel() { m_c->cycleDebugLevel(); }
    QString logText() const { return QString::fromStdString(m_c->logText()); }
    void clearLog() { m_c->clearLog(); }
    void dumpVars() { m_c->dumpVars(); }
    void dumpScom() { m_c->dumpScom(); }
    void dumpProg() { m_c->dumpProg(); }
    void dumpMemory() { m_c->dumpMemory(); }

    bool manualTrace() const { return m_c->manualTrace(); }
    void setManualTrace(bool on) { m_c->setManualTrace(on); }

    QString asmFileName() const { return QString::fromStdString(m_c->asmFileName()); }
    int asmWordCount() const { return m_c->asmWordCount(); }
    QString asmStatus() const { return QString::fromStdString(m_c->asmStatus()); }
    bool asmOverlayActive() const { return m_c->asmActive(); }
    void loadAsmFile(const QString& path);
    void runAsmOverlay() { m_c->runAsm(); }
    void clearAsmOverlay() { m_c->clearAsm(); }

signals:
    void modelChanged();
    void displayChanged();
    void cueCardChanged();
    void printerChanged();
    void cardStateChanged();
    void runStateChanged();      ///< freeze, armed freezes, full speed, playback, held key
    void liveSnapshotChanged();
    void cpuChanged();
    void heatmapChanged();
    void logChanged();
    void asmChanged();
    void traceChanged();
    void errorOccurred(const QString& title, const QString& message);

private:
    // SessionController::Platform
    void runOnUiThread(std::function<void()> job) override;
    std::optional<std::string> readConstantMemory() override;
    void writeConstantMemory(const std::string& text) override;
    bool writeCard(const std::string& path, const std::string& text) override;
    cu59::SessionController::TraceLocation traceLocation() override;
    void saveLastUsedModel(cu59::Model model) override;
    void saveModuleID(const std::string& moduleID) override;
    void error(const std::string& title, const std::string& message) override;
    void diagnostic(const std::string& message) override;
    void changed(uint32_t changes) override;

    std::unique_ptr<cu59::SessionController> m_c;
    QTimer m_frameTimer;
    QStringList m_printerLines;  ///< the controller's text lines, as Qt types
};
