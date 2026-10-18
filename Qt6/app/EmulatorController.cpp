#include "EmulatorController.hpp"
#include "AppPaths.hpp"
#include "AppSettings.hpp"
#include "KeyMatrix.hpp"
#include <QDebug>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>

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

cu59::ResourceReader romReader() {
    return [](const std::string& name) { return readResource(QStringLiteral(":/roms/") + qs(name)); };
}

} // namespace

EmulatorController::EmulatorController(QObject* parent) : QObject(parent) {
    m_c = std::make_unique<cu59::SessionController>(static_cast<Platform&>(*this), romReader(),
                                                    readResource(QStringLiteral(":/roms/cuecards.txt")).value_or(""),
                                                    AppSettings::resolvedSolidStateModuleID().toStdString());
    m_frameTimer.setTimerType(Qt::PreciseTimer);
    m_frameTimer.setInterval(1000 / 60);
    connect(&m_frameTimer, &QTimer::timeout, this, [this] { m_c->tick(std::chrono::steady_clock::now()); });
    m_frameTimer.start();
}

EmulatorController::~EmulatorController() { m_c.reset(); }

QVector<cu59::ModuleMetadata> EmulatorController::allModules() const {
    auto all = m_c->allModules();
    return QVector<cu59::ModuleMetadata>(all.begin(), all.end());
}

void EmulatorController::pressKey(int row, int col) { m_c->pressKey(cu59::matrixCode(row, col)); }
void EmulatorController::releaseKey(int row, int col) { m_c->releaseKey(cu59::matrixCode(row, col)); }

EmulatorController::CardState EmulatorController::cardState() const {
    return m_c->cardState() == cu59::SessionController::CardState::Swiping ? CardState::Swiping : CardState::NoCard;
}

void EmulatorController::insertCard(const QString& path) {
    m_c->insertCard(readBytes(path), path.toStdString(), QFileInfo(path).fileName().toStdString());
}

void EmulatorController::insertBlankCard(const QString& savePath) {
    m_c->insertBlankCard(savePath.toStdString(), QFileInfo(savePath).fileName().toStdString());
}

void EmulatorController::loadStateFile(const QString& path) { m_c->loadStateFile(readBytes(path)); }

void EmulatorController::loadAsmFile(const QString& path) {
    m_c->loadAsm(readResource(path), QFileInfo(path).fileName().toStdString());
}

EmulatorController::FreezePanel EmulatorController::freezeOwner() const {
    cu59::DebugState s = m_c->debugState();
    if (!s.frozen || !s.owner) return FreezePanel::None;
    return *s.owner == cu59::FreezeOwner::Cpu ? FreezePanel::Cpu : FreezePanel::Calculator;
}

void EmulatorController::freeze(FreezePanel owner) {
    if (owner == FreezePanel::None) return;
    m_c->freeze(owner == FreezePanel::Cpu ? cu59::FreezeOwner::Cpu : cu59::FreezeOwner::Calculator);
}

// ── SessionController::Platform ──────────────────────────────────────────────

void EmulatorController::runOnUiThread(std::function<void()> job) {
    QMetaObject::invokeMethod(this, std::move(job), Qt::QueuedConnection);
}

std::optional<std::string> EmulatorController::readConstantMemory() { return readResource(AppPaths::constantMemoryFile()); }

void EmulatorController::writeConstantMemory(const std::string& text) { writeText(AppPaths::constantMemoryFile(), text); }

bool EmulatorController::writeCard(const std::string& path, const std::string& text) { return writeText(qs(path), text); }

cu59::SessionController::TraceLocation EmulatorController::traceLocation() {
    return {AppPaths::toFsPath(AppPaths::traceDir()), static_cast<uint64_t>(AppSettings::resolvedTraceMaxMB()) * 1'000'000,
            true};
}

void EmulatorController::saveLastUsedModel(cu59::Model model) {
    AppSettings::setValue(AppSettings::kLastUsedModel, static_cast<int>(model));
}

void EmulatorController::saveModuleID(const std::string& moduleID) {
    AppSettings::setValue(AppSettings::kSolidStateModuleID, qs(moduleID));
}

void EmulatorController::error(const std::string& title, const std::string& message) {
    emit errorOccurred(qs(title), qs(message));
}

void EmulatorController::diagnostic(const std::string& message) { qDebug("%s", message.c_str()); }

void EmulatorController::changed(uint32_t c) {
    using S = cu59::SessionController;
    if (c & S::PrinterChanged) {
        // Mirror the strip in Qt types: append what's new, rebuild after a cut.
        const auto& lines = m_c->printerLines();
        const auto& codes = m_c->printerCodeLines();
        if (static_cast<size_t>(m_printerLines.size()) > lines.size()) m_printerLines.clear();
        if (static_cast<size_t>(m_printerCodeLines.size()) > codes.size()) m_printerCodeLines.clear();
        for (size_t i = static_cast<size_t>(m_printerLines.size()); i < lines.size(); ++i) m_printerLines << qs(lines[i]);
        for (size_t i = static_cast<size_t>(m_printerCodeLines.size()); i < codes.size(); ++i) m_printerCodeLines << codes[i];
    }
    if (c & S::ModelChanged) emit modelChanged();
    if (c & S::DisplayChanged) emit displayChanged();
    if (c & S::CueCardChanged) emit cueCardChanged();
    if (c & (S::PrinterChanged | S::PaperCut)) emit printerChanged();
    if (c & (S::CardChanged | S::ModelChanged)) emit cardStateChanged();
    if (c & S::RunStateChanged) {
        emit heldKeyChanged();
        emit runStateChanged();
    }
    if (c & S::LiveChanged) emit liveSnapshotChanged();
    if (c & S::CpuChanged) emit cpuChanged();
    if (c & S::HeatmapChanged) emit heatmapChanged();
    if (c & S::LogChanged) emit logChanged();
    if (c & S::AsmChanged) emit asmChanged();
    if (c & S::TraceChanged) emit traceChanged();
}
