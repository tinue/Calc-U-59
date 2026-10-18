#pragma once
#include "../Core/TI59Machine.hpp"
#include "FreezeController.hpp"
#include "Pacing.hpp"
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <mutex>
#include <thread>

// The emulation thread: a serial job queue (like a serial dispatch queue)
// whose long-running job is the paced run loop. Everything that steps the
// machine while it isn't running — warm-up, freeze-to-keycode, single steps,
// ASM overlay entry — is posted here too, so it runs after the loop has
// exited and never concurrently with it. Callbacks run on this thread;
// frontends hop to their UI thread.

namespace cu59 {

class EmulationRunner {
public:
    struct Callbacks {
        std::function<void(FreezeOwner)> freezeFired;     ///< loop stopped by an armed freeze
        std::function<void()> batchDone;                  ///< after every batch (TI-58C persist debounce)
    };

    EmulationRunner(TI59Machine& m, Model model, FreezeController& freeze, Callbacks callbacks);
    ~EmulationRunner();
    EmulationRunner(const EmulationRunner&) = delete;
    EmulationRunner& operator=(const EmulationRunner&) = delete;

    /// Queue the run loop (no-op if already running).
    void start();
    /// Ask the loop to exit after the current batch; returns at once.
    void stop() { m_running = false; }
    bool isRunning() const { return m_running.load(); }

    void setFullSpeed(bool on) { m_fullSpeed = on; }
    bool fullSpeed() const { return m_fullSpeed.load(); }

    /// Queue a job (after the run loop has exited, if it is running).
    void post(std::function<void()> job);
    /// Queue a job and wait for it. Stop the loop first, or this waits for it.
    /// Called from the emulation thread itself, the job runs inline.
    void sync(const std::function<void()>& job);

private:
    void threadMain();
    void runLoop();

    TI59Machine& m_machine;
    const Model m_model;
    FreezeController& m_freeze;
    Callbacks m_callbacks;
    std::atomic<bool> m_running{false};
    std::atomic<bool> m_fullSpeed{false};

    std::mutex m_mutex;
    std::condition_variable m_cv;
    std::deque<std::function<void()>> m_jobs;
    bool m_quit = false;
    std::thread m_thread;
};

} // namespace cu59
