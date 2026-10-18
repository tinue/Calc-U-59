#include "CpuInspectorWidget.hpp"
#include "ChromeStyle.hpp"
#include "DebugText.hpp"
#include "EmulatorController.hpp"
#include "HoldRepeatButton.hpp"
#include "RomHeatmapWidget.hpp"
#include <QHBoxLayout>
#include <QLabel>
#include <QListWidget>
#include <QPushButton>
#include <QScrollArea>
#include <QToolButton>
#include <QVBoxLayout>

namespace {

QToolButton* headerButton(const QString& text, const QColor& color, QWidget* parent) {
    auto* b = new QToolButton(parent);
    b->setText(text);
    b->setStyleSheet(ChromeStyle::headerButton(color));
    b->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);  // the title gives way first
    return b;
}

QWidget* sectionBox(const QString& title, QLabel*& body, QWidget* parent, QWidget* extraHeader = nullptr) {
    auto* box = new QWidget(parent);
    auto* col = new QVBoxLayout(box);
    col->setContentsMargins(0, 0, 0, 0);
    col->setSpacing(0);
    auto* head = new QWidget(box);
    head->setStyleSheet(QStringLiteral("background: %1;").arg(ChromeStyle::rgb(ChromeStyle::kDebugHeader)));
    auto* hrow = new QHBoxLayout(head);
    hrow->setContentsMargins(8, 3, 8, 3);
    auto* t = new QLabel(title, head);
    t->setStyleSheet(QStringLiteral("color: rgba(255,255,255,0.45); font: bold 9px Menlo, monospace;"));
    hrow->addWidget(t);
    hrow->addStretch(1);
    if (extraHeader) hrow->addWidget(extraHeader);
    col->addWidget(head);
    if (body) {
        body->setParent(box);
        body->setTextFormat(Qt::RichText);
        body->setTextInteractionFlags(Qt::TextSelectableByMouse);
        body->setStyleSheet(QStringLiteral("background: %1; padding: 4px 8px;").arg(ChromeStyle::rgb(ChromeStyle::kSectionBody)));
        col->addWidget(body);
    }
    return box;
}

QString nibbles(const uint8_t* n) { return QString::fromStdString(cu59::registerNibbles(n)); }

QString hexBin16(uint16_t v) { return QString::fromStdString(cu59::hexBin16(v)); }

QString c(const QString& text, const QString& color) {
    return QStringLiteral("<span style='color:%1'>%2</span>").arg(color, text.toHtmlEscaped());
}

} // namespace

CpuInspectorWidget::CpuInspectorWidget(EmulatorController& controller, QWidget* parent)
    : QWidget(parent), m_controller(controller) {
    auto* col = new QVBoxLayout(this);
    col->setContentsMargins(0, 0, 0, 0);
    col->setSpacing(0);

    auto* header = new QWidget(this);
    header->setStyleSheet(QStringLiteral("background: %1;").arg(ChromeStyle::rgb(ChromeStyle::kDebugHeader)));
    auto* hrow = new QHBoxLayout(header);
    hrow->setContentsMargins(10, 6, 10, 6);
    hrow->setSpacing(8);
    m_title = new QLabel(QStringLiteral("CPU DEBUG"), header);
    m_title->setStyleSheet(QStringLiteral("color: rgba(255,255,255,0.6); font-weight: bold; font-size: 11px;"));
    m_title->setSizePolicy(QSizePolicy::Ignored, QSizePolicy::Preferred);
    m_title->setMinimumWidth(40);
    hrow->addWidget(m_title, 1);  // takes the spare width; shrinks first
    m_resume = headerButton(QStringLiteral("RESUME"), QColor(255, 149, 0), header);
    connect(m_resume, &QToolButton::clicked, this, [this] { m_controller.unfreeze(); });
    m_freeze = headerButton(QStringLiteral("FREEZE"), Qt::white, header);
    connect(m_freeze, &QToolButton::clicked, this, [this] { m_controller.freeze(cu59::FreezeOwner::Cpu); });
    m_freezeOnStart = headerButton(QStringLiteral("FREEZE ON START"), Qt::white, header);
    connect(m_freezeOnStart, &QToolButton::clicked, this, [this] { m_controller.freezeOnScanLoopExit(); });
    m_armed = headerButton(QStringLiteral("ARMED"), QColor(255, 204, 0), header);
    connect(m_armed, &QToolButton::clicked, this, [this] { m_controller.disarmScanLoopFreeze(); });
    m_step = new HoldRepeatButton(QStringLiteral("STEP"), header);
    m_step->setStyleSheet(ChromeStyle::headerButton(QColor(50, 173, 230)));
    m_step->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
    connect(m_step, &HoldRepeatButton::fired, this, [this] { m_controller.stepFrozen(); });
    for (QWidget* w : std::initializer_list<QWidget*>{m_resume, m_freeze, m_freezeOnStart, m_armed, m_step}) hrow->addWidget(w);
    col->addWidget(header);

    m_list = new QListWidget(this);
    m_list->setFixedHeight(200);
    m_list->setStyleSheet(QStringLiteral("QListWidget { background: %1; border: none; color: white; }"
                                         "QListWidget::item:selected { background: %2; color: white; }")
                              .arg(ChromeStyle::rgb(ChromeStyle::kDebugBackground), ChromeStyle::rgb(ChromeStyle::gray(0.20))));
    connect(m_list, &QListWidget::currentRowChanged, this, [this](int row) {
        m_selected = row;
        refreshDetails();
    });
    col->addWidget(m_list);

    auto* scroll = new QScrollArea(this);
    scroll->setWidgetResizable(true);
    scroll->setFrameShape(QFrame::NoFrame);
    auto* content = new QWidget(scroll);
    content->setStyleSheet(QStringLiteral("background: %1;").arg(ChromeStyle::rgb(ChromeStyle::kDebugBackground)));
    auto* sections = new QVBoxLayout(content);
    sections->setContentsMargins(4, 4, 4, 4);
    sections->setSpacing(1);
    m_registers = new QLabel;
    sections->addWidget(sectionBox(QStringLiteral("REGISTERS"), m_registers, content));
    m_control = new QLabel;
    sections->addWidget(sectionBox(QStringLiteral("CONTROL REGISTERS"), m_control, content));
    m_displayState = new QLabel;
    sections->addWidget(sectionBox(QStringLiteral("DISPLAY STATE"), m_displayState, content));

    auto* heatHeader = new QWidget;
    auto* hh = new QHBoxLayout(heatHeader);
    hh->setContentsMargins(0, 0, 0, 0);
    m_hover = new QLabel(heatHeader);
    m_hover->setStyleSheet(QStringLiteral("color: rgba(255,214,0,0.85); font: bold 9px Menlo, monospace;"));
    auto* clr = new QPushButton(QStringLiteral("CLR"), heatHeader);
    clr->setStyleSheet(QStringLiteral("QPushButton { color: rgba(255,255,255,0.45); background: transparent; border: none;"
                                      " font: bold 9px Menlo, monospace; }"));
    connect(clr, &QPushButton::clicked, this, [this] { m_controller.clearHeatmap(); });
    hh->addWidget(m_hover);
    hh->addWidget(clr);
    QLabel* none = nullptr;
    QWidget* heatBox = sectionBox(QStringLiteral("ROM HEATMAP"), none, content, heatHeader);
    m_heatmap = new RomHeatmapWidget(m_controller, heatBox);
    heatBox->layout()->addWidget(m_heatmap);
    connect(m_heatmap, &RomHeatmapWidget::hoveredAddressChanged, this, [this](int a) {
        m_hover->setText(a < 0 ? QString() : QString::asprintf("0x%04X", a));
    });
    sections->addWidget(heatBox);
    sections->addStretch(1);
    scroll->setWidget(content);
    col->addWidget(scroll, 1);

    connect(&m_controller, &EmulatorController::cpuChanged, this, &CpuInspectorWidget::refreshList);
    connect(&m_controller, &EmulatorController::runStateChanged, this, &CpuInspectorWidget::refreshHeader);
    refreshHeader();
    refreshList();
}

int CpuInspectorWidget::baseFontSize() const { return cu59::debugPanelFontSize(width()); }

void CpuInspectorWidget::resizeEvent(QResizeEvent* e) {
    QWidget::resizeEvent(e);
    refreshHeader();
    refreshList();
}

void CpuInspectorWidget::refreshHeader() {
    bool narrow = baseFontSize() < 13;
    m_freezeOnStart->setText(narrow ? QStringLiteral("F.START") : QStringLiteral("FREEZE ON START"));
    bool frozen = m_controller.isFrozen();
    bool owned = frozen && m_controller.freezeOwner() == cu59::FreezeOwner::Cpu;
    bool canFreeze = !frozen && !m_controller.pendingCpuScanLoopFreeze();
    m_resume->setEnabled(owned);
    m_freeze->setEnabled(canFreeze);
    m_freezeOnStart->setEnabled(canFreeze);
    m_armed->setEnabled(m_controller.pendingCpuScanLoopFreeze());
    m_step->setEnabled(owned);
}

void CpuInspectorWidget::refreshList() {
    const auto& history = m_controller.cpuHistory();
    QFont mono(QStringLiteral("Menlo"));
    mono.setStyleHint(QFont::Monospace);
    mono.setPixelSize(baseFontSize() + 2);
    QSignalBlocker block(m_list);
    m_list->clear();
    int current = -1;
    for (size_t i = 0; i < history.size(); ++i) {
        const auto& e = history[i];
        auto* item = new QListWidgetItem(QString::asprintf("%04X  %04X  ", e.pc, e.opcode) + QString::fromStdString(e.disasm), m_list);
        item->setFont(mono);
        // Executed instructions full strength, the predicted next one dimmed.
        item->setForeground(QColor(255, 255, 255, e.isHistory ? 230 : 90));
        if (e.isCurrent) {
            item->setBackground(QColor(52, 199, 89, 90));
            current = static_cast<int>(i);
        }
    }
    // Running: follow the newest; frozen: select the current instruction.
    int select = m_controller.isFrozen() ? current : static_cast<int>(history.size()) - 1;
    if (select >= 0) {
        m_list->setCurrentRow(select);
        m_list->scrollToItem(m_list->item(select), m_controller.isFrozen() ? QAbstractItemView::PositionAtCenter
                                                                           : QAbstractItemView::PositionAtBottom);
    }
    m_selected = select;
    refreshDetails();
    m_heatmap->setCurrentPC(current >= 0 ? history[static_cast<size_t>(current)].pc : -1);
}

void CpuInspectorWidget::refreshDetails() {
    const auto& history = m_controller.cpuHistory();
    const QString font = QStringLiteral("font-family: Menlo, monospace; font-size: %1px;").arg(baseFontSize() + 2);
    auto set = [&](QLabel* l, const QString& html) { l->setText(QStringLiteral("<div style='%1'>%2</div>").arg(font, html)); };
    if (m_selected < 0 || m_selected >= static_cast<int>(history.size())) {
        set(m_registers, QString());
        set(m_control, QString());
        set(m_displayState, QString());
        return;
    }
    const CpuFrame& f = history[static_cast<size_t>(m_selected)].frame;
    const QString label = QStringLiteral("rgba(255,255,255,0.6)"), value = QStringLiteral("rgba(255,255,255,0.85)");
    QStringList regs;
    const std::pair<const char*, const uint8_t*> rows[] = {{"A", f.A}, {"B", f.B}, {"C", f.C}, {"D", f.D}, {"E", f.E}, {"Sout", f.Sout}};
    for (const auto& [name, n] : rows) regs << QStringLiteral("<b>%1</b> %2").arg(c(QLatin1String(name), label), c(nibbles(n), value));
    set(m_registers, regs.join(QStringLiteral("<br>")));

    int cond = cu59::condFlag(f.flags) ? 1 : 0, idle = cu59::idleFlag(f.flags) ? 1 : 0;
    set(m_control, c(QStringLiteral("KR: ") + hexBin16(f.KR), value) + QStringLiteral("<br>") +
                       c(QStringLiteral("fA: ") + hexBin16(f.fA), value) + QStringLiteral("<br>") +
                       c(QStringLiteral("fB: ") + hexBin16(f.fB), value) + QStringLiteral("<br>") +
                       c(QString::asprintf("SR: %04X", f.SR), value) + QStringLiteral("&nbsp;&nbsp;&nbsp;&nbsp;") +
                       c(QStringLiteral("R5: %1").arg(f.R5), value) + QStringLiteral("<br>") +
                       c(QStringLiteral("COND: %1").arg(cond), cond ? QStringLiteral("rgba(255,204,0,0.4)") : QStringLiteral("#ffcc00")) +
                       QStringLiteral("&nbsp;&nbsp;&nbsp;&nbsp;") +
                       c(QStringLiteral("IDLE: %1").arg(idle), idle ? QStringLiteral("white") : QStringLiteral("rgba(255,255,255,0.45)")) +
                       QStringLiteral("&nbsp;&nbsp;&nbsp;&nbsp;") + c(QString::asprintf("DIGIT: %2d", f.postDigit), value));
    bool on = f.displayOn != 0;
    set(m_displayState, c(QStringLiteral("Decay: %1").arg(f.maxDigitDecay), value) + QStringLiteral("&nbsp;&nbsp;&nbsp;&nbsp;") +
                            c(on ? QStringLiteral("ON") : QStringLiteral("OFF"), on ? QStringLiteral("rgba(52,199,89,0.85)")
                                                                                     : QStringLiteral("rgba(255,59,48,0.7)")));
}
