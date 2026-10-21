#pragma once
#include "../Core/TraceTypes.hpp"
#include "MachineModelInfo.hpp"
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <mutex>
#include <string>

// Binary CPU trace file writer (format v2, documented in reference/DebugAPI.md;
// tools/read_trace.py reads it). Each open() starts a fresh file and session:
// 16-byte file header, then records of [type u8][length u16 LE][payload].
// Where the file goes is the frontend's choice — the Swift app resolves its
// trace directory (iCloud, local or a custom folder), the Qt app a local one.
// Thread-safe: frames (emulation side) and key/card events (UI side) may
// arrive from different threads.

namespace cu59 {

class TraceWriter {
public:
    explicit TraceWriter(Model model) : m_model(model) {}
    ~TraceWriter() { close(); }
    TraceWriter(const TraceWriter&) = delete;
    TraceWriter& operator=(const TraceWriter&) = delete;

    /// Model-derived default file name: CALCU59_TRACE.bin, CALCU58_TRACE.bin, CALCU58C_TRACE.bin.
    static std::string baseFileName(Model model);

    /// Delete any existing file at `path`, create it, write the file header and
    /// a SESSION_START record. Stops the session once it reaches `maxBytes`.
    /// No-op returning true if already open.
    bool open(const std::filesystem::path& path, uint64_t maxBytes);

    /// Write SESSION_END and close. No-op if not open.
    void close();

    bool isOpen() const;

    /// Write one TRACE_EVENT. Returns false if this frame reached the size
    /// limit and the session was closed (the frontend tells the user).
    bool write(const CpuFrame& frame);

    /// TRACE_GAP: `count` frames lost to ring-buffer overflow.
    void writeLostGap(uint32_t count);

    void writeKeyDown(uint8_t row, uint8_t col);
    void writeKeyUp(uint8_t row, uint8_t col);
    void writeCardInsert();
    void writeCardEject();

private:
    void closeLocked();
    void writeRecord(uint8_t type, const uint8_t* payload, uint16_t length);
    void writeUserEvent(uint8_t kind, uint8_t p1, uint8_t p2);

    const Model m_model;
    mutable std::mutex m_mutex;
    std::FILE* m_file = nullptr;
    uint32_t m_eventCount = 0;
    uint64_t m_maxBytes = 0;
    uint64_t m_bytesWritten = 0;
};

} // namespace cu59
