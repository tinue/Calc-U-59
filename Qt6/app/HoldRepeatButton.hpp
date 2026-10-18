#pragma once
#include <QTimer>
#include <QToolButton>

// A button that fires once on press and then repeats while held (the debug
// headers' STEP). Counterpart of App/Views/HoldRepeatButton.swift: same
// 0.25 s repeat interval.
class HoldRepeatButton : public QToolButton {
    Q_OBJECT
public:
    explicit HoldRepeatButton(const QString& text, QWidget* parent = nullptr);

signals:
    void fired();

protected:
    void mousePressEvent(QMouseEvent* e) override;
    void mouseReleaseEvent(QMouseEvent* e) override;
    void hideEvent(QHideEvent* e) override;

private:
    QTimer m_repeat;
};
