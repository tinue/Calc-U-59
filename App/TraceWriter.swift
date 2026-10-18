import Foundation

// ── TraceWriter ───────────────────────────────────────────────────────────────
//
// Swift side of the manual binary trace file (CALCU59_TRACE.bin and friends,
// format in DebugAPI.md): decides WHERE the file goes — the configured trace
// directory (iCloud, local or a custom folder; see AppSettings.traceDirectory())
// — and whether that location is available. The file is written by the
// session's Shared/TraceWriter (Bridge/TITraceWriter, thread-safe); the
// session also drains frames into it and logs key events. The scripted
// KEYSTROKES "Trace:" capture is the session's second writer.
//
// Fresh-file mode: each open() call deletes the existing file and starts fresh.

final class TraceWriter {

    private static let defaultMaxFileSizeMB = 50

    var isOpen: Bool { writer.isOpen }
    private(set) var isAvailable = true  // false if iCloud/storage is unavailable
    private var currentTraceURL: URL?  // Track the URL for security-scoped resource cleanup
    private let model: MachineModel     // Calculator model (determines trace filename)
    private let writer: TITraceWriter
    private var sessionMaxBytes: UInt64 = 0

    init(model: MachineModel, writer: TITraceWriter) {
        self.model = model
        self.writer = writer
        isAvailable = Self.checkAvailability()
    }

    /// Whether the trace location is accessible. Checked at app startup and per session.
    static func checkAvailability() -> Bool {
        let fm = FileManager.default

        #if !os(macOS)
        let location = AppSettings.resolvedTraceLocation()
        if location == .iCloud && fm.ubiquityIdentityToken == nil {
            return false
        }
        #endif

        let traceDir = AppSettings.traceDirectory()
        do {
            try fm.createDirectory(at: traceDir, withIntermediateDirectories: true)
            return true
        } catch {
            print("[TraceWriter] checkAvailability(): failed to create/access trace directory \(traceDir.path): \(error)")
            return false
        }
    }

    /// Open the model-derived trace file (fresh) and start a session.
    /// Returns true if successful, false if unavailable.
    @discardableResult
    func open() -> Bool {
        guard !isOpen else { return true }
        let url = traceFileURL()
        guard isAvailable else {
            print("[TraceWriter] open(): trace location is not available — no file will be written")
            return false
        }
        // integer(forKey:) returns 0 when unset; any positive user value is honoured.
        let maxMB = UserDefaults.standard.integer(forKey: SettingsKey.traceMaxFileSizeMB)
        sessionMaxBytes = UInt64(maxMB > 0 ? maxMB : Self.defaultMaxFileSizeMB) * 1_000_000
        guard writer.open(atPath: url.path, maxBytes: sessionMaxBytes) else {
            print("[TraceWriter] open(): could not create trace file at \(url.path)")
            return false
        }
        currentTraceURL = url
        return true
    }

    /// Write a SESSION_END record and close the file.
    func close() {
        writer.close()
        releaseURL()
    }

    /// The session closed the file at the size limit.
    func didReachSizeLimit() {
        let fileName = currentTraceURL?.lastPathComponent ?? "trace file"
        print("WARNING: \(fileName) reached the \(sessionMaxBytes / 1_000_000) MB size limit — trace stopped. Re-enable TRACE to start a new session (existing trace file will be lost).")
        releaseURL()
    }

    private func releaseURL() {
        currentTraceURL?.stopAccessingSecurityScopedResource()
        currentTraceURL = nil
    }

    func writeCardInsert() { writer.writeCardInsert() }
    func writeCardEject() { writer.writeCardEject() }

    func traceFileURL() -> URL {
        AppSettings.traceDirectory().appendingPathComponent(TITraceWriter.baseFileName(forModel: model.rawValue))
    }
}
