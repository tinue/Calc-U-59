import Foundation

/// Manages the single magnetic-card file used for card read/write operations.
///
/// The file (`card.bin`) contains the raw bytes captured by OUT CRD instructions
/// during a write swipe, stored verbatim.  On a read swipe the same bytes are
/// fed back to the hardware via IN CRD — no interpretation is applied.
///
/// Storage location (in priority order):
///   1. iCloud Documents container — syncs across all signed-in devices
///      automatically, provided the "iCloud Documents" capability is enabled
///      in the Xcode target and a matching container ID exists in the entitlements.
///   2. Local app Documents directory — used as a fallback when iCloud is
///      unavailable (simulator without an account, iCloud disabled, etc.).
///
/// To enable iCloud sync: in Xcode → target → Signing & Capabilities → "+ Capability"
/// → iCloud → check "iCloud Documents" and set the container identifier.
struct CardStorage {

    private static let fileName = "card.U59"

    // Resolved once on a background thread; `url(forUbiquityContainerIdentifier:)`
    // must not be called on the main thread — it blocks and returns nil there.
    private static var _resolvedURL: URL?

    static var directoryURL: URL { fileURL.deletingLastPathComponent() }

    static var fileURL: URL {
        if let cached = _resolvedURL { return cached }
        // Fallback used only when warmUp() hasn't completed yet.
        let localDocs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask)[0]
        return localDocs.appendingPathComponent(fileName)
    }

    /// Call once at app start off the main thread so the iCloud container
    /// URL is ready before any file operations or panel opens.
    static func warmUp() {
        if _resolvedURL != nil { return }
        if let cloudBase = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            let docs = cloudBase.appendingPathComponent("Documents", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: docs, withIntermediateDirectories: true)
            _resolvedURL = docs.appendingPathComponent(fileName)
        } else {
            let localDocs = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask)[0]
            _resolvedURL = localDocs.appendingPathComponent(fileName)
        }
    }

    /// `true` when a card file is present on disk.
    static var hasCard: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Overwrite the card file with `data`.  Atomic write prevents corruption
    /// if the process is interrupted mid-write.
    static func write(_ data: Data) throws {
        try data.write(to: fileURL, options: .atomic)
    }

    /// Read and return the card file contents.
    static func read() throws -> Data {
        try Data(contentsOf: fileURL)
    }
}
