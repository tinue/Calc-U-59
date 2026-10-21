#pragma once
#include "MachineModelInfo.hpp"
#include "StateFile.hpp"
#include "Threading.hpp"
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

// Timed key input: KEYSTROKES playback and the physical keyboard.
//
// A tap waits until the CPU is in the steady keyboard scan loop, holds the key
// 100 ms — longer than the ROM's worst-case debounce (~3 sweeps to arm and
// confirm, ideas/KeypressLatch.md) yet short enough that a repeat-while-held
// key (Adv) fires only a couple of times at regular speed — then releases it
// and waits for the scan loop again, so no keystroke is lost to a
// still-computing calculator or one still in its key-release gate.
//
// Physical keys follow the hardware's level semantics: a single code goes down
// on key-down and up on key-up, but never earlier than 100 ms after it went
// down (a faster release would be discarded as bounce). A two-code binding
// (2nd + key, e.g. Shift+A for A′) is played as two taps instead, since the ROM
// must see 2nd released and rescanned before the second key.
//
// Playback and keyboard taps run on two independent lanes, as two separate
// tasks would: a key press cancels earlier keyboard taps, never a running
// script. Each script or tap is a resumable task — a small state machine that
// says when it next wants to run. With Threading::Threads each lane is a thread
// that sleeps until then (deferred releases on a timer thread), and Host
// callbacks arrive on those threads and must be thread-safe. With
// Threading::Cooperative there are no threads: advance(now) runs whatever is
// due, on the caller's thread.

namespace cu59 {

class KeySequencer {
public:
    struct Host {
        virtual ~Host() = default;
        virtual void pressKey(uint8_t matrixCode) = 0;
        virtual void releaseKey(uint8_t matrixCode) = 0;
        virtual uint16_t pc() = 0;
        virtual bool isFrozen() = 0;
        /// The key shown pressed (row×5 + col, 0-based), -1 for none.
        virtual void heldKeyChanged(int highlightID) = 0;
        // KEYSTROKES playback
        virtual bool fullSpeed() = 0;
        virtual void setFullSpeed(bool on) = 0;
        virtual void togglePrinterTrace() = 0;
        virtual void scriptedTrace(const std::optional<std::string>& fileName) = 0;  ///< nullopt = stop
        virtual void zeroElapseTime() = 0;
        virtual void reportElapseTime() = 0;
        virtual void playbackStarted() = 0;
        /// Always called at the end of a script, even if cancelled: the host
        /// drops full speed and closes a scripted trace left open.
        virtual void playbackFinished() = 0;
    };

    static constexpr std::chrono::milliseconds kHold{100};
    static constexpr std::chrono::microseconds kScanPoll{1500};

    KeySequencer(Model model, Host& host, Threading threading = Threading::Threads);
    ~KeySequencer();
    KeySequencer(const KeySequencer&) = delete;
    KeySequencer& operator=(const KeySequencer&) = delete;

    /// Play a KEYSTROKES sequence (queued after a script still running).
    void play(std::vector<KeystrokeEvent> events);

    /// Cancel playback (a key being tapped is still released).
    void cancel();

    bool isPlaying() const { return m_playing.load(); }

    // Physical keyboard
    void keyDown(const std::vector<uint8_t>& codes);
    void keyUp();
    /// Force-release whatever is held (focus lost, view torn down).
    void releaseAll();

    /// Cooperative only: run the lanes and deferred releases due at `now`.
    void advance(std::chrono::steady_clock::time_point now);

    /// row×5 + col identifier the keyboard view highlights for a matrix code.
    static int highlightID(uint8_t matrixCode) { return (matrixCode / 10 - 1) * 5 + (matrixCode % 10 - 1); }

private:
    using Clock = std::chrono::steady_clock;

    /// One script or keyboard tap sequence, resumable: step() runs it until it
    /// has to wait, and says until when.
    struct Task {
        enum class Phase {
            Next,            ///< run the next event
            WaitingToPress,  ///< poll every kScanPoll until the CPU is in the scan loop, then press
            Holding,         ///< key down until `wake` (a cancel does not cut it short)
            WaitingIdle,     ///< key up; poll every kScanPoll until the CPU is in the scan loop
            Sleeping,        ///< Wait / WaitFullSpeed until `wake` (a cancel ends it)
        };
        std::vector<KeystrokeEvent> events;  ///< a keyboard tap sequence holds Key events only
        bool script = false;
        uint64_t generation = 0;
        size_t next = 0;
        Phase phase = Phase::Next;
        Clock::time_point wake{};
        uint8_t code = 0;                    ///< the key being tapped
        std::optional<bool> restoreSpeed;    ///< WaitFullSpeed: the speed to go back to
    };

    /// A serial queue of tasks; cancel() bumps the generation, which drops
    /// queued tasks and ends a waiting one. Threaded: a thread calls advance()
    /// and sleeps until the time it returns. Cooperative: the owner calls it.
    class Lane {
    public:
        Lane(KeySequencer& owner, Threading threading);
        ~Lane();
        void post(Task task);
        void cancel();
        bool cancelled(uint64_t generation) const { return m_generation.load() != generation; }
        /// Run what is due at `now`; when the task in progress next wants to
        /// run, nullopt when the lane is idle.
        std::optional<Clock::time_point> advance(Clock::time_point now);
    private:
        void run();
        bool takeNext(Task& task);  // under m_mutex
        KeySequencer& m_owner;
        std::atomic<uint64_t> m_generation{0};
        std::mutex m_mutex;
        std::condition_variable m_cv;
        std::deque<Task> m_tasks;
        std::optional<Task> m_current;  ///< the task in progress
        bool m_quit = false;
        std::thread m_thread;
    };

    /// Run `task` at `now` until it waits: when it next wants to run, or
    /// nullopt when it has finished.
    std::optional<Clock::time_point> step(Lane& lane, Task& task, Clock::time_point now);
    void finish(Task& task);
    void releaseAt(uint8_t code, Clock::time_point when);
    /// Release every key due by `now`; when the next is due, nullopt for none.
    /// `lock` holds m_timerMutex (dropped while a key is released).
    std::optional<Clock::time_point> releaseDue(Clock::time_point now, std::unique_lock<std::mutex>& lock);
    void timerLoop();
    Clock::time_point now() const;

    const PcRange m_scanLoop;
    Host& m_host;
    const Threading m_threading;
    std::atomic<bool> m_playing{false};
    Clock::time_point m_now{};  ///< cooperative: the last advance() time

    // Physical keyboard: the single code held down, and since when.
    std::mutex m_keyMutex;
    std::optional<uint8_t> m_heldCode;
    Clock::time_point m_heldSince;

    // Deferred releases (threaded: on the timer thread).
    std::mutex m_timerMutex;
    std::condition_variable m_timerCv;
    std::vector<std::pair<Clock::time_point, uint8_t>> m_releases;
    bool m_timerQuit = false;
    std::thread m_timer;

    // Declared last: destroyed (joined) first, while the members above live.
    Lane m_script;
    Lane m_keys;
};

} // namespace cu59
