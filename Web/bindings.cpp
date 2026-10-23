// The web client's adapter to Shared/ (Web/, reference/WebClient.md): one
// cu59::SessionController, run single-threaded (Threading::Cooperative — a
// static host can't send the headers SharedArrayBuffer needs), behind an
// embind surface for calc-engine-worker.js. Like Qt6/app/EmulatorController
// it only translates: files and input in, what changed() names posted back
// as plain JS objects the page draws without further rules — LED cells,
// the cue card as a draw list, printer lines with their heights, debug rows
// formatted by Shared/DebugText.
//
// Web-specific Platform: settings and the TI-58C constant memory are posted
// to the page, which keeps them in localStorage; magnetic cards live in an
// in-memory folder for the page session; traces go to Emscripten's MEMFS
// (/traces) and are handed to the page as downloads.
//
// Built by Web/build.sh into dist/wasm/ti59-core.{js,wasm}.

#include <emscripten/bind.h>
#include <emscripten/val.h>
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <deque>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <map>
#include <string>

#include "../Shared/CardFile.hpp"
#include "../Shared/DebugText.hpp"
#include "../Shared/KeyMatrix.hpp"
#include "../Shared/KeyboardLayout.hpp"
#include "../Shared/KeyboardMap.hpp"
#include "../Shared/LedGeometry.hpp"
#include "../Shared/ModuleCatalog.hpp"
#include "../Shared/ModuleImage.hpp"
#include "../Shared/PrinterFont.hpp"
#include "../Shared/RomHeatmap.hpp"
#include "../Shared/SessionController.hpp"
#include "../Shared/SettingsKeys.hpp"
#include "../Shared/SevenSegment.hpp"

using namespace emscripten;
namespace fs = std::filesystem;
namespace keys = cu59::settings;

namespace {

/// The page's storage key for the TI-58C constant memory (ti58c.mem in the apps).
constexpr const char* kConstantMemoryKey = "ti58c.mem";
constexpr const char* kCardScheme = "session:";
const fs::path kTraceDir = "/traces";

std::string hexColor(uint32_t rgb) {
    char buf[8];
    std::snprintf(buf, sizeof buf, "#%06x", rgb & 0xFFFFFFu);
    return buf;
}

template <typename T, typename F>
val array(const std::vector<T>& items, F&& convert) {
    val out = val::array();
    for (size_t i = 0; i < items.size(); ++i) out.set(i, convert(items[i]));
    return out;
}

val rectJS(double x, double y, double w, double h) {
    val r = val::array();
    r.set(0, x);
    r.set(1, y);
    r.set(2, w);
    r.set(3, h);
    return r;
}

std::optional<std::string> stored(val settings, const char* key) {
    val v = settings[key];
    if (!v.isString()) return std::nullopt;
    return v.as<std::string>();
}

std::optional<int> storedInt(val settings, const char* key) {
    auto s = stored(settings, key);
    if (!s) return std::nullopt;
    try { return std::stoi(*s); } catch (...) { return std::nullopt; }
}

/// "TI-59" / "TI-58" / "TI-58C" (or a raw value) to a model.
std::optional<cu59::Model> modelNamed(const std::string& name) {
    for (int raw = 0; raw <= 2; ++raw) {
        auto m = static_cast<cu59::Model>(raw);
        if (name == cu59::info(m).displayName || name == std::to_string(raw)) return m;
    }
    return std::nullopt;
}

const char* textAlign(cu59::TextAlign a) { return cu59::toString(a); }

class WebController : public cu59::SessionController::Platform {
public:
    /// `files`: {fileName: text} of the files startupPlan() named, fetched
    /// ahead; any other ROM (a module chosen later, another model) is read
    /// when needed through the worker's readRomFile(name) → text or null.
    /// `settings`: the page's stored values by SettingsKeys name.
    WebController(val files, val settings, int model, std::string moduleID) {
        val names = val::global("Object").call<val>("keys", files);
        const int n = names["length"].as<int>();
        for (int i = 0; i < n; ++i) {
            std::string name = names[i].as<std::string>();
            m_files[name] = files[name].as<std::string>();
        }
        m_constantMemory = stored(settings, kConstantMemoryKey);
        m_traceMaxMB = keys::resolveTraceMaxMB(storedInt(settings, keys::kTraceMaxFileSizeMB));
        m_startupModel = storedInt(settings, keys::kStartupModel).value_or(keys::kStartupLastUsed);
        std::error_code ec;
        fs::create_directories(kTraceDir, ec);

        m_c = std::make_unique<cu59::SessionController>(
            *this, [this](const std::string& name) { return readFile(name); }, m_files["cuecards.txt"], moduleID,
            cu59::Threading::Cooperative);
        // A stand-alone calculator until the user connects the PC-100C (a
        // preset's PRINTER: line still applies).
        m_c->setPrinterConnected(false);
        m_c->startMachine(static_cast<cu59::Model>(model));
        postSettings();
        drain();
    }

    /// The 60 Hz frame: emulation, key input, display, debugger.
    void tick() {
        m_c->tick(std::chrono::steady_clock::now());
        drain();
    }

    // ── Machine ──────────────────────────────────────────────────────────────
    void startMachine(int model) {
        if (cu59::settings::isModelRaw(model) && static_cast<cu59::Model>(model) != m_c->model())
            m_c->startMachine(static_cast<cu59::Model>(model));
        drain();
    }
    void resetMachine() { m_c->resetMachine(); drain(); }
    void cleanResetMachine() { m_c->cleanResetMachine(); drain(); }
    void changeModule(std::string id) { m_c->changeModule(id); drain(); }
    void suspend() { m_c->suspend(); drain(); }
    void resume() { m_c->resumeAfterSuspend(); drain(); }

    // ── Settings the page can't resolve itself ───────────────────────────────
    void setStartupModel(int raw) {
        m_startupModel = raw;
        store(keys::kStartupModel, std::to_string(raw));
        postSettings();
    }
    void setTraceMaxMB(int mb) {
        m_traceMaxMB = keys::resolveTraceMaxMB(mb);
        store(keys::kTraceMaxFileSizeMB, std::to_string(m_traceMaxMB));
        postSettings();
    }

    // ── Pointer (canvas-normalized, as Qt6/app/KeyboardWidget::pointer) ──────
    // Keys go through the keyboard path, so a click shorter than the ROM's
    // debounce still holds the key the minimum time.
    void pointerDown(double nx, double ny) { pointer(nx, ny); drain(); }
    void pointerMove(double nx, double ny) { pointer(nx, ny); drain(); }
    void pointerUp() {
        if (m_displayPressed) {
            m_displayPressed = false;
            m_c->setFullSpeed(false);
        }
        if (m_pointerKey >= 0) {
            m_c->keyboardUp();
            m_pointerKey = -1;
        }
        drain();
    }
    /// A key by grid position (the page's accessible key buttons).
    void keyButtonDown(int row, int col) { m_c->keyboardDown({cu59::matrixCode(row, col)}); drain(); }
    void keyButtonUp() { m_c->keyboardUp(); drain(); }

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
    void blur() {
        m_c->keyboardRelease();
        m_pointerKey = -1;
        if (m_displayPressed) {
            m_displayPressed = false;
            m_c->setFullSpeed(false);
        }
        drain();
    }

    // ── Files ────────────────────────────────────────────────────────────────
    /// A preset's bytes; returns the errors it reported.
    val loadState(val bytes) {
        m_errors = val::array();
        m_c->loadStateFile(vecFromJSArray<uint8_t>(bytes));
        drain();
        val errors = m_errors;
        m_errors = val::undefined();
        return errors;
    }

    // ── Card reader: an in-memory card folder for the page session ───────────
    val listCards() const {
        val out = val::array();
        int n = 0;
        for (const auto& [name, text] : m_cards)
            if (cu59::isCardFileName(name)) out.set(n++, name);
        return out;
    }
    /// A session card by name, or an uploaded one (bytes given: kept in the folder).
    void insertCard(std::string name, val bytes) {
        if (!bytes.isUndefined() && !bytes.isNull()) {
            auto raw = vecFromJSArray<uint8_t>(bytes);
            m_cards[name] = std::string(raw.begin(), raw.end());
        }
        auto it = m_cards.find(name);
        std::optional<std::vector<uint8_t>> raw;
        if (it != m_cards.end()) raw = std::vector<uint8_t>(it->second.begin(), it->second.end());
        m_c->insertCard(raw, kCardScheme + name, name);
        drain();
    }
    void insertBlankCard(std::string name) {
        name = cu59::withDefaultCardExtension(name);
        m_c->insertBlankCard(kCardScheme + name, name);
        drain();
    }
    void ejectCard() { m_c->ejectCard(); drain(); }
    /// A session card's bytes, for download (null when absent).
    val cardBytes(std::string name) const {
        auto it = m_cards.find(name);
        if (it == m_cards.end()) return val::null();
        return bytesJS(it->second);
    }

    // ── Printer ──────────────────────────────────────────────────────────────
    void setPrinterConnected(bool on) {
        m_c->setPrinterConnected(on);
        m_c->resetMachine();
        drain();
    }
    void togglePrinterTrace() { m_c->togglePrinterTrace(); drain(); }
    void pressPrinterPrint(bool pressed) { m_c->pressPrinterPrint(pressed); drain(); }
    void pressPrinterAdv(bool pressed) { m_c->pressPrinterAdv(pressed); drain(); }
    void cutPaper() { m_c->cutPaper(); drain(); }

    // ── Debugger ─────────────────────────────────────────────────────────────
    void setLiveDebugEnabled(bool on) { m_c->setLiveDebugEnabled(on); m_liveOn = on; postLive(); drain(); }
    void setCpuDebugEnabled(bool on) { m_c->setCpuDebugEnabled(on); m_cpuOn = on; postCpu(); postHeatmap(); drain(); }
    void freeze(bool cpu) { m_c->freeze(cpu ? cu59::FreezeOwner::Cpu : cu59::FreezeOwner::Calculator); drain(); }
    void resumeFrozen() { m_c->resume(); drain(); }
    void armPcChange() { m_c->armPcChange(); drain(); }
    void armScanLoopExit() { m_c->armScanLoopExit(); drain(); }
    void disarmPcChange() { m_c->disarmPcChange(); drain(); }
    void disarmScanLoopExit() { m_c->disarmScanLoopExit(); drain(); }
    void stepKeycode() { m_c->stepKeycode(); drain(); }
    void stepInstruction() { m_c->stepInstruction(); drain(); }
    void clearHeatmap() { m_c->clearHeatmap(); postHeatmap(); drain(); }
    void cycleDebugLevel() { m_c->cycleDebugLevel(); postLog(); drain(); }
    void clearLog() { m_c->clearLog(); drain(); }
    void dumpVars() { m_c->dumpVars(); drain(); }
    void dumpScom() { m_c->dumpScom(); drain(); }
    void dumpProg() { m_c->dumpProg(); drain(); }
    void dumpMemory() { m_c->dumpMemory(); drain(); }
    void setManualTrace(bool on) { m_c->setManualTrace(on); drain(); }
    void loadAsm(std::string text, std::string fileName) { m_c->loadAsm(text, fileName); drain(); }
    void runAsm() { m_c->runAsm(); drain(); }
    void clearAsm() { m_c->clearAsm(); drain(); }

    /// The trace files in MEMFS: [{name, size}].
    val listTraces() const {
        val out = val::array();
        int n = 0;
        std::error_code ec;
        for (const auto& e : fs::directory_iterator(kTraceDir, ec)) {
            if (!e.is_regular_file()) continue;
            val o = val::object();
            o.set("name", e.path().filename().string());
            o.set("size", static_cast<double>(e.file_size()));
            out.set(n++, o);
        }
        return out;
    }
    val traceBytes(std::string name) const {
        std::ifstream in(kTraceDir / fs::path(name).filename(), std::ios::binary);
        if (!in) return val::null();
        std::string data((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
        return bytesJS(data);
    }

    // ── Sizes the page draws at ──────────────────────────────────────────────
    /// The cue card's draw list is laid out for this size (CSS px).
    void setCueCardSize(double w, double h) {
        m_cardW = w;
        m_cardH = h;
        post("cueCard", "card", cueCard());
    }
    /// The debug panels' base font size for their width.
    void setDebugWidth(double w) {
        post("debugFont", "size", val(cu59::debugPanelFontSize(w)));
    }

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

    static val bytesJS(const std::string& data) {
        static const val Uint8Array = val::global("Uint8Array");
        val view(typed_memory_view(data.size(), reinterpret_cast<const uint8_t*>(data.data())));
        return Uint8Array.new_(view);  // a copy: the view dies with `data`
    }

    void pointer(double nx, double ny) {
        // Holding the display runs the emulator at full speed.
        if (cu59::kDisplayRect.contains(nx, ny)) {
            if (!m_displayPressed) {
                m_displayPressed = true;
                m_c->setFullSpeed(true);
                if (m_pointerKey >= 0) {
                    m_c->keyboardUp();
                    m_pointerKey = -1;
                }
            }
            return;
        }
        if (m_displayPressed) {
            m_displayPressed = false;
            m_c->setFullSpeed(false);
        }
        double kbNy = (ny - cu59::kKeyboardYStart) / cu59::kKeyboardYScale;
        const double margin = 0.025;  // room for the vertical hit expansion
        if (kbNy < -margin || kbNy > 1 + margin) {
            if (m_pointerKey >= 0) {
                m_c->keyboardUp();
                m_pointerKey = -1;
            }
            return;
        }
        cu59::KeyHit hit{};
        if (!cu59::keyAt(nx, kbNy, hit)) return;
        int id = hit.row * 5 + hit.col;
        if (id == m_pointerKey) return;
        if (m_pointerKey >= 0) m_c->keyboardUp();  // one key at a time
        m_pointerKey = id;
        m_c->keyboardDown({cu59::matrixCode(hit.row, hit.col)});
    }

    // ── Platform ──────────────────────────────────────────────────────────────
    void runOnUiThread(std::function<void()> job) override { m_queue.push_back(std::move(job)); }
    std::optional<std::string> readConstantMemory() override { return m_constantMemory; }
    void writeConstantMemory(const std::string& text) override {
        m_constantMemory = text;
        store(kConstantMemoryKey, text);
    }
    bool writeCard(const std::string& path, const std::string& text) override {
        std::string name = path.rfind(kCardScheme, 0) == 0 ? path.substr(std::strlen(kCardScheme)) : path;
        m_cards[name] = text;
        m_cardsChanged = true;
        return true;
    }
    cu59::SessionController::TraceLocation traceLocation() override {
        return {kTraceDir, static_cast<uint64_t>(m_traceMaxMB) * 1'000'000};
    }
    void saveLastUsedModel(cu59::Model m) override { store(keys::kLastUsedModel, std::to_string(static_cast<int>(m))); }
    void saveModuleID(const std::string& id) override { store(keys::kSolidStateModuleID, id); }
    void error(const std::string& title, const std::string& message) override {
        if (!m_errors.isUndefined()) m_errors.call<void>("push", message);
        else post("error", "message", val(title + ": " + message));
    }
    void diagnostic(const std::string& message) override { val::global("console").call<void>("debug", message); }
    void changed(uint32_t c) override { m_changes |= c; }

    void store(const char* key, const std::string& value) {
        val msg = val::object();
        msg.set("type", val("store"));
        msg.set("key", val(key));
        msg.set("value", val(value));
        val::global("postMessage")(msg);
    }

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
        if (c & S::ModelChanged) post("model", "model", model());
        if (c & (S::DisplayChanged | S::ModelChanged)) post("display", "cells", display());
        if (c & (S::CueCardChanged | S::ModelChanged)) post("cueCard", "card", cueCard());
        if (c & (S::RunStateChanged | S::ModelChanged | S::AsmChanged)) post("runState", "state", runState());
        if (c & (S::PrinterChanged | S::PaperCut | S::ModelChanged)) postPrinter((c & S::PaperCut) != 0);
        if ((c & (S::CardChanged | S::ModelChanged)) || m_cardsChanged) {
            m_cardsChanged = false;
            post("card", "card", card());
        }
        if (c & (S::LiveChanged | S::ListingChanged | S::RunStateChanged)) postLive();
        if (c & (S::CpuChanged | S::RunStateChanged)) postCpu();
        if (c & S::HeatmapChanged) postHeatmap();
        if (c & (S::LogChanged | S::TraceChanged)) postLog();
        if (c & S::AsmChanged) post("asm", "asm", asmState());
        if (c & S::TraceChanged) {
            // A manual trace that just ended is offered as a download.
            if (m_traceWasOn && !m_c->manualTrace()) post("traceReady", "name", val(manualTraceName()));
            m_traceWasOn = m_c->manualTrace();
        }
        if (c & (S::TraceChanged | S::RunStateChanged | S::ModelChanged)) post("traces", "traces", listTraces());
    }

    std::string manualTraceName() const {
        switch (m_c->model()) {
        case cu59::Model::TI58: return "CALCU58_TRACE.bin";
        case cu59::Model::TI58C: return "CALCU58C_TRACE.bin";
        default: return "CALCU59_TRACE.bin";
        }
    }

    static void post(const char* type, const char* field, val payload) {
        static const val postMessage = val::global("postMessage");
        val msg = val::object();
        msg.set("type", val(type));
        msg.set(field, payload);
        postMessage(msg);
    }

    void postSettings() {
        val o = val::object();
        o.set("startupModel", m_startupModel);
        o.set("traceMaxMB", m_traceMaxMB);
        post("settings", "settings", o);
    }

    val model() const {
        const auto& i = cu59::info(m_c->model());
        val o = val::object();
        o.set("model", static_cast<int>(m_c->model()));
        o.set("name", std::string(i.displayName));
        o.set("hasCardReader", i.hasCardReader);
        o.set("moduleID", m_c->moduleID());
        return o;
    }

    // Per cell (0 = rightmost) its segment mask, brightness and decimal point
    // (0–1), flat: [segments, level, dp] × 12. Cell 11 shows the "C" indicator
    // while it is lit.
    val display() const {
        const cu59::LedFrame& d = m_c->display();
        const double calc = m_c->calcIndicatorOpacity();
        float cells[36];
        for (int i = 0; i < 12; ++i) {
            const cu59::LedCell cell = cu59::ledCell(i, d.digits[i], d.ctrl[i], d.digitLevel[i], calc);
            cells[i * 3] = cell.segments;
            cells[i * 3 + 1] = static_cast<float>(cell.opacity);
            cells[i * 3 + 2] = d.dpLevel[i] / 255.0f;
        }
        static const val Float32Array = val::global("Float32Array");
        return Float32Array.new_(typed_memory_view(36, cells));
    }

    val runState() const {
        const cu59::DebugState d = m_c->debugState();
        val o = val::object();
        o.set("frozen", d.frozen);
        o.set("owner", !d.owner ? val::null() : val(*d.owner == cu59::FreezeOwner::Cpu ? "cpu" : "calculator"));
        o.set("pcArmed", d.pcChangeArmed);
        o.set("scanArmed", d.scanLoopExitArmed);
        o.set("fullSpeed", m_c->fullSpeed());
        o.set("playing", m_c->keystrokesPlaying());
        o.set("heldKey", m_c->heldKey());
        o.set("asmActive", m_c->asmActive());
        return o;
    }

    val card() const {
        val o = val::object();
        o.set("swiping", m_c->cardState() == cu59::SessionController::CardState::Swiping);
        o.set("fileName", m_c->cardFileName());
        o.set("cards", listCards());
        return o;
    }

    val asmState() const {
        val o = val::object();
        o.set("fileName", m_c->asmFileName());
        o.set("words", m_c->asmWordCount());
        o.set("status", m_c->asmStatus());
        o.set("active", m_c->asmActive());
        return o;
    }

    // ── Cue card: a draw list for m_cardW × m_cardH (CueCardRenderer in Qt) ──
    val cueCard() const {
        const auto& card = m_c->cueCard();
        if (!card || m_cardW <= 0) return val::null();
        const double w = m_cardW, h = m_cardH;
        const cu59::CueCardLayout& L = cu59::cueCardLayout(card->template_);
        const cu59::CueCardGeometry g = cu59::cueCardGeometry(*card, w, h);
        const std::string ink = hexColor(cu59::cueCardInk(*card));
        const bool boxed = card->style == cu59::CardButtonStyle::Button;

        val items = val::array();
        int n = 0;
        auto text = [&](const std::string& s, double size, const char* align, double cx, double cy, double width,
                        bool box = false) {
            if (s.empty()) return;
            val t = val::object();
            t.set("kind", val("text"));
            t.set("text", s);
            t.set("size", size);
            t.set("align", val(align));
            t.set("cx", cx);
            t.set("cy", cy);
            t.set("width", width);
            t.set("color", ink);
            if (box) t.set("box", rectJS(g.buttonPadX, g.buttonPadY, 0, 0));
            items.set(n++, t);
        };
        auto badge = [&](int bank, const cu59::CueCardFrame& f) {
            val b = val::object();
            b.set("kind", val("badge"));
            b.set("text", std::to_string(bank));
            b.set("size", g.bankFontSize);
            b.set("frame", rectJS(f.cx - f.width / 2, f.cy - f.height / 2, f.width, f.height));
            items.set(n++, b);
        };
        auto rect = [&](double x, double y, double rw, double rh, const std::string& color, double alpha) {
            val r = val::object();
            r.set("kind", val("rect"));
            r.set("rect", rectJS(x, y, rw, rh));
            r.set("color", color);
            r.set("alpha", alpha);
            items.set(n++, r);
        };

        if (L.hasId) {
            text(card->title, g.titleFontSize, "left", g.gridCenter, g.titleY, g.gridWidth);
            text(card->id, g.titleFontSize, "right", g.gridCenter, g.titleY, g.gridWidth);
        } else {
            text(card->title, g.titleFontSize, "center", w / 2, g.titleY, g.titleWidth);
        }
        if (card->template_ == cu59::CueCardTemplate::MagnetCard) {
            if (card->bankLeft) badge(*card->bankLeft, g.bankLeft);
            if (card->bankRight) badge(*card->bankRight, g.bankRight);
        }
        auto gridRow = [&](int row, double y) {
            auto spans = cu59::labelSpans(*card, row);
            if (spans.empty()) return;
            double fs = cu59::cellFittingFontSize(spans, L, w, g.gridFontSize);
            if (L.drawsDividers)
                for (int i : cu59::dividersBetween(spans))
                    rect(cu59::cueCardDividerX(L, i, w) - 0.5, y - g.dividerHeight / 2, 1, g.dividerHeight,
                         hexColor(cu59::kCueCardDividerColor), 1);
            for (const auto& s : spans) {
                cu59::CueCardFrame f = cu59::cueCardSpanFrame(L, s, y, w);
                text(s.label, fs, "center", f.cx, f.cy, f.width);
            }
        };
        // Top row: Row1 text, or the A′–E′ grid.
        if (!card->row1.empty())
            text(card->row1, g.gridFontSize, textAlign(card->row1Align), g.gridCenter, g.gridY0, g.gridWidth, boxed);
        else gridRow(0, g.gridY0);
        // Bottom row: Row2 / Row2R text, or the A–E grid.
        if (!card->row2.empty() || !card->row2R.empty()) {
            if (card->row2R.empty()) {
                text(card->row2, g.gridFontSize, textAlign(card->row2Align), g.gridCenter, g.gridY1, g.gridWidth, boxed);
            } else {
                text(card->row2, g.gridFontSize, textAlign(card->row2Align), g.row2Left.cx, g.row2Left.cy,
                     g.row2Left.width, boxed);
                text(card->row2R, g.gridFontSize, textAlign(card->row2RAlign), g.row2Right.cx, g.row2Right.cy,
                     g.row2Right.width, boxed);
            }
        } else {
            gridRow(1, g.gridY1);
        }
        rect(0, 0, w, g.washHeight, hexColor(cu59::kCueCardWashColor), cu59::kCueCardWashAlpha);

        val o = val::object();
        o.set("template", std::string(cu59::toString(card->template_)));
        o.set("width", w);
        o.set("height", h);
        o.set("items", items);
        // Plain text of the card, for assistive technology and tests.
        std::string label = card->title;
        for (const auto& l : card->labels)
            if (!l.empty() && l != cu59::kCueCardInvisibleMarker) label += " " + l;
        for (const auto* s : {&card->row1, &card->row2, &card->row2R})
            if (!s->empty()) label += " " + *s;
        o.set("label", label);
        return o;
    }

    // ── Printer: the lines from the first one that changed ───────────────────
    void postPrinter(bool cut) {
        const auto& lines = m_c->printerLines();
        const auto& codes = m_c->printerCodeLines();
        if (cut || lines.size() < m_sentLines) m_sentLines = m_sentCodes = 0;
        size_t from = std::min(m_sentLines, m_sentCodes);
        val out = val::array();
        for (size_t i = from; i < lines.size(); ++i) {
            const PrinterCodeLine* line = i < codes.size() ? &codes[i] : nullptr;
            const bool feed = lines[i].empty();
            val l = val::object();
            l.set("text", lines[i]);
            l.set("height", cu59::PrinterGeometry::lineHeightUnits(feed, line ? line->rowCount : 7));
            if (line && !feed) {
                l.set("rows", cu59::PrinterGeometry::clampRowCount(line->rowCount));
                val cs = val::array();
                for (size_t ch = 0; ch < 20; ++ch) cs.set(ch, line->codes[ch] & 0x3F);
                l.set("codes", cs);
            }
            out.set(i - from, l);
        }
        m_sentLines = lines.size();
        m_sentCodes = std::min(codes.size(), lines.size());
        const double units = m_c->printerStripHeightUnits();
        val o = val::object();
        o.set("from", static_cast<int>(from));
        o.set("lines", out);
        o.set("connected", m_c->printerConnected());
        o.set("trace", m_c->printerTrace());
        o.set("heightUnits", units);
        o.set("copyPixelsPerUnit", cu59::PrinterGeometry::copyPixelsPerUnit(units));
        post("printer", "printer", o);
    }

    // ── Debugger rows, formatted as Qt6/app/debug/*Widget do ─────────────────
    void postLive() {
        if (!m_liveOn) return;
        const cu59::LiveDebugSnapshot& s = m_c->debug().live();
        char buf[64];
        val o = val::object();
        std::snprintf(buf, sizeof buf, "FA:%04X", s.fA);
        o.set("fA", std::string(buf));
        std::snprintf(buf, sizeof buf, "FB:%04X", s.fB);
        o.set("fB", std::string(buf));
        o.set("hir0", "HIR0:" + s.statusRegister);
        o.set("partition", cu59::partitionLine(s.programRegCount, s.dataRegCount));
        o.set("source", cu59::programSourceLabel(s.programSource, s.prSourceFlag));

        // Program steps: the full listing when frozen, else ±5 around the current step.
        const bool frozen = m_c->isFrozen() && !m_c->debug().listing().empty();
        const auto& entries = frozen ? m_c->debug().listing() : s.programWindow;
        val steps = val::array();
        for (size_t i = 0; i < entries.size(); ++i) {
            const auto& e = entries[i];
            std::snprintf(buf, sizeof buf, "%03d  %02d  ", e.stepNum, e.keycode);
            std::string t = buf + e.mnemonic;
            if (e.isCurrent) t += "  " + cu59::currentStepMarker(frozen);
            val r = val::object();
            r.set("text", t);
            r.set("current", e.isCurrent);
            steps.set(i, r);
        }
        o.set("steps", steps);
        o.set("stepHighlight", hexColor(cu59::stepHighlightColor(frozen ? m_c->debug().listingSource() : s.programSource)));
        o.set("fix", "FIX:" + s.fixIndicator);
        o.set("angle", cu59::angleModeLabel(s.angleMode));
        o.set("angleKnown", s.angleMode.has_value());
        o.set("eng", !s.engIndicator.empty());
        o.set("second", !s.secondIndicator.empty());
        o.set("inv", !s.invIndicator.empty());
        val returns = val::array();
        for (int i = 0; i < 6; ++i) {
            int a = s.returnAddresses[static_cast<size_t>(i)];
            std::snprintf(buf, sizeof buf, "L%d:%03d", i + 1, a);
            val r = val::object();
            r.set("text", std::string(buf));
            r.set("color", hexColor(cu59::returnLevelColor(s.returnAddressSourceFlags[static_cast<size_t>(i)], a == 0)));
            returns.set(i, r);
        }
        o.set("returns", returns);
        val flags = val::array();
        for (int i = 0; i < 10; ++i) flags.set(i, s.calcFlags[static_cast<size_t>(i)]);
        o.set("flags", flags);
        val hir = val::array();
        for (int i = 0; i < 8; ++i) {
            val r = val::object();
            r.set("text", cu59::hirLine(i + 1, s.hir[static_cast<size_t>(i)]));
            r.set("zero", s.hir[static_cast<size_t>(i)] == 0);
            hir.set(i, r);
        }
        o.set("hir", hir);
        o.set("x", cu59::xRegisterLine(s.xValue, s.xRaw));
        o.set("xColor", hexColor(cu59::xRegisterColor(s.xValue, s.xRaw)));
        o.set("t", cu59::tRegisterLine(s.tRegister));
        o.set("tZero", s.tRegister == 0);
        o.set("vars", array(s.nonZeroRegs, [](const auto& r) { return val(cu59::registerLine(r)); }));
        post("live", "live", o);
    }

    void postCpu() {
        if (!m_cpuOn) return;
        const auto& history = m_c->debug().cpuHistory();
        char buf[64];
        val rows = val::array();
        for (size_t i = 0; i < history.size(); ++i) {
            const auto& e = history[i];
            const CpuFrame& f = e.frame;
            std::snprintf(buf, sizeof buf, "%04X  %04X  ", e.pc, e.opcode);
            val r = val::object();
            r.set("text", buf + e.disasm);
            r.set("pc", e.pc);
            r.set("history", e.isHistory);
            r.set("current", e.isCurrent);
            val regs = val::array();
            const std::pair<const char*, const uint8_t*> named[] = {
                {"A", f.A}, {"B", f.B}, {"C", f.C}, {"D", f.D}, {"E", f.E}, {"Sout", f.Sout}};
            int k = 0;
            for (const auto& [name, nib] : named) {
                val reg = val::array();
                reg.set(0, val(name));
                reg.set(1, cu59::registerNibbles(nib));
                regs.set(k++, reg);
            }
            r.set("registers", regs);
            r.set("KR", "KR: " + cu59::hexBin16(f.KR));
            r.set("fA", "fA: " + cu59::hexBin16(f.fA));
            r.set("fB", "fB: " + cu59::hexBin16(f.fB));
            std::snprintf(buf, sizeof buf, "SR: %04X", f.SR);
            r.set("SR", std::string(buf));
            r.set("R5", "R5: " + std::to_string(f.R5));
            r.set("cond", cu59::condFlag(f.flags));
            r.set("idle", cu59::idleFlag(f.flags));
            std::snprintf(buf, sizeof buf, "DIGIT: %2d", f.postDigit);
            r.set("digit", std::string(buf));
            r.set("lit", "Lit: " + std::to_string(f.maxDigitDecay));
            r.set("displayOn", f.displayOn != 0);
            rows.set(i, r);
        }
        post("cpu", "rows", rows);
    }

    void postHeatmap() {
        if (!m_cpuOn) return;
        const auto& counts = m_c->debug().heatmapCounts();
        std::vector<uint8_t> steps(counts.size());
        for (size_t i = 0; i < counts.size(); ++i) steps[i] = cu59::heatStep(counts[i]);
        static const val Uint8Array = val::global("Uint8Array");
        post("heatmap", "steps", Uint8Array.new_(typed_memory_view(steps.size(), steps.data())));
    }

    void postLog() {
        val o = val::object();
        o.set("text", m_c->logText());
        o.set("level", static_cast<int>(m_c->debugLevel()));
        o.set("trace", m_c->manualTrace());
        post("log", "log", o);
    }

    std::map<std::string, std::string> m_files;
    std::unique_ptr<cu59::SessionController> m_c;
    std::deque<std::function<void()>> m_queue;
    uint32_t m_changes = 0;
    val m_errors = val::undefined();

    std::optional<std::string> m_constantMemory;
    int m_traceMaxMB = keys::kDefaultTraceMaxMB;
    int m_startupModel = keys::kStartupLastUsed;

    std::map<std::string, std::string> m_cards;
    bool m_cardsChanged = false;

    int m_pointerKey = -1;
    bool m_displayPressed = false;

    double m_cardW = 0, m_cardH = 0;
    size_t m_sentLines = 0, m_sentCodes = 0;
    bool m_liveOn = false, m_cpuOn = false;
    bool m_traceWasOn = false;
};

// ── Free functions ───────────────────────────────────────────────────────────

/// What to start with: the model and module from the host's overrides, else
/// the stored settings (SettingsKeys resolution), and the files to fetch
/// before WebController can start: the model's ROM and constants and the
/// module's image. {model, moduleID, files}.
val startupPlan(val settings, std::string modelOverride, std::string moduleOverride, std::string cuecards) {
    cu59::Model model = keys::resolveStartupModel(storedInt(settings, keys::kStartupModel),
                                                  storedInt(settings, keys::kLastUsedModel));
    if (auto m = modelNamed(modelOverride)) model = *m;
    std::string moduleID = keys::resolveModuleID(stored(settings, keys::kSolidStateModuleID));
    if (!moduleOverride.empty() && cu59::moduleRomFile(cuecards, moduleOverride)) moduleID = moduleOverride;
    if (!cu59::moduleRomFile(cuecards, moduleID)) moduleID = keys::kDefaultModuleID;

    val files = val::array();
    int n = 0;
    for (const char* f : cu59::info(model).romFiles) files.set(n++, std::string(f));
    for (const char* f : cu59::info(model).constFiles) files.set(n++, std::string(f));
    if (auto file = cu59::moduleRomFile(cuecards, moduleID)) files.set(n++, *file);
    val o = val::object();
    o.set("model", static_cast<int>(model));
    o.set("moduleID", moduleID);
    o.set("files", files);
    return o;
}

/// Everything fixed the page draws with: models, modules, the canvas layout
/// (KeyboardLayout, canvas-normalized), the printer's geometry and font, the
/// heatmap's grid and colours.
val staticData(std::string cuecards) {
    val o = val::object();
    val models = val::array();
    for (int raw = 0; raw <= 2; ++raw) {
        const auto& i = cu59::info(static_cast<cu59::Model>(raw));
        val m = val::object();
        m.set("model", raw);
        m.set("name", std::string(i.displayName));
        m.set("hasCardReader", i.hasCardReader);
        models.set(raw, m);
    }
    o.set("models", models);
    o.set("modules", array(cu59::allModuleMetadata(cuecards), [](const cu59::ModuleMetadata& m) {
        val v = val::object();
        v.set("id", m.id);
        v.set("menuTitle", m.menuTitle);
        return v;
    }));

    val layout = val::object();
    layout.set("aspect", cu59::kCanvasAspect);
    const auto& d = cu59::kDisplayRect;
    const auto& c = cu59::kCardRect;
    layout.set("display", rectJS(d.x, d.y, d.w, d.h));
    layout.set("card", rectJS(c.x, c.y, c.w, c.h));
    val keyRects = val::array();
    for (int row = 0; row < 9; ++row)
        for (int col = 0; col < 5; ++col) {
            const auto& k = cu59::kKeyRects[row][col];
            keyRects.set(row * 5 + col, rectJS(k.x, cu59::kKeyboardYStart + k.y * cu59::kKeyboardYScale, k.w,
                                               k.h * cu59::kKeyboardYScale));
        }
    layout.set("keys", keyRects);
    o.set("layout", layout);

    using PG = cu59::PrinterGeometry;
    val printer = val::object();
    printer.set("widthUnits", PG::widthUnits);
    printer.set("charStepUnits", PG::charStepUnits);
    printer.set("dotRadiusFraction", PG::dotRadiusFraction);
    printer.set("paddingX", PG::paperPaddingX);
    printer.set("paddingY", PG::paperPaddingY);
    printer.set("dotPitchMM", PG::dotPitchMM);
    val font = val::array();
    for (int ch = 0; ch < 64; ++ch) {
        val rows = val::array();
        for (int r = 0; r < 7; ++r) rows.set(r, cu59::kPC100CFont[ch][r]);
        font.set(ch, rows);
    }
    printer.set("font", font);
    o.set("printer", printer);

    val heat = val::object();
    heat.set("cols", cu59::kHeatmapCols);
    heat.set("rows", cu59::kHeatmapRows);
    val colors = val::array();
    for (int i = 0; i < 6; ++i) {
        char buf[8];
        std::snprintf(buf, sizeof buf, "#%02x%02x%02x", cu59::kHeatColors[i].r, cu59::kHeatColors[i].g, cu59::kHeatColors[i].b);
        colors.set(i, std::string(buf));
    }
    heat.set("colors", colors);
    o.set("heatmap", heat);
    return o;
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
        .constructor<val, val, int, std::string>()
        .function("tick", &WebController::tick)
        .function("startMachine", &WebController::startMachine)
        .function("resetMachine", &WebController::resetMachine)
        .function("cleanResetMachine", &WebController::cleanResetMachine)
        .function("changeModule", &WebController::changeModule)
        .function("suspend", &WebController::suspend)
        .function("resume", &WebController::resume)
        .function("setStartupModel", &WebController::setStartupModel)
        .function("setTraceMaxMB", &WebController::setTraceMaxMB)
        .function("pointerDown", &WebController::pointerDown)
        .function("pointerMove", &WebController::pointerMove)
        .function("pointerUp", &WebController::pointerUp)
        .function("keyButtonDown", &WebController::keyButtonDown)
        .function("keyButtonUp", &WebController::keyButtonUp)
        .function("keyDown", &WebController::keyDown)
        .function("keyUp", &WebController::keyUp)
        .function("blur", &WebController::blur)
        .function("loadState", &WebController::loadState)
        .function("listCards", &WebController::listCards)
        .function("insertCard", &WebController::insertCard)
        .function("insertBlankCard", &WebController::insertBlankCard)
        .function("ejectCard", &WebController::ejectCard)
        .function("cardBytes", &WebController::cardBytes)
        .function("setPrinterConnected", &WebController::setPrinterConnected)
        .function("togglePrinterTrace", &WebController::togglePrinterTrace)
        .function("pressPrinterPrint", &WebController::pressPrinterPrint)
        .function("pressPrinterAdv", &WebController::pressPrinterAdv)
        .function("cutPaper", &WebController::cutPaper)
        .function("setLiveDebugEnabled", &WebController::setLiveDebugEnabled)
        .function("setCpuDebugEnabled", &WebController::setCpuDebugEnabled)
        .function("freeze", &WebController::freeze)
        .function("resumeFrozen", &WebController::resumeFrozen)
        .function("armPcChange", &WebController::armPcChange)
        .function("armScanLoopExit", &WebController::armScanLoopExit)
        .function("disarmPcChange", &WebController::disarmPcChange)
        .function("disarmScanLoopExit", &WebController::disarmScanLoopExit)
        .function("stepKeycode", &WebController::stepKeycode)
        .function("stepInstruction", &WebController::stepInstruction)
        .function("clearHeatmap", &WebController::clearHeatmap)
        .function("cycleDebugLevel", &WebController::cycleDebugLevel)
        .function("clearLog", &WebController::clearLog)
        .function("dumpVars", &WebController::dumpVars)
        .function("dumpScom", &WebController::dumpScom)
        .function("dumpProg", &WebController::dumpProg)
        .function("dumpMemory", &WebController::dumpMemory)
        .function("setManualTrace", &WebController::setManualTrace)
        .function("loadAsm", &WebController::loadAsm)
        .function("runAsm", &WebController::runAsm)
        .function("clearAsm", &WebController::clearAsm)
        .function("listTraces", &WebController::listTraces)
        .function("traceBytes", &WebController::traceBytes)
        .function("setCueCardSize", &WebController::setCueCardSize)
        .function("setDebugWidth", &WebController::setDebugWidth);
    function("startupPlan", &startupPlan);
    function("staticData", &staticData);
    function("ledGeometry", &ledGeometry);
}
