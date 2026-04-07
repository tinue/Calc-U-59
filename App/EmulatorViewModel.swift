import Foundation
import SwiftUI

enum FreezeReason {
    case manual
    case breakpointPC(Int)     // future: breakpoint on program step
    case keycode(UInt8)        // future: freeze when specific keycode executes next
    case variable(Int, Double) // future: freeze when register matches value
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
                traceWriter.open()
                machine?.traceFlags = [.pc, .regsFull]
            } else {
                emulQueue.async { [weak self] in
                    guard let self, let m = machine else { return }
                    drainTraceEvents(machine: m)
                    traceWriter.close()
                }
                machine?.traceFlags = .flagsNone
            }
        }
    }
    private var cDropDebugger = CDropDebugger()
    private var cZeroFrames: Int = 0   // consecutive frames where fA was zero the entire frame
    private let traceWriter = TraceWriter()

    // ── Debug panel state ────────────────────────────────────────────────────
    var debugEnabled: Bool = false
    var debugLines: [String] = []
    var debugClearID: Int = 0   // incremented on clear to reset Text identity and drop selection

    // ── Live debug panel state (60 Hz real-time) ──────────────────────────────
    var liveDebugEnabled: Bool = false
    var liveDebugSnapshot: LiveDebugSnapshot = .empty
    var freezeReason: FreezeReason? = nil
    var isFrozen: Bool { freezeReason != nil }
    private var lastPrSourceFlag: UInt8 = 0
    private var frozenProgramCounter: Int? = nil

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

        let lines = machine.drainPrinterLines()
        if !lines.isEmpty {
            printerLines.append(contentsOf: lines)
        }
        let codes = machine.drainPrinterCodeLines()
        if !codes.isEmpty {
            printerCodeLines.append(contentsOf: codes)
        }

        // Drain trace events (60 Hz, same cadence as display refresh).
        if traceEnabled {
            let evs = machine.drainTraceEvents(max: 512)
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

        if cIndicatorDebug {
            cDropDebugger.update(snap.calcIndicator)
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
        cardState = .noCard
        machine?.reset()

        // Clear out-of-range registers for the current model
        let programRegs = Int(machine?.partitionProgramRegs ?? 60)
        let dataRegCount = max(0, 120 - programRegs)
        let zeroNibbles = Array(repeating: UInt8(0), count: 16)
        for regNum in dataRegCount..<120 {
            machine?.setRawRegister(regNum, nibbles: Data(zeroNibbles))
        }

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

    func freeze(reason: FreezeReason = .manual) {
        isRunning = false
        freezeReason = reason
        // Capture one fresh snapshot so the panel reflects the exact freeze state
        if liveDebugEnabled, let m = machine {
            liveDebugSnapshot = buildLiveSnapshot(machine: m)
        }
    }

    func unfreeze() {
        freezeReason = nil
        startEmulationLoop()
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

    /// Build a real-time debug snapshot for the live debug view.
    /// Called from tick() at 60 Hz only when liveDebugEnabled.
    private func buildLiveSnapshot(machine m: TI59MachineWrapper) -> LiveDebugSnapshot {
        let programRegs = Int(m.partitionProgramRegs)
        // For TI-58/58C: total 60 registers, for TI-59: total 120 registers
        let isTI58Family = (model == .ti58 || model == .ti58c)
        let dataRegCount = max(0, (isTI58Family ? 60 : 120) - programRegs)
        var snap = LiveDebugSnapshot()
        snap.programRegCount = programRegs
        snap.dataRegCount = dataRegCount

        // Data registers (use optimized batch scan from bridge)
        // For TI-58/58C, register indices are offset by 60 (memory starts at index 60)
        let registerOffset = isTI58Family ? 60 : 0
        let nonZeroIdx = m.nonZeroDataRegisterIndices()
        nonZeroIdx.forEach { regNum in
            let regIdx = Int(regNum)
            let displayRegNum = regIdx - registerOffset
            snap.nonZeroRegs.append(.init(num: displayRegNum, value: m.dataRegister(regIdx)))
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

        // Program steps window
        let steps = Array(m.allProgramSteps() as Data)
        snap.currentStep = decodeProgramCounter(from: cpu)

        // Freeze program counter when prSourceFlag transitions from 0 to non-zero
        if lastPrSourceFlag == 0 && snap.prSourceFlag != 0 {
            frozenProgramCounter = snap.currentStep
        } else if snap.prSourceFlag == 0 {
            frozenProgramCounter = nil
        }
        lastPrSourceFlag = snap.prSourceFlag

        // Use frozen counter if available, otherwise use current
        if let frozen = frozenProgramCounter {
            snap.currentStep = frozen
        }

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

        // SCOM rows (all 16, plus extract rows 0–3 for printer)
        withUnsafeBytes(of: cpu.SCOM) { bytes in
            snap.scomRows = (0..<16).map { row in
                (0..<16).map { String(bytes[row * 16 + $0], radix: 16, uppercase: false) }.joined()
            }
        }
        snap.printerSCOM = Array(snap.scomRows.prefix(4))

        return snap
    }

    /// Decode the program counter from SCOM[0] positions 4-7.
    /// Encoding has three ranges with different formulas:
    ///
    /// Range 1: PC 0–791 (original formula)
    ///   T' = T + 2×H  (H=hundreds, T=tens, U=units)
    ///   pos 4 = ((T'×2) mod 8) + U
    ///   pos 5 = T' if T'<4 else T'+1
    ///   pos 6 = H
    ///   pos 7 = 0
    ///
    /// Range 2: PC 792–799 (special case for T=9)
    ///   pos 4 = U - 2
    ///   pos 5 = 9
    ///   pos 6 = 9
    ///   pos 7 = 0
    ///
    /// Range 3: PC 800–959 (high page, uses pos 7 = 1)
    ///   pos 4-5 encode (T mod 100, U), using original formula
    ///   pos 6 = (H - 8) for 800–899, 1 for 900–959
    ///   pos 7 = 1
    private func decodeProgramCounter(from cpu: TICPUSnapshot) -> Int {
        // PC encoding formula
        let n4 = Int(cpu.SCOM.0.4)
        let n5 = Int(cpu.SCOM.0.5)
        let n6 = Int(cpu.SCOM.0.6)
        let n7 = Int(cpu.SCOM.0.7)

        let pc = n7 * 800 + n6 * 80 + n5 * 8 + n4
        return pc
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
        // For TI-58/58C: total 60 registers, so data count is (60 - programRegs)
        // For TI-59: total 120 registers, so data count is (120 - programRegs)
        let isTI58Family = (model == .ti58 || model == .ti58c)
        let dataRegCount = isTI58Family ? (60 - programRegs) : (120 - programRegs)
        let maxRegNum = dataRegCount - 1
        guard maxRegNum >= 0 else {
            debugLines.append("── Vars: no data registers in current partition ──")
            return
        }
        var lines: [String] = [String(format: "── Vars R00–R%02d ──", maxRegNum)]
        for regNum in 0...maxRegNum {
            // For TI-58/58C: data registers start at end of 60-register memory (index 59)
            // For TI-59: data registers start at end of 120-register memory (index 119)
            let maxIndex = isTI58Family ? 59 : 119
            let raw = m.rawRegister(maxIndex - regNum) as Data
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

    /// Dump entire RAM memory with address information.
    /// Shows only non-zero registers as raw nibble pairs.
    /// Useful for tracking where saved values end up in memory.
    func debugDumpMemory() {
        guard let m = machine else { return }
        var lines: [String] = ["── Memory (non-zero registers) ──"]

        for reg in 0..<120 {
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
        _ = emulQueue.sync { m.stepN(300_000) }

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

        // Clear out-of-range data registers to prevent corruption from stale state files
        let dataRegCount = 120 - programRegs
        let zeroNibbles = Data(repeating: UInt8(0), count: 16)
        for regNum in dataRegCount..<120 {
            m.setRawRegister(regNum, nibbles: zeroNibbles)
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

    // ── Binary trace file (TI59_TRACE.bin) ───────────────────────────────────
    // Drain the CPU ring buffer and forward each event+snapshot to TraceWriter.
    // Called from tick() (main thread, 60 Hz) and from the emulQueue close path.

    private func drainTraceEvents(machine m: TI59MachineWrapper) {
        var snapsOut: NSArray? = nil
        let eventsNS = m.drainTraceEvents(max: 2000, snapshots: &snapsOut)
        guard !eventsNS.isEmpty else { return }
        let snapsNS = (snapsOut as? [NSValue]) ?? []

        for (i, ev) in eventsNS.enumerated() {
            var e = TITraceEvent()
            ev.getValue(&e)
            var snap = TICPUSnapshot()
            if i < snapsNS.count { snapsNS[i].getValue(&snap) }
            traceWriter.write(event: e, snapshot: snap)
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
        var num: Int      // user-visible register number (R00–R99)
        var value: Double
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

    // Calculator-level status (from SCOM)
    var isINV: Bool? = nil
    var is2nd: Bool? = nil
    var angleMode: AngleMode? = nil
    enum AngleMode: Equatable { case deg, rad, grad }

    // SCOM-derived control state
    var prSourceFlag: UInt8 = 0   // Program Source Flag (SCOM[0] nibble 3)
    var pendingOpsCount: Int = 0  // Number of pending operations in hierarchy stack (SCOM 13)

    // Printer SCOM rows 0–3
    var printerSCOM: [String] = []

    // All 16 SCOM rows
    var scomRows: [String] = []

    static let empty = LiveDebugSnapshot()
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
