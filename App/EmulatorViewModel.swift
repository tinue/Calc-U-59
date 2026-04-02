import Foundation
import SwiftUI

@Observable
class EmulatorViewModel {
    var displayDigits: [UInt8]  = Array(repeating: 0, count: 12)
    var displayCtrl:   [UInt8]  = Array(repeating: 0, count: 12)
    var dpPos:          UInt8   = 0
    var calcIndicator:  Bool    = false
    var calcIndicatorOpacity: Double = 0.0
    var model: MachineModel     = .ti59
    var errorMessage: String?

    // ── Printer state ────────────────────────────────────────────────────────
    var printerLines: [String] = []
    var printerCodeLines: [Data] = []  // parallel to printerLines; 20 raw codes per line
    var printerClearID: Int = 0   // incremented on cut to reset Text identity and drop selection
    var printerTrace: Bool = false

    // ── Debug panel state ────────────────────────────────────────────────────
    var debugEnabled: Bool = false
    var debugLines: [String] = []
    var debugClearID: Int = 0   // incremented on clear to reset Text identity and drop selection

    // ── Trace / debug state ──────────────────────────────────────────────────
    var traceEnabled: Bool = false
    var traceEvents: [TITraceEvent] = []          // sliding window, last 512
    var breakpoints: Set<UInt16> = []
    var isPausedOnBreakpoint: Bool = false
    var breakpointPC: UInt16? = nil

    // ── Card reader state ────────────────────────────────────────────────────
    enum CardState: Equatable {
        case noCard      // Nothing selected
        case swiping     // Card is passing through; I/O in progress
    }
    enum CardMode: Int { case none = 0, read = 1, write = 2 }
    var cardState: CardState = .noCard
    var cardMode: CardMode { CardMode(rawValue: Int(machine?.cardMode ?? 0)) ?? .none }
    var cardPickerMode: CardPickerView.Mode? = nil
    /// `true` when a card file exists on disk.
    var hasCardFile: Bool = false
    /// Display name of the last card file loaded.
    var cardFileName: String = "card.U59"

    private static let cardFileHeader = Data("Calc-U-59-CRD".utf8)

    private var machine: TI59MachineWrapper?
    private let emulQueue = DispatchQueue(label: "calc-u-59.emulation", qos: .userInteractive)
    private var displayTimer: Timer?
    private var isRunning = false
    private static let constantMemoryFileName = "ti58c.mem"
    private static var constantMemoryURL: URL {
        CardStorage.directoryURL.appendingPathComponent(constantMemoryFileName)
    }

    init() {
        Task { await self.start(model: .ti59) }
    }

    func start(model: MachineModel) async {
        persistConstantMemory()  // save TI-58C RAM before switching away
        stop()
        await drainEmulQueue()   // ensure old loop has exited before starting the new one
        self.model = model
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                CardStorage.warmUp()
                continuation.resume()
            }
        }
        do {
            let words = try ROMLoader.load(model: model)
            let wrapper = TI59MachineWrapper(model: model.rawValue)
            words.withUnsafeBufferPointer { buf in
                let data = Data(buffer: buf)
                wrapper.loadROM(data)
            }

            if let libData = ROMLoader.loadLibrary() {
                wrapper.loadLibrary(libData)
            }

            if model.hasConstantMemory, let saved = loadConstantMemory() {
                // Restore RAM before the emulation loop starts so the ROM's startup
                // routine sees the warm-start flag and skips its RAM clear —
                // matching the real TI-58C where CMOS RAM was always live.
                wrapper.deserialiseRAM(saved)
            }

            self.machine = wrapper
            hasCardFile = CardStorage.hasCard
            startEmulationLoop()
            startDisplayRefresh()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func startEmulationLoop() {
        isRunning = true
        guard let m = machine else { return }
        emulQueue.async { [weak self, m] in
            guard let self else { return }
            var cyclesDone: Int32 = 0
            // Hardware clock: 455 kHz crystal ÷ 2 (two-phase) ÷ 16 (digit-serial)
            // = 14,218.75 instructions/sec in active mode.  Idle mode runs at ÷4
            // (step() returns 4 instead of 1), so the loop naturally slows down
            // when the calculator is waiting for a keypress.
            let targetHz: Double = 14218.75
            let batchMs: Double = 0.020  // 20 ms batches keep latency low
            let targetBatchCycles = Int32(targetHz * batchMs) // ≈ 284

            while self.isRunning {
                let start = DispatchTime.now()
                while cyclesDone < targetBatchCycles {
                    let result = m.step()
                    if result & 0x8000_0000 != 0 {
                        // Breakpoint hit — pause the emulation loop.
                        self.isRunning = false
                        let hitPC = m.currentPC
                        DispatchQueue.main.async { self.onBreakpointHit(pc: hitPC) }
                        return
                    }
                    cyclesDone += Int32(result & 0x7FFF_FFFF)
                }
                // Subtract rather than reset to zero: carry the overshoot into
                // the next batch so long-term average speed stays exact.
                cyclesDone -= targetBatchCycles

                let end = DispatchTime.now()
                let elapsed = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
                let remaining = batchMs - elapsed
                if remaining > 0 {
                    Thread.sleep(forTimeInterval: remaining)
                }
            }
        }
    }

    private func startDisplayRefresh() {
        // Always schedule on the main run loop so the timer fires reliably
        // regardless of which thread calls this. Invalidate any existing timer
        // first to prevent duplicate ticks if start() is called more than once.
        displayTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func tick() {
        guard let machine else { return }

        // Detect auto-eject: C++ ejects the card at CRD_OFF (matching physical hardware
        // where the card exits the reader after each pass).  Save any written data.
        if cardState == .swiping && !machine.isCardPresent {
            ejectCard()
        }

        if let lines = machine.drainPrinterLines() as? [String], !lines.isEmpty {
            printerLines.append(contentsOf: lines)
        }
        if let codes = machine.drainPrinterCodeLines() as? [Data], !codes.isEmpty {
            printerCodeLines.append(contentsOf: codes)
        }

        // Drain trace events (60 Hz, same cadence as display refresh).
        if traceEnabled, let evs = machine.drainTraceEvents(max: 512) as? [NSValue] {
            let newEvents = evs.map { v -> TITraceEvent in
                var e = TITraceEvent()
                v.getValue(&e)
                return e
            }
            traceEvents.append(contentsOf: newEvents)
            if traceEvents.count > 512 { traceEvents.removeFirst(traceEvents.count - 512) }
        }

        let snap = machine.getDisplay()
        var d = [UInt8](repeating: 0, count: 12)
        var c = [UInt8](repeating: 0, count: 12)
        withUnsafeBytes(of: snap.digits) { b in for i in 0..<12 { d[i] = b[i] } }
        withUnsafeBytes(of: snap.ctrl)   { b in for i in 0..<12 { c[i] = b[i] } }
        // Guard each assignment: @Observable only notifies SwiftUI when a property
        // is actually written, but the write itself counts as a change even if the
        // value is identical.  The guards prevent 60 Hz spurious re-renders when
        // the display is static (e.g. calculator idle showing a number).
        if displayDigits    != d               { displayDigits    = d }
        if displayCtrl      != c               { displayCtrl      = c }
        if dpPos            != snap.dpPos      { dpPos            = snap.dpPos }
        if calcIndicator    != snap.calcIndicator { calcIndicator = snap.calcIndicator }
        // Simulate the TI-59 "C" LED appearance:
        //   • latching to peak (0.65) on any pulse — rise ≥ cap ensures 1-pulse and
        //     2-pulse keypresses both land at the same brightness (no dimmer single-pulse keys)
        //   • capping at 0.65 — brighter than before; matches perceived LED intensity
        //   • fading at 0.12/frame — ~90 ms afterglow from peak to zero; fast enough
        //     that off-frames during computation drop noticeably (visible flicker)
        // fA-based flicker (fA varies during computation) produces natural opacity
        // oscillation during longer programs; the fast rise keeps each pulse at full peak.
        if snap.calcIndicator {
            calcIndicatorOpacity = min(0.65, calcIndicatorOpacity + 0.65)
        } else if calcIndicatorOpacity > 0 {
            calcIndicatorOpacity = max(0.0, calcIndicatorOpacity - 0.12)
        }
    }

    func stop() {
        isRunning = false
        displayTimer?.invalidate()
        displayTimer = nil
    }

    /// Wait for any in-flight emulation batch to finish.
    /// Must be called after stop() before starting a new loop.
    private func drainEmulQueue() async {
        await withCheckedContinuation { continuation in
            emulQueue.async { continuation.resume() }
        }
    }

    // MARK: - Key input

    func pressKey(row: Int, col: Int) {
        machine?.pressMatrixKey(UInt8((row + 1) * 10 + (col + 1)))
    }

    func releaseKey(row: Int, col: Int) {
        machine?.releaseMatrixKey(UInt8((row + 1) * 10 + (col + 1)))
    }

    // MARK: - Printer

    func pressPrinterPrint(_ pressed: Bool) { machine?.pressPrinterPrint(pressed) }
    func pressPrinterAdv(_ pressed: Bool)   { machine?.pressPrinterAdv(pressed) }
    func togglePrinterTrace() {
        printerTrace.toggle()
        machine?.setPrinterTrace(printerTrace)
    }
    func cutPaper() { printerLines = []; printerCodeLines = []; printerClearID &+= 1 }

    // MARK: - Reset

    func resetMachine() {
        cardState = .noCard
        machine?.reset()
        debugAppend(["Calculator Reset"])
    }

    /// Hard reset (TI-58C only): delete the persistent memory file, then reset.
    /// The calculator starts fresh with no constant memory on the next load.
    func hardResetMachine() {
        guard model.hasConstantMemory else { return }
        let url = Self.constantMemoryURL
        let coordinator = NSFileCoordinator()
        var err: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &err) { dst in
            try? FileManager.default.removeItem(at: dst)
        }
        // Zero all RAM before reset so the ROM's startup sees no valid-memory flag
        // and performs a full cold-start clear instead of preserving contents.
        machine?.deserialiseRAM(Data(repeating: 0, count: 120 * 16))
        cardState = .noCard
        machine?.reset()
        debugAppend(["Hard Reset — constant memory cleared"])
    }

    // MARK: - Magnetic card reader

    func ejectIfSwiping() {
        if cardState == .swiping { ejectCard() }
    }

    private func beginSwipe(data: Data) {
        guard let machine, cardState == .noCard else { return }
        cardState = .swiping
        machine.insertCard(data)
    }

    private var pendingSaveURL: URL? = nil

    func insertBlankCard(savingTo url: URL) {
        pendingSaveURL = url
        cardFileName = url.lastPathComponent
        beginSwipe(data: Data())
    }

    func insertCard(from url: URL) {
        // startAccessingSecurityScopedResource is a no-op (returns false) for URLs
        // constructed from our own iCloud container; call it only as a courtesy for
        // any URL that may actually be security-scoped (e.g. future external sources).
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let raw = try? Data(contentsOf: url) else {
            errorMessage = "Could not read card file."
            return
        }
        let data: Data
        let hdr = Self.cardFileHeader
        if raw.prefix(hdr.count) == hdr {
            // New format: strip header, then expect exactly 246 bytes of card data.
            let payload = raw.dropFirst(hdr.count)
            guard payload.count == 246 else {
                errorMessage = "Card file \"\(url.lastPathComponent)\" has wrong size (\(payload.count) bytes after header; expected 246)."
                return
            }
            data = Data(payload)
        } else {
            // Legacy format: accept 246-byte (single bank) or 984-byte (four banks).
            guard raw.count == 246 || raw.count == 984 else {
                errorMessage = "Card file \"\(url.lastPathComponent)\" has unrecognised size (\(raw.count) bytes)."
                return
            }
            data = raw
        }
        cardFileName = url.lastPathComponent
        pendingSaveURL = url          // write-back if machine writes during this swipe
        beginSwipe(data: data)
    }

    func ejectCard() {
        guard let machine, cardState == .swiping else { cardState = .noCard; return }
        let written = machine.cardEject() as Data
        cardState = .noCard
        guard !written.isEmpty else { return }
        if let url = pendingSaveURL {
            saveCard(written, to: url)
        }
    }

    func saveCard(_ data: Data, to url: URL) {
        let fileData = Self.cardFileHeader + data
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { writingURL in
            do {
                try fileData.write(to: writingURL, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let err = coordinatorError ?? writeError {
            errorMessage = "Card save failed: \(err.localizedDescription)"
        } else {
            cardFileName = url.lastPathComponent
            hasCardFile = true
        }
    }

    // MARK: - TI-58C constant memory

    func persistConstantMemory() {
        guard model.hasConstantMemory, let data = machine?.serialiseRAM() else { return }
        let url = Self.constantMemoryURL
        let coordinator = NSFileCoordinator()
        var err: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &err) { dst in
            try? data.write(to: dst, options: .atomic)
        }
    }

    private func loadConstantMemory() -> Data? {
        let url = Self.constantMemoryURL
        var result: Data?
        let coordinator = NSFileCoordinator()
        var err: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &err) { src in
            result = try? Data(contentsOf: src)
        }
        return result
    }

    // MARK: - Trace / debug

    /// Enable or disable instruction tracing.  fullRegs adds the full A–E/SCOM snapshot.
    func setTraceEnabled(_ enabled: Bool, fullRegs: Bool = false) {
        traceEnabled = enabled
        if enabled {
            var flags: TITraceFlags = [.pc, .regsLight]
            if fullRegs { flags.insert(.regsFull) }
            if !breakpoints.isEmpty { flags.insert(.breakpoints) }
            machine?.traceFlags = flags
        } else {
            // Keep breakpoints active even when the trace view is off, if any are set.
            machine?.traceFlags = breakpoints.isEmpty ? [] : .breakpoints
        }
        if !enabled { traceEvents = [] }
    }

    func addBreakpoint(_ pc: UInt16) {
        breakpoints.insert(pc)
        machine?.addBreakpoint(pc)
        // Ensure TRACE_BREAKPOINTS is armed.
        if let m = machine {
            var f = m.traceFlags
            f.insert(.breakpoints)
            m.traceFlags = f
        }
    }

    func removeBreakpoint(_ pc: UInt16) {
        breakpoints.remove(pc)
        machine?.removeBreakpoint(pc)
        if breakpoints.isEmpty, let m = machine {
            var f = m.traceFlags
            f.remove(.breakpoints)
            m.traceFlags = f
        }
    }

    func resumeFromBreakpoint() {
        guard isPausedOnBreakpoint else { return }
        isPausedOnBreakpoint = false
        breakpointPC = nil
        startEmulationLoop()
    }

    func singleStep() {
        guard isPausedOnBreakpoint else { return }
        guard let m = machine else { return }
        emulQueue.async { [weak self, m] in
            guard let self else { return }
            let result = m.step()
            if result & 0x8000_0000 != 0 {
                let hitPC = m.currentPC
                DispatchQueue.main.async { self.onBreakpointHit(pc: hitPC) }
            }
        }
    }

    private func onBreakpointHit(pc: UInt16) {
        isPausedOnBreakpoint = true
        breakpointPC = pc
    }

    // MARK: - Calculator-level snapshot

    /// A decoded view of the calculator's current state.
    struct CalcSnapshot {
        /// Data registers R00–Rnn decoded as Double, where nn is determined by the
        /// current partition (e.g. R00–R59 for the default 479:59 split).
        /// Index 0 = R00, index (count-1) = last available register.
        var registers: [Double]
        /// Program step keycodes (one byte per step, 0–99).  Length = partition step count.
        var programSteps: [UInt8]
        /// Content of the printer character accumulator (not yet committed to a line).
        var printerBuffer: String
        /// Current CPU register state.
        var cpu: TICPUSnapshot
    }

    /// Read the full calculator state without disturbing execution.
    /// Returns nil if the machine is not yet started.
    func getCalcSnapshot() -> CalcSnapshot? {
        guard let m = machine else { return nil }
        // Number of accessible data registers depends on the current partition:
        // programRAMregs occupy RAM[0..(n-1)]; data regs fill RAM[n..119] top-down.
        let numRegs = max(0, 120 - Int(m.partitionProgramRegs))
        var regs = [Double](repeating: 0, count: numRegs)
        for i in 0..<numRegs { regs[i] = m.dataRegister(i) }
        let steps = Array(m.allProgramSteps() as Data)
        let cpu = m.snapshotCPU()
        return CalcSnapshot(registers: regs, programSteps: steps,
                            printerBuffer: m.printerBufferContent, cpu: cpu)
    }

    func toggleDebug() {
        debugEnabled.toggle()
    }

    func clearDebug() {
        debugLines = []
        debugClearID &+= 1
    }

    private func debugAppend(_ lines: [String]) {
        guard debugEnabled else { return }
        debugLines.append(contentsOf: lines)
    }

    /// Dump non-zero data variables within the current partition.
    /// Shows register numbers as R00–Rnn (not raw RAM indices).
    func debugDumpVars() {
        guard let m = machine else { return }
        let programRegs = Int(m.partitionProgramRegs)
        let maxRegNum = 119 - programRegs   // last addressable data register
        guard maxRegNum >= 0 else {
            debugLines.append("── Vars: no data registers in current partition ──")
            return
        }
        var lines: [String] = [String(format: "── Vars R00–R%02d ──", maxRegNum)]
        for regNum in 0...maxRegNum {
            let raw = m.rawRegister(119 - regNum) as Data
            if raw.contains(where: { $0 != 0 }) {
                let v = TI59MachineWrapper.decodeBCD(raw)
                lines.append(String(format: "R%02d = %.10g", regNum, v))
            }
        }
        debugLines.append(contentsOf: lines)
    }

    /// Dump all 16 SCOM rows in compact hex nibble format.
    func debugDumpSCOM() {
        guard let m = machine else { return }
        var cpu = m.snapshotCPU()
        var lines: [String] = ["── SCOM ──"]
        withUnsafeBytes(of: &cpu.SCOM) { bytes in
            for s in 0..<16 {
                let nibbles = (0..<16).map { String(bytes[s * 16 + $0], radix: 16) }.joined()
                lines.append(String(format: "S%02d %@", s, nibbles))
            }
        }
        debugLines.append(contentsOf: lines)
    }

    /// Dump program RAM registers as raw nibble pairs in storage order.
    /// Each register = 8 steps × 2 nibbles (units nibble first, then tens nibble).
    /// Format: `R00: 67 11 24 00 00 00 00 00`
    func debugDumpProg() {
        guard let m = machine else { return }
        let progRegs = Int(m.partitionProgramRegs)
        var lines: [String] = [String(format: "── Prog R00–R%02d (raw nibbles) ──", progRegs - 1)]
        for reg in 0..<progRegs {
            let n = Array(m.rawRegister(reg) as Data)
            let pairs = stride(from: 0, to: 16, by: 2)
                .map { String(format: "%X%X", n[$0], n[$0 + 1]) }
                .joined(separator: " ")
            lines.append(String(format: "R%02d: %@", reg, pairs))
        }
        debugLines.append(contentsOf: lines)
    }

    /// Read a raw 16-nibble RAM register (reg 0–119).
    func rawRegister(_ reg: Int) -> [UInt8]? {
        guard let m = machine else { return nil }
        return Array(m.rawRegister(reg) as Data)
    }

    /// Write a raw 16-nibble RAM register (reg 0–119).
    func setRawRegister(_ reg: Int, nibbles: [UInt8]) {
        guard nibbles.count == 16 else { return }
        machine?.setRawRegister(reg, nibbles: Data(nibbles))
    }

    // MARK: - State file loading

    func loadStateFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            errorMessage = "Cannot read file."
            return
        }
        var parsed = parseStateFile(text)
        if !parsed.errors.isEmpty { errorMessage = parsed.errors.joined(separator: "\n") }

        // TI-58/58C: 60 RAM registers → max 480 steps (last step 479).
        let isTI58 = (model == .ti58 || model == .ti58c)
        if isTI58 {
            if parsed.partitionWasExplicit && parsed.partitionMaxStep > 479 {
                errorMessage = "State file partition (\(parsed.partitionMaxStep)) exceeds TI-58 maximum (479) — load aborted."
                return
            }
            // Apply TI-58 default partition when the file has none.
            if !parsed.partitionWasExplicit {
                parsed.partitionMaxStep = 239   // 30 program regs, 30 data regs (R00–R29)
            }
        }

        isRunning = false
        // Synchronous dispatch ensures the emulation loop has fully exited
        // before we touch RAM or SCOM.  Without this, a step() in-flight on
        // emulQueue could write stale values after our state-file writes.
        emulQueue.sync {}

        guard let m = machine else { return }
        m.reset()

        // Run the ROM's power-on startup routine until it reaches idle mode.
        // 300,000 instructions is a conservative upper bound; the actual startup
        // (master-clear, display init) completes in well under 100k steps.
        // Skipping this would leave SCOM in an uninitialised state that confuses
        // the AOS stack and display driver when we write program/data below.
        emulQueue.sync { m.stepN(300_000) }

        // Set partition directly in SCOM (SCOM[9][0] and SCOM[13][8..9]).
        // For TI-58, programRegs is capped at 60; the rounding above ensures this.
        let programRegs = (parsed.partitionMaxStep + 1) / 8
        m.partitionProgramRegs = programRegs

        // Expand sparse steps into a full zero-padded array so unlisted steps are 00.
        let totalSteps = parsed.partitionMaxStep + 1
        var programArray = [UInt8](repeating: 0, count: totalSteps)
        for (addr, keycode) in parsed.programSteps where addr < totalSteps {
            programArray[addr] = keycode
        }
        m.writeProgramSteps(Data(programArray))
        for (regNum, nibbles) in parsed.registers {
            m.writeDataRegister(regNum, nibbles: Data(nibbles))
        }

        startEmulationLoop()

        if !parsed.keystrokes.isEmpty {
            Task { await playKeystrokes(parsed.keystrokes) }
        }
    }

    // MARK: - Keystroke playback

    /// Play back a KEYSTROKES sequence asynchronously after a preset loads.
    /// Each .key event presses and releases one key with a 0.5 s total gap.
    /// Each .wait event inserts an explicit pause between keystroke lines.
    private func playKeystrokes(_ events: [KeystrokeEvent]) async {
        for event in events {
            switch event {
            case .key(let matrixCode):
                machine?.pressMatrixKey(matrixCode)
                try? await Task.sleep(nanoseconds: 450_000_000)  // hold 450 ms
                machine?.releaseMatrixKey(matrixCode)
                try? await Task.sleep(nanoseconds: 50_000_000)   // 50 ms → 500 ms total
            case .wait(let t):
                try? await Task.sleep(nanoseconds: UInt64(t * 1_000_000_000))
            }
        }
    }
}
