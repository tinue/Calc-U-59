#include "KeySequencer.hpp"
#include <algorithm>

namespace cu59 {

// ── Lane ─────────────────────────────────────────────────────────────────────

KeySequencer::Lane::Lane() { m_thread = std::thread([this] { run(); }); }

KeySequencer::Lane::~Lane() {
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_quit = true;
        ++m_generation;
    }
    m_cv.notify_all();
    m_thread.join();
}

void KeySequencer::Lane::post(Job job) {
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_jobs.emplace_back(m_generation.load(), std::move(job));
    }
    m_cv.notify_all();
}

void KeySequencer::Lane::cancel() {
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        ++m_generation;
        m_jobs.clear();
    }
    m_cv.notify_all();
}

bool KeySequencer::Lane::sleepFor(Clock::duration d, uint64_t generation) {
    std::unique_lock<std::mutex> lock(m_mutex);
    return !m_cv.wait_for(lock, d, [&] { return m_quit || cancelled(generation); });
}

void KeySequencer::Lane::run() {
    for (;;) {
        std::pair<uint64_t, Job> job;
        {
            std::unique_lock<std::mutex> lock(m_mutex);
            m_cv.wait(lock, [this] { return m_quit || !m_jobs.empty(); });
            if (m_quit) return;
            job = std::move(m_jobs.front());
            m_jobs.pop_front();
        }
        if (!cancelled(job.first)) job.second(job.first);
    }
}

// ── KeySequencer ─────────────────────────────────────────────────────────────

KeySequencer::KeySequencer(Model model, Host& host) : m_scanLoop(info(model).scanLoop), m_host(host) {
    m_timer = std::thread([this] { timerLoop(); });
}

KeySequencer::~KeySequencer() {
    m_script.cancel();
    m_keys.cancel();
    {
        std::lock_guard<std::mutex> lock(m_timerMutex);
        m_timerQuit = true;
    }
    m_timerCv.notify_all();
    m_timer.join();
}

void KeySequencer::tap(Lane& lane, uint8_t code, uint64_t generation) {
    m_host.pressKey(code);
    // The hold is not cut short by a cancel: the key must still come up.
    std::this_thread::sleep_for(kHold);
    m_host.releaseKey(code);
    waitForScanLoopIdle(lane, generation);
}

// The narrow steady-state scan loop, not the wider key-detect range: that
// also covers the debounce/confirm states of the key just pressed, so the
// next key could fire mid-debounce and be discarded. A freeze stops the CPU
// outright, so return at once instead of waiting forever.
void KeySequencer::waitForScanLoopIdle(Lane& lane, uint64_t generation) {
    while (!lane.cancelled(generation)) {
        if (m_host.isFrozen()) return;
        if (m_scanLoop.contains(m_host.pc())) return;
        if (!lane.sleepFor(kScanPoll, generation)) return;
    }
}

void KeySequencer::play(std::vector<KeystrokeEvent> events) {
    m_script.post([this, events = std::move(events)](uint64_t generation) { runScript(events, generation); });
}

void KeySequencer::cancel() { m_script.cancel(); }

void KeySequencer::runScript(const std::vector<KeystrokeEvent>& events, uint64_t generation) {
    using K = KeystrokeEvent::Kind;
    m_playing = true;
    m_host.playbackStarted();
    auto seconds = [](double s) { return std::chrono::duration_cast<Clock::duration>(std::chrono::duration<double>(s)); };
    for (const auto& e : events) {
        if (m_script.cancelled(generation)) break;
        switch (e.kind) {
        case K::Key: tap(m_script, e.code, generation); break;
        case K::ToggleTrace: m_host.togglePrinterTrace(); break;
        case K::Wait: m_script.sleepFor(seconds(e.seconds), generation); break;
        case K::WaitFullSpeed: {
            bool previous = m_host.fullSpeed();
            m_host.setFullSpeed(true);
            m_script.sleepFor(seconds(e.seconds), generation);
            m_host.setFullSpeed(previous);
            break;
        }
        case K::FullSpeed: m_host.setFullSpeed(true); break;
        case K::RegularSpeed: m_host.setFullSpeed(false); break;
        case K::ZeroElapseTime: m_host.zeroElapseTime(); break;
        case K::ReportElapseTime: m_host.reportElapseTime(); break;
        case K::Trace: m_host.scriptedTrace(e.traceName); break;
        }
    }
    m_playing = false;
    m_host.playbackFinished();
}

void KeySequencer::keyDown(const std::vector<uint8_t>& codes) {
    if (codes.empty()) return;
    // The hardware rejects chords: one key at a time.
    keyUp();
    m_keys.cancel();
    if (codes.size() == 1) {
        {
            std::lock_guard<std::mutex> lock(m_keyMutex);
            m_heldCode = codes[0];
            m_heldSince = Clock::now();
        }
        m_host.heldKeyChanged(highlightID(codes[0]));
        m_host.pressKey(codes[0]);
        return;
    }
    m_keys.post([this, codes](uint64_t generation) {
        for (uint8_t code : codes) {
            if (m_keys.cancelled(generation)) return;
            m_host.heldKeyChanged(highlightID(code));
            tap(m_keys, code, generation);
        }
        m_host.heldKeyChanged(-1);
    });
}

void KeySequencer::keyUp() {
    uint8_t code;
    Clock::time_point since;
    {
        std::lock_guard<std::mutex> lock(m_keyMutex);
        if (!m_heldCode) return;
        code = *m_heldCode;
        since = m_heldSince;
        m_heldCode.reset();
    }
    m_host.heldKeyChanged(-1);
    auto earliest = since + kHold;
    if (Clock::now() >= earliest) m_host.releaseKey(code);
    else releaseAt(code, earliest);
}

void KeySequencer::releaseAll() {
    m_keys.cancel();
    std::optional<uint8_t> code;
    {
        std::lock_guard<std::mutex> lock(m_keyMutex);
        code = m_heldCode;
        m_heldCode.reset();
    }
    if (code) m_host.releaseKey(*code);
    m_host.heldKeyChanged(-1);
}

void KeySequencer::releaseAt(uint8_t code, Clock::time_point when) {
    {
        std::lock_guard<std::mutex> lock(m_timerMutex);
        m_releases.emplace_back(when, code);
    }
    m_timerCv.notify_all();
}

void KeySequencer::timerLoop() {
    std::unique_lock<std::mutex> lock(m_timerMutex);
    while (!m_timerQuit) {
        if (m_releases.empty()) {
            m_timerCv.wait(lock, [this] { return m_timerQuit || !m_releases.empty(); });
            continue;
        }
        auto next = std::min_element(m_releases.begin(), m_releases.end());
        if (Clock::now() < next->first) {
            m_timerCv.wait_until(lock, next->first);
            continue;
        }
        uint8_t code = next->second;
        m_releases.erase(next);
        lock.unlock();
        m_host.releaseKey(code);
        lock.lock();
    }
}

} // namespace cu59
