// Shared/ runtime without threads (Threading::Cooperative), as the web build
// runs it: the key sequencer on virtual time compared against its threaded
// mode, the pumped run loop's pacing, and a whole SessionController.

#include "TestHarness.hpp"
#include "FakePlatform.hpp"
#include "TestRoms.hpp"
#include "../Shared/EmulationRunner.hpp"
#include "../Shared/KeyMatrix.hpp"
#include "../Shared/KeyboardLayout.hpp"
#include "../Shared/TextUtil.hpp"
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
    std::atomic<bool> frozen{false};
    bool isFrozen() override { return frozen; }
    void heldKeyChanged(int id) override { note("held " + std::to_string(id)); }
    void setFullSpeed(bool on) override { full = on; note(on ? "full" : "regular"); }
    void scriptedTrace(const std::optional<std::string>&) override {}
    void zeroElapseTime() override { note("zero"); }
    void reportElapseTime() override { note("report"); }
    void playbackStarted() override { note("started"); }
    void playbackFinished() override { note("finished"); }
    std::atomic<int> pending{0};
    void applyReload(const std::shared_ptr<const ReloadStage>&) override { ++pending; note("reload"); }
    void queueCard(const KeystrokeEvent& e) override {
        if (e.kind == KeystrokeEvent::Kind::InsertCard) ++pending;
        note("card " + e.cardName);
    }
    void control(const KeystrokeEvent&) override { ++pending; note("control"); }
    bool hostPending() override { return pending > 0; }

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

TEST(cooperative_wait_runs_at_the_speed_set_before_it) {
    VirtualRig r;
    r.keys.play({event(KeystrokeEvent::Kind::FullSpeed), event(KeystrokeEvent::Kind::Wait, 0.5),
                 event(KeystrokeEvent::Kind::RegularSpeed), event(KeystrokeEvent::Kind::ZeroElapseTime)});
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
        events.push_back(event(KeystrokeEvent::Kind::Wait, 0.05));
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
    events.push_back(event(KeystrokeEvent::Kind::Wait, 0.05));
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
bool cardIdle(ControllerRig& r) { return r.c.cardState() == SessionController::CardState::NoCard; }

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

TEST(cooperative_controller_reload_keeps_the_program) {
    ControllerRig r;
    r.load("PROGRAM:\n85 01\nKEYSTROKES:\n25\nREGISTERS:\n05 = 3.25\n");  // CLR, then a reload
    CHECK(r.runUntil([&] { return r.c.keystrokesPlaying(); }));
    CHECK(r.runUntil([&] { return !r.c.keystrokesPlaying(); }));
    CHECK_EQ(int(r.c.session()->machine().readProgramStep(1)), 1);
    CHECK_EQ(r.c.session()->machine().readDataReg(5), 3.25);
}

TEST(cooperative_controller_writes_and_reads_a_card) {
    ControllerRig r;
    r.load("PROGRAM:\n76 11 01 02 03 91\nKEYSTROKES:\n82 21 91\n");  // Lbl A 1 2 3 R/S; 1 2nd Write
    CHECK(r.runUntil([&] { return r.c.keystrokesPlaying(); }));
    r.run(2s);  // the ROM waits for a card; playback waits with it
    CHECK(r.c.keystrokesPlaying());
    CHECK(r.c.fitBlankCard("web:card", "card.U59"));
    CHECK(r.c.feedSide(0));
    CHECK(r.runUntil([&] { return cardIdle(r); }));
    CHECK(r.runUntil([&] { return !r.c.keystrokesPlaying(); }));
    CHECK_EQ(r.p.cards.count("web:card"), size_t{1});
    r.load("PARTITION: 479\n");  // a fresh machine: no program
    r.run(1s);
    CHECK_EQ(int(r.c.session()->machine().readProgramStep(1)), 0);
    const std::string& card = r.p.cards["web:card"];
    CHECK(r.c.fitCard(std::vector<uint8_t>(card.begin(), card.end()), "web:card", "card.U59"));
    CHECK(r.c.feedSide(0));
    CHECK(r.runUntil([&] { return cardIdle(r); }));
    r.run(1s);
    CHECK_EQ(int(r.c.session()->machine().readProgramStep(1)), 11);
    CHECK(r.p.errors.empty());
}

TEST(cooperative_controller_shows_the_library_program_card) {
    ControllerRig r;
    r.run(50ms);
    r.load("KEYSTROKES:\n21 31 92 82\n");  // 2nd Pgm 01
    CHECK(r.runUntil([&] { return !r.c.keystrokesPlaying(); }));
    r.run(1s);
    CHECK(r.c.cueCard().has_value());
    if (r.c.cueCard()) CHECK_EQ(r.c.cueCard()->id, std::string("ML-01"));
}

// ── Multi-stage presets: reloads and preset cards ────────────────────────────

TEST(cooperative_reload_waits_for_the_scan_loop_and_the_host) {
    VirtualRig r;
    auto events = keyEvents({25});
    KeystrokeEvent reload = event(KeystrokeEvent::Kind::Reload);
    reload.reload = std::make_shared<ReloadStage>();
    events.push_back(reload);
    events.push_back(keyEvents({83})[0]);
    r.keys.play(events);
    r.run(40ms);
    CHECK(r.host.at("press 25") != Clock::time_point{});
    r.host.idle = false;  // the key starts a run: the reload waits
    r.run(300ms);
    CHECK(r.host.at("reload") == Clock::time_point{});
    r.host.idle = true;
    r.run(40ms);
    CHECK(r.host.at("reload") != Clock::time_point{});
    r.run(300ms);  // the host hasn't applied it yet: the next key waits
    CHECK(r.host.at("press 83") == Clock::time_point{});
    r.host.pending = 0;
    r.run(200ms);
    CHECK(r.host.at("press 83") != Clock::time_point{});
    CHECK(!r.keys.isPlaying());
}

TEST(cooperative_arm_card_does_not_wait_insert_card_does) {
    VirtualRig r;
    KeystrokeEvent arm = event(KeystrokeEvent::Kind::ArmCard);
    arm.cardName = "mem:A";
    KeystrokeEvent insert = event(KeystrokeEvent::Kind::InsertCard);
    insert.cardName = "B";
    std::vector<KeystrokeEvent> events{arm, insert};
    events.push_back(keyEvents({83})[0]);
    r.keys.play(events);
    r.run(100ms);
    CHECK(r.host.names() == (std::vector<std::string>{"started", "card mem:A", "card B"}));
    r.host.pending = 0;  // the inserted card has passed
    r.run(200ms);
    CHECK(r.host.at("press 83") != Clock::time_point{});
}

TEST(cooperative_controller_reload_after_the_first_run) {
    ControllerRig r;
    r.load("PROGRAM:\n76 11 01 02 03 42 08 91\n"  // Lbl A 123 STO 08 R/S
           "KEYSTROKES:\n11\n"
           "PROGRAM:\n76 11 43 08 85 01 95 91\n"  // Lbl A RCL 08 + 1 = R/S
           "REGISTERS:\n07 = 9\nCUECARD:\nTitle: Part 2\n"
           "KEYSTROKES:\n11\n");
    CHECK(r.runUntil([&] { return r.c.keystrokesPlaying(); }));
    CHECK(r.runUntil([&] { return !r.c.keystrokesPlaying(); }));
    r.run(300ms);
    TI59Machine& m = r.c.session()->machine();
    CHECK_EQ(testroms::displayText(m), std::string("124"));  // part 2 used part 1's R08
    CHECK_EQ(m.readDataReg(7), 9.0);
    CHECK(r.c.cueCard() && r.c.cueCard()->title == "Part 2");
    CHECK(r.p.errors.empty());
}

TEST(cooperative_controller_program_writes_and_reads_a_memory_card) {
    ControllerRig r;
    r.load("PROGRAM:\n76 11 04 96 25 47 04 22 96 43 00 91\n"  // Lbl A 4 Write CLR CMs 4 INV Write RCL 00 R/S
           "REGISTERS:\n00 = 42\n"
           "KEYSTROKES:\nArmCard: mem:Scratch\nArmCard: mem:Scratch\n11\n");
    CHECK(r.runUntil([&] { return r.c.keystrokesPlaying(); }));
    CHECK(r.runUntil([&] { return !r.c.keystrokesPlaying(); }, 60s));
    r.run(300ms);
    CHECK_EQ(testroms::displayText(r.c.session()->machine()), std::string("42"));
    CHECK(r.p.cards.empty());  // a memory card never reaches the card folder
    CHECK(r.p.errors.empty());
}

TEST(cooperative_controller_program_reads_a_defined_card) {
    ControllerRig r;
    r.load("CARD: mem:Vars\nBank: 4\nREGISTERS:\n05 = 2.5\nCUECARD:\nTitle: Vars\nEND-CARD\n"
           "PROGRAM:\n76 11 04 22 96 43 05 91\n"  // Lbl A 4 INV Write RCL 05 R/S
           "KEYSTROKES:\nArmCard: mem:Vars\n11\n");
    CHECK(r.runUntil([&] { return r.c.keystrokesPlaying(); }));
    CHECK(r.runUntil([&] { return !r.c.keystrokesPlaying(); }, 60s));
    r.run(300ms);
    CHECK_EQ(r.c.session()->machine().readDataReg(5), 2.5);  // the full load cleared it; the card set it
    CHECK(r.c.cueCard() && r.c.cueCard()->title == "Vars");
    CHECK(r.p.errors.empty());
}

TEST(cooperative_controller_card_file_written_then_inserted) {
    ControllerRig r;
    r.load("PROGRAM:\n76 11 04 96 91\nREGISTERS:\n03 = 7\n"  // Lbl A 4 Write R/S
           "KEYSTROKES:\nArmCard: Results\n11\n");
    CHECK(r.runUntil([&] { return r.p.cards.count("cards/Results.U59") == 1; }, 60s));
    CHECK(r.c.logText().find("no card file Results.U59") != std::string::npos);
    r.load("REGISTERS:\n03 = 0\nKEYSTROKES:\nInsertCard: Results\n");
    CHECK(r.runUntil([&] { return r.c.keystrokesPlaying(); }));
    CHECK(r.runUntil([&] { return !r.c.keystrokesPlaying(); }, 60s));
    CHECK(cardIdle(r));  // playback waited for the card
    CHECK_EQ(r.c.session()->machine().readDataReg(3), 7.0);
    CHECK(r.p.errors.empty());
}

TEST(cooperative_controller_unused_card_is_logged_on_the_next_load) {
    ControllerRig r;
    r.load("KEYSTROKES:\nArmCard: mem:Never\n");
    CHECK(r.runUntil([&] { return !r.c.keystrokesPlaying(); }));
    r.run(100ms);
    CHECK(r.c.logText().find("mem:Never") == std::string::npos);  // still armed after the script
    r.load("REGISTERS:\n01 = 1\n");
    r.run(1100ms);  // the LOG text refreshes at 1 Hz
    CHECK(r.c.logText().find("card mem:Never was never read or written") != std::string::npos);
}

TEST(cooperative_controller_cards_need_a_card_reader) {
    ControllerRig r;
    CHECK(r.c.startMachine(Model::TI58));
    r.load("KEYSTROKES:\nArmCard: Results\n");
    CHECK(!r.p.errors.empty() && r.p.errors.back().find("need a card reader") != std::string::npos);
}

TEST(cooperative_controller_insert_card_passes_an_unused_armed_card) {
    ControllerRig r;
    r.load("CARD: mem:Data\nBank: 4\nREGISTERS:\n03 = 7\nEND-CARD\n"
           "KEYSTROKES:\nArmCard: mem:NeverAsked\nInsertCard: mem:Data\n");
    CHECK(r.runUntil([&] { return r.c.keystrokesPlaying(); }));
    CHECK(r.runUntil([&] { return !r.c.keystrokesPlaying(); }, 30s));
    CHECK_EQ(r.c.session()->machine().readDataReg(3), 7.0);  // read at idle, as pushed in by hand
}

namespace {
std::vector<uint8_t> bytes(const std::string& s) { return {s.begin(), s.end()}; }
/// A card holding the program Lbl A 1 2 3 R/S, as a blank card written by the machine.
std::string writtenCard(ControllerRig& r) {
    r.load("PROGRAM:\n76 11 01 02 03 91\nKEYSTROKES:\n82 21 91\n");  // 1 2nd Write
    CHECK(r.runUntil([&] { return r.c.keystrokesPlaying(); }));
    r.run(2s);
    CHECK(r.c.fitBlankCard("first", "first.U59"));
    CHECK(r.c.feedSide(0));
    CHECK(r.runUntil([&] { return cardIdle(r); }));
    CHECK(r.runUntil([&] { return !r.c.keystrokesPlaying(); }));
    return r.p.cards["first"];
}
}  // namespace

TEST(drop_action_goes_by_name_and_model) {
    using A = SessionController::DropAction;
    ControllerRig r;
    CHECK(r.c.dropAction("a.ti59") == A::LoadPreset);
    CHECK(r.c.dropAction("a.TI58") == A::LoadPreset);
    CHECK(r.c.dropAction("a.Ti58C") == A::LoadPreset);
    CHECK(r.c.dropAction("a.U59") == A::FitCard);
    CHECK(r.c.dropAction("a.bin") == A::FitCard);
    CHECK(r.c.dropAction(".a.u59") == A::NotAccepted);
    CHECK(r.c.dropAction(".a.ti59") == A::NotAccepted);
    CHECK(r.c.dropAction("a.txt") == A::NotAccepted);
    CHECK(r.c.dropAction("ti59") == A::NotAccepted);
    for (Model m : {Model::TI58, Model::TI58C}) {
        CHECK(r.c.startMachine(m));
        CHECK(r.c.dropAction("a.U59") == A::Ignore);
        CHECK(r.c.dropAction("a.ti59") == A::LoadPreset);
    }
}

TEST(dropped_card_is_fitted_and_read_at_idle) {
    ControllerRig r;
    const std::string card = writtenCard(r);
    r.load("PARTITION: 479\n");  // a fresh machine: no program
    r.run(1s);
    CHECK_EQ(int(r.c.session()->machine().readProgramStep(1)), 0);
    CHECK(r.c.openDroppedFile(bytes(card), "dropped", "dropped.U59"));
    CHECK(r.c.cardFitted());
    CHECK(cardIdle(r));  // not fed until a corner is tapped
    r.run(500ms);
    CHECK_EQ(int(r.c.session()->machine().readProgramStep(1)), 0);
    CHECK(r.c.feedSide(0));
    CHECK(r.c.cardState() == SessionController::CardState::Swiping);
    CHECK(r.c.litCardCorner() == 0);
    CHECK(r.runUntil([&] { return cardIdle(r); }));
    r.run(1s);
    CHECK_EQ(int(r.c.session()->machine().readProgramStep(1)), 11);
    CHECK_EQ(r.p.cards.count("dropped"), size_t{0});  // read, not written
    CHECK(r.p.errors.empty());
}

TEST(dropped_card_is_overwritten_after_write) {
    ControllerRig r;
    const std::string card = writtenCard(r);
    r.load("PROGRAM:\n76 12 04 05 06 91\nKEYSTROKES:\n82 21 91\n");  // Lbl B …; 1 2nd Write
    CHECK(r.runUntil([&] { return r.c.keystrokesPlaying(); }));
    r.run(2s);
    r.p.cards["dropped"] = card;
    CHECK(r.c.openDroppedFile(bytes(card), "dropped", "dropped.U59"));
    CHECK(r.c.feedSide(0));
    CHECK(r.runUntil([&] { return cardIdle(r); }));
    CHECK(r.runUntil([&] { return !r.c.keystrokesPlaying(); }));
    CHECK_EQ(r.p.cards.count("dropped"), size_t{1});
    CHECK(r.p.cards["dropped"] != card);

    r.load("PARTITION: 479\n");
    r.run(1s);
    const std::string overwritten = r.p.cards["dropped"];
    CHECK(r.c.openDroppedFile(bytes(overwritten), "dropped", "dropped.U59"));
    CHECK(r.c.feedSide(0));
    CHECK(r.runUntil([&] { return cardIdle(r); }));
    r.run(1s);
    CHECK_EQ(int(r.c.session()->machine().readProgramStep(1)), 12);
}

TEST(dropped_card_is_ignored_without_a_reader) {
    ControllerRig r;
    const std::string card = writtenCard(r);
    for (Model m : {Model::TI58, Model::TI58C}) {
        CHECK(r.c.startMachine(m));
        CHECK(!r.c.openDroppedFile(bytes(card), "dropped", "dropped.U59"));
        r.run(500ms);
        CHECK(cardIdle(r));
    }
    CHECK(r.p.errors.empty());
}

TEST(dropped_card_replaces_the_fitted_one_but_not_during_a_pass) {
    ControllerRig r;
    const std::string card = writtenCard(r);
    CHECK(r.c.openDroppedFile(bytes(card), "one", "one.U59"));
    CHECK(r.c.openDroppedFile(bytes(card), "two", "two.U59"));
    CHECK_EQ(r.c.cardFileName(), std::string("two.U59"));
    CHECK(r.c.feedSide(0));
    CHECK(!r.c.openDroppedFile(bytes(card), "three", "three.U59"));
    CHECK_EQ(r.c.cardFileName(), std::string("two.U59"));
}

namespace {
const char* const kTwoWrites = "PROGRAM:\n76 11 01 02 03 91\nKEYSTROKES:\n82 21 91\n83 21 91\n";  // 1 2nd Write; 2 2nd Write
/// Run a preset's two key-driven writes, feeding `first` then `second` as the ROM waits.
void feedTwoWrites(ControllerRig& r, int first, int second) {
    CHECK(r.runUntil([&] { return r.c.keystrokesPlaying(); }));
    r.run(2s);
    CHECK(r.c.feedSide(first));
    CHECK(r.runUntil([&] { return cardIdle(r); }));
    r.run(2s);
    CHECK(r.c.feedSide(second));
    CHECK(r.runUntil([&] { return cardIdle(r); }));
    CHECK(r.runUntil([&] { return !r.c.keystrokesPlaying(); }));
}
}  // namespace

TEST(fresh_card_writes_both_sides_into_one_file) {
    ControllerRig r;
    // Loading a preset removes a fitted card, so fit it once the preset runs.
    r.load(kTwoWrites);
    CHECK(r.c.fitBlankCard("cards/Fresh.U59", "Fresh.U59"));
    CHECK(r.c.cueCard() && r.c.cueCard()->title == "Fresh");
    CHECK(r.c.cueCard() && !r.c.cueCard()->bankLeft && !r.c.cueCard()->bankRight);
    feedTwoWrites(r, 0, 1);
    const std::string& text = r.p.cards["cards/Fresh.U59"];
    CHECK(startsWith(text, "Calc-U-59 Card 2.0\n"));
    CHECK(text.find("Banks:") == std::string::npos);
    // The corners show what was written.
    CHECK(r.c.cueCard() && r.c.cueCard()->bankLeft == 1 && r.c.cueCard()->bankRight == 2);
    auto doc = decodeCardFile(bytes(text), "Fresh.U59");
    CHECK(doc.card && doc.card->sides[0] && doc.card->sides[1]);

    // Side 2 reads bank 2; the card stays fitted after the pass.
    const std::string saved = text;
    r.load("PARTITION: 479\n");
    r.run(1s);
    CHECK(!r.c.cardFitted());
    CHECK(r.c.fitCard(bytes(saved), "cards/Fresh.U59", "Fresh.U59"));
    CHECK(r.c.tapCard(0.9, kCardRect.y + 0.1 * kCardRect.h));
    CHECK(r.c.litCardCorner() == 1);
    CHECK(r.runUntil([&] { return cardIdle(r); }));
    CHECK(!r.c.litCardCorner());
    CHECK(r.c.cardFitted());
    CHECK(r.p.errors.empty());
}

TEST(a_side_can_hold_any_bank_and_the_corner_follows) {
    ControllerRig r;
    r.load("PROGRAM:\n76 11 01 02 03 91\nKEYSTROKES:\n82 21 91\n82 21 91\n");  // bank 1 twice
    CHECK(r.c.fitBlankCard("c", "c.U59"));
    feedTwoWrites(r, 1, 0);
    CHECK(r.c.cueCard() && r.c.cueCard()->bankLeft == 1 && r.c.cueCard()->bankRight == 1);
    CHECK(r.p.errors.empty());
}

TEST(version_1_card_stays_version_1_on_a_write) {
    ControllerRig r;
    const std::string card = writtenCard(r);
    auto oldDoc = decodeCardFile(bytes(card), "x");
    CHECK(oldDoc.card && oldDoc.card->sides[0]);
    CueCardContent cue;
    cue.title = "OLD CARD";
    cue.bankLeft = 1;
    cue.bankRight = 2;
    const std::string v1 = encodeCardText(*oldDoc.card->sides[0], &cue);
    r.p.cards["v1"] = v1;
    r.load("PROGRAM:\n76 12 04 05 06 91\nKEYSTROKES:\n82 21 91\n");
    CHECK(r.c.fitCard(bytes(v1), "v1", "v1.U59"));
    CHECK(r.c.cueCard() && r.c.cueCard()->bankLeft == 1 && r.c.cueCard()->bankRight == 2);
    CHECK(r.runUntil([&] { return r.c.keystrokesPlaying(); }));
    r.run(2s);
    CHECK(r.c.feedSide(1));  // either corner: the one side
    CHECK(r.runUntil([&] { return cardIdle(r); }));
    CHECK(r.runUntil([&] { return !r.c.keystrokesPlaying(); }));
    const std::string& text = r.p.cards["v1"];
    CHECK(text != v1);
    CHECK(startsWith(text, "Calc-U-59 Card 1.0\n"));
    CHECK(text.find("Banks: 1, 2") != std::string::npos);
    CHECK(r.c.cueCard() && r.c.cueCard()->bankRight == 2);
    CHECK(r.p.errors.empty());
}

TEST(write_keeps_the_side_changed_elsewhere_and_refuses_a_broken_file) {
    ControllerRig r;
    const std::string card = writtenCard(r);
    CardDocument other;
    other.cueCard = freshCardCue("Shared.U59");
    other.sides[1] = decodeCardFile(bytes(card), "x").card->sides[0];
    r.p.cards["s"] = encodeCardDocument(other);

    CardDocument mine;
    mine.cueCard = freshCardCue("Shared.U59");
    r.load("PROGRAM:\n76 12 04 05 06 91\nKEYSTROKES:\n82 21 91\n");
    CHECK(r.c.fitCard(bytes(encodeCardDocument(mine)), "s", "Shared.U59"));  // fitted before side 2 appeared
    CHECK(r.runUntil([&] { return r.c.keystrokesPlaying(); }));
    r.run(2s);
    CHECK(r.c.feedSide(0));
    CHECK(r.runUntil([&] { return cardIdle(r); }));
    auto merged = decodeCardFile(bytes(r.p.cards["s"]), "Shared.U59");
    CHECK(merged.card && merged.card->sides[0] && merged.card->sides[1]);

    r.load("PROGRAM:\n76 12 04 05 06 91\nKEYSTROKES:\n82 21 91\n");
    CHECK(r.c.fitCard(bytes(r.p.cards["s"]), "s", "Shared.U59"));
    r.p.cards["s"] = "Calc-U-59 Card 2.0\nbroken";
    CHECK(r.runUntil([&] { return r.c.keystrokesPlaying(); }));
    r.run(2s);
    CHECK(r.c.feedSide(0));
    CHECK(r.runUntil([&] { return cardIdle(r); }));
    CHECK_EQ(r.p.cards["s"], std::string("Calc-U-59 Card 2.0\nbroken"));  // left alone, reported
    CHECK(!r.p.errors.empty());
}

TEST(fresh_card_replaces_the_file_of_that_name_at_its_first_write_only) {
    ControllerRig r;
    r.p.cards["same"] = "Calc-U-59 Card 2.0\nwhatever was here";
    r.load(kTwoWrites);
    CHECK(r.c.fitBlankCard("same", "same.U59"));
    CHECK_EQ(r.p.cards["same"], std::string("Calc-U-59 Card 2.0\nwhatever was here"));  // still there
    feedTwoWrites(r, 0, 1);
    CHECK(decodeCardFile(bytes(r.p.cards["same"]), "same.U59").card.has_value());
    CHECK(r.p.errors.empty());
}

TEST(blank_side_fed_at_idle_writes_nothing) {
    ControllerRig r;
    r.load("PARTITION: 479\n");
    r.run(1s);
    CHECK(r.c.fitBlankCard("blank", "blank.U59"));
    CHECK(r.c.feedSide(0));
    r.run(5s);
    r.c.ejectCard();
    r.run(500ms);
    CHECK_EQ(r.p.cards.count("blank"), size_t{0});
    CHECK(r.c.cardFitted());
    CHECK(r.p.errors.empty());
}

TEST(blank_side_fed_at_partition_0_writes_nothing) {
    ControllerRig r;
    r.load("KEYSTROKES:\n92 21 64 82 62\n");  // 0 2nd Op 17
    CHECK(r.runUntil([&] { return r.c.keystrokesPlaying(); }));
    CHECK(r.runUntil([&] { return !r.c.keystrokesPlaying(); }));
    r.run(1s);
    CHECK(r.c.fitBlankCard("blank", "blank.U59"));
    CHECK(r.c.feedSide(0));
    r.run(5s);
    r.c.ejectCard();
    r.run(500ms);
    CHECK_EQ(r.p.cards.count("blank"), size_t{0});
    CHECK(r.c.cardFitted());
}

TEST(module_cue_card_covers_the_fitted_card_and_it_comes_back) {
    ControllerRig r;
    r.load("KEYSTROKES:\nWait: 1s\n21 31 92 82\nWait: 3s\n21 31 92 92\n");  // Pgm 01, later Pgm 00
    CHECK(r.c.fitBlankCard("c", "Mine.U59"));
    auto mine = [&] { return r.c.cueCard() && r.c.cueCard()->title == "Mine"; };
    CHECK(mine());
    CHECK(r.runUntil([&] { return !mine(); }));
    CHECK(!r.c.tapCard(0.1, kCardRect.y + 0.1 * kCardRect.h));  // not on show
    CHECK(cardIdle(r));
    CHECK(r.c.cardFitted());
    CHECK(r.runUntil(mine));
    CHECK(r.p.errors.empty());
}

TEST(card_corners_hit_only_the_top_corners) {
    const double top = kCardRect.y + 0.1 * kCardRect.h;
    CHECK(cardCornerAt(0.01, top) == 0);
    CHECK(cardCornerAt(0.99, top) == 1);
    CHECK(!cardCornerAt(0.5, top));
    CHECK(!cardCornerAt(0.1, kCardRect.y + 0.3 * kCardRect.h));  // the title row
    CHECK(!cardCornerAt(0.1, kCardRect.y - 0.001));
    CHECK(!cardCornerAt(0.21, top));
}

TEST(preset_creates_a_full_two_sided_card) {
    for (const std::string arms : {std::string("ArmCard: Results:1\nArmCard: Results:2\n"),
                                   std::string("ArmCard: Results:2\nArmCard: Results:1\n")}) {
        ControllerRig r;
        r.load("PROGRAM:\n76 11 01 96 02 96 91\n"  // Lbl A 1 Write 2 Write R/S
               "CUECARD:\nTitle: My Program\nA: run\nBanks: 3, 4\n"
               "KEYSTROKES:\n" + arms + "11\n");
        CHECK(r.runUntil([&] { return r.c.keystrokesPlaying(); }));
        CHECK(r.runUntil([&] { return !r.c.keystrokesPlaying() && r.p.cards.count("cards/Results.U59"); }, 60s));
        r.run(1s);
        const std::string& text = r.p.cards["cards/Results.U59"];
        CHECK(startsWith(text, "Calc-U-59 Card 2.0\n"));
        CHECK(text.find("Banks:") == std::string::npos);
        auto doc = decodeCardFile(bytes(text), "Results.U59");
        CHECK(doc.card && doc.card->sides[0] && doc.card->sides[1]);
        if (doc.card && doc.card->cueCard) {
            CHECK_EQ(doc.card->cueCard->title, std::string("My Program"));
            CHECK_EQ(doc.card->cueCard->labels[5], std::string("run"));
        }
        CHECK(r.c.cardFitted());
        CHECK(r.p.errors.empty());
    }
}

TEST(preset_cannot_feed_an_unreadable_file) {
    ControllerRig r;
    r.p.unreadableCards.insert("cards/Gone.U59");
    r.load("KEYSTROKES:\nInsertCard: Gone\n25\n");
    CHECK(r.runUntil([&] { return r.c.keystrokesPlaying(); }));
    CHECK(r.runUntil([&] { return !r.c.keystrokesPlaying(); }));
    CHECK(!r.p.errors.empty());
    CHECK(!r.c.cardFitted());
    CHECK_EQ(r.p.cards.count("cards/Gone.U59"), size_t{0});
}

TEST(preset_side_on_a_version_1_file_feeds_its_one_side) {
    ControllerRig r;
    const std::string card = writtenCard(r);
    r.p.cards["cards/Old.U59"] = encodeCardText(*decodeCardFile(bytes(card), "x").card->sides[0], nullptr);
    r.load("KEYSTROKES:\nInsertCard: Old:2\n");
    CHECK(r.runUntil([&] { return r.c.keystrokesPlaying(); }));
    CHECK(r.runUntil([&] { return !r.c.keystrokesPlaying(); }));
    r.run(1s);
    CHECK_EQ(int(r.c.session()->machine().readProgramStep(1)), 11);
    CHECK(r.p.errors.empty());
}

TEST(dropped_preset_loads_as_the_button_does) {
    ControllerRig r;
    CHECK(r.c.openDroppedFile(bytes("MODEL: TI-58\nPROGRAM:\n76 11\nKEYSTROKES:\n25\n"), "p", "p.ti58"));
    CHECK(r.c.model() == Model::TI58);
    CHECK_EQ(int(r.c.session()->machine().readProgramStep(1)), 11);
    CHECK(r.runUntil([&] { return r.c.keystrokesPlaying(); }));
    CHECK(r.p.errors.empty());
    CHECK(!r.c.openDroppedFile(std::nullopt, "p", "p.ti58"));
    CHECK(!r.p.errors.empty());  // reported, as a failed Open is
}

TEST(cooperative_script_waits_out_a_freeze_but_runs_its_directives) {
    VirtualRig r;
    r.host.frozen = true;
    std::vector<KeystrokeEvent> events{event(KeystrokeEvent::Kind::Resume)};
    events.push_back(keyEvents({83})[0]);
    r.keys.play(events);
    r.run(100ms);
    CHECK(r.host.at("control") != Clock::time_point{});  // Resume: runs while frozen
    r.host.pending = 0;                                  // … and is done
    r.run(300ms);
    CHECK(r.host.at("press 83") == Clock::time_point{});  // the key waits for the machine
    r.host.frozen = false;
    r.run(200ms);
    CHECK(r.host.at("press 83") != Clock::time_point{});
}
