#include "AppPaths.hpp"
#include "AppSettings.hpp"
#include <QDir>

namespace AppPaths {

namespace {
QString ensure(const QString& dir) {
    QDir().mkpath(dir);
    return dir;
}

QString overrideOr(const char* key, const QString& fallback) {
    const QString dir = AppSettings::value<QString>(key, QString());
    return dir.isEmpty() ? fallback : ensure(dir);
}
} // namespace

QString defaultDir() { return ensure(QDir::homePath() + QStringLiteral("/Calc-U-59")); }

QString cardDir() { return overrideOr(AppSettings::kCardDirOverride, defaultDir()); }

QString constantMemoryFile() { return cardDir() + QStringLiteral("/ti58c.mem"); }

QString traceDir() { return overrideOr(AppSettings::kTraceDirOverride, cardDir()); }

QString displayPath(const QString& path) {
    const QString home = QDir::homePath();
    if (path == home || path.startsWith(home + QLatin1Char('/')))
        return QDir::toNativeSeparators(QStringLiteral("~") + path.mid(home.size()));
    return QDir::toNativeSeparators(path);
}

std::filesystem::path toFsPath(const QString& path) {
#ifdef _WIN32
    return std::filesystem::path(path.toStdWString());
#else
    return std::filesystem::path(path.toStdString());
#endif
}

} // namespace AppPaths
