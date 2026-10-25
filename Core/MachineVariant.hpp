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

/// Clock oscillator frequency in Hz; ÷ 2 (two-phase) ÷ 16 (digit-serial) is the
/// instruction rate. TI-59 455 kHz, TI-58 384 kHz, ±1% ceramic resonators
/// (TP0240 clock chip, http://www.datamath.org/Chips/TP0240.htm; the service
/// manual names 455 kHz and allows the TI-58 a 384 kHz part, "the preferred
/// part"). The TI-58C has no clock chip and no resonator: its clock comes
/// from the oscillator built into a TMC0580 DSCOM (CD2400 or CD2401), set by
/// external R/C parts (http://www.datamath.org/Chips/TMC0580.htm;
/// reference/CoreArchitecture.md, "TI-58C clock"). Its rate varies by unit;
/// 394 kHz here is one real TI-58C's clock, from its error blinks; the
/// emulator matches that unit's instruction counts exactly, but its rate
/// wanders ~0.8% between sessions and other units run at PHI 194.7-200 kHz.
/// Compare real timings at the unit's clock of the day (reference/
/// CoreArchitecture.md, "TI-58C clock"; tests/core_tests.cpp).
constexpr double resonatorHz(MachineVariant v) {
    switch (v) {
    case MachineVariant::TI59: return 455000.0;
    case MachineVariant::TI58: return 384000.0;
    case MachineVariant::TI58C: return 394000.0;
    }
    return 455000.0;
}

/// Instructions/sec in active (RUN) mode: resonatorHz() ÷ 2 (two-phase) ÷ 16 (digit-serial).
constexpr double instructionHz(MachineVariant v) { return resonatorHz(v) / 32; }
