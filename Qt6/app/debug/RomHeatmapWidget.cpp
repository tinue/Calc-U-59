#include "RomHeatmapWidget.hpp"
#include "EmulatorController.hpp"
#include "RomHeatmap.hpp"
#include <QMouseEvent>
#include <QPainter>

using cu59::kHeatmapCols;
using cu59::kHeatmapRows;

RomHeatmapWidget::RomHeatmapWidget(EmulatorController& controller, QWidget* parent)
    : QWidget(parent), m_controller(controller), m_image(kHeatmapCols, kHeatmapRows, QImage::Format_RGB32),
      m_steps(static_cast<size_t>(kHeatmapCols * kHeatmapRows), 0xFF) {
    setMouseTracking(true);
    setSizePolicy(QSizePolicy::Preferred, QSizePolicy::Fixed);
    update(m_controller.heatmapCounts());
    connect(&m_controller, &EmulatorController::heatmapChanged, this, [this] { update(m_controller.heatmapCounts()); });
}

int RomHeatmapWidget::heightForWidth(int w) const {
    double cell = std::max(2.0, static_cast<double>(w) / kHeatmapCols);
    return static_cast<int>(kHeatmapRows * cell);
}

void RomHeatmapWidget::setCurrentPC(int pc) {
    if (pc == m_currentPC) return;
    m_currentPC = pc;
    QWidget::update();
}

void RomHeatmapWidget::update(const std::vector<uint32_t>& counts) {
    bool changed = false;
    for (int addr = 0; addr < kHeatmapCols * kHeatmapRows; ++addr) {
        uint8_t step = cu59::heatStep(addr < static_cast<int>(counts.size()) ? counts[static_cast<size_t>(addr)] : 0);
        if (step == m_steps[static_cast<size_t>(addr)]) continue;
        m_steps[static_cast<size_t>(addr)] = step;
        const cu59::Rgb& c = cu59::kHeatColors[step];
        m_image.setPixel(addr % kHeatmapCols, addr / kHeatmapCols, qRgb(c.r, c.g, c.b));
        changed = true;
    }
    setFixedHeight(heightForWidth(width()));
    if (changed) QWidget::update();
}

void RomHeatmapWidget::paintEvent(QPaintEvent*) {
    QPainter p(this);
    p.setRenderHint(QPainter::SmoothPixmapTransform, false);
    p.drawImage(rect(), m_image);
    if (m_currentPC >= 0 && m_currentPC < kHeatmapCols * kHeatmapRows) {
        double cw = static_cast<double>(width()) / kHeatmapCols, ch = static_cast<double>(height()) / kHeatmapRows;
        p.fillRect(QRectF((m_currentPC % kHeatmapCols) * cw, (m_currentPC / kHeatmapCols) * ch, std::max(1.0, cw - 0.5),
                          std::max(1.0, ch - 0.5)), Qt::green);
    }
}

int RomHeatmapWidget::addressAt(const QPointF& pos) const {
    int col = static_cast<int>(pos.x() / (static_cast<double>(width()) / kHeatmapCols));
    int row = static_cast<int>(pos.y() / (static_cast<double>(height()) / kHeatmapRows));
    if (col < 0 || col >= kHeatmapCols || row < 0 || row >= kHeatmapRows) return -1;
    return row * kHeatmapCols + col;
}

void RomHeatmapWidget::mouseMoveEvent(QMouseEvent* e) { emit hoveredAddressChanged(addressAt(e->position())); }

void RomHeatmapWidget::leaveEvent(QEvent*) { emit hoveredAddressChanged(-1); }
