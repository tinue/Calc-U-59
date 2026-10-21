#pragma once
#include "SettingsKeys.hpp"
#include <QDir>
#include <QFileInfo>
#include <QSettings>
#include <QString>
#include <optional>

// Persistent settings. The keys both apps store, their defaults and how they
// resolve live in Shared/SettingsKeys.hpp. The trace location keys and the iOS-only keys
// (keyboard feedback, portrait debug page) have no Qt counterpart; the Qt
// app has its own folder keys instead (below, laid out as in Calc-U-1600),
// where the Swift app has iCloud Documents and the system file importer.
namespace AppSettings {

inline QSettings store() { return QSettings(QStringLiteral("Calc-U-59"), QStringLiteral("Calc-U-59")); }

template <class T> T value(const char* key, const T& fallback) {
    return store().value(QLatin1String(key), QVariant::fromValue(fallback)).template value<T>();
}
template <class T> void setValue(const char* key, const T& v) { store().setValue(QLatin1String(key), v); }

// ── Keys shared with the Swift app ───────────────────────────────────────────
using cu59::settings::kLastUsedModel;
using cu59::settings::kLedFontStyle;
using cu59::settings::kSolidStateModuleID;
using cu59::settings::kStartupModel;
using cu59::settings::kTraceMaxFileSizeMB;

// ── Qt only ──────────────────────────────────────────────────────────────────
/// String: cards and ti58c.mem; empty = ~/Calc-U-59 (AppPaths::cardDir()).
inline constexpr const char* kCardDirOverride = "storage/cardDirOverride";
/// String: CALCU59_TRACE.bin and KEYSTROKES traces; empty = the card folder (AppPaths::traceDir()).
inline constexpr const char* kTraceDirOverride = "trace/dirOverride";
inline constexpr const char* kWindowGeometry = "windowGeometry";
inline constexpr const char* kSplitterState = "splitterState";

/// The folders the file-open dialogs start in, one per kind of file:
///   Presets     -- "Open Preset…" (.ti59 / .ti58 / .ti58c), a row in Settings
///   AsmOverlays -- the debugger's ASM overlay picker (last used only)
enum class OpenFolder { Presets, AsmOverlays };

inline QString openFolderKeyGroup(OpenFolder folder) {
    return folder == OpenFolder::Presets ? QStringLiteral("preset/") : QStringLiteral("asm/");
}

/// "<group>openDir": a fixed start folder set in Settings. Empty -- the
/// default, and what Reset restores -- means "<last used>".
inline QString openDir(OpenFolder folder) {
    return store().value(openFolderKeyGroup(folder) + QStringLiteral("openDir")).toString();
}

inline void setOpenDir(OpenFolder folder, const QString& dir) {
    const QString key = openFolderKeyGroup(folder) + QStringLiteral("openDir");
    if (dir.isEmpty()) store().remove(key);
    else store().setValue(key, dir);
}

/// "<group>lastOpenDir": the folder of the file last picked in that dialog,
/// recorded on every pick but only used while openDir() is unset.
inline QString lastOpenDir(OpenFolder folder) {
    return store().value(openFolderKeyGroup(folder) + QStringLiteral("lastOpenDir")).toString();
}

inline void rememberOpenFile(OpenFolder folder, const QString& filePath) {
    store().setValue(openFolderKeyGroup(folder) + QStringLiteral("lastOpenDir"), QFileInfo(filePath).absolutePath());
}

/// The start folder of that dialog: the fixed one, else the last used, else home.
inline QString openStartDir(OpenFolder folder) {
    QString dir = openDir(folder);
    if (dir.isEmpty()) dir = lastOpenDir(folder);
    return dir.isEmpty() ? QDir::homePath() : dir;
}

template <class T> std::optional<T> stored(const char* key) {
    QVariant v = store().value(QLatin1String(key));
    if (!v.isValid()) return std::nullopt;
    return v.value<T>();
}

/// Startup model: the stored one, else the last used, else TI-59.
inline cu59::Model resolvedStartupModel() {
    return cu59::settings::resolveStartupModel(stored<int>(kStartupModel), stored<int>(kLastUsedModel));
}

inline QString resolvedSolidStateModuleID() {
    auto id = stored<QString>(kSolidStateModuleID);
    return QString::fromStdString(cu59::settings::resolveModuleID(id ? std::optional<std::string>(id->toStdString()) : std::nullopt));
}

inline int resolvedTraceMaxMB() { return cu59::settings::resolveTraceMaxMB(stored<int>(kTraceMaxFileSizeMB)); }

} // namespace AppSettings
