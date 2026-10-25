#include "EmulationRunner.hpp"
#include <future>

namespace cu59 {

namespace {

const auto kBatch = std::chrono::duration_cast<EmulationRunner::Clock::duration>(std::chrono::duration<double>(kBatchSeconds));
// A stall longer than this (debugger stop, App Nap, a hidden browser tab)
// restarts the schedule instead of bursting to catch up.
constexpr auto kMaxLag = std::chrono::milliseconds(100);

/// The batch due at `deadline` is late by more than kMaxLag: start over at `now`.
bool lagging(EmulationRunner::Clock::time_point deadline, EmulationRunner::Clock::time_point now) {
    return now - deadline > kMaxLag;
}

} // namespace

EmulationRunner::EmulationRunner(TI59Machine& m, Model model, FreezeController& freeze, Callbacks callbacks,
                                 Threading threading)
    : m_machine(m), m_model(model), m_freeze(freeze), m_callbacks(std::move(callbacks)), m_threading(threading),
      m_jitter(batchTargetCycles(model), m_callbacks.jitterSeed) {
    requireThreadSupport(threading);
    if (threading == Threading::Threads) m_thread = std::thread([this] { threadMain(); });
}

EmulationRunner::~EmulationRunner() {
    m_running = false;
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_quit = true;
    }
    m_cv.notify_all();
    if (m_thread.joinable()) m_thread.join();
}

void EmulationRunner::start() {
    if (m_running.exchange(true)) return;
    if (m_threading == Threading::Cooperative) {
        m_carry = 0;
        m_jitter.reset();
        m_deadline = {};  // lagging: pump() starts the schedule at its `now`
        post(nullptr);
    } else {
        post([this] { runLoop(); });
    }
}

void EmulationRunner::post(std::function<void()> job) {
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_jobs.push_back(std::move(job));
    }
    m_cv.notify_all();
}

void EmulationRunner::sync(const std::function<void()>& job) {
    if (m_threading == Threading::Cooperative) {
        if (!m_draining) drainJobs();
        job();
        return;
    }
    if (std::this_thread::get_id() == m_thread.get_id()) {
        job();
        return;
    }
    std::promise<void> done;
    auto future = done.get_future();
    post([&] {
        job();
        done.set_value();
    });
    future.wait();
}

void EmulationRunner::threadMain() {
    for (;;) {
        std::function<void()> job;
        {
            std::unique_lock<std::mutex> lock(m_mutex);
            m_cv.wait(lock, [this] { return m_quit || !m_jobs.empty(); });
            if (m_quit) return;
            job = std::move(m_jobs.front());
            m_jobs.pop_front();
        }
        job();
    }
}

EmulationRunner::BatchEnd EmulationRunner::runOneBatch(int32_t& carry) {
    BatchResult r = runBatch(m_machine, carry, m_jitter.next(), m_freeze);
    if (r.stop == BatchResult::Stop::Breakpoint) {  // Core breakpoints are set by headless tools only
        m_running = false;
        return BatchEnd::Stopped;
    }
    if (r.stop == BatchResult::Stop::Freeze) {
        m_running = false;
        if (m_callbacks.freezeFired) m_callbacks.freezeFired(r.freezeOwner);
        return BatchEnd::Stopped;
    }
    return shouldSleep(m_fullSpeed, m_machine.pc(), r.polledHardware, m_model) ? BatchEnd::Paced
                                                                                : BatchEnd::Unpaced;
}

void EmulationRunner::runLoop() {
    // Absolute deadlines: each batch is due 20 ms after the previous one, so
    // oversleep and callback time are paid back by a shorter next sleep. Timing
    // each batch from a fresh now() (as before) lost both every batch — about
    // 17% of real time on macOS. A full-speed batch restarts the schedule.
    int32_t carry = 0;
    m_jitter.reset();
    auto deadline = Clock::now();
    while (m_running) {
        deadline += kBatch;
        const BatchEnd end = runOneBatch(carry);
        if (end == BatchEnd::Stopped) return;
        if (end == BatchEnd::Paced) {
            auto now = Clock::now();
            if (lagging(deadline, now)) deadline = now;
            else std::this_thread::sleep_until(deadline);
        } else {
            deadline = Clock::now();
        }
        if (m_callbacks.batchDone) m_callbacks.batchDone();
    }
}

void EmulationRunner::drainJobs() {
    m_draining = true;
    for (;;) {
        std::function<void()> job;
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            if (m_jobs.empty()) break;
            if (!m_jobs.front()) {  // the run loop: jobs behind it wait until it stops
                if (m_running) break;
                m_jobs.pop_front();
                continue;
            }
            job = std::move(m_jobs.front());
            m_jobs.pop_front();
        }
        job();
    }
    m_draining = false;
}

// The same schedule as runLoop, with the sleeps replaced by returning: a batch
// is due once its start time has passed.
void EmulationRunner::pump(Clock::time_point now, const std::function<void(Clock::time_point)>& afterBatch) {
    if (m_threading != Threading::Cooperative) return;
    drainJobs();
    bool loopActive;
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        loopActive = m_running && !m_jobs.empty() && !m_jobs.front();
    }
    if (loopActive) {
        if (lagging(m_deadline, now)) m_deadline = now;
        const auto sliceEnd = m_callbacks.wallClock() + kFullSpeedSlice;
        while (m_running && m_deadline <= now) {
            const BatchEnd end = runOneBatch(m_carry);
            if (end == BatchEnd::Stopped) break;
            const bool paced = end == BatchEnd::Paced;
            if (paced) m_deadline += kBatch;
            if (m_callbacks.batchDone) m_callbacks.batchDone();
            if (afterBatch) afterBatch(paced ? m_deadline : now);
            if (!paced && m_callbacks.wallClock() >= sliceEnd) {
                m_deadline = now;  // full speed: go on at the next pump
                break;
            }
        }
    }
    drainJobs();
}

} // namespace cu59
