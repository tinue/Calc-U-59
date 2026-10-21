#pragma once
#include <QWidget>

class EmulatorController;
class QLabel;
class QPushButton;

// ASM OVERLAY box under the CPU inspector: file, word count, status, and
// Select File / Run / Clear (ASMDebugContent in App/Views/DebugView.swift).
class AsmOverlayBox : public QWidget {
    Q_OBJECT
public:
    explicit AsmOverlayBox(EmulatorController& controller, QWidget* parent = nullptr);

signals:
    void selectFileRequested();

private:
    void refresh();

    EmulatorController& m_controller;
    QLabel* m_file;
    QLabel* m_words;
    QLabel* m_status;
    QPushButton* m_run;
};
