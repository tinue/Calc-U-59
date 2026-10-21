#pragma once
#include <QTimer>
#include <QWidget>

class EmulatorController;
class QComboBox;
class QToolButton;

// The bar under the calculator: Reset (Ctrl/Cmd held: red "Clean" reset),
// model picker, the card buttons (TI-59 only), and Preset. The counterpart
// of CalculatorView.cardReaderBar in App/Views/CalculatorView.swift.
class ControlBar : public QWidget {
    Q_OBJECT
public:
    explicit ControlBar(EmulatorController& controller, QWidget* parent = nullptr);

signals:
    void openPresetRequested();
    void loadCardRequested();
    void newCardRequested();

private:
    void refresh();
    void pollModifiers();

    EmulatorController& m_controller;
    QToolButton* m_reset;
    QComboBox* m_model;
    QToolButton* m_loadCard;
    QToolButton* m_newCard;
    QToolButton* m_eject;
    QTimer m_modifierPoll;
    bool m_cleanMode = false;
};
