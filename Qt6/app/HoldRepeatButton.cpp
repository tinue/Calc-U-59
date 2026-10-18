#include "HoldRepeatButton.hpp"
#include <QMouseEvent>

HoldRepeatButton::HoldRepeatButton(const QString& text, QWidget* parent) : QToolButton(parent) {
    setText(text);
    m_repeat.setInterval(250);
    connect(&m_repeat, &QTimer::timeout, this, &HoldRepeatButton::fired);
}

void HoldRepeatButton::mousePressEvent(QMouseEvent* e) {
    QToolButton::mousePressEvent(e);
    if (!isEnabled() || e->button() != Qt::LeftButton) return;
    emit fired();  // immediate first step
    m_repeat.start();
}

void HoldRepeatButton::mouseReleaseEvent(QMouseEvent* e) {
    m_repeat.stop();
    QToolButton::mouseReleaseEvent(e);
}

void HoldRepeatButton::hideEvent(QHideEvent* e) {
    m_repeat.stop();
    QToolButton::hideEvent(e);
}
