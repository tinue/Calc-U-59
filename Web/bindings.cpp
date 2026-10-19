// The web calculator's adapter to Shared/ (Web/, reference/WebClient.md):
// one cu59::SessionController, run single-threaded (Threading::Cooperative —
// a static host can't send the headers SharedArrayBuffer needs), behind an embind surface for
// calc-engine-worker.js. Like Qt6/app/EmulatorController it only translates:
// files in, input forwarded, what changed() names posted back as plain JS
// objects for the page to draw. reference/NewGUIGuide.md describes the
// pattern.
//
// The web build is deliberately narrower than the apps: TI-59 only, no
// printer, debugger or traces, one virtual magnetic card.
//
// Built by Web/build.sh into dist/wasm/ti59-core.{js,wasm}.

#include <emscripten/bind.h>
#include <emscripten/val.h>
#include <chrono>
#include <cstdio>
#include <deque>
#include <map>
#include <string>

#include "../Shared/KeyMatrix.hpp"
#include "../Shared/KeyboardMap.hpp"
#include "../Shared/LedGeometry.hpp"
#include "../Shared/ModuleCatalog.hpp"
#include "../Shared/SessionController.hpp"
#include "../Shared/SettingsKeys.hpp"
#include "../Shared/SevenSegment.hpp"

using namespace emscripten;

namespace {

constexpr const char* kCardPath = "web:card";
constexpr const char* kCardName = "card.U59";

val spansToJS(const std::vector<cu59::LabelSpan>& spans) {
    val out = val::array();
    for (size_t i = 0; i < spans.size(); ++i) {
        val s = val::object();
        s.set("start", spans[i].startCol);
        s.set("end", spans[i].endCol);
        s.set("label", spans[i].label);
        out.set(i, s);
    }
    return out;
}

std::string hexColor(uint32_t rgb) {
    char buf[8];
    std::snprintf(buf, sizeof buf, "#%06x", rgb & 0xFFFFFFu);
    return buf;
}

class WebController : public cu59::SessionController::Platform {
public:
    /// `files`: {fileName: text} of the ROM files requiredRomFiles() names,
    /// fetched ahead; any other file (a module chosen later) is read when
    /// needed through the worker's readRomFile(name) → text or null.
    /// What changed is posted to the page as {type, …} messages.
    explicit WebController(val files) {
        val names = val::global("Object").call<val>("keys", files);
        const int n = names["length"].as<int>();
        for (int i = 0; i < n; ++i) {
            std::string name = names[i].as<std::string>();
            m_files[name] = files[name].as<std::string>();
        }
        m_c = std::make_unique<cu59::SessionController>(
            *this, [this](const std::string& name) { return readFile(name); }, m_files["cuecards.txt"], cu59::settings::kDefaultModuleID,
            cu59::Threading::Cooperative);
        m_c->startMachine(cu59::Model::TI59);
        drain();
    }

    /// The 60 Hz frame: emulation, key input, display.
    void tick() {
        m_c->tick(std::chrono::steady_clock::now());
        drain();
    }

    // On-screen keys go through the keyboard path, so a click shorter than the
    // ROM's debounce still holds the key the minimum 100 ms.
    void pointerDown(int row, int col) {
        m_c->keyboardDown({cu59::matrixCode(row, col)});
        drain();
    }
    void pointerUp() { m_c->keyboardUp(); drain(); }

    /// A key event as KeyboardMap takes it; unbound keys do nothing.
    void keyDown(int key, int produced, bool isLetter, bool shift, bool command) {
        auto codes = matrixCodes(key, produced, isLetter, shift, command);
        if (codes.empty()) return;
        m_c->keyboardDown(codes);
        drain();
    }
    void keyUp(int key, int produced, bool isLetter, bool shift, bool command) {
        if (matrixCodes(key, produced, isLetter, shift, command).empty()) return;
        m_c->keyboardUp();
        drain();
    }
    void blur() { m_c->keyboardRelease(); drain(); }

    void changeModule(std::string id) { m_c->changeModule(id); drain(); }

    /// A preset's bytes; returns the errors it reported.
    val loadState(val bytes) {
        m_errors = val::array();
        m_c->loadStateFile(vecFromJSArray<uint8_t>(bytes));
        drain();
        val errors = m_errors;
        m_errors = val::undefined();
        return errors;
    }

    /// The one virtual card: blank until something is written to it, then
    /// whatever was last written (it lasts for the page session).
    void queueCard() {
        if (m_cardText.empty()) m_c->insertBlankCard(kCardPath, kCardName);
        else m_c->insertCard(std::vector<uint8_t>(m_cardText.begin(), m_cardText.end()), kCardPath, kCardName);
        drain();
    }

    void suspend() { m_c->suspend(); }
    void resume() { m_c->resumeAfterSuspend(); }

private:
    std::optional<std::string> readFile(const std::string& name) {
        auto it = m_files.find(name);
        if (it != m_files.end()) return it->second;
        val text = val::global("readRomFile")(name);
        if (!text.isString()) return std::nullopt;
        return m_files[name] = text.as<std::string>();
    }

    static std::vector<uint8_t> matrixCodes(int key, int produced, bool isLetter, bool shift, bool command) {
        return cu59::matrixCodesFor({static_cast<char32_t>(key), static_cast<char32_t>(produced), isLetter, shift, command});
    }

    // ── Platform ──────────────────────────────────────────────────────────────
    void runOnUiThread(std::function<void()> job) override { m_queue.push_back(std::move(job)); }
    std::optional<std::string> readConstantMemory() override { return std::nullopt; }
    void writeConstantMemory(const std::string&) override {}
    bool writeCard(const std::string&, const std::string& text) override {
        m_cardText = text;
        return true;
    }
    // No file system: a preset's "Trace:" line fails to open and is reported.
    cu59::SessionController::TraceLocation traceLocation() override { return {"/no-traces", 1'000'000}; }
    bool traceAvailable() override { return false; }
    void saveLastUsedModel(cu59::Model) override {}
    void saveModuleID(const std::string&) override {}
    void error(const std::string& title, const std::string& message) override {
        if (!m_errors.isUndefined()) m_errors.call<void>("push", message);
        else post("error", "message", val(title + ": " + message));
    }
    void diagnostic(const std::string& message) override { val::global("console").call<void>("debug", message); }
    void changed(uint32_t c) override { m_changes |= c; }

    /// UI jobs queued by the session, then one post per kind of change.
    void drain() {
        while (!m_queue.empty()) {
            auto job = std::move(m_queue.front());
            m_queue.pop_front();
            job();
        }
        uint32_t c = m_changes;
        m_changes = 0;
        using S = cu59::SessionController;
        if (c & (S::DisplayChanged | S::ModelChanged)) post("display", "cells", display());
        if (c & (S::CueCardChanged | S::ModelChanged)) post("cueCard", "card", cueCard());
        if (c & S::ModelChanged) post("module", "id", val(m_c->moduleID()));
        if (c & (S::RunStateChanged | S::ModelChanged)) post("heldKey", "key", val(m_c->heldKey()));
    }

    static void post(const char* type, const char* field, val payload) {
        val msg = val::object();
        msg.set("type", std::string(type));
        msg.set(field, payload);
        val::global("postMessage")(msg);
    }

    // Per cell (0 = rightmost) its segment mask, brightness and decimal point
    // (0–1), flat: [segments, level, dp] × 12. Cell 11 shows the "C" indicator
    // while it is lit.
    val display() const {
        const cu59::LedFrame& d = m_c->display();
        const double calc = m_c->calcIndicatorOpacity();
        float cells[36];
        for (int i = 0; i < 12; ++i) {
            const bool c = i == 11 && calc > 0;
            cells[i * 3] = c ? cu59::kSegmentsC : cu59::segmentsFor(d.digits[i], d.ctrl[i], d.digitLevel[i] == 0);
            cells[i * 3 + 1] = static_cast<float>(c ? calc : d.digitLevel[i] / 255.0);
            cells[i * 3 + 2] = d.dpLevel[i] / 255.0f;
        }
        return val::global("Float32Array").new_(typed_memory_view(36, cells));
    }

    val cueCard() const {
        const auto& card = m_c->cueCard();
        if (!card) return val::null();
        val o = val::object();
        o.set("template", std::string(cu59::toString(card->template_)));
        o.set("title", card->title);
        o.set("id", card->id);
        o.set("style", std::string(cu59::toString(card->style)));
        o.set("ink", hexColor(cu59::cueCardInk(*card)));
        o.set("row1", card->row1);
        o.set("row1Align", std::string(cu59::toString(card->row1Align)));
        o.set("row2", card->row2);
        o.set("row2Align", std::string(cu59::toString(card->row2Align)));
        o.set("row2R", card->row2R);
        o.set("row2RAlign", std::string(cu59::toString(card->row2RAlign)));
        o.set("topSpans", spansToJS(cu59::labelSpans(*card, 0)));
        o.set("bottomSpans", spansToJS(cu59::labelSpans(*card, 1)));
        return o;
    }

    std::map<std::string, std::string> m_files;
    std::unique_ptr<cu59::SessionController> m_c;
    std::deque<std::function<void()>> m_queue;
    uint32_t m_changes = 0;
    std::string m_cardText;
    val m_errors = val::undefined();
};

// ── Free functions ───────────────────────────────────────────────────────────

/// The files the TI-59 needs before WebController can start, besides
/// cuecards.txt: its ROM and constants and the start-up module.
val requiredRomFiles(std::string cuecards) {
    val out = val::array();
    int n = 0;
    for (const char* f : cu59::info(cu59::Model::TI59).romFiles) out.set(n++, std::string(f));
    for (const char* f : cu59::info(cu59::Model::TI59).constFiles) out.set(n++, std::string(f));
    if (auto file = cu59::moduleRomFile(cuecards, cu59::settings::kDefaultModuleID)) out.set(n++, *file);
    return out;
}

/// Every module in menu order: {id, menuTitle}.
val modules(std::string cuecards) {
    val out = val::array();
    int n = 0;
    for (const auto& m : cu59::allModuleMetadata(cuecards)) {
        val o = val::object();
        o.set("id", m.id);
        o.set("menuTitle", m.menuTitle);
        out.set(n++, o);
    }
    return out;
}

/// The classic LED style's shapes for a w × h digit cell, and its colours.
val ledGeometry(double w, double h) {
    const cu59::LedStyleParams& p = cu59::ledStyleParams(cu59::LedStyle::Classic);
    val segments = val::array();
    auto segs = cu59::classicSegments(w, h);
    for (size_t i = 0; i < segs.size(); ++i) {
        val centres = val::array();
        for (size_t j = 0; j < segs[i].centres.size(); ++j) {
            val pt = val::array();
            pt.set(0, segs[i].centres[j].x);
            pt.set(1, segs[i].centres[j].y);
            centres.set(j, pt);
        }
        val s = val::object();
        s.set("centres", centres);
        s.set("radius", segs[i].radius);
        segments.set(i, s);
    }
    cu59::LedDot dot = cu59::decimalPoint(w, h);
    val dp = val::object();
    dp.set("cx", dot.cx);
    dp.set("cy", dot.cy);
    dp.set("diameter", dot.diameter);
    auto rgb = [](double r, double g, double b) {
        val c = val::array();
        c.set(0, r * 255);
        c.set(1, g * 255);
        c.set(2, b * 255);
        return c;
    };
    val o = val::object();
    o.set("segments", segments);
    o.set("dp", dp);
    o.set("slant", p.slant);
    o.set("active", rgb(p.activeR, p.activeG, p.activeB));
    o.set("inactive", rgb(p.inactiveR, p.inactiveG, p.inactiveB));
    o.set("inactiveAlpha", p.inactiveAlpha);
    o.set("glowBlurPerRadius", p.glowBlurPerWidth);
    o.set("glowOpacity", p.glowOpacity);
    o.set("dpGlowBlurPerDiameter", cu59::kDecimalGlowBlurPerDiameter);
    o.set("dpGlowOpacity", cu59::kDecimalGlowOpacity);
    o.set("background", rgb(cu59::kLedBackgroundR, cu59::kLedBackgroundG, cu59::kLedBackgroundB));
    return o;
}

} // namespace

EMSCRIPTEN_BINDINGS(ti59_web) {
    class_<WebController>("WebController")
        .constructor<val>()
        .function("tick", &WebController::tick)
        .function("pointerDown", &WebController::pointerDown)
        .function("pointerUp", &WebController::pointerUp)
        .function("keyDown", &WebController::keyDown)
        .function("keyUp", &WebController::keyUp)
        .function("blur", &WebController::blur)
        .function("changeModule", &WebController::changeModule)
        .function("loadState", &WebController::loadState)
        .function("queueCard", &WebController::queueCard)
        .function("suspend", &WebController::suspend)
        .function("resume", &WebController::resume);
    function("requiredRomFiles", &requiredRomFiles);
    function("modules", &modules);
    function("ledGeometry", &ledGeometry);
}
