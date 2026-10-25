#pragma once
#include "MachineModelInfo.hpp"
#include <optional>
#include <string>

// Settings more than one frontend stores (UserDefaults in the Swift app,
// QSettings in the Qt app, localStorage in the web client): the key names,
// their defaults and how a stored value resolves. Keys only one app has stay
// in that app (App/AppSettings.swift, Qt6/app/AppSettings.hpp).

namespace cu59::settings {

inline constexpr const char* kStartupModel = "startupModel";            ///< Int: model raw value, -1 = last used
inline constexpr const char* kLastUsedModel = "lastUsedModel";          ///< Int: model raw value
inline constexpr const char* kSolidStateModuleID = "solidStateModuleID"; ///< String
inline constexpr const char* kTraceMaxFileSizeMB = "traceMaxFileSizeMB"; ///< Int: MB
inline constexpr const char* kLedFontStyle = "ledFontStyle";             ///< Int: 0 modernized, 1 classic
inline constexpr const char* kKeyboardFeedback = "keyboardFeedback";     ///< Int: 0 off, 1 haptic, 2 click (Swift, web)

inline constexpr int kStartupLastUsed = -1;
inline constexpr int kDefaultTraceMaxMB = 50;
inline constexpr int kDefaultLedFontStyle = 0;
inline constexpr int kDefaultKeyboardFeedback = 0;
inline constexpr const char* kDefaultModuleID = "ML";

inline bool isModelRaw(int raw) { return raw >= 0 && raw <= 2; }

/// The stored startup model if it names one, else the last used, else TI-59.
inline Model resolveStartupModel(std::optional<int> stored, std::optional<int> lastUsed) {
    if (stored && isModelRaw(*stored)) return static_cast<Model>(*stored);
    if (lastUsed && isModelRaw(*lastUsed)) return static_cast<Model>(*lastUsed);
    return Model::TI59;
}

/// The stored size if positive, else the default.
inline int resolveTraceMaxMB(std::optional<int> stored) {
    return stored && *stored > 0 ? *stored : kDefaultTraceMaxMB;
}

inline std::string resolveModuleID(const std::optional<std::string>& stored) {
    return stored && !stored->empty() ? *stored : std::string(kDefaultModuleID);
}

} // namespace cu59::settings
