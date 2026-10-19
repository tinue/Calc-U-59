#pragma once
#include "../Shared/KeyMatrix.hpp"
#include "../Shared/RomLoader.hpp"
#include <fstream>
#include <memory>
#include <sstream>

// Test fixtures: read roms/ from the working directory (the repo root under
// CTest) and boot a machine the way the apps do.

namespace testroms {

inline std::optional<std::string> readFile(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return std::nullopt;
    std::ostringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

/// ResourceReader over roms/calculator and roms/solid-state.
inline cu59::ResourceReader reader() {
    return [](const std::string& name) -> std::optional<std::string> {
        if (auto t = readFile("roms/calculator/" + name)) return t;
        return readFile("roms/solid-state/" + name);
    };
}

/// Build a machine with ROM, constants and the Master Library, as the apps do.
inline std::unique_ptr<TI59Machine> makeMachine(cu59::Model model) {
    auto m = std::make_unique<TI59Machine>(cu59::toVariant(model));
    auto words = cu59::loadRom(model, reader());
    m->loadROM(words.data(), words.size());
    if (auto lib = cu59::loadModule("TMC0541.txt", reader())) m->loadLibrary(lib->data(), lib->size());
    auto k = cu59::loadConstants(model, reader());
    m->loadConstants(k.data(), k.size());
    return m;
}

/// Run until the CPU sits in the keyboard scan loop (or give up).
inline bool runToScanLoop(TI59Machine& m, cu59::Model model, uint32_t maxSteps = 2'000'000) {
    const auto& range = cu59::info(model).scanLoop;
    for (uint32_t i = 0; i < maxSteps; i += 100) {
        m.stepN(100, false);
        if (range.contains(m.pc())) return true;
    }
    return false;
}

/// Display as text, leftmost digit first, using the LED decode rules
/// (ctrl 0/1/8/9 = digit, 5/6 = minus/degree, others blank). Positions not
/// driven since the last poll (suppressed, blank, or the CPU computing) are skipped.
inline std::string displayText(TI59Machine& m) {
    DisplaySnapshot d = m.takeDisplay();
    std::string s;
    for (int i = 11; i >= 0; --i) {
        if (d.digitDuty[i] == 0) continue;
        switch (d.ctrl[i]) {
        case 0: case 1: case 8: case 9: s += static_cast<char>('0' + (d.digits[i] & 0xF) % 10); break;
        case 5: s += d.digits[i] == 0 ? '-' : 'o'; break;
        case 6: s += '-'; break;
        default: break;
        }
    }
    return s;
}

/// Press a matrix key, hold ~100 ms of emulated time, release, settle.
inline void tap(TI59Machine& m, cu59::Model model, int code) {
    cu59::pressMatrix(m, code);
    m.stepN(static_cast<uint32_t>(cu59::info(model).instructionHz * 0.1), false);
    cu59::releaseMatrix(m, code);
    m.stepN(static_cast<uint32_t>(cu59::info(model).instructionHz * 0.1), false);
    runToScanLoop(m, model);
}

} // namespace testroms
