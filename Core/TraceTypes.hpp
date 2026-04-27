#pragma once
#include <cstdint>

// ── Trace feature flags ───────────────────────────────────────────────────────
//
// Independently gated cost tiers for the instruction trace / debug API.
// Set via TMC0501::setTraceFlags() or TI59Machine::setTraceFlags().

enum : uint32_t {
    TRACE_NONE         = 0x0000,
    TRACE_PC           = 0x0001,  ///< (pc, opcode, digit, cycleWeight, seqno) only; ~10 bytes/event
    TRACE_REGS_LIGHT   = 0x0002,  ///< adds KR, SR, fA, fB, R5, cpuFlags; medium cost
    TRACE_REGS_FULL    = 0x0004,  ///< adds A–E, SCOM, Sout; ~370 bytes/event; debug sessions only
    TRACE_BREAKPOINTS  = 0x0008,  ///< binary-search breakpoint check on each step; stop-the-world
};


// ── Unified CPU frame ─────────────────────────────────────────────────────────
//
// Combines TraceEvent and CPUSnapshot into a single struct.
// Reduces ring buffers from 2 to 1 and eliminates parallel-array mismatch risk.
// ~397 bytes per frame; 1024-deep ring = ~406 KB.

struct CpuFrame {
    // Identity (always captured)
    uint32_t seqno;
    uint16_t pc;
    uint16_t opcode;
    uint8_t  digit;
    uint8_t  cycleWeight;

    // Light registers (captured when TRACE_REGS_LIGHT is set)
    uint16_t KR, SR, fA, fB, cpuFlags;
    uint8_t  R5;
    uint8_t  dpPos_captured; ///< Buffered R5 from m_display (decimal-point position served to Swift)

    // Full snapshot (captured when TRACE_REGS_FULL is set)
    uint8_t  A[16], B[16], C[16], D[16], E[16];
    uint8_t  SCOM[16][16];
    uint8_t  Sout[16];
    uint16_t EXT, PREG, flags, m_libAddr;
    uint8_t  REG_ADDR, RAM_ADDR, RAM_OP, m_libAddrReadPos;
    uint8_t  dispFilter; ///< Display blanking filter counter (0–3; ≥3 = display blanked during compute)
};

// ── Debug event ───────────────────────────────────────────────────────────────
//
// Emitted by the CPU core for observability; drained by the UI at 60 Hz.
// level: 1 = INFO, 2 = DEBUG.

struct DebugEvent {
    uint8_t level;    ///< 1=INFO, 2=DEBUG
    char    msg[80];  ///< Null-terminated message
};
