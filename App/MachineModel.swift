import Foundation

/// Selects which calculator variant to emulate.
///
/// All three share the same TMC0501 CPU core and the same 6144-word ROM
/// (TMC0582 + TMC0583 program chips plus the TMC0571 SCOM constant table at
/// 0x1400–0x17FF, present on all variants).  Differences are accessible RAM
/// size and a handful of hardware details (card-switch column, constant memory).
enum MachineModel: Int, CaseIterable, Identifiable {
    case ti59  = 0
    case ti58  = 1
    case ti58c = 2

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .ti59:  return "TI-59"
        case .ti58:  return "TI-58"
        case .ti58c: return "TI-58C"
        }
    }

    var romWordCount: Int { 6144 }

    /// Digit-counter column that the card-detect switch occupies in the key matrix.
    /// TI-59 uses column 10; TI-58/58C use column 7.  The CPU reads this column
    /// via TST BUSY to detect whether a card is present in the reader slot.
    var cardSwitchCol: Int {
        switch self {
        case .ti59:         return 10
        case .ti58, .ti58c: return 7
        }
    }

    /// TI-58C only: RAM contents survive power-off (persisted to UserDefaults).
    var hasConstantMemory: Bool { self == .ti58c }

    /// Only the TI-59 has a magnetic card reader slot.
    var hasCardReader: Bool { self == .ti59 }
}
