#include "EmulationRunner.hpp"
#include <chrono>
#include <future>

namespace cu59 {

EmulationRunner::EmulationRunner(TI59Machine& m, Model model, FreezeController& freeze, Callbacks callbacks)
    : m_machine(m), m_model(model), m_freeze(freeze), m_callbacks(std::move(callbacks)) {
    m_thread = std::thread([this] { threadMain(); });
}

EmulationRunner::~EmulationRunner() {
    m_running = false;
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_quit = true;
    }
    m_cv.notify_all();
    m_thread.join();
}

void EmulationRunner::start() {
    if (m_running.exchange(true)) return;
    post([this] { runLoop(); });
}

void EmulationRunner::post(std::function<void()> job) {
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_jobs.push_back(std::move(job));
    }
    m_cv.notify_all();
}

void EmulationRunner::sync(const std::function<void()>& job) {
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

void EmulationRunner::runLoop() {
    using Clock = std::chrono::steady_clock;
    const int32_t target = batchTargetCycles(m_model);
    const auto batch = std::chrono::duration_cast<Clock::duration>(std::chrono::duration<double>(kBatchSeconds));
    // Absolute deadlines: each batch is due 20 ms after the previous one, so
    // oversleep and callback time are paid back by a shorter next sleep. Timing
    // each batch from a fresh now() (as before) lost both every batch — about
    // 17% of real time on macOS. A stall longer than kMaxLag (debugger stop,
    // App Nap) or a full-speed batch restarts the schedule instead of bursting
    // to catch up.
    constexpr auto kMaxLag = std::chrono::milliseconds(100);
    int32_t carry = 0;
    auto deadline = Clock::now();
    while (m_running) {
        deadline += batch;
        BatchResult r = runBatch(m_machine, carry, target, m_freeze);
        if (r.stop == BatchResult::Stop::Breakpoint) {  // Core breakpoints are set by headless tools only
            m_running = false;
            return;
        }
        if (r.stop == BatchResult::Stop::Freeze) {
            m_running = false;
            if (m_callbacks.freezeFired) m_callbacks.freezeFired(r.freezeOwner);
            return;
        }
        if (shouldSleep(m_fullSpeed, m_machine.pc(), r.polledHardware, m_model)) {
            auto now = Clock::now();
            if (now - deadline > kMaxLag) deadline = now;
            else std::this_thread::sleep_until(deadline);
        } else {
            deadline = Clock::now();
        }
        if (m_callbacks.batchDone) m_callbacks.batchDone();
    }
}

} // namespace cu59
