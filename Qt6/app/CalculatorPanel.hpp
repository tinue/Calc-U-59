#pragma once
#include <QWidget>

class ControlBar;
class EmulatorController;
class KeyboardWidget;

// The calculator column: canvas above, control bar below, on the dark panel
// colour (CalculatorView.calculatorBody in the Swift app).
class CalculatorPanel : public QWidget {
    Q_OBJECT
public:
    explicit CalculatorPanel(EmulatorController& controller, QWidget* parent = nullptr);
    KeyboardWidget* keyboard() const { return m_keyboard; }
    ControlBar* controlBar() const { return m_bar; }

private:
    KeyboardWidget* m_keyboard;
    ControlBar* m_bar;
};
