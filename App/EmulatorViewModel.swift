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

/// Where the running program's steps come from, decoded from the PRG SOURCE
/// flag (SCOM[0] nibble 3) the way the firmware tests it: the run loop (ROM
/// 07C9) only asks "non-zero?", the step fetch (08B7, 0B98) tests bit 0
/// (module) before bit 3 (constant-ROM keycode table). There is no fast-mode
/// flag value: fast mode is any non-zero flag that selects neither table
/// (2, 4, 6) — see rom/TI59-ROM-Guide.md § "Fast mode".
enum ProgramSource: Equatable {
    /// 0: RAM program or keyboard.
    case userProgram
    /// Bit 0 set (1 official; 3, 5, 7, 9 fetch from the module just the same).
    case solidState
    /// 2 inside RTN_POP → LIB_RETURN (ROM 1193–1194, 14F9–1506, same on all
    /// variants): RTN has written the popped library level into SCOM[0], so
    /// nibbles 4–7 hold the saved CROM return address (plain BCD, not a step
    /// number) until 1506 sets the flag back to 1. Lasts 16 instructions —
    /// visible only when frozen, since stepUntilNextKeycode stops at 1192.
    case solidStateReturn
    /// 2, 4 or 6 anywhere else: a RAM program on the sub-program fast path —
    /// no display formatting, no R/S or GTO polls.
    case fastMode
    /// Bit 3 set, bit 0 clear (8 official): keycode sub-program in the
    /// constant ROM.
    case rom

    /// Decoded by Shared/ModuleImage.cpp (programSourceFrom).
    init(flag: UInt8, romPC: UInt16) {
        self = Self.cases[TIDebugModel.programSource(forFlag: flag, romPC: romPC)]
    }

    /// TIDebugModel / TILiveDebugSnapshot raw values follow the C++ enumerator order.
    init(raw: Int) { self = Self.cases[raw] }
    private static let cases: [ProgramSource] = [.userProgram, .solidState, .solidStateReturn, .fastMode, .rom]
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
    /// Title shown alongside `errorMessage` in the alert. Defaults to the ROM-loading
    /// case since that's the only path that doesn't set it explicitly.
    var errorTitle: String = "ROM load error"

    // ── Display interaction state ────────────────────────────────────────────────
    var isDisplayPressed: Bool = false
    var isFullSpeedMode: Bool = false  // true when user is pressing display; emulation runs unrestricted
    var isKeystrokesPlaying: Bool = false
    /// Baseline core elapsed-tick count, snapshotted by the KEYSTROKES ".zeroElapseTime" event.
    private var elapseTimeBaseline: UInt64 = 0
    private var keystrokeTask: Task<Void, Never>?

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

    // Scripted CPU trace (KEYSTROKES "Trace:" directive) — independent of the
    // manual "C" indicator toggle above: its own writer, own filename, own
    // session lifecycle. Both may be open simultaneously; drainTraceEvents()
    // fans each drained frame out to whichever of the two is currently open.
    private var scriptedTraceWriter: TraceWriter!

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
    /// Module image, ROM keycode cache, heatmap and log ring (Shared/ via Bridge/TIDebugModel).
    /// Replaced with the machine on a model switch; touched on the main thread only.
    @ObservationIgnored private var debugModel = TIDebugModel(model: 0)
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
    var programListingSource: ProgramSource = .userProgram   // Prg Source the listing was built for

    private var lastLibProgramMismatch: Int = .min  // throttles SCOM[9] cross-check logging

    // ── Live CPU view state (60 Hz real-time, runs while emulating) ────────────
    var cpuDebugSnapshot: CPUDebugSnapshot = .empty
    private var cpuFrameWindow: [TICpuFrame] = []  // rolling window of recent instructions

    // ── ROM Heatmap (5 120 code addresses 0x0000–0x13FF) ─────────────────────
    // Observable published at ~10 Hz to avoid flooding SwiftUI render pipeline.
    var romHitCount: [UInt32] = Array(repeating: 0, count: 0x1400)

    func clearRomHeatmap() {
        debugModel.heatmapClear()
        romHitCount = Array(repeating: 0, count: 0x1400)
    }

    /// Clear the heatmap and skip whatever is still in the trace ring, so counting
    /// starts at "now" rather than replaying up to 1024 stale frames from the last
    /// time tracing was active.
    private func resetHeatmapBaseline() {
        clearRomHeatmap()
        if let m = machine, let newest = m.readCpuFrames(max: 1).last {
            var f = TICpuFrame()
            newest.getValue(&f)
            debugModel.heatmapResetBaseline(f.seqno)
        }
    }

    /// Single owner of the machine's trace flags.  Recomputed whenever a consumer
    /// changes state: CPU debug panel visibility, freeze mode (incl. armed
    /// freeze-on-start), the binary trace toggle, or the breakpoint set.
    /// With no consumer active the core runs with TRACE_NONE — its fast path.
    private func updateDebugTraceFlags() {
        guard let m = machine else { return }
        var flags: TITraceFlags = []
        if cpuDebugEnabled || isFrozen || cIndicatorDebug || pendingFreezeOnPCChange || pendingCPUScanLoopFreeze
            || scriptedTraceWriter.isOpen {
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

    private var machine: TI59MachineWrapper?
    private let emulQueue = DispatchQueue(label: "calc-u-59.emulation", qos: .userInteractive)
    private var displayTimer: Timer?
    private var isRunning = false
    /// Held for the app's lifetime so macOS never App-Naps the background emulation
    /// queue while the window is unfocused/occluded — App Nap can otherwise stall
    /// emulQueue's step() loop entirely, freezing currentPC and making any PC-range
    /// wait (e.g. waitForScanLoopIdle) return immediately instead of actually waiting.
    private var appNapActivityToken: NSObjectProtocol?
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
        appNapActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "TI-59 CPU emulation must keep running at real-time pace in the background"
        )
        // Initialize traceWriter with default model
        traceWriter = TraceWriter(model: model)
        configureTraceWriter()
        // Check trace availability at startup (for iOS/iPadOS iCloud detection, etc.)
        traceWriter.checkAvailability()
        scriptedTraceWriter = TraceWriter(model: model)
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
        scriptedTraceWriter = TraceWriter(model: model)
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
            wrapper.loadROM(words)

            debugModel = TIDebugModel(model: model.rawValue)

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
            self.errorTitle = "ROM load error"
            self.errorMessage = error.localizedDescription
        }
    }

    private func startEmulationLoop() {
        isRunning = true
        guard let m = machine else { return }
        emulQueue.async { [weak self, m] in
            guard let self else { return }
            var cyclesDone: Int32 = 0
            // Idle mode runs at ÷4 (step() returns 4 instead of 1, except TI-58C constant speed),
            // so the loop naturally slows down when the calculator is waiting for a keypress.
            let targetHz: Double = model.instructionHz
            let batchMs: Double = 0.020  // 20 ms batches keep latency low
            let targetBatchCycles = Int32(targetHz * batchMs) // ≈ 284

            while self.isRunning {
                let start = DispatchTime.now()
                // Set when any step this batch was a *confirmed* spin-wait retrying a
                // keyboard-matrix scan or printer/peripheral BUSY test — real-world state
                // whose completion doesn't depend on CPU speed (see TMC0501::step()'s
                // 0x4000_0000 return bit doc: only a backward branch that retries such a
                // poll sets it, not every occurrence, so an incidental check on the way
                // through productive code doesn't force throttling). Forces the throttle
                // below regardless of PC, since the ROM re-implements this spin idiom at
                // multiple addresses (e.g. fast mode's print dispatcher has its own copy
                // outside the normal keyboard-scan idle loop that cpuIdleAndKeyDetectRange
                // covers) — see calendar-08-acosta.ti59.
                var polledHardwareState = false
                while cyclesDone < targetBatchCycles {
                    let result = m.step()
                    if result & 0x8000_0000 != 0 {
                        // Breakpoint hit — pause the emulation loop.
                        self.isRunning = false
                        let hitPC = m.currentPC
                        DispatchQueue.main.async { self.onBreakpointHit(pc: hitPC) }
                        return
                    }
                    if result & 0x4000_0000 != 0 { polledHardwareState = true }
                    cyclesDone += Int32(result & 0x3FFF_FFFF)

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
                    let currentPC = TIDebugModel.decodeProgramCounter(cpu)

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

                // Skip timing throttle when in full-speed mode (user pressing display, or a
                // KEYSTROKES FullSpeed:/WaitFullSpeed: window) — EXCEPT while the CPU is
                // currently sitting in the keyboard-scan idle loop, or this batch polled
                // hardware state (polledHardwareState, set above). Full speed always paces
                // those portions at regular speed instead of racing unthrottled: otherwise the
                // batch loop below never sleeps, so it can execute an enormous, real-time-
                // unbounded number of idle-loop/poll iterations before whatever polls
                // currentPC (e.g. waitForScanLoopIdle) next samples it and notices the CPU is
                // idle — wildly inflating any elapsed-tick measurement taken across that
                // window. cpuIdleAndKeyDetectRange is PC-range based (not FLG_IDLE) because
                // the TI-58C is only partially idle while in its scan loop; polledHardwareState
                // catches the same class of spin at ROM addresses outside that range (e.g.
                // fast mode's own print-dispatch key/BUSY wait — see calendar-08-acosta.ti59).
                let inScanLoop = (self.cpuIdleAndKeyDetectRange?.contains(m.currentPC) ?? false) || polledHardwareState
                if !self.isFullSpeedMode || inScanLoop {
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
                debugModel.logWrite(String(msg.dropFirst(2)))
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

        if cIndicatorDebug || scriptedTraceWriter.isOpen {
            // Drain trace events directly on main thread (tick() is already on main).
            // The emulation loop runs on the serial emulQueue, so async dispatches would
            // never execute until the loop exits — we drain here at 60 Hz instead.
            // Must also run for the scripted (KEYSTROKES "Trace:") writer: without this,
            // frames only get drained at the Trace:/Trace: Off calls in playKeystrokes,
            // letting the 1024-frame ring buffer overflow and silently lose most of a
            // session that runs for more than an instant (e.g. spans a Wait:/WaitFullSpeed:).
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

    /// Matrix code (11–95) → the 0-based (row, col) `pressKey`/`releaseKey` take.
    private static func rowCol(forMatrix code: UInt8) -> (row: Int, col: Int) {
        (row: Int(code / 10) - 1, col: Int(code % 10) - 1)
    }

    private func pressMatrix(_ code: UInt8) {
        let (row, col) = Self.rowCol(forMatrix: code)
        pressKey(row: row, col: col)
    }

    private func releaseMatrix(_ code: UInt8) {
        let (row, col) = Self.rowCol(forMatrix: code)
        releaseKey(row: row, col: col)
    }

    /// Press a key, hold it long enough for the ROM to accept it, release, then
    /// wait until the keyboard-scan idle loop is reached again.
    ///
    /// The 100 ms hold is comfortably longer than the ROM's worst-case debounce
    /// window (~3 sweeps to arm + confirm, see `ideas/KeypressLatch.md`) while short
    /// enough that a "repeat while held" key (e.g. Adv/PRT_FEED, gated by real
    /// busy time — see the printer busy-cycle comments in `TMC0501.cpp`) only
    /// fires a couple of times per keystroke at regular speed, matching
    /// real-hardware button feel.
    ///
    /// Shared by KEYSTROKES script playback and by physical-keyboard input, so
    /// both feed the core with the same, proven timing.
    private func tapMatrixKey(_ code: UInt8) async {
        pressMatrix(code)
        try? await Task.sleep(nanoseconds: Self.keyHoldNanoseconds)
        releaseMatrix(code)
        await waitForScanLoopIdle()
    }

    /// Minimum time a key stays electrically down. See `tapMatrixKey`.
    private static let keyHoldNanoseconds: UInt64 = 100_000_000

    // MARK: - Physical keyboard input

    /// The key a physical-keyboard press is currently holding down, as
    /// `row * 5 + col`, so `KeyboardView` can show it depressed exactly as it
    /// does for a pointer press. Nil when no keyboard key is down.
    var keyboardHeldKey: Int? = nil

    private var keyboardHeldCode: UInt8? = nil
    private var keyboardPressedAt: Date? = nil
    private var keyboardTask: Task<Void, Never>? = nil

    /// Handle a physical key going down, resolved to one or two matrix codes by
    /// `Shared/KeyboardMap.cpp`.
    ///
    /// A single code follows the hardware's level semantics: it goes down now and
    /// comes back up in `keyboardKeyUp()`, subject to the minimum hold. A pair
    /// (2nd + key, e.g. Shift+A for A′) is one logical action and is played back
    /// as two full taps instead — key-up is ignored for it, because the ROM needs
    /// 2nd to be released and re-scanned before the second key can be accepted.
    func keyboardKeyDown(_ codes: [UInt8]) {
        guard let last = codes.last else { return }
        // The hardware rejects chords, and only one key can be held at a time —
        // mirrors KeyboardView.releaseHeldKey() for pointer input.
        keyboardKeyUp()
        keyboardTask?.cancel()

        if codes.count == 1 {
            keyboardHeldCode = last
            keyboardPressedAt = Date()
            keyboardHeldKey = Self.highlightID(forMatrix: last)
            pressMatrix(last)
            return
        }

        keyboardTask = Task { [weak self] in
            for code in codes {
                guard !Task.isCancelled, let self else { return }
                self.keyboardHeldKey = Self.highlightID(forMatrix: code)
                await self.tapMatrixKey(code)
            }
            self?.keyboardHeldKey = nil
        }
    }

    /// Handle a physical key going up. No-op unless a single-code press is held.
    ///
    /// Releasing earlier than `keyHoldNanoseconds` after the press would let the
    /// ROM discard the key as bounce (`ideas/KeypressLatch.md` constraint 3), which is
    /// exactly what fast typing produces — so a too-early release is deferred to
    /// the end of the hold window rather than applied.
    func keyboardKeyUp() {
        guard let code = keyboardHeldCode else { return }
        keyboardHeldCode = nil
        keyboardHeldKey = nil

        let held = Date().timeIntervalSince(keyboardPressedAt ?? .distantPast)
        keyboardPressedAt = nil
        let remaining = Double(Self.keyHoldNanoseconds) / 1_000_000_000 - held
        guard remaining > 0 else {
            releaseMatrix(code)
            return
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            self?.releaseMatrix(code)
        }
    }

    /// Force-release whatever the keyboard is holding — used when the calculator
    /// view loses focus or is torn down, so a matrix bit can't stay stuck set.
    func keyboardRelease() {
        keyboardTask?.cancel()
        keyboardTask = nil
        if let code = keyboardHeldCode {
            keyboardHeldCode = nil
            keyboardPressedAt = nil
            releaseMatrix(code)
        }
        keyboardHeldKey = nil
    }

    /// Matrix code → the `row * 5 + col` identifier `KeyboardView` highlights by.
    private static func highlightID(forMatrix code: UInt8) -> Int {
        let (row, col) = rowCol(forMatrix: code)
        return row * 5 + col
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
        keystrokeTask?.cancel()
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
            debugModel.logWrite("Calculator Reset")
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

        debugModel.logWrite("Calculator Reset")
    }

    /// Clean reset (all models): zero all RAM, then reset.
    /// For TI-58C, writes the zeroed state immediately to the save file.
    func cleanResetMachine() {
        keystrokeTask?.cancel()
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
        debugModel.logWrite("Clean Reset — all registers cleared")
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
            errorTitle = "Card load error"
            errorMessage = "Could not read card file."
            return
        }
        // Text, headered binary and legacy layouts: Shared/CardFile.cpp.
        let decoded = TIFileFormats.decodeCardFile(raw, fileName: url.lastPathComponent)
        guard let data = decoded.data else {
            errorTitle = "Card load error"
            errorMessage = decoded.error
            return
        }
        if decoded.isText {
            userCueCardContent = decoded.cueCard.swiftValue
            cueCardContent = resolvedCueCard()
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
        let text = TIFileFormats.encodeCardText(data, cueCard: cueCardContent?.bridged)
        guard let fileData = text.data(using: .utf8) else {
            errorTitle = "Card save error"
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
            errorTitle = "Card save error"
            errorMessage = "Card save failed: \(err.localizedDescription)"
        } else {
            cardFileName = url.lastPathComponent
            hasCardFile = true
        }
    }

    // MARK: - TI-58C constant memory

    func persistConstantMemory() {
        guard model.hasConstantMemory, let data = machine?.serialiseRAM() else { return }
        let text = TIFileFormats.encodeConstantMemory(data, cueCard: userCueCardContent?.bridged)
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
        if let text = String(data: rawData, encoding: .utf8),
           let decoded = TIFileFormats.decodeConstantMemory(text) {
            self.userCueCardContent = decoded.cueCard.swiftValue
            self.cueCardContent = resolvedCueCard()
            return decoded.ram
        }

        // Silently fail; caller resets RAM to zeros.
        return nil
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
        lastObservedPC = UInt16(TIDebugModel.decodeProgramCounter(cpu))
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

    /// Steady-state keyboard scan loop (FREEZE ON START); see Shared/MachineModelInfo.hpp.
    private var cpuScanLoopRange: ClosedRange<UInt16>? {
        Self.closedRange(TISharedTables.scanLoopRange(forModel: model.rawValue))
    }

    /// PC range covering the FULL keyboard scan/detect cycle — release-gate spin
    /// through key acceptance. Wider than `cpuScanLoopRange` above (used only by FREEZE ON
    /// START, which cares about the steady-state cycle, not the release gates) —
    /// this one is used anywhere a held key or full-speed racing must not be allowed
    /// to blow past real "the calculator is still just scanning/debouncing" time.
    /// Addresses and sources: Shared/MachineModelInfo.hpp.
    private var cpuIdleAndKeyDetectRange: ClosedRange<UInt16>? {
        Self.closedRange(TISharedTables.idleAndKeyDetectRange(forModel: model.rawValue))
    }

    private static func closedRange(_ r: NSRange) -> ClosedRange<UInt16> {
        UInt16(r.location)...UInt16(r.location + r.length - 1)
    }

    /// Poll until the CPU reaches the keyboard-scan idle loop. Used as the default
    /// inter-keystroke gap during KEYSTROKES playback so a script never sends its next
    /// key before the calculator can actually accept it — independent of the "FREEZE ON
    /// START" armed state (pendingCPUScanLoopFreeze etc.), which it neither reads nor sets.
    /// No timeout: a scenario that never reaches idle will hang playback indefinitely —
    /// except that a freeze (e.g. FREEZE ON START firing on the keypress just sent) stops
    /// the CPU outright, so PC will never enter the scan loop again; return immediately
    /// once frozen instead of spinning forever.
    ///
    /// Deliberately uses the NARROW `cpuScanLoopRange`, not `cpuIdleAndKeyDetectRange`:
    /// the wide range also covers states reached while still debouncing/confirming the
    /// key just pressed (release gates, arming/confirmation scans before 0x0661 accept).
    /// Using it here would let this return before that key is actually fully accepted,
    /// so the NEXT key could fire mid-debounce and get discarded as bounce — the narrow
    /// range is specifically the steady "nothing pending" cycle, the correct "safe for a
    /// new keypress" signal.
    private func waitForScanLoopIdle() async {
        guard let range = cpuScanLoopRange else { return }
        while !Task.isCancelled {
            if isFrozen { return }
            if let pc = machine?.currentPC, range.contains(pc) { return }
            try? await Task.sleep(nanoseconds: 1_500_000) // ~1.5ms poll
        }
    }

    /// Report elapsed time since the last ".zeroElapseTime" (or since reset, if none), to
    /// the debug log — unconditionally, regardless of the debug level setting.
    private func reportElapseTime() {
        let current = machine?.elapsedTicks ?? 0
        let deltaTicks = current >= elapseTimeBaseline ? current - elapseTimeBaseline : 0
        let seconds = Double(deltaTicks) / model.instructionHz
        let totalMs = Int((seconds * 1000).rounded())
        let minutes = totalMs / 60_000
        let secs = (totalMs / 1000) % 60
        let ms = totalMs % 1000
        ringWriteAll([String(format: "Elapsed: %d:%02d.%03d", minutes, secs, ms)])
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
                let source = ProgramSource(flag: UInt8(cpu.SCOM.0.3), romPC: cpu.pc)

                // Update always-live program listing.
                // solidStateReturn: SCOM[0] holds a raw CROM return address —
                // keep the previous listing and advance the highlight onto the just-executed RTN.
                // All other sources: rebuild from current machine state (frozen-step semantics).
                if source == .solidStateReturn {
                    self.advanceProgramListingCurrent()
                } else {
                    let build = self.debugModel.buildLiveSnapshot(for: m, frozen: true)
                    self.refreshProgramListing(source: source, build: build,
                                               currentStep: build.snapshot.currentStep)
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
    /// For solidStateReturn call advanceProgramListingCurrent() instead —
    /// that source's SCOM PC is a raw return address, not a step number.
    private func refreshProgramListing(source: ProgramSource, build: TILiveDebugBuild, currentStep: Int) {
        guard !build.sourceKeycodes.isEmpty else { programListing = []; return }
        programListingSource = source
        programListing = TIDebugModel.programListing(build.sourceKeycodes, argSteps: build.argSteps,
                                                     currentStep: currentStep).map(LiveDebugSnapshot.StepEntry.init)
    }

    /// Move the isCurrent marker one step forward in programListing.
    /// Used for solidStateReturn: keep the previous listing visible,
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

    // MARK: - Solid-state module program table

    /// Hand the module image to the debug model (program table for the live
    /// PROGRAM STEPS view: Shared/ModuleImage.cpp).
    private func cacheModuleImage(_ data: Data?) {
        if let error = debugModel.setModuleImage(data) {
            Self.logger.error("\(error, privacy: .public)")
        }
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


    /// Build a real-time debug snapshot for the live debug view (Shared/DebugSnapshots.cpp)
    /// and refresh the always-live program listing.
    /// Called from tick() at 60 Hz only when liveDebugEnabled.
    private func buildLiveSnapshot(machine m: TI59MachineWrapper) -> LiveDebugSnapshot {
        let build = debugModel.buildLiveSnapshot(for: m, frozen: isFrozen)
        logLibProgramMismatch(build)
        let snap = LiveDebugSnapshot(build.snapshot)
        // solidStateReturn shows a raw CROM address in the PC; that case is
        // handled by advanceProgramListingCurrent() in stepKeycode.
        if snap.programSource != .solidStateReturn {
            refreshProgramListing(source: snap.programSource, build: build, currentStep: snap.currentStep)
        }
        return snap
    }

    /// Cross-check of the library range against the Pgm register in SCOM[9], logged once per value.
    private func logLibProgramMismatch(_ build: TILiveDebugBuild) {
        guard build.scomProgram >= 0, build.scomProgram != lastLibProgramMismatch else { return }
        lastLibProgramMismatch = build.scomProgram
        Self.logger.debug("Library exec PC resolves to Pgm \(build.libProgram) but SCOM[9] says Pgm \(build.scomProgram)")
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
        debugModel.heatmapIngest(framesNS)
        // Publish to @Observable at ~10 Hz (every 6 ticks) to keep display refresh unaffected.
        if debugModel.heatmapPublishTick() {
            romHitCount = debugModel.heatmapCounts.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
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

    func toggleDebug() {
        debugLevel.cycle()
        machine?.setDebugLevel(UInt8(debugLevel.rawValue))
    }

    func clearDebug() {
        debugModel.logClear()
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
            errorTitle = "ASM load error"
            errorMessage = "Could not read ASM file."
            return
        }

        do {
            let wordData = try TIDebugModel.parseAsmWords(text)
            let words = wordData.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self)) }

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
                errorTitle = "ASM load error"
                errorMessage = asmStatusMessage
                return
            }

            asmOverlayWords = words
            asmFileName = url.lastPathComponent
            asmWordCount = words.count
            asmStatusMessage = String(format: "Loaded %d word(s) at 0x1800.", words.count)
        } catch {
            let msg = error.localizedDescription
            print("[WARN FileImporter] loadASMOverlayFile: parseAsmWords failed: \(msg)")
            asmStatusMessage = msg
            errorTitle = "ASM load error"
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
        var loaded: ObjCBool = true

        // Wait until any in-flight step batch finishes, then run the injection
        // (park at a keycode boundary, load, enter at 0x1800: Shared/AsmOverlay.cpp).
        let data = asmOverlayWords.withUnsafeBufferPointer { Data(buffer: $0) }
        emulQueue.sync {
            ok = TIDebugModel.runAsmOverlay(m, words: data, loaded: &loaded, steps: &steps)
        }

        if !loaded.boolValue {
            asmStatusMessage = "ASM program exceeds overlay range 0x1800-0x1FFF."
            errorTitle = "ASM load error"
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
            errorTitle = "ASM load error"
            errorMessage = asmStatusMessage
        }
    }

    private func ringWriteAll(_ lines: [String]) {
        debugModel.logWriteAll(lines)
        refreshDebugDisplay()
    }

    /// Called by the 1 Hz timer and immediately after user-initiated dumps.
    private func refreshDebugDisplay() {
        debugDisplayText = debugModel.logDisplayText()
    }

    // Dumps for the LOG tab (formats: Shared/DebugLog.cpp).
    func debugDumpVars() {
        guard let m = machine else { return }
        ringWriteAll(debugModel.dumpVars(m))
    }

    func debugDumpSCOM() {
        guard let m = machine else { return }
        ringWriteAll(TIDebugModel.dumpScom(m))
    }

    func debugDumpProg() {
        guard let m = machine else { return }
        ringWriteAll(TIDebugModel.dumpProg(m))
    }

    func debugDumpMemory() {
        guard let m = machine else { return }
        ringWriteAll(TIDebugModel.dumpMemory(m))
    }

    func debugDumpStepCounterAnalysis() {
        guard let m = machine else { return }
        ringWriteAll(TIDebugModel.dumpStepCounterAnalysis(m))
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
        guard let raw = try? Data(contentsOf: url) else {
            errorTitle = "State file load error"
            errorMessage = "Cannot read file."
            return
        }
        guard let text = String(data: raw, encoding: .utf8) else {
            errorTitle = "State file load error"
            errorMessage = "File is not valid UTF-8 text — re-save it with UTF-8 encoding (a non-UTF-8 character, e.g. a curly quote or em dash from a word processor, is the usual cause)."
            return
        }

        // Pre-scan for SKIP-RESET and MODEL: to use correct parsing parameters.
        // SKIP-RESET suppresses the model switch, so MODEL: is ignored for parsing too.
        let targetRaw = TIFileFormats.prescanStateFile(text, currentModel: model.rawValue, skipReset: nil)
        let targetModel = MachineModel(rawValue: targetRaw) ?? model

        let maxStepAddr = targetModel.hasLargeMemory ? 959 : 479
        let parsed = LoadStateResult(parsing: text, maxStepAddr: maxStepAddr,
                                     allowHiddenRegisters: targetModel.hasConstantMemory)
        if !parsed.errors.isEmpty {
            errorTitle = "State file load error"
            errorMessage = parsed.errors.joined(separator: "\n")
        }

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
                errorTitle = "State file load error"
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

        // Clear RAM before loading new state, but preserve the TI-58C's extra
        // registers (raw RAM 60-63, E000-E003 / H00-H03 — not normal registers
        // "60"-"63"; see reference/CoreArchitecture.md's "TI-58C Extra
        // (Constant Memory) Registers"). RAM[60] holds SCOM reconstruction
        // data; clearing it triggers the ROM's memory-clear routine.
        let zeroNibbles = Data(repeating: UInt8(0), count: 16)
        let preserveExtraRegs = model.hasConstantMemory
        let clearUpTo = preserveExtraRegs ? MachineModel.extraRegisterBase : 120
        for regNum in 0..<clearUpTo {
            m.setRawRegister(regNum, nibbles: zeroNibbles)
        }

        // Expand sparse steps into a full zero-padded array so unlisted steps are 00.
        // Sized to the model's physical step capacity, not the (possibly rounded, or
        // simply mismatched) PARTITION boundary — some listings deliberately load
        // registers as programs and programs as registers (e.g.
        // examples/calendar-05-vanderburgh.ti59), so PROGRAM:/REGISTERS: are trusted
        // as written; only the physical capacity is an overflow limit.
        let physicalMaxStep = model.hasLargeMemory ? 959 : 479
        var programArray = [UInt8](repeating: 0, count: physicalMaxStep + 1)
        for (addr, keycode) in parsed.programSteps where addr <= physicalMaxStep {
            programArray[addr] = keycode
        }
        m.writeProgramSteps(Data(programArray))
        for (regNum, nibbles, isHidden) in parsed.registers {
            if isHidden {
                // TI-58C extra registers (H00-H03): write directly to raw RAM
                // slots 60-63 — these are never normal registers "60"-"99",
                // which is why this branches on the explicit isHidden flag
                // rather than regNum's range (a TI-59 file legitimately uses
                // regNum up to 99 for ordinary registers).
                m.setRawRegister(MachineModel.extraRegisterBase + regNum, nibbles: Data(nibbles))
            } else {
                // Normal data registers: use the reversed (top-down) mapping
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
            keystrokeTask = Task { await playKeystrokes(parsed.keystrokes) }
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
        // See the full-reset path above for why this is sized to the model's physical
        // step capacity rather than the PARTITION boundary.
        if !parsed.programSteps.isEmpty {
            let physicalMaxStep = model.hasLargeMemory ? 959 : 479
            var programArray = [UInt8](repeating: 0, count: physicalMaxStep + 1)
            for (addr, keycode) in parsed.programSteps where addr <= physicalMaxStep {
                programArray[addr] = keycode
            }
            m.writeProgramSteps(Data(programArray))
        }

        // Apply REGISTERS if present. See the full-reset path above for why
        // this branches on isHidden rather than regNum's range.
        for (regNum, nibbles, isHidden) in parsed.registers {
            if isHidden {
                m.setRawRegister(MachineModel.extraRegisterBase + regNum, nibbles: Data(nibbles))
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
            keystrokeTask = Task { await playKeystrokes(parsed.keystrokes) }
        }
    }

    // MARK: - Keystroke playback

    /// Play back a KEYSTROKES sequence asynchronously after a preset loads.
    ///
    /// Keys are held 100 ms then released, after which playback waits for the CPU to
    /// actually reach the keyboard-scan idle loop before the next event — this guarantees
    /// no keystroke is lost to a still-computing calculator, regardless of how long the
    /// preceding computation takes.  Use `.waitFullSpeed(t)` events to run the emulator at
    /// full speed for a fixed interval between keystrokes (e.g. while a program computes);
    /// full speed is restored to its previous state after each such wait.  `.fullSpeed`/
    /// `.regularSpeed` toggle full speed persistently instead (no auto-revert) — speed is
    /// always reset to regular when the script ends, even if it omitted `.regularSpeed`.
    private func playKeystrokes(_ events: [KeystrokeEvent]) async {
        isKeystrokesPlaying = true
        defer {
            isKeystrokesPlaying = false
            isFullSpeedMode = false  // always end a script at regular speed
            // Auto-stop a scripted trace left running past the end of the script,
            // so no session is ever left dangling without a matching "Trace: Off".
            if scriptedTraceWriter.isOpen, let m = machine {
                drainTraceEvents(machine: m)
                scriptedTraceWriter.close()
                updateDebugTraceFlags()
            }
        }

        for event in events {
            guard !Task.isCancelled else { return }
            switch event {
            case .key(let matrixCode):
                await tapMatrixKey(matrixCode)
            case .toggleTrace:
                togglePrinterTrace()
            case .wait(let t):
                try? await Task.sleep(nanoseconds: UInt64(t * 1_000_000_000))
            case .waitFullSpeed(let t):
                let previous = isFullSpeedMode
                isFullSpeedMode = true
                try? await Task.sleep(nanoseconds: UInt64(t * 1_000_000_000))
                isFullSpeedMode = previous
            case .fullSpeed:
                isFullSpeedMode = true
            case .regularSpeed:
                isFullSpeedMode = false
            case .zeroElapseTime:
                elapseTimeBaseline = machine?.elapsedTicks ?? 0
            case .reportElapseTime:
                reportElapseTime()
            case .trace(let name):
                // Switching files (or turning off) first flushes and closes whatever
                // scripted session is currently open, for a clean SESSION_END.
                if scriptedTraceWriter.isOpen, let m = machine {
                    drainTraceEvents(machine: m)
                    scriptedTraceWriter.close()
                }
                if let name {
                    let opened = scriptedTraceWriter.open(fileName: name)
                    if !opened {
                        print("[EmulatorViewModel] KEYSTROKES \"Trace: \(name)\" failed to open trace file — see TraceWriter/AppSettings logs above for the reason")
                    }
                }
                updateDebugTraceFlags()
            }
        }
    }

    // ── Binary trace file (TI59_TRACE.bin) ───────────────────────────────────
    // Drain the CPU ring buffer and forward frames to TraceWriter.
    // Called from tick() (main thread, 60 Hz) and from the emulQueue close path.

    private func drainTraceEvents(machine m: TI59MachineWrapper) {
        var lost: UInt = 0
        let framesNS = m.drainCpuFrames(max: 1024, lost: &lost)

        // Write gap record if ring overflow occurred, to whichever writer(s) are open.
        if lost > 0 {
            traceWriter.writeLostGap(count: UInt32(lost))
            scriptedTraceWriter.writeLostGap(count: UInt32(lost))
        }

        guard !framesNS.isEmpty else { return }

        // There is a single consuming ring-buffer cursor (drainCpuFrames above), so both
        // writers — the manual "C" indicator toggle and the scripted Trace: directive —
        // share this one drain and independently choose whether to persist each frame.
        for frameVal in framesNS {
            guard traceWriter.isOpen || scriptedTraceWriter.isOpen else { break }
            var frame = TICpuFrame()
            frameVal.getValue(&frame)
            if traceWriter.isOpen { traceWriter.write(frame: frame) }
            if scriptedTraceWriter.isOpen { scriptedTraceWriter.write(frame: frame) }
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
    var programSource: ProgramSource = .userProgram  // prSourceFlag decoded (see ProgramSource)
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

// MARK: - Bridge conversion (Shared/DebugSnapshots.hpp → SwiftUI view model)

extension LiveDebugSnapshot.StepEntry {
    init(_ e: TIStepEntry) {
        self.init(stepNum: e.stepNum, keycode: e.keycode, mnemonic: e.mnemonic, isCurrent: e.isCurrent)
    }
}

extension LiveDebugSnapshot {
    init(_ t: TILiveDebugSnapshot) {
        self.init()
        nonZeroRegs = t.nonZeroRegs.map { RegEntry(num: $0.num, value: $0.value, isHidden: $0.isHidden) }
        dataRegCount = t.dataRegCount
        programRegCount = t.programRegCount
        programWindow = t.programWindow.map(StepEntry.init)
        currentStep = t.currentStep
        nextStepNum = t.nextStepNum
        nextStepKeycode = t.nextStepKeycode
        nextStepMnemonic = t.nextStepMnemonic
        let h = t.hir.map(\.doubleValue)
        (hir1, hir2, hir3, hir4, hir5, hir6, hir7, hir8) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
        tRegister = t.tRegister
        calcFlags = t.calcFlags.map(\.boolValue)
        fixIndicator = t.fixIndicator
        ioUserFlags = t.ioUserFlags
        lastKey = t.lastKey
        fA = t.fA
        fB = t.fB
        engIndicator = t.engIndicator
        secondIndicator = t.secondIndicator
        invIndicator = t.invIndicator
        angleMode = [AngleMode.deg, .rad, .grad].indices.contains(t.angleMode) ? [AngleMode.deg, .rad, .grad][t.angleMode] : nil
        prSourceFlag = t.prSourceFlag
        programSource = ProgramSource(raw: t.programSource)
        pendingOpsCount = t.pendingOpsCount
        scomRows = t.scomRows
        printerSCOM = Array(scomRows.prefix(4))
        returnAddress = t.returnAddress
        returnAddressSourceFlags = [UInt8](t.returnAddressSourceFlags)
        returnAddresses = t.returnAddresses.map(\.intValue)
    }
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


