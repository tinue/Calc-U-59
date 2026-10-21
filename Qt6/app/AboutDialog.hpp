#pragma once
#include <QDialog>

// About Calc-U-59: version and build, a short description and the project
// links (the Swift app's About panel, App/AppInfo.swift).
class AboutDialog : public QDialog {
    Q_OBJECT
public:
    explicit AboutDialog(QWidget* parent = nullptr);
};
