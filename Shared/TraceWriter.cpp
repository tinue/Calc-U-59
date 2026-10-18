#include "TraceWriter.hpp"
#include <chrono>
#include <system_error>
#include <vector>

namespace cu59 {

namespace {

enum : uint8_t {
    kSessionStart = 0x01,
    kTraceEvent   = 0x02,
    kSessionEnd   = 0x03,
    kUserEvent    = 0x04,
    kTraceGap     = 0x05,  // payload: u32 count of lost frames
};

enum : uint8_t { kKeyDown = 0x01, kKeyUp = 0x02, kCardInsert = 0x03, kCardEject = 0x04 };

constexpr uint32_t kMagic = 0x54493539;  // 'TI59' LE
// v1 (released in v1.0.0) is stable; v2+ can evolve without backwards-compat guarantees.
constexpr uint16_t kVersion = 2;
constexpr size_t kFramePayload = 125;

struct Buf {
    std::vector<uint8_t> b;
    void u8(uint8_t v) { b.push_back(v); }
    void u16(uint16_t v) { u8(v & 0xFF); u8(v >> 8); }
    void u32(uint32_t v) { u16(v & 0xFFFF); u16(v >> 16); }
    void u64(uint64_t v) { u32(v & 0xFFFFFFFF); u32(v >> 32); }
    void bytes(const uint8_t* p, size_t n) { b.insert(b.end(), p, p + n); }
};

std::FILE* openForWriting(const std::filesystem::path& path) {
#ifdef _WIN32
    return _wfopen(path.c_str(), L"wb");
#else
    return std::fopen(path.c_str(), "wb");
#endif
}

} // namespace

std::string TraceWriter::baseFileName(Model model) {
    switch (model) {
    case Model::TI59:  return "CALCU59_TRACE.bin";
    case Model::TI58:  return "CALCU58_TRACE.bin";
    case Model::TI58C: return "CALCU58C_TRACE.bin";
    }
    return "CALCU59_TRACE.bin";
}

bool TraceWriter::open(const std::filesystem::path& path, uint64_t maxBytes) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_file) return true;
    // Fresh file: never append to a previous session.
    std::error_code ec;
    std::filesystem::remove(path, ec);
    if (ec) {
        std::fprintf(stderr, "[TraceWriter] cannot remove existing %s: %s\n", path.string().c_str(), ec.message().c_str());
        return false;
    }
    m_file = openForWriting(path);
    if (!m_file) {
        std::fprintf(stderr, "[TraceWriter] cannot create %s\n", path.string().c_str());
        return false;
    }
    m_eventCount = 0;
    m_maxBytes = maxBytes;

    Buf header;  // 16 bytes
    header.u32(kMagic);
    header.u16(kVersion);
    header.u16(static_cast<uint16_t>(m_model));  // v2: 0 = TI-59, 1 = TI-58, 2 = TI-58C
    header.u64(0);                              // reserved
    std::fwrite(header.b.data(), 1, header.b.size(), m_file);
    m_bytesWritten = header.b.size();

    Buf start;
    auto now = std::chrono::system_clock::now().time_since_epoch();
    start.u64(static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::seconds>(now).count()));
    start.u8(static_cast<uint8_t>(m_model));
    writeRecord(kSessionStart, start.b.data(), static_cast<uint16_t>(start.b.size()));
    return true;
}

void TraceWriter::close() {
    std::lock_guard<std::mutex> lock(m_mutex);
    closeLocked();
}

void TraceWriter::closeLocked() {
    if (!m_file) return;
    Buf end;
    end.u32(m_eventCount);
    end.u32(0);  // suppressed-event total: always 0 (no deduplication), kept for the format
    writeRecord(kSessionEnd, end.b.data(), static_cast<uint16_t>(end.b.size()));
    std::fclose(m_file);
    m_file = nullptr;
}

bool TraceWriter::isOpen() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_file != nullptr;
}

bool TraceWriter::write(const CpuFrame& f) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (!m_file) return true;

    // Every frame is written, no deduplication, to keep the exact execution trace.
    Buf d;
    d.b.reserve(kFramePayload);
    d.u32(0);  // suppressed count, always 0
    d.u32(f.seqno);
    d.u16(f.pc);
    d.u16(f.opcode);
    d.u16(f.fA);
    d.u16(f.fB);
    d.u16(f.KR);
    d.u16(f.SR);
    d.u16(f.EXT);
    d.u16(f.PREG);
    d.u16(f.flags);
    d.u16(f.m_libAddr);
    d.u8(f.R5);
    d.u8(f.digit);
    d.u8(f.RAM_ADDR);
    d.u8(f.RAM_OP);
    d.u8(f.REG_ADDR);
    d.u8(f.m_libAddrReadPos);
    d.u8(f.cycleWeight);
    d.u8(f.displayOn);
    d.u8(f.maxDigitDecay);
    // Registers A–E: one nibble per byte, index 0 = least significant digit.
    d.bytes(f.A, 16);
    d.bytes(f.B, 16);
    d.bytes(f.C, 16);
    d.bytes(f.D, 16);
    d.bytes(f.E, 16);
    // Sout nibble-packed: low nibble = Sout[2i], high nibble = Sout[2i+1].
    for (int i = 0; i < 8; ++i)
        d.u8(static_cast<uint8_t>((f.Sout[2 * i] & 0x0F) | ((f.Sout[2 * i + 1] & 0x0F) << 4)));
    writeRecord(kTraceEvent, d.b.data(), static_cast<uint16_t>(d.b.size()));
    ++m_eventCount;

    // Auto-stop at the size limit (protects iCloud quota / disk).
    if (m_bytesWritten >= m_maxBytes) {
        closeLocked();
        return false;
    }
    return true;
}

void TraceWriter::writeLostGap(uint32_t count) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (!m_file) return;
    Buf p;
    p.u32(count);
    writeRecord(kTraceGap, p.b.data(), 4);
}

void TraceWriter::writeKeyDown(uint8_t row, uint8_t col) { writeUserEvent(kKeyDown, row, col); }
void TraceWriter::writeKeyUp(uint8_t row, uint8_t col)   { writeUserEvent(kKeyUp, row, col); }
void TraceWriter::writeCardInsert()                      { writeUserEvent(kCardInsert, 0, 0); }
void TraceWriter::writeCardEject()                       { writeUserEvent(kCardEject, 0, 0); }

void TraceWriter::writeUserEvent(uint8_t kind, uint8_t p1, uint8_t p2) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (!m_file) return;
    const uint8_t p[4] = {kind, p1, p2, 0};  // param3 reserved
    writeRecord(kUserEvent, p, 4);
}

void TraceWriter::writeRecord(uint8_t type, const uint8_t* payload, uint16_t length) {
    const uint8_t header[3] = {type, static_cast<uint8_t>(length & 0xFF), static_cast<uint8_t>(length >> 8)};
    std::fwrite(header, 1, 3, m_file);
    std::fwrite(payload, 1, length, m_file);
    m_bytesWritten += 3u + length;
}

} // namespace cu59
