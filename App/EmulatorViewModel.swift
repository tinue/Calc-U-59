import Foundation
import SwiftUI

enum FreezeReason {
    case manual
    case breakpointPC(Int)     // future: breakpoint on program step
    case keycode(UInt8)        // future: freeze when specific keycode executes next
    case variable(Int, Double) // future: freeze when register matches value
}

enum DebugLevel: Int, Comparable {
    case off   = 0
    case info  = 1
    case debug = 2

    static func < (lhs: DebugLevel, rhs: DebugLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    mutating func cycle() {
        self = switch self {
        case .off:   .info
        case .info:  .debug
        case .debug: .off
        }
    }
}

@Observable
class EmulatorViewModel {
    var displayDigits: [UInt8]  = Array(repeating: 0, count: 12)
    var displayCtrl:   [UInt8]  = Array(repeating: 0, count: 12)
    var dpPos:          UInt8   = 0
    var calcIndicatorOpacity: Double = 0.0
    var model: MachineModel     = .ti59
    var errorMessage: String?

    // ── Printer state ────────────────────────────────────────────────────────
    var printerLines: [String] = []
    var printerCodeLines: [Data] = []  // parallel to printerLines; 20 raw codes per line
    var printerClearID: Int = 0   // incremented on cut to reset Text identity and drop selection
    var printerTrace: Bool = false
    var printerConnected: Bool = true

    // ── C indicator drop debugger ─────────────────────────────────────────────
    // When enabled, prints one line per drop event — not 60 lines/s.
    // Watches snap.calcIndicator (raw C++ duty cycle, before Swift smoothing).
    // Also writes TI59_TRACE.bin (binary format — see DebugAPI.md).
    var cIndicatorDebug: Bool = false {
        didSet {
            if cIndicatorDebug {
                // TRACE ENABLED
                // a) Open or create file
                _ = AppSettings.traceDirectory()
                let success = traceWriter.open()

                // If open failed (e.g., iCloud unavailable), disable immediately
                if !success {
                    cIndicatorDebug = false
                    return
                }

                guard let m = machine else { return }

                // b) Tell C-code to start tracing
                m.traceFlags = [.pc, .regsFull]

                // c) Start draining via tick() calls (happens automatically at 60 Hz)
            } else {
                // TRACE DISABLED
                guard let m = machine else { return }

                // a) Tell C-code to stop writing events IMMEDIATELY
                m.traceFlags = .flagsNone

                // b) Drain remaining buffer on main thread immediately
                drainTraceEvents(machine: m)

                // c) Close file
                traceWriter.close()
            }
        }
    }
    private var cDropDebugger = CDropDebugger()
    private var cZeroFrames: Int = 0   // consecutive frames where fA was zero the entire frame
    private var traceWriter: TraceWriter!  // initialized in init, updated when model changes
    var isTraceAvailable: Bool { traceWriter?.isAvailable ?? true }  // false if trace location (e.g., iCloud) unavailable

    // ── Debug panel state ────────────────────────────────────────────────────
    var debugLevel: DebugLevel = .off
    var debugEnabled: Bool { debugLevel != .off }   // convenience for existing callers
    var debugLines: [String] = []
    var debugClearID: Int = 0   // incremented on clear to reset Text identity and drop selection
    var asmFileName: String = "No file selected"
    var asmWordCount: Int = 0
    var asmStatusMessage: String = "Load a hex opcode file and press Run."
    private var asmOverlayWords: [UInt16] = []
    var canRunASM: Bool { !asmOverlayWords.isEmpty }
    var asmOverlayActive: Bool = false

    // ── Live debug panel state (60 Hz real-time) ──────────────────────────────
    var liveDebugEnabled: Bool = false
    var liveDebugSnapshot: LiveDebugSnapshot = .empty
    var freezeReason: FreezeReason? = nil
    var isFrozen: Bool { freezeReason != nil }
    var pendingFreezeOnPCChange: Bool = false  // Freeze as soon as PC changes (first instruction)
    private var lastObservedPC: UInt16 = 0     // Track PC to detect changes

    // Frozen program caches (built on freeze entry, reused until unfreeze)
    private var frozenROMCache: [LiveDebugSnapshot.StepEntry]?
    private var frozenRAMCache: [LiveDebugSnapshot.StepEntry]?
    private var cachedPrSourceFlag: UInt8 = 0  // tracks which cache is currently valid

    // ── Live CPU view state (60 Hz real-time, runs while emulating) ────────────
    var cpuDebugSnapshot: CPUDebugSnapshot = .empty
    private var cpuFrameWindow: [TICpuFrame] = []  // rolling window of recent instructions

    // ── Frozen CPU inspector state (static snapshot when paused) ───────────────
    struct InspectorSnapshot {
        var pc: UInt16
        var opcode: UInt16
        var disasm: String
        var frame: TICpuFrame
        var isHistory: Bool  // true = executed, false = speculative (future ROM)
        var isCurrent: Bool  // true = this is where it froze
    }
    var cpuInspectorHistory: [InspectorSnapshot] = []  // 32 history + 1 current + 5 future
    var cpuInspectorUpdateID: Int = 0  // incremented every captureInspectorSnapshot call

    // ── Trace / debug state ──────────────────────────────────────────────────
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
    private var suspendedByLifecycle = false
    private static let constantMemoryFileName = "ti58c.mem"
    private static var constantMemoryURL: URL {
        CardStorage.directoryURL.appendingPathComponent(constantMemoryFileName)
    }

    init() {
        // Initialize traceWriter with default model
        traceWriter = TraceWriter(model: model)
        // Check trace availability at startup (for iOS/iPadOS iCloud detection, etc.)
        traceWriter.checkAvailability()
        Task { await self.start(model: AppSettings.resolvedStartupModel()) }
    }

    func start(model: MachineModel) async {
        persistConstantMemory()  // save TI-58C RAM before switching away
        stop()
        await drainEmulQueue()   // ensure old loop has exited before starting the new one
        self.model = model
        traceWriter = TraceWriter(model: model)  // reinitialize with new model for correct trace filename
        UserDefaults.standard.set(model.rawValue, forKey: SettingsKey.lastUsedModel)
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

            if let constData = try? ROMLoader.loadConstants(model: model) {
                wrapper.loadConstants(constData)
            }

            if model.hasConstantMemory, let saved = loadConstantMemory() {
                // Restore RAM before the emulation loop starts so the ROM's startup
                // routine sees the warm-start flag and skips its RAM clear —
                // matching the real TI-58C where CMOS RAM was always live.
                wrapper.deserialiseRAM(saved)
            }

            if !asmOverlayWords.isEmpty {
                let data = asmOverlayWords.withUnsafeBufferPointer { Data(buffer: $0) }
                if !wrapper.loadDebugOverlayWords(data) {
                    asmOverlayWords = []
                    asmOverlayActive = false
                    asmWordCount = 0
                    asmStatusMessage = "ASM overlay cleared (incompatible after model switch)."
                }
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

                // Check if pending freeze on PC change should activate
                if self.pendingFreezeOnPCChange {
                    // Get the user-visible PC (decoded from SCOM), not the raw CPU PC
                    let cpu = m.snapshotCPU()
                    let currentPC = self.decodeProgramCounter(from: cpu)

                    // Check if PC has changed from when we armed the freeze
                    if UInt16(currentPC) != self.lastObservedPC {
                        // PC has changed — freeze now
                        self.isRunning = false
                        self.pendingFreezeOnPCChange = false
                        self.freezeReason = .manual
                        DispatchQueue.main.async { [weak self] in
                            guard let self else { return }
                            if self.liveDebugEnabled {
                                self.liveDebugSnapshot = self.buildLiveSnapshot(machine: m)
                            }
                            self.captureInspectorSnapshot(machine: m)
                        }
                        return
                    }
                }

                let end = DispatchTime.now()
                let elapsed = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
                let remaining = batchMs - elapsed
                if remaining > 0 {
                    Thread.sleep(forTimeInterval: remaining)
                }

                // Persist TI-58C state after each 20 ms batch if needed
                if self.model.hasConstantMemory {
                    self.persistConstantMemory()
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

        let lines = machine.drainPrinterLines()
        if !lines.isEmpty {
            printerLines.append(contentsOf: lines)
        }

        // Drain C-core debug messages into the debug panel.
        if debugLevel != .off {
            let dbgMsgs = machine.drainDebugMessages()
            if !dbgMsgs.isEmpty {
                for msg in dbgMsgs {
                    guard msg.count >= 2 else { continue }
                    let levelChar = msg.first!
                    let msgLevel: DebugLevel = (levelChar == "I") ? .info : .debug
                    let text = String(msg.dropFirst(2))
                    debugAppend([text], level: msgLevel)
                }
            }
        }

        let codes = machine.drainPrinterCodeLines()
        if !codes.isEmpty {
            printerCodeLines.append(contentsOf: codes)
        }

        let snap = machine.getDisplay()
        var d = [UInt8](repeating: 0, count: 12)
        var c = [UInt8](repeating: 0, count: 12)
        withUnsafeBytes(of: snap.digits) { b in for i in 0..<12 { d[i] = b[i] } }
        withUnsafeBytes(of: snap.ctrl)   { b in for i in 0..<12 { c[i] = b[i] } }

        // Display content freeze: while display is ON (afterglow) but IDLE is 0 (RUN mode),
        // do not update display content. This prevents stale values (e.g., R5) from appearing
        // after exiting IDLE, while still showing the last captured display state.
        let cpuFrame = machine.snapshotCPU()
        let isIdle = (cpuFrame.flags & 0x0001) != 0          // FLG_IDLE
        let displayOn = cpuFrame.dispFilter < 3              // Display still on (not blanked yet)
        let shouldFreeze = displayOn && !isIdle              // Afterglow with RUN mode

        // Guard each assignment: @Observable only notifies SwiftUI when a property
        // is actually written, but the write itself counts as a change even if the
        // value is identical.  The guards prevent 60 Hz spurious re-renders when
        // the display is static (e.g. calculator idle showing a number).
        if !shouldFreeze {
            if displayDigits    != d               { displayDigits    = d }
            if displayCtrl      != c               { displayCtrl      = c }
            if dpPos            != snap.dpPos      { dpPos            = snap.dpPos }
        }
        // C indicator opacity driven by the integrated duty cycle from the C++ core.
        //
        // Hardware model (per Sladký 2014 HW guide):
        //   • IDLE mode: C driven by fA[14] only (other fA bits = display state)
        //   • RUN mode:  C driven by any fA bit
        //
        // 60 Hz aliasing: the ROM's IDLE display-update scan lasts ~4.5 ms
        // (16 IDLE steps × 281 µs/step).  The 60 Hz poll (16.7 ms window) can
        // capture the entire IDLE phase as a single zero-duty frame even though
        // the real C darkness is <4.5 ms.  On hardware that gap is imperceptible.
        //
        // Three-mode update:
        //   • target > current  → instant rise
        //   • target = 0, first zero frame → hold (aliasing artefact; see below)
        //   • target = 0, frame 2+         → rapid decay (genuine dark phase)
        //   • 0 < target < current → proportional-alpha fall
        // Live debug snapshot — sampled at 60 Hz when the panel is open (unless frozen).
        if liveDebugEnabled && !isFrozen {
            let s = buildLiveSnapshot(machine: machine)
            if s != liveDebugSnapshot { liveDebugSnapshot = s }
        }

        // CPU debug snapshot — sampled at 60 Hz to keep instruction history current.
        // Always update so SimpleLiveCPUView gets fresh data after freeze/resume.
        let s = buildCPUDebugSnapshot(machine: machine)
        if s != cpuDebugSnapshot { cpuDebugSnapshot = s }

        if cIndicatorDebug {
            cDropDebugger.update(snap.calcIndicator)
            // Drain trace events directly on main thread (tick() is already on main).
            // The emulation loop runs on the serial emulQueue, so async dispatches would
            // never execute until the loop exits — we drain here at 60 Hz instead.
            drainTraceEvents(machine: machine)
        }
        let target = Double(snap.calcIndicator) * 0.65
        if target < 0.001 {
            cZeroFrames += 1
            if cZeroFrames >= 2 {
                // Genuine sustained dark phase (error blink, computation with fA
                // cleared).  Decay rapidly — hardware LED has near-zero persistence.
                let decay = min(0.65, 0.35 * Double(cZeroFrames - 1))
                calcIndicatorOpacity = max(0.0, calcIndicatorOpacity - decay)
            }
            // cZeroFrames == 1: hold opacity unchanged.  A single zero frame is
            // a 60 Hz aliasing artefact of the ~4.5 ms IDLE scan (fA[14]=0 for
            // one digit cycle) — too brief to perceive on real hardware.
        } else if target >= calcIndicatorOpacity {
            cZeroFrames = 0
            calcIndicatorOpacity = target
        } else {
            cZeroFrames = 0
            let alpha = min(0.5, target / max(0.001, calcIndicatorOpacity))
            calcIndicatorOpacity += alpha * (target - calcIndicatorOpacity)
        }
    }

    func stop() {
        isRunning = false
        displayTimer?.invalidate()
        displayTimer = nil
    }

    /// Suspend emulation when the app enters the background.
    /// Stops the CPU loop and display timer to prevent battery drain.
    /// Does not destroy machine state — resumeFromBackground() will restart both.
    func suspendForBackground() {
        persistConstantMemory()
        suspendedByLifecycle = isRunning
        isRunning = false
        displayTimer?.invalidate()
        displayTimer = nil
    }

    /// Resume emulation after the app returns to the foreground.
    /// Restarts the CPU loop only if it was running at suspension time,
    /// so a user-triggered debug freeze is preserved across backgrounding.
    func resumeFromBackground() {
        guard machine != nil else { return }
        startDisplayRefresh()
        if suspendedByLifecycle {
            suspendedByLifecycle = false
            startEmulationLoop()
        }
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
        traceWriter.writeKeyDown(row: UInt8(row), col: UInt8(col))
        machine?.pressMatrixKey(UInt8((row + 1) * 10 + (col + 1)))
    }

    func releaseKey(row: Int, col: Int) {
        traceWriter.writeKeyUp(row: UInt8(row), col: UInt8(col))
        machine?.releaseMatrixKey(UInt8((row + 1) * 10 + (col + 1)))
    }

    // MARK: - Printer

    func pressPrinterPrint(_ pressed: Bool) { machine?.pressPrinterPrint(pressed) }
    func pressPrinterAdv(_ pressed: Bool)   { machine?.pressPrinterAdv(pressed) }
    func togglePrinterTrace() {
        printerTrace.toggle()
        machine?.setPrinterTrace(printerTrace)
    }
    func setPrinterConnected(_ connected: Bool) {
        printerConnected = connected
        machine?.setPrinterConnected(connected)
    }
    func cutPaper() { printerLines = []; printerCodeLines = []; printerClearID &+= 1 }

    // MARK: - Reset

    func resetMachine() {
        unfreeze()  // exit freeze mode when resetting
        asmOverlayActive = false
        cardState = .noCard
        printerTrace = false
        machine?.setPrinterTrace(false)
        machine?.reset()

        // Clear out-of-range registers for the current model
        let programRegs  = Int(machine?.partitionProgramRegs ?? 60)
        let totalRegs    = Int(machine?.ramRegisterCount ?? (model.hasLargeMemory ? 120 : model.hasConstantMemory ? 64 : 60))
        let dataRegCount = max(0, totalRegs - programRegs)
        let zeroNibbles  = Array(repeating: UInt8(0), count: 16)
        for regNum in dataRegCount..<totalRegs {
            machine?.setRawRegister(regNum, nibbles: Data(zeroNibbles))
        }

        debugAppend(["Calculator Reset"])
    }

    /// Clean reset (all models): zero all RAM, then reset.
    /// For TI-58C, writes the zeroed state immediately to the save file.
    func cleanResetMachine() {
        unfreeze()  // exit freeze mode when resetting
        asmOverlayActive = false
        machine?.deserialiseRAM(Data(repeating: 0, count: 120 * 16))
        cardState = .noCard
        printerTrace = false
        machine?.setPrinterTrace(false)
        machine?.reset()
        // Write zeroed state for TI-58C immediately
        persistConstantMemory()
        debugAppend(["Clean Reset — all registers cleared"])
    }

    // MARK: - Magnetic card reader

    func ejectIfSwiping() {
        if cardState == .swiping { ejectCard() }
    }

    private func beginSwipe(data: Data) {
        guard let machine, cardState == .noCard else { return }
        cardState = .swiping
        traceWriter.writeCardInsert()
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
        traceWriter.writeCardEject()
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
        let text = encodeConstantMemoryToText(data)
        let url = Self.constantMemoryURL
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func loadConstantMemory() -> Data? {
        let url = Self.constantMemoryURL
        var rawFileData: Data?
        let coordinator = NSFileCoordinator()
        var err: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &err) { src in
            rawFileData = try? Data(contentsOf: src)
        }
        guard let rawData = rawFileData else { return nil }

        // Try to decode as text format (new format)
        if let text = String(data: rawData, encoding: .utf8),
           let decodedData = decodeConstantMemoryFromText(text) {
            return decodedData
        }

        // Fallback: if file is exactly 120*16 bytes, treat as old binary format
        if rawData.count == 120 * 16 {
            return rawData
        }

        // Otherwise, silently fail and return nil (RAM will be initialized to zeros)
        return nil
    }

    /// Encode RAM data (120 regs × 16 nibbles) as human-readable text.
    /// Only includes non-zero registers.
    private func encodeConstantMemoryToText(_ data: Data) -> String {
        var lines: [String] = []
        lines.append("── Memory (non-zero registers) ──")

        for regNum in 0..<120 {
            let offset = regNum * 16
            guard offset + 16 <= data.count else { break }

            let nibbles = Array(data.subdata(in: offset..<(offset + 16)))

            // Check if register is all zeros
            if nibbles.allSatisfy({ $0 == 0 }) { continue }

            // Format: RXXX: HH HH HH HH HH HH HH HH
            let hexBytes = nibbles.map { String(format: "%02X", $0) }.joined(separator: " ")
            lines.append(String(format: "R%03d: %@", regNum, hexBytes as NSString))
        }

        return lines.joined(separator: "\n")
    }

    /// Decode human-readable text format back to RAM data (120 regs × 16 nibbles).
    /// Returns nil on parse error (which triggers fallback to old binary format).
    /// All registers are initialized to zero; only those in the text are updated.
    private func decodeConstantMemoryFromText(_ text: String) -> Data? {
        var resultBytes = [UInt8](repeating: 0, count: 120 * 16)

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and header line
            if trimmed.isEmpty || trimmed.hasPrefix("──") { continue }

            // Expected format: "RXXX: HH HH HH HH HH HH HH HH"
            guard trimmed.hasPrefix("R") else { continue }

            // Split on colon
            let parts = trimmed.components(separatedBy: ":")
            guard parts.count == 2 else { return nil }

            let regStr = String(parts[0].dropFirst())  // Remove "R" prefix
            guard let regNum = Int(regStr), regNum >= 0, regNum < 120 else { return nil }

            // Parse hex bytes from the second part
            let hexPart = parts[1].trimmingCharacters(in: .whitespaces)
            let hexTokens = hexPart.components(separatedBy: " ").filter { !$0.isEmpty }

            guard hexTokens.count == 16 else { return nil }

            let offset = regNum * 16
            for (i, hexToken) in hexTokens.enumerated() {
                guard let byte = UInt8(hexToken, radix: 16) else { return nil }
                resultBytes[offset + i] = byte
            }
        }

        return Data(resultBytes)
    }

    // MARK: - Trace / debug

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
        guard isFrozen else { return }
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

    /// Step once while frozen and refresh the inspector view with the new state.
    /// If the instruction has HOLD set (WAIT Dn), auto-steps until the PC advances.
    func stepFrozen() {
        guard isFrozen else { return }
        guard let m = machine else { return }
        emulQueue.async { [weak self, m] in
            guard let self else { return }
            let priorPC = m.currentPC
            var result = m.step()
            if result & 0x8000_0000 != 0 {
                let hitPC = m.currentPC
                DispatchQueue.main.async { self.onBreakpointHit(pc: hitPC) }
            } else if m.currentPC == priorPC {
                // PC didn't advance — HOLD is set (WAIT Dn). Step until it clears.
                var limit = 32
                while m.currentPC == priorPC && limit > 0 {
                    result = m.step()
                    if result & 0x8000_0000 != 0 {
                        let hitPC = m.currentPC
                        DispatchQueue.main.async { self.onBreakpointHit(pc: hitPC) }
                        break
                    }
                    limit -= 1
                }
            }
            m.beginNextStep()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.captureInspectorSnapshot(machine: m)
            }
        }
    }

    private func onBreakpointHit(pc: UInt16) {
        isPausedOnBreakpoint = true
        breakpointPC = pc
    }

    func freezeOnNextPCChange() {
        // Prepare to freeze as soon as the program counter changes (first instruction executes)
        // Track the decoded PC (from SCOM), not the raw CPU PC
        pendingFreezeOnPCChange = true
        guard let m = machine else { return }
        let cpu = m.snapshotCPU()
        lastObservedPC = UInt16(decodeProgramCounter(from: cpu))
    }

    func freeze(reason: FreezeReason = .manual, waitForKeycode: Bool = true) {
        isRunning = false
        freezeReason = reason
        asmOverlayActive = false
        pendingFreezeOnPCChange = false  // Cancel any pending freeze
        guard let m = machine else { return }
        // Advance to the next keycode boundary on the emulation queue (runs after the
        // running loop exits, since emulQueue is serial). Then capture state.
        emulQueue.async { [weak self, m] in
            if waitForKeycode {
                _ = m.stepUntilNextKeycode()  // advance to program-step boundary
            }
            // else: stop after the current ROM opcode — correct for CPU-level freeze
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Pre-execution phase: prepare ring buffer and snapshot for display
                m.beginNextStep()
                // Build program caches on freeze entry
                let cpu = m.snapshotCPU()
                let currentStep = self.decodeProgramCounter(from: cpu)
                let prSourceFlag = UInt8(cpu.SCOM.0.3)
                self.cachedPrSourceFlag = prSourceFlag
                if prSourceFlag == 0 {
                    self.frozenRAMCache = self.buildFullProgram(machine: m, currentStep: currentStep, prSourceFlag: 0)
                } else if prSourceFlag == 8 {
                    self.frozenROMCache = self.buildFullProgram(machine: m, currentStep: currentStep, prSourceFlag: 8)
                }
                if self.liveDebugEnabled {
                    self.liveDebugSnapshot = self.buildLiveSnapshot(machine: m)
                }
                self.captureInspectorSnapshot(machine: m)
            }
        }
    }

    /// Step one keycode while frozen. Advances to the next keycode boundary and
    /// refreshes the live debug and CPU inspector snapshots. Updates frozen program
    /// caches if Prg Source changed, and re-centers current step.
    func stepKeycode() {
        guard isFrozen else { return }
        guard let m = machine else { return }
        emulQueue.async { [weak self, m] in
            guard let self else { return }
            _ = m.stepUntilNextKeycode()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                m.beginNextStep()
                let cpu = m.snapshotCPU()
                let currentStep = self.decodeProgramCounter(from: cpu)
                let prSourceFlag = UInt8(cpu.SCOM.0.3)

                // Check if Prg Source changed; if so, rebuild appropriate cache
                if prSourceFlag != self.cachedPrSourceFlag {
                    self.cachedPrSourceFlag = prSourceFlag
                    if prSourceFlag == 0 {
                        self.frozenRAMCache = self.buildFullProgram(machine: m, currentStep: currentStep, prSourceFlag: 0)
                        self.frozenROMCache = nil
                    } else if prSourceFlag == 8 {
                        self.frozenROMCache = self.buildFullProgram(machine: m, currentStep: currentStep, prSourceFlag: 8)
                        self.frozenRAMCache = nil
                    }
                } else {
                    // Prg Source unchanged: update isCurrent markers in existing cache
                    self.updateCachedProgramCurrent(to: currentStep, prSourceFlag: prSourceFlag)
                }

                if self.liveDebugEnabled {
                    self.liveDebugSnapshot = self.buildLiveSnapshot(machine: m)
                }
                self.captureInspectorSnapshot(machine: m)
            }
        }
    }

    /// Capture the current CPU state and last 32 executed instructions for the frozen inspector view.
    /// Reads (without draining) the ring buffer to preserve history across steps.
    private func captureInspectorSnapshot(machine m: TI59MachineWrapper) {
        // Read (without draining) all available frames from the ring buffer
        let framesNS = m.readCpuFrames(max: 1024)
        let frames = (framesNS as [NSValue]).map { v -> TICpuFrame in
            var f = TICpuFrame()
            v.getValue(&f)
            return f
        }

        cpuInspectorHistory = []
        let currentPC = m.currentPC

        // Get program source to determine if we can read ahead
        let cpu = m.snapshotCPU()

        // Add history: all executed instructions from the ring buffer (up to 1024)
        for i in 0..<frames.count {
            let frame = frames[i]
            let disasm = TI59MachineWrapper.disassemblePC(frame.pc, opcode: frame.opcode)
            let isLastInstruction = (i == frames.count - 1)
            cpuInspectorHistory.append(InspectorSnapshot(
                pc: frame.pc,
                opcode: frame.opcode,
                disasm: disasm,
                frame: frame,
                isHistory: true,
                isCurrent: isLastInstruction
            ))
        }

        // Certain next instruction — always show, even when same PC (WAIT/KEY loops on same instruction)
        // cpu.opcode is now the real next opcode from snapshotCPU()
        let nextOpcode = cpu.opcode
        let disasm = TI59MachineWrapper.disassemblePC(currentPC, opcode: nextOpcode)
        let emptyFrame = TICpuFrame()
        cpuInspectorHistory.append(InspectorSnapshot(
            pc: currentPC,
            opcode: nextOpcode,
            disasm: disasm,
            frame: emptyFrame,
            isHistory: false,
            isCurrent: false
        ))

        // Signal that the inspector snapshot has been updated (fires onChange observers)
        cpuInspectorUpdateID &+= 1
    }

    /// Update isCurrent markers in the cached program for the given current step.
    /// Clears old current marker and sets new one.
    private func updateCachedProgramCurrent(to currentStep: Int, prSourceFlag: UInt8) {
        if prSourceFlag == 0, var cache = frozenRAMCache {
            for i in 0..<cache.count {
                cache[i].isCurrent = (cache[i].stepNum == currentStep)
            }
            frozenRAMCache = cache
        } else if prSourceFlag == 8, var cache = frozenROMCache {
            for i in 0..<cache.count {
                cache[i].isCurrent = (cache[i].stepNum == currentStep)
            }
            frozenROMCache = cache
        }
    }

    /// Return the full cached program when frozen, or nil if not frozen.
    var frozenCachedProgram: [LiveDebugSnapshot.StepEntry]? {
        if cachedPrSourceFlag == 0 {
            return frozenRAMCache
        } else if cachedPrSourceFlag == 8 {
            return frozenROMCache
        }
        return nil
    }

    /// Return the index of the current step in the cached program when frozen, or -1 if not frozen.
    var frozenCachedCurrentIndex: Int {
        guard let program = frozenCachedProgram else { return -1 }
        return program.firstIndex(where: { $0.isCurrent }) ?? -1
    }

    func unfreeze() {
        freezeReason = nil
        frozenROMCache = nil
        frozenRAMCache = nil
        cachedPrSourceFlag = 0
        startEmulationLoop()
        startDisplayRefresh()
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
        var cpu: TICpuFrame
    }

    /// Read the full calculator state without disturbing execution.
    /// Returns nil if the machine is not yet started.
    func getCalcSnapshot() -> CalcSnapshot? {
        guard let m = machine else { return nil }
        // Number of accessible data registers depends on the current partition:
        // programRAMregs occupy RAM[0..(n-1)]; data regs fill RAM[n..totalRegs-1] top-down.
        let partitionProgramRegs = Int(m.partitionProgramRegs)
        let totalRegs = Int(m.ramRegisterCount)

        // If partition is invalid (claims more than physically exists), return empty registers
        guard partitionProgramRegs <= totalRegs else {
            let regs = [Double](repeating: 0, count: 0)
            let steps = Array(m.allProgramSteps() as Data)
            let cpu = m.snapshotCPU()
            return CalcSnapshot(registers: regs, programSteps: steps,
                                printerBuffer: m.printerBufferContent, cpu: cpu)
        }

        let numRegs = max(0, totalRegs - partitionProgramRegs)
        var regs = [Double](repeating: 0, count: numRegs)
        for i in 0..<numRegs { regs[i] = m.dataRegister(i) }
        let steps = Array(m.allProgramSteps() as Data)
        let cpu = m.snapshotCPU()
        return CalcSnapshot(registers: regs, programSteps: steps,
                            printerBuffer: m.printerBufferContent, cpu: cpu)
    }

    /// Build full program for a given source (RAM or ROM), used for freeze caching.
    /// Returns all steps as StepEntry with mnemonics, marking currentStep as current.
    private func buildFullProgram(machine m: TI59MachineWrapper, currentStep: Int, prSourceFlag: UInt8) -> [LiveDebugSnapshot.StepEntry] {
        var result: [LiveDebugSnapshot.StepEntry] = []

        switch prSourceFlag {
        case 0:
            // User RAM — all program steps
            let steps = Array(m.allProgramSteps() as Data)
            guard !steps.isEmpty else { return [] }

            // Build set of argument step indices
            var argSteps = Set<Int>()
            for i in 0..<steps.count {
                let stepsAfter = TI59KeyNames.stepsAfter(for: steps[i])
                if stepsAfter > 0 {
                    for j in 1...stepsAfter {
                        if i + j < steps.count {
                            argSteps.insert(i + j)
                        }
                    }
                }
            }

            for i in 0..<steps.count {
                let kc = steps[i]
                let isArgument = argSteps.contains(i)
                let mnemonic = isArgument ? String(format: "%02d", kc) : TI59KeyNames.mnemonic(for: kc)

                result.append(.init(
                    stepNum: i,
                    keycode: kc,
                    mnemonic: mnemonic,
                    isCurrent: i == currentStep
                ))
            }

        case 8:
            // Main ROM (384 steps)
            var keycodes: [UInt8] = []
            for addr in 0..<384 {
                keycodes.append(m.romKeycode(at: addr))
            }

            // Detect argument step indices
            var argSteps = Set<Int>()
            for i in 0..<keycodes.count {
                let stepsAfter = TI59KeyNames.stepsAfter(for: keycodes[i])
                if stepsAfter > 0 {
                    for j in 1...stepsAfter {
                        if i + j < keycodes.count {
                            argSteps.insert(i + j)
                        }
                    }
                }
            }

            for (idx, keycode) in keycodes.enumerated() {
                let isArgument = argSteps.contains(idx)
                let mnemonic = isArgument ? String(format: "%02d", keycode) : TI59KeyNames.mnemonic(for: keycode)

                result.append(.init(
                    stepNum: idx,
                    keycode: keycode,
                    mnemonic: mnemonic,
                    isCurrent: idx == currentStep
                ))
            }

        default:
            // Library or other: TBD
            break
        }

        return result
    }

    /// Build a real-time debug snapshot for the live debug view.
    /// Called from tick() at 60 Hz only when liveDebugEnabled.
    private func buildLiveSnapshot(machine m: TI59MachineWrapper) -> LiveDebugSnapshot {
        let partitionProgramRegs = Int(m.partitionProgramRegs)
        let totalRegs = Int(m.ramRegisterCount)   // 60 (TI-58), 64 (TI-58C), or 120 (TI-59)
        let displayableRegs = model.hasConstantMemory ? 60 : totalRegs

        // Clamp programRegs to physical RAM; quirky partitions may claim more than exists
        let programRegs = min(partitionProgramRegs, totalRegs)
        let dataRegCount = max(0, displayableRegs - programRegs)
        var snap = LiveDebugSnapshot()
        snap.programRegCount = partitionProgramRegs  // Store the claimed partition, not the clamped value
        snap.dataRegCount = dataRegCount

        // Data registers: check all non-zero values in the data region
        // Visible registers (programRegs to displayableRegs-1) shown as R##
        // Hidden registers (displayableRegs to totalRegs-1) shown as H##
        // Guard against quirky partitions: only access what physically exists
        guard programRegs <= totalRegs else { return snap }
        for ramIdx in programRegs..<totalRegs {
            guard ramIdx >= 0 && ramIdx < totalRegs else { continue }
            let raw = m.rawRegister(ramIdx) as Data
            if raw.contains(where: { $0 != 0 }) {
                let value = TI59MachineWrapper.decodeBCD(raw)
                if ramIdx < displayableRegs {
                    // Visible register
                    let regNum = displayableRegs - 1 - ramIdx
                    snap.nonZeroRegs.append(.init(num: regNum, value: value, isHidden: false))
                } else {
                    // Hidden register
                    let hiddenNum = ramIdx - displayableRegs
                    snap.nonZeroRegs.append(.init(num: hiddenNum, value: value, isHidden: true))
                }
            }
        }

        // CPU snapshot (single ~370-byte memcpy)
        let cpu = m.snapshotCPU()

        // HIR registers 1–8 (stored in SCOM[1..8]; decode as Double)
        // Each HIR is 16 BCD nibbles: bits 15–3 = mantissa, 2–1 = exponent, 0 = sign
        withUnsafeBytes(of: cpu.SCOM) { bytes in
            for hirNum in 1...8 {
                let scomRow = hirNum  // HIR N lives in SCOM[N]
                let scomBytes = Data(bytes[(scomRow * 16)..<((scomRow + 1) * 16)])
                let value = TI59MachineWrapper.decodeBCD(scomBytes)
                switch hirNum {
                case 1: snap.hir1 = value
                case 2: snap.hir2 = value
                case 3: snap.hir3 = value
                case 4: snap.hir4 = value
                case 5: snap.hir5 = value
                case 6: snap.hir6 = value
                case 7: snap.hir7 = value
                case 8: snap.hir8 = value
                default: break
                }
            }
        }

        // T register (stored in SCOM[11]; the stack top / last-X equivalent)
        withUnsafeBytes(of: cpu.SCOM) { bytes in
            let tBytes = Data(bytes[(11 * 16)..<(12 * 16)])
            snap.tRegister = TI59MachineWrapper.decodeBCD(tBytes)
        }

        // Program Source Flag (SCOM[0], nibble 3; per SCOM map)
        snap.prSourceFlag = UInt8(cpu.SCOM.0.3)

        // Degree/Radian/Grad mode (SCOM[13][0], nibble 0; per SCOM map)
        // Encoding: 0=DEG, 1=GRAD, 12(C)=RAD
        withUnsafeBytes(of: cpu.SCOM) { bytes in
            let modeNibble = bytes[13 * 16 + 0] & 0x0F
            snap.angleMode = {
                switch modeNibble {
                case 0x0: return .deg
                case 0x1: return .grad
                case 0xC: return .rad
                default: return nil
                }
            }()
        }

        // Pending operations count (SCOM[13], bit 1 area; exact position TBD)
        withUnsafeBytes(of: cpu.SCOM) { bytes in
            // Per SCOM map: "No. of pending ops" is in SCOM[13]
            // Assuming it's in nibble 0 or bits within the row
            snap.pendingOpsCount = Int(bytes[13 * 16 + 0])  // TBD: exact bit position
        }

        // Calculator flags 0–9 (stored in SCOM[0], nibbles 11–15)
        // Encoding: flags 0-4 use bit 1 (value 1), flags 5-9 use bit 2 (value 2) in their respective nibbles
        // Flag N maps to nibble (11 + N%5) and bit (1 if N<5 else 2)
        let n11 = Int(cpu.SCOM.0.11)
        let n12 = Int(cpu.SCOM.0.12)
        let n13 = Int(cpu.SCOM.0.13)
        let n14 = Int(cpu.SCOM.0.14)
        let n15 = Int(cpu.SCOM.0.15)

        snap.calcFlags = [
            (n11 & 1) != 0,  // Flag 0
            (n12 & 1) != 0,  // Flag 1
            (n13 & 1) != 0,  // Flag 2
            (n14 & 1) != 0,  // Flag 3
            (n15 & 1) != 0,  // Flag 4
            (n11 & 2) != 0,  // Flag 5
            (n12 & 2) != 0,  // Flag 6
            (n13 & 2) != 0,  // Flag 7
            (n14 & 2) != 0,  // Flag 8
            (n15 & 2) != 0,  // Flag 9
        ]

        // FIX (SCOM[0].15: if 0 show dash, else (raw - 2) % 10), IO User Flags (SCOM[0], nibbles 14–10), Last Key (SCOM[0], nibbles 2–1)
        let fix_raw = Int(cpu.SCOM.0.0)
        let io14 = Int(cpu.SCOM.0.1)
        let io13 = Int(cpu.SCOM.0.2)
        let io12 = Int(cpu.SCOM.0.3)
        let io11 = Int(cpu.SCOM.0.4)
        let io10 = Int(cpu.SCOM.0.5)
        let key2 = Int(cpu.SCOM.0.13)
        let key1 = Int(cpu.SCOM.0.14)
        if fix_raw == 0 {
            snap.fixIndicator = "-"
        } else {
            let fix = ((fix_raw - 2) % 10 + 10) % 10
            snap.fixIndicator = String(fix)
        }
        snap.ioUserFlags = String(format: "%d%d%d%d%d", io14, io13, io12, io11, io10)
        snap.lastKey = String(format: "%d%d", key2, key1)

        // Debug indicators from FA and FB registers
        let fa = cpu.fA
        let fb = cpu.fB
        snap.fA = fa
        snap.fB = fb

        // 2nd and INV indicators (from FA register, 2nd digit from left = nibble 1)
        // Bit 0 (rightmost) = INV, Bit 1 = 2nd
        let faNibble1 = Int((fa >> 8) & 0xF)  // 2nd digit from left (bits 11-8)
        let invBit = (faNibble1 & 0x1) != 0
        let secondBit = (faNibble1 & 0x2) != 0
        snap.invIndicator = invBit ? "INV" : ""
        snap.secondIndicator = secondBit ? "2nd" : ""

        // EE indicator (from FB register, 3rd digit from left, bit 3 from right)
        let fbNibble2 = Int((fb >> 4) & 0xF)  // 3rd digit from left (bits 7-4)
        let engBit = (fbNibble2 & 0x8) != 0
        snap.engIndicator = engBit ? "Eng" : ""

        // Program steps window — source depends on PRG SOURCE flag
        let decodedPC = decodeProgramCounter(from: cpu)

        // When frozen: currentStep is the last executed instruction,
        // nextStep is what PC points to (next to execute)
        if isFrozen {
            snap.currentStep = max(0, decodedPC - 1)
            snap.nextStepNum = decodedPC
        } else {
            // When running: currentStep is the next to execute (pre-execution state)
            snap.currentStep = decodedPC
            snap.nextStepNum = -1
        }

        // Pre-fetch RAM program steps once (used by both window and nextStep population)
        let ramSteps = snap.prSourceFlag == 0 ? Array(m.allProgramSteps() as Data) : []

        switch snap.prSourceFlag {
        case 0:
            // User RAM — existing behavior
            let steps = ramSteps
            if !steps.isEmpty {
                let center = snap.currentStep >= 0 ? snap.currentStep : 0
                let lo = max(0, center - 5)
                let hi = min(steps.count - 1, center + 5)
                if lo <= hi {
                    // Build set of argument step indices (not keycodes)
                    var argSteps = Set<Int>()
                    for i in lo...hi {
                        let stepsAfter = TI59KeyNames.stepsAfter(for: steps[i])
                        if stepsAfter > 0 {
                            for j in 1...stepsAfter {
                                if i + j <= hi {
                                    argSteps.insert(i + j)
                                }
                            }
                        }
                    }

                    for i in lo...hi {
                        let kc = steps[i]
                        let isArgument = argSteps.contains(i)
                        let mnemonic = isArgument ? String(format: "%02d", kc) : TI59KeyNames.mnemonic(for: kc)

                        snap.programWindow.append(.init(
                            stepNum: i,
                            keycode: kc,
                            mnemonic: mnemonic,
                            isCurrent: i == snap.currentStep
                        ))
                    }
                }
            }

        case 8:
            // Main ROM (384 keycode programs from constants)
            let romCenter = snap.currentStep
            let lo = max(0, romCenter - 5)
            let hi = min(383, romCenter + 5)

            // Build array of keycodes for this range
            var keycodes: [UInt8] = []
            for addr in lo...hi {
                keycodes.append(m.romKeycode(at: addr))
            }

            // Detect argument step indices
            var argSteps = Set<Int>()
            for i in 0..<keycodes.count {
                let stepsAfter = TI59KeyNames.stepsAfter(for: keycodes[i])
                if stepsAfter > 0 {
                    for j in 1...stepsAfter {
                        if i + j < keycodes.count {
                            argSteps.insert(i + j)
                        }
                    }
                }
            }

            for (idx, keycode) in keycodes.enumerated() {
                let addr = lo + idx
                let isArgument = argSteps.contains(idx)
                let mnemonic = isArgument ? String(format: "%02d", keycode) : TI59KeyNames.mnemonic(for: keycode)
                snap.programWindow.append(.init(
                    stepNum: addr, keycode: keycode, mnemonic: mnemonic,
                    isCurrent: addr == romCenter))
            }

        default:
            // PRG SOURCE = 1 (library) or other: TBD
            break
        }

        // When frozen: populate nextStep fields from the next instruction to execute
        if isFrozen && snap.nextStepNum >= 0 {
            switch snap.prSourceFlag {
            case 0:
                // User RAM (steps already fetched above)
                if snap.nextStepNum < ramSteps.count {
                    let nextKeycode = ramSteps[snap.nextStepNum]
                    snap.nextStepKeycode = nextKeycode
                    let isArgument = {
                        // Check if this step is an argument for a previous instruction
                        if snap.nextStepNum == 0 { return false }
                        let stepsAfter = TI59KeyNames.stepsAfter(for: ramSteps[snap.nextStepNum - 1])
                        return stepsAfter > 0 && snap.nextStepNum - 1 + stepsAfter >= snap.nextStepNum
                    }()
                    snap.nextStepMnemonic = isArgument ? String(format: "%02d", nextKeycode) : TI59KeyNames.mnemonic(for: nextKeycode)
                }
            case 8:
                // Main ROM
                if snap.nextStepNum < 384 {
                    let nextKeycode = m.romKeycode(at: snap.nextStepNum)
                    snap.nextStepKeycode = nextKeycode
                    let isArgument = {
                        // Check if this step is an argument for a previous instruction
                        if snap.nextStepNum == 0 { return false }
                        let prevKeycode = m.romKeycode(at: snap.nextStepNum - 1)
                        let stepsAfter = TI59KeyNames.stepsAfter(for: prevKeycode)
                        return stepsAfter > 0 && snap.nextStepNum - 1 + stepsAfter >= snap.nextStepNum
                    }()
                    snap.nextStepMnemonic = isArgument ? String(format: "%02d", nextKeycode) : TI59KeyNames.mnemonic(for: nextKeycode)
                }
            default:
                break
            }
        }

        // Return address stack (SCOM[14:15]) — 6 levels of subroutine return addresses
        // Each level: 5 nibbles (1 PRG SOURCE + 4 address in Base 80, read right-to-left)
        // Format: Nibble 0 = count, then Level 1-3 (5 nibbles each) in SCOM[15], Level 4-6 in SCOM[14]
        withUnsafeBytes(of: cpu.SCOM) { bytes in
            let baseOffset14 = 14 * 16
            let baseOffset15 = 15 * 16

            // Collect all 16 nibbles from SCOM[15] (left to right)
            var nibbles15: [UInt8] = []
            for i in 0..<16 {
                nibbles15.append(bytes[baseOffset15 + i] & 0xF)
            }

            // Collect all 16 nibbles from SCOM[14] (left to right)
            var nibbles14: [UInt8] = []
            for i in 0..<16 {
                nibbles14.append(bytes[baseOffset14 + i] & 0xF)
            }

            // Count from first nibble of SCOM[15]
            let count = Int(nibbles15[0])

            // Decode levels: PRG SOURCE at position 0, address (Base 80) at positions 1-4 (read right-to-left)
            // Level 1: positions 1-5
            let l1_src = nibbles15[1]
            let l1 = Int(nibbles15[5]) * 800 + Int(nibbles15[4]) * 80 + Int(nibbles15[3]) * 8 + Int(nibbles15[2])

            // Level 2: positions 6-10
            let l2_src = nibbles15[6]
            let l2 = Int(nibbles15[10]) * 800 + Int(nibbles15[9]) * 80 + Int(nibbles15[8]) * 8 + Int(nibbles15[7])

            // Level 3: positions 11-15
            let l3_src = nibbles15[11]
            let l3 = Int(nibbles15[15]) * 800 + Int(nibbles15[14]) * 80 + Int(nibbles15[13]) * 8 + Int(nibbles15[12])

            // Level 4: positions 1-5
            let l4_src = nibbles14[1]
            let l4 = Int(nibbles14[5]) * 800 + Int(nibbles14[4]) * 80 + Int(nibbles14[3]) * 8 + Int(nibbles14[2])

            // Level 5: positions 6-10
            let l5_src = nibbles14[6]
            let l5 = Int(nibbles14[10]) * 800 + Int(nibbles14[9]) * 80 + Int(nibbles14[8]) * 8 + Int(nibbles14[7])

            // Level 6: positions 11-15
            let l6_src = nibbles14[11]
            let l6 = Int(nibbles14[15]) * 800 + Int(nibbles14[14]) * 80 + Int(nibbles14[13]) * 8 + Int(nibbles14[12])

            snap.returnAddress = String(format: "L6:%03d L5:%03d L4:%03d L3:%03d L2:%03d L1:%03d (count=%d)",
                l6, l5, l4, l3, l2, l1, count)
            snap.returnAddressSourceFlags = [l1_src, l2_src, l3_src, l4_src, l5_src, l6_src]
            snap.returnAddresses = [l1, l2, l3, l4, l5, l6]
        }

        // SCOM rows (all 16, plus extract rows 0–3 for printer)
        withUnsafeBytes(of: cpu.SCOM) { bytes in
            snap.scomRows = (0..<16).map { row in
                (0..<16).map { String(bytes[row * 16 + $0], radix: 16, uppercase: false) }.joined()
            }
        }
        snap.printerSCOM = Array(snap.scomRows.prefix(4))

        return snap
    }

    /// Build CPU debug snapshot with disassembled trace history.
    /// Drains last 32 instructions from trace ring with their pre-execution CPU snapshots.
    /// Enables TRACE_REGS_FULL automatically so every instruction has a snapshot.
    private func buildCPUDebugSnapshot(machine m: TI59MachineWrapper) -> CPUDebugSnapshot {
        var snap = CPUDebugSnapshot()
        snap.currentPC = m.currentPC
        snap.isPaused = isPausedOnBreakpoint
        snap.pausedPC = breakpointPC

        // Ensure trace flags are set so the CPU generates events
        let requiredFlags: TITraceFlags = [.pc, .regsFull]
        if !m.traceFlags.contains(requiredFlags) {
            m.traceFlags = m.traceFlags.union(requiredFlags)
        }

        // Read (without draining) all recent frames from the ring buffer
        let framesNS = m.readCpuFrames(max: 1024)
        let newFrames = (framesNS as [NSValue]).map { v -> TICpuFrame in
            var f = TICpuFrame()
            v.getValue(&f)
            return f
        }

        // Store frames in the rolling window
        cpuFrameWindow = newFrames

        // Build recent instructions from the accumulated window (show last 32)
        let instructionsToShow = min(32, cpuFrameWindow.count)
        snap.recentInstructions = []
        for i in (cpuFrameWindow.count - instructionsToShow)..<cpuFrameWindow.count {
            let frame = cpuFrameWindow[i]
            let disasm = TI59MachineWrapper.disassemblePC(frame.pc, opcode: frame.opcode)
            snap.recentInstructions.append(CPUDebugSnapshot.Instruction(
                pc: frame.pc,
                opcode: frame.opcode,
                disasm: disasm,
                frame: frame
            ))
        }

        return snap
    }

    /// Decode the program counter from SCOM[0] positions 4-7.
    /// It's encoded in base-80, so to speak.
    private func decodeProgramCounter(from cpu: TICpuFrame) -> Int {
        // PC encoding formula
        let n4 = Int(cpu.SCOM.0.4)
        let n5 = Int(cpu.SCOM.0.5)
        let n6 = Int(cpu.SCOM.0.6)
        let n7 = Int(cpu.SCOM.0.7)

        let pc = n7 * 800 + n6 * 80 + n5 * 8 + n4
        return pc
    }

    func toggleDebug() {
        debugLevel.cycle()
        machine?.setDebugLevel(UInt8(debugLevel.rawValue))
    }

    func clearDebug() {
        debugLines = []
        debugClearID &+= 1
    }

    func loadASMOverlayFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            asmStatusMessage = "Could not read ASM file."
            errorMessage = "Could not read ASM file."
            return
        }

        do {
            let words = try parseASMWords(from: text)
            guard let m = machine else {
                asmStatusMessage = "Machine not initialized yet."
                return
            }
            let data = words.withUnsafeBufferPointer { Data(buffer: $0) }
            guard m.loadDebugOverlayWords(data) else {
                asmStatusMessage = "ASM program exceeds overlay range 0x1800-0x1FFF."
                errorMessage = asmStatusMessage
                return
            }
            asmOverlayWords = words
            asmFileName = url.lastPathComponent
            asmWordCount = words.count
            asmStatusMessage = String(format: "Loaded %d word(s) at 0x1800.", words.count)
        } catch {
            let msg = error.localizedDescription
            asmStatusMessage = msg
            errorMessage = msg
        }
    }

    func clearASMOverlay() {
        machine?.clearDebugOverlay()
        asmOverlayWords = []
        asmOverlayActive = false
        asmWordCount = 0
        asmStatusMessage = "ASM overlay cleared."
    }

    func runASMOverlay() {
        guard !asmOverlayWords.isEmpty else {
            asmStatusMessage = "No ASM overlay loaded."
            return
        }
        guard let m = machine else {
            asmStatusMessage = "Machine not initialized yet."
            return
        }

        isRunning = false
        isPausedOnBreakpoint = false
        breakpointPC = nil
        pendingFreezeOnPCChange = false
        freezeReason = nil
        frozenROMCache = nil
        frozenRAMCache = nil
        cachedPrSourceFlag = 0

        var steps: UInt32 = 0
        var sawHold: ObjCBool = false
        var ok = false
        var loaded = true

        // Wait until any in-flight step batch finishes, then run the injection.
        emulQueue.sync {
            let data = self.asmOverlayWords.withUnsafeBufferPointer { Data(buffer: $0) }
            if !m.loadDebugOverlayWords(data) {
                loaded = false
                ok = false
                return
            }
            ok = m.runDebugOverlay(at: 0x1800, maxSteps: 8192, steps: &steps, sawHold: &sawHold)
            m.beginNextStep()
        }

        if !loaded {
            asmStatusMessage = "ASM program exceeds overlay range 0x1800-0x1FFF."
            errorMessage = asmStatusMessage
        } else if ok {
            asmStatusMessage = sawHold.boolValue
                ? "ASM entered at 0x1800 (HOLD detected after \(steps) step(s))."
                : "ASM entered at 0x1800 (\(steps) step(s))."
            asmOverlayActive = true
            startEmulationLoop()
            startDisplayRefresh()
        } else {
            asmStatusMessage = "ASM run timed out before HOLD (\(steps) step(s))."
            errorMessage = asmStatusMessage
        }
    }

    private func parseASMWords(from text: String) throws -> [UInt16] {
        enum ASMParseError: LocalizedError {
            case noHexSection
            case noWords
            case invalidToken(String)
            case tooLarge(Int)

            var errorDescription: String? {
                switch self {
                case .noHexSection:
                    return "No HEX: section found in ASM file."
                case .noWords:
                    return "No hex opcode words found after HEX: in ASM file."
                case .invalidToken(let token):
                    return "Invalid token in HEX section: \(token)"
                case .tooLarge(let count):
                    return "ASM contains \(count) words; maximum is 2048 (0x1800-0x1FFF)."
                }
            }
        }

        // Find the HEX: marker and parse only the text that follows it.
        let lines = text.components(separatedBy: .newlines)
        guard let hexLine = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).uppercased() == "HEX:" }) else {
            throw ASMParseError.noHexSection
        }
        let hexText = lines[(hexLine + 1)...].joined(separator: "\n")

        let pattern = #"0[xX][0-9A-Fa-f]+|[0-9A-Fa-f]{4,}"#
        let regex = try NSRegularExpression(pattern: pattern)
        let nsText = hexText as NSString
        let matches = regex.matches(in: hexText, range: NSRange(location: 0, length: nsText.length))

        var words: [UInt16] = []
        words.reserveCapacity(matches.count)

        for match in matches {
            var token = nsText.substring(with: match.range)
            if token.hasPrefix("0x") || token.hasPrefix("0X") {
                token.removeFirst(2)
            }
            guard !token.isEmpty else { continue }
            guard token.allSatisfy({ $0.isHexDigit }) else {
                throw ASMParseError.invalidToken(token)
            }
            if token.count % 4 != 0 {
                throw ASMParseError.invalidToken(token)
            }

            var idx = token.startIndex
            while idx < token.endIndex {
                let next = token.index(idx, offsetBy: 4)
                let chunk = String(token[idx..<next])
                guard let value = UInt16(chunk, radix: 16) else {
                    throw ASMParseError.invalidToken(chunk)
                }
                words.append(value & 0x1FFF)
                idx = next
            }
        }

        if words.isEmpty {
            throw ASMParseError.noWords
        }
        if words.count > 2048 {
            throw ASMParseError.tooLarge(words.count)
        }
        return words
    }

    private func debugAppend(_ lines: [String], level: DebugLevel = .info) {
        guard debugLevel >= level else { return }
        debugLines.append(contentsOf: lines)
    }

    /// Dump non-zero data variables within the current partition.
    /// Displays visible registers as R00–Rnn, hidden ones (beyond 60) as H00–Hnn.
    /// Sorted by label for consistent output.
    func debugDumpVars() {
        guard let m = machine else { return }
        let partitionProgramRegs = Int(m.partitionProgramRegs)
        let totalRegs   = Int(m.ramRegisterCount)   // 60 (TI-58), 64 (TI-58C), or 120 (TI-59)
        let model = self.model

        // For TI-58/58C, treat as 60-register address space; TI-59 uses full 120
        let displayableRegs = model.hasConstantMemory ? 60 : totalRegs

        // Clamp to physical RAM; quirky partitions may claim more than exists
        let programRegs = min(partitionProgramRegs, totalRegs)
        let visibleDataRegCount = displayableRegs - programRegs

        guard visibleDataRegCount > 0 else {
            debugLines.append("── Vars: no data registers in current partition ──")
            return
        }
        var lines: [String] = [String(format: "── Vars R00–R%02d ──", visibleDataRegCount - 1)]

        // Collect all non-zero registers with labels, then sort for consistent output
        var regEntries: [(label: String, value: Double)] = []

        // Check hidden registers first (RAM[displayableRegs..totalRegs-1])
        // Only iterate through physically existing registers
        for ramIdx in displayableRegs..<totalRegs {
            guard ramIdx >= 0 && ramIdx < totalRegs else { continue }
            let raw = m.rawRegister(ramIdx) as Data
            if raw.contains(where: { $0 != 0 }) {
                let v = TI59MachineWrapper.decodeBCD(raw)
                let hiddenIdx = ramIdx - displayableRegs
                regEntries.append((label: String(format: "H%02d", hiddenIdx), value: v))
            }
        }

        // Check visible data registers (RAM[programRegs..displayableRegs-1])
        // Clamp upper bound to physical RAM limit
        let visibleEnd = min(displayableRegs, totalRegs)
        for ramIdx in programRegs..<visibleEnd {
            guard ramIdx < totalRegs else { break }
            let raw = m.rawRegister(ramIdx) as Data
            if raw.contains(where: { $0 != 0 }) {
                let v = TI59MachineWrapper.decodeBCD(raw)
                let dataIdx = displayableRegs - 1 - ramIdx
                regEntries.append((label: String(format: "R%02d", dataIdx), value: v))
            }
        }

        // Sort by label and add to output
        regEntries.sort { $0.label < $1.label }
        for entry in regEntries {
            lines.append(String(format: "%@ = %.10g", entry.label, entry.value))
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
                let nibbles = (0..<16).reversed().map { String(bytes[s * 16 + $0], radix: 16) }.joined()
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

    /// Dump entire RAM memory with address information.
    /// Shows only non-zero registers as raw nibble pairs using raw indices.
    func debugDumpMemory() {
        guard let m = machine else { return }
        var lines: [String] = ["── Memory (non-zero registers) ──"]

        let totalRegs = Int(m.ramRegisterCount)

        for reg in 0..<totalRegs {
            guard reg >= 0 && reg < totalRegs else { continue }
            let n = Array(m.rawRegister(reg) as Data)
            // Skip if all zeros
            if n.allSatisfy({ $0 == 0 }) { continue }

            let pairs = stride(from: 0, to: 16, by: 2)
                .map { String(format: "%X%X", n[$0], n[$0 + 1]) }
                .joined(separator: " ")
            lines.append(String(format: "R%03d: %@", reg, pairs))
        }
        debugLines.append(contentsOf: lines)
    }

    /// Debug helper: dump step counter encoding from SCOM[0] and surrounding rows.
    /// Used to identify the nibble pattern for the program counter.
    func debugDumpStepCounterAnalysis() {
        guard let m = machine else { return }
        var lines: [String] = ["── Step Counter Analysis (SCOM) ──"]

        let cpu = m.snapshotCPU()

        // Format SCOM[0] with position numbers
        var row0Hex = ""
        withUnsafeBytes(of: cpu.SCOM.0) { bytes in
            row0Hex = (0..<16).map { String(bytes[$0], radix: 16) }.joined()
        }
        lines.append("SCOM[0]  (positions 0–15):")
        lines.append("values:  " + row0Hex)
        lines.append("pos:     0123456789abcdef")

        // Highlight the varying segment (positions 4-6)
        lines.append("note:    ----VARYING---")

        // Extract and show SCOM[15][0] as indicator
        let row15Hex0 = String(Int(cpu.SCOM.15.0), radix: 16)
        lines.append(String(format: "SCOM[15][0]: %@ (expected: 0=PC=0, 9=PC>0)", row15Hex0))

        // Show first 16 hex chars of SCOM[10] and [13] as alternatives
        var row10Hex = ""
        withUnsafeBytes(of: cpu.SCOM.10) { bytes in
            row10Hex = (0..<16).map { String(bytes[$0], radix: 16) }.joined()
        }
        var row13Hex = ""
        withUnsafeBytes(of: cpu.SCOM.13) { bytes in
            row13Hex = (0..<16).map { String(bytes[$0], radix: 16) }.joined()
        }
        lines.append("SCOM[10]: " + row10Hex)
        lines.append("SCOM[13]: " + row13Hex)

        // Known reference data
        lines.append("")
        lines.append("Known mappings (for reference):")
        lines.append("PC=100 → SCOM[0] pos 4-6 = '421'")
        lines.append("PC=200 → SCOM[0] pos 4-6 = '052'")
        lines.append("PC=300 → SCOM[0] pos 4-6 = '473'")
        lines.append("PC=400 → SCOM[0] pos 4-6 = '425'")
        lines.append("Pattern: nibbles don't decode as BCD or simple hex")

        debugAppend(lines)
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
        let maxStepAddr = model.hasLargeMemory ? 959 : 479
        var parsed = parseStateFile(text, maxStepAddr: maxStepAddr, allowHiddenRegisters: model.hasConstantMemory)
        if !parsed.errors.isEmpty { errorMessage = parsed.errors.joined(separator: "\n") }

        if !model.hasLargeMemory {
            let maxStep = 479  // TI-58 and TI-58C: both use up to 480 steps
            if parsed.partitionWasExplicit && parsed.partitionMaxStep > maxStep {
                errorMessage = "State file partition (\(parsed.partitionMaxStep)) exceeds \(model.displayName) maximum (\(maxStep)) — load aborted."
                return
            }
            // Apply default partition when the file has none.
            if !parsed.partitionWasExplicit {
                parsed.partitionMaxStep = 239
            }
        }

        isRunning = false
        // Clear freeze state without restarting the loop
        freezeReason = nil
        frozenROMCache = nil
        frozenRAMCache = nil
        cachedPrSourceFlag = 0
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
        _ = emulQueue.sync { m.stepN(300_000) }

        // Set partition directly in SCOM (SCOM[9][0] and SCOM[13][8..9]).
        // For TI-58, programRegs capped at 60; for TI-58C at 64; rounding above ensures this.
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
            if regNum >= 60 {
                // Hidden registers (H00-H03): write directly to RAM slots 60-63
                m.setRawRegister(regNum, nibbles: Data(nibbles))
            } else {
                // Normal data registers: use the reversed mapping
                m.writeDataRegister(regNum, nibbles: Data(nibbles))
            }
        }

        // Clear out-of-range data registers to prevent corruption from stale state files
        let dataRegCount = 120 - programRegs
        let zeroNibbles = Data(repeating: UInt8(0), count: 16)
        for regNum in dataRegCount..<120 {
            m.setRawRegister(regNum, nibbles: zeroNibbles)
        }

        startEmulationLoop()

        // Persist the loaded state once after all writes complete
        persistConstantMemory()

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

    // ── Binary trace file (TI59_TRACE.bin) ───────────────────────────────────
    // Drain the CPU ring buffer and forward frames to TraceWriter.
    // Called from tick() (main thread, 60 Hz) and from the emulQueue close path.

    private func drainTraceEvents(machine m: TI59MachineWrapper) {
        var lost: UInt = 0
        let framesNS = m.drainCpuFrames(max: 1024, lost: &lost)

        // Write gap record if ring overflow occurred
        if lost > 0 {
            traceWriter.writeLostGap(count: UInt32(lost))
        }

        guard !framesNS.isEmpty else { return }

        for frameVal in framesNS {
            var frame = TICpuFrame()
            frameVal.getValue(&frame)
            traceWriter.write(frame: frame)
        }
    }
}

// ── Live Debug Snapshot ───────────────────────────────────────────────────────
//
// Real-time (60 Hz) view of calculator state: registers, flags, SCOM, program steps.
// Stores decoded/formatted values to minimize work on render thread.

struct LiveDebugSnapshot: Equatable {
    // Data registers — only non-zero values
    struct RegEntry: Equatable {
        var num: Int      // register number (0–99 for R, 0–3 for H)
        var value: Double
        var isHidden: Bool = false  // true for H##, false for R##
    }
    var nonZeroRegs: [RegEntry] = []
    var dataRegCount: Int = 0
    var programRegCount: Int = 0

    // Program steps window — ±5 around current step
    struct StepEntry: Equatable {
        var stepNum: Int       // 000–479
        var keycode: UInt8     // raw 2-digit code
        var mnemonic: String   // e.g. "STO 00", "GTO 27"
        var isCurrent: Bool
    }
    var programWindow: [StepEntry] = []
    var currentStep: Int = -1   // -1 = unknown (SCOM location TBD)

    // When frozen: the last fully executed step and the next step to execute
    var nextStepNum: Int = -1      // Step number of next instruction (from PC when frozen)
    var nextStepKeycode: UInt8 = 0  // Keycode of next instruction
    var nextStepMnemonic: String = ""  // Mnemonic of next instruction

    // HIR registers (stored in SCOM[1..8]; decoded as Double)
    // Each HIR is 16 BCD nibbles: bits 15–3 = mantissa, 2–1 = exponent, 0 = sign
    var hir1: Double = 0
    var hir2: Double = 0
    var hir3: Double = 0
    var hir4: Double = 0
    var hir5: Double = 0
    var hir6: Double = 0
    var hir7: Double = 0
    var hir8: Double = 0

    // T register (SCOM[11]; decoded as Double; stack top / last-X equivalent)
    var tRegister: Double = 0

    // Calculator flags 0–9 (stored in SCOM; bit mapping TBD experimentally)
    var calcFlags: [Bool?] = Array(repeating: nil, count: 10)

    // SCOM[0] fields
    var fixIndicator: String = "0"      // Nibble 15 (FIX = value - 2 mod 10)
    var ioUserFlags: String = "00000"   // Nibbles 14–10 (5 digits)
    var lastKey: String = "00"          // Nibbles 2–1 (2 digits)
    var fA: UInt16 = 0                  // FA register (debug display)
    var fB: UInt16 = 0                  // FB register (debug display)
    var engIndicator: String = ""       // "Eng" if FB bit 3 (of 3rd digit) is set, else empty
    var secondIndicator: String = ""    // "2nd" if FA bit 1 is set, else empty
    var invIndicator: String = ""       // "INV" if FA bit 0 is set, else empty

    // Calculator-level status (from SCOM)
    var angleMode: AngleMode? = nil
    enum AngleMode: Equatable { case deg, rad, grad }

    // SCOM-derived control state
    var prSourceFlag: UInt8 = 0   // Program Source Flag (SCOM[0] nibble 3)
    var pendingOpsCount: Int = 0  // Number of pending operations in hierarchy stack (SCOM 13)

    // Printer SCOM rows 0–3
    var printerSCOM: [String] = []

    // All 16 SCOM rows
    var scomRows: [String] = []

    // Return address stack (from SCOM[14:15]) — 6 levels of subroutine return addresses
    var returnAddress: String = ""
    var returnAddressSourceFlags: [UInt8] = Array(repeating: 0, count: 6)  // PRG SOURCE for each level (L1-L6)
    var returnAddresses: [Int] = Array(repeating: 0, count: 6)  // Decoded address values for each level (L1-L6)

    static let empty = LiveDebugSnapshot()
}

// ── CPU-level debugger snapshot ───────────────────────────────────────────────
//
// Deep CPU state at each instruction: registers A–E, SCOM, Sout, control registers.
// Each instruction entry carries its pre-execution CPU snapshot, enabling back-stepping.

struct CPUDebugSnapshot: Equatable {
    struct Instruction: Equatable {
        var pc: UInt16
        var opcode: UInt16
        var disasm: String
        var frame: TICpuFrame  // CPU frame with all state BEFORE this instruction executed

        static func == (lhs: Instruction, rhs: Instruction) -> Bool {
            // Compare only the instruction data, not the frame (which can't be compared)
            return lhs.pc == rhs.pc && lhs.opcode == rhs.opcode && lhs.disasm == rhs.disasm
        }
    }

    var recentInstructions: [Instruction] = []  // last ~32 instructions with snapshots
    var currentPC: UInt16 = 0
    var isPaused: Bool = false
    var pausedPC: UInt16? = nil

    static let empty = CPUDebugSnapshot()
}

// ── C indicator drop debugger ─────────────────────────────────────────────────
//
// Watches the raw duty-cycle float (snap.calcIndicator) at 60 Hz and emits one
// console line per drop event.  A "drop" starts when duty falls to less than
// 40 % of the previous frame's value (and previous was meaningfully non-zero).
// It ends when duty recovers to at least 60 % of the pre-drop value.
// Each log line shows: time since last drop, pre-drop level, minimum during
// drop, frame count, elapsed ms, and recovery level — enough to see whether
// drops are isolated 1-frame aliasing or sustained 2–3-frame sequences, and
// whether they repeat at a regular (blink-rate) period.

private struct CDropDebugger {
    private var prev:        Float = 0
    private var inDrop:      Bool  = false
    private var dropFrom:    Float = 0
    private var dropMin:     Float = 0
    private var dropFrames:  Int   = 0
    private var dropStart:   Double = 0          // CACurrentMediaTime()
    private var lastDropEnd: Double = 0

    mutating func update(_ duty: Float) {
        let now = CACurrentMediaTime()

        if !inDrop {
            // Start a drop when duty falls below 40 % of the previous value
            // and the previous value was above the noise floor.
            if prev > 0.04 && duty < prev * 0.40 {
                inDrop     = true
                dropFrom   = prev
                dropMin    = duty
                dropFrames = 1
                dropStart  = now
            }
        } else {
            if duty >= dropFrom * 0.60 {
                // Recovered — emit one summary line.
                let elapsed   = (now - dropStart) * 1000
                let sinceStr  = lastDropEnd > 0
                    ? String(format: "+%.0f ms since last", (dropStart - lastDropEnd) * 1000)
                    : "first drop"
                print(String(format: "[C-DBG] DROP  from %.3f  min %.3f  %lld frame(s)  %.0f ms  → %.3f   (%@)",
                             dropFrom, dropMin, Int64(dropFrames), elapsed, duty, sinceStr as NSString))
                lastDropEnd = now
                inDrop      = false
            } else {
                dropMin    = min(dropMin, duty)
                dropFrames += 1
            }
        }
        prev = duty
    }
}
