#include "EmulatorController.hpp"
#include "AppPaths.hpp"
#include "AppSettings.hpp"
#include "ConstantMemory.hpp"
#include "KeyMatrix.hpp"
#include "StateApplier.hpp"
#include "TextUtil.hpp"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <cstring>

namespace {

QString qs(const std::string& s) { return QString::fromStdString(s); }

std::optional<std::string> readResource(const QString& path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) return std::nullopt;
    return f.readAll().toStdString();
}

std::optional<std::vector<uint8_t>> readBytes(const QString& path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) return std::nullopt;
    QByteArray b = f.readAll();
    return std::vector<uint8_t>(b.begin(), b.end());
}

bool writeText(const QString& path, const std::string& text) {
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly)) return false;
    f.write(text.data(), static_cast<qint64>(text.size()));
    return f.commit();
}

std::string cuecardsText() { return readResource(QStringLiteral(":/roms/cuecards.txt")).value_or(""); }

} // namespace

EmulatorController::EmulatorController(QObject* parent) : QObject(parent) {
    m_frameTimer.setTimerType(Qt::PreciseTimer);
    m_frameTimer.setInterval(1000 / 60);
    connect(&m_frameTimer, &QTimer::timeout, this, &EmulatorController::tick);
    m_programTimer.setInterval(500);  // cue-card program detection, 2 Hz
    connect(&m_programTimer, &QTimer::timeout, this, &EmulatorController::checkProgramNumber);
    m_logTimer.setInterval(1000);     // log pane refresh, 1 Hz
    connect(&m_logTimer, &QTimer::timeout, this, &EmulatorController::refreshLog);
    m_persistTimer.setSingleShot(true);  // TI-58C persist debounce
    m_persistTimer.setInterval(500);
    connect(&m_persistTimer, &QTimer::timeout, this, [this] { persistConstantMemory(); });
    m_moduleID = AppSettings::resolvedSolidStateModuleID();
}

EmulatorController::~EmulatorController() {
    persistConstantMemory();
    if (m_session) m_session->stop();
    m_session.reset();
}

cu59::ResourceReader EmulatorController::romReader() const {
    return [](const std::string& name) { return readResource(QStringLiteral(":/roms/") + qs(name)); };
}

// ── Machine ──────────────────────────────────────────────────────────────────

void EmulatorController::start(cu59::Model model) {
    persistConstantMemory();  // save TI-58C RAM before switching away
    if (m_session) {
        m_session->stop();
        m_session->sync([] {});  // the old loop has exited
    }
    setManualTrace(false);
    m_session.reset();
    m_model = model;
    m_printerTrace = false;   // a new machine starts with the TRACE latch released
    m_userCueCard.reset();
    m_activeProgram = 0;
    m_freezePanel = FreezePanel::None;
    m_pendingPcFreeze = m_pendingScanFreeze = false;
    m_cardState = CardState::NoCard;
    AppSettings::setValue(AppSettings::kLastUsedModel, static_cast<int>(model));

    std::string catalog = cuecardsText();
    auto romFile = cu59::moduleRomFile(catalog, m_moduleID.toStdString());
    try {
        m_session = std::make_unique<cu59::EmulatorSession>(model, romReader(), romFile, m_listener);
    } catch (const std::exception& e) {
        error(QStringLiteral("ROM load error"), QString::fromUtf8(e.what()));
        emit modelChanged();
        return;
    }
    m_moduleImage = cu59::ModuleImage::parse(m_session->moduleImage());
    m_romCache.clear();
    auto cards = cu59::moduleCards(catalog, m_moduleID.toStdString());
    m_moduleCards = std::move(cards.cards);
    m_moduleMetadata = cards.metadata;

    TI59Machine& m = m_session->machine();
    m.setPrinterConnected(m_printerConnected);
    if (cu59::info(model).hasConstantMemory) {
        auto saved = loadConstantMemory();
        cu59::powerOn(m, model, saved ? &*saved : nullptr);
    }
    if (!m_asmWords.empty() && !m.loadDebugOverlay(m_asmWords.data(), m_asmWords.size())) {
        m_asmWords.clear();
        m_asmActive = false;
        m_asmStatus = QStringLiteral("ASM overlay cleared (incompatible after model switch).");
        emit asmChanged();
    }
    m_session->setTraceLocation(AppPaths::toFsPath(AppPaths::traceDir()),
                                static_cast<uint64_t>(AppSettings::resolvedTraceMaxMB()) * 1'000'000);
    updateTraceFlags();
    resetHeatmapBaseline();
    refreshCueCard();
    m_session->start();
    m_frameTimer.start();
    m_programTimer.start();
    m_logTimer.start();
    emit modelChanged();
    emit runStateChanged();
    emit cardStateChanged();
    emit printerChanged();
}

void EmulatorController::resetMachine() {
    if (!m_session) return;
    m_session->cancelKeystrokes();
    unfreeze();
    m_asmActive = false;
    m_cardState = CardState::NoCard;
    m_userCueCard.reset();
    m_activeProgram = 0;
    refreshCueCard();
    auto saved = cu59::info(m_model).hasConstantMemory ? loadConstantMemory() : std::nullopt;
    cu59::softReset(m_session->machine(), m_model, saved ? &*saved : nullptr);
    resetHeatmapBaseline();
    logLines({"Calculator Reset"});
    emit cardStateChanged();
    emit asmChanged();
}

void EmulatorController::cleanResetMachine() {
    if (!m_session) return;
    m_session->cancelKeystrokes();
    unfreeze();
    m_asmActive = false;
    m_cardState = CardState::NoCard;
    m_userCueCard.reset();
    m_activeProgram = 0;
    refreshCueCard();
    cu59::cleanReset(m_session->machine());
    resetHeatmapBaseline();
    persistConstantMemory();  // the zeroed state, at once
    logLines({"Clean Reset — all registers cleared"});
    emit cardStateChanged();
    emit asmChanged();
}

void EmulatorController::persistConstantMemory() {
    m_persistPending = false;
    if (!m_session || !cu59::info(m_model).hasConstantMemory) return;
    std::vector<uint8_t> ram(cu59::kConstantMemoryBytes);
    m_session->machine().serialiseRAM(ram.data());
    // Persisting is requested after every batch; skip the file write while nothing changed.
    std::string text = cu59::encodeConstantMemory(ram, m_userCueCard ? &*m_userCueCard : nullptr);
    if (text == m_persistedText) return;
    if (writeText(AppPaths::constantMemoryFile(), text)) m_persistedText = std::move(text);
}

std::optional<std::vector<uint8_t>> EmulatorController::loadConstantMemory() {
    auto text = readResource(AppPaths::constantMemoryFile());
    if (!text) return std::nullopt;
    auto decoded = cu59::decodeConstantMemory(*text);
    if (!decoded) return std::nullopt;  // invalid file: the caller keeps zeroed RAM
    m_userCueCard = decoded->cueCard;
    refreshCueCard();
    return decoded->ram;
}

QVector<cu59::ModuleMetadata> EmulatorController::allModules() const {
    auto all = cu59::allModuleMetadata(cuecardsText());
    return QVector<cu59::ModuleMetadata>(all.begin(), all.end());
}

void EmulatorController::selectModule(const QString& moduleID) {
    if (!m_session) return;
    std::string catalog = cuecardsText();
    auto romFile = cu59::moduleRomFile(catalog, moduleID.toStdString());
    if (!romFile || !m_session->loadModule(*romFile, romReader())) {
        error(QStringLiteral("Module error"), QStringLiteral("Failed to load module ROM: ") + moduleID);
        return;
    }
    m_moduleID = moduleID;
    AppSettings::setValue(AppSettings::kSolidStateModuleID, moduleID);
    m_moduleImage = cu59::ModuleImage::parse(m_session->moduleImage());
    m_romCache.clear();
    auto cards = cu59::moduleCards(catalog, moduleID.toStdString());
    m_moduleCards = std::move(cards.cards);
    m_moduleMetadata = cards.metadata;
}

// ── 60 Hz frame ──────────────────────────────────────────────────────────────

void EmulatorController::tick() {
    if (!m_session) return;
    cu59::FrameUpdate f = m_session->tick(static_cast<int>(m_debugLevel), m_cardState == CardState::Swiping);
    if (f.cardAutoEjected) ejectCard();  // the core ejected at CRD_OFF: save written data
    // Text and dot lines arrive independently: the core commits a line's text
    // at PRT_PRINT but its dot codes only when the print finishes, often a
    // frame later — so a frame can carry codes without text.
    for (const auto& l : f.printerLines) m_printerLines << qs(l);
    for (const auto& c : f.printerCodeLines) m_printerCodeLines << c;
    if (!f.printerLines.empty() || !f.printerCodeLines.empty()) emit printerChanged();
    if (!f.logLines.empty()) {
        for (const auto& l : f.logLines) m_log.write(l);
    }
    if (m_persistPending && !m_persistTimer.isActive()) m_persistTimer.start();

    bool changed = false;
    if (f.displayUpdated && std::memcmp(&f.display, &m_display, sizeof m_display) != 0) {
        m_display = f.display;
        changed = true;
    }
    if (f.calcIndicatorOpacity != m_calcOpacity) {
        m_calcOpacity = f.calcIndicatorOpacity;
        changed = true;
    }
    if (changed) emit displayChanged();

    if (m_liveDebugEnabled && !isFrozen()) buildLive();
    if (m_cpuDebugEnabled || isFrozen()) {
        auto frames = cu59::readTraceRing(m_session->machine());
        m_heatmap.ingest(frames.data(), frames.size());
        if (m_heatmap.publishTick()) emit heatmapChanged();
        // Rebuild the list only when new instructions ran.
        uint32_t newest = frames.empty() ? 0 : frames.back().seqno;
        if (!isFrozen() && newest != m_cpuHistorySeqno) {
            m_cpuHistorySeqno = newest;
            m_cpuHistory = cu59::recentInstructions(frames);
            emit cpuChanged();
        }
    }
    if (m_manualTrace || m_scriptedTraceOpen) {
        auto r = m_session->drainTrace();
        if (r.manualLimit) {
            error(QStringLiteral("Trace stopped"),
                  QStringLiteral("The trace file reached the %1 MB size limit.").arg(AppSettings::resolvedTraceMaxMB()));
            setManualTrace(false);
        }
        if (r.scriptedLimit) {
            m_scriptedTraceOpen = false;
            updateTraceFlags();
        }
    }
}

void EmulatorController::checkProgramNumber() {
    if (!m_session) return;
    CpuFrame cpu = m_session->machine().snapshotCPU();
    int program = cu59::activeLibraryProgram(cpu.SCOM[9]);
    if (program != m_activeProgram) {
        m_activeProgram = program;
        refreshCueCard();
    }
}

void EmulatorController::refreshCueCard() {
    auto card = cu59::resolveCueCard(m_activeProgram, m_moduleCards, m_moduleMetadata.title, m_moduleMetadata.id,
                                     m_userCueCard);
    if (card != m_cueCard) {
        m_cueCard = card;
        emit cueCardChanged();
    }
}

void EmulatorController::setFullSpeed(bool on) {
    if (m_fullSpeed == on) return;
    m_fullSpeed = on;
    if (m_session) m_session->setFullSpeed(on);
    emit runStateChanged();
}

// ── Keys ─────────────────────────────────────────────────────────────────────

void EmulatorController::pressKey(int row, int col) {
    if (m_session) m_session->pressKey(cu59::matrixCode(row, col));
}

void EmulatorController::releaseKey(int row, int col) {
    if (m_session) m_session->releaseKey(cu59::matrixCode(row, col));
}

void EmulatorController::keyboardDown(const std::vector<uint8_t>& codes) {
    if (m_session) m_session->keyboardDown(codes);
}

void EmulatorController::keyboardUp() {
    if (m_session) m_session->keyboardUp();
}

void EmulatorController::keyboardRelease() {
    if (m_session) m_session->keyboardRelease();
}

// ── Printer ──────────────────────────────────────────────────────────────────

void EmulatorController::setPrinterConnected(bool connected) {
    m_printerConnected = connected;
    m_printerTrace = false;  // attach/detach releases the TRACE latch (the core does too)
    if (m_session) m_session->machine().setPrinterConnected(connected);
    emit printerChanged();
}

void EmulatorController::togglePrinterTrace() {
    m_printerTrace = !m_printerTrace;
    if (m_session) m_session->machine().setPrinterTrace(m_printerTrace);
    emit printerChanged();
}

void EmulatorController::pressPrinterPrint(bool pressed) {
    if (m_session) m_session->machine().pressPrinterPrint(pressed);
}

void EmulatorController::pressPrinterAdv(bool pressed) {
    if (m_session) m_session->machine().pressPrinterAdv(pressed);
}

void EmulatorController::cutPaper() {
    m_printerLines.clear();
    m_printerCodeLines.clear();
    emit printerChanged();
}

// ── Card reader (flow: reference/AppArchitecture.md § "Card Reader Flow") ────

void EmulatorController::insertCard(const QString& path) {
    if (!m_session || m_cardState != CardState::NoCard) return;
    auto raw = readBytes(path);
    if (!raw) {
        error(QStringLiteral("Card load error"), QStringLiteral("Could not read card file."));
        return;
    }
    auto decoded = cu59::decodeCardFile(*raw, QFileInfo(path).fileName().toStdString());
    if (!decoded.card) {
        error(QStringLiteral("Card load error"), qs(decoded.error));
        return;
    }
    if (decoded.isText) {
        m_userCueCard = decoded.card->cueCard;
        refreshCueCard();
    }
    m_cardFileName = QFileInfo(path).fileName();
    m_pendingSavePath = path;  // write back if the machine writes during this pass
    m_cardState = CardState::Swiping;
    m_session->manualTrace().writeCardInsert();
    m_session->machine().insertCard(decoded.card->data.data(), decoded.card->data.size());
    emit cardStateChanged();
}

void EmulatorController::insertBlankCard(const QString& savePath) {
    if (!m_session || m_cardState != CardState::NoCard) return;
    m_pendingSavePath = savePath;
    m_cardFileName = QFileInfo(savePath).fileName();
    m_cardState = CardState::Swiping;
    m_session->manualTrace().writeCardInsert();
    m_session->machine().insertCard(nullptr, 0);
    emit cardStateChanged();
}

void EmulatorController::ejectCard() {
    if (!m_session || m_cardState != CardState::Swiping) {
        m_cardState = CardState::NoCard;
        emit cardStateChanged();
        return;
    }
    m_session->manualTrace().writeCardEject();
    std::vector<uint8_t> written = m_session->machine().cardEject();
    m_cardState = CardState::NoCard;
    emit cardStateChanged();
    if (!written.empty() && !m_pendingSavePath.isEmpty()) saveCard(written, m_pendingSavePath);
}

void EmulatorController::saveCard(const std::vector<uint8_t>& data, const QString& path) {
    std::string text = cu59::encodeCardText(data, m_cueCard ? &*m_cueCard : nullptr);
    if (!writeText(path, text)) {
        error(QStringLiteral("Card save error"), QStringLiteral("Card save failed: ") + path);
        return;
    }
    m_cardFileName = QFileInfo(path).fileName();
}

// ── State files (reference/AppArchitecture.md § "State File Loading") ───────

void EmulatorController::loadStateFile(const QString& path) {
    auto raw = readBytes(path);
    if (!raw) {
        error(QStringLiteral("State file load error"), QStringLiteral("Cannot read file."));
        return;
    }
    std::string text(raw->begin(), raw->end());
    if (!cu59::isValidUtf8(text)) {
        error(QStringLiteral("State file load error"),
              QStringLiteral("File is not valid UTF-8 text — re-save it with UTF-8 encoding."));
        return;
    }
    // SKIP-RESET suppresses the model switch, so MODEL: is ignored for parsing too.
    cu59::StateFilePrescan pre = cu59::prescanStateFile(text, m_model);
    const cu59::ModelInfo& target = cu59::info(pre.targetModel);
    cu59::LoadStateResult parsed = cu59::parseStateFile(text, target.maxStep(), target.hasConstantMemory);
    if (!parsed.errors.empty()) {
        QStringList lines;
        for (const auto& e : parsed.errors) lines << qs(e);
        error(QStringLiteral("State file load error"), lines.join(QLatin1Char('\n')));
    }
    if (pre.targetModel != m_model) start(pre.targetModel);
    applyParsedState(parsed);
}

void EmulatorController::applyParsedState(const cu59::LoadStateResult& parsed) {
    if (!m_session) return;
    TI59Machine& m = m_session->machine();
    if (parsed.skipReset) {
        // Only partition (if explicit), program, registers, cue card, keystrokes.
        m_session->stop();
        m_freezePanel = FreezePanel::None;
        m_session->sync([&] { cu59::applySkipResetState(m, parsed, m_model); });
        m_session->start();
        if (cu59::info(m_model).hasConstantMemory) persistConstantMemory();
        if (parsed.cueCard) {
            m_userCueCard = parsed.cueCard;
            refreshCueCard();
        }
    } else {
        if (auto e = cu59::stateFilePartitionError(parsed, m_model)) {
            error(QStringLiteral("State file load error"), qs(*e));
            return;
        }
        m_session->stop();
        m_freezePanel = FreezePanel::None;
        m_activeProgram = 0;
        m_session->sync([&] { cu59::applyState(m, parsed, m_model); });
        resetHeatmapBaseline();
        m_session->start();
        cutPaper();  // each loaded state starts with a blank strip
        persistConstantMemory();
        if (parsed.solidStateModuleID && qs(*parsed.solidStateModuleID) != m_moduleID)
            selectModule(qs(*parsed.solidStateModuleID));
        if (parsed.printerConnected) setPrinterConnected(*parsed.printerConnected);
        m_userCueCard = parsed.cueCard;
        refreshCueCard();
    }
    emit runStateChanged();
    if (!parsed.keystrokes.empty()) {
        m_session->setTraceLocation(AppPaths::toFsPath(AppPaths::traceDir()),
                                    static_cast<uint64_t>(AppSettings::resolvedTraceMaxMB()) * 1'000'000);
        m_session->playKeystrokes(parsed.keystrokes);
    }
}

// ── Debugger ─────────────────────────────────────────────────────────────────

void EmulatorController::updateTraceFlags() {
    if (!m_session) return;
    cu59::TraceConsumers c;
    c.cpuPanelVisible = m_cpuDebugEnabled;
    c.frozen = isFrozen();
    c.manualTrace = m_manualTrace;
    c.freezeArmed = m_pendingPcFreeze || m_pendingScanFreeze;
    c.scriptedTrace = m_scriptedTraceOpen;
    uint32_t flags = cu59::traceFlagsFor(c);
    TI59Machine& m = m_session->machine();
    if (m.traceFlags() != flags) m.setTraceFlags(flags);
}

void EmulatorController::resetHeatmapBaseline() {
    m_heatmap.clear();
    if (m_session) {
        auto frames = cu59::readTraceRing(m_session->machine());
        if (!frames.empty()) m_heatmap.resetBaseline(frames.back().seqno);
    }
    emit heatmapChanged();
}

void EmulatorController::clearHeatmap() {
    m_heatmap.clear();
    emit heatmapChanged();
}

void EmulatorController::setLiveDebugEnabled(bool on) {
    m_liveDebugEnabled = on;
    // Shown while frozen: freeze() skipped the build, so do it now.
    if (on && isFrozen()) buildLive();
}

void EmulatorController::setCpuDebugEnabled(bool on) {
    if (m_cpuDebugEnabled == on) return;
    m_cpuDebugEnabled = on;
    // The heatmap shows activity since the panel became visible (no tracing
    // while hidden); a frozen heatmap is static, so keep it.
    if (on && !isFrozen()) resetHeatmapBaseline();
    updateTraceFlags();
}

void EmulatorController::buildLive() {
    if (!m_session) return;
    cu59::LiveDebugBuild b = cu59::buildLiveSnapshot(m_session->machine(), m_model, m_moduleImage, m_romCache, isFrozen());
    if (b.libProgramMismatch && b.libProgramMismatch->second != m_lastLibMismatch) {
        m_lastLibMismatch = b.libProgramMismatch->second;
        qDebug("Library exec PC resolves to Pgm %d but SCOM[9] says Pgm %d", b.libProgramMismatch->first,
               b.libProgramMismatch->second);
    }
    // solidStateReturn shows a raw CROM address: keep the listing (stepKeycode advances it).
    if (b.snap.programSource != cu59::ProgramSource::SolidStateReturn) {
        m_programListing = cu59::programListing(b.sourceKeycodes, b.argSteps, b.snap.currentStep);
        m_listingSource = b.snap.programSource;
    }
    if (b.snap != m_liveSnapshot) {
        m_liveSnapshot = std::move(b.snap);
        emit liveSnapshotChanged();
    }
}

void EmulatorController::captureInspector() {
    if (!m_session) return;
    m_cpuHistory = cu59::inspectorHistory(m_session->machine());
    m_cpuHistorySeqno = 0;
    emit cpuChanged();
}

void EmulatorController::freeze(FreezePanel owner) {
    if (!m_session) return;
    m_session->stop();
    m_freezePanel = owner;
    m_session->setFrozen(true);
    m_asmActive = false;
    disarmPcChangeFreeze();
    disarmScanLoopFreeze();
    updateTraceFlags();
    TI59Machine& m = m_session->machine();
    // Advance to the next keycode boundary on the emulation thread (after the
    // loop has exited), then capture the state on the GUI thread.
    m_session->post([this, &m] {
        m.stepUntilNextKeycode();
        onGui([this, &m] {
            m.beginNextStep();
            buildLive();
            captureInspector();
        });
    });
    emit runStateChanged();
    emit asmChanged();
}

void EmulatorController::unfreeze() {
    m_freezePanel = FreezePanel::None;
    if (m_session) {
        m_session->setFrozen(false);
        m_session->start();
    }
    updateTraceFlags();
    emit runStateChanged();
}

void EmulatorController::freezeOnNextPCChange() {
    if (!m_session) return;
    disarmScanLoopFreeze();
    m_session->freezeControl().armPcChange(m_session->machine());
    m_pendingPcFreeze = true;
    updateTraceFlags();
    emit runStateChanged();
}

void EmulatorController::freezeOnScanLoopExit() {
    if (!m_session) return;
    disarmPcChangeFreeze();
    m_session->freezeControl().armScanLoopExit(m_session->machine().pc());
    m_pendingScanFreeze = true;
    updateTraceFlags();
    emit runStateChanged();
}

void EmulatorController::disarmPcChangeFreeze() {
    m_pendingPcFreeze = false;
    if (m_session) m_session->freezeControl().disarmPcChange();
    updateTraceFlags();
    emit runStateChanged();
}

void EmulatorController::disarmScanLoopFreeze() {
    m_pendingScanFreeze = false;
    if (m_session) m_session->freezeControl().disarmScanLoopExit();
    updateTraceFlags();
    emit runStateChanged();
}

void EmulatorController::stepKeycode() {
    if (!isFrozen() || !m_session) return;
    TI59Machine& m = m_session->machine();
    m_session->post([this, &m] {
        m.stepUntilNextKeycode();
        onGui([this, &m] {
            m.beginNextStep();
            CpuFrame cpu = m.snapshotCPU();
            auto source = cu59::programSourceFrom(cpu.SCOM[0][3], cpu.pc);
            if (source == cu59::ProgramSource::SolidStateReturn) {
                // SCOM[0] holds a raw CROM return address: keep the listing and
                // move the highlight onto the RTN just executed.
                for (size_t i = 0; i + 1 < m_programListing.size(); ++i) {
                    if (m_programListing[i].isCurrent) {
                        m_programListing[i].isCurrent = false;
                        m_programListing[i + 1].isCurrent = true;
                        break;
                    }
                }
            }
            buildLive();
            captureInspector();
        });
    });
}

void EmulatorController::stepFrozen() {
    if (!isFrozen() || !m_session) return;
    TI59Machine& m = m_session->machine();
    m_session->post([this, &m] {
        uint16_t prior = m.pc();
        uint32_t r = m.step();
        bool breakpoint = (r & 0x8000'0000u) != 0;
        // HOLD (WAIT Dn): the PC didn't advance — step until it does.
        for (int limit = 32; !breakpoint && m.pc() == prior && limit > 0; --limit)
            breakpoint = (m.step() & 0x8000'0000u) != 0;
        m.beginNextStep();
        onGui([this] { captureInspector(); });
    });
}

void EmulatorController::cycleDebugLevel() {
    m_debugLevel = static_cast<DebugLevel>((static_cast<int>(m_debugLevel) + 1) % 3);
    if (m_session) m_session->machine().setDebugLevel(static_cast<uint8_t>(m_debugLevel));
    emit logChanged();
}

void EmulatorController::logLines(const std::vector<std::string>& lines) {
    m_log.writeAll(lines);
    refreshLog();
}

void EmulatorController::refreshLog() {
    QString text = qs(m_log.displayText());
    if (text != m_logText) {
        m_logText = text;
        emit logChanged();
    }
}

void EmulatorController::clearLog() {
    m_log.clear();
    m_logText.clear();
    emit logChanged();
}

void EmulatorController::dumpVars() { if (m_session) logLines(cu59::dumpVars(m_session->machine(), m_model)); }
void EmulatorController::dumpScom() { if (m_session) logLines(cu59::dumpScom(m_session->machine())); }
void EmulatorController::dumpProg() { if (m_session) logLines(cu59::dumpProg(m_session->machine())); }
void EmulatorController::dumpMemory() { if (m_session) logLines(cu59::dumpMemory(m_session->machine())); }

void EmulatorController::setManualTrace(bool on) {
    if (on == m_manualTrace) return;
    if (!m_session) {
        m_manualTrace = false;
        return;
    }
    if (on) {
        QString path = AppPaths::traceDir() + QLatin1Char('/') + qs(cu59::TraceWriter::baseFileName(m_model));
        if (!m_session->manualTrace().open(AppPaths::toFsPath(path),
                                           static_cast<uint64_t>(AppSettings::resolvedTraceMaxMB()) * 1'000'000)) {
            error(QStringLiteral("Trace error"), QStringLiteral("Could not create ") + path);
            return;
        }
        m_manualTrace = true;
        updateTraceFlags();
    } else {
        m_manualTrace = false;
        updateTraceFlags();
        m_session->drainTrace();
        m_session->manualTrace().close();
    }
    emit traceChanged();
}

void EmulatorController::loadAsmFile(const QString& path) {
    auto text = readResource(path);
    if (!text) {
        m_asmStatus = QStringLiteral("Could not read ASM file.");
        error(QStringLiteral("ASM load error"), m_asmStatus);
        emit asmChanged();
        return;
    }
    try {
        std::vector<uint16_t> words = cu59::parseAsmWords(*text);
        if (!m_session || !m_session->machine().loadDebugOverlay(words.data(), words.size())) {
            m_asmStatus = QStringLiteral("ASM program exceeds overlay range 0x1800-0x1FFF.");
            error(QStringLiteral("ASM load error"), m_asmStatus);
        } else {
            m_asmWords = std::move(words);
            m_asmFileName = QFileInfo(path).fileName();
            m_asmStatus = QStringLiteral("Loaded %1 word(s) at 0x1800.").arg(m_asmWords.size());
        }
    } catch (const cu59::AsmParseError& e) {
        m_asmStatus = QString::fromUtf8(e.what());
        error(QStringLiteral("ASM load error"), m_asmStatus);
    }
    emit asmChanged();
}

void EmulatorController::runAsmOverlay() {
    if (m_asmWords.empty() || !m_session) {
        m_asmStatus = m_asmWords.empty() ? QStringLiteral("No ASM overlay loaded.") : QStringLiteral("Machine not initialized yet.");
        emit asmChanged();
        return;
    }
    bool freezeOnStart = m_pendingScanFreeze;
    m_session->stop();
    m_freezePanel = FreezePanel::None;
    disarmPcChangeFreeze();
    disarmScanLoopFreeze();
    cu59::AsmRunResult r;
    m_session->sync([&] { r = cu59::runAsmOverlay(m_session->machine(), m_asmWords); });
    if (!r.loaded) {
        m_asmStatus = QStringLiteral("ASM program exceeds overlay range 0x1800-0x1FFF.");
        error(QStringLiteral("ASM load error"), m_asmStatus);
    } else if (r.entered) {
        m_asmStatus = QStringLiteral("ASM entered at 0x1800 (%1 step(s)).").arg(r.steps);
        m_asmActive = true;
        if (freezeOnStart) {
            // FREEZE ON START was armed: freeze in place at the 0x1800 entry.
            m_freezePanel = FreezePanel::Cpu;
            m_session->setFrozen(true);
            updateTraceFlags();
            buildLive();
            captureInspector();
        } else {
            m_session->start();
        }
    } else {
        m_asmStatus = QStringLiteral("ASM entry failed after %1 step(s).").arg(r.steps);
        error(QStringLiteral("ASM load error"), m_asmStatus);
    }
    emit runStateChanged();
    emit asmChanged();
}

void EmulatorController::clearAsmOverlay() {
    bool wasActive = m_asmActive;
    if (m_session) m_session->machine().clearDebugOverlay();
    m_asmWords.clear();
    m_asmActive = false;
    m_asmStatus = QStringLiteral("ASM overlay cleared.");
    // A running overlay would now execute the empty range: reset the machine.
    if (wasActive && m_session) {
        unfreeze();
        m_session->machine().reset();
    }
    emit asmChanged();
}

// ── Session events (session threads → GUI thread) ────────────────────────────

void EmulatorController::SessionListener::breakpointHit(uint16_t) {
    c->onGui([c = c] { emit c->runStateChanged(); });
}

void EmulatorController::SessionListener::freezeFired(cu59::FreezeOwner owner) {
    c->onGui([c = c, owner] {
        if (!c->m_session) return;
        c->m_freezePanel = owner == cu59::FreezeOwner::Cpu ? FreezePanel::Cpu : FreezePanel::Calculator;
        c->m_session->setFrozen(true);
        c->m_pendingPcFreeze = c->m_pendingScanFreeze = false;
        c->updateTraceFlags();
        if (owner == cu59::FreezeOwner::Calculator) c->m_session->machine().beginNextStep();
        if (c->m_liveDebugEnabled || owner == cu59::FreezeOwner::Calculator) c->buildLive();
        c->captureInspector();
        emit c->runStateChanged();
    });
}

void EmulatorController::SessionListener::heldKeyChanged(int highlightID) {
    c->onGui([c = c, highlightID] {
        c->m_heldKey = highlightID;
        emit c->heldKeyChanged();
    });
}

void EmulatorController::SessionListener::fullSpeedChanged(bool on) {
    c->onGui([c = c, on] {
        if (c->m_fullSpeed == on) return;
        c->m_fullSpeed = on;
        emit c->runStateChanged();
    });
}

void EmulatorController::SessionListener::playbackStarted() {
    c->onGui([c = c] {
        c->m_keystrokesPlaying = true;
        emit c->runStateChanged();
    });
}

void EmulatorController::SessionListener::playbackFinished() {
    c->onGui([c = c] {
        c->m_keystrokesPlaying = false;
        emit c->runStateChanged();
    });
}

void EmulatorController::SessionListener::togglePrinterTrace() {
    c->onGui([c = c] { c->togglePrinterTrace(); });
}

void EmulatorController::SessionListener::logLine(const std::string& line) {
    c->onGui([c = c, line] { c->logLines({line}); });
}

void EmulatorController::SessionListener::scriptedTraceFailed(const std::string& fileName) {
    c->onGui([c = c, fileName] {
        c->error(QStringLiteral("Trace error"),
                 QStringLiteral("KEYSTROKES \"Trace: %1\" could not create its file in %2").arg(qs(fileName), AppPaths::traceDir()));
    });
}

void EmulatorController::SessionListener::scriptedTraceChanged(bool open) {
    c->onGui([c = c, open] {
        c->m_scriptedTraceOpen = open;
        c->updateTraceFlags();
    });
}

void EmulatorController::SessionListener::batchDone() {
    if (cu59::info(c->m_model).hasConstantMemory) c->m_persistPending = true;
}
