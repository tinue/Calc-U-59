import Foundation

// Parsed .ti59 / .ti58 / .ti58c state file, as the view model consumes it.
// The format is specified in reference/StateFileFormat.md and parsed by
// Shared/StateFile.cpp; these types are filled from its bridge result.

/// What the view model handles itself; partition, program and registers stay
/// in `parsed` and are written by Shared/StateApplier.
struct LoadStateResult {
    /// KEYSTROKES section present; playback runs from `parsed` in the session.
    var hasKeystrokes = false
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
        hasKeystrokes = r.hasKeystrokes
        cueCardContent = r.cueCard.swiftValue
        solidStateModuleID = r.solidStateModuleID
        printerConnected = r.printerConnected?.boolValue
        model = MachineModel(rawValue: r.model)
        skipReset = r.skipReset
        errors = r.errors
    }
}
