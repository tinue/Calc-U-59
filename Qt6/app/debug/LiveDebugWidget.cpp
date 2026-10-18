#include "LiveDebugWidget.hpp"
#include "ChromeStyle.hpp"
#include "DebugText.hpp"
#include "EmulatorController.hpp"
#include "HoldRepeatButton.hpp"
#include <QHBoxLayout>
#include <QLabel>
#include <QListWidget>
#include <QScrollArea>
#include <QToolButton>
#include <QVBoxLayout>

namespace {

QString span(const QString& text, double white) {
    return QStringLiteral("<span style='color:%1'>%2</span>").arg(ChromeStyle::gray(white).name(), text.toHtmlEscaped());
}

QString spanColor(const QString& text, const QColor& c) {
    return QStringLiteral("<span style='color:%1'>%2</span>").arg(c.name(), text.toHtmlEscaped());
}

QString qs(const std::string& s) { return QString::fromStdString(s); }

QColor rgb(uint32_t c) { return QColor(static_cast<int>(c >> 16 & 0xFF), static_cast<int>(c >> 8 & 0xFF), static_cast<int>(c & 0xFF)); }

/// A titled section: header strip and body label (SectionBox in the Swift app).
QLabel* section(QVBoxLayout* into, const QString& title, QWidget* parent) {
    auto* box = new QWidget(parent);
    auto* col = new QVBoxLayout(box);
    col->setContentsMargins(0, 0, 0, 0);
    col->setSpacing(0);
    auto* head = new QLabel(title, box);
    head->setStyleSheet(QStringLiteral("color: rgba(255,255,255,0.45); background: %1; font: bold 9px Menlo, monospace;"
                                       " padding: 3px 8px;").arg(ChromeStyle::rgb(ChromeStyle::kDebugHeader)));
    col->addWidget(head);
    auto* body = new QLabel(box);
    body->setTextFormat(Qt::RichText);
    body->setTextInteractionFlags(Qt::TextSelectableByMouse);
    body->setStyleSheet(QStringLiteral("background: %1; padding: 4px 8px;").arg(ChromeStyle::rgb(ChromeStyle::kSectionBody)));
    col->addWidget(body);
    into->addWidget(box);
    return body;
}

QToolButton* headerButton(const QString& text, const QColor& color, QWidget* parent) {
    auto* b = new QToolButton(parent);
    b->setText(text);
    b->setStyleSheet(ChromeStyle::headerButton(color));
    b->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);  // the title gives way first
    return b;
}

} // namespace

LiveDebugWidget::LiveDebugWidget(EmulatorController& controller, QWidget* parent) : QWidget(parent), m_controller(controller) {
    auto* col = new QVBoxLayout(this);
    col->setContentsMargins(0, 0, 0, 0);
    col->setSpacing(0);

    auto* header = new QWidget(this);
    header->setStyleSheet(QStringLiteral("background: %1;").arg(ChromeStyle::rgb(ChromeStyle::kDebugHeader)));
    auto* hrow = new QHBoxLayout(header);
    hrow->setContentsMargins(10, 6, 10, 6);
    hrow->setSpacing(8);
    m_title = new QLabel(header);
    m_title->setStyleSheet(QStringLiteral("color: rgba(255,255,255,0.6); font-weight: bold; font-size: 11px;"));
    m_title->setSizePolicy(QSizePolicy::Ignored, QSizePolicy::Preferred);
    m_title->setMinimumWidth(40);
    hrow->addWidget(m_title, 1);  // takes the spare width; shrinks first
    // RESUME sits far from STEP to avoid accidental taps while stepping.
    m_resume = headerButton(QStringLiteral("RESUME"), QColor(255, 149, 0), header);
    connect(m_resume, &QToolButton::clicked, this, [this] { m_controller.unfreeze(); });
    m_freeze = headerButton(QStringLiteral("FREEZE"), Qt::white, header);
    connect(m_freeze, &QToolButton::clicked, this, [this] { m_controller.freeze(EmulatorController::FreezePanel::Calculator); });
    m_freezeOnStart = headerButton(QStringLiteral("FREEZE ON START"), Qt::white, header);
    connect(m_freezeOnStart, &QToolButton::clicked, this, [this] { m_controller.freezeOnNextPCChange(); });
    m_armed = headerButton(QStringLiteral("ARMED"), QColor(255, 204, 0), header);
    connect(m_armed, &QToolButton::clicked, this, [this] { m_controller.disarmPcChangeFreeze(); });
    m_step = new HoldRepeatButton(QStringLiteral("STEP"), header);
    m_step->setStyleSheet(ChromeStyle::headerButton(QColor(50, 173, 230)));
    m_step->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
    connect(m_step, &HoldRepeatButton::fired, this, [this] { m_controller.stepKeycode(); });
    for (QWidget* w : std::initializer_list<QWidget*>{m_resume, m_freeze, m_freezeOnStart, m_armed, m_step}) hrow->addWidget(w);
    col->addWidget(header);

    // DEBUG section stays above the scrolling sections.
    auto* top = new QVBoxLayout;
    top->setContentsMargins(4, 4, 4, 0);
    m_debug = section(top, QStringLiteral("DEBUG"), this);
    col->addLayout(top);

    auto* scroll = new QScrollArea(this);
    scroll->setWidgetResizable(true);
    scroll->setFrameShape(QFrame::NoFrame);
    auto* content = new QWidget(scroll);
    content->setStyleSheet(QStringLiteral("background: %1;").arg(ChromeStyle::rgb(ChromeStyle::kDebugBackground)));
    auto* sections = new QVBoxLayout(content);
    sections->setContentsMargins(4, 4, 4, 4);
    sections->setSpacing(1);
    m_partition = section(sections, QStringLiteral("PARTITION"), content);
    m_source = section(sections, QString(), content);

    auto* stepsBox = new QWidget(content);
    auto* stepsCol = new QVBoxLayout(stepsBox);
    stepsCol->setContentsMargins(0, 0, 0, 0);
    stepsCol->setSpacing(0);
    auto* stepsHead = new QLabel(QStringLiteral("PROGRAM STEPS"), stepsBox);
    stepsHead->setStyleSheet(QStringLiteral("color: rgba(255,255,255,0.45); background: %1; font: bold 9px Menlo, monospace;"
                                            " padding: 3px 8px;").arg(ChromeStyle::rgb(ChromeStyle::kDebugHeader)));
    stepsCol->addWidget(stepsHead);
    m_steps = new QListWidget(stepsBox);
    m_steps->setFixedHeight(165);
    m_steps->setSelectionMode(QAbstractItemView::NoSelection);
    m_steps->setFocusPolicy(Qt::NoFocus);
    m_steps->setStyleSheet(QStringLiteral("QListWidget { background: %1; border: none; }").arg(ChromeStyle::rgb(ChromeStyle::kSectionBody)));
    stepsCol->addWidget(m_steps);
    sections->addWidget(stepsBox);

    m_fields = section(sections, QString(), content);
    m_returns = section(sections, QStringLiteral("RETURN ADDRESS"), content);
    m_flags = section(sections, QStringLiteral("FLAGS"), content);
    m_hir = section(sections, QStringLiteral("HIR"), content);
    m_t = section(sections, QString(), content);
    m_vars = section(sections, QStringLiteral("VARIABLES"), content);
    sections->addStretch(1);
    scroll->setWidget(content);
    col->addWidget(scroll, 1);

    connect(&m_controller, &EmulatorController::liveSnapshotChanged, this, &LiveDebugWidget::refresh);
    connect(&m_controller, &EmulatorController::runStateChanged, this, &LiveDebugWidget::refreshHeader);
    refreshHeader();
    refresh();
}

int LiveDebugWidget::baseFontSize() const { return cu59::debugPanelFontSize(width()); }

void LiveDebugWidget::resizeEvent(QResizeEvent* e) {
    QWidget::resizeEvent(e);
    refreshHeader();
    refresh();
}

void LiveDebugWidget::refreshHeader() {
    bool narrow = baseFontSize() < 13;
    m_title->setText(narrow ? QStringLiteral("DEBUG") : QStringLiteral("CALCULATOR DEBUG"));
    m_freezeOnStart->setText(narrow ? QStringLiteral("F.START") : QStringLiteral("FREEZE ON START"));
    bool frozen = m_controller.isFrozen();
    bool owned = frozen && m_controller.freezeOwner() == EmulatorController::FreezePanel::Calculator;
    bool canFreeze = !frozen && !m_controller.pendingFreezeOnPCChange();
    m_resume->setEnabled(owned);
    m_freeze->setEnabled(canFreeze);
    m_freezeOnStart->setEnabled(canFreeze);
    m_armed->setEnabled(m_controller.pendingFreezeOnPCChange());
    m_step->setEnabled(owned);
    refresh();
}

void LiveDebugWidget::refresh() {
    const cu59::LiveDebugSnapshot& s = m_controller.liveSnapshot();
    const int fs = baseFontSize() + 2;
    const QString font = QStringLiteral("font-family: Menlo, monospace; font-size: %1px;").arg(fs);
    auto set = [&](QLabel* l, const QString& html) { l->setText(QStringLiteral("<div style='%1'>%2</div>").arg(font, html)); };
    const QString sp = QStringLiteral("&nbsp;&nbsp;&nbsp;");

    set(m_debug, span(QString::asprintf("FA:%04X", s.fA), 0.65) + sp + span(QString::asprintf("FB:%04X", s.fB), 0.65) + sp +
                     span(QStringLiteral("IO:") + QString::fromStdString(s.ioUserFlags), 0.85) + sp +
                     span(QStringLiteral("KEY:") + QString::fromStdString(s.lastKey), 0.85));

    set(m_partition, span(qs(cu59::partitionLine(s.programRegCount, s.dataRegCount)), 0.75));
    set(m_source, span(QString::fromStdString(cu59::programSourceLabel(s.programSource, s.prSourceFlag)), 0.85));

    // Program steps: the full listing when frozen, else ±5 around the current step.
    bool frozen = m_controller.isFrozen() && !m_controller.programListing().empty();
    const auto& entries = frozen ? m_controller.programListing() : s.programWindow;
    QColor highlight = rgb(cu59::stepHighlightColor(frozen ? m_controller.programListingSource() : s.programSource));
    QFont mono(QStringLiteral("Menlo"));
    mono.setStyleHint(QFont::Monospace);
    mono.setPixelSize(fs);
    m_steps->clear();
    int current = -1;
    for (const auto& e : entries) {
        QString text = QStringLiteral("%1  %2  %3").arg(e.stepNum, 3, 10, QLatin1Char('0')).arg(e.keycode, 2, 10, QLatin1Char('0'))
                           .arg(QString::fromStdString(e.mnemonic));
        if (e.isCurrent) text += frozen ? QStringLiteral("  ← frozen") : QStringLiteral("  ← running");
        auto* item = new QListWidgetItem(text, m_steps);
        item->setFont(mono);
        item->setForeground(e.isCurrent ? Qt::white : ChromeStyle::gray(0.6));
        if (e.isCurrent) {
            item->setBackground(highlight);
            current = m_steps->count() - 1;
        }
    }
    if (current >= 0) m_steps->scrollToItem(m_steps->item(current), QAbstractItemView::PositionAtCenter);

    auto dim = [](bool on) { return on ? 0.85 : 0.4; };
    QString angle = span(qs(cu59::angleModeLabel(s.angleMode)), s.angleMode ? 0.85 : 0.4);
    set(m_fields, span(QStringLiteral("FIX:") + QString::fromStdString(s.fixIndicator), 0.85) + sp + angle + sp +
                      span(QStringLiteral("Eng"), dim(!s.engIndicator.empty())) + sp +
                      span(QStringLiteral("2nd"), dim(!s.secondIndicator.empty())) + sp +
                      span(QStringLiteral("INV"), dim(!s.invIndicator.empty())));

    auto level = [&](int i) {
        int a = s.returnAddresses[static_cast<size_t>(i)];
        return spanColor(QStringLiteral("L%1:%2").arg(i + 1).arg(a, 3, 10, QLatin1Char('0')),
                         rgb(cu59::returnLevelColor(s.returnAddressSourceFlags[static_cast<size_t>(i)], a == 0)));
    };
    set(m_returns, level(5) + sp + level(4) + sp + level(3) + QStringLiteral("<br>") + level(2) + sp + level(1) + sp + level(0));

    QString flags;
    for (int i = 0; i < 10; ++i) {
        bool on = s.calcFlags[static_cast<size_t>(i)];
        flags += span(QStringLiteral("F%1:%2").arg(i).arg(on ? 1 : 0), on ? 0.85 : 0.6) + (i == 4 ? QStringLiteral("<br>") : sp);
    }
    set(m_flags, flags);

    QString hir;
    for (int i = 0; i < 8; ++i) {
        double v = s.hir[static_cast<size_t>(i)];
        hir += span(qs(cu59::hirLine(i + 1, v)), v == 0 ? 0.6 : 0.85) + (i == 3 ? QStringLiteral("<br>") : sp);
    }
    set(m_hir, hir);
    set(m_t, span(qs(cu59::tRegisterLine(s.tRegister)), s.tRegister == 0 ? 0.6 : 0.85));

    if (s.nonZeroRegs.empty()) {
        set(m_vars, span(QStringLiteral("(all zero)"), 0.35));
    } else {
        QStringList lines;
        for (const auto& r : s.nonZeroRegs) lines << span(qs(cu59::registerLine(r)), 0.85);
        set(m_vars, lines.join(QStringLiteral("<br>")));
    }
}
