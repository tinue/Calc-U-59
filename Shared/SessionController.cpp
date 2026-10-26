#include "SessionController.hpp"
#include "AsmOverlay.hpp"
#include "CardFile.hpp"
#include "ConstantMemory.hpp"
#include "PrinterFont.hpp"
#include "StateApplier.hpp"
#include "TextUtil.hpp"
#include <algorithm>

namespace cu59 {

using namespace std::chrono_literals;

namespace {
// `on ? bit : 0` mixes an enum and an int (GCC -Wextra).
uint32_t changeIf(bool on, SessionController::Change bit) { return on ? static_cast<uint32_t>(bit) : 0u; }
}  // namespace

// Session events, on the session's threads; each hops to the UI thread and is
// dropped there if its session has been replaced meanwhile.
struct SessionController::Events : EmulatorSession::Listener {
    SessionController& c;
    const uint64_t generation;
    Events(SessionController& controller, uint64_t gen) : c(controller), generation(gen) {}

    void debugStateChanged() override {
        c.onUi(generation, [&c = c] { c.pullDebugState(); });
    }
    void frozenViewReady(uint64_t freezeGeneration, FrozenViewReason reason) override {
        c.onUi(generation, [&c = c, freezeGeneration, reason] { c.onFrozenView(freezeGeneration, reason); });
    }
    void heldKeyChanged(int id) override {
        c.onUi(generation, [&c = c, id] {
            c.m_heldKey = id;
            c.emitChanged(RunStateChanged);
        });
    }
    void fullSpeedChanged(bool on) override {
        c.onUi(generation, [&c = c, on] {
            if (c.m_fullSpeed == on) return;
            c.m_fullSpeed = on;
            c.emitChanged(RunStateChanged);
        });
    }
    void playbackStarted() override { setPlaying(true); }
    void playbackFinished() override { setPlaying(false); }
    void reloadRequested(const std::shared_ptr<const ReloadStage>& stage) override {
        c.onUi(generation, [&c = c, stage] { c.applyReloadStage(*stage); });
    }
    void controlRequested(const KeystrokeEvent& event) override {
        c.onUi(generation, [&c = c, event] { c.applyControl(event); });
    }
    void logLine(const std::string& line) override {
        c.onUi(generation, [&c = c, line] { c.log({line}); });
    }
    void scriptedTraceFailed(const std::string& fileName) override {
        c.onUi(generation, [&c = c, fileName] {
            c.m_platform.error("Trace error", "KEYSTROKES \"Trace: " + fileName + "\" could not create its file in " +
                                                  c.m_platform.traceLocation().dir.string());
        });
    }

private:
    void setPlaying(bool on) {
        c.onUi(generation, [&c = c, on] {
            c.m_keystrokesPlaying = on;
            c.emitChanged(RunStateChanged);
        });
    }
};

SessionController::SessionController(Platform& platform, ResourceReader roms, std::string cuecards, std::string moduleID,
                                     Threading threading)
    : m_platform(platform), m_threading(threading), m_roms(std::move(roms)), m_cuecards(std::move(cuecards)), m_moduleID(std::move(moduleID)) {}

SessionController::~SessionController() {
    m_alive.reset();  // drop events still queued for the UI thread
    persistConstantMemory();
    if (m_session) m_session->stop();
    m_session.reset();
}

void SessionController::onUi(uint64_t sessionGeneration, std::function<void()> f) {
    m_platform.runOnUiThread([alive = std::weak_ptr<bool>(m_alive), this, sessionGeneration, f = std::move(f)] {
        if (alive.expired() || sessionGeneration != m_sessionGeneration) return;
        f();
    });
}

// ── Machine ──────────────────────────────────────────────────────────────────

bool SessionController::startMachine(Model model) {
    persistConstantMemory();  // save TI-58C RAM before switching away
    if (m_session) {
        m_session->stop();
        m_session->sync([] {});  // the old loop has exited
    }
    setManualTrace(false);

    const uint64_t generation = m_sessionGeneration + 1;
    auto events = std::make_unique<Events>(*this, generation);
    auto romFile = moduleRomFile(m_cuecards, m_moduleID);
    std::unique_ptr<EmulatorSession> session;
    try {
        session = std::make_unique<EmulatorSession>(model, m_roms, romFile, *events, m_threading);
    } catch (const std::exception& e) {
        m_platform.error("ROM load error", e.what());
        if (m_session && !m_debugState.frozen) m_session->start();  // keep the calculator we had
        return false;
    }
    m_session = std::move(session);  // the old session goes first, then its events
    m_events = std::move(events);
    m_sessionGeneration = generation;
    m_model = model;
    m_platform.saveLastUsedModel(model);

    // A new machine: running, nothing armed, TRACE latch released, no card.
    m_debugState = m_session->debugState();
    m_userCueCard.reset();
    m_activeProgram = 0;
    m_cardState = CardState::NoCard;
    m_memoryCardInReader.reset();
    m_queuedCardInReader = false;
    m_memoryCards.clear();
    m_keystrokesPlaying = false;
    m_fullSpeed = false;
    m_heldKey = -1;

    auto cards = moduleCards(m_cuecards, m_moduleID);
    m_moduleCards = std::move(cards.cards);
    m_moduleMetadata = cards.metadata;
    if (!romFile || m_session->moduleImage().empty())
        m_platform.diagnostic("Solid-state module library was not loaded; continuing without library data");
    m_debug.attach(*m_session);
    if (!m_debug.moduleImageError().empty()) m_platform.diagnostic(m_debug.moduleImageError());

    TI59Machine& m = m_session->machine();
    m.setPrinterConnected(m_printerConnected);
    m.setDebugLevel(static_cast<uint8_t>(m_debugLevel));
    if (info(model).hasConstantMemory) {
        auto saved = loadConstantMemory();
        powerOn(m, model, saved ? &*saved : nullptr);
    }
    if (!m_asmWords.empty() && !m.loadDebugOverlay(m_asmWords.data(), m_asmWords.size())) {
        m_asmWords.clear();
        m_asmActive = false;
        m_asmStatus = "ASM overlay cleared (incompatible after model switch).";
    }
    configureTraceLocation();
    m_session->setCpuPanelVisible(m_cpuDebugEnabled);
    m_debug.resetHeatmapBaseline(m);
    refreshCueCard();
    m_session->start();
    emitChanged(ModelChanged | RunStateChanged | CardChanged | PrinterChanged | CueCardChanged | LiveChanged |
                CpuChanged | HeatmapChanged | AsmChanged | TraceChanged);
    return true;
}

void SessionController::beginReset() {
    m_session->cancelKeystrokes();
    resume();
    m_asmActive = false;
    m_cardState = CardState::NoCard;
    m_memoryCardInReader.reset();
    m_queuedCardInReader = false;
    dropPresetCards();
    m_userCueCard.reset();
    m_activeProgram = 0;
    refreshCueCard();
}

void SessionController::resetMachine() {
    if (!m_session) return;
    beginReset();
    // The printer's TRACE latch survives a reset, as on the hardware (the core keeps it).
    auto saved = info(m_model).hasConstantMemory ? loadConstantMemory() : std::nullopt;
    softReset(m_session->machine(), m_model, saved ? &*saved : nullptr);
    m_debug.resetHeatmapBaseline(m_session->machine());
    log({"Calculator Reset"});
    emitChanged(ModelChanged | CardChanged | AsmChanged | HeatmapChanged);
}

void SessionController::cleanResetMachine() {
    if (!m_session) return;
    beginReset();
    cleanReset(m_session->machine());
    m_debug.resetHeatmapBaseline(m_session->machine());
    persistConstantMemory();  // the zeroed state, at once
    log({"Clean Reset — all registers cleared"});
    emitChanged(ModelChanged | CardChanged | AsmChanged | HeatmapChanged);
}

void SessionController::suspend() {
    persistConstantMemory();
    m_suspendedRunning = m_session && m_session->isRunning();
    if (m_session) m_session->stop();
}

void SessionController::resumeAfterSuspend() {
    if (m_suspendedRunning && m_session) m_session->start();
    m_suspendedRunning = false;
}

bool SessionController::selectModule(const std::string& moduleID) {
    if (!m_session) return false;
    auto romFile = moduleRomFile(m_cuecards, moduleID);
    if (!romFile || !m_session->loadModule(*romFile, m_roms)) {
        m_platform.error("Module error", "Failed to load module ROM: " + moduleID);
        return false;
    }
    m_moduleID = moduleID;
    m_platform.saveModuleID(moduleID);
    m_debug.moduleChanged(*m_session);
    if (!m_debug.moduleImageError().empty()) m_platform.diagnostic(m_debug.moduleImageError());
    auto cards = moduleCards(m_cuecards, moduleID);
    m_moduleCards = std::move(cards.cards);
    m_moduleMetadata = cards.metadata;
    refreshCueCard();
    emitChanged(ModelChanged);
    return true;
}

void SessionController::changeModule(const std::string& moduleID) {
    if (moduleID != m_moduleID && selectModule(moduleID)) resetMachine();
}

// ── TI-58C constant memory ───────────────────────────────────────────────────

// Requested after every batch while running (debounced); the file is only
// written when its contents changed.
void SessionController::persistConstantMemory() {
    m_persistDue.reset();
    if (!m_session || !info(m_model).hasConstantMemory) return;
    std::vector<uint8_t> ram(kConstantMemoryBytes);
    m_session->machine().serialiseRAM(ram.data());
    std::string text = encodeConstantMemory(ram, m_userCueCard ? &*m_userCueCard : nullptr);
    if (text == m_persistedText) return;
    m_platform.writeConstantMemory(text);
    m_persistedText = std::move(text);
}

std::optional<std::vector<uint8_t>> SessionController::loadConstantMemory() {
    auto text = m_platform.readConstantMemory();
    if (!text) return std::nullopt;
    auto decoded = decodeConstantMemory(*text);
    if (!decoded) return std::nullopt;  // invalid file: the caller keeps zeroed RAM
    m_userCueCard = decoded->cueCard;
    refreshCueCard();
    return decoded->ram;
}

// ── 60 Hz frame ──────────────────────────────────────────────────────────────

void SessionController::tick(Clock::time_point now) {
    if (!m_session) return;
    m_session->pump(now);
    uint32_t changes = 0;
    FrameUpdate f = m_session->tick(static_cast<int>(m_debugLevel), m_cardState == CardState::Swiping);
    if (f.cardAutoEjected) ejectCard();  // the core ejected at CRD_OFF: save written data
    if (m_cardState == CardState::NoCard) feedQueuedCard();
    // Text and dot lines arrive independently: the core commits a line's text
    // at PRT_PRINT but its dot codes only when the print finishes, often a
    // frame later — so a frame can carry codes without text.
    m_printerLines.insert(m_printerLines.end(), f.printerLines.begin(), f.printerLines.end());
    m_printerCodeLines.insert(m_printerCodeLines.end(), f.printerCodeLines.begin(), f.printerCodeLines.end());
    if (!f.printerLines.empty() || !f.printerCodeLines.empty()) changes |= PrinterChanged;
    if (!f.logLines.empty()) m_debug.log().writeAll(f.logLines);

    if (m_session->takeRamDirty() && info(m_model).hasConstantMemory && !m_persistDue) m_persistDue = now + 500ms;
    if (m_persistDue && now >= *m_persistDue) persistConstantMemory();

    if (f.led != m_display) {
        m_display = f.led;
        changes |= DisplayChanged;
    }
    if (f.calcIndicatorOpacity != m_calcOpacity) {
        m_calcOpacity = f.calcIndicatorOpacity;
        changes |= DisplayChanged;
    }

    DebugModel::Update u = m_debug.tick(m_session->machine(), m_liveDebugEnabled, m_cpuDebugEnabled,
                                        m_debugState.frozen);
    if (u.live) changes |= LiveChanged;
    if (u.listing) changes |= ListingChanged;
    if (u.cpu) changes |= CpuChanged;
    if (u.heatmap) changes |= HeatmapChanged;
    if (u.diagnostic) m_platform.diagnostic(*u.diagnostic);

    if (m_session->needsDrain()) {
        auto r = m_session->drainTrace();
        if (r.manualLimit) {
            m_manualTrace = false;
            changes |= TraceChanged;
            m_platform.error("Trace stopped", "The trace file reached the " +
                                                  std::to_string(m_platform.traceLocation().maxBytes / 1'000'000) +
                                                  " MB size limit.");
        }
        if (r.scriptedLimit) m_platform.diagnostic("Scripted trace reached its size limit — trace stopped.");
    }

    if (now >= m_nextProgramCheck) {  // cue-card program detection, 2 Hz
        m_nextProgramCheck = now + 500ms;
        checkProgramNumber();
    }
    if (now >= m_nextLogRefresh) {  // LOG pane, 1 Hz
        m_nextLogRefresh = now + 1s;
        refreshLog();
    }
    emitChanged(changes);
}

void SessionController::checkProgramNumber() {
    int program = activeLibraryProgram(m_session->machine().snapshotCPU().SCOM[9]);
    if (program != m_activeProgram) {
        m_activeProgram = program;
        refreshCueCard();
    }
}

void SessionController::refreshCueCard() {
    auto card = resolveCueCard(m_activeProgram, m_moduleCards, m_moduleMetadata.title, m_moduleMetadata.id, m_userCueCard);
    if (card != m_cueCard) {
        m_cueCard = card;
        emitChanged(CueCardChanged);
    }
}

// ── Keys and speed ───────────────────────────────────────────────────────────

void SessionController::pressKey(uint8_t code) { if (m_session) m_session->pressKey(code); }
void SessionController::releaseKey(uint8_t code) { if (m_session) m_session->releaseKey(code); }
void SessionController::keyboardDown(const std::vector<uint8_t>& codes) { if (m_session) m_session->keyboardDown(codes); }
void SessionController::keyboardUp() { if (m_session) m_session->keyboardUp(); }
void SessionController::keyboardRelease() { if (m_session) m_session->keyboardRelease(); }

void SessionController::setFullSpeed(bool on) {
    if (m_fullSpeed == on) return;
    m_fullSpeed = on;
    if (m_session) m_session->setFullSpeed(on);
    emitChanged(RunStateChanged);
}

// ── Printer ──────────────────────────────────────────────────────────────────

void SessionController::setPrinterConnected(bool connected) {
    m_printerConnected = connected;
    if (m_session) m_session->machine().setPrinterConnected(connected);
    emitChanged(PrinterChanged);
}

void SessionController::togglePrinterConnection() {
    setPrinterConnected(!m_printerConnected);
    resetMachine();
}

void SessionController::togglePrinterTrace() {
    if (!m_session) return;
    TI59Machine& m = m_session->machine();
    m.setPrinterTrace(!m.printerTrace());
    emitChanged(PrinterChanged);
}

void SessionController::pressPrinterPrint(bool pressed) { if (m_session) m_session->machine().pressPrinterPrint(pressed); }
void SessionController::pressPrinterAdv(bool pressed) { if (m_session) m_session->machine().pressPrinterAdv(pressed); }

double SessionController::printerStripHeightUnits() const {
    double units = 0;
    for (size_t i = 0; i < m_printerLines.size(); ++i)
        units += PrinterGeometry::lineHeightUnits(m_printerLines[i].empty(),
                                                  i < m_printerCodeLines.size() ? &m_printerCodeLines[i] : nullptr);
    return units;
}

void SessionController::cutPaper() {
    m_printerLines.clear();
    m_printerCodeLines.clear();
    emitChanged(PrinterChanged | PaperCut);
}

// ── Card reader ──────────────────────────────────────────────────────────────

void SessionController::insertCard(const std::optional<std::vector<uint8_t>>& raw, const std::string& path,
                                   const std::string& fileName) {
    if (!m_session || m_cardState != CardState::NoCard) return;
    if (!raw) {
        m_platform.error("Card load error", "Could not read card file.");
        return;
    }
    auto decoded = decodeCardFile(*raw, fileName);
    if (!decoded.card) {
        m_platform.error("Card load error", decoded.error);
        return;
    }
    if (decoded.isText) {
        m_userCueCard = decoded.card->cueCard;
        refreshCueCard();
    }
    startSwipe(decoded.card->data, path, fileName);  // write back to `path` if the machine writes during this pass
}

void SessionController::insertBlankCard(const std::string& savePath, const std::string& fileName) {
    if (!m_session || m_cardState != CardState::NoCard) return;
    startSwipe({}, savePath, fileName);
}

void SessionController::startSwipe(const std::vector<uint8_t>& data, const std::string& savePath,
                                   const std::string& fileName) {
    m_pendingSavePath = savePath;
    m_cardFileName = fileName;
    m_cardState = CardState::Swiping;
    m_session->manualTrace().writeCardInsert();
    m_session->machine().insertCard(data.empty() ? nullptr : data.data(), data.size());
    emitChanged(CardChanged);
}

void SessionController::ejectCard() {
    if (!m_session || m_cardState != CardState::Swiping) {
        m_cardState = CardState::NoCard;
        emitChanged(CardChanged);
        return;
    }
    m_session->manualTrace().writeCardEject();
    std::vector<uint8_t> written = m_session->machine().cardEject();
    m_cardState = CardState::NoCard;
    if (!written.empty()) {
        if (m_memoryCardInReader) m_memoryCards[*m_memoryCardInReader] = {written, m_cueCard};
        else if (!m_pendingSavePath.empty()) saveCard(written, m_pendingSavePath);
    }
    m_memoryCardInReader.reset();
    queuedCardDone();
    emitChanged(CardChanged);
}

void SessionController::feedQueuedCard() {
    if (!m_session) return;
    auto card = m_session->takeQueuedCard();
    if (!card) return;
    m_queuedCardInReader = card->insertNow;
    if (isMemoryCardName(card->name)) {
        // A bank written to it earlier in the preset, else its CARD: block, else blank.
        std::string key(memoryCardKey(card->name));
        std::vector<uint8_t> bank;
        std::optional<CueCardContent> cueCard;
        if (auto it = m_memoryCards.find(key); it != m_memoryCards.end()) {
            bank = it->second.bank;
            cueCard = it->second.cueCard;
        } else if (card->definition) {
            bank = buildCardBank(*card->definition, m_session->machine().partitionProgramRegs());
            cueCard = card->definition->cueCard;
        }
        if (cueCard) {
            m_userCueCard = cueCard;
            refreshCueCard();
        }
        startSwipe(bank, "", card->name);
        m_memoryCardInReader = key;
        return;
    }
    std::string fileName = withDefaultCardExtension(card->name);
    Platform::CardFileRef file = m_platform.cardFile(fileName);
    if (!file.raw) {
        log({"KEYSTROKES: no card file " + fileName + " — a blank card goes in"});
        insertBlankCard(file.path, fileName);
    } else {
        insertCard(file.raw, file.path, fileName);
    }
    if (m_cardState == CardState::NoCard) queuedCardDone();  // the file could not be read
}

void SessionController::dropPresetCards() {
    if (!m_session) return;
    std::vector<std::string> lines;
    for (const auto& name : m_session->clearQueuedCards())
        lines.push_back("KEYSTROKES: card " + name + " was never read or written");
    if (!lines.empty()) log(lines);
    m_memoryCards.clear();
}

void SessionController::queuedCardDone() {
    if (!m_queuedCardInReader) return;
    m_queuedCardInReader = false;
    m_session->hostDone();
}

void SessionController::saveCard(const std::vector<uint8_t>& data, const std::string& path) {
    std::string text = encodeCardText(data, m_cueCard ? &*m_cueCard : nullptr);
    if (!m_platform.writeCard(path, text)) {
        m_platform.error("Card save error", "Card save failed: " + path);
        return;
    }
    m_cardFileName = std::filesystem::path(path).filename().string();
}

// ── State files (reference/SharedArchitecture.md § "State File Loading") ───────

void SessionController::loadStateFile(const std::optional<std::vector<uint8_t>>& raw) {
    const std::string title = "State file load error";
    if (!raw) {
        m_platform.error(title, "Cannot read file.");
        return;
    }
    std::string text(raw->begin(), raw->end());
    if (!isValidUtf8(text)) {
        m_platform.error(title, "File is not valid UTF-8 text — re-save it with UTF-8 encoding (a non-UTF-8 character, "
                                "e.g. a curly quote or em dash from a word processor, is the usual cause).");
        return;
    }
    const Model targetModel = stateFileModel(text, m_model);
    const ModelInfo& target = info(targetModel);
    LoadStateResult parsed = parseStateFile(text, target.maxStep(), target.hasConstantMemory);
    if (parsed.usesCardReader && !target.hasCardReader) {
        parsed.errors.push_back(std::string("CARD:, ArmCard: and InsertCard: need a card reader; the ") +
                                target.displayName + " has none.");
        auto& k = parsed.keystrokes;
        k.erase(std::remove_if(k.begin(), k.end(), [](const KeystrokeEvent& e) {
                    return e.kind == KeystrokeEvent::Kind::ArmCard || e.kind == KeystrokeEvent::Kind::InsertCard;
                }), k.end());
    }
    if (!parsed.errors.empty()) {
        std::string joined;
        for (const auto& e : parsed.errors) joined += (joined.empty() ? "" : "\n") + e;
        m_platform.error(title, joined);
    }
    if (targetModel != m_model && !startMachine(targetModel)) return;
    applyState(parsed);
}

void SessionController::applyState(const LoadStateResult& parsed) {
    if (!m_session) return;
    TI59Machine& m = m_session->machine();
    if (auto e = stateFilePartitionError(parsed, m_model)) {
        m_platform.error("State file load error", *e);
        return;
    }
    dropPresetCards();
    m_session->stop();
    m_session->clearFreeze();
    m_activeProgram = 0;
    m_session->sync([&] { cu59::applyState(m, parsed, m_model); });
    m_debug.resetHeatmapBaseline(m);  // fresh machine state: skip the power-on walk
    m_session->start();
    cutPaper();  // each loaded state starts with a blank strip
    if (parsed.solidStateModuleID && *parsed.solidStateModuleID != m_moduleID) selectModule(*parsed.solidStateModuleID);
    if (parsed.printerConnected) setPrinterConnected(*parsed.printerConnected);
    m_userCueCard = parsed.cueCard;
    refreshCueCard();
    persistConstantMemory();  // after the cue card: ti58c.mem keeps the file's card
    pullDebugState();
    emitChanged(RunStateChanged | HeatmapChanged);
    if (!parsed.keystrokes.empty()) {
        configureTraceLocation();
        m_session->playKeystrokes(parsed.keystrokes);
    }
}

void SessionController::applyControl(const KeystrokeEvent& e) {
    if (!m_session) return;
    using K = KeystrokeEvent::Kind;
    const FreezeOwner owner = e.panel == DebugPanel::Cpu ? FreezeOwner::Cpu : FreezeOwner::Calculator;
    switch (e.kind) {
    case K::PrinterTrace:
        m_session->machine().setPrinterTrace(e.on);
        emitChanged(PrinterChanged);
        break;
    case K::CutPaper: cutPaper(); break;
    case K::ShowPanel:
        if (!(m_asmActive && e.panel == DebugPanel::Calculator)) m_platform.showDebugPanel(e.panel);  // the overlay keeps the CPU tab
        break;
    case K::Freeze:
        if (!m_debugState.frozen) freeze(owner);
        break;
    case K::FreezeOnStart:
        if (!e.on) {
            disarmPcChange();
            disarmScanLoopExit();
        } else if (owner == FreezeOwner::Cpu) {
            armScanLoopExit();
        } else {
            armPcChange();
        }
        break;
    case K::Step:
        if (!m_debugState.frozen) {
            log({"KEYSTROKES: Step: ignored — the calculator is not frozen"});
            break;
        }
        for (int i = 0; i < e.count; ++i) owner == FreezeOwner::Cpu ? stepInstruction() : stepKeycode();
        break;
    case K::Resume: resume(); break;
    default: break;
    }
    m_session->hostDone();
}

void SessionController::applyReloadStage(const ReloadStage& stage) {
    if (!m_session) return;
    const ModelInfo& mi = info(m_model);
    if (stage.partitionMaxStep && *stage.partitionMaxStep > mi.maxStep()) {
        log({"KEYSTROKES: reload skipped — its partition (" + std::to_string(*stage.partitionMaxStep) + ") exceeds the " +
             mi.displayName + " maximum (" + std::to_string(mi.maxStep()) + ")"});
    } else {
        TI59Machine& m = m_session->machine();
        bool frozen = m_session->frozen();
        m_session->stop();
        m_session->sync([&] { applyReload(m, stage, m_model); });
        if (!frozen) m_session->start();
        if (stage.cueCard) {
            m_userCueCard = stage.cueCard;
            refreshCueCard();
        }
        persistConstantMemory();
        emitChanged(RunStateChanged);
    }
    m_session->hostDone();
}

// ── Debugger ─────────────────────────────────────────────────────────────────

void SessionController::pullDebugState() {
    if (!m_session) return;
    DebugState s = m_session->debugState();
    if (s == m_debugState) return;
    m_debugState = s;
    emitChanged(RunStateChanged);
}

void SessionController::onFrozenView(uint64_t freezeGeneration, FrozenViewReason reason) {
    if (!m_session) return;
    pullDebugState();
    // RESUME (or a new freeze) came first: this view is stale, and the machine may be running.
    if (!m_debugState.frozen || m_debugState.generation != freezeGeneration) return;
    DebugModel::Update u = m_debug.frozenView(m_session->machine(), reason);
    if (u.diagnostic) m_platform.diagnostic(*u.diagnostic);
    emitChanged(changeIf(u.live, LiveChanged) | changeIf(u.listing, ListingChanged) | changeIf(u.cpu, CpuChanged) |
                RunStateChanged);
}

void SessionController::setLiveDebugEnabled(bool on) {
    m_liveDebugEnabled = on;
    // Shown while frozen: the frozen view may predate it, so build it now.
    if (on && m_debugState.frozen && m_session) {
        DebugModel::Update u = m_debug.rebuildLive(m_session->machine(), true);
        emitChanged(changeIf(u.live, LiveChanged) | changeIf(u.listing, ListingChanged));
    }
}

void SessionController::setCpuDebugEnabled(bool on) {
    if (m_cpuDebugEnabled == on) return;
    m_cpuDebugEnabled = on;
    if (!m_session) return;
    // The heatmap shows activity since the panel became visible (no tracing
    // while hidden); a frozen heatmap is static, so keep it.
    if (on && !m_debugState.frozen) {
        m_debug.resetHeatmapBaseline(m_session->machine());
        emitChanged(HeatmapChanged);
    }
    m_session->setCpuPanelVisible(on);
}

void SessionController::freeze(FreezeOwner owner) {
    if (!m_session) return;
    m_asmActive = false;
    m_session->freeze(owner);
    pullDebugState();
    emitChanged(AsmChanged);
}

void SessionController::resume() {
    if (!m_session) return;
    m_session->resume();
    pullDebugState();
}

void SessionController::armPcChange() { if (m_session) { m_session->armPcChange(); pullDebugState(); } }
void SessionController::armScanLoopExit() { if (m_session) { m_session->armScanLoopExit(); pullDebugState(); } }
void SessionController::disarmPcChange() { if (m_session) { m_session->disarmPcChange(); pullDebugState(); } }
void SessionController::disarmScanLoopExit() { if (m_session) { m_session->disarmScanLoopExit(); pullDebugState(); } }
void SessionController::stepKeycode() { if (m_session) m_session->stepKeycode(); }
void SessionController::stepInstruction() { if (m_session) m_session->stepInstruction(); }

void SessionController::clearHeatmap() {
    m_debug.clearHeatmap();
    emitChanged(HeatmapChanged);
}

void SessionController::cycleDebugLevel() {
    m_debugLevel = static_cast<DebugLevel>((static_cast<int>(m_debugLevel) + 1) % 3);
    if (m_session) m_session->machine().setDebugLevel(static_cast<uint8_t>(m_debugLevel));
    emitChanged(LogChanged);
}

void SessionController::log(const std::vector<std::string>& lines) {
    m_debug.log().writeAll(lines);
    refreshLog();
}

void SessionController::refreshLog() {
    std::string text = m_debug.log().displayText();
    if (text == m_logText) return;
    m_logText = std::move(text);
    emitChanged(LogChanged);
}

void SessionController::clearLog() {
    m_debug.log().clear();
    m_logText.clear();
    emitChanged(LogChanged);
}

void SessionController::dumpVars() { if (m_session) log(cu59::dumpVars(m_session->machine())); }
void SessionController::dumpScom() { if (m_session) log(cu59::dumpScom(m_session->machine())); }
void SessionController::dumpProg() { if (m_session) log(cu59::dumpProg(m_session->machine())); }
void SessionController::dumpMemory() { if (m_session) log(cu59::dumpMemory(m_session->machine())); }

// ── Traces ───────────────────────────────────────────────────────────────────

void SessionController::configureTraceLocation() {
    if (!m_session) return;
    TraceLocation loc = m_platform.traceLocation();
    m_session->setTraceLocation(loc.dir, loc.maxBytes);
}

void SessionController::setManualTrace(bool on) {
    if (on == m_manualTrace) return;
    if (!m_session) {
        m_manualTrace = false;
        return;
    }
    if (on) {
        if (!m_platform.traceAvailable()) {
            m_platform.error("Trace error", "The trace location is not available.");
            return;
        }
        TraceLocation loc = m_platform.traceLocation();
        std::filesystem::path path = loc.dir / TraceWriter::baseFileName(m_model);
        if (!m_session->openManualTrace(path, loc.maxBytes)) {
            m_platform.error("Trace error", "Could not create " + path.string());
            return;
        }
        m_manualTrace = true;
    } else {
        m_manualTrace = false;
        m_session->closeManualTrace();
    }
    emitChanged(TraceChanged);
}

// ── ASM overlay ──────────────────────────────────────────────────────────────

void SessionController::loadAsm(const std::optional<std::string>& text, const std::string& fileName) {
    const std::string title = "ASM load error";
    if (!text) {
        m_asmStatus = "Could not read ASM file.";
        m_platform.error(title, m_asmStatus);
    } else {
        try {
            std::vector<uint16_t> words = parseAsmWords(*text);
            if (!m_session) {
                m_asmStatus = "Machine not initialized yet.";
            } else if (!m_session->machine().loadDebugOverlay(words.data(), words.size())) {
                m_asmStatus = "ASM program exceeds overlay range 0x1800-0x1FFF.";
                m_platform.error(title, m_asmStatus);
            } else {
                m_asmWords = std::move(words);
                m_asmFileName = fileName;
                m_asmStatus = "Loaded " + std::to_string(m_asmWords.size()) + " word(s) at 0x1800.";
            }
        } catch (const AsmParseError& e) {
            m_asmStatus = e.what();
            m_platform.error(title, m_asmStatus);
        }
    }
    emitChanged(AsmChanged);
}

void SessionController::runAsm() {
    if (m_asmWords.empty() || !m_session) {
        m_asmStatus = m_asmWords.empty() ? "No ASM overlay loaded." : "Machine not initialized yet.";
        emitChanged(AsmChanged);
        return;
    }
    const bool freezeOnStart = m_session->debugState().scanLoopExitArmed;
    m_session->stop();
    m_session->disarmPcChange();
    m_session->disarmScanLoopExit();
    m_session->clearFreeze();
    AsmRunResult r;
    m_session->sync([&] { r = runAsmOverlay(m_session->machine(), m_asmWords); });
    uint32_t changes = AsmChanged;
    if (!r.loaded) {
        m_asmStatus = "ASM program exceeds overlay range 0x1800-0x1FFF.";
        m_platform.error("ASM load error", m_asmStatus);
    } else if (r.entered) {
        m_asmStatus = "ASM entered at 0x1800 (" + std::to_string(r.steps) + " step(s)).";
        m_asmActive = true;
        if (freezeOnStart) {
            // FREEZE ON START was armed: freeze in place at the 0x1800 entry.
            m_session->freezeInPlace(FreezeOwner::Cpu);
            DebugModel::Update u = m_debug.frozenView(m_session->machine(), FrozenViewReason::Freeze);
            changes |= changeIf(u.live, LiveChanged) | changeIf(u.listing, ListingChanged) | changeIf(u.cpu, CpuChanged);
        } else {
            m_session->start();
        }
    } else {
        m_asmStatus = "ASM entry failed after " + std::to_string(r.steps) + " step(s).";
        m_platform.error("ASM load error", m_asmStatus);
    }
    pullDebugState();
    emitChanged(changes);
}

void SessionController::clearAsm() {
    bool wasActive = m_asmActive;
    if (m_session) m_session->machine().clearDebugOverlay();
    m_asmWords.clear();
    m_asmActive = false;
    m_asmStatus = "ASM overlay cleared.";
    // A running overlay would now execute the empty range: reset the machine.
    if (wasActive && m_session) {
        resume();
        m_session->machine().reset();
    }
    emitChanged(AsmChanged);
}

} // namespace cu59
