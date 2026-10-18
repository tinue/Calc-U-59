#include "AppPaths.hpp"
#include "AppSettings.hpp"
#include <QDir>
#include <QStandardPaths>

namespace AppPaths {

namespace {
QString ensure(const QString& dir) {
    QDir().mkpath(dir);
    return dir;
}
} // namespace

QString documentsDir() {
    QString dir = AppSettings::value<QString>(AppSettings::kDocumentsDir, QString());
    if (dir.isEmpty())
        dir = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation) + QStringLiteral("/Calc-U-59");
    return ensure(dir);
}

// Cards live directly in the documents folder, as in the Swift app's iCloud folder.
QString cardsDir() { return documentsDir(); }

QString constantMemoryFile() { return documentsDir() + QStringLiteral("/ti58c.mem"); }

QString traceDir() {
    if (AppSettings::value<int>(AppSettings::kTraceLocation, 0) == 2) {
        QString custom = AppSettings::value<QString>(AppSettings::kTraceCustomPath, QString());
        if (!custom.isEmpty()) return ensure(custom);
    }
    return ensure(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/Calc-U-59"));
}

std::filesystem::path toFsPath(const QString& path) {
#ifdef _WIN32
    return std::filesystem::path(path.toStdWString());
#else
    return std::filesystem::path(path.toStdString());
#endif
}

} // namespace AppPaths
