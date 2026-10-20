#include "KeySequencer.hpp"
#include <algorithm>

namespace cu59 {

// ── Lane ─────────────────────────────────────────────────────────────────────

KeySequencer::Lane::Lane(KeySequencer& owner, Threading threading) : m_owner(owner) {
    if (threading == Threading::Threads) m_thread = std::thread([this] { run(); });
}

KeySequencer::Lane::~Lane() {
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_quit = true;
        ++m_generation;
    }
    m_cv.notify_all();
    if (m_thread.joinable()) m_thread.join();
}

void KeySequencer::Lane::post(Task task) {
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        task.generation = m_generation.load();
        m_tasks.push_back(std::move(task));
    }
    m_cv.notify_all();
}

void KeySequencer::Lane::cancel() {
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        ++m_generation;
        m_tasks.clear();
    }
    m_cv.notify_all();
}

// A task cancelled before it started never runs (no playbackStarted).
bool KeySequencer::Lane::takeNext(Task& task) {
    while (!m_tasks.empty()) {
        task = std::move(m_tasks.front());
        m_tasks.pop_front();
        if (!cancelled(task.generation)) return true;
    }
    return false;
}

void KeySequencer::Lane::run() {
    for (;;) {
        Task task;
        {
            std::unique_lock<std::mutex> lock(m_mutex);
            m_cv.wait(lock, [this] { return m_quit || !m_tasks.empty(); });
            if (m_quit) return;
            if (!takeNext(task)) continue;
        }
        while (auto wake = m_owner.step(*this, task, Clock::now())) {
            std::unique_lock<std::mutex> lock(m_mutex);
            // A hold runs to its end; step() goes back to sleep if woken early.
            if (task.phase == Task::Phase::Holding) m_cv.wait_until(lock, *wake);
            else m_cv.wait_until(lock, *wake, [&] { return m_quit || cancelled(task.generation); });
        }
    }
}

void KeySequencer::Lane::advance(Clock::time_point now) {
    for (;;) {
        if (!m_current) {
            Task task;
            {
                std::lock_guard<std::mutex> lock(m_mutex);
                if (!takeNext(task)) return;
            }
            m_current = std::move(task);
        }
        auto wake = m_owner.step(*this, *m_current, now);
        if (!wake) {
            m_current.reset();
            continue;
        }
        if (*wake > now) return;
    }
}

// ── KeySequencer ─────────────────────────────────────────────────────────────

KeySequencer::KeySequencer(Model model, Host& host, Threading threading)
    : m_scanLoop(info(model).scanLoop), m_host(host), m_threading((requireThreadSupport(threading), threading)),
      m_script(*this, threading), m_keys(*this, threading) {
    if (threading == Threading::Threads) m_timer = std::thread([this] { timerLoop(); });
}

KeySequencer::~KeySequencer() {
    m_script.cancel();
    m_keys.cancel();
    {
        std::lock_guard<std::mutex> lock(m_timerMutex);
        m_timerQuit = true;
    }
    m_timerCv.notify_all();
    if (m_timer.joinable()) m_timer.join();
}

KeySequencer::Clock::time_point KeySequencer::now() const {
    return m_threading == Threading::Threads ? Clock::now() : m_now;
}

void KeySequencer::advance(Clock::time_point now) {
    if (m_threading != Threading::Cooperative) return;
    m_now = std::max(m_now, now);
    std::optional<Clock::time_point> next;
    for (;;) {
        std::optional<uint8_t> code;
        {
            std::lock_guard<std::mutex> lock(m_timerMutex);
            code = takeDueRelease(m_now, next);
        }
        if (!code) break;
        m_host.releaseKey(*code);
    }
    m_script.advance(m_now);
    m_keys.advance(m_now);
}

// A tap waits for the narrow steady-state scan loop, holds the key kHold —
// not cut short by a cancel, the key must still come up — then waits for the
// scan loop again. The narrow loop, not the wider key-detect range: that also
// covers the release gate, where a new key is discarded, and the key just
// pressed being decoded. (With a printer the narrow loop includes the confirm
// scan: the printer line makes every pass take it.) A freeze stops the CPU outright, so
// the waits end at once instead of forever.
std::optional<KeySequencer::Clock::time_point> KeySequencer::step(Lane& lane, Task& task, Clock::time_point now) {
    using K = KeystrokeEvent::Kind;
    using P = Task::Phase;
    auto seconds = [](double s) { return std::chrono::duration_cast<Clock::duration>(std::chrono::duration<double>(s)); };
    if (task.script && task.next == 0 && task.phase == P::Next) {
        m_playing = true;
        m_host.playbackStarted();
    }
    for (;;) {
        switch (task.phase) {
        case P::WaitingToPress:
            if (lane.cancelled(task.generation)) {
                task.phase = P::Next;
                break;
            }
            if (m_host.isFrozen() || m_scanLoop.contains(m_host.pc())) {
                if (!task.script) m_host.heldKeyChanged(highlightID(task.code));
                m_host.pressKey(task.code);
                task.wake = now + kHold;
                task.phase = P::Holding;
                return task.wake;
            }
            if (now < task.wake) return task.wake;
            task.wake = now + kScanPoll;
            return task.wake;
        case P::Holding:
            if (now < task.wake) return task.wake;
            m_host.releaseKey(task.code);
            task.phase = P::WaitingIdle;
            break;
        case P::WaitingIdle:
            if (lane.cancelled(task.generation) || m_host.isFrozen() || m_scanLoop.contains(m_host.pc())) {
                task.phase = P::Next;
                break;
            }
            if (now < task.wake) return task.wake;
            task.wake = now + kScanPoll;
            return task.wake;
        case P::Sleeping:
            if (now < task.wake && !lane.cancelled(task.generation)) return task.wake;
            if (task.restoreSpeed) m_host.setFullSpeed(*task.restoreSpeed);
            task.restoreSpeed.reset();
            task.phase = P::Next;
            break;
        case P::Next: {
            // A keyboard sequence that ran its last tap clears the highlight
            // even if cancelled during that tap; one cancelled earlier doesn't.
            if (task.next == task.events.size() || (task.script && lane.cancelled(task.generation))) {
                finish(task);
                return std::nullopt;
            }
            if (lane.cancelled(task.generation)) return std::nullopt;
            const KeystrokeEvent& e = task.events[task.next++];
            switch (e.kind) {
            case K::Key:
                task.code = e.code;
                task.wake = now;
                task.phase = P::WaitingToPress;
                break;
            case K::ToggleTrace: m_host.togglePrinterTrace(); break;
            case K::Wait:
                task.wake = now + seconds(e.seconds);
                task.phase = P::Sleeping;
                break;
            case K::WaitFullSpeed:
                task.restoreSpeed = m_host.fullSpeed();
                m_host.setFullSpeed(true);
                task.wake = now + seconds(e.seconds);
                task.phase = P::Sleeping;
                break;
            case K::FullSpeed: m_host.setFullSpeed(true); break;
            case K::RegularSpeed: m_host.setFullSpeed(false); break;
            case K::ZeroElapseTime: m_host.zeroElapseTime(); break;
            case K::ReportElapseTime: m_host.reportElapseTime(); break;
            case K::Trace: m_host.scriptedTrace(e.traceName); break;
            }
            break;
        }
        }
    }
}

void KeySequencer::finish(Task& task) {
    if (task.script) {
        m_playing = false;
        m_host.playbackFinished();
    } else {
        m_host.heldKeyChanged(-1);
    }
}

void KeySequencer::play(std::vector<KeystrokeEvent> events) {
    Task task;
    task.events = std::move(events);
    task.script = true;
    m_script.post(std::move(task));
}

void KeySequencer::cancel() { m_script.cancel(); }

void KeySequencer::keyDown(const std::vector<uint8_t>& codes) {
    if (codes.empty()) return;
    // The hardware rejects chords: one key at a time.
    keyUp();
    m_keys.cancel();
    if (codes.size() == 1) {
        {
            std::lock_guard<std::mutex> lock(m_keyMutex);
            m_heldCode = codes[0];
            m_heldSince = now();
        }
        m_host.heldKeyChanged(highlightID(codes[0]));
        m_host.pressKey(codes[0]);
        return;
    }
    Task task;
    for (uint8_t code : codes) {
        KeystrokeEvent e;
        e.code = code;
        task.events.push_back(e);
    }
    m_keys.post(std::move(task));
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
    if (now() >= earliest) m_host.releaseKey(code);
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

std::optional<uint8_t> KeySequencer::takeDueRelease(Clock::time_point now, std::optional<Clock::time_point>& next) {
    next.reset();
    auto it = std::min_element(m_releases.begin(), m_releases.end());
    if (it == m_releases.end()) return std::nullopt;
    if (now < it->first) {
        next = it->first;
        return std::nullopt;
    }
    uint8_t code = it->second;
    m_releases.erase(it);
    return code;
}

void KeySequencer::timerLoop() {
    std::unique_lock<std::mutex> lock(m_timerMutex);
    while (!m_timerQuit) {
        std::optional<Clock::time_point> next;
        if (auto code = takeDueRelease(Clock::now(), next)) {
            lock.unlock();
            m_host.releaseKey(*code);
            lock.lock();
        } else if (next) {
            m_timerCv.wait_until(lock, *next);
        } else {
            m_timerCv.wait(lock, [this] { return m_timerQuit || !m_releases.empty(); });
        }
    }
}

} // namespace cu59
