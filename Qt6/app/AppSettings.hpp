#pragma once
#include <QDir>
#include <QFileInfo>
#include <QSettings>
#include <QString>

// Persistent settings. Key names are identical to the Swift app's
// SettingsKey (App/AppSettings.swift) — keep them in sync (CLAUDE.md
// § "Frontend Parity"). The trace location keys and the iOS-only keys
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
inline constexpr const char* kStartupModel = "startupModel";            ///< Int: model raw value, -1 = last used
inline constexpr const char* kLastUsedModel = "lastUsedModel";          ///< Int: model raw value
inline constexpr const char* kSolidStateModuleID = "solidStateModuleID"; ///< String, default "ML"
inline constexpr const char* kTraceMaxFileSizeMB = "traceMaxFileSizeMB"; ///< Int, default 50
inline constexpr const char* kLedFontStyle = "ledFontStyle";             ///< Int: 0 modernized, 1 classic

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

/// Startup model: the stored one, or the last used (default TI-59).
inline int resolvedStartupModel() {
    int raw = value<int>(kStartupModel, -1);
    if (raw < 0 || raw > 2) raw = value<int>(kLastUsedModel, 0);
    return (raw >= 0 && raw <= 2) ? raw : 0;
}

inline QString resolvedSolidStateModuleID() { return value<QString>(kSolidStateModuleID, QStringLiteral("ML")); }

inline int resolvedTraceMaxMB() {
    int mb = value<int>(kTraceMaxFileSizeMB, 50);
    return mb > 0 ? mb : 50;
}

} // namespace AppSettings
