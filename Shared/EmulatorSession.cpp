#include "EmulatorSession.hpp"
#include "KeyMatrix.hpp"
#include <cmath>
#include <cstdio>

namespace cu59 {

uint32_t traceFlagsFor(const TraceConsumers& c) {
    uint32_t flags = TRACE_NONE;
    if (c.cpuPanelVisible || c.frozen || c.manualTrace || c.freezeArmed || c.scriptedTrace)
        flags |= TRACE_PC | TRACE_REGS_FULL;
    if (c.breakpoints) flags |= TRACE_BREAKPOINTS;
    return flags;
}

EmulatorSession::EmulatorSession(Model model, const ResourceReader& roms, const std::optional<std::string>& moduleRomFile,
                                 Listener& listener)
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
    cb.breakpoint = [this](uint16_t pc) { m_listener.breakpointHit(pc); };
    cb.freezeFired = [this](FreezeOwner owner) { m_listener.freezeFired(owner); };
    cb.batchDone = [this] { m_listener.batchDone(); };
    m_runner = std::make_unique<EmulationRunner>(*m_machine, model, m_freeze, std::move(cb));
    m_keys = std::make_unique<KeySequencer>(model, static_cast<KeySequencer::Host&>(*this));
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

void EmulatorSession::setTraceLocation(const std::filesystem::path& dir, uint64_t maxBytes) {
    std::lock_guard<std::mutex> lock(m_traceMutex);
    m_traceDir = dir;
    m_traceMaxBytes = maxBytes;
}

EmulatorSession::DrainResult EmulatorSession::drainTrace() {
    std::lock_guard<std::mutex> lock(m_traceMutex);
    DrainResult r;
    std::vector<CpuFrame> frames(1024);
    uint32_t lost = 0;
    uint32_t n = m_machine->drainCpuFrames(frames.data(), 1024, &lost);
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
    m_listener.scriptedTraceChanged(opened);
}

// A script always ends at regular speed, and never leaves a scripted trace
// running without its "Trace: Off".
void EmulatorSession::playbackFinished() {
    setFullSpeed(false);
    if (m_scriptedTrace.isOpen()) {
        drainTrace();
        m_scriptedTrace.close();
        m_listener.scriptedTraceChanged(false);
    }
    m_listener.playbackFinished();
}

} // namespace cu59
