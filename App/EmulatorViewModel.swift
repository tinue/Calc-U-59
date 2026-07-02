import Foundation
import os
import SwiftUI

enum FreezeReason {
    case manual
    case breakpointPC(Int)     // future: breakpoint on program step
    case keycode(UInt8)        // future: freeze when specific keycode executes next
    case variable(Int, Double) // future: freeze when register matches value
}

/// Which debug panel owns the current freeze.
/// RESUME and STEP are only enabled in the owning panel; the other panel's buttons are
/// disabled while frozen to prevent cross-panel confusion (e.g. CALCULATOR STEP while
/// frozen in CPU would silently resume until the next keycode boundary).
enum FreezePanel { case cpu, calculator }

/// Selected tab in the debug pane. Stored on EmulatorViewModel so the
/// selection survives navigation on iPhone (where DebugView is recreated).
enum DebugTab { case live, cpu, log }

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

enum ProgramSource: UInt8 {
    case userProgram = 0
    case solidState = 1
    /// Transitional state after a RTN whose return level points back into the
    /// solid-state module: SCOM[0] nibbles 4–7 hold the saved CROM return
    /// address (plain BCD, not a step number) and the firmware reloads the
    /// CROM PC from it on the next keycode dispatch before setting the flag
    /// back to 1. Lasts exactly one single-step.
    case solidStateReturn = 2
    case fastMode = 4
    case rom = 8
}

@Observable
class EmulatorViewModel {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Calc-U-59", category: "EmulatorViewModel")

    var displayDigits: [UInt8]  = Array(repeating: 0, count: 12)
    var displayCtrl:   [UInt8]  = Array(repeating: 0, count: 12)
    var displaySuppressedMask: UInt16 = 0
    var dpPos:          UInt8   = 0
    var dpAfterglowMask: UInt16 = 0  // Bit (pos-2) set for each dp position 2..13 with active afterglow
    var calcIndicatorOpacity: Double = 0.0
    var model: MachineModel     = .ti59
    var errorMessage: String?

    // ── Display interaction state ────────────────────────────────────────────────
    var isDisplayPressed: Bool = false
    var isFullSpeedMode: Bool = false  // true when user is pressing display; emulation runs unrestricted
    var isKeystrokesPlaying: Bool = false

    // ── Printer state ────────────────────────────────────────────────────────
    var printerLines: [String] = []
    var printerCodeLines: [Data] = []  // parallel to printerLines; 20 raw codes per line
    var printerClearID: Int = 0   // incremented on cut to reset Text identity and drop selection
    var printerTrace: Bool = false
    var printerConnected: Bool = true

    // ── C indicator trace writer ──────────────────────────────────────────────
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

                guard machine != nil else { return }

                // b) Tell C-code to start tracing
                updateDebugTraceFlags()

                // c) Start draining via tick() calls (happens automatically at 60 Hz)
            } else {
                // TRACE DISABLED
                guard let m = machine else { return }

                // a) Stop generating events (unless another consumer still needs them)
                updateDebugTraceFlags()

                // b) Drain remaining buffer on main thread immediately
                drainTraceEvents(machine: m)

                // c) Close file
                traceWriter.close()
            }
        }
    }
    private var cZeroFrames: Int = 0   // consecutive frames where fA was zero the entire frame
    private var traceWriter: TraceWriter!  // initialized in init, updated when model changes
    var isTraceAvailable: Bool { traceWriter?.isAvailable ?? true }  // false if trace location (e.g., iCloud) unavailable

    private func configureTraceWriter() {
        traceWriter.onSizeLimitReached = { [weak self] in
            // Called on the main thread from inside drainTraceEvents().
            // Defer to avoid reentrance in the drain loop.
            DispatchQueue.main.async { self?.cIndicatorDebug = false }
        }
    }

    // ── Debug panel state ────────────────────────────────────────────────────
    var debugTab: DebugTab = .live   // persists tab selection across iPhone navigation
    var debugLevel: DebugLevel = .off
    var debugEnabled: Bool { debugLevel != .off }   // convenience for existing callers
    private static let ringBufCap = 2_000
    private static let displayLinesPerPage = 40   // approx visible lines in the log pane
    private static let displayPageCap = 10        // max pages copied to the display panel
    @ObservationIgnored private var ringBuf: [String] = Array(repeating: "", count: ringBufCap)
    @ObservationIgnored private var ringHead: Int = 0   // monotonically increasing write position
    @ObservationIgnored private var debugLastDisplayHead: Int = 0
    var debugClearID: Int = 0              // incremented on clear to reset Text identity
    var debugDisplayText: String = ""      // ring buffer tail, refreshed at 1 Hz
    var asmFileName: String = "No file selected"
    var asmWordCount: Int = 0
    var asmStatusMessage: String = "Load a hex opcode file and press Run."
    private var asmOverlayWords: [UInt16] = []
    var canRunASM: Bool { !asmOverlayWords.isEmpty }
    var asmOverlayActive: Bool = false

    // ── Live debug panel state (60 Hz real-time) ──────────────────────────────
    // Both flags track panel visibility (set by LiveDebugView / CPUInspectorView
    // onAppear/onDisappear).  While false, tick() skips the snapshot builds and
    // the core runs with tracing fully disabled — its zero-overhead fast path.
    var liveDebugEnabled: Bool = false {
        didSet {
            // When the panel becomes visible while already frozen, the freeze() path
            // skipped building the snapshot (liveDebugEnabled was false at that time).
            // Rebuild now so the correct frozen step is shown immediately on appear.
            guard liveDebugEnabled, !oldValue, isFrozen, let m = machine else { return }
            liveDebugSnapshot = buildLiveSnapshot(machine: m)
        }
    }
    var cpuDebugEnabled: Bool = false {
        didSet {
            guard cpuDebugEnabled != oldValue else { return }
            if cpuDebugEnabled && !isFrozen {
                // The heatmap shows activity since the panel became visible:
                // tracing is off while hidden, so reset and skip any ring backlog.
                // When frozen the heatmap is static — don't wipe it on re-entry.
                resetHeatmapBaseline()
            }
            updateDebugTraceFlags()
        }
    }
    var liveDebugSnapshot: LiveDebugSnapshot = .empty
    var freezeReason: FreezeReason? = nil {
        didSet { updateDebugTraceFlags() }
    }
    var isFrozen: Bool { freezeReason != nil }
    var freezeOwner: FreezePanel? = nil  // set on freeze entry, cleared on unfreeze
    var pendingFreezeOnPCChange: Bool = false {  // Freeze as soon as PC changes (first instruction)
        didSet {
            guard pendingFreezeOnPCChange != oldValue else { return }
            updateDebugTraceFlags()
        }
    }
    private var lastObservedPC: UInt16 = 0     // Track PC to detect changes
    private var lastObservedLibPC: UInt16 = 0xFFFF  // Track library exec PC (solid-state programs don't move the SCOM PC)

    // CPU-tab "Freeze on Start": fires when the keyboard scan loop exits (key press or reset).
    // Distinct from pendingFreezeOnPCChange (CALCULATOR tab: fires on any PC change).
    var pendingCPUScanLoopFreeze: Bool = false {
        didSet {
            guard pendingCPUScanLoopFreeze != oldValue else { return }
            updateDebugTraceFlags()
        }
    }
    private var _cpuFreezeSeenLoop = false   // have we entered the scan loop since arming?
    private var _cpuFreezeArmPC: UInt16 = 0xFFFF  // PC at arm time (guards against immediate 0000 re-trigger)

    // Full program listing — always kept current (not just when frozen).
    // Updated at 60 Hz by buildLiveSnapshot when running, and after each STEP/freeze-entry when frozen.
    var programListing: [LiveDebugSnapshot.StepEntry] = []
    var programListingSourceFlag: UInt8 = 0   // Prg Source flag the listing was built for

    // ── Solid-state module image (for the live PROGRAM STEPS view) ────────────
    // Swift-side copy of the module bytes plus the per-program byte ranges
    // parsed from the module header. Program n (1-based) = moduleProgramRanges[n-1].
    private var moduleKeycodes: [UInt8] = []
    private var moduleProgramRanges: [Range<Int>] = []
    private var romKeycodesCache: [UInt8] = []  // 384 main-ROM keycodes, constant per machine
    private var lastLibProgramMismatch: Int = .min  // throttles SCOM[9] cross-check logging

    // ── Live CPU view state (60 Hz real-time, runs while emulating) ────────────
    var cpuDebugSnapshot: CPUDebugSnapshot = .empty
    private var cpuFrameWindow: [TICpuFrame] = []  // rolling window of recent instructions

    // ── ROM Heatmap (5 120 code addresses 0x0000–0x13FF) ─────────────────────
    // Observable published at ~10 Hz to avoid flooding SwiftUI render pipeline.
    var romHitCount: [UInt32] = Array(repeating: 0, count: 0x1400)
    private var romHitCountBuffer: [UInt32] = Array(repeating: 0, count: 0x1400)
    private var romHeatmapLastSeqno: UInt32 = 0
    private var romHeatmapDirty = false
    private var heatmapTickCounter: Int = 0

    func clearRomHeatmap() {
        romHitCountBuffer = Array(repeating: 0, count: 0x1400)
        romHitCount       = Array(repeating: 0, count: 0x1400)
        romHeatmapLastSeqno = 0
        romHeatmapDirty = false
        heatmapTickCounter = 0
    }

    /// Clear the heatmap and skip whatever is still in the trace ring, so counting
    /// starts at "now" rather than replaying up to 1024 stale frames from the last
    /// time tracing was active.
    private func resetHeatmapBaseline() {
        clearRomHeatmap()
        if let m = machine, let newest = m.readCpuFrames(max: 1).last {
            var f = TICpuFrame()
            newest.getValue(&f)
            romHeatmapLastSeqno = f.seqno
        }
    }

    /// Single owner of the machine's trace flags.  Recomputed whenever a consumer
    /// changes state: CPU debug panel visibility, freeze mode (incl. armed
    /// freeze-on-start), the binary trace toggle, or the breakpoint set.
    /// With no consumer active the core runs with TRACE_NONE — its fast path.
    private func updateDebugTraceFlags() {
        guard let m = machine else { return }
        var flags: TITraceFlags = []
        if cpuDebugEnabled || isFrozen || cIndicatorDebug || pendingFreezeOnPCChange || pendingCPUScanLoopFreeze {
            flags.insert([.pc, .regsFull])
        }
        if !breakpoints.isEmpty {
            flags.insert(.breakpoints)
        }
        if m.traceFlags != flags { m.traceFlags = flags }
    }

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

    // ── Cue card state ───────────────────────────────────────────────────────
    var cueCardContent: CueCardContent? = nil
    private var userCueCardContent: CueCardContent? = nil  // set by preset/card/file load
    private var moduleCueCards: [Int: CueCardContent] = [:]  // program number → card
    private var moduleMetadata: ModuleMetadata = ModuleMetadata()  // module-level metadata
    private var activeProgramNumber: Int = 0  // 0 = none, 1+ = active program

    // ── Solid-state module state ─────────────────────────────────────────────
    var selectedModuleID: String = AppSettings.resolvedSolidStateModuleID() {
        didSet {
            UserDefaults.standard.set(self.selectedModuleID, forKey: SettingsKey.solidStateModuleID)
        }
    }

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
    private var persistPending = false
    private var persistDebounceTimer: Timer?
    private var programCheckTimer: Timer?
    private var debugDisplayTimer: Timer?

    init() {
        // Initialize traceWriter with default model
        traceWriter = TraceWriter(model: model)
        configureTraceWriter()
        // Check trace availability at startup (for iOS/iPadOS iCloud detection, etc.)
        traceWriter.checkAvailability()
        Task { await self.start(model: AppSettings.resolvedStartupModel()) }
    }

    /// Resolve which cue card to display based on current program number.
    private func resolvedCueCard() -> CueCardContent? {
        if activeProgramNumber > 0 {
            // Try to find the specific program card
            if let card = moduleCueCards[activeProgramNumber] {
                return card
            }
            // Fallback: if card not found but a program is active, show default with module metadata
            if !moduleMetadata.title.isEmpty || !moduleMetadata.id.isEmpty {
                return CueCardContent(
                    template: .solidState,
                    title: moduleMetadata.title,
                    id: moduleMetadata.id,
                    labels: Array(repeating: "", count: 10)
                )
            }
            return nil
        }
        return userCueCardContent  // nil when no user card loaded → blank
    }

    func start(model: MachineModel) async {
        persistConstantMemory()  // save TI-58C RAM before switching away
        stop()
        await drainEmulQueue()   // ensure old loop has exited before starting the new one
        self.model = model
        // A fresh machine is created below; the printer's TRACE latch is released
        // on a model change (the new core instance starts with it off).
        printerTrace = false
        userCueCardContent = nil
        activeProgramNumber = 0
        cueCardContent = nil  // clear cuecard when switching models
        traceWriter = TraceWriter(model: model)
        configureTraceWriter()  // reinitialize with new model for correct trace filename
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

            // Load solid-state library module
            if let libData = ROMLoader.loadModuleLibrary(moduleID: self.selectedModuleID) {
                wrapper.loadLibrary(libData)
                cacheModuleImage(libData)
            } else {
                Self.logger.error("Solid-state module library was not loaded; continuing without library data")
                cacheModuleImage(nil)
            }
            let (cards, metadata) = ROMLoader.loadModuleCardsAndMetadata(moduleID: self.selectedModuleID)
            moduleCueCards = cards
            moduleMetadata = metadata

            if let constData = try? ROMLoader.loadConstants(model: model) {
                wrapper.loadConstants(constData)
            }

            if model.hasConstantMemory {
                // Run ROM startup once, then restore RAM. This matches the preset-load
                // path and avoids startup code mutating freshly restored registers.
                _ = wrapper.stepN(300_000)
                if let saved = loadConstantMemory() {
                    wrapper.deserialiseRAM(saved)
                }
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
            updateDebugTraceFlags()   // new wrapper starts with TRACE_NONE; re-apply consumer state
            // New machine restarts frame seqnos at 0; without a reset the
            // `seqno > romHeatmapLastSeqno` filter would reject all new frames.
            resetHeatmapBaseline()
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
            // = 14,218.75 instructions/sec in active mode (TI-59).
            // TI-58/58C: 384 kHz ÷ 2 ÷ 16 = 12,000 instructions/sec.
            // Idle mode runs at ÷4 (step() returns 4 instead of 1, except TI-58C constant speed),
            // so the loop naturally slows down when the calculator is waiting for a keypress.
            let targetHz: Double = model == .ti59 ? 14218.75 : 12000.0
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

                    // Per-step scan loop exit check (must be inside the step loop for
                    // exact PC precision — a post-batch check lands hundreds of
                    // instructions late after reset clears the loop in one burst).
                    if self.pendingCPUScanLoopFreeze, let range = self.cpuScanLoopRange {
                        let pc = m.currentPC
                        if range.contains(pc) {
                            self._cpuFreezeSeenLoop = true
                        } else if self._cpuFreezeSeenLoop || (pc == 0x0000 && self._cpuFreezeArmPC != 0x0000) {
                            self.freezeOwner = .cpu
                            self.isRunning = false
                            self.freezeReason = .manual
                            self.pendingCPUScanLoopFreeze = false
                            self._cpuFreezeSeenLoop = false
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
                }
                // Subtract rather than reset to zero: carry the overshoot into
                // the next batch so long-term average speed stays exact.
                cyclesDone -= targetBatchCycles

                // Check if pending freeze on PC change should activate
                if self.pendingFreezeOnPCChange {
                    // Get the user-visible PC (decoded from SCOM), not the raw CPU PC
                    let cpu = m.snapshotCPU()
                    let currentPC = self.decodeProgramCounter(from: cpu)

                    // Check if either PC has changed from when we armed the
                    // freeze. Solid-state programs never move the SCOM PC, so
                    // the library exec latch is watched as a second trigger.
                    if UInt16(currentPC) != self.lastObservedPC || m.libExecPC != self.lastObservedLibPC {
                        // PC has changed — freeze now.  Set freezeReason before
                        // clearing the armed flag so updateDebugTraceFlags()
                        // (fired by both didSets) keeps tracing enabled throughout.
                        self.freezeOwner = .calculator
                        self.isRunning = false
                        self.freezeReason = .manual
                        self.pendingFreezeOnPCChange = false
                        DispatchQueue.main.async { [weak self] in
                            guard let self else { return }
                            m.beginNextStep()
                            self.liveDebugSnapshot = self.buildLiveSnapshot(machine: m)
                            self.captureInspectorSnapshot(machine: m)
                        }
                        return
                    }
                }

                // Skip timing throttle when in full-speed mode (user pressing display)
                if !self.isFullSpeedMode {
                    let end = DispatchTime.now()
                    let elapsed = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
                    let remaining = batchMs - elapsed
                    if remaining > 0 {
                        Thread.sleep(forTimeInterval: remaining)
                    }
                }

                // Mark TI-58C state for persist (debounced, non-blocking)
                if self.model.hasConstantMemory {
                    self.persistPending = true
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

        // Separate 2 Hz timer for program number detection to avoid UI blocking.
        programCheckTimer?.invalidate()
        let progTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkProgramNumber()
        }
        RunLoop.main.add(progTimer, forMode: .common)
        programCheckTimer = progTimer

        // 1 Hz timer: copies ring buffer tail into the display panel.
        // Rate and copy size adapt to logging speed (see refreshDebugDisplay()).
        debugDisplayTimer?.invalidate()
        let dbgTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshDebugDisplay()
        }
        RunLoop.main.add(dbgTimer, forMode: .common)
        debugDisplayTimer = dbgTimer
    }

    private func checkProgramNumber() {
        guard let machine else { return }
        let cpuFrame = machine.snapshotCPU()
        let detectedProgram = Int(cpuFrame.SCOM.9.4) * 10 + Int(cpuFrame.SCOM.9.3)
        if detectedProgram != activeProgramNumber {
            activeProgramNumber = detectedProgram
            cueCardContent = resolvedCueCard()
        }
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

        // Drain C-core debug messages into the ring buffer (O(1) per message, no trimming).
        if debugLevel != .off {
            let dbgMsgs = machine.drainDebugMessages()
            for msg in dbgMsgs {
                guard msg.count >= 2 else { continue }
                let msgLevel: DebugLevel = (msg.first! == "I") ? .info : .debug
                guard debugLevel >= msgLevel else { continue }
                ringWrite(String(msg.dropFirst(2)))
            }
        }

        // Debounce TI-58C persist: schedule write if pending and timer not already running
        if persistPending && persistDebounceTimer == nil {
            persistDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                self?.performPersistWrite()
                self?.persistDebounceTimer = nil
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
        let displayOn = cpuFrame.displayOn != 0               // One or more digits/dots currently visible
        let shouldFreeze = displayOn && !isIdle               // Afterglow with RUN mode


        // Guard each assignment: @Observable only notifies SwiftUI when a property
        // is actually written, but the write itself counts as a change even if the
        // value is identical.  The guards prevent 60 Hz spurious re-renders when
        // the display is static (e.g. calculator idle showing a number).
        if !shouldFreeze {
            if displayDigits    != d               { displayDigits    = d }
            if displayCtrl      != c               { displayCtrl      = c }
            if displaySuppressedMask != snap.suppressedMask { displaySuppressedMask = snap.suppressedMask }
            if dpPos            != snap.dpPos      { dpPos            = snap.dpPos }
            if dpAfterglowMask  != snap.dpAfterglowMask { dpAfterglowMask = snap.dpAfterglowMask }
        }
        // Live debug snapshot — sampled at 60 Hz when the panel is open (unless frozen).
        if liveDebugEnabled && !isFrozen {
            let s = buildLiveSnapshot(machine: machine)
            if s != liveDebugSnapshot { liveDebugSnapshot = s }
        }

        // CPU debug snapshot — sampled at 60 Hz when panel is enabled or frozen.
        if cpuDebugEnabled || isFrozen {
            let s = buildCPUDebugSnapshot(machine: machine)
            if s != cpuDebugSnapshot { cpuDebugSnapshot = s }
        }

        if cIndicatorDebug {
            // Drain trace events directly on main thread (tick() is already on main).
            // The emulation loop runs on the serial emulQueue, so async dispatches would
            // never execute until the loop exits — we drain here at 60 Hz instead.
            drainTraceEvents(machine: machine)
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

    private func invalidateAllTimers() {
        displayTimer?.invalidate()
        displayTimer = nil
        programCheckTimer?.invalidate()
        programCheckTimer = nil
        debugDisplayTimer?.invalidate()
        debugDisplayTimer = nil
    }

    func stop() {
        isRunning = false
        invalidateAllTimers()
    }

    /// Suspend emulation when the app enters the background.
    /// Stops the CPU loop and display timer to prevent battery drain.
    /// Does not destroy machine state — resumeFromBackground() will restart both.
    func suspendForBackground() {
        persistConstantMemory()
        suspendedByLifecycle = isRunning
        isRunning = false
        invalidateAllTimers()
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
        // Attaching or detaching the printer physically releases the TRACE latch.
        printerTrace = false
        machine?.setPrinterConnected(connected)
    }
    func cutPaper() { printerLines = []; printerCodeLines = []; printerClearID &+= 1 }

    // MARK: - Solid-state module selection

    /// Load ROM and cue cards for the specified module without resetting.
    /// Used by both selectModule and loadStateFile.
    private func applyModule(id: String) {
        guard let m = machine else {
            Self.logger.error("Cannot apply module \(id, privacy: .public): machine is not initialized")
            return
        }
        if let libData = ROMLoader.loadModuleLibrary(moduleID: id) {
            m.loadLibrary(libData)
            cacheModuleImage(libData)
        } else {
            Self.logger.error("Failed to load module ROM: \(id, privacy: .public)")
            cacheModuleImage(nil)
        }
        let (cards, meta) = ROMLoader.loadModuleCardsAndMetadata(moduleID: id)
        moduleCueCards = cards
        moduleMetadata = meta
        selectedModuleID = id
        UserDefaults.standard.set(id, forKey: SettingsKey.solidStateModuleID)
    }

    /// Change the solid-state module and perform a soft reset (preserves RAM).
    func selectModule(id: String) {
        applyModule(id: id)
        resetMachine()
    }

    // MARK: - Reset

    func resetMachine() {
        unfreeze()  // exit freeze mode when resetting
        asmOverlayActive = false
        cardState = .noCard
        userCueCardContent = nil
        activeProgramNumber = 0
        cueCardContent = resolvedCueCard()
        // The printer's TRACE button is a physical hardware latch — a calculator
        // reset does not release it.  The core preserves it across reset(); it is
        // released only on printer attach/detach or model change.
        machine?.reset()
        resetHeatmapBaseline()

        // TI-58C: restore persisted memory after reset
        if model.hasConstantMemory {
            if let saved = loadConstantMemory() {
                machine?.deserialiseRAM(saved)
            }
            ringWrite("Calculator Reset")
            return
        }

        // Clear out-of-range registers for the current model
        let programRegs  = Int(machine?.partitionProgramRegs ?? 60)
        let totalRegs    = Int(machine?.ramRegisterCount ?? (model.hasLargeMemory ? 120 : model.hasConstantMemory ? 64 : 60))
        let dataRegCount = max(0, totalRegs - programRegs)
        let zeroNibbles  = Array(repeating: UInt8(0), count: 16)
        for regNum in dataRegCount..<totalRegs {
            machine?.setRawRegister(regNum, nibbles: Data(zeroNibbles))
        }

        ringWrite("Calculator Reset")
    }

    /// Clean reset (all models): zero all RAM, then reset.
    /// For TI-58C, writes the zeroed state immediately to the save file.
    func cleanResetMachine() {
        unfreeze()  // exit freeze mode when resetting
        asmOverlayActive = false
        machine?.deserialiseRAM(Data(repeating: 0, count: 120 * 16))
        cardState = .noCard
        userCueCardContent = nil
        activeProgramNumber = 0
        cueCardContent = resolvedCueCard()
        // TRACE is a physical latch — preserved across reset by the core (see resetMachine).
        machine?.reset()
        resetHeatmapBaseline()
        // Write zeroed state for TI-58C immediately
        persistConstantMemory()
        ringWrite("Clean Reset — all registers cleared")
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
        if let text = String(data: raw, encoding: .utf8), text.hasPrefix("Calc-U-59 Card ") {
            guard let result = parseCardFile(text) else {
                errorMessage = "Card file \"\(url.lastPathComponent)\" could not be parsed."
                return
            }
            userCueCardContent = result.cueCard
            cueCardContent = resolvedCueCard()
            cardFileName = url.lastPathComponent
            pendingSaveURL = url
            beginSwipe(data: result.data)
            return
        }
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
        let text = encodeCardFileToText(data, cueCard: cueCardContent)
        guard let fileData = text.data(using: .utf8) else {
            errorMessage = "Card save failed: UTF-8 encoding error."
            return
        }
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
        let text = encodeConstantMemoryToText(data, cueCard: userCueCardContent)
        let url = Self.constantMemoryURL
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func performPersistWrite() {
        persistPending = false
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.persistConstantMemory()
        }
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

        // Decode text format; invalid files are treated as load failure.
        if let text = String(data: rawData, encoding: .utf8) {
            let (data, cueCard) = decodeConstantMemoryFromText(text)
            if let data = data {
                self.userCueCardContent = cueCard
                self.cueCardContent = resolvedCueCard()
                return data
            }
        }

        // Silently fail; caller resets RAM to zeros.
        return nil
    }

    /// Encode card data (246-byte bank) as human-readable text .U59 format.
    private func encodeCardFileToText(_ data: Data, cueCard: CueCardContent?) -> String {
        var lines: [String] = []
        lines.append("Calc-U-59 Card 1.0")

        if let card = cueCard {
            lines.append("")
            lines.append("CUECARD:")
            lines.append(contentsOf: card.encodeToLines(writeTemplate: .magnetCard))
        }

        let partition  = data.count > 0 ? data[0] : 0
        let dataType   = data.count > 1 ? data[1] : 0x11
        let pageByte   = data.count > 2 ? data[2] : 0x10
        let protection = data.count > 3 ? data[3] : 0x00
        let checksum   = data.count > 244 ? data[244] : 0x00
        let bankNum    = Int((pageByte & 0x0F) / 3) + 1
        let dataTypeStr   = dataType == 0x11 ? "program" : "data"
        let protectionStr = protection == 0x10 ? "yes" : "no"

        lines.append("")
        lines.append("HEADER:")
        lines.append(String(format: "Partition: %02X", partition))
        lines.append("DataType: \(dataTypeStr)")
        lines.append("Bank: \(bankNum)")
        lines.append("Protection: \(protectionStr)")
        lines.append(String(format: "Checksum: %02X", checksum))

        lines.append("")
        lines.append("DATA:")
        // 30 registers per bank, 8 bytes (16 nibbles) each. Same format as ti58c.mem.
        // Bank 0 → R000-R029, Bank 1 → R030-R059, Bank 2 → R060-R089, Bank 3 → R090-R119.
        // Swap nibbles within each byte, then reverse byte order.
        // data is guaranteed 246 bytes; bank bytes 4–243 always in bounds.
        let startReg = (bankNum - 1) * 30
        for row in 0..<30 {
            let bankOffset = 4 + row * 8
            let raw: [UInt8] = (0..<8).map { data[bankOffset + $0] }
            let nibbles: [UInt8] = raw.flatMap { b in [b >> 4, b & 0x0F] }
            // Card files reverse the bytes compared to ti58c.mem format
            let encoded = encodeRegisterLine(nibbles)
            let bytes = Array(encoded.reversed())
            let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            lines.append(String(format: "R%03d: %@", startReg + row, hex as NSString))
        }

        return lines.joined(separator: "\n")
    }

    private func parseHexBytes(_ hexString: String, count: Int) -> [UInt8]? {
        let tokens = hexString.components(separatedBy: " ").filter { !$0.isEmpty }
        guard tokens.count == count else { return nil }
        let bytes = tokens.compactMap { UInt8($0, radix: 16) }
        return bytes.count == count ? bytes : nil
    }

    /// Encode RAM data (120 regs × 16 nibbles) as human-readable text.
    /// Only includes non-zero registers. Optionally includes CUECARD section if provided.
    private func encodeConstantMemoryToText(_ data: Data, cueCard: CueCardContent? = nil) -> String {
        var lines: [String] = []

        // Include CUECARD section if present
        if let card = cueCard {
            lines.append("CUECARD:")
            lines.append(contentsOf: card.encodeToLines(writeTemplate: .cueCard))
            lines.append("")
        }

        lines.append("── Registers (raw values) ──")

        for regNum in 0..<120 {
            let offset = regNum * 16
            guard offset + 16 <= data.count else { break }

            let nibbles = Array(data.subdata(in: offset..<(offset + 16)))

            // Check if register is all zeros
            if nibbles.allSatisfy({ $0 == 0 }) { continue }

            let bytes = encodeRegisterLine(nibbles)
            let hexBytes = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            lines.append(String(format: "R%03d: %@", regNum, hexBytes as NSString))
        }

        return lines.joined(separator: "\n")
    }

    /// Decode human-readable text format back to RAM data (120 regs × 16 nibbles) and optional CUECARD.
    /// Format: optional CUECARD section, then non-zero registers with 8 hex byte pairs each (reversed order).
    /// Returns (Data, CueCardContent?) tuple; returns (nil, nil) on parse error.
    private func decodeConstantMemoryFromText(_ text: String) -> (Data?, CueCardContent?) {
        var resultBytes = [UInt8](repeating: 0, count: 120 * 16)
        var cueCard: CueCardContent?
        var inCueCardSection = false

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            if trimmed.isEmpty { continue }

            // Check for section headers
            if trimmed.hasPrefix("CUECARD:") {
                inCueCardSection = true
                cueCard = CueCardContent()
                continue
            }

            if trimmed.hasPrefix("──") {
                inCueCardSection = false
                continue
            }

            // Parse CUECARD section
            if inCueCardSection {
                cueCard?.parseLine(trimmed)
                continue
            }

            // Parse registers
            if trimmed.hasPrefix("R") {
                let parts = trimmed.components(separatedBy: ":")
                guard parts.count == 2 else { return (nil, nil) }

                let regStr = String(parts[0].dropFirst())
                guard let regNum = Int(regStr), regNum >= 0, regNum < 120 else { return (nil, nil) }

                // Parse 8 hex byte pairs
                let hexPart = parts[1].trimmingCharacters(in: .whitespaces)
                guard let fileBytes = parseHexBytes(hexPart, count: 8) else { return (nil, nil) }

                let nibbles = decodeRegisterLine(fileBytes)
                let offset = regNum * 16
                for (i, nibble) in nibbles.enumerated() {
                    guard offset + i < resultBytes.count else { break }
                    resultBytes[offset + i] = nibble
                }
            }
        }

        return (Data(resultBytes), cueCard)
    }



    // MARK: - Trace / debug

    func addBreakpoint(_ pc: UInt16) {
        breakpoints.insert(pc)
        machine?.addBreakpoint(pc)
        updateDebugTraceFlags()   // arms TRACE_BREAKPOINTS
    }

    func removeBreakpoint(_ pc: UInt16) {
        breakpoints.remove(pc)
        machine?.removeBreakpoint(pc)
        updateDebugTraceFlags()
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
        // Track the decoded PC (from SCOM), not the raw CPU PC — plus the
        // library exec latch, which is the PC for solid-state programs
        // Mutex: disarm CPU scan-loop freeze if active
        disarmCPUScanLoopFreeze()
        pendingFreezeOnPCChange = true
        guard let m = machine else { return }
        let cpu = m.snapshotCPU()
        lastObservedPC = UInt16(decodeProgramCounter(from: cpu))
        lastObservedLibPC = m.libExecPC
    }

    /// Arm the CPU-tab "Freeze on Start": fires when the keyboard scan loop exits.
    /// Scan loop ranges: TI-59/58 = 0x063C–0x0658, TI-58C = 0x063D–0x0A2E.
    /// Trigger conditions: (a) PC was inside loop and exits (key press or reset while idle),
    /// or (b) PC jumps to 0x0000 while outside the loop (reset during program execution),
    /// or (c) an ASM overlay run succeeds (runASMOverlay checks this flag on success).
    func freezeOnScanLoopExit() {
        // Mutex: disarm CALCULATOR any-PC-change freeze if active
        pendingFreezeOnPCChange = false
        _cpuFreezeSeenLoop = false
        _cpuFreezeArmPC = machine?.currentPC ?? 0xFFFF
        pendingCPUScanLoopFreeze = true
    }

    func disarmCPUScanLoopFreeze() {
        _cpuFreezeSeenLoop = false
        pendingCPUScanLoopFreeze = false
    }

    private var cpuScanLoopRange: ClosedRange<UInt16>? {
        switch model {
        case .ti59, .ti58: return 0x063C...0x0658
        case .ti58c:       return 0x063D...0x0A2E
        }
    }

    /// Freeze with an explicit panel owner (called by the FREEZE button in each panel).
    func freeze(from panel: FreezePanel) {
        freezeOwner = panel
        freeze()
    }

    func freeze(reason: FreezeReason = .manual, waitForKeycode: Bool = true) {
        isRunning = false
        freezeReason = reason
        asmOverlayActive = false
        pendingFreezeOnPCChange = false   // Cancel any pending CALCULATOR freeze
        pendingCPUScanLoopFreeze = false  // Cancel any pending CPU scan-loop freeze
        _cpuFreezeSeenLoop = false
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
                // buildLiveSnapshot refreshes programListing as a side effect (always, not just when liveDebugEnabled)
                self.liveDebugSnapshot = self.buildLiveSnapshot(machine: m)
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
                let prSourceFlag = UInt8(cpu.SCOM.0.3)
                let isLibSource = prSourceFlag == ProgramSource.solidState.rawValue
                let libInfo = isLibSource ? self.libraryProgramStep(machine: m) : nil
                let currentStep = isLibSource ? (libInfo?.step ?? -1)
                                              : self.decodeProgramCounter(from: cpu)

                // Update always-live program listing.
                // Prg Source 2 (solidStateReturn): SCOM[0] holds a raw CROM return address —
                // keep the previous listing and advance the highlight onto the just-executed RTN.
                // All other sources: rebuild from current machine state.
                if prSourceFlag == ProgramSource.solidStateReturn.rawValue {
                    self.advanceProgramListingCurrent()
                } else {
                    let sourceKeycodes: [UInt8]
                    let effectiveStep: Int
                    if self.isUserProgramSource(prSourceFlag) {
                        sourceKeycodes = Array(m.allProgramSteps() as Data)
                        effectiveStep = max(0, currentStep - 1)
                    } else if prSourceFlag == ProgramSource.rom.rawValue {
                        sourceKeycodes = self.romKeycodes(machine: m)
                        effectiveStep = max(0, currentStep - 1)
                    } else if isLibSource {
                        sourceKeycodes = libInfo.map { Array(self.moduleKeycodes[$0.range]) } ?? []
                        effectiveStep = currentStep
                    } else {
                        sourceKeycodes = []
                        effectiveStep = -1
                    }
                    let argSteps = TI59KeyNames.argumentSteps(in: sourceKeycodes)
                    self.refreshProgramListing(machine: m, prSourceFlag: prSourceFlag,
                                              currentStep: effectiveStep,
                                              sourceKeycodes: sourceKeycodes, argSteps: argSteps)
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

    /// Index of the current step in programListing, or -1 if none is marked current.
    var programListingCurrentIndex: Int {
        programListing.firstIndex(where: { $0.isCurrent }) ?? -1
    }

    /// Rebuild programListing from the current machine state.
    /// For Prg Source 2 (solidStateReturn) call advanceProgramListingCurrent() instead —
    /// that source's SCOM PC is a raw return address, not a step number.
    private func refreshProgramListing(machine m: TI59MachineWrapper, prSourceFlag: UInt8, currentStep: Int,
                                       sourceKeycodes: [UInt8], argSteps: Set<Int>) {
        guard !sourceKeycodes.isEmpty else { programListing = []; return }
        programListingSourceFlag = prSourceFlag
        programListing = sourceKeycodes.enumerated().map { i, kc in
            .init(stepNum: i, keycode: kc,
                  mnemonic: argSteps.contains(i) ? String(format: "%02d", kc) : TI59KeyNames.mnemonic(for: kc),
                  isCurrent: i == currentStep)
        }
    }

    /// Move the isCurrent marker one step forward in programListing.
    /// Used for Prg Source 2 (solidStateReturn): keep the previous listing visible,
    /// advance the highlight onto the just-executed RTN.
    private func advanceProgramListingCurrent() {
        guard let idx = programListing.firstIndex(where: { $0.isCurrent }),
              idx + 1 < programListing.count else { return }
        programListing[idx].isCurrent = false
        programListing[idx + 1].isCurrent = true
    }

    /// Drop the freeze reason and ownership.  programListing is intentionally
    /// NOT cleared — it stays current and will be refreshed by the 60 Hz loop
    /// once the emulator resumes.
    private func clearFrozenState() {
        freezeReason = nil
        freezeOwner = nil
    }

    func unfreeze() {
        clearFrozenState()
        startEmulationLoop()
        startDisplayRefresh()
    }

    // MARK: - Program source helpers

    /// Returns true if the flag represents a user-stored program (User RAM or Fast Mode).
    private func isUserProgramSource(_ flag: UInt8) -> Bool {
        flag == ProgramSource.userProgram.rawValue || flag == ProgramSource.fastMode.rawValue
    }

    /// Returns true if the flag represents a program source whose step is
    /// driven by the SCOM[0] PC and can be shown via the SCOM-PC fallback path.
    /// Solid State (1) also shows steps, but through the CROM exec latch via a
    /// separate early branch — it is not covered here.
    private func isScomDisplayableSource(_ flag: UInt8) -> Bool {
        flag == ProgramSource.userProgram.rawValue || flag == ProgramSource.fastMode.rawValue || flag == ProgramSource.rom.rawValue
    }

    // MARK: - Solid-state module program table

    /// Cache the module image and parse its header into per-program byte ranges.
    /// Header layout (https://www.datamath.org/Chips/TMC0540.htm): byte 0 =
    /// program count (BCD), byte 1 = copy-protect flag, then one 2-byte BCD
    /// start address per program, followed by a pointer one past the last
    /// keycode of the final program.
    private func cacheModuleImage(_ data: Data?) {
        // Model/module switches rebuild the machine, so drop the ROM keycode
        // cache here; romKeycodes(machine:) refills it lazily from the new wrapper.
        romKeycodesCache = []
        let raw = data.map { [UInt8]($0) } ?? []
        func bcd(_ b: UInt8) -> Int { Int(b >> 4) * 10 + Int(b & 0xF) }

        // Module bytes are BCD: keycode 76 is stored as 0x76. Decode once so
        // every consumer (mnemonics, stepsAfter, listing) sees plain keycodes.
        moduleKeycodes = raw.map { UInt8(bcd($0)) }
        moduleProgramRanges = []
        guard raw.count > 2 else { return }

        func pointer(at offset: Int) -> Int? {
            guard offset + 1 < raw.count else { return nil }
            return bcd(raw[offset]) * 100 + bcd(raw[offset + 1])
        }

        let programCount = bcd(raw[0])
        guard programCount > 0 else { return }

        // Program n's start pointer lives at bytes 2n/2n+1; the entry after
        // program N's pointer marks the end of the last program.
        var boundaries: [Int] = []
        for n in 1...(programCount + 1) {
            guard let p = pointer(at: 2 * n) else { return }
            boundaries.append(p)
        }
        var ranges: [Range<Int>] = []
        for i in 0..<programCount {
            guard boundaries[i] < boundaries[i + 1], boundaries[i + 1] <= moduleKeycodes.count else {
                Self.logger.error("Module header has non-monotonic program table; solid-state step view disabled")
                return
            }
            ranges.append(boundaries[i]..<boundaries[i + 1])
        }
        moduleProgramRanges = ranges
    }

    /// The 384 main-ROM keycodes (PRG SOURCE = 8), fetched once per machine —
    /// they live in the constant ROM, so per-frame bridge calls are avoided.
    private func romKeycodes(machine m: TI59MachineWrapper) -> [UInt8] {
        if romKeycodesCache.count != 384 {
            romKeycodesCache = (0..<384).map { m.romKeycode(at: $0) }
        }
        return romKeycodesCache
    }

    /// Resolve the latched library execution address to the containing module
    /// program. Returns the 1-based program number, the program-relative step
    /// (000 = first keycode of the program), and the program's byte range —
    /// or nil when no module keycode has executed yet.
    private func libraryProgramStep(machine m: TI59MachineWrapper) -> (program: Int, step: Int, range: Range<Int>)? {
        let pc = Int(m.libExecPC)
        guard pc != 0xFFFF else { return nil }
        guard let idx = moduleProgramRanges.firstIndex(where: { $0.contains(pc) }) else { return nil }
        return (idx + 1, pc - moduleProgramRanges[idx].lowerBound, moduleProgramRanges[idx])
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
        // One bridge call to locate the non-zero registers, then fetch only those —
        // instead of up to 120 individual rawRegister calls per 60 Hz frame.
        let nonZeroRamIndices = m.nonZeroDataRegisterIndices()
            .map { totalRegs - 1 - $0 }   // bridge indices count down from the top of RAM
            .sorted()
        for ramIdx in nonZeroRamIndices where ramIdx >= programRegs && ramIdx < totalRegs {
            let raw = m.rawRegister(ramIdx) as Data
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

        // SCOM-PC-based sources: 0 (User), 4 (Fast Mode), 8 (ROM). Solid State
        // (1) uses the CROM latch — handled by the libInfo branch below.
        let canDisplayFromScomPC = isScomDisplayableSource(snap.prSourceFlag)

        // Solid State (1): the step comes from the library exec latch, not the
        // SCOM[0] program counter (which does not move during module execution).
        let libInfo = snap.prSourceFlag == ProgramSource.solidState.rawValue
            ? libraryProgramStep(machine: m) : nil

        if let lib = libInfo {
            // The latch points at the byte being dispatched, so it is already
            // the "last executed" step when frozen — no −1 adjustment needed.
            snap.currentStep = lib.step
            snap.nextStepNum = isFrozen ? lib.step + 1 : -1

            // Cross-check the range-derived program number against the Pgm
            // register in SCOM[9] (same nibbles the cue card uses).
            let scomProgram = Int(cpu.SCOM.9.4) * 10 + Int(cpu.SCOM.9.3)
            if scomProgram != lib.program && scomProgram != lastLibProgramMismatch {
                lastLibProgramMismatch = scomProgram
                Self.logger.debug("Library exec PC resolves to Pgm \(lib.program) but SCOM[9] says Pgm \(scomProgram)")
            }
        } else if canDisplayFromScomPC {
            if isFrozen {
                snap.currentStep = max(0, decodedPC - 1)
                snap.nextStepNum = decodedPC
            } else {
                // When running: currentStep is the next to execute (pre-execution state)
                snap.currentStep = decodedPC
                snap.nextStepNum = -1
            }
        } else {
            // Unknown source: can't display
            snap.currentStep = -1
            snap.nextStepNum = -1
        }

        // Keycodes for the active source, fetched once per frame and shared by the
        // window and next-step sections. User RAM (0/4) = full program, ROM (8) =
        // 384 constants, Solid State (1) = current module program (step numbers
        // relative to its start). Operand classification runs over the full
        // listing so windows starting mid-instruction don't misread operands
        // as opcodes.
        let sourceKeycodes: [UInt8]
        switch snap.prSourceFlag {
        case 0, 4: sourceKeycodes = Array(m.allProgramSteps() as Data)
        case 8:    sourceKeycodes = romKeycodes(machine: m)
        case 1:    sourceKeycodes = libInfo.map { Array(moduleKeycodes[$0.range]) } ?? []
        default:   sourceKeycodes = []
        }
        let argSteps = TI59KeyNames.argumentSteps(in: sourceKeycodes)

        // Program window: ±5 steps around the current step
        if !sourceKeycodes.isEmpty {
            let center = snap.currentStep >= 0 ? snap.currentStep : 0
            let lo = max(0, center - 5)
            let hi = min(sourceKeycodes.count - 1, center + 5)
            if lo <= hi {
                for i in lo...hi {
                    let kc = sourceKeycodes[i]
                    let mnemonic = argSteps.contains(i) ? String(format: "%02d", kc) : TI59KeyNames.mnemonic(for: kc)
                    snap.programWindow.append(.init(
                        stepNum: i,
                        keycode: kc,
                        mnemonic: mnemonic,
                        isCurrent: i == snap.currentStep
                    ))
                }
            }
        }

        // Always-live full program listing — skip solidStateReturn (raw CROM address in PC);
        // that case is handled by advanceProgramListingCurrent() in stepKeycode.
        if snap.prSourceFlag != ProgramSource.solidStateReturn.rawValue {
            refreshProgramListing(machine: m, prSourceFlag: snap.prSourceFlag,
                                  currentStep: snap.currentStep,
                                  sourceKeycodes: sourceKeycodes, argSteps: argSteps)
        }

        // When frozen: populate nextStep fields from the next instruction to execute
        if isFrozen && snap.nextStepNum >= 0 && snap.nextStepNum < sourceKeycodes.count {
            let nextKeycode = sourceKeycodes[snap.nextStepNum]
            snap.nextStepKeycode = nextKeycode
            let isArgument = argSteps.contains(snap.nextStepNum)
            snap.nextStepMnemonic = isArgument ? String(format: "%02d", nextKeycode) : TI59KeyNames.mnemonic(for: nextKeycode)
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

        // Trace flags are managed by updateDebugTraceFlags(); they are guaranteed
        // on whenever this builder runs (cpuDebugEnabled or isFrozen).

        // Read (without draining) all recent frames from the ring buffer
        let framesNS = m.readCpuFrames(max: 1024)
        let newFrames = (framesNS as [NSValue]).map { v -> TICpuFrame in
            var f = TICpuFrame()
            v.getValue(&f)
            return f
        }

        // Store frames in the rolling window
        cpuFrameWindow = newFrames

        // Accumulate ROM heatmap hits into the local buffer (every tick, cheap).
        // seqno prevents double-counting frames across non-destructive readCpuFrames calls.
        let newHits = newFrames.filter { $0.seqno > romHeatmapLastSeqno }
        if !newHits.isEmpty {
            for frame in newHits {
                let pc = Int(frame.pc)
                if pc < 0x1400 { romHitCountBuffer[pc] &+= 1 }
            }
            romHeatmapLastSeqno = newHits.last!.seqno
            romHeatmapDirty = true
        }
        // Publish to @Observable at ~10 Hz (every 6 ticks) to keep display refresh unaffected.
        heatmapTickCounter &+= 1
        if heatmapTickCounter >= 6 {
            heatmapTickCounter = 0
            if romHeatmapDirty {
                romHeatmapDirty = false
                romHitCount = romHitCountBuffer
            }
        }

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
        ringHead = 0
        debugLastDisplayHead = 0
        debugDisplayText = ""
        debugClearID &+= 1
    }

    func loadASMOverlayFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        if !scoped {
            print("[WARN FileImporter] loadASMOverlayFile: security-scoped resource access denied — file may not be readable")
        }
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            print("[WARN FileImporter] loadASMOverlayFile: failed to read file contents as UTF-8 from \(url.path)")
            asmStatusMessage = "Could not read ASM file."
            errorMessage = "Could not read ASM file."
            return
        }

        do {
            let words = try parseASMWords(from: text)

            guard let m = machine else {
                print("[WARN FileImporter] loadASMOverlayFile: machine is nil — cannot load overlay")
                asmStatusMessage = "Machine not initialized yet."
                return
            }

            let data = words.withUnsafeBufferPointer { Data(buffer: $0) }
            let loaded = m.loadDebugOverlayWords(data)
            guard loaded else {
                print("[WARN FileImporter] loadASMOverlayFile: overlay range exceeded (0x1800-0x1FFF) for \(words.count) word(s)")
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
            print("[WARN FileImporter] loadASMOverlayFile: parseASMWords threw: \(msg)")
            asmStatusMessage = msg
            errorMessage = msg
        }
    }

    func clearASMOverlay() {
        let wasActive = asmOverlayActive
        machine?.clearDebugOverlay()
        asmOverlayWords = []
        asmOverlayActive = false
        asmWordCount = 0
        asmStatusMessage = "ASM overlay cleared."
        // If the overlay was running, reset the machine so the CPU doesn't
        // execute the now-empty overlay range (which returns opcode 0) and
        // count all the way from 0x1800 to 0xFFFF before hitting real ROM.
        if wasActive {
            unfreeze()
            machine?.reset()
        }
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
        let freezeOnASMStart = pendingCPUScanLoopFreeze  // capture before clearing
        pendingCPUScanLoopFreeze = false
        _cpuFreezeSeenLoop = false
        clearFrozenState()

        var steps: UInt32 = 0
        var ok = false
        var loaded = true

        // Wait until any in-flight step batch finishes, then run the injection.
        emulQueue.sync {
            // Park the CPU at a keycode boundary so the digit counter is mid-cycle
            // when the overlay entry point is hit.
            _ = m.stepUntilNextKeycode()
            let data = self.asmOverlayWords.withUnsafeBufferPointer { Data(buffer: $0) }
            if !m.loadDebugOverlayWords(data) {
                loaded = false
                return
            }
            ok = m.runDebugOverlay(at: 0x1800, maxSteps: 8192, steps: &steps)
            m.beginNextStep()
        }

        if !loaded {
            asmStatusMessage = "ASM program exceeds overlay range 0x1800-0x1FFF."
            errorMessage = asmStatusMessage
        } else if ok {
            asmStatusMessage = "ASM entered at 0x1800 (\(steps) step(s))."
            asmOverlayActive = true
            if freezeOnASMStart {
                // FREEZE ON START was armed — freeze in-place at the 0x1800 entry point.
                // emulQueue.sync above already completed; no running loop to drain.
                freezeOwner = .cpu
                freezeReason = .manual
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.liveDebugSnapshot = self.buildLiveSnapshot(machine: m)
                    self.captureInspectorSnapshot(machine: m)
                }
            } else {
                startEmulationLoop()
            }
            startDisplayRefresh()
        } else {
            asmStatusMessage = "ASM entry failed after \(steps) step(s)."
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

    private func ringWrite(_ line: String) {
        ringBuf[ringHead % Self.ringBufCap] = line
        ringHead += 1
    }

    private func ringWriteAll(_ lines: [String]) {
        for line in lines { ringWrite(line) }
        refreshDebugDisplay()
    }

    /// Called by the 1 Hz timer and immediately after user-initiated dumps.
    /// Copies the ring buffer tail into debugDisplayText.
    /// Amount copied adapts to logging rate:
    ///   fast (> one page of new entries since last call) → show only the newest page
    ///   slow (≤ one page)                               → show up to displayPageCap pages
    private func refreshDebugDisplay() {
        let head = ringHead
        let newSinceLast = head - debugLastDisplayHead
        debugLastDisplayHead = head

        let totalAvailable = min(head, Self.ringBufCap)
        guard totalAvailable > 0 else { debugDisplayText = ""; return }

        let linesToShow = newSinceLast > Self.displayLinesPerPage
            ? min(Self.displayLinesPerPage, totalAvailable)
            : min(Self.displayLinesPerPage * Self.displayPageCap, totalAvailable)
        let startPos = head - linesToShow

        var lines = [String]()
        lines.reserveCapacity(linesToShow)
        for i in 0..<linesToShow {
            lines.append(ringBuf[(startPos + i) % Self.ringBufCap])
        }
        debugDisplayText = lines.joined(separator: "\n")
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
            ringWrite("── Vars: no data registers in current partition ──")
            refreshDebugDisplay()
            return
        }
        var lines: [String] = [String(format: "── Vars V00–V%02d ──", visibleDataRegCount - 1)]

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
                regEntries.append((label: String(format: "V%02d", dataIdx), value: v))
            }
        }

        // Sort by label and add to output
        regEntries.sort { $0.label < $1.label }
        for entry in regEntries {
            lines.append(String(format: "%@ = %.10g", entry.label, entry.value))
        }

        ringWriteAll(lines)
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
        ringWriteAll(lines)
    }

    /// Dump program RAM registers as raw nibble pairs in storage order.
    /// Each register = 8 steps × 2 nibbles (units nibble first, then tens nibble).
    /// Format: `R00: 67 11 24 00 00 00 00 00`
    func debugDumpProg() {
        guard let m = machine else { return }
        let progRegs = Int(m.partitionProgramRegs)
        var lines: [String] = [String(format: "── Prog P000–P%03d (key codes) ──", max(progRegs - 1, 0))]
        for reg in 0..<progRegs {
            let n = Array(m.rawRegister(reg) as Data)
            if n.allSatisfy({ $0 == 0 }) { continue }
            // Intentional: display program nibbles in storage order (units-tens pairs),
            // NOT the display format used by encodeRegisterLine (which reverses bytes).
            let pairs = stride(from: 0, to: 16, by: 2)
                .map { String(format: "%X%X", n[$0 + 1], n[$0]) }
                .joined(separator: " ")
            lines.append(String(format: "P%03d: %@", reg, pairs))
        }
        ringWriteAll(lines)
    }

    /// Dump entire RAM memory with address information.
    /// Shows only non-zero registers as raw nibble pairs using raw indices.
    func debugDumpMemory() {
        guard let m = machine else { return }
        var lines: [String] = ["── Registers (raw values) ──"]

        let totalRegs = Int(m.ramRegisterCount)

        for reg in 0..<totalRegs {
            guard reg >= 0 && reg < totalRegs else { continue }
            let nibbles = Array(m.rawRegister(reg) as Data)
            // Skip if all zeros
            if nibbles.allSatisfy({ $0 == 0 }) { continue }

            let bytes = encodeRegisterLine(nibbles)
            let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            lines.append(String(format: "R%03d: %@", reg, hex as NSString))
        }
        ringWriteAll(lines)
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

        ringWriteAll(lines)
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

        // Pre-scan for SKIP-RESET and MODEL: to use correct parsing parameters.
        // SKIP-RESET suppresses the model switch, so MODEL: is ignored for parsing too.
        var isSkipReset = false
        var targetModel = model
        for raw in text.components(separatedBy: .newlines) {
            let line = (raw.components(separatedBy: "#").first ?? "").trimmingCharacters(in: .whitespaces)
            let upper = line.uppercased()
            if upper.hasPrefix("SKIP-RESET:") {
                let val = String(line.dropFirst("SKIP-RESET:".count)).trimmingCharacters(in: .whitespaces).lowercased()
                isSkipReset = (val == "on" || val == "true" || val == "1")
            } else if !isSkipReset, upper.hasPrefix("MODEL:") {
                let val = String(line.dropFirst("MODEL:".count)).trimmingCharacters(in: .whitespaces).uppercased()
                targetModel = MachineModel.allCases.first(where: { $0.displayName == val }) ?? model
            }
        }

        let maxStepAddr = targetModel.hasLargeMemory ? 959 : 479
        let parsed = parseStateFile(text, maxStepAddr: maxStepAddr, allowHiddenRegisters: targetModel.hasConstantMemory)
        if !parsed.errors.isEmpty { errorMessage = parsed.errors.joined(separator: "\n") }

        // If the file targets a different model (and SKIP-RESET is not set), switch first
        // (async) then apply state. Partition validation runs inside applyParsedState after
        // self.model is resolved.
        if targetModel != model {
            Task { @MainActor in
                await self.start(model: targetModel)
                self.applyParsedState(parsed)
            }
            return
        }
        applyParsedState(parsed)
    }

    private func applyParsedState(_ parsed: LoadStateResult) {
        if parsed.skipReset {
            applySkipResetState(parsed)
            return
        }

        // Validate and adjust partition using self.model, which is now guaranteed to reflect
        // the target model (model switch via start(model:) completes before this is called).
        var parsed = parsed
        if !model.hasLargeMemory {
            if parsed.partitionWasExplicit && parsed.partitionMaxStep > 479 {
                errorMessage = "State file partition (\(parsed.partitionMaxStep)) exceeds \(model.displayName) maximum (479) — load aborted."
                return
            }
            if !parsed.partitionWasExplicit {
                parsed.partitionMaxStep = 239
            }
        }

        isRunning = false
        // Clear freeze state without restarting the loop
        clearFrozenState()
        // Synchronous dispatch ensures the emulation loop has fully exited
        // before we touch RAM or SCOM.  Without this, a step() in-flight on
        // emulQueue could write stale values after our state-file writes.
        emulQueue.sync {}

        guard let m = machine else { return }
        m.reset()

        // Clear program state: when loading a state file, no program should be active.
        // This ensures that the loaded custom cue card (or nil) is displayed, not a leftover program card.
        activeProgramNumber = 0

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

        // Clear RAM before loading new state, but preserve hidden registers (60-63) on TI-58C
        // Register 60 contains SCOM reconstruction data; clearing it triggers ROM memory clear
        let zeroNibbles = Data(repeating: UInt8(0), count: 16)
        let preserveHiddenRegs = model.hasConstantMemory
        let clearUpTo = preserveHiddenRegs ? 60 : 120
        for regNum in 0..<clearUpTo {
            m.setRawRegister(regNum, nibbles: zeroNibbles)
        }

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

        // Fresh machine state → fresh heatmap (also skips the power-on walk above).
        resetHeatmapBaseline()

        startEmulationLoop()

        // Clear the printer tape so each loaded state starts with a blank strip
        cutPaper()

        // Persist the loaded state once after all writes complete
        persistConstantMemory()

        // Apply solid-state module if specified in file
        if let moduleID = parsed.solidStateModuleID, moduleID != selectedModuleID {
            applyModule(id: moduleID)
        }

        // Apply printer connection state if specified in file
        if let connected = parsed.printerConnected {
            setPrinterConnected(connected)
        }

        // Set cue card if present in file
        self.userCueCardContent = parsed.cueCardContent
        self.cueCardContent = resolvedCueCard()

        if !parsed.keystrokes.isEmpty {
            Task { await playKeystrokes(parsed.keystrokes) }
        }
    }

    /// Apply a SKIP-RESET state file: no machine reset, no model/printer/module changes.
    /// Only PARTITION (if explicit), PROGRAM (if present), REGISTERS, CUECARD, and KEYSTROKES
    /// are applied. Sections that require a reset are logged as warnings and ignored.
    private func applySkipResetState(_ parsed: LoadStateResult) {
        if parsed.model != nil {
            print("[WARN] SKIP-RESET: MODEL: ignored — model switch requires a reset")
        }
        if parsed.solidStateModuleID != nil {
            print("[WARN] SKIP-RESET: SOLID-STATE-MODULE: ignored — module load requires a reset")
        }
        if parsed.printerConnected != nil {
            print("[WARN] SKIP-RESET: PRINTER: ignored — printer connection change requires a reset")
        }

        // Pause the emulation loop long enough to write program/registers safely.
        isRunning = false
        clearFrozenState()
        emulQueue.sync {}

        guard let m = machine else { return }

        // Apply PARTITION only if the file specified it explicitly; otherwise leave as-is.
        if parsed.partitionWasExplicit {
            let programRegs = (parsed.partitionMaxStep + 1) / 8
            m.partitionProgramRegs = programRegs
        }

        // Apply PROGRAM if present (zero-padded full write, same as full-reset path).
        if !parsed.programSteps.isEmpty {
            let totalSteps = parsed.partitionMaxStep + 1
            var programArray = [UInt8](repeating: 0, count: totalSteps)
            for (addr, keycode) in parsed.programSteps where addr < totalSteps {
                programArray[addr] = keycode
            }
            m.writeProgramSteps(Data(programArray))
        }

        // Apply REGISTERS if present.
        for (regNum, nibbles) in parsed.registers {
            if regNum >= 60 {
                m.setRawRegister(regNum, nibbles: Data(nibbles))
            } else {
                m.writeDataRegister(regNum, nibbles: Data(nibbles))
            }
        }

        startEmulationLoop()

        if model.hasConstantMemory {
            persistConstantMemory()
        }

        // Apply CUECARD if present.
        if parsed.cueCardContent != nil {
            self.userCueCardContent = parsed.cueCardContent
            self.cueCardContent = resolvedCueCard()
        }

        if !parsed.keystrokes.isEmpty {
            Task { await playKeystrokes(parsed.keystrokes) }
        }
    }

    // MARK: - Keystroke playback

    /// Play back a KEYSTROKES sequence asynchronously after a preset loads.
    ///
    /// Keys are sent at normal speed (450 ms hold + 50 ms gap) so the emulation loop
    /// reliably processes each press and release.  Use `.waitFullSpeed(t)` events to run
    /// the emulator at full speed for a fixed interval between keystrokes (e.g. while a
    /// program computes).  Full speed is restored to its previous state after each such wait.
    private func playKeystrokes(_ events: [KeystrokeEvent]) async {
        isKeystrokesPlaying = true
        defer { isKeystrokesPlaying = false }

        for event in events {
            switch event {
            case .key(let matrixCode):
                machine?.pressMatrixKey(matrixCode)
                try? await Task.sleep(nanoseconds: 450_000_000)  // hold 450 ms
                machine?.releaseMatrixKey(matrixCode)
                try? await Task.sleep(nanoseconds: 50_000_000)   // 50 ms gap → 500 ms total
            case .toggleTrace:
                togglePrinterTrace()
            case .wait(let t):
                try? await Task.sleep(nanoseconds: UInt64(t * 1_000_000_000))
            case .waitFullSpeed(let t):
                let previous = isFullSpeedMode
                isFullSpeedMode = true
                try? await Task.sleep(nanoseconds: UInt64(t * 1_000_000_000))
                isFullSpeedMode = previous
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
            guard traceWriter.isOpen else { break }
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


