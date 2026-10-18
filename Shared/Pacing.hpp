#pragma once
#include "../Core/TI59Machine.hpp"
#include "FreezeController.hpp"
#include "MachineModelInfo.hpp"
#include <cstdint>

// Real-time pacing of the run loop (reference/AppArchitecture.md § "Emulation
// Loop and Timing"): 20 ms batches of the model's instruction rate, cycle-
// weighted — TMC0501::step() returns 4 for an IDLE step (1 on the TI-58C,
// which runs at constant speed) — with the overshoot carried into the next
// batch so the long-term rate stays exact. The loop sleeps out the rest of
// each 20 ms unless full speed is on.

namespace cu59 {

inline constexpr double kBatchSeconds = 0.020;

/// Weighted cycles per batch: instructionHz × 20 ms (≈ 284 on the TI-59).
inline int32_t batchTargetCycles(Model model) {
    return static_cast<int32_t>(info(model).instructionHz * kBatchSeconds);
}

struct BatchResult {
    enum class Stop { None, Breakpoint, Freeze };
    Stop stop = Stop::None;
    FreezeOwner freezeOwner = FreezeOwner::Cpu;  ///< for Stop::Freeze
    /// A step this batch was a confirmed spin-wait retrying a keyboard scan or
    /// printer BUSY test (step() bit 30) — real-world state that full speed
    /// must not race through.
    bool polledHardware = false;
};

/// Run one batch, continuing from `carry` (the previous batch's overshoot).
/// Stops early on a breakpoint (step() bit 31) or an armed freeze firing.
BatchResult runBatch(TI59Machine& m, int32_t& carry, int32_t targetCycles, FreezeController& freeze);

/// Whether to sleep out the rest of the batch. Full speed skips it — except
/// while the CPU sits in the scan/key-detect range or the batch polled
/// hardware, which always run at regular speed: racing them would execute an
/// unbounded number of idle iterations before anything notices the CPU is
/// idle (and inflate elapsed-time measurements across that window).
bool shouldSleep(bool fullSpeed, uint16_t pc, bool polledHardware, Model model);

} // namespace cu59
