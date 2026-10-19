// Shared/ runtime without threads (Threading::Cooperative): the key sequencer
// on virtual time, compared against its threaded mode.

#include "TestHarness.hpp"
#include "../Shared/KeySequencer.hpp"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

using namespace cu59;
using namespace std::chrono_literals;
using Clock = std::chrono::steady_clock;

namespace {

// Records every call with the time it came at; pc() is in the scan loop when `idle`.
struct FakeHost : KeySequencer::Host {
    std::mutex mutex;
    std::vector<std::pair<std::string, Clock::time_point>> calls;
    std::atomic<bool> idle{true};
    std::atomic<bool> full{false};
    std::function<Clock::time_point()> clock = [] { return Clock::now(); };
    uint16_t idlePC = info(Model::TI59).scanLoop.lo;

    void note(std::string s) { std::lock_guard<std::mutex> lock(mutex); calls.emplace_back(std::move(s), clock()); }
    void pressKey(uint8_t c) override { note("press " + std::to_string(c)); }
    void releaseKey(uint8_t c) override { note("release " + std::to_string(c)); }
    uint16_t pc() override { return idle ? idlePC : 0; }
    bool isFrozen() override { return false; }
    void heldKeyChanged(int id) override { note("held " + std::to_string(id)); }
    bool fullSpeed() override { return full; }
    void setFullSpeed(bool on) override { full = on; note(on ? "full" : "regular"); }
    void togglePrinterTrace() override { note("trace"); }
    void scriptedTrace(const std::optional<std::string>&) override {}
    void zeroElapseTime() override { note("zero"); }
    void reportElapseTime() override { note("report"); }
    void playbackStarted() override { note("started"); }
    void playbackFinished() override { note("finished"); }

    std::vector<std::string> names() {
        std::lock_guard<std::mutex> lock(mutex);
        std::vector<std::string> v;
        for (auto& c : calls) v.push_back(c.first);
        return v;
    }
    Clock::time_point at(const std::string& name) {
        std::lock_guard<std::mutex> lock(mutex);
        for (auto& c : calls) if (c.first == name) return c.second;
        return {};
    }
};

// A cooperative sequencer on virtual time, advanced in 20 ms batches as
// EmulatorSession::pump does.
struct VirtualRig {
    FakeHost host;
    Clock::time_point t = Clock::time_point{} + 1h;
    KeySequencer keys{Model::TI59, host, Threading::Cooperative};
    VirtualRig() { host.clock = [this] { return t; }; keys.advance(t); }
    void run(Clock::duration d, Clock::duration slice = 20ms) {
        auto end = t + d;
        while (t < end) {
            t += slice;
            keys.advance(t);
        }
    }
};

std::vector<KeystrokeEvent> keyEvents(std::initializer_list<uint8_t> codes) {
    std::vector<KeystrokeEvent> v;
    for (uint8_t c : codes) {
        KeystrokeEvent e;
        e.code = c;
        v.push_back(e);
    }
    return v;
}

KeystrokeEvent event(KeystrokeEvent::Kind kind, double seconds = 0) {
    KeystrokeEvent e;
    e.kind = kind;
    e.seconds = seconds;
    return e;
}

} // namespace

TEST(cooperative_script_holds_each_key_and_waits_for_the_scan_loop) {
    VirtualRig r;
    r.host.idle = false;  // the CPU is computing after each key
    r.keys.play(keyEvents({25, 83}));
    r.run(120ms);
    CHECK(r.keys.isPlaying());
    CHECK(r.host.at("release 25") - r.host.at("press 25") == 100ms);
    r.run(200ms);  // still busy: the next key waits
    CHECK(r.host.at("press 83") == Clock::time_point{});
    r.host.idle = true;
    auto idleAt = r.t;
    r.run(200ms);
    CHECK(r.host.at("press 83") == idleAt + 20ms);  // noticed at the next batch boundary
    CHECK(!r.keys.isPlaying());
    CHECK(r.host.names() == (std::vector<std::string>{"started", "press 25", "release 25", "press 83", "release 83", "finished"}));
}

TEST(cooperative_wait_full_speed_restores_the_speed) {
    VirtualRig r;
    r.keys.play({event(KeystrokeEvent::Kind::WaitFullSpeed, 0.5), event(KeystrokeEvent::Kind::ZeroElapseTime)});
    r.run(400ms);
    CHECK(r.host.full.load());
    r.run(200ms);
    CHECK(!r.host.full.load());
    CHECK(r.host.at("regular") - r.host.at("full") == 500ms);
    CHECK(r.host.names() == (std::vector<std::string>{"started", "full", "regular", "zero", "finished"}));
}

TEST(cooperative_cancel_ends_a_wait_but_not_a_hold) {
    VirtualRig r;
    auto events = keyEvents({25});
    events.push_back(event(KeystrokeEvent::Kind::Wait, 10));
    events.push_back(event(KeystrokeEvent::Kind::ZeroElapseTime));
    r.keys.play(events);
    r.run(40ms);
    r.keys.cancel();
    r.run(40ms);
    CHECK(r.host.at("release 25") == Clock::time_point{});  // the hold runs on
    r.run(40ms);
    CHECK(r.host.at("release 25") - r.host.at("press 25") == 100ms);
    r.keys.play(keyEvents({83}));  // queued after a cancel: runs
    r.run(1s);
    CHECK(r.host.names() == (std::vector<std::string>{"started", "press 25", "release 25", "finished",
                                                      "started", "press 83", "release 83", "finished"}));
}

TEST(cooperative_physical_key_keeps_the_minimum_hold) {
    VirtualRig r;
    r.keys.keyDown({83});
    r.keys.keyUp();  // in the same frame: the release is deferred
    CHECK(r.host.names() == (std::vector<std::string>{"held 37", "press 83", "held -1"}));
    r.run(80ms);
    CHECK(r.host.at("release 83") == Clock::time_point{});
    r.run(40ms);
    CHECK(r.host.at("release 83") - r.host.at("press 83") == 100ms);
}

TEST(cooperative_two_code_binding_taps_both_keys) {
    VirtualRig r;
    r.keys.keyDown({21, 11});  // 2nd, then A
    r.run(500ms);
    CHECK(r.host.names() == (std::vector<std::string>{"held 5", "press 21", "release 21", "held 0", "press 11",
                                                      "release 11", "held -1"}));
    r.keys.keyDown({21, 11});
    r.run(20ms);
    r.keys.keyDown({83});  // cancels the sequence after its first tap
    r.run(500ms);
    auto n = r.host.names();
    CHECK(std::count(n.begin(), n.end(), "press 11") == 1);
}

TEST(threaded_and_cooperative_sequencers_agree) {
    FakeHost host;
    {
        KeySequencer keys(Model::TI59, host);
        auto events = keyEvents({25, 83});
        events.push_back(event(KeystrokeEvent::Kind::WaitFullSpeed, 0.05));
        keys.play(events);
        auto end = Clock::now() + 2s;
        while (keys.isPlaying() || host.names().empty()) {
            if (Clock::now() > end) break;
            std::this_thread::sleep_for(5ms);
        }
        std::this_thread::sleep_for(20ms);
    }
    VirtualRig r;
    auto events = keyEvents({25, 83});
    events.push_back(event(KeystrokeEvent::Kind::WaitFullSpeed, 0.05));
    r.keys.play(events);
    r.run(1s);
    CHECK(host.names() == r.host.names());
    auto hold = host.at("release 25") - host.at("press 25");
    CHECK(hold >= 100ms && hold < 150ms);
}
