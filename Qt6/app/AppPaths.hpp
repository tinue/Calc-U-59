#pragma once
#include <QString>
#include <filesystem>

// Where the Qt app keeps files, laid out as in Calc-U-1600: one folder in the
// home directory, ~/Calc-U-59, for cards, ti58c.mem and traces, each folder
// overridable in Settings. The Swift app uses iCloud Documents instead
// (App/CardStorage.swift). Where "Open Preset…" starts is an open-dialog
// setting (AppSettings::openStartDir), not a storage folder.
namespace AppPaths {

/// ~/Calc-U-59, created on demand.
QString defaultDir();

/// Cards and ti58c.mem: the card folder override, else defaultDir().
QString cardDir();
QString constantMemoryFile();

/// Binary traces: the trace folder override, else cardDir().
QString traceDir();

/// `path` as labels show it: "~/Calc-U-59/…" or "~/…" when under home.
QString displayPath(const QString& path);

/// A QString path as std::filesystem::path (wide characters on Windows).
std::filesystem::path toFsPath(const QString& path);

} // namespace AppPaths
