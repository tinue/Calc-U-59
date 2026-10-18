import Foundation

// Parsed .ti59 / .ti58 / .ti58c state file, as the view model consumes it.
// The format is specified in reference/StateFileFormat.md and parsed by
// Shared/StateFile.cpp; these types are filled from its bridge result.

/// A single event in the KEYSTROKES section.
enum KeystrokeEvent {
    case key(UInt8)                  // matrix code to press (row*10 + col, row 1–9, col 1–5)
    case toggleTrace                 // virtual: toggle the emulated printer's TRACE latch (file token: 99)
    case wait(TimeInterval)          // explicit pause; emulator runs at normal speed
    case waitFullSpeed(TimeInterval) // enable full speed, wait, then restore normal speed
    case trace(String?)              // start CPU trace capture to the given filename, or stop it (nil) — unrelated to .toggleTrace
    case fullSpeed                   // persistent: switch to full speed until a matching .regularSpeed (or end of script)
    case regularSpeed                // persistent: switch back to normal speed
    case zeroElapseTime              // snapshot the core's elapsed-tick counter as the report baseline
    case reportElapseTime            // report elapsed time since the last .zeroElapseTime to the debug log

    /// TIKeystrokeEvent.kind follows the C++ KeystrokeEvent::Kind order.
    init(_ e: TIKeystrokeEvent) {
        switch e.kind {
        case 0: self = .key(e.code)
        case 1: self = .toggleTrace
        case 2: self = .wait(e.seconds)
        case 3: self = .waitFullSpeed(e.seconds)
        case 4: self = .trace(e.traceName)
        case 5: self = .fullSpeed
        case 6: self = .regularSpeed
        case 7: self = .zeroElapseTime
        default: self = .reportElapseTime
        }
    }
}

struct LoadStateResult {
    var partitionMaxStep: Int = 479
    /// True when the file contained an explicit PARTITION: line; false = default was used.
    var partitionWasExplicit: Bool = false
    /// Sparse list of (stepAddress, keycode) pairs. Steps not listed default to 0x00.
    var programSteps: [(stepAddr: Int, keycode: UInt8)] = []
    /// `regNum` is the user-facing number as written in the file: 00–99 for a
    /// normal register, 00–03 for an extra (H-prefixed, TI-58C-only) register.
    /// `isHidden` disambiguates the two — do NOT infer it from `regNum`'s
    /// range, since normal TI-59 registers legitimately go up to 99.
    var registers: [(regNum: Int, nibbles: [UInt8], isHidden: Bool)] = []
    var keystrokes: [KeystrokeEvent] = []
    var cueCardContent: CueCardContent? = nil
    var solidStateModuleID: String? = nil
    var printerConnected: Bool? = nil
    /// MODEL: TI-59 / TI-58 / TI-58C — switches the machine variant before applying state.
    var model: MachineModel? = nil
    /// SKIP-RESET: on — skip machine reset; apply only PROGRAM/REGISTERS/PARTITION/CUECARD/KEYSTROKES.
    var skipReset: Bool = false
    var errors: [String] = []

    /// Parse a state file. maxStepAddr bounds step-number prefixes;
    /// allowHiddenRegisters admits H00–H03 (TI-58C).
    init(parsing text: String, maxStepAddr: Int, allowHiddenRegisters: Bool) {
        let r = TIFileFormats.parseStateFile(text, maxStepAddr: maxStepAddr, allowHiddenRegisters: allowHiddenRegisters)
        partitionMaxStep = r.partitionMaxStep
        partitionWasExplicit = r.partitionWasExplicit
        programSteps = zip(r.programStepAddrs, r.programStepKeycodes).map { (stepAddr: $0.intValue, keycode: $1) }
        registers = r.registers.map { (regNum: $0.regNum, nibbles: [UInt8]($0.nibbles), isHidden: $0.isHidden) }
        keystrokes = r.keystrokes.map(KeystrokeEvent.init)
        cueCardContent = r.cueCard.swiftValue
        solidStateModuleID = r.solidStateModuleID
        printerConnected = r.printerConnected?.boolValue
        model = MachineModel(rawValue: r.model)
        skipReset = r.skipReset
        errors = r.errors
    }
}
