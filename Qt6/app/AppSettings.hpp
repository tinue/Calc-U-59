#pragma once
#include <QSettings>
#include <QString>

// Persistent settings. Key names are identical to the Swift app's
// SettingsKey (App/AppSettings.swift) — keep them in sync (CLAUDE.md
// § "Frontend Parity"). The iCloud trace location and the iOS-only keys
// (keyboard feedback, portrait debug page) have no Qt counterpart; the Qt
// app adds the documents folder, where the Swift app has iCloud Documents.
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
inline constexpr const char* kTraceLocation = "traceLocation";           ///< Int: 0 local (default), 2 custom
inline constexpr const char* kTraceCustomPath = "traceCustomPath";       ///< String: custom trace folder

// ── Qt only ──────────────────────────────────────────────────────────────────
inline constexpr const char* kDocumentsDir = "documentsDir";  ///< String: cards and ti58c.mem; empty = default
inline constexpr const char* kLastPresetDir = "lastPresetDir";
inline constexpr const char* kLastAsmDir = "lastAsmDir";
inline constexpr const char* kWindowGeometry = "windowGeometry";
inline constexpr const char* kSplitterState = "splitterState";

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
