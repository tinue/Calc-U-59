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
    int32_t carry = 0;
    while (m_running) {
        auto start = Clock::now();
        BatchResult r = runBatch(m_machine, carry, target, m_freeze);
        if (r.stop == BatchResult::Stop::Breakpoint) {
            m_running = false;
            if (m_callbacks.breakpoint) m_callbacks.breakpoint(m_machine.pc());
            return;
        }
        if (r.stop == BatchResult::Stop::Freeze) {
            m_running = false;
            if (m_callbacks.freezeFired) m_callbacks.freezeFired(r.freezeOwner);
            return;
        }
        if (shouldSleep(m_fullSpeed, m_machine.pc(), r.polledHardware, m_model))
            std::this_thread::sleep_until(start + batch);
        if (m_callbacks.batchDone) m_callbacks.batchDone();
    }
}

} // namespace cu59
