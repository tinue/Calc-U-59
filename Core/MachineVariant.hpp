#pragma once

/// Machine variant enumeration for TI-58/59 family.
enum class MachineVariant { TI59, TI58, TI58C };

/// TI-58C only: external RAM chip (TMC0599) provides constant memory that
/// survives power-off.  Also governs MEMRD/MEMWR instruction decoding, ROM
/// loading, and printer-detection digit (KP.D10 vs KP.D0).
inline bool hasConstantMemory(MachineVariant v) { return v == MachineVariant::TI58C; }

/// TI-59 only: full 120-register RAM, magnetic card reader.  Governs data-
/// register addressing, accessible memory size, and state-file handling.
/// TI-58 and TI-58C both use 60 registers and lack a card reader.
inline bool hasLargeMemory(MachineVariant v) { return v == MachineVariant::TI59; }

/// Ceramic resonator frequency in Hz; ÷ 2 (two-phase) ÷ 16 (digit-serial) is the
/// instruction rate. TI-59 455 kHz, TI-58 384 kHz, ±1% (TP0240 clock chip,
/// http://www.datamath.org/Chips/TP0240.htm; the service manual names 455 kHz
/// and allows the TI-58 a 384 kHz part, "the preferred part"). TI-58C 400 kHz:
/// PHI1/PHI2 measured at 200 kHz on a real TI-58C, which also matches its filmed
/// error blink (0.896 s).
constexpr double resonatorHz(MachineVariant v) {
    return v == MachineVariant::TI59 ? 455000.0 : v == MachineVariant::TI58 ? 384000.0 : 400000.0;
}
