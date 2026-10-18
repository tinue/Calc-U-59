// Shared/ runtime: pacing, armed freezes, C-indicator smoothing, the
// emulation runner and a live EmulatorSession with KEYSTROKES playback.

#include "TestHarness.hpp"
#include "TestRoms.hpp"
#include "../Shared/EmulatorSession.hpp"
#include <chrono>
#include <cmath>
#include <thread>

using namespace cu59;
using namespace std::chrono_literals;

namespace {

template <class F> bool waitFor(F cond, std::chrono::milliseconds timeout) {
    auto end = std::chrono::steady_clock::now() + timeout;
    while (std::chrono::steady_clock::now() < end) {
        if (cond()) return true;
        std::this_thread::sleep_for(5ms);
    }
    return cond();
}

struct RecordingListener : EmulatorSession::Listener {
    std::atomic<int> freezes{0}, playbackDone{0};
    std::atomic<bool> frozenWhenFired{false};
    EmulatorSession* session = nullptr;
    std::mutex mutex;
    std::vector<std::string> logs;
    void frozenViewReady(uint64_t, FrozenViewReason reason) override {
        // The freeze is applied before any listener runs.
        if (reason == FrozenViewReason::FreezeFired && session) frozenWhenFired = session->frozen();
        ++freezes;
    }
    void playbackFinished() override { ++playbackDone; }
    void logLine(const std::string& l) override { std::lock_guard<std::mutex> lock(mutex); logs.push_back(l); }
};

} // namespace

TEST(pacing_batches_are_cycle_weighted_with_carry) {
    auto m = testroms::makeMachine(Model::TI59);
    testroms::runToScanLoop(*m, Model::TI59);
    FreezeController freeze(Model::TI59);
    int32_t target = batchTargetCycles(Model::TI59);
    CHECK_EQ(target, 284);
    CHECK_EQ(batchTargetCycles(Model::TI58C), 240);
    uint64_t before = m->elapsedTicks();
    int32_t carry = 0;
    for (int i = 0; i < 50; ++i) {  // one emulated second
        auto r = runBatch(*m, carry, target, freeze);
        CHECK(r.stop == BatchResult::Stop::None);
        CHECK(carry >= 0 && carry < 8);  // overshoot is at most one IDLE step
    }
    uint64_t ticks = m->elapsedTicks() - before;
    CHECK(ticks >= 50u * 284u && ticks < 50u * 284u + 8u);
}

TEST(pacing_sleep_rule) {
    CHECK(shouldSleep(false, 0x0100, false, Model::TI59));
    CHECK(!shouldSleep(true, 0x0100, false, Model::TI59));      // full speed races productive code
    CHECK(shouldSleep(true, 0x0640, false, Model::TI59));       // … but never the scan loop
    CHECK(shouldSleep(true, 0x0100, true, Model::TI59));        // … or a hardware poll
    CHECK(shouldSleep(true, 0x0A00, false, Model::TI58C));      // TI-58C's wider scan range
    CHECK(!shouldSleep(true, 0x0A00, false, Model::TI59));
}

TEST(freeze_on_scan_loop_exit_fires_on_key) {
    auto m = testroms::makeMachine(Model::TI59);
    testroms::runToScanLoop(*m, Model::TI59);
    FreezeController freeze(Model::TI59);
    freeze.armScanLoopExit(m->pc());
    CHECK(freeze.scanLoopExitArmed());
    int32_t carry = 0;
    auto idle = runBatch(*m, carry, 284, freeze);
    CHECK(idle.stop == BatchResult::Stop::None);  // still scanning
    pressMatrix(*m, 83);
    BatchResult r;
    for (int i = 0; i < 50 && r.stop == BatchResult::Stop::None; ++i) r = runBatch(*m, carry, 284, freeze);
    CHECK(r.stop == BatchResult::Stop::Freeze);
    CHECK(r.freezeOwner == FreezeOwner::Cpu);
    CHECK(!freeze.scanLoopExitArmed());
    CHECK(!info(Model::TI59).scanLoop.contains(m->pc()));
}

TEST(freeze_on_pc_change_and_mutual_exclusion) {
    auto m = testroms::makeMachine(Model::TI59);
    testroms::runToScanLoop(*m, Model::TI59);
    const uint8_t prog[] = {76, 11, 85, 1, 95, 61, 0, 0};  // LBL A + 1 = GTO 000
    m->writeProgram(prog, sizeof prog);
    FreezeController freeze(Model::TI59);
    freeze.armScanLoopExit(m->pc());
    freeze.armPcChange(*m);
    CHECK(freeze.pcChangeArmed() && !freeze.scanLoopExitArmed());
    int32_t carry = 0;
    BatchResult r;
    for (int i = 0; i < 20 && r.stop == BatchResult::Stop::None; ++i) r = runBatch(*m, carry, 284, freeze);
    CHECK(r.stop == BatchResult::Stop::None);  // idle: the calculator PC doesn't move
    pressMatrix(*m, 11);  // A: runs the program
    for (int i = 0; i < 50 && r.stop == BatchResult::Stop::None; ++i) r = runBatch(*m, carry, 284, freeze);
    releaseMatrix(*m, 11);
    CHECK(r.stop == BatchResult::Stop::Freeze);
    CHECK(r.freezeOwner == FreezeOwner::Calculator);
}

TEST(calc_indicator_smoothing) {
    FrameSampler s;
    CHECK(std::fabs(s.updateCalcIndicator(1.0f) - 0.65) < 1e-9);  // instant rise to 0.65 × duty
    CHECK(std::fabs(s.updateCalcIndicator(0.0f) - 0.65) < 1e-9);  // one zero frame: hold
    CHECK(std::fabs(s.updateCalcIndicator(0.0f) - 0.30) < 1e-9);  // then decay 0.35
    CHECK(std::fabs(s.updateCalcIndicator(0.0f) - 0.0) < 1e-9);   // 0.70 → clamped at 0
    s.updateCalcIndicator(1.0f);
    double v = s.updateCalcIndicator(0.5f);  // proportional fall: alpha = min(0.5, 0.325/0.65)
    CHECK(std::fabs(v - (0.65 + 0.5 * (0.325 - 0.65))) < 1e-9);
}

TEST(runner_post_and_sync_are_serial) {
    auto m = testroms::makeMachine(Model::TI59);
    FreezeController freeze(Model::TI59);
    EmulationRunner runner(*m, Model::TI59, freeze, {});
    std::vector<int> order;
    std::mutex mu;
    runner.post([&] { std::lock_guard<std::mutex> l(mu); order.push_back(1); });
    runner.sync([&] { std::lock_guard<std::mutex> l(mu); order.push_back(2); });
    CHECK(order == (std::vector<int>{1, 2}));
    runner.start();
    CHECK(runner.isRunning());
    std::this_thread::sleep_for(100ms);
    runner.stop();
    uint64_t ticks = 0;
    runner.sync([&] { ticks = m->elapsedTicks(); });  // runs after the loop exited
    CHECK(!runner.isRunning());
    // ~0.1 s at 14218.75 Hz plus the boot burst being paced too.
    CHECK(ticks > 500 && ticks < 14219 / 2);
}

TEST(session_plays_keystrokes_in_real_time) {
    RecordingListener listener;
    EmulatorSession session(Model::TI59, testroms::reader(), std::string("TMC0541.txt"), listener);
    CHECK(!session.moduleImage().empty());
    session.setFullSpeed(true);  // boot quickly; the scan loop still runs at regular speed
    session.start();
    CHECK(waitFor([&] { return info(Model::TI59).scanLoop.contains(session.machine().pc()); }, 5000ms));
    session.setFullSpeed(false);
    auto r = parseStateFile("KEYSTROKES:\n25 83 85 84 95\nZeroElapseTime:\nWait: 50ms\nReportElapseTime:\n");
    session.playKeystrokes(r.keystrokes);
    CHECK(waitFor([&] { return listener.playbackDone.load() == 1; }, 8000ms));
    CHECK_EQ(testroms::displayText(session.machine()), std::string("5"));
    {
        std::lock_guard<std::mutex> lock(listener.mutex);
        CHECK_EQ(listener.logs.size(), size_t{1});
        if (!listener.logs.empty()) CHECK(listener.logs[0].rfind("Elapsed: 0:00.", 0) == 0);
    }
    CHECK(!session.isFullSpeed());
    session.stop();
}

TEST(session_freeze_fires_through_listener) {
    RecordingListener listener;
    EmulatorSession session(Model::TI59, testroms::reader(), std::nullopt, listener);
    listener.session = &session;
    session.setFullSpeed(true);
    session.start();
    CHECK(waitFor([&] { return info(Model::TI59).scanLoop.contains(session.machine().pc()); }, 5000ms));
    session.armScanLoopExit();
    CHECK(session.debugState().scanLoopExitArmed);
    CHECK(session.machine().traceFlags() != TRACE_NONE);  // an armed freeze needs the trace ring
    session.keyboardDown({83});
    CHECK(waitFor([&] { return listener.freezes.load() == 1; }, 2000ms));
    CHECK(listener.frozenWhenFired.load());
    DebugState s = session.debugState();
    CHECK(s.frozen && s.owner == FreezeOwner::Cpu && !s.scanLoopExitArmed);
    CHECK(!session.isRunning());
    session.keyboardRelease();
    session.resume();
    CHECK(!session.debugState().frozen && session.isRunning());
    CHECK_EQ(session.machine().traceFlags(), static_cast<uint32_t>(TRACE_NONE));
    session.stop();
}

TEST(session_steps_only_when_frozen_and_arms_exclude) {
    RecordingListener listener;
    EmulatorSession session(Model::TI59, testroms::reader(), std::nullopt, listener);
    session.stepKeycode();  // not frozen: nothing posted
    session.sync([] {});
    CHECK_EQ(listener.freezes.load(), 0);
    session.armPcChange();
    session.armScanLoopExit();
    CHECK(session.debugState().scanLoopExitArmed && !session.debugState().pcChangeArmed);
    session.armPcChange();
    CHECK(!session.debugState().scanLoopExitArmed && session.debugState().pcChangeArmed);
    session.start();
    session.freeze(FreezeOwner::Calculator);
    CHECK(waitFor([&] { return listener.freezes.load() == 1; }, 2000ms));
    DebugState s = session.debugState();
    CHECK(s.frozen && s.owner == FreezeOwner::Calculator && !s.pcChangeArmed);
    session.stepInstruction();
    session.stepKeycode();
    CHECK(waitFor([&] { return listener.freezes.load() == 3; }, 2000ms));
    CHECK(!session.isRunning());
    uint64_t before = session.debugState().generation;
    session.resume();
    CHECK(session.debugState().generation != before);  // views built for the freeze are now stale
    session.stop();
}

TEST(trace_flags_for_consumers) {
    CHECK_EQ(traceFlagsFor({}), static_cast<uint32_t>(TRACE_NONE));
    TraceConsumers c;
    c.frozen = true;
    CHECK_EQ(traceFlagsFor(c), static_cast<uint32_t>(TRACE_PC | TRACE_REGS_FULL));
}
