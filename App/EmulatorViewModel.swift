import Foundation
import os
import SwiftUI

/// Which debug panel owns the current freeze.
/// RESUME and STEP are only enabled in the owning panel; the other panel's buttons are
/// disabled while frozen to prevent cross-panel confusion (e.g. CALCULATOR STEP while
/// frozen in CPU would silently resume until the next keycode boundary).
enum FreezePanel { case cpu, calculator }

/// Selected tab in the debug pane. Stored on EmulatorViewModel so the
/// selection survives navigation on iPhone (where DebugView is recreated).
enum DebugTab { case live, cpu, log }

/// SessionController::DebugLevel (cycled there).
enum DebugLevel: Int {
    case off   = 0
    case info  = 1
    case debug = 2
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
    /// visible only when the CPU is single-stepped; STEP stops at the step
    /// dispatch, outside it.
    case solidStateReturn
    /// 2, 4 or 6 anywhere else: a RAM program on the sub-program fast path —
    /// no display formatting, no R/S or GTO polls.
    case fastMode
    /// Bit 3 set, bit 0 clear (8 official): keycode sub-program in the
    /// constant ROM.
    case rom

    /// Decoded by Shared/ModuleImage.cpp (programSourceFrom).
    init(flag: UInt8, romPC: UInt16) {
        self = Self.cases[TIViewRules.programSource(forFlag: flag, romPC: romPC)]
    }

    /// TIViewRules / TILiveDebugSnapshot raw values follow the C++ enumerator order.
    init(raw: Int) { self = Self.cases[raw] }
    var raw: Int { Self.cases.firstIndex(of: self)! }
    private static let cases: [ProgramSource] = [.userProgram, .solidState, .solidStateReturn, .fastMode, .rom]
}
/// The SwiftUI face of Shared/SessionController (the Qt app's is
/// Qt6/app/EmulatorController): implements its platform — the main thread,
/// iCloud card storage and ti58c.mem, UserDefaults, error alerts — runs its
/// 60 Hz tick and copies what changed into observable properties. Everything
/// that isn't UI state lives in Shared/ — see CLAUDE.md § "Frontend Parity".
@Observable
class EmulatorViewModel {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Calc-U-59", category: "EmulatorViewModel")

    var displayDigits:   [UInt8] = Array(repeating: 0, count: 12)
    var displayCtrl:     [UInt8] = Array(repeating: 0, count: 12)
    var displayLevels:   [UInt8] = Array(repeating: 0, count: 12)  // brightness 0…255 per position
    var dpLevels:        [UInt8] = Array(repeating: 0, count: 12)  // decimal point brightness per position
    var calcIndicatorOpacity: Double = 0.0
    var model: MachineModel = .ti59
    var errorMessage: String?
    /// Title shown alongside `errorMessage` in the alert.
    var errorTitle: String = "ROM load error"

    // ── Display interaction state ────────────────────────────────────────────
    var isDisplayPressed: Bool = false
    /// True while the user presses the display or a KEYSTROKES FullSpeed: window is
    /// open; emulation runs unrestricted (Shared/Pacing.cpp shouldSleep).
    var isFullSpeedMode: Bool = false {
        didSet { if controller.fullSpeed != isFullSpeedMode { controller.fullSpeed = isFullSpeedMode } }
    }
    var isKeystrokesPlaying: Bool = false

    // ── Printer state ────────────────────────────────────────────────────────
    var printerLines: [String] = []
    var printerCodeLines: [PrinterCodeLine] = []  // parallel to printerLines
    var printerClearID: Int = 0   // incremented on cut to reset Text identity and drop selection
    var printerTrace: Bool = false
    var printerConnected: Bool = true

    // ── Binary trace (the "C" indicator toggle) ──────────────────────────────
    var cIndicatorDebug: Bool = false {
        didSet {
            guard controller.manualTrace != cIndicatorDebug else { return }
            controller.setManualTrace(cIndicatorDebug)
            if controller.manualTrace != cIndicatorDebug { cIndicatorDebug = controller.manualTrace }  // could not open
        }
    }
    /// False if the trace location (e.g. iCloud) is unavailable at startup.
    private(set) var isTraceAvailable = AppSettings.traceLocationAvailable()

    // ── Debug panel state ────────────────────────────────────────────────────
    var debugTab: DebugTab = .live   // persists tab selection across iPhone navigation
    var debugLevel: DebugLevel = .off
    var debugClearID: Int = 0              // incremented on clear to reset Text identity
    var debugDisplayText: String = ""      // LOG pane text, refreshed at 1 Hz
    var asmFileName: String = "No file selected"
    var asmWordCount: Int = 0
    var asmStatusMessage: String = "Load a hex opcode file and press Run."
    var canRunASM: Bool { asmWordCount > 0 }
    var asmOverlayActive: Bool = false

    // ── Live debug panels ────────────────────────────────────────────────────
    // Both flags track panel visibility (LiveDebugView / CPUInspectorView
    // onAppear/onDisappear). While false the snapshots aren't built and the
    // core runs with tracing off — its zero-overhead fast path.
    var liveDebugEnabled: Bool = false {
        didSet { if liveDebugEnabled != oldValue { controller.setLiveDebugEnabled(liveDebugEnabled) } }
    }
    var cpuDebugEnabled: Bool = false {
        didSet { if cpuDebugEnabled != oldValue { controller.setCpuDebugEnabled(cpuDebugEnabled) } }
    }
    var liveDebugSnapshot: LiveDebugSnapshot = .empty
    private(set) var isFrozen: Bool = false
    private(set) var freezeOwner: FreezePanel? = nil
    /// CALCULATOR "FREEZE ON START": freeze before the next program step. Setting it to
    /// false (the ARMED button) disarms it.
    var pendingFreezeOnPCChange: Bool = false {
        didSet { if !pendingFreezeOnPCChange && controller.pcChangeArmed { controller.disarmPcChange() } }
    }
    /// CPU "FREEZE ON START": freeze when the keyboard scan loop exits.
    var pendingCPUScanLoopFreeze: Bool = false {
        didSet { if !pendingCPUScanLoopFreeze && controller.scanLoopExitArmed { controller.disarmScanLoopExit() } }
    }

    /// The whole program of the source last shown (frozen PROGRAM STEPS view).
    var programListing: [LiveDebugSnapshot.StepEntry] = []
    var programListingSource: ProgramSource = .userProgram
    private(set) var programListingCurrentIndex: Int = -1

    // ── CPU tab ──────────────────────────────────────────────────────────────
    struct InspectorSnapshot {
        var pc: UInt16
        var opcode: UInt16
        var disasm: String
        var frame: TICpuFrame
        var isHistory: Bool  // true = executed, false = the predicted next instruction
        var isCurrent: Bool  // the newest (running) or where it froze
    }
    /// Running: the newest 32 instructions; frozen: the trace ring plus the next.
    var cpuHistory: [InspectorSnapshot] = []
    var cpuHistoryUpdateID: Int = 0  // incremented on every cpuHistory change
    /// ROM heatmap (5 120 code addresses 0x0000–0x13FF), published at ~10 Hz.
    var romHitCount: [UInt32] = Array(repeating: 0, count: 0x1400)

    // ── Card reader state ────────────────────────────────────────────────────
    enum CardState: Equatable {
        case noCard      // Nothing selected
        case swiping     // Card is passing through; I/O in progress
    }
    var cardState: CardState = .noCard
    var cardPickerMode: CardPickerView.Mode? = nil
    /// `true` when a card file exists on disk.
    var hasCardFile: Bool = false
    /// Display name of the last card file loaded.
    var cardFileName: String = "card.U59"

    // ── Cue card and module ──────────────────────────────────────────────────
    var cueCardContent: CueCardContent? = nil
    var selectedModuleID: String = AppSettings.resolvedSolidStateModuleID()

    /// The key a physical-keyboard press is holding down (`row * 5 + col`), so
    /// `KeyboardView` shows it depressed as for a pointer press.
    var keyboardHeldKey: Int? = nil

    // ── The calculator (Shared/SessionController via Bridge/TISessionController)
    @ObservationIgnored private lazy var platform = PlatformForwarder(self)
    @ObservationIgnored private lazy var controller = TISessionController(
        reader: ROMLoader.bundleReader, cuecards: ROMLoader.cuecardsText,
        moduleID: AppSettings.resolvedSolidStateModuleID(), platform: platform)
    private var displayTimer: Timer?
    /// Held for the app's lifetime so macOS never App-Naps the background emulation
    /// queue while the window is unfocused/occluded — App Nap can otherwise stall the
    /// emulation thread's step() loop entirely.
    private var appNapActivityToken: NSObjectProtocol?
    private static let constantMemoryFileName = "ti58c.mem"
    fileprivate static var constantMemoryURL: URL {
        CardStorage.directoryURL.appendingPathComponent(constantMemoryFileName)
    }

    init() {
        appNapActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "TI-59 CPU emulation must keep running at real-time pace in the background"
        )
        Task { await self.start(model: AppSettings.resolvedStartupModel()) }
    }

    /// Build a fresh machine of `model` (the previous one keeps running on a ROM error).
    func start(model: MachineModel) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                CardStorage.warmUp()
                continuation.resume()
            }
        }
        if controller.startMachine(model.rawValue) {
            hasCardFile = CardStorage.hasCard
        }
        startDisplayRefresh()
    }

    private func startDisplayRefresh() {
        // On the main run loop, so the timer fires whichever thread calls this.
        displayTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.controller.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    /// Suspend emulation when the app enters the background (persists TI-58C RAM);
    /// a debug freeze survives.
    func suspendForBackground() {
        controller.suspend()
        displayTimer?.invalidate()
        displayTimer = nil
    }

    func resumeFromBackground() {
        guard controller.hasMachine else { return }
        startDisplayRefresh()
        controller.resumeAfterSuspend()
    }

    // MARK: - Keys
    // Keys go through the session (Shared/KeySequencer): it logs them to the
    // manual trace and owns the timed input — KEYSTROKES playback and the
    // physical keyboard's hold rules.

    func pressKey(row: Int, col: Int) { controller.pressKey(TISharedTables.matrixCode(row: row, col: col)) }
    func releaseKey(row: Int, col: Int) { controller.releaseKey(TISharedTables.matrixCode(row: row, col: col)) }

    /// A physical key went down, resolved to one or two matrix codes by
    /// `Shared/KeyboardMap.cpp`. A single code is held until `keyboardKeyUp()`
    /// (at least 100 ms); a 2nd + key pair plays as two taps.
    func keyboardKeyDown(_ codes: [UInt8]) { controller.keyboardDown(Data(codes)) }
    func keyboardKeyUp() { controller.keyboardUp() }
    /// Force-release whatever the keyboard is holding — used when the calculator
    /// view loses focus or is torn down, so a matrix bit can't stay stuck set.
    func keyboardRelease() { controller.keyboardRelease() }

    // MARK: - Printer

    func pressPrinterPrint(_ pressed: Bool) { controller.pressPrinterPrint(pressed) }
    func pressPrinterAdv(_ pressed: Bool) { controller.pressPrinterAdv(pressed) }
    func togglePrinterTrace() { controller.togglePrinterTrace() }
    func togglePrinterConnection() { controller.togglePrinterConnection() }
    func cutPaper() { controller.cutPaper() }
    /// The strip's height in dot pitches (Shared pairs text and dot lines).
    var printerStripHeightUnits: Double { controller.printerStripHeightUnits }

    // MARK: - Module, reset

    /// Change the solid-state module and perform a soft reset (preserves RAM); no-op if unchanged.
    func changeModule(id: String) { controller.changeModule(id) }

    func resetMachine() { controller.resetMachine() }
    /// Clean reset (all models): zero all RAM, then reset.
    func cleanResetMachine() { controller.cleanResetMachine() }

    // MARK: - Magnetic card reader

    func ejectIfSwiping() {
        if cardState == .swiping { ejectCard() }
    }

    func insertBlankCard(savingTo url: URL) {
        controller.insertBlankCard(url.path, fileName: url.lastPathComponent)
    }

    func insertCard(from url: URL) {
        // A courtesy for URLs that may be security-scoped (our own iCloud container's aren't).
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        controller.insertCard(try? Data(contentsOf: url), path: url.path, fileName: url.lastPathComponent)
    }

    func ejectCard() { controller.ejectCard() }

    // MARK: - Debugger

    func freeze(from panel: FreezePanel) { controller.freeze(panel == .cpu ? .cpu : .calculator) }
    func unfreeze() { controller.resume() }
    func freezeOnNextPCChange() { controller.armPcChange() }
    func freezeOnScanLoopExit() { controller.armScanLoopExit() }
    func disarmCPUScanLoopFreeze() { controller.disarmScanLoopExit() }
    /// STEP in the CALCULATOR panel: one keycode.
    func stepKeycode() { controller.stepKeycode() }
    /// STEP in the CPU panel: one instruction (through a HOLD).
    func stepFrozen() { controller.stepInstruction() }

    func clearRomHeatmap() { controller.clearHeatmap() }

    func toggleDebug() { controller.cycleDebugLevel() }

    func clearDebug() {
        controller.clearLog()
        debugClearID &+= 1
    }

    // Dumps for the LOG tab (formats: Shared/DebugLog.cpp).
    func debugDumpVars() { controller.dumpVars() }
    func debugDumpSCOM() { controller.dumpScom() }
    func debugDumpProg() { controller.dumpProg() }
    func debugDumpMemory() { controller.dumpMemory() }

    func loadASMOverlayFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        controller.loadAsm(try? String(contentsOf: url, encoding: .utf8), fileName: url.lastPathComponent)
    }

    func runASMOverlay() { controller.runAsm() }
    func clearASMOverlay() { controller.clearAsm() }

    // MARK: - State files

    func loadStateFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        controller.loadStateFile(try? Data(contentsOf: url))
    }

    // MARK: - Changes from the controller

    /// Copy what changed into the observable properties. Each assignment is
    /// guarded: @Observable notifies on every write, even of an identical value.
    fileprivate func apply(_ c: TIChange) {
        if c.contains(.model) {
            if let m = MachineModel(rawValue: controller.model), m != model { model = m }
            if selectedModuleID != controller.moduleID { selectedModuleID = controller.moduleID }
        }
        if c.contains(.display) {
            let snap = controller.display
            let d = withUnsafeBytes(of: snap.digits) { Array($0) }
            let k = withUnsafeBytes(of: snap.ctrl) { Array($0) }
            let lv = withUnsafeBytes(of: snap.digitLevel) { Array($0) }
            let dp = withUnsafeBytes(of: snap.dpLevel) { Array($0) }
            if displayDigits != d { displayDigits = d }
            if displayCtrl != k { displayCtrl = k }
            if displayLevels != lv { displayLevels = lv }
            if dpLevels != dp { dpLevels = dp }
            if calcIndicatorOpacity != controller.calcIndicatorOpacity { calcIndicatorOpacity = controller.calcIndicatorOpacity }
        }
        if c.contains(.cueCard) { cueCardContent = controller.cueCard.swiftValue }
        if c.contains(.paperCut) {
            printerLines = []
            printerCodeLines = []
            printerClearID &+= 1
        }
        if c.contains(.printer) {
            // Append what's new (text and dot codes arrive independently; .paperCut cleared above).
            if controller.printerLineCount > printerLines.count {
                printerLines.append(contentsOf: controller.printerLines(from: printerLines.count))
            }
            if controller.printerCodeLineCount > printerCodeLines.count {
                printerCodeLines.append(contentsOf: controller.printerCodeLines(from: printerCodeLines.count).map { PrinterCodeLine($0) })
            }
            if printerTrace != controller.printerTrace { printerTrace = controller.printerTrace }
            if printerConnected != controller.printerConnected { printerConnected = controller.printerConnected }
        }
        if c.contains(.card) || c.contains(.model) {
            let state: CardState = controller.cardSwiping ? .swiping : .noCard
            if cardState != state { cardState = state }
            if cardFileName != controller.cardFileName { cardFileName = controller.cardFileName }
        }
        if c.contains(.runState) {
            if isFrozen != controller.frozen { isFrozen = controller.frozen }
            let owner: FreezePanel? = switch controller.freezeOwner {
            case .cpu: .cpu
            case .calculator: .calculator
            default: nil
            }
            if freezeOwner != owner { freezeOwner = owner }
            if pendingFreezeOnPCChange != controller.pcChangeArmed { pendingFreezeOnPCChange = controller.pcChangeArmed }
            if pendingCPUScanLoopFreeze != controller.scanLoopExitArmed { pendingCPUScanLoopFreeze = controller.scanLoopExitArmed }
            if isFullSpeedMode != controller.fullSpeed { isFullSpeedMode = controller.fullSpeed }
            if isKeystrokesPlaying != controller.keystrokesPlaying { isKeystrokesPlaying = controller.keystrokesPlaying }
            let held: Int? = controller.heldKey >= 0 ? controller.heldKey : nil
            if keyboardHeldKey != held { keyboardHeldKey = held }
        }
        if c.contains(.live) {
            let snap = LiveDebugSnapshot(controller.liveSnapshot)
            if snap != liveDebugSnapshot { liveDebugSnapshot = snap }
        }
        if c.contains(.listing) {
            programListing = controller.programListing.map { LiveDebugSnapshot.StepEntry($0) }
            programListingSource = ProgramSource(raw: controller.programListingSource)
            programListingCurrentIndex = controller.programListingCurrentIndex
        }
        if c.contains(.cpu) {
            cpuHistory = controller.cpuHistory.map { InspectorSnapshot($0) }
            cpuHistoryUpdateID &+= 1
        }
        if c.contains(.heatmap) {
            romHitCount = controller.heatmapCounts.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        }
        if c.contains(.log) {
            if debugDisplayText != controller.logText { debugDisplayText = controller.logText }
            let level = DebugLevel(rawValue: controller.debugLevel) ?? .off
            if debugLevel != level { debugLevel = level }
        }
        if c.contains(.asm) {
            if asmFileName != controller.asmFileName { asmFileName = controller.asmFileName }
            if asmWordCount != controller.asmWordCount { asmWordCount = controller.asmWordCount }
            if asmStatusMessage != controller.asmStatus { asmStatusMessage = controller.asmStatus }
            if asmOverlayActive != controller.asmActive { asmOverlayActive = controller.asmActive }
        }
        if c.contains(.trace), cIndicatorDebug != controller.manualTrace { cIndicatorDebug = controller.manualTrace }
    }

    fileprivate func showError(title: String, message: String) {
        errorTitle = title
        errorMessage = message
    }

    fileprivate func cardWritten() { hasCardFile = CardStorage.hasCard }

    fileprivate static func diagnostic(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }
}

// MARK: - Platform (Shared/SessionController ↔ app)

/// TIPlatform needs an NSObject; @Observable classes can't be one. All calls
/// arrive on the main thread.
final class PlatformForwarder: NSObject, TIPlatform {
    weak var target: EmulatorViewModel?
    init(_ target: EmulatorViewModel) { self.target = target }

    func readConstantMemory() -> String? {
        var data: Data?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: EmulatorViewModel.constantMemoryURL, options: [], error: &err) { src in
            data = try? Data(contentsOf: src)
        }
        return data.flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Off the main thread: iCloud writes can block.
    func writeConstantMemory(_ text: String) {
        let url = EmulatorViewModel.constantMemoryURL
        DispatchQueue.global(qos: .background).async {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func cardFilePath(_ fileName: String) -> String {
        CardStorage.directoryURL.appendingPathComponent(fileName).path
    }

    func writeCard(_ text: String, toPath path: String) -> Bool {
        guard let fileData = text.data(using: .utf8) else { return false }
        let url = URL(fileURLWithPath: path)
        var coordinatorError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { writingURL in
            do { try fileData.write(to: writingURL, options: .atomic) } catch { writeError = error }
        }
        guard coordinatorError == nil, writeError == nil else { return false }
        target?.cardWritten()
        return true
    }

    var traceDirectory: String { AppSettings.traceDirectory().path }
    var traceMaxBytes: UInt64 { UInt64(AppSettings.resolvedTraceMaxMB()) * 1_000_000 }
    var traceAvailable: Bool { AppSettings.traceLocationAvailable() }

    func saveLastUsedModel(_ model: Int) { UserDefaults.standard.set(model, forKey: SettingsKey.lastUsedModel) }
    func saveModuleID(_ moduleID: String) { UserDefaults.standard.set(moduleID, forKey: SettingsKey.solidStateModuleID) }
    func showErrorTitle(_ title: String, message: String) { target?.showError(title: title, message: message) }
    func diagnostic(_ message: String) { EmulatorViewModel.diagnostic(message) }
    func changed(_ changes: TIChange) { target?.apply(changes) }
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

    // HIR registers (stored in SCOM[1..8]; decoded as Double)
    // Each HIR is 16 BCD nibbles: bits 15–3 = mantissa, 2–1 = exponent, 0 = sign
    var hir: [Double] = Array(repeating: 0, count: 8)  // HIR 1–8

    // T register (SCOM[11]; decoded as Double; stack top / last-X equivalent)
    var tRegister: Double = 0
    var xValue: Double = 0
    var xRaw: String = ""              // X's register as "C=…"/"A=…" when it holds no number

    // Calculator flags 0–9 (stored in SCOM; bit mapping TBD experimentally)
    var calcFlags: [Bool] = Array(repeating: false, count: 10)

    // SCOM[0] fields
    var fixIndicator: String = "0"      // Nibble 15 (FIX = value - 2 mod 10)
    var statusRegister: String = "0000000000000000"  // Whole register (HIR 0), nibble 15 first
    var fA: UInt16 = 0                  // FA register (debug display)
    var fB: UInt16 = 0                  // FB register (debug display)
    var engIndicator: String = ""       // "Eng" if FB bit 3 (of 3rd digit) is set, else empty
    var secondIndicator: String = ""    // "2nd" if FA bit 1 is set, else empty
    var invIndicator: String = ""       // "INV" if FA bit 0 is set, else empty

    // Calculator-level status (from SCOM)
    var angleMode: Int = -1  // TILiveDebugSnapshot.angleMode: -1 unknown, 0 DEG, 1 RAD, 2 GRAD

    // SCOM-derived control state
    var prSourceFlag: UInt8 = 0   // Program Source Flag (SCOM[0] nibble 3)
    var programSource: ProgramSource = .userProgram  // prSourceFlag decoded (see ProgramSource)
    var pendingOpsCount: Int = 0  // Number of pending operations in hierarchy stack (SCOM 13)

    // All 16 SCOM rows
    var scomRows: [String] = []

    // Return address stack (from SCOM[14:15]) — 6 levels of subroutine return addresses
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
        programWindow = t.programWindow.map { StepEntry($0) }
        currentStep = t.currentStep
        hir = t.hir.map(\.doubleValue)
        tRegister = t.tRegister
        xValue = t.xValue
        xRaw = t.xRaw
        calcFlags = t.calcFlags.map(\.boolValue)
        fixIndicator = t.fixIndicator
        statusRegister = t.statusRegister
        fA = t.fA
        fB = t.fB
        engIndicator = t.engIndicator
        secondIndicator = t.secondIndicator
        invIndicator = t.invIndicator
        angleMode = t.angleMode
        prSourceFlag = t.prSourceFlag
        programSource = ProgramSource(raw: t.programSource)
        pendingOpsCount = t.pendingOpsCount
        scomRows = t.scomRows
        returnAddressSourceFlags = [UInt8](t.returnAddressSourceFlags)
        returnAddresses = t.returnAddresses.map(\.intValue)
    }
}

