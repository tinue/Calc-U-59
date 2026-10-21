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
/// and allows the TI-58 a 384 kHz part, "the preferred part"). The TI-58C is
/// assumed to use the TI-58's part: one real TI-58C measured PHI 194.7 kHz
/// (389.4 kHz) and blinks to match, another blinks as at 400 kHz; neither is
/// a known part. Real measurements are compared after normalising the unit's
/// clock from its error blink (tests/core_tests.cpp).
constexpr double resonatorHz(MachineVariant v) {
    return v == MachineVariant::TI59 ? 455000.0 : 384000.0;
}

/// Instructions/sec in active (RUN) mode: resonatorHz() ÷ 2 (two-phase) ÷ 16 (digit-serial).
constexpr double instructionHz(MachineVariant v) { return resonatorHz(v) / 32; }
