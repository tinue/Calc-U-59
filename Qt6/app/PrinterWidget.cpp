#include "PrinterWidget.hpp"
#include "ChromeStyle.hpp"
#include "EmulatorController.hpp"
#include "PrinterFont.hpp"
#include <QApplication>
#include <QClipboard>
#include <QHBoxLayout>
#include <QLabel>
#include <QMimeData>
#include <QPainter>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QScrollArea>
#include <QScrollBar>
#include <QStackedWidget>
#include <QTimer>
#include <QVBoxLayout>

using cu59::PrinterGeometry;

// ── Paper strip (dot mode) ───────────────────────────────────────────────────

/// Paints the printed lines at the PC-100C's proportions: 7 dot rows plus the
/// stepper gap per line, a shorter advance for PRT_FEED blank lines, and
/// partial lines (row count < 7) where printing was cut short.
class PaperView : public QWidget {
public:
    explicit PaperView(EmulatorController& c, QWidget* parent) : QWidget(parent), m_c(c) {}

    /// Height for a width, in dot-pitch units scaled to that width.
    static double heightUnits(const QStringList& lines, const QVector<PrinterCodeLine>& codes) {
        double units = 0;
        for (int i = 0; i < lines.size(); ++i)
            units += PrinterGeometry::lineHeightUnits(lines[i].isEmpty(), i < codes.size() ? codes[i].rowCount : 7);
        return units;
    }

    /// Draw the strip into `p` with the given width and dot colour; only the
    /// lines overlapping [visibleTop, visibleBottom) (strip coordinates).
    static void paintStrip(QPainter& p, double width, const QStringList& lines, const QVector<PrinterCodeLine>& codes,
                           const QColor& dot, double visibleTop = -1e18, double visibleBottom = 1e18) {
        const double pitch = width / PrinterGeometry::widthUnits;
        const double radius = pitch * PrinterGeometry::dotRadiusFraction;
        p.setPen(Qt::NoPen);
        p.setBrush(dot);
        double y = 0;
        for (int i = 0; i < lines.size() && y < visibleBottom; ++i) {
            const double lineHeight =
                PrinterGeometry::lineHeightUnits(lines[i].isEmpty(), i < codes.size() ? codes[i].rowCount : 7) * pitch;
            if (lines[i].isEmpty() || y + lineHeight < visibleTop) {
                y += lineHeight;
                continue;
            }
            const PrinterCodeLine* line = i < codes.size() ? &codes[i] : nullptr;
            int rows = PrinterGeometry::clampRowCount(line ? line->rowCount : 7);
            for (int row = 0; row < rows; ++row) {
                double cy = y + (row + 0.5) * pitch;
                for (int ch = 0; ch < 20 && line; ++ch) {
                    uint8_t bits = cu59::kPC100CFont[line->codes[static_cast<size_t>(ch)] & 0x3F][row];
                    double cx0 = ch * PrinterGeometry::charStepUnits * pitch;
                    for (int col = 0; col < 5; ++col)
                        if (bits & (0x10 >> col)) p.drawEllipse(QPointF(cx0 + (col + 0.5) * pitch, cy), radius, radius);
                }
            }
            y += lineHeight;  // a complete line ends with the stepper's advance; a cut-short one doesn't
        }
    }

    QSize sizeHint() const override { return QSize(220, heightForWidth(220)); }
    bool hasHeightForWidth() const override { return true; }
    int heightForWidth(int w) const override {
        double pitch = (w - 2 * PrinterGeometry::paperPaddingX) / PrinterGeometry::widthUnits;
        return static_cast<int>(heightUnits(m_c.printerLines(), m_c.printerCodeLines()) * pitch) +
               static_cast<int>(2 * PrinterGeometry::paperPaddingY);
    }

protected:
    void paintEvent(QPaintEvent* e) override {
        QPainter p(this);
        p.setRenderHint(QPainter::Antialiasing);
        p.translate(PrinterGeometry::paperPaddingX, PrinterGeometry::paperPaddingY);
        // A long tape is mostly scrolled out of view: draw the exposed lines only.
        paintStrip(p, width() - 2 * PrinterGeometry::paperPaddingX, m_c.printerLines(), m_c.printerCodeLines(),
                   ChromeStyle::gray(0.12), e->rect().top() - PrinterGeometry::paperPaddingY,
                   e->rect().bottom() + 1 - PrinterGeometry::paperPaddingY);
    }

private:
    EmulatorController& m_c;
};

// ── Panel ────────────────────────────────────────────────────────────────────

namespace {
QPushButton* pill(const QString& text, QWidget* parent) {
    auto* b = new QPushButton(text, parent);
    b->setStyleSheet(ChromeStyle::pillButton());
    b->setCursor(Qt::PointingHandCursor);
    b->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);  // never squeeze the labels
    return b;
}
} // namespace

PrinterWidget::PrinterWidget(EmulatorController& controller, QWidget* parent) : QWidget(parent), m_controller(controller) {
    setAutoFillBackground(true);
    QPalette pal = palette();
    pal.setColor(QPalette::Window, ChromeStyle::kPanel);
    setPalette(pal);
    // Minimum width: whatever the button bar needs (Fixed-size pills), at least 220.
    setMaximumWidth(320);

    auto* col = new QVBoxLayout(this);
    col->setContentsMargins(8, 8, 8, 8);
    col->setSpacing(0);

    // Header: PC-100C toggle, dot/text toggle.
    auto* header = new QWidget(this);
    header->setAutoFillBackground(true);
    QPalette hp = header->palette();
    hp.setColor(QPalette::Window, ChromeStyle::kHeader);
    header->setPalette(hp);
    auto* hrow = new QHBoxLayout(header);
    hrow->setContentsMargins(8, 8, 8, 8);
    m_connect = pill(QString(), header);
    connect(m_connect, &QPushButton::clicked, this, [this] {
        m_controller.setPrinterConnected(!m_controller.printerConnected());
        m_controller.resetMachine();
    });
    m_mode = pill(QStringLiteral("•••"), header);
    m_mode->setToolTip(QStringLiteral("Dot / text view"));
    connect(m_mode, &QPushButton::clicked, this, [this] {
        m_dotMode = !m_dotMode;
        m_stack->setCurrentIndex(m_dotMode ? 0 : 1);
        m_mode->setText(m_dotMode ? QStringLiteral("•••") : QStringLiteral("☰"));
    });
    hrow->addStretch(1);
    hrow->addWidget(m_connect);
    hrow->addStretch(1);
    hrow->addWidget(m_mode);
    col->addWidget(header);

    // Paper.
    m_stack = new QStackedWidget(this);
    const QString paperCss = QStringLiteral("background: %1; border: 1px solid #b3b3b3;").arg(ChromeStyle::rgb(ChromeStyle::kPaper));
    m_scroll = new QScrollArea(m_stack);
    m_scroll->setWidgetResizable(true);
    m_scroll->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    m_scroll->setStyleSheet(QStringLiteral("QScrollArea { %1 } QScrollArea > QWidget > QWidget { background: %2; }")
                                .arg(paperCss, ChromeStyle::rgb(ChromeStyle::kPaper)));
    m_paper = new PaperView(m_controller, m_scroll);
    m_scroll->setWidget(m_paper);
    m_text = new QPlainTextEdit(m_stack);
    m_text->setReadOnly(true);
    QFont mono(QStringLiteral("Menlo"));
    mono.setStyleHint(QFont::Monospace);
    mono.setPixelSize(13);
    m_text->setFont(mono);
    m_text->setStyleSheet(QStringLiteral("QPlainTextEdit { %1 color: #262626; }").arg(paperCss));
    m_stack->addWidget(m_scroll);
    m_stack->addWidget(m_text);
    col->addWidget(m_stack, 1);

    // Hardware buttons.
    auto* bar = new QWidget(this);
    bar->setAutoFillBackground(true);
    QPalette bp = bar->palette();
    bp.setColor(QPalette::Window, ChromeStyle::kBar);
    bar->setPalette(bp);
    bar->setFixedHeight(50);
    auto* brow = new QHBoxLayout(bar);
    brow->setContentsMargins(10, 0, 10, 0);
    brow->setSpacing(8);
    m_print = pill(QStringLiteral("PRINT"), bar);
    connect(m_print, &QPushButton::pressed, this, [this] { m_controller.pressPrinterPrint(true); });
    connect(m_print, &QPushButton::released, this, [this] { m_controller.pressPrinterPrint(false); });
    m_trace = pill(QString(), bar);
    connect(m_trace, &QPushButton::clicked, this, [this] { m_controller.togglePrinterTrace(); });
    auto* adv = pill(QStringLiteral("ADV"), bar);
    connect(adv, &QPushButton::pressed, this, [this] { m_controller.pressPrinterAdv(true); });
    connect(adv, &QPushButton::released, this, [this] { m_controller.pressPrinterAdv(false); });
    m_copy = pill(QStringLiteral("⧉"), bar);
    m_copy->setToolTip(QStringLiteral("Copy the paper (text and image)"));
    connect(m_copy, &QPushButton::clicked, this, &PrinterWidget::copyToClipboard);
    m_cut = pill(QStringLiteral("✂"), bar);
    m_cut->setToolTip(QStringLiteral("Copy, then tear off the paper"));
    connect(m_cut, &QPushButton::clicked, this, [this] {
        copyToClipboard();
        m_controller.cutPaper();
    });
    brow->addWidget(m_print);
    brow->addWidget(m_trace);
    brow->addWidget(adv);
    brow->addStretch(1);
    brow->addWidget(m_copy);
    brow->addWidget(m_cut);
    col->addWidget(bar);

    m_toast = new QLabel(QStringLiteral("Copied to clipboard"), this);
    m_toast->setStyleSheet(QStringLiteral("background: rgba(0,0,0,0.75); color: white; font-weight: bold;"
                                          " padding: 7px 14px; border-radius: 10px;"));
    m_toast->hide();

    connect(&m_controller, &EmulatorController::printerChanged, this, &PrinterWidget::refresh);
    refresh();
}

void PrinterWidget::refresh() {
    auto dot = [](bool on) { return on ? QStringLiteral("●") : QStringLiteral("○"); };
    m_connect->setText(QStringLiteral("PC-100C ") + dot(m_controller.printerConnected()));
    m_trace->setText(QStringLiteral("T ") + dot(m_controller.printerTrace()));
    m_print->setText(width() < 180 ? QStringLiteral("PRN") : QStringLiteral("PRINT"));
    bool empty = m_controller.printerLines().isEmpty();
    m_copy->setEnabled(!empty);
    m_cut->setEnabled(!empty);
    m_paper->updateGeometry();
    m_paper->update();
    // Text view: append the new lines (a full reset per line is quadratic on a long listing).
    const QStringList& lines = m_controller.printerLines();
    if (lines.size() < m_textLines) {
        m_text->clear();
        m_textLines = 0;
    }
    for (; m_textLines < lines.size(); ++m_textLines) m_text->appendPlainText(lines[m_textLines]);
    // Keep the newest line in view.
    QTimer::singleShot(0, this, [this] {
        m_scroll->verticalScrollBar()->setValue(m_scroll->verticalScrollBar()->maximum());
        m_text->verticalScrollBar()->setValue(m_text->verticalScrollBar()->maximum());
    });
}

void PrinterWidget::resizeEvent(QResizeEvent* e) {
    QWidget::resizeEvent(e);
    m_print->setText(width() < 180 ? QStringLiteral("PRN") : QStringLiteral("PRINT"));
}

void PrinterWidget::copyToClipboard() {
    const QStringList& lines = m_controller.printerLines();
    const auto& codes = m_controller.printerCodeLines();
    double unitsHigh = PaperView::heightUnits(lines, codes);
    double pxPerUnit = PrinterGeometry::copyPixelsPerUnit(unitsHigh);
    QImage image(QSize(static_cast<int>(PrinterGeometry::widthUnits * pxPerUnit),
                       std::max(1, static_cast<int>(unitsHigh * pxPerUnit))), QImage::Format_RGB32);
    image.fill(Qt::white);
    {
        QPainter p(&image);
        p.setRenderHint(QPainter::Antialiasing);
        PaperView::paintStrip(p, image.width(), lines, codes, Qt::black);
    }
    image.setDotsPerMeterX(static_cast<int>(pxPerUnit / PrinterGeometry::dotPitchMM * 1000));
    image.setDotsPerMeterY(image.dotsPerMeterX());
    auto* mime = new QMimeData;
    mime->setText(lines.join(QLatin1Char('\n')));
    mime->setImageData(image);
    QApplication::clipboard()->setMimeData(mime);
    showToast();
}

void PrinterWidget::showToast() {
    m_toast->adjustSize();
    m_toast->move((width() - m_toast->width()) / 2, height() - 48 - m_toast->height());
    m_toast->raise();
    m_toast->show();
    QTimer::singleShot(1800, m_toast, &QLabel::hide);
}
