#include "LogWidget.hpp"
#include "ChromeStyle.hpp"
#include "EmulatorController.hpp"
#include <QHBoxLayout>
#include <QLabel>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QScrollBar>
#include <QVBoxLayout>

LogWidget::LogWidget(EmulatorController& controller, QWidget* parent) : QWidget(parent), m_controller(controller) {
    auto* col = new QVBoxLayout(this);
    col->setContentsMargins(0, 0, 0, 0);
    col->setSpacing(0);

    auto* title = new QLabel(QStringLiteral("DEBUG LOG"), this);
    title->setAlignment(Qt::AlignCenter);
    title->setStyleSheet(QStringLiteral("color: rgba(255,255,255,0.6); font-weight: bold; font-size: 11px;"
                                        " background: %1; padding: 6px;").arg(ChromeStyle::rgb(ChromeStyle::kDebugHeader)));
    col->addWidget(title);

    m_text = new QPlainTextEdit(this);
    m_text->setReadOnly(true);
    m_text->setStyleSheet(QStringLiteral("QPlainTextEdit { background: %1; color: #d9d9d9; border: 1px solid #404040;"
                                         " font-family: Menlo, monospace; font-size: 11px; padding: 8px; }")
                              .arg(ChromeStyle::rgb(ChromeStyle::kSectionBody)));
    col->addWidget(m_text, 1);

    auto* bar = new QWidget(this);
    bar->setStyleSheet(QStringLiteral("background: %1;").arg(ChromeStyle::rgb(ChromeStyle::kBar)) + ChromeStyle::pillButton());
    auto* rows = new QVBoxLayout(bar);
    rows->setContentsMargins(10, 8, 10, 8);
    auto* row1 = new QHBoxLayout;
    struct Dump { const char* name; void (EmulatorController::*fn)(); };
    for (Dump d : {Dump{"SCOM", &EmulatorController::dumpScom}, Dump{"Memory", &EmulatorController::dumpMemory},
                   Dump{"Prog", &EmulatorController::dumpProg}, Dump{"Vars", &EmulatorController::dumpVars}}) {
        auto* b = new QPushButton(QLatin1String(d.name), bar);
        connect(b, &QPushButton::clicked, this, [this, fn = d.fn] { (m_controller.*fn)(); });
        row1->addWidget(b);
    }
    row1->addStretch(1);
    m_clear = new QPushButton(QStringLiteral("🗑"), bar);
    m_clear->setToolTip(QStringLiteral("Clear the log"));
    connect(m_clear, &QPushButton::clicked, this, [this] { m_controller.clearLog(); });
    row1->addWidget(m_clear);
    rows->addLayout(row1);

    auto* row2 = new QHBoxLayout;
    m_trace = new QPushButton(bar);
    m_trace->setToolTip(QStringLiteral("Write every executed instruction to the binary trace file"));
    connect(m_trace, &QPushButton::clicked, this, [this] { m_controller.setManualTrace(!m_controller.manualTrace()); });
    m_level = new QPushButton(bar);
    m_level->setToolTip(QStringLiteral("Core log level: off / info / debug"));
    connect(m_level, &QPushButton::clicked, this, [this] { m_controller.cycleDebugLevel(); });
    row2->addWidget(m_trace);
    row2->addWidget(m_level);
    row2->addStretch(1);
    rows->addLayout(row2);
    col->addWidget(bar);

    connect(&m_controller, &EmulatorController::logChanged, this, &LogWidget::refresh);
    connect(&m_controller, &EmulatorController::traceChanged, this, &LogWidget::refresh);
    refresh();
}

void LogWidget::refresh() {
    if (m_text->toPlainText() != m_controller.logText()) {
        m_text->setPlainText(m_controller.logText());
        m_text->verticalScrollBar()->setValue(m_text->verticalScrollBar()->maximum());
    }
    m_clear->setEnabled(!m_controller.logText().isEmpty());
    m_trace->setText(m_controller.manualTrace() ? QStringLiteral("TRACE ●") : QStringLiteral("TRACE ○"));
    m_trace->setStyleSheet(m_controller.manualTrace() ? QStringLiteral("QPushButton { color: orange; }") : QString());
    const char* levels[3] = {"LOG ○", "LOG ●", "LOG ●"};
    int level = static_cast<int>(m_controller.debugLevel());
    m_level->setText(QLatin1String(levels[level]));
    m_level->setStyleSheet(level == 0 ? QString()
                                      : QStringLiteral("QPushButton { color: %1; }").arg(level == 1 ? QStringLiteral("orange") : QStringLiteral("#ff3b30")));
}
