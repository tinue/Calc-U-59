#pragma once
#include "LedGeometry.hpp"
#include <QPixmap>
#include <QWidget>

class EmulatorController;

// The calculator canvas: base artwork (2064×4075) with the LED display and cue
// card painted over it, key hit-testing with the widened rects from
// Shared/KeyboardLayout, the pressed-key effect, press-and-hold on the display
// for full speed, and the physical keyboard via Shared/KeyboardMap. The
// counterpart of App/Views/KeyboardView.swift.
class KeyboardWidget : public QWidget {
    Q_OBJECT
public:
    explicit KeyboardWidget(EmulatorController& controller, QWidget* parent = nullptr);

    bool hasHeightForWidth() const override { return true; }
    int heightForWidth(int w) const override;
    QSize sizeHint() const override;
    /// Re-read the LED style (after the Settings dialog).
    void reloadSettings();

protected:
    void paintEvent(QPaintEvent* e) override;
    void mousePressEvent(QMouseEvent* e) override;
    void mouseMoveEvent(QMouseEvent* e) override;
    void mouseReleaseEvent(QMouseEvent* e) override;
    void keyPressEvent(QKeyEvent* e) override;
    void keyReleaseEvent(QKeyEvent* e) override;
    void focusOutEvent(QFocusEvent* e) override;
    void hideEvent(QHideEvent* e) override;

private:
    QRectF canvasRect() const;
    void pointer(const QPointF& pos);
    void releasePointer();
    std::vector<uint8_t> matrixCodes(const QKeyEvent* e) const;

    EmulatorController& m_controller;
    QPixmap m_base;
    QPixmap m_scaled;        ///< m_base at the canvas's device size
    cu59::LedStyle m_ledStyle = cu59::LedStyle::Modernized;
    int m_pressedKey = -1;   ///< row × 5 + col held by the pointer
    bool m_displayPressed = false;
};
