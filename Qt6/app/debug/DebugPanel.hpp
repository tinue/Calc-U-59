#pragma once
#include <QWidget>

class EmulatorController;
class QStackedWidget;
class QToolButton;

// The debug pane: CALCULATOR / CPU / LOG tabs (the CPU tab also holds the ASM
// overlay box). Tabs tell the controller which snapshots to build. The
// counterpart of App/Views/DebugView.swift.
class DebugPanel : public QWidget {
    Q_OBJECT
public:
    explicit DebugPanel(EmulatorController& controller, QWidget* parent = nullptr);

signals:
    void selectAsmFileRequested();

protected:
    void showEvent(QShowEvent* e) override;
    void hideEvent(QHideEvent* e) override;

private:
    void select(int tab);
    void notifyVisibility();

    EmulatorController& m_controller;
    QStackedWidget* m_stack;
    QToolButton* m_tabs[3];
    int m_tab = 0;
};
