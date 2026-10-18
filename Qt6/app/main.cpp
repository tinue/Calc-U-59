#include "AppSettings.hpp"
#include "EmulatorController.hpp"
#include "MainWindow.hpp"
#include <QApplication>
#include <QFileOpenEvent>
#include <QIcon>
#include <QPalette>
#include <QStyleFactory>
#include <QTimer>

namespace {

/// Catches files opened from the Dock or Finder (macOS QFileOpenEvent), which
/// can arrive before the window exists.
class App : public QApplication {
public:
    using QApplication::QApplication;
    MainWindow* window = nullptr;
    QString pendingFile;

protected:
    bool event(QEvent* e) override {
        if (e->type() == QEvent::FileOpen) {
            QString path = static_cast<QFileOpenEvent*>(e)->file();
            if (window) window->openStateFile(path);
            else pendingFile = path;
            return true;
        }
        return QApplication::event(e);
    }
};

/// The Swift app is always dark (preferredColorScheme(.dark)); so is this.
void applyDarkPalette(QApplication& app) {
    app.setStyle(QStyleFactory::create(QStringLiteral("Fusion")));
    QPalette p;
    p.setColor(QPalette::Window, QColor(37, 37, 37));
    p.setColor(QPalette::WindowText, Qt::white);
    p.setColor(QPalette::Base, QColor(28, 28, 28));
    p.setColor(QPalette::AlternateBase, QColor(45, 45, 45));
    p.setColor(QPalette::Text, Qt::white);
    p.setColor(QPalette::Button, QColor(50, 50, 50));
    p.setColor(QPalette::ButtonText, Qt::white);
    p.setColor(QPalette::Highlight, QColor(10, 132, 255));
    p.setColor(QPalette::HighlightedText, Qt::white);
    p.setColor(QPalette::ToolTipBase, QColor(50, 50, 50));
    p.setColor(QPalette::ToolTipText, Qt::white);
    p.setColor(QPalette::Disabled, QPalette::Text, QColor(128, 128, 128));
    p.setColor(QPalette::Disabled, QPalette::ButtonText, QColor(128, 128, 128));
    app.setPalette(p);
}

} // namespace

int main(int argc, char* argv[]) {
    App app(argc, argv);
    QApplication::setApplicationName(QStringLiteral("Calc-U-59"));
    QApplication::setOrganizationName(QStringLiteral("Calc-U-59"));
    QApplication::setWindowIcon(QIcon(QStringLiteral(":/app/icon.png")));
    applyDarkPalette(app);

    EmulatorController controller;
    MainWindow window(controller);
    app.window = &window;
    controller.start(static_cast<cu59::Model>(AppSettings::resolvedStartupModel()));
    window.show();

    // Developer option: --grab <file.png> [--after <ms>] saves a screenshot of the
    // window and quits (run with QT_QPA_PLATFORM=offscreen to check rendering
    // without showing a window). Any other argument is a state file to open.
    QStringList args = QApplication::arguments();
    QString grabPath;
    int grabAfter = 3000;
    QString stateFile;
    for (int i = 1; i < args.size(); ++i) {
        if (args[i] == QLatin1String("--grab") && i + 1 < args.size()) grabPath = args[++i];
        else if (args[i] == QLatin1String("--after") && i + 1 < args.size()) grabAfter = args[++i].toInt();
        else stateFile = args[i];
    }
    if (!stateFile.isEmpty()) window.openStateFile(stateFile);
    else if (!app.pendingFile.isEmpty()) window.openStateFile(app.pendingFile);
    if (!grabPath.isEmpty()) {
        QTimer::singleShot(grabAfter, &window, [&window, grabPath] {
            window.grab().save(grabPath);
            QApplication::quit();
        });
    }
    return QApplication::exec();
}
