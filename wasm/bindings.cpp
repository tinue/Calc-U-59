// Embind wrapper around Core/TI59Machine for the playable web calculator
// (docs/#play). Deliberately narrow surface: no debug/trace/printer/card
// API — those features are out of scope for the web build (see the plan
// at /Users/me/.claude/plans/replicated-riding-duckling.md).
//
// Built by tools/build_wasm.sh into docs/wasm/ti59-core.{js,wasm}.

#include <emscripten/bind.h>
#include <emscripten/val.h>
#include <vector>

#include "../../Core/TI59Machine.hpp"

using namespace emscripten;

namespace {

// Fixed to TI-59 for this build — see the plan's "machine variant is
// fixed" call. MachineVariant::TI58/TI58C are not exposed.
class WebMachine {
public:
    WebMachine() : m_machine(MachineVariant::TI59) {}

    void loadROM(val words) {
        auto v = vecFromJSArray<uint16_t>(words);
        m_machine.loadROM(v.data(), v.size());
    }

    void loadLibrary(val bytes) {
        auto v = vecFromJSArray<uint8_t>(bytes);
        m_machine.loadLibrary(v.data(), v.size());
    }

    void loadConstants(val bytes) {
        auto v = vecFromJSArray<uint8_t>(bytes);
        m_machine.loadConstants(v.data(), v.size());
    }

    void reset() { m_machine.reset(); }

    void pressKey(int row, int col) { m_machine.pressKey(row, col); }
    void releaseKey(int row, int col) { m_machine.releaseKey(row, col); }

    // Returns a plain JS object mirroring DisplaySnapshot. Built
    // element-by-element rather than via typed_memory_view, since the
    // source DisplaySnapshot is a local stack value here — a memory view
    // into it would dangle the instant this function returns.
    val getDisplay() const {
        DisplaySnapshot d = m_machine.getDisplay();

        val digits = val::array();
        val ctrl = val::array();
        for (int i = 0; i < 12; ++i) {
            digits.set(i, d.digits[i]);
            ctrl.set(i, d.ctrl[i]);
        }

        val obj = val::object();
        obj.set("digits", digits);
        obj.set("ctrl", ctrl);
        obj.set("dpPos", d.dpPos);
        obj.set("dpAfterglowMask", d.dpAfterglowMask);
        obj.set("suppressedMask", d.suppressedMask);
        obj.set("calcIndicator", d.calcIndicator);
        return obj;
    }

    void writeProgram(val keycodes) {
        auto v = vecFromJSArray<uint8_t>(keycodes);
        m_machine.writeProgram(v.data(), static_cast<int>(v.size()));
    }

    // nibbles16 must be exactly 16 bytes (one BCD register) — silently
    // ignored otherwise, matching the "no exceptions across the JS
    // boundary" shape of the rest of this binding.
    void writeDataRegister(int regNum, val nibbles16) {
        auto v = vecFromJSArray<uint8_t>(nibbles16);
        if (v.size() != 16) return;
        m_machine.writeDataRegister(regNum, v.data());
    }

    void setPartitionProgramRegs(int programRAMregs) {
        m_machine.setPartitionProgramRegs(programRAMregs);
    }

    int insertedModuleNumber() const { return m_machine.insertedModuleNumber(); }

    unsigned int stepUntilNextKeycode(unsigned int maxCycles) {
        return m_machine.stepUntilNextKeycode(maxCycles);
    }

    // Used for the one-off post-reset stabilization burst (300k steps),
    // matching EmulatorViewModel.swift's own `wrapper.stepN(300_000)` call
    // for the same purpose. NOT used for the paced real-time run loop —
    // TI59Machine::stepN treats its argument as a literal count of step()
    // calls, ignoring each step's weighted cycle cost (1 active / 4 IDLE).
    // That's fine for "run enough steps to settle," but wrong as a
    // real-time cycle budget: an IDLE-heavy period (e.g. the error blink)
    // would execute ~4x more simulated hardware time per tick than an
    // active one for the same budget, since IDLE steps recorded via
    // `stepN` cost 1 unit here despite standing for 4 real cycles.
    unsigned int stepN(unsigned int n) {
        return m_machine.stepN(n, false);
    }

    // The actual real-time run-loop primitive: loops step() until the
    // weighted cycle budget is exhausted (1 unit per active step, 4 per
    // IDLE step — the same weighting stepUntilNextKeycode's internal loop
    // and EmulatorViewModel.swift's startEmulationLoop both use), with no
    // early exit at keycode boundaries. No breakpoint support is exposed
    // in this build, so the breakpoint-hit flag TI59Machine::step() can
    // set is simply not checked.
    unsigned int stepCycles(unsigned int maxCycles) {
        unsigned int done = 0;
        while (done < maxCycles) {
            done += (m_machine.step() & 0x7FFFFFFFu);
        }
        return done;
    }

private:
    TI59Machine m_machine;
};

} // namespace

EMSCRIPTEN_BINDINGS(ti59_web) {
    class_<WebMachine>("WebMachine")
        .constructor<>()
        .function("loadROM", &WebMachine::loadROM)
        .function("loadLibrary", &WebMachine::loadLibrary)
        .function("loadConstants", &WebMachine::loadConstants)
        .function("reset", &WebMachine::reset)
        .function("pressKey", &WebMachine::pressKey)
        .function("releaseKey", &WebMachine::releaseKey)
        .function("getDisplay", &WebMachine::getDisplay)
        .function("writeProgram", &WebMachine::writeProgram)
        .function("writeDataRegister", &WebMachine::writeDataRegister)
        .function("setPartitionProgramRegs", &WebMachine::setPartitionProgramRegs)
        .function("insertedModuleNumber", &WebMachine::insertedModuleNumber)
        .function("stepUntilNextKeycode", &WebMachine::stepUntilNextKeycode)
        .function("stepN", &WebMachine::stepN)
        .function("stepCycles", &WebMachine::stepCycles);
}
