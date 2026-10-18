import Foundation

// ── TraceWriter ───────────────────────────────────────────────────────────────
//
// Swift side of the binary trace file (TI59_TRACE.bin and friends, format in
// DebugAPI.md): decides WHERE the file goes — the configured trace directory
// (iCloud, local or a custom folder; see AppSettings.traceDirectory()) — and
// whether that location is available. The file itself is written by
// Shared/TraceWriter.cpp via Bridge/TITraceWriter (thread-safe).
//
// Fresh-file mode: each open() call deletes the existing file and starts fresh.
// This ensures each Trace button press captures a new, independent session.

final class TraceWriter {

    private static let defaultMaxFileSizeMB = 50

    var isOpen: Bool { writer.isOpen }
    private(set) var isAvailable = true  // false if iCloud/storage is unavailable
    private var currentTraceURL: URL?  // Track the URL for security-scoped resource cleanup
    private let model: MachineModel     // Calculator model (determines trace filename)
    private let writer: TITraceWriter
    private var sessionMaxBytes: UInt64 = 0

    /// Called on the main thread when the size limit is reached mid-session.
    /// The receiver should disable tracing (e.g. set cIndicatorDebug = false).
    var onSizeLimitReached: (() -> Void)?

    init(model: MachineModel) {
        self.model = model
        self.writer = TITraceWriter(model: model.rawValue)
    }

    /// Check if the trace location is accessible. Call at app startup to set isAvailable.
    func checkAvailability() {
        let fm = FileManager.default

        #if !os(macOS)
        let location = AppSettings.resolvedTraceLocation()
        if location == .iCloud && fm.ubiquityIdentityToken == nil {
            isAvailable = false
            return
        }
        #endif

        let traceDir = AppSettings.traceDirectory()
        do {
            try fm.createDirectory(at: traceDir, withIntermediateDirectories: true)
            isAvailable = true
        } catch {
            print("[TraceWriter] checkAvailability(): failed to create/access trace directory \(traceDir.path): \(error)")
            isAvailable = false
        }
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /// Open the model-derived trace file (fresh) and start a session.
    /// Returns true if successful, false if unavailable.
    @discardableResult
    func open() -> Bool {
        open(at: traceFileURL(), label: "open()")
    }

    /// Resolve `fileName` under the configured trace directory and start a fresh
    /// session there. Used for scripted (KEYSTROKES "Trace:") captures, which
    /// target a caller-chosen filename instead of the model-derived one.
    @discardableResult
    func open(fileName: String) -> Bool {
        open(at: AppSettings.traceDirectory().appendingPathComponent(fileName), label: "open(fileName: \(fileName))")
    }

    private func open(at url: URL, label: String) -> Bool {
        guard !isOpen else { return true }
        guard isAvailable else {
            print("[TraceWriter] \(label): trace location is not available (checkAvailability() previously failed) — no file will be written")
            return false
        }
        // integer(forKey:) returns 0 when unset; any positive user value is honoured.
        let maxMB = UserDefaults.standard.integer(forKey: SettingsKey.traceMaxFileSizeMB)
        sessionMaxBytes = UInt64(maxMB > 0 ? maxMB : Self.defaultMaxFileSizeMB) * 1_000_000
        guard writer.open(atPath: url.path, maxBytes: sessionMaxBytes) else {
            print("[TraceWriter] \(label): could not create trace file at \(url.path)")
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

    private func releaseURL() {
        currentTraceURL?.stopAccessingSecurityScopedResource()
        currentTraceURL = nil
    }

    /// Write one CPU frame. Stops the session at the size limit.
    func write(frame: TICpuFrame) {
        guard isOpen else { return }
        if !writer.write(frame) {
            let fileName = currentTraceURL?.lastPathComponent ?? "trace file"
            print("WARNING: \(fileName) reached the \(sessionMaxBytes / 1_000_000) MB size limit — trace stopped. Re-enable TRACE to start a new session (existing trace file will be lost).")
            releaseURL()
            onSizeLimitReached?()
        }
    }

    /// Write a gap record indicating lost frames during ring overflow.
    func writeLostGap(count: UInt32) { writer.writeLostGap(count) }
    func writeKeyDown(row: UInt8, col: UInt8) { writer.writeKeyDownRow(row, col: col) }
    func writeKeyUp(row: UInt8, col: UInt8) { writer.writeKeyUpRow(row, col: col) }
    func writeCardInsert() { writer.writeCardInsert() }
    func writeCardEject() { writer.writeCardEject() }

    func traceFileURL() -> URL {
        AppSettings.traceDirectory().appendingPathComponent(TITraceWriter.baseFileName(forModel: model.rawValue))
    }
}
