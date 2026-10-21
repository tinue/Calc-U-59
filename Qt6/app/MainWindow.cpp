#include "MainWindow.hpp"
#include "AboutDialog.hpp"
#include "AppPaths.hpp"
#include "AppSettings.hpp"
#include "CalculatorPanel.hpp"
#include "CardPickerDialog.hpp"
#include "ControlBar.hpp"
#include "EmulatorController.hpp"
#include "KeyboardWidget.hpp"
#include "PrinterWidget.hpp"
#include "SettingsDialog.hpp"
#include "debug/DebugPanel.hpp"
#include <QCloseEvent>
#include <QDesktopServices>
#include <QFileDialog>
#include <QFileInfo>
#include <QMenuBar>
#include <QMessageBox>
#include <QMimeData>
#include <QSplitter>
#include <QUrl>

namespace {
bool isStateFile(const QString& path) {
    QString ext = QFileInfo(path).suffix().toLower();
    return ext == QLatin1String("ti59") || ext == QLatin1String("ti58") || ext == QLatin1String("ti58c");
}
} // namespace

MainWindow::MainWindow(EmulatorController& controller, QWidget* parent) : QMainWindow(parent), m_controller(controller) {
    setWindowTitle(QStringLiteral("Calc-U-59"));
    setAcceptDrops(true);

    m_splitter = new QSplitter(Qt::Horizontal, this);
    m_splitter->setChildrenCollapsible(false);
    auto* calculator = new CalculatorPanel(controller, m_splitter);
    auto* printer = new PrinterWidget(controller, m_splitter);
    auto* debug = new DebugPanel(controller, m_splitter);
    m_splitter->addWidget(calculator);
    m_splitter->addWidget(printer);
    m_splitter->addWidget(debug);
    m_splitter->setStretchFactor(0, 0);
    m_splitter->setStretchFactor(1, 0);
    m_splitter->setStretchFactor(2, 1);  // the debug panel absorbs extra width
    setCentralWidget(m_splitter);

    connect(calculator->controlBar(), &ControlBar::openPresetRequested, this, &MainWindow::openPreset);
    connect(calculator->controlBar(), &ControlBar::loadCardRequested, this, &MainWindow::loadCard);
    connect(calculator->controlBar(), &ControlBar::newCardRequested, this, &MainWindow::newCard);
    connect(debug, &DebugPanel::selectAsmFileRequested, this, &MainWindow::selectAsmFile);
    connect(&m_controller, &EmulatorController::errorOccurred, this,
            [this](const QString& title, const QString& message) { QMessageBox::warning(this, title, message); });

    buildMenus();
    if (!restoreGeometry(AppSettings::value<QByteArray>(AppSettings::kWindowGeometry, QByteArray()))) resize(1280, 860);
    m_splitter->restoreState(AppSettings::value<QByteArray>(AppSettings::kSplitterState, QByteArray()));
    m_keyboard = calculator->keyboard();
    m_keyboard->setFocus();
}

void MainWindow::buildMenus() {
    QMenu* file = menuBar()->addMenu(QStringLiteral("&File"));
    file->addAction(QStringLiteral("Open Preset…"), QKeySequence::Open, this, &MainWindow::openPreset);
    file->addAction(QStringLiteral("Read Card…"), this, &MainWindow::loadCard);
    file->addAction(QStringLiteral("Write Blank Card…"), this, &MainWindow::newCard);
    file->addSeparator();
    QAction* settings = file->addAction(QStringLiteral("Settings…"), QKeySequence::Preferences, this, [this] {
        SettingsDialog dialog(m_controller, this);
        dialog.exec();
        m_keyboard->reloadSettings();
    });
    settings->setMenuRole(QAction::PreferencesRole);
    QAction* quit = file->addAction(QStringLiteral("Quit"), QKeySequence::Quit, this, &QWidget::close);
    quit->setMenuRole(QAction::QuitRole);

    QMenu* help = menuBar()->addMenu(QStringLiteral("&Help"));
    help->addAction(QStringLiteral("Calc-U-59 Help"), this,
                    [] { QDesktopServices::openUrl(QUrl(QStringLiteral("https://calc-u.org/59/"))); });
    QAction* about = help->addAction(QStringLiteral("About Calc-U-59"), this, [this] {
        AboutDialog dialog(this);
        dialog.exec();
    });
    about->setMenuRole(QAction::AboutRole);
}

void MainWindow::openPreset() {
    QString path = QFileDialog::getOpenFileName(this, QStringLiteral("Select a .ti59, .ti58, or .ti58c state file"),
                                                AppSettings::openStartDir(AppSettings::OpenFolder::Presets),
                                                QStringLiteral("State files (*.ti59 *.ti58 *.ti58c);;All files (*)"));
    if (path.isEmpty()) return;
    AppSettings::rememberOpenFile(AppSettings::OpenFolder::Presets, path);
    openStateFile(path);
}

void MainWindow::openStateFile(const QString& path) { m_controller.loadStateFile(path); }

void MainWindow::loadCard() {
    if (!cu59::info(m_controller.model()).hasCardReader) return;
    CardPickerDialog dialog(CardPickerDialog::Mode::Load, AppPaths::cardDir(), m_controller.cardFileName(), this);
    if (dialog.exec() == QDialog::Accepted) m_controller.insertCard(dialog.selectedPath());
}

void MainWindow::newCard() {
    if (!cu59::info(m_controller.model()).hasCardReader) return;
    CardPickerDialog dialog(CardPickerDialog::Mode::Save, AppPaths::cardDir(), m_controller.cardFileName(), this);
    if (dialog.exec() == QDialog::Accepted) m_controller.insertBlankCard(dialog.selectedPath());
}

void MainWindow::selectAsmFile() {
    QString path = QFileDialog::getOpenFileName(this, QStringLiteral("Select an ASM overlay"),
                                                AppSettings::openStartDir(AppSettings::OpenFolder::AsmOverlays),
                                                QStringLiteral("ASM files (*.asm);;All files (*)"));
    if (path.isEmpty()) return;
    AppSettings::rememberOpenFile(AppSettings::OpenFolder::AsmOverlays, path);
    m_controller.loadAsmFile(path);
}

void MainWindow::closeEvent(QCloseEvent* e) {
    AppSettings::setValue(AppSettings::kWindowGeometry, saveGeometry());
    AppSettings::setValue(AppSettings::kSplitterState, m_splitter->saveState());
    m_controller.persistConstantMemory();
    QMainWindow::closeEvent(e);
}

void MainWindow::dragEnterEvent(QDragEnterEvent* e) {
    const auto urls = e->mimeData()->urls();
    if (urls.size() == 1 && isStateFile(urls.first().toLocalFile())) e->acceptProposedAction();
}

void MainWindow::dropEvent(QDropEvent* e) {
    const auto urls = e->mimeData()->urls();
    if (urls.size() == 1 && isStateFile(urls.first().toLocalFile())) openStateFile(urls.first().toLocalFile());
}
