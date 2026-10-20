// Shared/ runtime: pacing, armed freezes, C-indicator smoothing, the
// emulation runner and a live EmulatorSession with KEYSTROKES playback.

#include "TestHarness.hpp"
#include "TestRoms.hpp"
#include "../Shared/EmulatorSession.hpp"
#include "../Shared/FrameSampler.hpp"
#include "../Shared/KeyMatrix.hpp"
#include <algorithm>
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
    CHECK_EQ(batchTargetCycles(Model::TI58C), 250);
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
    freeze.armPcChange();
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
    CHECK(m->lastStepBoundary().count > 0 && m->lastStepBoundary().cpu.pc == m->pc());  // where STEP stops
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

// ── Display: persistence of vision (Shared/DisplayPov) ──

TEST(display_pov_channel_hold_and_fade) {
    const double frame = 1.0 / 60;
    DisplayPov::Channel c;  // the whole display darkens alike: best duty = own duty
    CHECK_EQ(c.step(1.0, 1.0, frame), 1.0);                  // driven: on at once
    CHECK_EQ(c.step(0.4, 0.4, frame), 1.0);                  // part of a frame dark: within the hold
    CHECK_EQ(c.step(1.0, 1.0, frame), 1.0);
    CHECK_EQ(c.step(0.0, 0.0, frame), 1.0);                  // 17 ms dark …
    CHECK_EQ(c.step(0.0, 0.0, frame), 1.0);                  // … 33 ms: still held
    double fading = c.step(0.0, 0.0, frame);                 // 50 ms
    fading = c.step(0.0, 0.0, frame);                        // 67 ms: fading
    CHECK(fading < 1.0 && fading > DisplayPov::kCutoff);
    for (int i = 0; i < 6; ++i) c.step(0.0, 0.0, frame);     // 167 ms: out
    CHECK_EQ(c.level, 0.0);
    CHECK_EQ(c.brightness(1.0), 0.0);
}

// A position that gets less of the multiplex than the others — alternately
// 54% and 81% of the best-driven one, as the 60 Hz polls catch the error
// blink's short sweeps — is steadily dimmer, not flickering and not fading:
// a 67.5% share looks like √0.675 = 82%.
TEST(display_pov_channel_share_is_steady) {
    const double frame = 1.0 / 60;
    DisplayPov::Channel c;
    double lo = 1, hi = 0;
    for (int i = 0; i < 120; ++i) {
        c.step(i % 2 ? 0.54 * 0.9 : 0.81 * 0.9, 0.9, frame);
        if (i >= 30) { lo = std::min(lo, c.brightness(1.0)); hi = std::max(hi, c.brightness(1.0)); }
    }
    CHECK_EQ(c.level, 1.0);
    CHECK(lo > 0.79 && hi < 0.85);
    CHECK(hi - lo < 0.04);
}

namespace {

// A machine driven frame by frame (60 Hz of emulated time) through FrameSampler,
// as the apps do.
struct PovRig {
    Model model;
    std::unique_ptr<TI59Machine> m;
    FrameSampler sampler;
    double hz;
    double acc = 0;
    explicit PovRig(Model md) : model(md), m(testroms::makeMachine(md)), hz(info(md).instructionHz) {
        testroms::runToScanLoop(*m, md);
        m->takeDisplay();
    }
    FrameUpdate frame() {
        while (acc < hz / 60) acc += m->step() & TI59Machine::kWeightMask;
        acc -= hz / 60;
        return sampler.tick(*m, hz, 0, false);
    }
    static int brightest(const FrameUpdate& f) {
        int mx = 0;
        for (uint8_t l : f.led.digitLevel) mx = std::max(mx, int(l));
        return mx;
    }
    /// Press the last key of `keys` (the others are tapped first) and return the
    /// dimmest brightest-digit level over the next second.
    int dimmestDuring(std::initializer_list<int> setup, std::initializer_list<int> keys) {
        for (int k : setup) testroms::tap(*m, model, k);
        std::vector<int> v(keys);
        for (size_t i = 0; i + 1 < v.size(); ++i) testroms::tap(*m, model, v[i]);
        for (int i = 0; i < 10; ++i) frame();
        pressMatrix(*m, v.back());
        int dim = 255;
        for (int i = 0; i < 60; ++i) {
            if (i == 6) releaseMatrix(*m, v.back());
            dim = std::min(dim, brightest(frame()));
        }
        return dim;
    }
};

} // namespace

// Calibrated on a real TI-59: a digit key's ≈ 11 ms of dark display is
// invisible, sin (≈ 350 ms) visibly darkens.
TEST(display_pov_keys_as_the_eye_sees_them) {
    CHECK_EQ(PovRig(Model::TI59).dimmestDuring({82, 83}, {84}), 255);    // 1 2 → 3
    CHECK_EQ(PovRig(Model::TI59).dimmestDuring({84, 92}, {21, 33}), 0);  // 30 sin
}

// In the error blink each lit pass leaves IDLE before the sweep reaches the
// right-hand digits every time, so they get less of the multiplex. On a real
// TI-59 they look a little dimmer than the left ones, steadily — no flicker.
// Mid-phase (frames well inside a lit phase) every position must hold its
// brightness frame to frame, the rightmost must be dimmer than the leftmost
// but never dark (with the old per-poll brightness it flickered between 60%
// and 87% on the TI-58, and before that dropped to dark).
TEST(display_pov_error_blink_is_steady) {
    for (Model model : {Model::TI58, Model::TI59}) {
        PovRig r(model);
        for (int k : {92, 35}) testroms::tap(*r.m, model, k);  // 0 1/x → error blink
        std::vector<FrameUpdate> f;
        for (int i = 0; i < 600; ++i) f.push_back(r.frame());
        // "9.9999999 99": position 10 is the leftmost lit one (not fading).
        auto lit = [&](size_t i) { return f[i].led.digitLevel[10] >= 200; };
        int midFrames = 0, worstSpread = 0, dimmest = 255, phases = 0;
        int lo[12], hi[12];
        bool inPhase = false;
        for (size_t i = 3; i + 3 < f.size(); ++i) {
            bool mid = true;
            for (size_t j = i - 3; j <= i + 3; ++j) mid = mid && lit(j);
            if (!mid) {
                inPhase = false;
                continue;
            }
            if (!inPhase) {  // a new lit phase: compare frames within it only
                for (int p = 0; p < 12; ++p) lo[p] = hi[p] = f[i].led.digitLevel[p];
                inPhase = true;
                ++phases;
            }
            if (phases == 1) continue;  // the shares still settle from the display before the blink
            ++midFrames;
            for (int p = 0; p < 12; ++p) {
                lo[p] = std::min(lo[p], int(f[i].led.digitLevel[p]));
                hi[p] = std::max(hi[p], int(f[i].led.digitLevel[p]));
                worstSpread = std::max(worstSpread, hi[p] - lo[p]);
            }
            CHECK(f[i].led.digitLevel[10] >= 245);
            dimmest = std::min(dimmest, int(f[i].led.digitLevel[0]));
        }
        CHECK(midFrames > 100);
        CHECK(worstSpread <= 13);              // ≤ 5%: no visible flicker
        CHECK(dimmest > 150 && dimmest < 245); // a little dimmer, never dark
    }
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

// The run loop must deliver emulated time at the real rate even when every
// batch costs extra (oversleep, the batchDone callback). Pacing each batch
// from a fresh now() lost that time — 0.83× real time on macOS, which made the
// TI-59 error blink 1.07 s instead of the measured 0.90 s.
TEST(runner_keeps_real_time) {
    auto m = testroms::makeMachine(Model::TI59);
    testroms::runToScanLoop(*m, Model::TI59);
    FreezeController freeze(Model::TI59);
    EmulationRunner::Callbacks cb;
    cb.batchDone = [] { std::this_thread::sleep_for(2ms); };  // a slow UI callback
    EmulationRunner runner(*m, Model::TI59, freeze, cb);
    uint64_t t0 = m->elapsedTicks();
    auto w0 = std::chrono::steady_clock::now();
    runner.start();
    std::this_thread::sleep_for(1500ms);
    uint64_t t1 = m->elapsedTicks();
    double wall = std::chrono::duration<double>(std::chrono::steady_clock::now() - w0).count();
    runner.stop();
    double ratio = double(t1 - t0) / info(Model::TI59).instructionHz / wall;
    CHECK(ratio > 0.95 && ratio < 1.05);
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
