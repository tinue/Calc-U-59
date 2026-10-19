#include "DebugLog.hpp"
#include "Bcd.hpp"
#include "DebugSnapshots.hpp"
#include <algorithm>
#include <cstdio>
#include <utility>

namespace cu59 {

namespace {

bool allZero(const uint8_t* n) { return std::all_of(n, n + 16, [](uint8_t v) { return v == 0; }); }

} // namespace

void RingLog::write(std::string line) {
    m_buf[static_cast<size_t>(m_head % kCapacity)] = std::move(line);
    ++m_head;
}

void RingLog::writeAll(const std::vector<std::string>& lines) {
    for (const auto& l : lines) write(l);
}

void RingLog::clear() {
    m_head = 0;
    m_lastDisplayHead = 0;
}

std::string RingLog::displayText() {
    long head = m_head;
    long newSinceLast = head - m_lastDisplayHead;
    m_lastDisplayHead = head;
    long available = std::min<long>(head, kCapacity);
    if (available <= 0) return "";
    long show = newSinceLast > kLinesPerPage ? std::min<long>(kLinesPerPage, available)
                                             : std::min<long>(kLinesPerPage * kPageCap, available);
    std::string out;
    for (long i = head - show; i < head; ++i) {
        if (i > head - show) out += '\n';
        out += m_buf[static_cast<size_t>(i % kCapacity)];
    }
    return out;
}

std::vector<std::string> dumpVars(const TI59Machine& m) {
    const int visible = partitionDataRegCount(m);
    if (visible <= 0) return {"── Vars: no data registers in current partition ──"};

    char buf[96];
    std::snprintf(buf, sizeof buf, "── Vars V00–V%02d ──", visible - 1);
    std::vector<std::string> lines{buf};
    std::vector<std::pair<std::string, double>> entries;
    for (const auto& r : nonZeroDataRegs(m)) {
        std::snprintf(buf, sizeof buf, "%c%02d", r.isHidden ? 'H' : 'V', r.num);
        entries.emplace_back(buf, r.value);
    }
    std::sort(entries.begin(), entries.end(), [](const auto& a, const auto& b) { return a.first < b.first; });
    for (const auto& [label, value] : entries) {
        // 13 significant digits, the BCD mantissa width: %.10g would round away
        // precision-loss bugs (1731371734.999090 printing as 1731371735).
        std::snprintf(buf, sizeof buf, "%s = %.13g", label.c_str(), value);
        lines.emplace_back(buf);
    }
    return lines;
}

std::vector<std::string> dumpScom(const TI59Machine& m) {
    CpuFrame cpu = m.snapshotCPU();
    std::vector<std::string> lines{"── SCOM ──"};
    char buf[32];
    for (int s = 0; s < 16; ++s) {
        std::snprintf(buf, sizeof buf, "S%02d %s", s, nibbleHex(cpu.SCOM[s], true).c_str());
        lines.emplace_back(buf);
    }
    return lines;
}

std::vector<std::string> dumpProg(const TI59Machine& m) {
    const int progRegs = m.partitionProgramRegs();
    char buf[64];
    std::snprintf(buf, sizeof buf, "── Prog P000–P%03d (key codes) ──", std::max(progRegs - 1, 0));
    std::vector<std::string> lines{buf};
    for (int reg = 0; reg < progRegs; ++reg) {
        uint8_t n[16];
        m.copyRAMReg(reg, n);
        if (allZero(n)) continue;
        // Storage order (units-tens pairs), deliberately not the register-line format.
        std::string pairs;
        for (int i = 0; i < 16; i += 2) {
            char p[4];
            std::snprintf(p, sizeof p, "%X%X", n[i + 1], n[i]);
            if (!pairs.empty()) pairs += ' ';
            pairs += p;
        }
        std::snprintf(buf, sizeof buf, "P%03d: ", reg);
        lines.push_back(buf + pairs);
    }
    return lines;
}

std::vector<std::string> dumpMemory(const TI59Machine& m) {
    std::vector<std::string> lines{"── Registers (raw values) ──"};
    for (int reg = 0; reg < m.ramRegCount(); ++reg) {
        Nibbles16 n{};
        m.copyRAMReg(reg, n.data());
        if (allZero(n.data())) continue;
        char label[16];
        std::snprintf(label, sizeof label, "R%03d: ", reg);
        lines.push_back(label + registerLineHex(n));
    }
    return lines;
}

} // namespace cu59
