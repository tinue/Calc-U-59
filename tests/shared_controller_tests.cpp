// Shared/SessionController: the flows both apps run through it — model
// switches, presets, the TI-58C memory file, freezes, the ASM overlay and
// the fixes that came with moving them out of the frontends.

#include "TestHarness.hpp"
#include "TestRoms.hpp"
#include "../Shared/SessionController.hpp"
#include <chrono>
#include <deque>
#include <mutex>
#include <thread>

using namespace cu59;
using namespace std::chrono_literals;

namespace {

/// A frontend without a UI: the UI-thread queue is pumped by the test.
struct FakePlatform : SessionController::Platform {
    std::mutex mutex;
    std::deque<std::function<void()>> queue;
    std::optional<std::string> mem;
    int memWrites = 0;
    std::vector<std::string> errors;
    uint32_t changes = 0;

    void runOnUiThread(std::function<void()> job) override {
        std::lock_guard<std::mutex> lock(mutex);
        queue.push_back(std::move(job));
    }
    std::optional<std::string> readConstantMemory() override { return mem; }
    void writeConstantMemory(const std::string& text) override { mem = text; ++memWrites; }
    bool writeCard(const std::string&, const std::string&) override { return true; }
    SessionController::TraceLocation traceLocation() override { return {std::filesystem::temp_directory_path(), 1'000'000}; }
    void saveLastUsedModel(Model) override {}
    void saveModuleID(const std::string&) override {}
    void error(const std::string& title, const std::string& message) override { errors.push_back(title + ": " + message); }
    void diagnostic(const std::string&) override {}
    void changed(uint32_t c) override { changes |= c; }

    void pump() {
        for (;;) {
            std::function<void()> job;
            {
                std::lock_guard<std::mutex> lock(mutex);
                if (queue.empty()) return;
                job = std::move(queue.front());
                queue.pop_front();
            }
            job();
        }
    }
};

template <class F> bool pumpUntil(FakePlatform& p, F cond, std::chrono::milliseconds timeout = 3000ms) {
    auto end = std::chrono::steady_clock::now() + timeout;
    while (std::chrono::steady_clock::now() < end) {
        p.pump();
        if (cond()) return true;
        std::this_thread::sleep_for(5ms);
    }
    p.pump();
    return cond();
}

std::string catalog() { return testroms::readFile("roms/solid-state/cuecards.txt").value_or(""); }

std::vector<uint8_t> bytes(const std::string& s) { return std::vector<uint8_t>(s.begin(), s.end()); }

bool waitForScanLoop(SessionController& c) {
    for (int i = 0; i < 600; ++i) {
        if (info(c.model()).scanLoop.contains(c.session()->machine().pc())) return true;
        std::this_thread::sleep_for(5ms);
    }
    return false;
}

} // namespace

TEST(controller_loads_a_preset_for_another_model) {
    FakePlatform p;
    SessionController c(p, testroms::reader(), catalog(), "ML");
    CHECK(c.startMachine(Model::TI59));
    c.loadStateFile(bytes("MODEL: TI-58\nREGISTERS:\n05 = 3.25\n"));
    CHECK(c.model() == Model::TI58);
    CHECK(c.session()->isRunning());
    CHECK_EQ(c.session()->machine().readDataReg(5), 3.25);
    CHECK(p.errors.empty());
}

TEST(controller_reports_parse_errors_and_partition_errors) {
    FakePlatform p;
    SessionController c(p, testroms::reader(), catalog(), "ML");
    CHECK(c.startMachine(Model::TI58));
    c.loadStateFile(bytes("PARTITION: 959\n"));  // beyond the TI-58's 479
    CHECK_EQ(p.errors.size(), size_t{1});
    c.loadStateFile(std::nullopt);
    CHECK_EQ(p.errors.back(), std::string("State file load error: Cannot read file."));
    c.loadStateFile(bytes("\xff\xfe"));
    CHECK(p.errors.back().find("not valid UTF-8") != std::string::npos);
}

TEST(controller_load_while_frozen_ends_running_without_tracing) {
    FakePlatform p;
    SessionController c(p, testroms::reader(), catalog(), "ML");
    CHECK(c.startMachine(Model::TI59));
    c.freeze(FreezeOwner::Calculator);
    CHECK(c.isFrozen());
    CHECK(pumpUntil(p, [&] { return !c.debug().cpuHistory().empty(); }));
    c.loadStateFile(bytes("REGISTERS:\n01 = 7\n"));
    CHECK(!c.isFrozen());
    CHECK(!c.session()->debugState().frozen);
    CHECK(c.session()->isRunning());
    CHECK_EQ(c.session()->machine().traceFlags(), static_cast<uint32_t>(TRACE_NONE));
}

TEST(controller_skip_reset_logs_ignored_sections) {
    FakePlatform p;
    SessionController c(p, testroms::reader(), catalog(), "ML");
    CHECK(c.startMachine(Model::TI59));
    c.loadStateFile(bytes("SKIP-RESET: on\nMODEL: TI-58\nPRINTER: off\nREGISTERS:\n02 = 6\n"));
    CHECK(c.model() == Model::TI59);
    CHECK(c.printerConnected());
    CHECK(c.logText().find("SKIP-RESET: MODEL: ignored") != std::string::npos);
    CHECK(c.logText().find("SKIP-RESET: PRINTER: ignored") != std::string::npos);
    CHECK_EQ(c.session()->machine().readDataReg(2), 6.0);
}

TEST(controller_constant_memory_keeps_the_loaded_card) {
    FakePlatform p;
    SessionController c(p, testroms::reader(), catalog(), "ML");
    CHECK(c.startMachine(Model::TI58C));
    c.loadStateFile(bytes("CUECARD:\nTemplate: MagnetCard\nTitle: KEEP ME\nREGISTERS:\n03 = 1\n"));
    CHECK(p.mem && p.mem->find("KEEP ME") != std::string::npos);
    // Unchanged RAM: the debounced persist does not write again.
    int writes = p.memWrites;
    auto t = std::chrono::steady_clock::now();
    c.session()->stop();
    c.session()->sync([] {});
    c.tick(t);
    c.tick(t + 600ms);
    CHECK_EQ(p.memWrites, writes);
}

TEST(controller_model_switch_keeps_printer_and_log_resets_freeze) {
    FakePlatform p;
    SessionController c(p, testroms::reader(), catalog(), "ML");
    CHECK(c.startMachine(Model::TI59));
    c.setPrinterConnected(false);
    c.dumpVars();
    c.armPcChange();
    CHECK(c.debugState().pcChangeArmed);
    CHECK(c.startMachine(Model::TI58));
    CHECK(!c.session()->machine().isPrinterConnected());
    CHECK(!c.debugState().pcChangeArmed && !c.isFrozen());
    CHECK(c.logText().find("──") != std::string::npos);  // the dump survived the switch
    CHECK(c.cardState() == SessionController::CardState::NoCard);
}

TEST(controller_rom_failure_keeps_the_running_machine) {
    FakePlatform p;
    // Only the TI-58C chips are missing.
    auto reader = [](const std::string& name) -> std::optional<std::string> {
        if (name.rfind("CD24", 0) == 0) return std::nullopt;
        return testroms::reader()(name);
    };
    SessionController c(p, reader, catalog(), "ML");
    CHECK(c.startMachine(Model::TI59));
    CHECK(!c.startMachine(Model::TI58C));
    CHECK(c.model() == Model::TI59);
    CHECK(c.hasMachine() && c.session()->isRunning());
    CHECK_EQ(p.errors.size(), size_t{1});
}

TEST(controller_bad_module_changes_nothing) {
    FakePlatform p;
    SessionController c(p, testroms::reader(), catalog(), "ML");
    CHECK(c.startMachine(Model::TI59));
    CHECK(!c.selectModule("ZZ"));
    CHECK_EQ(c.moduleID(), std::string("ML"));
    CHECK_EQ(p.errors.size(), size_t{1});
}

TEST(controller_resume_before_the_frozen_view_drops_it) {
    FakePlatform p;
    SessionController c(p, testroms::reader(), catalog(), "ML");
    CHECK(c.startMachine(Model::TI59));
    c.freeze(FreezeOwner::Cpu);
    c.resume();  // before the frozen view arrives
    std::this_thread::sleep_for(200ms);  // the freeze job ran (it is queued before the loop)
    p.changes = 0;
    p.pump();
    CHECK(!c.isFrozen());
    CHECK(c.debug().cpuHistory().empty());
    CHECK((p.changes & SessionController::CpuChanged) == 0);
}

TEST(controller_events_of_a_replaced_machine_are_ignored) {
    FakePlatform p;
    SessionController c(p, testroms::reader(), catalog(), "ML");
    CHECK(c.startMachine(Model::TI59));
    c.freeze(FreezeOwner::Calculator);
    c.session()->sync([] {});  // the old machine's frozen view is queued
    CHECK(c.startMachine(Model::TI58));
    p.pump();
    CHECK(!c.isFrozen());
    CHECK(c.debug().cpuHistory().empty());
}

TEST(controller_asm_overlay) {
    FakePlatform p;
    SessionController c(p, testroms::reader(), catalog(), "ML");
    c.runAsm();
    CHECK_EQ(c.asmStatus(), std::string("No ASM overlay loaded."));
    c.loadAsm(std::string("HEX:\n0x0A01\n"), "a.asm");
    CHECK_EQ(c.asmStatus(), std::string("Machine not initialized yet."));
    CHECK(c.startMachine(Model::TI59));
    c.loadAsm(std::nullopt, "a.asm");
    CHECK_EQ(c.asmStatus(), std::string("Could not read ASM file."));
    c.loadAsm(std::string("HEX:\n0x0A01 0x0A01\n"), "a.asm");
    CHECK_EQ(c.asmStatus(), std::string("Loaded 2 word(s) at 0x1800."));
    CHECK(waitForScanLoop(c));
    c.armScanLoopExit();
    c.runAsm();
    CHECK(c.asmActive());
    CHECK(c.isFrozen() && c.debugState().owner == FreezeOwner::Cpu);
    CHECK(!c.session()->isRunning());
    CHECK(!c.debug().cpuHistory().empty());
    c.clearAsm();
    CHECK(!c.asmActive() && !c.isFrozen() && c.session()->isRunning());
    CHECK_EQ(c.asmStatus(), std::string("ASM overlay cleared."));
}
