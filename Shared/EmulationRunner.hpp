#pragma once
#include "../Core/TI59Machine.hpp"
#include "FreezeController.hpp"
#include "Pacing.hpp"
#include "Threading.hpp"
#include <atomic>
#include <chrono>
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
//
// With Threading::Cooperative there is no thread: pump(now), called at 60 Hz
// from the frontend's thread, runs the batches due by `now` and the jobs
// queued after the loop stopped, in the same order the thread would.

namespace cu59 {

class EmulationRunner {
public:
    using Clock = std::chrono::steady_clock;

    struct Callbacks {
        std::function<void(FreezeOwner)> freezeFired;     ///< loop stopped by an armed freeze
        std::function<void()> batchDone;                  ///< after every batch (TI-58C persist debounce)
        /// Cooperative: the clock that ends a full-speed slice (tests inject one).
        std::function<Clock::time_point()> wallClock = [] { return Clock::now(); };
        /// Seeds the batch-end jitter (BatchJitter; tests fix it).
        uint32_t jitterSeed = std::random_device{}();
    };

    /// Cooperative: how long one pump() may run batches back to back at full speed.
    static constexpr std::chrono::milliseconds kFullSpeedSlice{10};

    EmulationRunner(TI59Machine& m, Model model, FreezeController& freeze, Callbacks callbacks,
                    Threading threading = Threading::Threads);
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
    /// Cooperative: runs the queued jobs, then `job`, inline.
    void sync(const std::function<void()>& job);

    /// Cooperative only: run the batches due by `now` (regular speed), or
    /// batches for up to kFullSpeedSlice (full speed), then the jobs queued
    /// behind a stopped loop. `afterBatch` gets the time each batch ends at.
    void pump(Clock::time_point now, const std::function<void(Clock::time_point)>& afterBatch);

private:
    void threadMain();
    void runLoop();
    /// Stopped: the batch stopped the loop (breakpoint, armed freeze).
    /// Paced: sleep out the rest of the batch. Unpaced: go on at once.
    enum class BatchEnd { Stopped, Paced, Unpaced };
    BatchEnd runOneBatch(int32_t& carry);
    /// Cooperative: run queued jobs up to a running loop (an empty job marks it).
    void drainJobs();

    TI59Machine& m_machine;
    const Model m_model;
    FreezeController& m_freeze;
    Callbacks m_callbacks;
    std::atomic<bool> m_running{false};
    std::atomic<bool> m_fullSpeed{false};
    const Threading m_threading;
    BatchJitter m_jitter;  // emulation thread (Cooperative: pump()'s caller)

    // Cooperative run loop state.
    int32_t m_carry = 0;
    Clock::time_point m_deadline{};
    bool m_draining = false;

    std::mutex m_mutex;
    std::condition_variable m_cv;
    std::deque<std::function<void()>> m_jobs;
    bool m_quit = false;
    std::thread m_thread;
};

} // namespace cu59
