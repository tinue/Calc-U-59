import Foundation

// MARK: - LED Font Style

enum LEDFontStyle: Int, CaseIterable, Identifiable {
    case modernized = 0
    case classic    = 1

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .modernized: return "Modernized"
        case .classic:    return "Classic"
        }
    }
}

// MARK: - Keyboard Feedback Type

enum KeyboardFeedbackType: Int, CaseIterable, Identifiable {
    case off    = 0
    case haptic = 1
    case click  = 2

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .off:    return "Off"
        case .haptic: return "Haptic"
        case .click:  return "Click Sound"
        }
    }
}

// MARK: - UserDefaults keys

enum SettingsKey {
    // Shared with the Qt app (Shared/SettingsKeys.hpp)
    static let startupModel           = TISettings.startupModelKey        // Int: MachineModel.rawValue, or -1 = last used
    static let lastUsedModel          = TISettings.lastUsedModelKey       // Int: MachineModel.rawValue
    static let solidStateModuleID     = TISettings.solidStateModuleIDKey  // String: module ID
    static let traceMaxFileSizeMB     = TISettings.traceMaxFileSizeMBKey  // Int: maximum trace file size in MB
    static let ledFontStyle           = TISettings.ledFontStyleKey        // Int: LEDFontStyle.rawValue
    // Swift only
    static let traceLocation          = "traceLocation"            // Int: TraceLocation.rawValue
    static let traceCustomPath        = "traceCustomPath"          // String: absolute directory path (macOS only)
    static let traceCustomPathBookmark = "traceCustomPathBookmark" // Data: security-scoped bookmark for custom path
    static let keyboardFeedback       = "keyboardFeedback"         // Int: KeyboardFeedbackType.rawValue
    static let portraitDebugPage      = "portraitDebugPage"        // Bool: show Debug as third portrait page (default false)
}

// MARK: - Trace file location

enum TraceLocation: Int, CaseIterable {
    case local   = 0   // ~/Library/Application Support/Calc-U-59/ (default — no TCC, always writable)
    case iCloud  = 1   // CardStorage.directoryURL (iCloud when available)
    case custom  = 2   // user-chosen directory, path stored in traceCustomPath (macOS only)

    var displayName: String {
        switch self {
        case .local:   return "Local (App Library)"
        case .iCloud:  return "iCloud"
        case .custom:  return "Custom Folder"
        }
    }
}

// MARK: - AppSettings

enum AppSettings {

    /// Resolve the LED font style from UserDefaults.
    /// Defaults to modernized if not set.
    static func resolvedLEDFontStyle() -> LEDFontStyle {
        let raw = UserDefaults.standard.object(forKey: SettingsKey.ledFontStyle) as? Int
        return LEDFontStyle(rawValue: raw ?? LEDFontStyle.modernized.rawValue) ?? .modernized
    }

    /// Resolve the keyboard feedback type from UserDefaults.
    /// Defaults to off if not set.
    static func resolvedKeyboardFeedback() -> KeyboardFeedbackType {
        let raw = UserDefaults.standard.object(forKey: SettingsKey.keyboardFeedback) as? Int
        return KeyboardFeedbackType(rawValue: raw ?? KeyboardFeedbackType.off.rawValue) ?? .off
    }

    /// Resolve the trace location from UserDefaults, with platform-aware defaults.
    /// Uses object(forKey:) to distinguish "not set" from "set to 0".
    static func resolvedTraceLocation() -> TraceLocation {
        let raw = UserDefaults.standard.object(forKey: SettingsKey.traceLocation) as? Int
        if let rawInt = raw {
            return TraceLocation(rawValue: rawInt) ?? .local
        } else {
            // Key not set; use platform default
            #if os(macOS)
            return .local
            #else
            return .iCloud
            #endif
        }
    }

    /// The model to launch at startup: the stored one, else the last used, else TI-59
    /// (Shared/SettingsKeys.hpp resolveStartupModel).
    static func resolvedStartupModel() -> MachineModel {
        let d = UserDefaults.standard
        let raw = TISettings.resolveStartupModel(d.object(forKey: SettingsKey.startupModel) as? NSNumber,
                                                 lastUsed: d.object(forKey: SettingsKey.lastUsedModel) as? NSNumber)
        return MachineModel(rawValue: raw) ?? .ti59
    }

    /// Maximum trace file size in MB (default when unset or not positive).
    static func resolvedTraceMaxMB() -> Int {
        TISettings.resolveTraceMaxMB(UserDefaults.standard.object(forKey: SettingsKey.traceMaxFileSizeMB) as? NSNumber)
    }

    /// The solid-state module ID (default "ML").
    static func resolvedSolidStateModuleID() -> String {
        TISettings.resolveModuleID(UserDefaults.standard.string(forKey: SettingsKey.solidStateModuleID))
    }

    /// Returns the directory URL where the trace file should be written.
    /// For custom paths on macOS, uses a security-scoped bookmark to gain file access.
    /// The caller (TraceWriter.open) is responsible for creating the directory if needed.
    static func traceDirectory() -> URL {
        let location = resolvedTraceLocation()
        switch location {
        case .local:
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let url = appSupport.appendingPathComponent("Calc-U-59", isDirectory: true)
            return url
        case .iCloud:
            return CardStorage.directoryURL
        case .custom:
            #if os(macOS)
            // Try to use security-scoped bookmark first (macOS only)
            if let bookmarkData = UserDefaults.standard.data(forKey: SettingsKey.traceCustomPathBookmark) {
                var isStale = false
                do {
                    let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                    if !isStale {
                        let granted = url.startAccessingSecurityScopedResource()
                        if !granted {
                            print("[AppSettings] startAccessingSecurityScopedResource() returned false for \(url.path) — sandbox extension not granted, trace writes to this folder will fail")
                        }
                        return url
                    } else {
                        print("[AppSettings] Security-scoped bookmark for custom trace path is stale — falling back to plain path")
                    }
                } catch {
                    print("[AppSettings] Failed to resolve security-scoped bookmark for custom trace path: \(error)")
                }
            }
            #endif

            // Fallback to stored path
            let path = UserDefaults.standard.string(forKey: SettingsKey.traceCustomPath) ?? ""
            if !path.isEmpty {
                print("[AppSettings] Using plain (non-bookmarked) custom trace path: \(path) — this will fail to write under App Sandbox without an active security scope")
                return URL(fileURLWithPath: path, isDirectory: true)
            }

            // Custom path not set: fall back to local App Library.
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let url = appSupport.appendingPathComponent("Calc-U-59", isDirectory: true)
            return url
        }
    }
    
    /// Check if the custom trace path needs re-authorization (has path but no valid bookmark).
    static func customTracePathNeedsReauthorization() -> Bool {
        #if os(macOS)
        let path = UserDefaults.standard.string(forKey: SettingsKey.traceCustomPath) ?? ""
        let hasPath = !path.isEmpty
        let hasBookmark = UserDefaults.standard.data(forKey: SettingsKey.traceCustomPathBookmark) != nil
        return hasPath && !hasBookmark
        #else
        return false
        #endif
    }
    
    /// Save a custom trace directory and create a security-scoped bookmark for it (macOS only).
    static func setCustomTraceDirectory(_ url: URL) {
        #if os(macOS)
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(url.path, forKey: SettingsKey.traceCustomPath)
            UserDefaults.standard.set(bookmark, forKey: SettingsKey.traceCustomPathBookmark)
            UserDefaults.standard.synchronize()
        } catch {
            // Fallback: just save the path without bookmark
            UserDefaults.standard.set(url.path, forKey: SettingsKey.traceCustomPath)
            UserDefaults.standard.removeObject(forKey: SettingsKey.traceCustomPathBookmark)
            UserDefaults.standard.synchronize()
        }
        #else
        UserDefaults.standard.set(url.path, forKey: SettingsKey.traceCustomPath)
        #endif
    }
}
