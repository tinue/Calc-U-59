#pragma once
#include <QWidget>

class EmulatorController;
class QPlainTextEdit;
class QPushButton;

// LOG tab: the debug log (ring buffer tail), dumps (SCOM, Memory, Prog, Vars),
// clear, the binary TRACE toggle and the log level (StaticDebugContent in
// App/Views/DebugView.swift).
class LogWidget : public QWidget {
    Q_OBJECT
public:
    explicit LogWidget(EmulatorController& controller, QWidget* parent = nullptr);

private:
    void refresh();

    EmulatorController& m_controller;
    QPlainTextEdit* m_text;
    QPushButton* m_clear;
    QPushButton* m_trace;
    QPushButton* m_level;
};
