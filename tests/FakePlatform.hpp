#pragma once
#include "../Shared/SessionController.hpp"
#include <deque>
#include <filesystem>
#include <functional>
#include <map>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

// The SessionController::Platform the controller tests drive: threaded tests
// pump its queue on a timer, cooperative ones after every tick.

namespace testroms {

/// A frontend without a UI: the UI-thread queue is pumped by the test.
struct FakePlatform : cu59::SessionController::Platform {
    std::mutex mutex;
    std::deque<std::function<void()>> queue;
    std::optional<std::string> mem;
    int memWrites = 0;
    std::vector<std::string> errors;
    std::map<std::string, std::string> cards;
    uint32_t changes = 0;

    void runOnUiThread(std::function<void()> job) override {
        std::lock_guard<std::mutex> lock(mutex);
        queue.push_back(std::move(job));
    }
    std::optional<std::string> readConstantMemory() override { return mem; }
    void writeConstantMemory(const std::string& text) override { mem = text; ++memWrites; }
    bool writeCard(const std::string& path, const std::string& text) override { cards[path] = text; return true; }
    std::vector<cu59::DebugPanel> panels;  ///< DebugPanel: requests
    void showDebugPanel(cu59::DebugPanel panel) override { panels.push_back(panel); }
    /// The card folder is `cards`, keyed by "cards/<file name>".
    CardFileRef cardFile(const std::string& fileName) override {
        std::string path = "cards/" + fileName;
        auto it = cards.find(path);
        if (it == cards.end()) return {std::nullopt, path};
        return {std::vector<uint8_t>(it->second.begin(), it->second.end()), path};
    }
    cu59::SessionController::TraceLocation traceLocation() override { return {std::filesystem::temp_directory_path(), 1'000'000}; }
    void saveLastUsedModel(cu59::Model) override {}
    void saveModuleID(const std::string&) override {}
    void error(const std::string& title, const std::string& message) override { errors.push_back(title + ": " + message); }
    void diagnostic(const std::string&) override {}
    void changed(uint32_t c) override { changes |= c; }

    void pump() {
        for (;;) {
            std::function<void()> job;
            {
                std::lock_guard<std::mutex> lock(mutex);
                if (queue.empty()) return;
                job = std::move(queue.front());
                queue.pop_front();
            }
            job();
        }
    }
};

} // namespace testroms
