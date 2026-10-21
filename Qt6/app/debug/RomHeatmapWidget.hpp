#pragma once
#include <QImage>
#include <QWidget>
#include <vector>

class EmulatorController;

// ROM HEATMAP: 80×64 cells (one per code address), coloured by
// Shared/RomHeatmap's heat steps, repainted incrementally (steps only grow),
// with the current PC as a green cell and the hovered address shown in the
// header. Part of App/Views/CPUInspectorView.swift.
class RomHeatmapWidget : public QWidget {
    Q_OBJECT
public:
    explicit RomHeatmapWidget(EmulatorController& controller, QWidget* parent = nullptr);
    void setCurrentPC(int pc);

    bool hasHeightForWidth() const override { return true; }
    int heightForWidth(int w) const override;

signals:
    void hoveredAddressChanged(int address);  ///< -1 when the pointer leaves

protected:
    void paintEvent(QPaintEvent* e) override;
    void mouseMoveEvent(QMouseEvent* e) override;
    void leaveEvent(QEvent* e) override;

private:
    void update(const std::vector<uint32_t>& counts);
    int addressAt(const QPointF& pos) const;

    EmulatorController& m_controller;
    QImage m_image;
    std::vector<uint8_t> m_steps;
    int m_currentPC = -1;
};
