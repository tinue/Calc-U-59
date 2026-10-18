#include "CalculatorPanel.hpp"
#include "ChromeStyle.hpp"
#include "ControlBar.hpp"
#include "KeyboardWidget.hpp"
#include <QVBoxLayout>

CalculatorPanel::CalculatorPanel(EmulatorController& controller, QWidget* parent) : QWidget(parent) {
    setAutoFillBackground(true);
    QPalette pal = palette();
    pal.setColor(QPalette::Window, ChromeStyle::kPanel);
    setPalette(pal);
    auto* col = new QVBoxLayout(this);
    col->setContentsMargins(8, 8, 8, 8);
    col->setSpacing(0);
    m_keyboard = new KeyboardWidget(controller, this);
    col->addWidget(m_keyboard, 1);
    m_bar = new ControlBar(controller, this);
    col->addWidget(m_bar);
}
