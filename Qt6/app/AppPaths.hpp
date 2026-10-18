#pragma once
#include <QString>
#include <filesystem>

// Where the Qt app keeps files. The Swift app uses iCloud Documents
// (App/CardStorage.swift); the Qt app a local folder, ~/Documents/Calc-U-59
// by default, configurable in Settings.
namespace AppPaths {

/// Cards, ti58c.mem: the configured documents folder (created on demand).
QString documentsDir();
QString cardsDir();
QString constantMemoryFile();

/// Binary trace files: the custom folder if set, else
/// <AppDataLocation>/Calc-U-59 (the Swift app's "Local (App Library)").
QString traceDir();

/// A QString path as std::filesystem::path (wide characters on Windows).
std::filesystem::path toFsPath(const QString& path);

} // namespace AppPaths
