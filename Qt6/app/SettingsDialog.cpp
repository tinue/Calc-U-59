#include "SettingsDialog.hpp"
#include "AppPaths.hpp"
#include "AppSettings.hpp"
#include "EmulatorController.hpp"
#include "Version.h"
#include <QComboBox>
#include <QDialogButtonBox>
#include <QDir>
#include <QFileDialog>
#include <QFormLayout>
#include <QGroupBox>
#include <QHBoxLayout>
#include <QLabel>
#include <QPushButton>
#include <QSpinBox>
#include <QVBoxLayout>

SettingsDialog::SettingsDialog(EmulatorController& controller, QWidget* parent) : QDialog(parent), m_controller(controller) {
    setWindowTitle(QStringLiteral("Settings"));
    setMinimumWidth(460);
    auto* col = new QVBoxLayout(this);

    auto* general = new QGroupBox(QStringLiteral("General"), this);
    auto* gf = new QFormLayout(general);
    m_startup = new QComboBox(general);
    m_startup->addItem(QStringLiteral("TI-59"), 0);
    m_startup->addItem(QStringLiteral("TI-58"), 1);
    m_startup->addItem(QStringLiteral("TI-58C"), 2);
    m_startup->insertSeparator(3);
    m_startup->addItem(QStringLiteral("Last Used"), -1);
    m_startup->setCurrentIndex(m_startup->findData(AppSettings::value<int>(AppSettings::kStartupModel, -1)));
    connect(m_startup, qOverload<int>(&QComboBox::activated), this,
            [this] { AppSettings::setValue(AppSettings::kStartupModel, m_startup->currentData().toInt()); });
    gf->addRow(QStringLiteral("Startup Calculator"), m_startup);

    m_module = new QComboBox(general);
    for (const auto& m : m_controller.allModules())
        m_module->addItem(QString::fromStdString(m.menuTitle), QString::fromStdString(m.id));
    m_module->setCurrentIndex(m_module->findData(m_controller.moduleID()));
    gf->addRow(QStringLiteral("Solid State Module"), m_module);
    gf->addRow(QStringLiteral("Version"), new QLabel(QStringLiteral(APP_VERSION " (" APP_BUILD_ID ")"), general));
    col->addWidget(general);

    auto* display = new QGroupBox(QStringLiteral("Display"), this);
    auto* df = new QFormLayout(display);
    m_style = new QComboBox(display);
    m_style->addItem(QStringLiteral("Modernized"), 0);
    m_style->addItem(QStringLiteral("Classic"), 1);
    m_style->setCurrentIndex(AppSettings::value<int>(AppSettings::kLedFontStyle, 0) == 1 ? 1 : 0);
    connect(m_style, qOverload<int>(&QComboBox::activated), this,
            [this] { AppSettings::setValue(AppSettings::kLedFontStyle, m_style->currentData().toInt()); });
    df->addRow(QStringLiteral("Segment Style"), m_style);
    col->addWidget(display);

    auto* files = new QGroupBox(QStringLiteral("Files"), this);
    auto* ff = new QFormLayout(files);
    auto* docsRow = new QHBoxLayout;
    m_docsPath = new QLabel(files);
    m_docsPath->setTextInteractionFlags(Qt::TextSelectableByMouse);
    auto* docsChoose = new QPushButton(QStringLiteral("Choose…"), files);
    connect(docsChoose, &QPushButton::clicked, this, [this] {
        QString dir = QFileDialog::getExistingDirectory(this, QStringLiteral("Folder for cards and ti58c.mem"), AppPaths::documentsDir());
        if (!dir.isEmpty()) AppSettings::setValue(AppSettings::kDocumentsDir, dir);
        refreshPaths();
    });
    docsRow->addWidget(m_docsPath, 1);
    docsRow->addWidget(docsChoose);
    ff->addRow(QStringLiteral("Documents Folder"), docsRow);

    m_traceLocation = new QComboBox(files);
    m_traceLocation->addItem(QStringLiteral("Local (App Data)"), 0);
    m_traceLocation->addItem(QStringLiteral("Custom Folder"), 2);
    m_traceLocation->setCurrentIndex(AppSettings::value<int>(AppSettings::kTraceLocation, 0) == 2 ? 1 : 0);
    connect(m_traceLocation, qOverload<int>(&QComboBox::activated), this, [this] {
        AppSettings::setValue(AppSettings::kTraceLocation, m_traceLocation->currentData().toInt());
        refreshPaths();
    });
    ff->addRow(QStringLiteral("Trace Save Location"), m_traceLocation);
    auto* traceRow = new QHBoxLayout;
    m_tracePath = new QLabel(files);
    m_tracePath->setTextInteractionFlags(Qt::TextSelectableByMouse);
    m_traceChoose = new QPushButton(QStringLiteral("Choose…"), files);
    connect(m_traceChoose, &QPushButton::clicked, this, [this] {
        QString dir = QFileDialog::getExistingDirectory(this, QStringLiteral("Choose a folder for CALCU59_TRACE.bin"), AppPaths::traceDir());
        if (!dir.isEmpty()) AppSettings::setValue(AppSettings::kTraceCustomPath, dir);
        refreshPaths();
    });
    traceRow->addWidget(m_tracePath, 1);
    traceRow->addWidget(m_traceChoose);
    ff->addRow(QString(), traceRow);
    m_maxMB = new QSpinBox(files);
    m_maxMB->setRange(1, 100000);
    m_maxMB->setSuffix(QStringLiteral(" MB"));
    m_maxMB->setValue(AppSettings::resolvedTraceMaxMB());
    connect(m_maxMB, qOverload<int>(&QSpinBox::valueChanged), this, [](int v) { AppSettings::setValue(AppSettings::kTraceMaxFileSizeMB, v); });
    ff->addRow(QStringLiteral("Maximum Trace File Size"), m_maxMB);
    col->addWidget(files);

    auto* buttons = new QDialogButtonBox(QDialogButtonBox::Close, this);
    connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);
    col->addWidget(buttons);
    refreshPaths();
}

void SettingsDialog::refreshPaths() {
    m_docsPath->setText(QDir::toNativeSeparators(AppPaths::documentsDir()));
    bool custom = m_traceLocation->currentData().toInt() == 2;
    m_tracePath->setText(QDir::toNativeSeparators(AppPaths::traceDir()));
    m_traceChoose->setVisible(custom);
}

void SettingsDialog::done(int r) {
    QString module = m_module->currentData().toString();
    if (!module.isEmpty() && module != m_controller.moduleID()) {
        m_controller.selectModule(module);
        m_controller.resetMachine();
    }
    QDialog::done(r);
}
