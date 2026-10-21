// Shared/TraceWriter: records from a real machine run, checked structurally
// here and by tools/read_trace.py (the CalcU59TraceReader CTest).

#include "TestHarness.hpp"
#include "TestRoms.hpp"
#include "../Shared/TraceWriter.hpp"

using namespace cu59;

namespace {
uint16_t le16(const std::string& s, size_t i) {
    return static_cast<uint16_t>(static_cast<uint8_t>(s[i]) | (static_cast<uint8_t>(s[i + 1]) << 8));
}
uint32_t le32(const std::string& s, size_t i) { return le16(s, i) | (static_cast<uint32_t>(le16(s, i + 2)) << 16); }
} // namespace

/// Writes build/trace-test.bin (read again by the read_trace.py CTest).
TEST(trace_writer_records) {
    auto m = testroms::makeMachine(Model::TI58C);
    m->setTraceFlags(TRACE_PC | TRACE_REGS_LIGHT | TRACE_REGS_FULL);
    const std::string path = "build/trace-test.bin";
    TraceWriter w(Model::TI58C);
    CHECK(w.open(path, 50'000'000));
    CHECK(w.isOpen());
    w.writeKeyDown(8, 3);
    std::vector<CpuFrame> frames(1024);
    uint32_t total = 0;
    for (int i = 0; i < 5; ++i) {
        m->stepN(500, false);
        uint32_t lost = 0;
        uint32_t n = m->drainCpuFrames(frames.data(), 1024, &lost);
        if (lost) w.writeLostGap(lost);
        for (uint32_t k = 0; k < n; ++k) CHECK(w.write(frames[k]));
        total += n;
    }
    w.writeKeyUp(8, 3);
    w.writeCardInsert();
    w.close();
    CHECK(!w.isOpen());
    CHECK(total > 0);

    auto text = testroms::readFile(path);
    CHECK(text.has_value());
    if (!text) return;
    const std::string& s = *text;
    CHECK_EQ(le32(s, 0), 0x54493539u);  // 'TI59'
    CHECK_EQ(le16(s, 4), 2);           // version
    CHECK_EQ(le16(s, 6), 2);           // model TI-58C
    size_t pos = 16;
    std::vector<uint8_t> types;
    uint32_t events = 0;
    while (pos + 3 <= s.size()) {
        auto type = static_cast<uint8_t>(s[pos]);
        uint16_t len = le16(s, pos + 1);
        types.push_back(type);
        if (type == 0x02) {
            CHECK_EQ(len, 125);
            ++events;
        }
        if (type == 0x03) CHECK_EQ(le32(s, pos + 3), events);  // SESSION_END event count
        pos += 3u + len;
    }
    CHECK_EQ(pos, s.size());
    CHECK_EQ(types.front(), 0x01);  // SESSION_START
    CHECK_EQ(types[1], 0x04);       // key down
    CHECK_EQ(types.back(), 0x03);   // SESSION_END
    CHECK_EQ(events, total);
}

TEST(trace_writer_size_limit) {
    auto m = testroms::makeMachine(Model::TI59);
    m->setTraceFlags(TRACE_PC | TRACE_REGS_LIGHT | TRACE_REGS_FULL);
    TraceWriter w(Model::TI59);
    CHECK(w.open("build/trace-limit.bin", 1000));
    m->stepN(200, false);
    std::vector<CpuFrame> frames(200);
    uint32_t lost = 0;
    uint32_t n = m->drainCpuFrames(frames.data(), 200, &lost);
    int written = 0;
    bool stopped = false;
    for (uint32_t k = 0; k < n && !stopped; ++k) {
        stopped = !w.write(frames[k]);
        ++written;
    }
    CHECK(stopped);
    CHECK(!w.isOpen());
    CHECK_EQ(written, 8);  // 16 + 12 header bytes, then 128 per frame: the 8th crosses 1000
    CHECK_EQ(TraceWriter::baseFileName(Model::TI58), std::string("CALCU58_TRACE.bin"));
}
