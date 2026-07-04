import Foundation

// ── TraceWriter ───────────────────────────────────────────────────────────────
//
// Writes TI59_TRACE.bin (or CALCU58_TRACE.bin, CALCU58C_TRACE.bin) in the binary
// format documented in DebugAPI.md.
//
// Fresh-file mode: each open() call deletes the existing file and starts fresh.
// This ensures each Trace button press captures a new, independent session.
//
// Thread safety: all methods must be called from the same serial queue
// (emulQueue in EmulatorViewModel).  open()/close() are called from the
// main thread but do file I/O synchronously — acceptable since they are
// infrequent UI toggles.

final class TraceWriter {

    // ── Constants ──────────────────────────────────────────────────────────────
    private static let defaultMaxFileSizeMB = 50

    // ── Record type constants ─────────────────────────────────────────────────
    private enum RecType: UInt8 {
        case sessionStart = 0x01
        case traceEvent   = 0x02
        case sessionEnd   = 0x03
        case userEvent    = 0x04
        case traceGap     = 0x05  // frame count: UInt32 of lost frames
    }

    private enum UserEventKind: UInt8 {
        case keyDown     = 0x01
        case keyUp       = 0x02
        case cardInsert  = 0x03
        case cardEject   = 0x04
    }

    // ── File header constants ─────────────────────────────────────────────────
    private static let magic: UInt32   = 0x54493539   // 'TI59' LE
    private static let version: UInt16 = 2  // v1 (released in v1.0.0) is stable; v2+ can evolve without backwards-compat guarantees
    private static let headerSize      = 16

    // ── State ─────────────────────────────────────────────────────────────────
    private(set) var isOpen = false
    private(set) var isAvailable = true  // false if iCloud/storage is unavailable
    private var fileHandle: FileHandle?
    private var currentTraceURL: URL?  // Track the URL for security-scoped resource cleanup
    private let model: MachineModel     // Calculator model (determines trace filename)

    /// Called on the main thread when the size limit is reached mid-session.
    /// The receiver should disable tracing (e.g. set cIndicatorDebug = false).
    var onSizeLimitReached: (() -> Void)?

    // Session statistics
    private var sessionEventCount: UInt32    = 0
    private var sessionSuppressedTotal: UInt32 = 0
    private var sessionMaxBytes: UInt64       = 0  // size limit cached at open()
    private var sessionBytesWritten: UInt64   = 0  // running total, avoids offsetInFile syscall

    init(model: MachineModel) {
        self.model = model
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
            isAvailable = false
        }
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /// Resolve the trace file URL, delete any existing file, create a fresh one,
    /// and write a SESSION_START record.  Returns true if successful, false if unavailable.
    /// Each call to open() starts a new, independent session.
    @discardableResult
    func open() -> Bool {
        guard !isOpen else { return true }
        guard isAvailable else { return false }

        let url = self.traceFileURL()

        // Cache the size limit for the upcoming session.
        // integer(forKey:) returns 0 when unset; any positive user value is
        // honoured (including values below the default).
        let maxMB = UserDefaults.standard.integer(forKey: SettingsKey.traceMaxFileSizeMB)
        sessionMaxBytes = UInt64(maxMB > 0 ? maxMB : Self.defaultMaxFileSizeMB) * 1_000_000

        return openFile(at: url)
    }

    /// Resolve `fileName` under the configured trace directory, delete any existing
    /// file of that name, create a fresh one, and write a SESSION_START record.
    /// Used for scripted (KEYSTROKES "Trace:") captures, which target a caller-chosen
    /// filename instead of the fixed model-derived one used by `open()`.
    @discardableResult
    func open(fileName: String) -> Bool {
        guard !isOpen else { return true }
        guard isAvailable else { return false }

        let maxMB = UserDefaults.standard.integer(forKey: SettingsKey.traceMaxFileSizeMB)
        sessionMaxBytes = UInt64(maxMB > 0 ? maxMB : Self.defaultMaxFileSizeMB) * 1_000_000

        let url = AppSettings.traceDirectory().appendingPathComponent(fileName)
        return openFile(at: url)
    }

    /// Open file at the given URL. Creates a new file (deletes existing). Returns true on success.
    private func openFile(at url: URL) -> Bool {
        let fm = FileManager.default

        // Delete existing file to start fresh (no appending to previous session)
        if fm.fileExists(atPath: url.path) {
            do {
                try fm.removeItem(at: url)
            } catch {
                return false
            }
        }

        // Create new file — try both methods
        var created = fm.createFile(atPath: url.path, contents: nil)
        if !created {
            do {
                try Data().write(to: url)
                created = true
            } catch {
                return false
            }
        }
        if !created {
            return false
        }

        // Open for writing
        guard let fh = try? FileHandle(forWritingTo: url) else {
            return false
        }

        let fileOffset = fh.seekToEndOfFile()
        if fileOffset == 0 {
            fh.write(fileHeader())
        }

        fileHandle = fh
        isOpen = true
        currentTraceURL = url
        sessionEventCount = 0
        sessionSuppressedTotal = 0
        sessionBytesWritten = UInt64(fh.offsetInFile)  // account for any pre-existing file header

        // Write SESSION_START record with timestamp and model
        var payload = Data(capacity: 9)
        payload.appendLE(UInt64(Date().timeIntervalSince1970))
        let modelByte: UInt8
        switch model {
        case .ti59:  modelByte = 0
        case .ti58:  modelByte = 1
        case .ti58c: modelByte = 2
        }
        payload.append(modelByte)
        writeRecord(.sessionStart, payload: payload)

        return true
    }

    /// Flush any pending dedup event, write a SESSION_END record, and close the file.
    func close() {
        guard isOpen, let fh = fileHandle else { isOpen = false; return }

        // SESSION_END record
        var payload = Data(capacity: 8)
        payload.appendLE(sessionEventCount)
        payload.appendLE(sessionSuppressedTotal)
        writeRecord(.sessionEnd, payload: payload)

        fh.closeFile()
        fileHandle = nil

        // Stop accessing security-scoped resource if it was used
        if let traceURL = currentTraceURL {
            traceURL.stopAccessingSecurityScopedResource()
        }
        currentTraceURL = nil

        isOpen = false
    }

    /// Write a unified CPU frame (combines TraceEvent and CPU state).
    func write(frame: TICpuFrame) {
        guard isOpen else { return }

        // Write every frame immediately with no deduplication.
        // This preserves the exact execution trace for debugging.
        let payload = makeFramePayload(frame: frame)
        writeRecord(.traceEvent, payload: payload)
        sessionEventCount += 1

        // Auto-stop when the file reaches the size limit to prevent iCloud quota overflow.
        if sessionBytesWritten >= sessionMaxBytes {
            let fileName = currentTraceURL?.lastPathComponent ?? "trace file"
            print("WARNING: \(fileName) reached the \(sessionMaxBytes / 1_000_000) MB size limit — trace stopped. Re-enable TRACE to start a new session (existing trace file will be lost).")
            close()
            onSizeLimitReached?()
        }
    }

    /// Write a gap record indicating lost frames during ring overflow.
    func writeLostGap(count: UInt32) {
        guard isOpen else { return }

        var payload = Data(capacity: 4)
        payload.appendLE(count)
        writeRecord(.traceGap, payload: payload)
    }

    func writeKeyDown(row: UInt8, col: UInt8) {
        writeUserEvent(kind: .keyDown, p1: row, p2: col)
    }

    func writeKeyUp(row: UInt8, col: UInt8) {
        writeUserEvent(kind: .keyUp, p1: row, p2: col)
    }

    func writeCardInsert() {
        writeUserEvent(kind: .cardInsert, p1: 0, p2: 0)
    }

    func writeCardEject() {
        writeUserEvent(kind: .cardEject, p1: 0, p2: 0)
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private func writeUserEvent(kind: UserEventKind, p1: UInt8, p2: UInt8) {
        guard isOpen else { return }
        var payload = Data(capacity: 4)
        payload.append(kind.rawValue)
        payload.append(p1)
        payload.append(p2)
        payload.append(0)     // param3 reserved
        writeRecord(.userEvent, payload: payload)
    }

    private func writeRecord(_ type: RecType, payload: Data) {
        guard let fh = fileHandle else { return }
        var header = Data(capacity: 3)
        header.append(type.rawValue)
        header.appendLE(UInt16(payload.count))
        fh.write(header)
        fh.write(payload)
        sessionBytesWritten += UInt64(3 + payload.count)
    }

    // ── Serialisation ─────────────────────────────────────────────────────────

    // Full 125-byte TRACE_EVENT payload from a unified CpuFrame.
    private func makeFramePayload(frame: TICpuFrame) -> Data {
        var d = Data(capacity: 125)

        // Control fields (suppressed count is always 0; kept for format compatibility) — 38 bytes
        d.appendLE(UInt32(0))
        d.appendLE(frame.seqno)
        d.appendLE(frame.pc)
        d.appendLE(frame.opcode)
        d.appendLE(frame.fA)
        d.appendLE(frame.fB)
        d.appendLE(frame.KR)
        d.appendLE(frame.SR)
        d.appendLE(frame.EXT)
        d.appendLE(frame.PREG)
        d.appendLE(frame.flags)
        d.appendLE(frame.m_libAddr)
        d.append(frame.R5)
        d.append(frame.digit)
        d.append(frame.RAM_ADDR)
        d.append(frame.RAM_OP)
        d.append(frame.REG_ADDR)
        d.append(frame.m_libAddrReadPos)
        d.append(frame.cycleWeight)
        d.append(frame.displayOn)
        d.append(frame.maxDigitDecay)

        // Registers A–E: one nibble per byte, index 0 = LSN (digit 0) — 80 bytes
        var a = frame.A; d.append(contentsOf: tupleBytes(&a))
        var b = frame.B; d.append(contentsOf: tupleBytes(&b))
        var c = frame.C; d.append(contentsOf: tupleBytes(&c))
        var dd = frame.D; d.append(contentsOf: tupleBytes(&dd))
        var e = frame.E; d.append(contentsOf: tupleBytes(&e))

        // Sout nibble-packed: low nibble = Sout[2i], high nibble = Sout[2i+1] — 8 bytes
        var soutTuple = frame.Sout
        let sout = tupleBytes(&soutTuple)   // 16 bytes, each a nibble
        for i in 0..<8 {
            let lo: UInt8 = sout[i * 2]     & 0x0F
            let hi: UInt8 = sout[i * 2 + 1] & 0x0F
            d.append(lo | (hi << 4))
        }

        assert(d.count == 125)
        return d
    }

    // ── File header ───────────────────────────────────────────────────────────

    private func fileHeader() -> Data {
        var d = Data(capacity: TraceWriter.headerSize)
        d.appendLE(TraceWriter.magic)
        d.appendLE(TraceWriter.version)

        // Model indicator (v2): 0=TI-59, 1=TI-58, 2=TI-58C
        let modelByte: UInt16
        switch model {
        case .ti59:  modelByte = 0
        case .ti58:  modelByte = 1
        case .ti58c: modelByte = 2
        }
        d.appendLE(modelByte)

        d.appendLE(UInt64(0))       // reserved for future use
        assert(d.count == TraceWriter.headerSize)
        return d
    }

    // ── URL resolution ────────────────────────────────────────────────────────
    //
    // Reuses the iCloud container already resolved by CardStorage.warmUp(),
    // which is called at app start.

    /// Generate the model-specific base filename.
    /// Examples: CALCU59_TRACE.bin, CALCU58_TRACE.bin, CALCU58C_TRACE.bin
    private func traceBaseFileName() -> String {
        let modelPrefix: String
        switch model {
        case .ti59:  modelPrefix = "CALCU59"
        case .ti58:  modelPrefix = "CALCU58"
        case .ti58c: modelPrefix = "CALCU58C"
        }
        return "\(modelPrefix)_TRACE.bin"
    }

    func traceFileURL() -> URL {
        AppSettings.traceDirectory().appendingPathComponent(traceBaseFileName())
    }
}

// ── Data LE helpers ───────────────────────────────────────────────────────────
// Explicit bit-shifting avoids withUnsafeBytes ambiguity inside a Data extension.

private extension Data {
    mutating func appendLE(_ v: UInt16) {
        append(UInt8(v & 0xFF))
        append(UInt8(v >> 8))
    }
    mutating func appendLE(_ v: UInt32) {
        append(UInt8(v        & 0xFF))
        append(UInt8(v >>  8  & 0xFF))
        append(UInt8(v >> 16  & 0xFF))
        append(UInt8(v >> 24  & 0xFF))
    }
    mutating func appendLE(_ v: UInt64) {
        appendLE(UInt32(v        & 0xFFFF_FFFF))
        appendLE(UInt32(v >> 32  & 0xFFFF_FFFF))
    }
}

// ── Tuple → [UInt8] helper ───────────────────────────────────────────────────
// C fixed-size arrays arrive in Swift as tuples; read them as raw bytes.
// Called at statement scope so there is no ambiguity with Data.withUnsafeBytes.

private func tupleBytes<T>(_ t: inout T) -> [UInt8] {
    Swift.withUnsafeBytes(of: &t) { Array($0) }
}
