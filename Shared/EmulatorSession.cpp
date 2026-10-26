#include "EmulatorSession.hpp"
#include "KeyMatrix.hpp"
#include <cmath>
#include <cstdio>

namespace cu59 {

uint32_t traceFlagsFor(const TraceConsumers& c) {
    uint32_t flags = TRACE_NONE;
    if (c.cpuPanelVisible || c.frozen || c.manualTrace || c.freezeArmed || c.scriptedTrace)
        flags |= TRACE_PC | TRACE_REGS_FULL;
    return flags;
}

EmulatorSession::EmulatorSession(Model model, const ResourceReader& roms, const std::optional<std::string>& moduleRomFile,
                                 Listener& listener, Threading threading)
    : m_model(model),
      m_listener(listener),
      m_machine(std::make_shared<TI59Machine>(toVariant(model))),
      m_freeze(model),
      m_manualTrace(model),
      m_scriptedTrace(model) {
    auto words = loadRom(model, roms);
    m_machine->loadROM(words.data(), words.size());
    if (moduleRomFile) loadModule(*moduleRomFile, roms);
    auto constants = loadConstants(model, roms);
    m_machine->loadConstants(constants.data(), constants.size());

    EmulationRunner::Callbacks cb;
    cb.freezeFired = [this](FreezeOwner owner) { onFreezeFired(owner); };
    cb.batchDone = [this] { m_ramDirty = true; };
    m_runner = std::make_unique<EmulationRunner>(*m_machine, model, m_freeze, std::move(cb), threading);
    m_keys = std::make_unique<KeySequencer>(model, static_cast<KeySequencer::Host&>(*this), threading);
}

EmulatorSession::~EmulatorSession() {
    m_keys.reset();    // stop key threads before the machine they press goes away
    m_runner.reset();  // joins the emulation thread
}

bool EmulatorSession::loadModule(const std::string& romFile, const ResourceReader& roms) {
    auto image = cu59::loadModule(romFile, roms);
    if (!image) return false;
    m_machine->loadLibrary(image->data(), image->size());
    m_moduleImage = std::move(*image);
    return true;
}

// Key input advances after every batch, at the time the batch ends, so a
// 100 ms hold is five batches and the wait for the scan loop is checked at
// each batch boundary; with the loop stopped (frozen), at `now`.
void EmulatorSession::pump(std::chrono::steady_clock::time_point now) {
    bool ran = false;
    m_runner->pump(now, [&](std::chrono::steady_clock::time_point t) {
        ran = true;
        m_keys->advance(t);
    });
    if (!ran) m_keys->advance(now);
}

void EmulatorSession::setFullSpeed(bool on) {
    if (m_runner->fullSpeed() == on) return;
    m_runner->setFullSpeed(on);
    m_listener.fullSpeedChanged(on);
}

void EmulatorSession::pressKey(uint8_t matrixCode) {
    if (!isValidMatrixCode(matrixCode)) return;
    m_manualTrace.writeKeyDown(static_cast<uint8_t>(matrixCode / 10 - 1), static_cast<uint8_t>(matrixCode % 10 - 1));
    pressMatrix(*m_machine, matrixCode);
}

void EmulatorSession::releaseKey(uint8_t matrixCode) {
    if (!isValidMatrixCode(matrixCode)) return;
    m_manualTrace.writeKeyUp(static_cast<uint8_t>(matrixCode / 10 - 1), static_cast<uint8_t>(matrixCode % 10 - 1));
    releaseMatrix(*m_machine, matrixCode);
}

// ── Debugger ─────────────────────────────────────────────────────────────────

DebugState EmulatorSession::debugState() const {
    std::lock_guard<std::mutex> lock(m_stateMutex);
    return m_state;
}

uint64_t EmulatorSession::setFrozenState(bool frozen, std::optional<FreezeOwner> owner) {
    if (frozen) {
        m_freeze.disarmPcChange();
        m_freeze.disarmScanLoopExit();
    }
    uint64_t generation;
    {
        std::lock_guard<std::mutex> lock(m_stateMutex);
        m_state.frozen = frozen;
        m_state.owner = frozen ? owner : std::nullopt;
        if (frozen) m_state.pcChangeArmed = m_state.scanLoopExitArmed = false;
        generation = ++m_state.generation;
        m_frozen = frozen;
    }
    applyTraceFlags();
    return generation;
}

// The loop has exited; the freeze is applied here, before any listener runs,
// so the key sequencer never sees a stopped machine as running.
void EmulatorSession::onFreezeFired(FreezeOwner owner) {
    uint64_t generation = setFrozenState(true, owner);
    // CALCULATOR freezes at a step dispatch: prepare the next step's display state.
    if (owner == FreezeOwner::Calculator) m_machine->beginNextStep();
    m_listener.debugStateChanged();
    m_listener.frozenViewReady(generation, FrozenViewReason::FreezeFired);
}

void EmulatorSession::freeze(FreezeOwner owner) {
    stop();
    uint64_t generation = setFrozenState(true, owner);
    // Runs after the loop has exited (the job queue is serial).
    post([this, generation] {
        m_machine->stepUntilNextKeycode();
        m_machine->beginNextStep();
        m_listener.frozenViewReady(generation, FrozenViewReason::Freeze);
    });
}

void EmulatorSession::freezeInPlace(FreezeOwner owner) { setFrozenState(true, owner); }

void EmulatorSession::resume() {
    setFrozenState(false, std::nullopt);
    start();
}

void EmulatorSession::clearFreeze() { setFrozenState(false, std::nullopt); }

void EmulatorSession::armPcChange() {
    m_freeze.armPcChange();  // disarms the scan-loop exit
    {
        std::lock_guard<std::mutex> lock(m_stateMutex);
        m_state.pcChangeArmed = true;
        m_state.scanLoopExitArmed = false;
    }
    applyTraceFlags();
}

void EmulatorSession::armScanLoopExit() {
    m_freeze.armScanLoopExit(m_machine->pc());  // disarms the step-boundary freeze
    {
        std::lock_guard<std::mutex> lock(m_stateMutex);
        m_state.scanLoopExitArmed = true;
        m_state.pcChangeArmed = false;
    }
    applyTraceFlags();
}

void EmulatorSession::disarmPcChange() {
    m_freeze.disarmPcChange();
    {
        std::lock_guard<std::mutex> lock(m_stateMutex);
        m_state.pcChangeArmed = false;
    }
    applyTraceFlags();
}

void EmulatorSession::disarmScanLoopExit() {
    m_freeze.disarmScanLoopExit();
    {
        std::lock_guard<std::mutex> lock(m_stateMutex);
        m_state.scanLoopExitArmed = false;
    }
    applyTraceFlags();
}

void EmulatorSession::stepKeycode() {
    DebugState s = debugState();
    if (!s.frozen) return;
    post([this, generation = s.generation] {
        m_machine->stepUntilNextKeycode();
        m_machine->beginNextStep();
        m_listener.frozenViewReady(generation, FrozenViewReason::StepKeycode);
    });
}

void EmulatorSession::stepInstruction() {
    DebugState s = debugState();
    if (!s.frozen) return;
    post([this, generation = s.generation] {
        uint16_t prior = m_machine->pc();
        m_machine->step();
        // HOLD (WAIT Dn): the PC didn't advance — step until it does.
        for (int limit = 32; m_machine->pc() == prior && limit > 0; --limit) m_machine->step();
        m_machine->beginNextStep();
        m_listener.frozenViewReady(generation, FrozenViewReason::StepInstruction);
    });
}

void EmulatorSession::setCpuPanelVisible(bool visible) {
    {
        std::lock_guard<std::mutex> lock(m_stateMutex);
        m_cpuPanelVisible = visible;
    }
    applyTraceFlags();
}

// The one place the core's trace flags are set; any thread.
void EmulatorSession::applyTraceFlags() {
    std::lock_guard<std::mutex> lock(m_stateMutex);
    TraceConsumers c;
    c.cpuPanelVisible = m_cpuPanelVisible;
    c.frozen = m_state.frozen;
    c.freezeArmed = m_state.pcChangeArmed || m_state.scanLoopExitArmed;
    c.manualTrace = m_manualTrace.isOpen();
    c.scriptedTrace = m_scriptedTrace.isOpen();
    uint32_t flags = traceFlagsFor(c);
    if (m_machine->traceFlags() != flags) m_machine->setTraceFlags(flags);
}

bool EmulatorSession::openManualTrace(const std::filesystem::path& path, uint64_t maxBytes) {
    bool ok = m_manualTrace.open(path, maxBytes);
    applyTraceFlags();
    return ok;
}

void EmulatorSession::closeManualTrace() {
    if (!m_manualTrace.isOpen()) return;
    drainTrace();
    m_manualTrace.close();
    applyTraceFlags();
}

void EmulatorSession::setTraceLocation(const std::filesystem::path& dir, uint64_t maxBytes) {
    std::lock_guard<std::mutex> lock(m_traceMutex);
    m_traceDir = dir;
    m_traceMaxBytes = maxBytes;
}

EmulatorSession::DrainResult EmulatorSession::drainTrace() {
    std::lock_guard<std::mutex> lock(m_traceMutex);
    DrainResult r;
    auto& frames = m_drainBuf;
    uint32_t lost = 0;
    uint32_t n = m_machine->drainCpuFrames(frames.data(), static_cast<uint32_t>(frames.size()), &lost);
    if (lost) {
        m_manualTrace.writeLostGap(lost);
        m_scriptedTrace.writeLostGap(lost);
    }
    for (uint32_t i = 0; i < n; ++i) {
        bool manual = m_manualTrace.isOpen(), scripted = m_scriptedTrace.isOpen();
        if (!manual && !scripted) break;
        if (manual && !m_manualTrace.write(frames[i])) r.manualLimit = true;
        if (scripted && !m_scriptedTrace.write(frames[i])) r.scriptedLimit = true;
    }
    if (r.manualLimit || r.scriptedLimit) applyTraceFlags();  // a writer closed itself
    return r;
}

std::string EmulatorSession::elapsedReport() const {
    uint64_t now = m_machine->elapsedTicks();
    uint64_t base = m_elapseBaseline.load();
    uint64_t delta = now >= base ? now - base : 0;
    double seconds = static_cast<double>(delta) / info(m_model).instructionHz;
    long totalMs = std::lround(seconds * 1000);
    char buf[64];
    std::snprintf(buf, sizeof buf, "Elapsed: %ld:%02ld.%03ld", totalMs / 60000, (totalMs / 1000) % 60, totalMs % 1000);
    return buf;
}

// Switching files (or turning off) first flushes and closes the open scripted
// session, for a clean SESSION_END.
void EmulatorSession::scriptedTrace(const std::optional<std::string>& fileName) {
    if (m_scriptedTrace.isOpen()) {
        drainTrace();
        m_scriptedTrace.close();
    }
    bool opened = false;
    if (fileName) {
        std::filesystem::path dir;
        uint64_t maxBytes;
        {
            std::lock_guard<std::mutex> lock(m_traceMutex);
            dir = m_traceDir;
            maxBytes = m_traceMaxBytes;
        }
        opened = m_scriptedTrace.open(dir / *fileName, maxBytes);
        if (!opened) m_listener.scriptedTraceFailed(*fileName);
    }
    applyTraceFlags();
}

// A script always ends at regular speed, and never leaves a scripted trace
// running without its "Trace: Off".
void EmulatorSession::applyReload(const std::shared_ptr<const ReloadStage>& stage) {
    ++m_hostPending;
    m_listener.reloadRequested(stage);
}

void EmulatorSession::queueCard(const KeystrokeEvent& event) {
    QueuedCard card{event.cardName, event.card, event.kind == KeystrokeEvent::Kind::InsertCard};
    if (card.insertNow) ++m_hostPending;
    std::lock_guard<std::mutex> lock(m_cardMutex);
    m_queuedCards.push_back(std::move(card));
}

void EmulatorSession::hostDone() {
    int n = m_hostPending.load();
    while (n > 0 && !m_hostPending.compare_exchange_weak(n, n - 1)) {}
}

std::optional<QueuedCard> EmulatorSession::takeQueuedCard() {
    if (m_frozen.load()) return std::nullopt;
    const uint16_t pc = m_machine->pc();
    std::lock_guard<std::mutex> lock(m_cardMutex);
    if (m_queuedCards.empty()) return std::nullopt;
    const ModelInfo& mi = info(m_model);
    const QueuedCard& next = m_queuedCards.front();
    bool ready = next.insertNow ? mi.scanLoop.contains(pc) : mi.cardWait.contains(pc) && m_machine->isWaitingForCard();
    if (!ready) return std::nullopt;
    QueuedCard card = std::move(m_queuedCards.front());
    m_queuedCards.pop_front();
    return card;
}

std::vector<std::string> EmulatorSession::clearQueuedCards() {
    std::lock_guard<std::mutex> lock(m_cardMutex);
    std::vector<std::string> names;
    for (const auto& c : m_queuedCards) names.push_back(c.name);
    m_queuedCards.clear();
    return names;
}

void EmulatorSession::playbackFinished() {
    // Queued cards stay: a Write keyed in last, or a run the user starts
    // later, still gets its card. An InsertCard nobody waits for any more is
    // done.
    m_hostPending = 0;
    setFullSpeed(false);
    if (m_scriptedTrace.isOpen()) {
        drainTrace();
        m_scriptedTrace.close();
        applyTraceFlags();
    }
    m_listener.playbackFinished();
}

} // namespace cu59
