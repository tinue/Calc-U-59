#pragma once
#include <QWidget>

class EmulatorController;
class QLabel;
class QPushButton;
class QScrollArea;
class QStackedWidget;
class QPlainTextEdit;
class PaperView;

// The PC-100C printer panel: connect toggle (resets the machine), dot / text
// view of the paper strip (Shared/PrinterFont font and geometry), PRINT, T
// (TRACE latch) and ADV, and copy / cut — text plus a 600 dpi image on the
// clipboard. The counterpart of App/Views/PrinterView.swift.
class PrinterWidget : public QWidget {
    Q_OBJECT
public:
    explicit PrinterWidget(EmulatorController& controller, QWidget* parent = nullptr);

protected:
    void resizeEvent(QResizeEvent* e) override;

private:
    void refresh();
    void copyToClipboard();
    void showToast();

    EmulatorController& m_controller;
    QPushButton* m_connect;
    QPushButton* m_mode;
    QPushButton* m_trace;
    QPushButton* m_print;
    QPushButton* m_copy;
    QPushButton* m_cut;
    QStackedWidget* m_stack;
    QScrollArea* m_scroll;
    PaperView* m_paper;
    QPlainTextEdit* m_text;
    QLabel* m_toast;
    bool m_dotMode = true;
};
