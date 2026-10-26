#pragma once
#include "Bcd.hpp"
#include "CueCard.hpp"
#include "MachineModelInfo.hpp"
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

// Parser for .ti59 / .ti58 / .ti58c state files (presets). The format —
// PARTITION, PROGRAM, REGISTERS, KEYSTROKES, CUECARD and CARD sections, reloads
// and the SOLID-STATE-MODULE / PRINTER / MODEL / SKIP-RESET directives — is specified
// in reference/StateFileFormat.md. Applying a parsed file to a machine is
// StateApplier's job; playing back KEYSTROKES is KeySequencer's.

namespace cu59 {

struct ProgramStep { int stepAddr; uint8_t keycode; };

struct RegisterValue {
    /// The number as written: 00–99 for a normal register, 00–03 for an
    /// extra (H-prefixed, TI-58C-only) register. Branch on isHidden, never on
    /// the range — normal TI-59 registers go up to 99.
    int regNum;
    Nibbles16 nibbles;
    bool isHidden;
};

/// PROGRAM / REGISTERS / CUECARD / PARTITION sections after a KEYSTROKES
/// section: applied during playback once the calculator is idle, like a
/// SKIP-RESET load (reference/StateFileFormat.md § "Reloads").
struct ReloadStage {
    std::optional<int> partitionMaxStep;
    std::vector<ProgramStep> programSteps;
    std::vector<RegisterValue> registers;
    std::optional<CueCardContent> cueCard;
};

/// A CARD: … END-CARD block: an in-memory magnetic card bank built from
/// program steps and registers (reference/StateFileFormat.md § "CARD").
struct CardDefinition {
    std::string name;                         ///< "mem:…", as written
    int bank = 0;                             ///< 1–4
    bool protect = false;
    std::optional<int> partitionMaxStep;      ///< header partition; default: the calculator's
    std::vector<ProgramStep> programSteps;    ///< absolute steps inside the bank
    std::vector<RegisterValue> registers;     ///< registers inside the bank
    std::optional<CueCardContent> cueCard;
};

/// "mem:" names an in-memory card; anything else a file in the card folder.
bool isMemoryCardName(std::string_view name);

/// One event of the KEYSTROKES section.
struct KeystrokeEvent {
    enum class Kind {
        Key,              ///< press matrix code `code` (row×10 + col)
        ToggleTrace,      ///< virtual key 99: toggle the printer's TRACE latch
        Wait,             ///< explicit pause of `seconds`, at the current speed
        Trace,            ///< start a CPU trace to `traceName`, or stop it (nullopt)
        FullSpeed,        ///< persistent full speed until RegularSpeed / end of script
        RegularSpeed,
        ZeroElapseTime,   ///< snapshot the core's elapsed-tick counter
        ReportElapseTime, ///< log the time since the last ZeroElapseTime
        Reload,           ///< apply `reload` once the calculator is idle
        ArmCard,          ///< queue card `cardName` for the next card wait of a program or Write
        InsertCard,       ///< insert card `cardName` once idle; wait until it has passed
    };
    Kind kind = Kind::Key;
    uint8_t code = 0;
    double seconds = 0;
    std::optional<std::string> traceName;
    std::shared_ptr<const ReloadStage> reload;
    std::string cardName;
    std::shared_ptr<const CardDefinition> card;  ///< its CARD: block, if the file has one
};

struct LoadStateResult {
    int partitionMaxStep = 479;
    bool partitionWasExplicit = false;        ///< file had a PARTITION: line
    std::vector<ProgramStep> programSteps;    ///< sparse; unlisted steps are 00
    std::vector<RegisterValue> registers;
    std::vector<KeystrokeEvent> keystrokes;
    std::optional<CueCardContent> cueCard;
    std::optional<std::string> solidStateModuleID;
    std::optional<bool> printerConnected;
    std::optional<Model> model;               ///< MODEL: switch variant before applying
    bool skipReset = false;                   ///< SKIP-RESET: apply without resetting
    bool usesCardReader = false;              ///< CARD:, ArmCard: or InsertCard: (TI-59 only)
    std::vector<std::string> errors;
};

/// Parse a state file. maxStepAddr bounds step-number prefixes (479, or 959
/// on the TI-59); allowHiddenRegisters admits H00–H03 (TI-58C).
LoadStateResult parseStateFile(std::string_view text, int maxStepAddr = 479, bool allowHiddenRegisters = false);

/// What a loader needs before parsing: whether SKIP-RESET is set, and which
/// model the file targets (MODEL:, ignored under SKIP-RESET; `current` if absent
/// or unknown).
struct StateFilePrescan { bool skipReset; Model targetModel; };
StateFilePrescan prescanStateFile(std::string_view text, Model current);

/// Parse a "MODEL:" value ("TI-59", "TI-58", "TI-58C", any case).
std::optional<Model> modelFromName(std::string_view name);

} // namespace cu59
