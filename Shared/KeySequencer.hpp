#pragma once
#include "MachineModelInfo.hpp"
#include "StateFile.hpp"
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
// A tap holds the key 100 ms — longer than the ROM's worst-case debounce
// (~3 sweeps to arm and confirm, ideas/KeypressLatch.md) yet short enough that
// a repeat-while-held key (Adv) fires only a couple of times at regular speed
// — then releases it and waits until the CPU is back in the steady keyboard
// scan loop, so no keystroke is lost to a still-computing calculator.
//
// Physical keys follow the hardware's level semantics: a single code goes down
// on key-down and up on key-up, but never earlier than 100 ms after it went
// down (a faster release would be discarded as bounce). A two-code binding
// (2nd + key, e.g. Shift+A for A′) is played as two taps instead, since the ROM
// must see 2nd released and rescanned before the second key.
//
// Playback and keyboard taps run on two independent lanes (threads), as two
// separate tasks would: a key press cancels earlier keyboard taps, never a
// running script. Host callbacks arrive on those threads (deferred releases
// on a timer thread) and must be thread-safe.

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

    KeySequencer(Model model, Host& host);
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

    /// row×5 + col identifier the keyboard view highlights for a matrix code.
    static int highlightID(uint8_t matrixCode) { return (matrixCode / 10 - 1) * 5 + (matrixCode % 10 - 1); }

private:
    using Clock = std::chrono::steady_clock;
    using Job = std::function<void(uint64_t generation)>;

    /// A serial job queue on its own thread; cancel() bumps the generation,
    /// which drops queued jobs and wakes a sleeping one.
    class Lane {
    public:
        Lane();
        ~Lane();
        void post(Job job);
        void cancel();
        bool cancelled(uint64_t generation) const { return m_generation.load() != generation; }
        /// Sleep unless cancelled; false if cancelled.
        bool sleepFor(Clock::duration d, uint64_t generation);
    private:
        void run();
        std::atomic<uint64_t> m_generation{0};
        std::mutex m_mutex;
        std::condition_variable m_cv;
        std::deque<std::pair<uint64_t, Job>> m_jobs;
        bool m_quit = false;
        std::thread m_thread;
    };

    void tap(Lane& lane, uint8_t code, uint64_t generation);
    void waitForScanLoopIdle(Lane& lane, uint64_t generation);
    void runScript(const std::vector<KeystrokeEvent>& events, uint64_t generation);
    void releaseAt(uint8_t code, Clock::time_point when);
    void timerLoop();

    const PcRange m_scanLoop;
    Host& m_host;
    std::atomic<bool> m_playing{false};

    // Physical keyboard: the single code held down, and since when.
    std::mutex m_keyMutex;
    std::optional<uint8_t> m_heldCode;
    Clock::time_point m_heldSince;

    // Deferred releases (timer thread).
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
