#pragma once

// How the runtime (EmulationRunner, KeySequencer) gets its time slices.
// Threads: its own threads, as the Swift and Qt apps run it. Cooperative: no
// threads at all; the frontend's 60 Hz SessionController::tick() pumps the run
// loop and the key lanes on its own thread — the web build, which has no
// threads (GitHub Pages can't send the headers SharedArrayBuffer needs), and
// tests on virtual time. See reference/SharedArchitecture.md § "Threads".

namespace cu59 {

enum class Threading { Threads, Cooperative };

/// Throws std::logic_error when `t` is Threads in a build without threads.
void requireThreadSupport(Threading t);

} // namespace cu59
