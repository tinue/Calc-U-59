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
    var raw: Int { Self.cases.firstIndex(of: self)! }
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
    /// True while the user presses the display or a KEYSTROKES FullSpeed: window is
    /// open; emulation runs unrestricted (Shared/Pacing.cpp shouldSleep). Mirrors the
    /// session, which also changes it during playback (sessionFullSpeedChanged).
    var isFullSpeedMode: Bool = false {
        didSet {
            guard isFullSpeedMode != oldValue, session?.fullSpeed != isFullSpeedMode else { return }
            session?.fullSpeed = isFullSpeedMode
        }
    }
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
                let success = traceWriter?.open() ?? false

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
                guard machine != nil else { return }

                // a) Stop generating events (unless another consumer still needs them)
                updateDebugTraceFlags()

                // b) Drain remaining buffer on main thread immediately
                drainTraceEvents()

                // c) Close file
                traceWriter?.close()
            }
        }
    }
    /// The manual trace (the "C" indicator toggle): its location; the session writes it.
    /// The scripted KEYSTROKES "Trace:" capture is the session's own second writer.
    private var traceWriter: TraceWriter?
    private var isTraceLocationAvailable = true
    var isTraceAvailable: Bool { traceWriter?.isAvailable ?? isTraceLocationAvailable }  // false if trace location (e.g., iCloud) unavailable
    private var isScriptedTraceOpen = false

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
        didSet {
            session?.frozen = freezeReason != nil
            updateDebugTraceFlags()
        }
    }
    var isFrozen: Bool { freezeReason != nil }
    var freezeOwner: FreezePanel? = nil  // set on freeze entry, cleared on unfreeze
    /// Freeze as soon as the calculator PC changes. Armed in the session's
    /// FreezeController (Shared/); this mirrors it for the UI.
    var pendingFreezeOnPCChange: Bool = false {
        didSet {
            guard pendingFreezeOnPCChange != oldValue else { return }
            if !pendingFreezeOnPCChange { session?.disarmPcChange() }
            updateDebugTraceFlags()
        }
    }

    // CPU-tab "Freeze on Start": fires when the keyboard scan loop exits (key press or reset).
    // Distinct from pendingFreezeOnPCChange (CALCULATOR tab: fires on any PC change).
    var pendingCPUScanLoopFreeze: Bool = false {
        didSet {
            guard pendingCPUScanLoopFreeze != oldValue else { return }
            if !pendingCPUScanLoopFreeze { session?.disarmScanLoopExit() }
            updateDebugTraceFlags()
        }
    }

    // Full program listing — always kept current (not just when frozen).
    // Updated at 60 Hz by buildLiveSnapshot when running, and after each STEP/freeze-entry when frozen.
    var programListing: [LiveDebugSnapshot.StepEntry] = []
    var programListingSource: ProgramSource = .userProgram   // Prg Source the listing was built for

    private var lastLibProgramMismatch: Int = .min  // throttles SCOM[9] cross-check logging

    // ── Live CPU view state (60 Hz real-time, runs while emulating) ────────────
    var cpuDebugSnapshot: CPUDebugSnapshot = .empty

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
        let flags = TISession.traceFlags(forCpuPanel: cpuDebugEnabled, frozen: isFrozen, manualTrace: cIndicatorDebug,
                                         freezeArmed: pendingFreezeOnPCChange || pendingCPUScanLoopFreeze,
                                         scriptedTrace: isScriptedTraceOpen, breakpoints: !breakpoints.isEmpty)
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
    var cpuInspectorHistory: [InspectorSnapshot] = []  // the trace ring + the next instruction
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

    /// The running calculator and its runtime (run loop, freezes, keys, frames,
    /// traces): Shared/EmulatorSession via Bridge/TISession. One per machine.
    private var session: TISession?
    private var machine: TI59MachineWrapper? { session?.machine }
    @ObservationIgnored private lazy var sessionEvents = SessionEventForwarder(self)
    private var displayTimer: Timer?
    /// Held for the app's lifetime so macOS never App-Naps the background emulation
    /// queue while the window is unfocused/occluded — App Nap can otherwise stall
    /// emulation thread's step() loop entirely, freezing currentPC and making any PC-range
    /// wait (e.g. waitForScanLoopIdle) return immediately instead of actually waiting.
    private var appNapActivityToken: NSObjectProtocol?
    private var suspendedByLifecycle = false
    private static let constantMemoryFileName = "ti58c.mem"
    private static var constantMemoryURL: URL {
        CardStorage.directoryURL.appendingPathComponent(constantMemoryFileName)
    }
    @ObservationIgnored private var persistPending = false  // set from the emulation thread
    private var persistDebounceTimer: Timer?
    private var programCheckTimer: Timer?
    private var debugDisplayTimer: Timer?

    init() {
        appNapActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "TI-59 CPU emulation must keep running at real-time pace in the background"
        )
        // Check trace availability at startup (for iOS/iPadOS iCloud detection, etc.)
        isTraceLocationAvailable = TraceWriter.checkAvailability()
        Task { await self.start(model: AppSettings.resolvedStartupModel()) }
    }

    /// Which cue card shows (Shared/CueCard resolveCueCard): the active library
    /// program's card, a generic card with the module's metadata, or the user's.
    private func resolvedCueCard() -> CueCardContent? {
        var cards: [NSNumber: TICueCard] = [:]
        for (n, card) in moduleCueCards { cards[NSNumber(value: n)] = card.bridged }
        return TIViewRules.resolveCueCard(forProgram: activeProgramNumber, moduleCards: cards,
                                          moduleTitle: moduleMetadata.title, moduleID: moduleMetadata.id,
                                          userCard: userCueCardContent?.bridged).swiftValue
    }

    func start(model: MachineModel) async {
        persistConstantMemory()  // save TI-58C RAM before switching away
        stop()
        await drainEmulation()   // ensure old loop has exited before starting the new one
        cIndicatorDebug = false  // the manual trace belongs to the old session
        self.model = model
        // A fresh machine is created below; the printer's TRACE latch is released
        // on a model change (the new core instance starts with it off).
        printerTrace = false
        userCueCardContent = nil
        activeProgramNumber = 0
        cueCardContent = nil  // clear cuecard when switching models
        UserDefaults.standard.set(model.rawValue, forKey: SettingsKey.lastUsedModel)
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                CardStorage.warmUp()
                continuation.resume()
            }
        }
        do {
            // ROM, constants and the solid-state module: Shared/EmulatorSession.
            let moduleFile = ROMLoader.moduleRomFile(moduleID: selectedModuleID)
            let newSession = try TISession(model: model.rawValue, reader: ROMLoader.bundleReader,
                                           moduleRomFile: moduleFile, delegate: sessionEvents)
            let wrapper = newSession.machine
            session = newSession
            traceWriter = TraceWriter(model: model, writer: newSession.manualTrace)
            configureScriptedTraceLocation()

            debugModel = TIDebugModel(model: model.rawValue)
            if moduleFile == nil || newSession.moduleImage.isEmpty {
                Self.logger.error("Solid-state module library was not loaded; continuing without library data")
                cacheModuleImage(nil)
            } else {
                cacheModuleImage(newSession.moduleImage)
            }
            let (cards, metadata) = ROMLoader.loadModuleCardsAndMetadata(moduleID: self.selectedModuleID)
            moduleCueCards = cards
            moduleMetadata = metadata

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

    /// Start the paced run loop (Shared/EmulationRunner).
    private func startEmulationLoop() {
        session?.start()
    }

    /// Where KEYSTROKES "Trace:" files go, and the session size limit.
    private func configureScriptedTraceLocation() {
        let maxMB = UserDefaults.standard.integer(forKey: SettingsKey.traceMaxFileSizeMB)
        session?.setTraceDirectory(AppSettings.traceDirectory().path,
                                   maxBytes: UInt64(maxMB > 0 ? maxMB : 50) * 1_000_000)
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
        let detectedProgram = TIViewRules.activeLibraryProgram(machine.snapshotCPU())
        if detectedProgram != activeProgramNumber {
            activeProgramNumber = detectedProgram
            cueCardContent = resolvedCueCard()
        }
    }

    private func tick() {
        guard let session, let machine else { return }

        // Printer, core log, card auto-eject, display hold rule and the C indicator:
        // Shared/FrameSampler.cpp.
        let frame = session.tick(withDebugLevel: debugLevel.rawValue, cardSwiping: cardState == .swiping)

        // Auto-eject: the core ejects the card at CRD_OFF (as the real card leaves the
        // reader after each pass).  Save any written data.
        if frame.cardAutoEjected {
            ejectCard()
        }
        if !frame.printerLines.isEmpty {
            printerLines.append(contentsOf: frame.printerLines)
        }
        if !frame.logLines.isEmpty {
            debugModel.logWriteAll(frame.logLines)
        }

        // Debounce TI-58C persist: schedule write if pending and timer not already running
        if persistPending && persistDebounceTimer == nil {
            persistDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                self?.performPersistWrite()
                self?.persistDebounceTimer = nil
            }
        }

        if !frame.printerCodeLines.isEmpty {
            printerCodeLines.append(contentsOf: frame.printerCodeLines)
        }

        // Guard each assignment: @Observable notifies on every write, even of an
        // identical value; the guards prevent 60 Hz re-renders of a static display.
        if frame.displayUpdated {
            let snap = frame.display
            var d = [UInt8](repeating: 0, count: 12)
            var c = [UInt8](repeating: 0, count: 12)
            withUnsafeBytes(of: snap.digits) { b in for i in 0..<12 { d[i] = b[i] } }
            withUnsafeBytes(of: snap.ctrl)   { b in for i in 0..<12 { c[i] = b[i] } }
            if displayDigits    != d               { displayDigits    = d }
            if displayCtrl      != c               { displayCtrl      = c }
            if displaySuppressedMask != snap.suppressedMask { displaySuppressedMask = snap.suppressedMask }
            if dpPos            != snap.dpPos      { dpPos            = snap.dpPos }
            if dpAfterglowMask  != snap.dpAfterglowMask { dpAfterglowMask = snap.dpAfterglowMask }
        }
        if calcIndicatorOpacity != frame.calcIndicatorOpacity { calcIndicatorOpacity = frame.calcIndicatorOpacity }

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

        // Drain the trace ring here at 60 Hz for both writers (the 1024-frame ring
        // would otherwise overflow during a scripted Trace: spanning a Wait:).
        if cIndicatorDebug || isScriptedTraceOpen {
            drainTraceEvents()
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
        session?.stop()
        invalidateAllTimers()
    }

    /// Suspend emulation when the app enters the background.
    /// Stops the CPU loop and display timer to prevent battery drain.
    /// Does not destroy machine state — resumeFromBackground() will restart both.
    func suspendForBackground() {
        persistConstantMemory()
        suspendedByLifecycle = session?.isRunning ?? false
        session?.stop()
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
    private func drainEmulation() async {
        guard let session else { return }
        await withCheckedContinuation { continuation in
            session.post { continuation.resume() }
        }
    }

    // MARK: - Key input

    // Keys go through the session (Shared/EmulatorSession, KeySequencer): it logs
    // them to the manual trace and owns the timed input — KEYSTROKES playback and
    // the physical keyboard's hold rules.

    func pressKey(row: Int, col: Int) {
        session?.pressKey(UInt8((row + 1) * 10 + (col + 1)))
    }

    func releaseKey(row: Int, col: Int) {
        session?.releaseKey(UInt8((row + 1) * 10 + (col + 1)))
    }

    // MARK: - Physical keyboard input

    /// The key a physical-keyboard press is currently holding down, as
    /// `row * 5 + col`, so `KeyboardView` can show it depressed exactly as it
    /// does for a pointer press. Nil when no keyboard key is down.
    var keyboardHeldKey: Int? = nil

    /// A physical key went down, resolved to one or two matrix codes by
    /// `Shared/KeyboardMap.cpp`. A single code is held until `keyboardKeyUp()`
    /// (at least 100 ms); a 2nd + key pair plays as two taps.
    func keyboardKeyDown(_ codes: [UInt8]) {
        session?.keyboardDown(Data(codes))
    }

    func keyboardKeyUp() {
        session?.keyboardUp()
    }

    /// Force-release whatever the keyboard is holding — used when the calculator
    /// view loses focus or is torn down, so a matrix bit can't stay stuck set.
    func keyboardRelease() {
        session?.keyboardRelease()
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
        guard let session else {
            Self.logger.error("Cannot apply module \(id, privacy: .public): machine is not initialized")
            return
        }
        if let file = ROMLoader.moduleRomFile(moduleID: id), session.loadModule(file, reader: ROMLoader.bundleReader) {
            cacheModuleImage(session.moduleImage)
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
        session?.cancelKeystrokes()
        unfreeze()  // exit freeze mode when resetting
        asmOverlayActive = false
        cardState = .noCard
        userCueCardContent = nil
        activeProgramNumber = 0
        cueCardContent = resolvedCueCard()
        // The printer's TRACE button is a physical hardware latch — a calculator
        // reset does not release it.  The core preserves it across reset(); it is
        // released only on printer attach/detach or model change.
        // Reset; TI-58C restores its persisted memory, the others clear the
        // registers past the partition (Shared/StateApplier softReset).
        if let m = machine {
            let saved = model.hasConstantMemory ? loadConstantMemory() : nil
            TIViewRules.softReset(m, model: model.rawValue, savedRam: saved)
        }
        resetHeatmapBaseline()
        debugModel.logWrite("Calculator Reset")
    }

    /// Clean reset (all models): zero all RAM, then reset.
    /// For TI-58C, writes the zeroed state immediately to the save file.
    func cleanResetMachine() {
        session?.cancelKeystrokes()
        unfreeze()  // exit freeze mode when resetting
        asmOverlayActive = false
        cardState = .noCard
        userCueCardContent = nil
        activeProgramNumber = 0
        cueCardContent = resolvedCueCard()
        // Zero all RAM, then reset (Shared/StateApplier cleanReset). TRACE is a
        // physical latch — the core preserves it across reset.
        if let m = machine { TIViewRules.cleanReset(m) }
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
        traceWriter?.writeCardInsert()
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
        traceWriter?.writeCardEject()
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
        guard let session, let m = machine else { return }
        session.post { [weak self, m] in
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
        guard let session, let m = machine else { return }
        session.post { [weak self, m] in
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
        session?.armPcChange()
        pendingFreezeOnPCChange = true
    }

    /// Arm the CPU-tab "Freeze on Start": fires when the keyboard scan loop exits.
    /// Scan loop ranges: TI-59/58 = 0x063C–0x0658, TI-58C = 0x063D–0x0A2E.
    /// Trigger conditions: (a) PC was inside loop and exits (key press or reset while idle),
    /// or (b) PC jumps to 0x0000 while outside the loop (reset during program execution),
    /// or (c) an ASM overlay run succeeds (runASMOverlay checks this flag on success).
    func freezeOnScanLoopExit() {
        // Mutex: disarm CALCULATOR any-PC-change freeze if active
        pendingFreezeOnPCChange = false
        session?.armScanLoopExit()
        pendingCPUScanLoopFreeze = true
    }

    func disarmCPUScanLoopFreeze() {
        pendingCPUScanLoopFreeze = false
    }

    /// Freeze with an explicit panel owner (called by the FREEZE button in each panel).
    func freeze(from panel: FreezePanel) {
        freezeOwner = panel
        freeze()
    }

    func freeze(reason: FreezeReason = .manual, waitForKeycode: Bool = true) {
        session?.stop()
        freezeReason = reason
        asmOverlayActive = false
        pendingFreezeOnPCChange = false   // Cancel any pending CALCULATOR freeze
        pendingCPUScanLoopFreeze = false  // Cancel any pending CPU scan-loop freeze
        guard let session, let m = machine else { return }
        // Advance to the next keycode boundary on the emulation thread (runs after the
        // running loop exits: the session's job queue is serial). Then capture state.
        session.post { [weak self, m] in
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
        guard let session, let m = machine else { return }
        session.post { [weak self, m] in
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
        // The trace ring (read, not drained) plus the certain next instruction —
        // shown even at the same PC (WAIT/KEY loops): Shared/DebugSnapshots.
        cpuInspectorHistory = TIViewRules.inspectorHistory(m).map(InspectorSnapshot.init)

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

        // Accumulate ROM heatmap hits into the local buffer (every tick, cheap).
        // seqno prevents double-counting frames across non-destructive readCpuFrames calls.
        debugModel.heatmapIngest(framesNS)
        // Publish to @Observable at ~10 Hz (every 6 ticks) to keep display refresh unaffected.
        if debugModel.heatmapPublishTick() {
            romHitCount = debugModel.heatmapCounts.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        }

        // The last 32 instructions (Shared/DebugSnapshots recentInstructions).
        snap.recentInstructions = TIViewRules.recentInstructions(framesNS, count: 32).map {
            CPUDebugSnapshot.Instruction(pc: $0.pc, opcode: $0.opcode, disasm: $0.disasm, frame: $0.frame)
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

        session?.stop()
        isPausedOnBreakpoint = false
        breakpointPC = nil
        pendingFreezeOnPCChange = false
        let freezeOnASMStart = pendingCPUScanLoopFreeze  // capture before clearing
        pendingCPUScanLoopFreeze = false
        clearFrozenState()

        var steps: UInt32 = 0
        var ok = false
        var loaded: ObjCBool = true

        // Wait until any in-flight step batch finishes, then run the injection
        // (park at a keycode boundary, load, enter at 0x1800: Shared/AsmOverlay.cpp).
        let data = asmOverlayWords.withUnsafeBufferPointer { Data(buffer: $0) }
        session?.sync {
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
                // session.sync above already completed; no running loop to drain.
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

        // Validate the partition against self.model, which is now guaranteed to reflect
        // the target model (model switch via start(model:) completes before this is called).
        if let error = TIFileFormats.partitionError(for: parsed.parsed, model: model.rawValue) {
            errorTitle = "State file load error"
            errorMessage = error
            return
        }

        session?.stop()
        // Clear freeze state without restarting the loop
        clearFrozenState()
        // Synchronous dispatch ensures the emulation loop has fully exited
        // before we touch RAM or SCOM.  Without this, a step() in-flight on
        // the emulation thread could write stale values after our state-file writes.
        session?.sync {}

        guard let m = machine else { return }

        // Clear program state: when loading a state file, no program should be active.
        // This ensures that the loaded custom cue card (or nil) is displayed, not a leftover program card.
        activeProgramNumber = 0

        // Reset, ROM power-on routine, partition, RAM, program, registers:
        // Shared/StateApplier.cpp.
        session?.sync { TIFileFormats.applyState(parsed.parsed, to: m, model: self.model.rawValue) }

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
            playKeystrokes(parsed)
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
        session?.stop()
        clearFrozenState()
        session?.sync {}

        guard let m = machine else { return }

        // Partition (if explicit), program (if present) and registers only:
        // Shared/StateApplier.cpp.
        session?.sync { TIFileFormats.applySkipResetState(parsed.parsed, to: m, model: self.model.rawValue) }

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
            playKeystrokes(parsed)
        }
    }

    // MARK: - Keystroke playback

    /// Play back a KEYSTROKES sequence after a preset loads (Shared/KeySequencer):
    /// keys held 100 ms, each waiting for the CPU to reach the keyboard-scan idle
    /// loop; Wait:/WaitFullSpeed:/FullSpeed:/Trace:/elapse events. Progress comes
    /// back through the TISessionDelegate methods below.
    private func playKeystrokes(_ parsed: LoadStateResult) {
        configureScriptedTraceLocation()
        session?.playKeystrokes(of: parsed.parsed)
    }

    // ── Binary trace files ───────────────────────────────────────────────────
    // The session drains the CPU ring into both writers (manual and scripted).
    // Called from tick() (main thread, 60 Hz) and when the manual trace stops.

    private func drainTraceEvents() {
        var manualLimit: ObjCBool = false
        var scriptedLimit: ObjCBool = false
        session?.drainTraceManualLimit(&manualLimit, scriptedLimit: &scriptedLimit)
        if manualLimit.boolValue {
            traceWriter?.didReachSizeLimit()
            // Defer to avoid reentrance via cIndicatorDebug's didSet.
            DispatchQueue.main.async { [weak self] in self?.cIndicatorDebug = false }
        }
        if scriptedLimit.boolValue {
            print("WARNING: scripted trace reached its size limit — trace stopped.")
            isScriptedTraceOpen = false
            updateDebugTraceFlags()
        }
    }
}

// MARK: - Session events (session threads → main)

/// TISessionDelegate needs an NSObject; @Observable classes can't be one.
/// Forwards to the view model, which the session never retains.
final class SessionEventForwarder: NSObject, TISessionDelegate {
    weak var target: EmulatorViewModel?
    init(_ target: EmulatorViewModel) { self.target = target }
    func sessionBreakpointHit(_ pc: UInt16) { target?.sessionBreakpointHit(pc) }
    func sessionFreezeFired(_ owner: Int) { target?.sessionFreezeFired(owner) }
    func sessionHeldKeyChanged(_ highlightID: Int) { target?.sessionHeldKeyChanged(highlightID) }
    func sessionFullSpeedChanged(_ on: Bool) { target?.sessionFullSpeedChanged(on) }
    func sessionPlaybackStarted() { target?.sessionPlaybackStarted() }
    func sessionPlaybackFinished() { target?.sessionPlaybackFinished() }
    func sessionTogglePrinterTrace() { target?.sessionTogglePrinterTrace() }
    func sessionLogLine(_ line: String) { target?.sessionLogLine(line) }
    func sessionScriptedTraceFailed(_ fileName: String) { target?.sessionScriptedTraceFailed(fileName) }
    func sessionScriptedTraceChanged(_ open: Bool) { target?.sessionScriptedTraceChanged(open) }
    func sessionBatchDone() { target?.sessionBatchDone() }
}

extension EmulatorViewModel {
    func sessionBreakpointHit(_ pc: UInt16) {
        DispatchQueue.main.async { [weak self] in self?.onBreakpointHit(pc: pc) }
    }

    /// An armed freeze fired; the run loop has stopped. Owner 0 = CPU panel
    /// (FREEZE ON START), 1 = CALCULATOR panel (next PC change).
    func sessionFreezeFired(_ owner: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let m = self.machine else { return }
            self.freezeOwner = owner == 0 ? .cpu : .calculator
            // Set freezeReason before clearing the armed flags so updateDebugTraceFlags()
            // keeps tracing enabled throughout.
            self.freezeReason = .manual
            self.pendingCPUScanLoopFreeze = false
            self.pendingFreezeOnPCChange = false
            if owner == 0 {
                if self.liveDebugEnabled { self.liveDebugSnapshot = self.buildLiveSnapshot(machine: m) }
            } else {
                m.beginNextStep()
                self.liveDebugSnapshot = self.buildLiveSnapshot(machine: m)
            }
            self.captureInspectorSnapshot(machine: m)
        }
    }

    func sessionHeldKeyChanged(_ highlightID: Int) {
        DispatchQueue.main.async { [weak self] in self?.keyboardHeldKey = highlightID >= 0 ? highlightID : nil }
    }

    func sessionFullSpeedChanged(_ on: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isFullSpeedMode != on else { return }
            self.isFullSpeedMode = on
        }
    }

    func sessionPlaybackStarted() {
        DispatchQueue.main.async { [weak self] in self?.isKeystrokesPlaying = true }
    }

    func sessionPlaybackFinished() {
        DispatchQueue.main.async { [weak self] in self?.isKeystrokesPlaying = false }
    }

    func sessionTogglePrinterTrace() {
        DispatchQueue.main.async { [weak self] in self?.togglePrinterTrace() }
    }

    func sessionLogLine(_ line: String) {
        DispatchQueue.main.async { [weak self] in self?.ringWriteAll([line]) }
    }

    func sessionScriptedTraceFailed(_ fileName: String) {
        print("[EmulatorViewModel] KEYSTROKES \"Trace: \(fileName)\" failed to open trace file in \(AppSettings.traceDirectory().path)")
    }

    func sessionScriptedTraceChanged(_ open: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isScriptedTraceOpen = open
            self.updateDebugTraceFlags()
        }
    }

    /// After every run-loop batch: mark TI-58C state for the debounced persist.
    func sessionBatchDone() {
        if model.hasConstantMemory { persistPending = true }
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

extension EmulatorViewModel.InspectorSnapshot {
    init(_ e: TIInspectorEntry) {
        self.init(pc: e.pc, opcode: e.opcode, disasm: e.disasm, frame: e.frame, isHistory: e.isHistory, isCurrent: e.isCurrent)
    }
}

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


