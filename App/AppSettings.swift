import Foundation

// MARK: - UserDefaults keys

enum SettingsKey {
    static let startupModel           = "startupModel"             // Int: MachineModel.rawValue, or -1 = last used
    static let lastUsedModel          = "lastUsedModel"            // Int: MachineModel.rawValue
    static let traceLocation          = "traceLocation"            // Int: TraceLocation.rawValue
    static let traceCustomPath        = "traceCustomPath"          // String: absolute directory path (macOS only)
    static let traceCustomPathBookmark = "traceCustomPathBookmark" // Data: security-scoped bookmark for custom path
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

    /// Returns the model to launch at startup.
    /// If `startupModel` has never been set, defaults to "last used" → TI-59.
    static func resolvedStartupModel() -> MachineModel {
        // object(forKey:) returns nil when the key is absent, distinguishing that
        // from an explicit 0 (TI-59). Absent key → treat as -1 (last used).
        let stored = UserDefaults.standard.object(forKey: SettingsKey.startupModel) as? Int
        let raw = stored ?? -1
        if raw == -1 {
            let lastRaw = UserDefaults.standard.integer(forKey: SettingsKey.lastUsedModel)
            return MachineModel(rawValue: lastRaw) ?? .ti59
        }
        return MachineModel(rawValue: raw) ?? .ti59
    }

    /// Returns the directory URL where the trace file should be written.
    /// For custom paths on macOS, uses a security-scoped bookmark to gain file access.
    /// The caller (TraceWriter.open) is responsible for creating the directory if needed.
    static func traceDirectory() -> URL {
        let raw = UserDefaults.standard.integer(forKey: SettingsKey.traceLocation)
        let location = TraceLocation(rawValue: raw) ?? .local
        switch location {
        case .local:
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let url = appSupport.appendingPathComponent("Calc-U-59", isDirectory: true)
            return url
        case .iCloud:
            return CardStorage.directoryURL
        case .custom:
            // Try to use security-scoped bookmark first
            if let bookmarkData = UserDefaults.standard.data(forKey: SettingsKey.traceCustomPathBookmark) {
                var isStale = false
                do {
                    let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                    if !isStale {
                        _ = url.startAccessingSecurityScopedResource()
                        return url
                    }
                } catch {
                    // silently fall through to fallback
                }
            }
            
            // Fallback to stored path
            let path = UserDefaults.standard.string(forKey: SettingsKey.traceCustomPath) ?? ""
            if !path.isEmpty {
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
