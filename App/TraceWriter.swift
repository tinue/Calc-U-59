import Foundation

// ── TraceWriter ───────────────────────────────────────────────────────────────
//
// Writes TI59_TRACE.bin in the binary format documented in DebugAPI.md.
// Append-mode: multiple sessions accumulate in the same file.
// The user deletes the file manually between unrelated capture runs.
//
// Thread safety: all methods must be called from the same serial queue
// (emulQueue in EmulatorViewModel).  open()/close() are called from the
// main thread but do file I/O synchronously — acceptable since they are
// infrequent UI toggles.

final class TraceWriter {

    // ── Record type constants ─────────────────────────────────────────────────
    private enum RecType: UInt8 {
        case sessionStart = 0x01
        case traceEvent   = 0x02
        case sessionEnd   = 0x03
        case userEvent    = 0x04
    }

    private enum UserEventKind: UInt8 {
        case keyDown     = 0x01
        case keyUp       = 0x02
        case cardInsert  = 0x03
        case cardEject   = 0x04
    }

    // ── File header constants ─────────────────────────────────────────────────
    private static let magic: UInt32   = 0x54493539   // 'TI59' LE
    private static let version: UInt16 = 3            // v3: added m_libAddrReadPos field
    private static let headerSize      = 16

    // ── State ─────────────────────────────────────────────────────────────────
    private(set) var isOpen = false
    private var fileHandle: FileHandle?
    private var currentTraceURL: URL?  // Track the URL for security-scoped resource cleanup

    // Dedup state: key bytes of the last written "first-of-run" event
    private var pendingBytes: Data?            // serialised payload of the last seen event
    private var pendingKey: Data?              // dedup key bytes of the pending event
    private var suppressedCount: UInt32 = 0   // identical events seen after the first

    // Session statistics
    private var sessionEventCount: UInt32    = 0
    private var sessionSuppressedTotal: UInt32 = 0

    init() {
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /// Resolve the trace file URL, open (or create+append) the file, and write
    /// a SESSION_START record.  Prints the path to the console.
    func open() {
        guard !isOpen else { return }

        let url = Self.traceFileURL()
        let fm = FileManager.default
        let parentDir = url.deletingLastPathComponent()
        
        // Ensure the parent directory exists (needed for App Library and Custom paths).
        do {
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        } catch {
            return
        }
        
        // Check if file exists
        let fileExists = fm.fileExists(atPath: url.path)
        
        // Create file if it doesn't exist
        if !fileExists {
            // Try method 1: FileManager.createFile()
            var created = fm.createFile(atPath: url.path, contents: nil)
            
            // If that failed, try method 2: Write empty data
            if !created {
                do {
                    try Data().write(to: url)
                    created = true
                } catch {
                    // silently fail
                }
            }
            
            guard created else { return }
        }
        
        // Verify file now exists
        guard fm.fileExists(atPath: url.path) else { return }
        
        // Try to open the file for writing
        guard let fh = try? FileHandle(forWritingTo: url) else { return }
        
        let fileOffset = fh.seekToEndOfFile()

        if fileOffset == 0 {
            // New file — write the 16-byte file header.
            fh.write(Self.fileHeader())
        }

        fileHandle = fh
        isOpen = true
        currentTraceURL = url
        suppressedCount = 0
        pendingBytes = nil
        pendingKey   = nil
        sessionEventCount = 0
        sessionSuppressedTotal = 0

        // SESSION_START record
        var payload = Data(capacity: 8)
        payload.appendLE(UInt64(Date().timeIntervalSince1970))
        writeRecord(.sessionStart, payload: payload)
    }

    /// Flush any pending dedup event, write a SESSION_END record, and close the file.
    func close() {
        guard isOpen, let fh = fileHandle else { isOpen = false; return }

        flushPending()

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

    /// Write a CPU trace event with full-dedup logic.
    func write(event e: TITraceEvent, snapshot snap: TICPUSnapshot) {
        guard isOpen else { return }

        let key = makeKey(event: e, snapshot: snap)

        if key == pendingKey {
            // Identical to last seen event: suppress it.
            suppressedCount += 1
            sessionSuppressedTotal += 1
            // Update the pending bytes so the last-of-run carries the right seqno/cycleWeight.
            pendingBytes = makeEventPayload(event: e, snapshot: snap, suppressedBefore: suppressedCount)
        } else {
            // Different event: flush the pending last-of-run, then write this as first-of-run.
            flushPending()
            let payload = makeEventPayload(event: e, snapshot: snap, suppressedBefore: 0)
            writeRecord(.traceEvent, payload: payload)
            sessionEventCount += 1
            pendingKey   = key
            pendingBytes = payload     // will be re-serialised as last-of-run if suppressed later
            suppressedCount = 0
        }
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

    private func flushPending() {
        guard let bytes = pendingBytes, suppressedCount > 0 else {
            // Either nothing pending, or it was written as first-of-run with no duplicates.
            return
        }
        // Re-write with the accumulated suppressedBefore count baked in.
        writeRecord(.traceEvent, payload: bytes)
        sessionEventCount += 1
        pendingBytes = nil
        pendingKey   = nil
        suppressedCount = 0
    }

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
    }

    // ── Serialisation ─────────────────────────────────────────────────────────

    // Dedup key: everything that uniquely identifies a CPU state for our purposes.
    // seqno and cycleWeight are excluded — they always differ.
    // Uses CPUSnapshot (post-execution, TRACE_REGS_FULL) for all register values;
    // TITraceEvent light-register fields (fA, fB, KR, SR, cpuFlags) are only
    // populated when TRACE_REGS_LIGHT is set — which we do NOT enable.
    private func makeKey(event e: TITraceEvent, snapshot snap: TICPUSnapshot) -> Data {
        var d = Data(capacity: 2+2+2+2+2+2+2+2+1+80)
        d.appendLE(e.pc)
        d.appendLE(e.opcode)
        // digit is excluded: the counter cycles 0–15 on every instruction,
        // so including it would prevent dedup of IDLE loops and HOLD cycles.
        d.appendLE(snap.fA)
        d.appendLE(snap.fB)
        d.appendLE(snap.KR)
        d.appendLE(snap.SR)
        d.appendLE(snap.flags)
        d.appendLE(snap.m_libAddr)
        d.append(snap.R5)
        var a2 = snap.A; d.append(contentsOf: tupleBytes(&a2))
        var b2 = snap.B; d.append(contentsOf: tupleBytes(&b2))
        var c2 = snap.C; d.append(contentsOf: tupleBytes(&c2))
        var d2 = snap.D; d.append(contentsOf: tupleBytes(&d2))
        var e3 = snap.E; d.append(contentsOf: tupleBytes(&e3))
        return d
    }

    // Full 123-byte TRACE_EVENT payload (v3: added m_libAddrReadPos field).
    // suppressedBefore is embedded at offset 0 so the last-of-run can carry the count.
    private func makeEventPayload(event e: TITraceEvent, snapshot snap: TICPUSnapshot,
                                  suppressedBefore: UInt32) -> Data {
        var d = Data(capacity: 123)

        // Dedup counter + control fields (34 bytes)
        d.appendLE(suppressedBefore)
        d.appendLE(e.seqno)
        d.appendLE(e.pc)
        d.appendLE(e.opcode)
        d.appendLE(snap.fA)
        d.appendLE(snap.fB)
        d.appendLE(snap.KR)
        d.appendLE(snap.SR)
        d.appendLE(snap.EXT)
        d.appendLE(snap.PREG)
        d.appendLE(snap.flags)
        d.appendLE(snap.m_libAddr)
        d.append(snap.R5)
        d.append(snap.digit)
        d.append(snap.RAM_ADDR)
        d.append(snap.RAM_OP)
        d.append(snap.REG_ADDR)
        d.append(snap.m_libAddrReadPos)
        d.append(e.cycleWeight)

        // Registers A–E: one nibble per byte, index 0 = LSN (digit 0) — 80 bytes
        var a = snap.A; d.append(contentsOf: tupleBytes(&a))
        var b = snap.B; d.append(contentsOf: tupleBytes(&b))
        var c = snap.C; d.append(contentsOf: tupleBytes(&c))
        var dd2 = snap.D; d.append(contentsOf: tupleBytes(&dd2))
        var e2 = snap.E; d.append(contentsOf: tupleBytes(&e2))

        // Sout nibble-packed: low nibble = Sout[2i], high nibble = Sout[2i+1] — 8 bytes
        var soutTuple = snap.Sout
        let sout = tupleBytes(&soutTuple)   // 16 bytes, each a nibble
        for i in 0..<8 {
            let lo: UInt8 = sout[i * 2]     & 0x0F
            let hi: UInt8 = sout[i * 2 + 1] & 0x0F
            d.append(lo | (hi << 4))
        }

        assert(d.count == 123)
        return d
    }

    // ── File header ───────────────────────────────────────────────────────────

    private static func fileHeader() -> Data {
        var d = Data(capacity: headerSize)
        d.appendLE(magic)
        d.appendLE(version)
        d.appendLE(UInt16(0))       // pad
        d.appendLE(UInt64(0))       // reserved
        assert(d.count == headerSize)
        return d
    }

    // ── URL resolution ────────────────────────────────────────────────────────
    //
    // Reuses the iCloud container already resolved by CardStorage.warmUp(),
    // which is called at app start.

    private static let traceFileName = "CALCU59_TRACE.bin"

    static func traceFileURL() -> URL {
        AppSettings.traceDirectory().appendingPathComponent(traceFileName)
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
