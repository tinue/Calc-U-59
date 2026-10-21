#pragma once
#include <QDialog>
#include <functional>

class EmulatorController;
class QComboBox;
class QGridLayout;
class QSpinBox;

// Settings: startup calculator, solid-state module, segment style, trace
// size limit — as App/Views/SettingsView.swift — plus the Qt app's folders
// (AppPaths), laid out as in Calc-U-1600: where Open Preset starts, the card
// folder (cards, ti58c.mem; the Swift app uses iCloud Documents) and the
// trace folder. A module change applies on close (soft reset).
class SettingsDialog : public QDialog {
    Q_OBJECT
public:
    explicit SettingsDialog(EmulatorController& controller, QWidget* parent = nullptr);

private:
    void done(int r) override;
    void addFolderRow(QGridLayout* grid, const QString& label, const QString& dialogTitle,
                      std::function<QString()> display, std::function<QString()> startDir,
                      std::function<bool()> isOverridden, std::function<void(const QString&)> set);
    static void setOverride(const char* key, const QString& dir);

    EmulatorController& m_controller;
    QComboBox* m_startup;
    QComboBox* m_module;
    QComboBox* m_style;
    QSpinBox* m_maxMB;
};
