#pragma once
#include "../Core/TI59Machine.hpp"
#include "MachineModelInfo.hpp"
#include <optional>
#include <string>
#include <vector>

// The LOG debug tab: a ring buffer of log lines and the dump commands
// (Vars, SCOM, Prog, Memory) that write into it.

namespace cu59 {

class RingLog {
public:
    static constexpr int kCapacity = 2000;
    static constexpr int kLinesPerPage = 40;  ///< roughly the visible lines in the log pane
    static constexpr int kPageCap = 10;       ///< most pages copied to the pane at once

    void write(std::string line);
    void writeAll(const std::vector<std::string>& lines);
    void clear();

    /// The pane's text after new writes. Adapts to the logging rate: more
    /// than a page of new lines since the last call shows only the newest
    /// page; otherwise up to kPageCap pages.
    std::string displayText();

private:
    std::vector<std::string> m_buf = std::vector<std::string>(kCapacity);
    long m_head = 0;             ///< monotonically increasing write position
    long m_lastDisplayHead = 0;
};

/// Non-zero data registers of the current partition, sorted by label: normal
/// registers as Vnn, the TI-58C's extra registers as Hnn.
std::vector<std::string> dumpVars(const TI59Machine& m);

/// All 16 SCOM rows, nibble 15 first.
std::vector<std::string> dumpScom(const TI59Machine& m);

/// Program registers as nibble pairs in storage order (units nibble first).
std::vector<std::string> dumpProg(const TI59Machine& m);

/// Every non-zero RAM register as a register line.
std::vector<std::string> dumpMemory(const TI59Machine& m);

} // namespace cu59
