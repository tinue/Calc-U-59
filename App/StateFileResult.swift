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

/// What the view model handles itself; partition, program and registers stay
/// in `parsed` and are written by Shared/StateApplier.
struct LoadStateResult {
    var keystrokes: [KeystrokeEvent] = []
    var cueCardContent: CueCardContent? = nil
    var solidStateModuleID: String? = nil
    var printerConnected: Bool? = nil
    /// MODEL: TI-59 / TI-58 / TI-58C — switches the machine variant before applying state.
    var model: MachineModel? = nil
    /// SKIP-RESET: on — skip machine reset; apply only PROGRAM/REGISTERS/PARTITION/CUECARD/KEYSTROKES.
    var skipReset: Bool = false
    var errors: [String] = []
    /// The bridge result, handed back to Shared/StateApplier when the file is applied.
    let parsed: TIStateFileResult

    /// Parse a state file. maxStepAddr bounds step-number prefixes;
    /// allowHiddenRegisters admits H00–H03 (TI-58C).
    init(parsing text: String, maxStepAddr: Int, allowHiddenRegisters: Bool) {
        let r = TIFileFormats.parseStateFile(text, maxStepAddr: maxStepAddr, allowHiddenRegisters: allowHiddenRegisters)
        parsed = r
        keystrokes = r.keystrokes.map(KeystrokeEvent.init)
        cueCardContent = r.cueCard.swiftValue
        solidStateModuleID = r.solidStateModuleID
        printerConnected = r.printerConnected?.boolValue
        model = MachineModel(rawValue: r.model)
        skipReset = r.skipReset
        errors = r.errors
    }
}
