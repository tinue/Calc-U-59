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
    /// Also governs MEMRD/MEMWR instruction decoding and ROM loading.
    var hasConstantMemory: Bool { self == .ti58c }

    /// TI-59 only: full 120-register RAM.
    /// Governs data-register addressing, accessible memory size, and state loading.
    var hasLargeMemory: Bool { self == .ti59 }

    /// Only the TI-59 has a magnetic card reader slot.
    var hasCardReader: Bool { self == .ti59 }

    /// TI-58C only: count of *extra* constant-memory registers beyond the normal
    /// 60 addressable data registers (0 for TI-59/TI-58). These are not normal
    /// registers "60"–"63" — STO/RCL can never reach them, they can't be program
    /// steps, and they don't participate in partitioning. Call them E000…E00n
    /// when referring to them as RAM storage, H00…H0n when referring to them as
    /// state-file/debugger variables. See `reference/CoreArchitecture.md` §
    /// "TI-58C Extra (Constant Memory) Registers".
    var extraRegisterCount: Int { hasConstantMemory ? 4 : 0 }

    /// Raw RAM index where the extra registers begin (TI-58C only). Fixed at 60
    /// regardless of total RAM size — it sits directly above the 60 registers
    /// TI-58C shares with the TI-58, addressed there by the ROM's MEMWR/MEMRD
    /// instructions (not by STO/RCL, which only ever reach 00–59 on this variant).
    static let extraRegisterBase = 60
}
