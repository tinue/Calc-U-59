#pragma once
#include "../Core/TI59Machine.hpp"
#include "StateFile.hpp"
#include <optional>
#include <string>

// Writes a parsed state file into a machine: partition, program and
// registers (see reference/AppArchitecture.md § "State File Loading"). The
// frontend owns everything around it — stopping its run loop first, model
// switches, module and printer changes, the cue card, KEYSTROKES playback.

namespace cu59 {

/// Why a file can't be applied to `model`, or nullopt. Only an explicit
/// partition beyond 479 on the 60-register models is rejected.
std::optional<std::string> stateFilePartitionError(const LoadStateResult& r, Model model);

/// Full load: reset, run the ROM's power-on routine to idle, set the
/// partition (default 239 on the TI-58/58C when the file gives none), clear
/// RAM (keeping the TI-58C's extra registers, whose RAM[60] the ROM needs),
/// write the program zero-padded to the model's physical capacity, then the
/// registers. Run on the emulation thread with the run loop stopped.
void applyState(TI59Machine& m, const LoadStateResult& r, Model model);

/// SKIP-RESET load: the partition only if the file sets it explicitly, the
/// program only if it has one, and the registers — nothing else is touched.
void applySkipResetState(TI59Machine& m, const LoadStateResult& r, Model model);

/// The Reset button: reset the CPU (the printer's TRACE latch survives, as on
/// the hardware). TI-58C: restore its constant memory if `savedRam` is given;
/// other models: clear the registers beyond the current data partition.
void softReset(TI59Machine& m, Model model, const std::vector<uint8_t>* savedRam);

/// Clean reset (all models): zero all RAM, then reset.
void cleanReset(TI59Machine& m);

} // namespace cu59
