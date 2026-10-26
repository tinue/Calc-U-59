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

/// A parsed file's sections as a reload stage.
ReloadStage stageOf(const LoadStateResult& r) {
    ReloadStage st;
    if (r.partitionWasExplicit) st.partitionMaxStep = r.partitionMaxStep;
    st.programSteps = r.programSteps;
    st.registers = r.registers;
    return st;
}

TEST(reload_touches_only_given_sections) {
    auto m = testroms::makeMachine(Model::TI59);
    testroms::runToScanLoop(*m, Model::TI59);
    applyState(*m, parseStateFile("PROGRAM:\n11 12 13\nREGISTERS:\n01 = 5\n", 959), Model::TI59);
    int partition = m->partitionProgramRegs();
    applyReload(*m, stageOf(parseStateFile("REGISTERS:\n02 = 6\n", 959)), Model::TI59);
    CHECK_EQ(m->partitionProgramRegs(), partition);
    auto kept = programSteps(*m);
    CHECK_EQ(kept[1], 12);  // program untouched
    CHECK_EQ(reg(*m, 1), 5.0);
    CHECK_EQ(reg(*m, 2), 6.0);
    applyReload(*m, stageOf(parseStateFile("PARTITION: 159\nPROGRAM:\n99\n", 959)), Model::TI59);
    CHECK_EQ(m->partitionProgramRegs(), 20);
    auto rewritten = programSteps(*m);
    CHECK_EQ(rewritten[0], 99);
    CHECK_EQ(rewritten[1], 12);  // only the listed step
    CHECK_EQ(reg(*m, 1), 5.0);
    CHECK_EQ(reg(*m, 2), 6.0);
    // A listed step beyond the partition is still written (registers as program).
    applyReload(*m, stageOf(parseStateFile("PROGRAM:\n940 77\n", 959)), Model::TI59);
    uint8_t r2[16];
    m->copyRAMReg(117, r2);      // steps 936-943 = R02 (RAM[119 - 2])
    CHECK_EQ(r2[(940 & 7) * 2] + 10 * r2[(940 & 7) * 2 + 1], 77);
    CHECK_EQ(reg(*m, 1), 5.0);
}

TEST(apply_every_example_file) {
    int applied = 0;
    for (const auto& e : std::filesystem::recursive_directory_iterator("examples")) {
        auto ext = e.path().extension().string();
        if (ext != ".ti59" && ext != ".ti58" && ext != ".ti58c") continue;
        auto text = testroms::readFile(e.path().string());
        Model model = stateFileModel(*text, ext == ".ti58" ? Model::TI58 : ext == ".ti58c" ? Model::TI58C : Model::TI59);
        auto r = parseStateFile(*text, info(model).maxStep(), info(model).hasConstantMemory);
        if (stateFilePartitionError(r, model)) continue;
        auto m = testroms::makeMachine(model);
        applyState(*m, r, model);
        bool ok = testroms::runToScanLoop(*m, model);
        for (const auto& k : r.keystrokes) {  // reloads, without the keys between them
            if (k.kind != KeystrokeEvent::Kind::Reload) continue;
            applyReload(*m, *k.reload, model);
            ok = ok && testroms::runToScanLoop(*m, model);
        }
        if (!ok) std::fprintf(stderr, "  no scan loop after %s\n", e.path().string().c_str());
        CHECK(ok);
        ++applied;
    }
    CHECK(applied >= 40);
}

// Rnn as the ROM addresses it: STO/RCL by key must agree with
// readDataReg/writeDataRegister (and so with REGISTERS:) on every model. The
// TI-58C's extra registers H00–H03 sit above R00 and must not shift it.
TEST(data_registers_match_the_rom) {
    constexpr int kKey7 = 62, kKey0 = 92, kSto = 42, kRcl = 43, kClr = 25;
    for (Model model : {Model::TI59, Model::TI58, Model::TI58C}) {
        auto m = testroms::makeMachine(model);
        CHECK(testroms::runToScanLoop(*m, model));
        for (int k : {kKey7, kSto, kKey0, kKey0, kClr}) testroms::tap(*m, model, k);
        CHECK_EQ(reg(*m, 0), 7.0);

        auto r = parseStateFile("REGISTERS:\n00 = 5\n", 959, model == Model::TI58C);
        applyReload(*m, stageOf(r), model);
        for (int k : {kRcl, kKey0, kKey0}) testroms::tap(*m, model, k);
        CHECK_EQ(testroms::displayText(*m), std::string("5"));
    }

    // TI-58C partitioned like a TI-59 (examples/repartition.ti58c): code 60 41
    // in steps 480–481 (RAM 60, kept by power-off) gives partition 0.19, and
    // the ROM then addresses Rnn as RAM[119 - nn]: R59 is RAM 60, R56 RAM 63.
    auto m = testroms::makeMachine(Model::TI58C);
    CHECK(testroms::runToScanLoop(*m, Model::TI58C));
    uint8_t r60[16];
    m->copyRAMReg(60, r60);
    r60[0] = 0; r60[1] = 6; r60[2] = 1; r60[3] = 4;
    m->writeRAMReg(60, r60);
    m->reset();
    CHECK(testroms::runToScanLoop(*m, Model::TI58C));
    CHECK_EQ(m->dataRegCount(), 120);
    for (int k : {kKey7, kSto, 73, 64, kClr}) testroms::tap(*m, Model::TI58C, k);  // 7 STO 59
    m->copyRAMReg(60, r60);
    CHECK_EQ(TI59Machine::decodeBCD(r60), 7.0);
    CHECK_EQ(reg(*m, 59), 7.0);
    auto r = parseStateFile("REGISTERS:\n56 = 5\n", 479, true);
    applyReload(*m, stageOf(r), Model::TI58C);
    uint8_t r63[16];
    m->copyRAMReg(63, r63);
    CHECK_EQ(TI59Machine::decodeBCD(r63), 5.0);
    CHECK_EQ(reg(*m, 0), 0.0);  // R00 would be RAM 119: no hardware
}

// A reload is the user keying in changes: only the listed steps and registers.
TEST(reload_changes_only_the_listed_steps_and_registers) {
    auto m = testroms::makeMachine(Model::TI58);
    applyState(*m, parseStateFile("PROGRAM:\n11 12 13 14\nREGISTERS:\n01 = 1\n02 = 2\n"), Model::TI58);
    ReloadStage stage;
    stage.programSteps = {{1, 22}};
    stage.registers = {{2, encodeBcd("5"), false}};
    applyReload(*m, stage, Model::TI58);
    CHECK_EQ(int(m->readProgramStep(0)), 11);
    CHECK_EQ(int(m->readProgramStep(1)), 22);
    CHECK_EQ(int(m->readProgramStep(3)), 14);  // not listed: kept
    CHECK_EQ(m->readDataReg(1), 1.0);
    CHECK_EQ(m->readDataReg(2), 5.0);
}
