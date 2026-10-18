// Shared/StateApplier: apply parsed state files to a real machine.

#include "TestHarness.hpp"
#include "TestRoms.hpp"
#include "../Shared/DebugSnapshots.hpp"
#include "../Shared/StateApplier.hpp"
#include <filesystem>

using namespace cu59;

namespace {
double reg(const TI59Machine& m, int n) { return m.readDataReg(n); }
}

TEST(apply_state_full) {
    auto m = testroms::makeMachine(Model::TI59);
    testroms::runToScanLoop(*m, Model::TI59);
    auto r = parseStateFile("PARTITION: 239\nPROGRAM:\n76 11 42 05 91\n010 85\nREGISTERS:\n05 = 3.25\n99 = -7\n", 959);
    CHECK(!stateFilePartitionError(r, Model::TI59));
    applyState(*m, r, Model::TI59);
    CHECK_EQ(m->partitionProgramRegs(), 30);
    auto steps = programSteps(*m);
    CHECK_EQ(steps.size(), size_t{240});
    CHECK_EQ(steps[0], 76);
    CHECK_EQ(steps[4], 91);
    CHECK_EQ(steps[5], 0);
    CHECK_EQ(steps[10], 85);
    CHECK_EQ(reg(*m, 5), 3.25);
    CHECK_EQ(reg(*m, 99), -7.0);
    // The machine still runs normally afterwards.
    CHECK(testroms::runToScanLoop(*m, Model::TI59));
}

TEST(apply_state_ti58_default_partition_and_limits) {
    auto r = parseStateFile("PROGRAM:\n1 2 3\n");
    auto m = testroms::makeMachine(Model::TI58);
    applyState(*m, r, Model::TI58);
    CHECK_EQ(m->partitionProgramRegs(), 30);  // no PARTITION: → 239 on the 60-register models
    auto big = parseStateFile("PARTITION: 959\n", 959);
    auto err = stateFilePartitionError(big, Model::TI58);
    CHECK(err.has_value());
    if (err) CHECK_EQ(*err, std::string("State file partition (959) exceeds TI-58 maximum (479) — load aborted."));
    CHECK(!stateFilePartitionError(big, Model::TI59));
}

TEST(apply_state_ti58c_keeps_extra_registers) {
    auto m = testroms::makeMachine(Model::TI58C);
    testroms::runToScanLoop(*m, Model::TI58C);
    uint8_t before[16];
    m->copyRAMReg(60, before);
    auto r = parseStateFile("REGISTERS:\nH02 = 9\n00 = 1\n", 479, true);
    applyState(*m, r, Model::TI58C);
    uint8_t after60[16], h2[16];
    m->copyRAMReg(60, after60);
    m->copyRAMReg(62, h2);
    CHECK(std::equal(before, before + 16, after60));
    CHECK_EQ(TI59Machine::decodeBCD(h2), 9.0);
}

TEST(apply_skip_reset_touches_only_given_sections) {
    auto m = testroms::makeMachine(Model::TI59);
    testroms::runToScanLoop(*m, Model::TI59);
    applyState(*m, parseStateFile("PROGRAM:\n11 12 13\nREGISTERS:\n01 = 5\n", 959), Model::TI59);
    int partition = m->partitionProgramRegs();
    applySkipResetState(*m, parseStateFile("SKIP-RESET: on\nREGISTERS:\n02 = 6\n", 959), Model::TI59);
    CHECK_EQ(m->partitionProgramRegs(), partition);
    auto kept = programSteps(*m);
    CHECK_EQ(kept[1], 12);  // program untouched
    CHECK_EQ(reg(*m, 1), 5.0);
    CHECK_EQ(reg(*m, 2), 6.0);
    applySkipResetState(*m, parseStateFile("PARTITION: 159\nPROGRAM:\n99\n", 959), Model::TI59);
    CHECK_EQ(m->partitionProgramRegs(), 20);
    auto rewritten = programSteps(*m);
    CHECK_EQ(rewritten[0], 99);
    CHECK_EQ(rewritten[1], 0);   // zero-padded rewrite
}

TEST(apply_every_example_file) {
    int applied = 0;
    for (const auto& e : std::filesystem::recursive_directory_iterator("examples")) {
        auto ext = e.path().extension().string();
        if (ext != ".ti59" && ext != ".ti58" && ext != ".ti58c") continue;
        auto text = testroms::readFile(e.path().string());
        auto pre = prescanStateFile(*text, ext == ".ti58" ? Model::TI58 : ext == ".ti58c" ? Model::TI58C : Model::TI59);
        Model model = pre.targetModel;
        auto r = parseStateFile(*text, info(model).hasLargeMemory ? 959 : 479, info(model).hasConstantMemory);
        if (stateFilePartitionError(r, model)) continue;
        auto m = testroms::makeMachine(model);
        if (r.skipReset) {
            testroms::runToScanLoop(*m, model);
            applySkipResetState(*m, r, model);
        } else {
            applyState(*m, r, model);
        }
        bool ok = testroms::runToScanLoop(*m, model);
        if (!ok) std::fprintf(stderr, "  no scan loop after %s\n", e.path().string().c_str());
        CHECK(ok);
        ++applied;
    }
    CHECK(applied >= 40);
}
