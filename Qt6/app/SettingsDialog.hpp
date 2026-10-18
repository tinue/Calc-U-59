#pragma once
#include <QDialog>

class EmulatorController;
class QComboBox;
class QLabel;
class QSpinBox;
class QPushButton;

// Settings: startup calculator, solid-state module, segment style, trace
// file location and size limit — as App/Views/SettingsView.swift — plus the
// documents folder (cards, ti58c.mem) the Qt app keeps where the Swift app
// uses iCloud Documents. A module change applies on close (soft reset).
class SettingsDialog : public QDialog {
    Q_OBJECT
public:
    explicit SettingsDialog(EmulatorController& controller, QWidget* parent = nullptr);

private:
    void done(int r) override;
    void refreshPaths();

    EmulatorController& m_controller;
    QComboBox* m_startup;
    QComboBox* m_module;
    QComboBox* m_style;
    QComboBox* m_traceLocation;
    QLabel* m_tracePath;
    QPushButton* m_traceChoose;
    QSpinBox* m_maxMB;
    QLabel* m_docsPath;
};
