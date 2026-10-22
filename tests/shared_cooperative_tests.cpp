// Shared/ runtime without threads (Threading::Cooperative), as the web build
// runs it: the key sequencer on virtual time compared against its threaded
// mode, the pumped run loop's pacing, and a whole SessionController.

#include "TestHarness.hpp"
#include "FakePlatform.hpp"
#include "TestRoms.hpp"
#include "../Shared/EmulationRunner.hpp"
#include "../Shared/KeyMatrix.hpp"
#include "../Shared/KeySequencer.hpp"
#include "../Shared/SessionController.hpp"
#include "../Shared/StateFile.hpp"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <deque>
#include <functional>
#include <map>
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
    r.host.idle = false;  // still computing: the first key waits
    r.keys.play(keyEvents({25, 83}));
    r.run(200ms);
    CHECK(r.keys.isPlaying());
    CHECK(r.host.at("press 25") == Clock::time_point{});
    r.host.idle = true;
    auto idleAt = r.t;
    r.run(20ms);
    CHECK(r.host.at("press 25") == idleAt + 20ms);  // noticed at the next batch boundary
    r.host.idle = false;  // the key starts a computation
    r.run(200ms);
    CHECK(r.host.at("release 25") - r.host.at("press 25") == 100ms);
    CHECK(r.host.at("press 83") == Clock::time_point{});  // waits for the scan loop
    r.host.idle = true;
    idleAt = r.t;
    r.run(200ms);
    CHECK(r.host.at("press 83") == idleAt + 20ms);
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

// ── Run loop ─────────────────────────────────────────────────────────────────

TEST(cooperative_runner_paces_by_the_wall_clock) {
    auto m = testroms::makeMachine(Model::TI59);
    testroms::runToScanLoop(*m, Model::TI59);
    FreezeController freeze(Model::TI59);
    int batches = 0;
    EmulationRunner::Callbacks cb;
    cb.batchDone = [&] { ++batches; };
    EmulationRunner runner(*m, Model::TI59, freeze, cb, Threading::Cooperative);
    std::vector<int> order;
    runner.post([&] { order.push_back(1); });
    runner.start();
    runner.post([&] { order.push_back(2); });  // behind the loop: waits until it stops
    auto t = Clock::time_point{} + 1h;
    uint64_t t0 = m->elapsedTicks();
    for (int i = 0; i < 60; ++i, t += std::chrono::microseconds(16'667)) runner.pump(t, nullptr);
    CHECK_EQ(batches, 50);  // one second of 20 ms batches
    uint64_t ticks = m->elapsedTicks() - t0;
    CHECK(ticks >= 50u * 284u && ticks < 50u * 284u + 142u + 8u);  // + the last batch's jitter offset
    CHECK(order == std::vector<int>{1});
    t += 5s;  // a stall: the schedule restarts instead of catching up
    runner.pump(t, nullptr);
    CHECK_EQ(batches, 51);
    runner.stop();
    runner.sync([&] { order.push_back(3); });
    CHECK(order == (std::vector<int>{1, 2, 3}));
    runner.pump(t + 1s, nullptr);
    CHECK_EQ(batches, 51);
}

// The TI-58's error-blink dark pass is 80 steps (through the card veto at
// 0x0459), and a TI-58 batch 240: with fixed batches every batch ended on the
// same instruction for the whole dark phase, and the CPU panel, which samples
// between batches, stood still. Jittered batch ends land all over the loop
// while the long-term rate stays exact.
TEST(cooperative_runner_batch_ends_do_not_lock_onto_a_loop) {
    auto m = testroms::makeMachine(Model::TI58);
    testroms::runToScanLoop(*m, Model::TI58);
    for (int k : {92, 35}) testroms::tap(*m, Model::TI58, k);  // 0 1/x: error blink
    FreezeController freeze(Model::TI58);
    EmulationRunner::Callbacks cb;
    cb.jitterSeed = 59;
    EmulationRunner runner(*m, Model::TI58, freeze, cb, Threading::Cooperative);
    std::vector<uint16_t> ends;
    runner.start();
    auto t = Clock::time_point{} + 1h;
    uint64_t t0 = m->elapsedTicks();
    for (int i = 0; i < 180; ++i, t += std::chrono::microseconds(16'667))  // 3 s: a few blinks
        runner.pump(t, [&](Clock::time_point) { ends.push_back(m->pc()); });
    uint64_t ticks = m->elapsedTicks() - t0;
    CHECK_EQ(ends.size(), size_t{150});
    CHECK(ticks >= 150u * 240u && ticks < 150u * 240u + 120u + 8u);
    size_t run = 1, longest = 1;
    for (size_t i = 1; i < ends.size(); ++i) longest = std::max(longest, run = ends[i] == ends[i - 1] ? run + 1 : 1);
    CHECK(longest <= 4);  // fixed batches: a whole dark phase, ~27
}

TEST(cooperative_runner_full_speed_runs_a_slice) {
    auto m = testroms::makeMachine(Model::TI59);
    testroms::runToScanLoop(*m, Model::TI59);
    const uint8_t loop[] = {61, 0, 0};  // GTO 000: computes forever
    m->writeProgram(loop, 3);
    pressMatrix(*m, 91);  // R/S
    m->stepN(30'000, false);
    releaseMatrix(*m, 91);
    m->stepN(30'000, false);
    CHECK(!info(Model::TI59).idleAndKeyDetect.contains(m->pc()));
    FreezeController freeze(Model::TI59);
    auto wall = Clock::time_point{} + 1h;
    int batches = 0;
    EmulationRunner::Callbacks cb;
    cb.batchDone = [&] { ++batches; wall += 1ms; };  // each batch "takes" 1 ms
    cb.wallClock = [&] { return wall; };
    EmulationRunner runner(*m, Model::TI59, freeze, cb, Threading::Cooperative);
    runner.setFullSpeed(true);
    runner.start();
    runner.pump(Clock::time_point{} + 1h, nullptr);
    CHECK_EQ(batches, 10);
}

// ── SessionController ────────────────────────────────────────────────────────

namespace {

struct ControllerRig {
    testroms::FakePlatform p;  // tick() at 60 Hz, then the UI queue
    SessionController c{p, testroms::reader(), testroms::readFile("roms/solid-state/cuecards.txt").value_or(""), "ML",
                        Threading::Cooperative};
    Clock::time_point t = Clock::time_point{} + 500ms;  // a browser's clock starts at page load
    ControllerRig() { CHECK(c.startMachine(Model::TI59)); }
    void run(Clock::duration d) {
        for (auto end = t + d; t < end; t += std::chrono::microseconds(16'667)) {
            c.tick(t);
            p.pump();
        }
    }
    template <class F> bool runUntil(F cond, Clock::duration limit = 20s) {
        for (auto end = t + limit; t < end;) {
            if (cond()) return true;
            run(100ms);
        }
        return cond();
    }
    void load(const std::string& text) { c.loadStateFile(std::vector<uint8_t>(text.begin(), text.end())); }
};

} // namespace

TEST(cooperative_controller_plays_a_preset) {
    ControllerRig r;
    r.run(1s);
    CHECK(info(Model::TI59).scanLoop.contains(r.c.session()->machine().pc()));
    r.load("KEYSTROKES:\n25 83 85 84 95\nZeroElapseTime:\nWait: 50ms\nReportElapseTime:\n");
    CHECK(r.runUntil([&] { return r.c.keystrokesPlaying(); }));
    CHECK(r.runUntil([&] { return !r.c.keystrokesPlaying(); }));
    r.run(500ms);
    CHECK_EQ(testroms::displayText(r.c.session()->machine()), std::string("5"));
    CHECK(r.c.logText().find("Elapsed: 0:00.0") != std::string::npos);
    CHECK(r.p.errors.empty());
}

TEST(cooperative_controller_skip_reset_keeps_the_program) {
    ControllerRig r;
    r.load("PROGRAM:\n85 01\n");
    r.run(1s);
    CHECK_EQ(int(r.c.session()->machine().readProgramStep(1)), 1);
    r.load("SKIP-RESET: on\nREGISTERS:\n05 = 3.25\n");
    r.run(200ms);
    CHECK_EQ(int(r.c.session()->machine().readProgramStep(1)), 1);
    CHECK_EQ(r.c.session()->machine().readDataReg(5), 3.25);
}

TEST(cooperative_controller_writes_and_reads_a_card) {
    ControllerRig r;
    r.load("PROGRAM:\n76 11 01 02 03 91\n");  // Lbl A 1 2 3 R/S
    r.run(1s);
    r.load("SKIP-RESET: on\nKEYSTROKES:\n82 21 91\n");  // 1 2nd Write
    CHECK(r.runUntil([&] { return !r.c.keystrokesPlaying(); }));
    r.run(500ms);  // the ROM reaches its card wait after the playback ends
    r.c.insertBlankCard("web:card", "card.U59");
    CHECK(r.runUntil([&] { return r.c.cardState() == SessionController::CardState::NoCard; }));
    CHECK_EQ(r.p.cards.count("web:card"), size_t{1});
    r.load("PARTITION: 479\n");  // a fresh machine: no program
    r.run(1s);
    CHECK_EQ(int(r.c.session()->machine().readProgramStep(1)), 0);
    const std::string& card = r.p.cards["web:card"];
    r.c.insertCard(std::vector<uint8_t>(card.begin(), card.end()), "web:card", "card.U59");
    CHECK(r.runUntil([&] { return r.c.cardState() == SessionController::CardState::NoCard; }));
    r.run(1s);
    CHECK_EQ(int(r.c.session()->machine().readProgramStep(1)), 11);
    CHECK(r.p.errors.empty());
}

TEST(cooperative_controller_shows_the_library_program_card) {
    ControllerRig r;
    r.run(50ms);
    r.load("SKIP-RESET: on\nKEYSTROKES:\n21 31 92 82\n");  // 2nd Pgm 01
    CHECK(r.runUntil([&] { return !r.c.keystrokesPlaying(); }));
    r.run(1s);
    CHECK(r.c.cueCard().has_value());
    if (r.c.cueCard()) CHECK_EQ(r.c.cueCard()->id, std::string("ML-01"));
}
