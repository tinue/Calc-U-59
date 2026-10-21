#include "ControlBar.hpp"
#include "ChromeStyle.hpp"
#include "EmulatorController.hpp"
#include <QApplication>
#include <QComboBox>
#include <QFrame>
#include <QHBoxLayout>
#include <QToolButton>

namespace {
QFrame* divider(QWidget* parent) {
    auto* f = new QFrame(parent);
    f->setFrameShape(QFrame::VLine);
    f->setFixedHeight(20);
    f->setStyleSheet(QStringLiteral("color: rgba(255,255,255,0.25);"));
    return f;
}

#ifdef Q_OS_MACOS
constexpr Qt::KeyboardModifier kCleanModifier = Qt::ControlModifier;  // ⌘ on macOS
#else
constexpr Qt::KeyboardModifier kCleanModifier = Qt::ControlModifier;
#endif
} // namespace

ControlBar::ControlBar(EmulatorController& controller, QWidget* parent) : QWidget(parent), m_controller(controller) {
    setAutoFillBackground(true);
    QPalette pal = palette();
    pal.setColor(QPalette::Window, ChromeStyle::kBar);
    setPalette(pal);
    setFixedHeight(50);
    setStyleSheet(ChromeStyle::barButton());

    auto* row = new QHBoxLayout(this);
    row->setContentsMargins(12, 0, 12, 0);
    row->setSpacing(12);

    m_reset = new QToolButton(this);
    m_reset->setToolTip(QStringLiteral("Reset (hold Ctrl/⌘ for a clean reset that clears all registers)"));
    connect(m_reset, &QToolButton::clicked, this, [this] {
        if (QApplication::keyboardModifiers() & kCleanModifier) m_controller.cleanResetMachine();
        else m_controller.resetMachine();
    });
    row->addWidget(m_reset);

    m_model = new QComboBox(this);
    m_model->addItems({QStringLiteral("TI-59"), QStringLiteral("TI-58"), QStringLiteral("TI-58C")});
    connect(m_model, qOverload<int>(&QComboBox::activated), this, [this](int index) {
        if (index != static_cast<int>(m_controller.model())) m_controller.start(static_cast<cu59::Model>(index));
    });
    row->addWidget(m_model);
    row->addWidget(divider(this));
    row->addStretch(1);

    m_loadCard = new QToolButton(this);
    m_loadCard->setText(QStringLiteral("⤓ Crd"));
    m_loadCard->setToolTip(QStringLiteral("Read a magnetic card"));
    connect(m_loadCard, &QToolButton::clicked, this, &ControlBar::loadCardRequested);
    m_newCard = new QToolButton(this);
    m_newCard->setText(QStringLiteral("＋ Crd"));
    m_newCard->setToolTip(QStringLiteral("Insert a blank card to write"));
    connect(m_newCard, &QToolButton::clicked, this, &ControlBar::newCardRequested);
    m_eject = new QToolButton(this);
    m_eject->setText(QStringLiteral("⏏ Eject Card"));
    connect(m_eject, &QToolButton::clicked, this, [this] { m_controller.ejectCard(); });
    row->addWidget(m_loadCard);
    row->addWidget(m_newCard);
    row->addWidget(m_eject);
    row->addWidget(divider(this));

    auto* preset = new QToolButton(this);
    preset->setText(QStringLiteral("Preset"));
    preset->setToolTip(QStringLiteral("Load a .ti59, .ti58 or .ti58c state file"));
    connect(preset, &QToolButton::clicked, this, &ControlBar::openPresetRequested);
    row->addWidget(preset);

    connect(&m_controller, &EmulatorController::modelChanged, this, &ControlBar::refresh);
    connect(&m_controller, &EmulatorController::cardStateChanged, this, &ControlBar::refresh);
    m_modifierPoll.setInterval(50);
    connect(&m_modifierPoll, &QTimer::timeout, this, &ControlBar::pollModifiers);
    m_modifierPoll.start();
    refresh();
}

void ControlBar::pollModifiers() {
    bool clean = (QApplication::keyboardModifiers() & kCleanModifier) != 0;
    if (clean == m_cleanMode && !m_reset->text().isEmpty()) return;
    m_cleanMode = clean;
    m_reset->setText(clean ? QStringLiteral("⊗ Clean") : QStringLiteral("↺ Reset"));
    m_reset->setStyleSheet(QStringLiteral("QToolButton { color: %1; }").arg(clean ? QStringLiteral("#ff3b30") : QStringLiteral("#ff9500")));
}

void ControlBar::refresh() {
    m_model->setCurrentIndex(static_cast<int>(m_controller.model()));
    bool reader = cu59::info(m_controller.model()).hasCardReader;
    bool swiping = m_controller.cardState() == EmulatorController::CardState::Swiping;
    m_loadCard->setVisible(reader && !swiping);
    m_newCard->setVisible(reader && !swiping);
    m_eject->setVisible(reader && swiping);
    pollModifiers();
}
