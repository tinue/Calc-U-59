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
