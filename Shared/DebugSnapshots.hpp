#pragma once
#include "../Core/TI59Machine.hpp"
#include "MachineModelInfo.hpp"
#include "ModuleImage.hpp"
#include <array>
#include <optional>
#include <set>
#include <string>
#include <vector>

// The CALCULATOR debug tab's data: a calculator-level view decoded from SCOM
// and RAM (registers, flags, AOS/HIR state, return stack, the program steps
// around the current one). Field meanings: reference/DebugAPI.md and
// rom/TI59-ROM-Guide.md § "SCOM register map". Built at 60 Hz while the tab
// is visible, so the frontends compare with operator== before redrawing.

namespace cu59 {

/// Calculator PC from SCOM[0] nibbles 4–7: n7×800 + n6×80 + n5×8 + n4.
int decodeProgramCounter(const CpuFrame& cpu);

/// Program steps of the current partition (clamped to physical RAM: the
/// partition nibble can transiently claim more registers than exist).
std::vector<uint8_t> programSteps(const TI59Machine& m);

/// The 384 constant-ROM keycodes (PRG SOURCE = 8).
std::vector<uint8_t> romKeycodes(const TI59Machine& m);

struct StepEntry {
    int stepNum;
    uint8_t keycode;
    std::string mnemonic;  ///< "STO", or "12" for an operand step
    bool isCurrent;
    bool operator==(const StepEntry& o) const {
        return stepNum == o.stepNum && keycode == o.keycode && mnemonic == o.mnemonic && isCurrent == o.isCurrent;
    }
};

/// Listing of `keycodes` with operands shown as numbers.
std::vector<StepEntry> programListing(const std::vector<uint8_t>& keycodes, const std::set<int>& argSteps,
                                      int currentStep);

enum class AngleMode { Deg, Rad, Grad };

struct LiveDebugSnapshot {
    struct RegEntry {
        int num;          ///< 0–99 for Rnn, 0–3 for Hnn
        double value;
        bool isHidden;    ///< TI-58C extra register
        bool operator==(const RegEntry& o) const { return num == o.num && value == o.value && isHidden == o.isHidden; }
    };
    std::vector<RegEntry> nonZeroRegs;
    int dataRegCount = 0;
    int programRegCount = 0;            ///< the claimed partition, not clamped

    std::vector<StepEntry> programWindow;  ///< ±5 steps around currentStep
    int currentStep = -1;               ///< the next step to execute; -1 = unknown

    std::array<double, 8> hir{};        ///< HIR 1–8 (SCOM[1..8])
    double tRegister = 0;               ///< SCOM[11]
    double xValue = 0;                  ///< X, the working value (decodeX)
    std::string xRaw;                   ///< X's register as "C=…"/"A=…" when it holds no number, else ""
    std::array<bool, 10> calcFlags{};   ///< user flags 0–9

    std::string fixIndicator = "0";
    std::string statusRegister = "0000000000000000";  ///< SCOM[0] (HIR 0), nibble 15 first
    uint16_t fA = 0, fB = 0;
    std::string engIndicator, secondIndicator, invIndicator;

    std::optional<AngleMode> angleMode;
    uint8_t prSourceFlag = 0;
    ProgramSource programSource = ProgramSource::UserProgram;
    int pendingOpsCount = 0;

    std::array<std::string, 16> scomRows;   ///< nibbles 0→15 as lowercase hex
    std::array<uint8_t, 6> returnAddressSourceFlags{};  ///< L1–L6
    std::array<int, 6> returnAddresses{};               ///< L1–L6

    bool operator==(const LiveDebugSnapshot& o) const;
    bool operator!=(const LiveDebugSnapshot& o) const { return !(*this == o); }
};

/// Result of one live build: the snapshot plus what the frontend needs for the
/// full program listing.
struct LiveDebugBuild {
    LiveDebugSnapshot snap;
    std::vector<uint8_t> sourceKeycodes;   ///< keycodes of the active program source
    std::set<int> argSteps;                ///< operand steps within sourceKeycodes
    /// Solid State: the program number from the library range disagreed with
    /// the Pgm register in SCOM[9] — {range program, SCOM program}, for logging.
    std::optional<std::pair<int, int>> libProgramMismatch;
};

// ── CPU tab ──────────────────────────────────────────────────────────────────

struct InspectorEntry {
    uint16_t pc;
    uint16_t opcode;
    std::string disasm;
    CpuFrame frame;     ///< state after the instruction (zeroed for the not-yet-executed one)
    bool isHistory;     ///< executed; false for the next instruction
    bool isCurrent;     ///< the last executed instruction
};

/// Frozen CPU view: every frame still in the trace ring (read, not drained),
/// then the certain next instruction — shown even at the same PC (WAIT/KEY
/// loops re-execute one instruction).
std::vector<InspectorEntry> inspectorHistory(const TI59Machine& m);

/// Running CPU view: the newest `count` of `frames`, the last one current.
std::vector<InspectorEntry> recentInstructions(const std::vector<CpuFrame>& frames, size_t count = 32);

/// The ring's frames, read without draining (up to 1024).
std::vector<CpuFrame> readTraceRing(const TI59Machine& m);
/// The same into `frames`, reusing its storage (the 60 Hz read).
void readTraceRing(const TI59Machine& m, std::vector<CpuFrame>& frames);

/// The CPU state a CALCULATOR view is built from: the last step boundary
/// (about to dispatch a program byte) or idle entry the CPU latched, never
/// the middle of an operation; the live state only before the first one.
TMC0501::StepBoundary calcViewState(const TI59Machine& m);

/// Build the live snapshot from `state`. `romCache` holds the 384 ROM keycodes
/// once filled (constant per machine). The current step is the next one to
/// execute, as the calculator's LRN display shows it.
LiveDebugBuild buildLiveSnapshot(const TI59Machine& m, Model model, const ModuleImage& module,
                                 std::vector<uint8_t>& romCache, const TMC0501::StepBoundary& state);

} // namespace cu59
