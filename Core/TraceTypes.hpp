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

// ── Trace event ───────────────────────────────────────────────────────────────
//
// One event per executed instruction (PREG pseudo-cycles are not traced).
// Events accumulate in a 512-deep ring; seqno gaps indicate overflow.

struct TraceEvent {
    uint16_t pc;            ///< Address of the instruction
    uint16_t opcode;        ///< 13-bit opcode fetched from ROM at pc
    uint8_t  digit;         ///< Digit-counter value when the instruction executed
    uint8_t  cycleWeight;   ///< 1 (active) or 4 (idle); matches step() return value
    uint32_t seqno;         ///< Monotonically increasing; gaps = dropped events

    // Light registers — valid when TRACE_REGS_LIGHT was set at capture time
    uint16_t KR, SR, fA, fB, cpuFlags;
    uint8_t  R5;

    // Snapshot presence flag: 0x00 = snapshot in parallel snapRing slot, 0xFF = none.
    // Not used as an actual ring index; the drain uses (m_traceTail & kTraceRingMask).
    uint8_t  snapshotIndex;
};

// ── Full CPU snapshot ─────────────────────────────────────────────────────────
//
// Captured into a parallel ring when TRACE_REGS_FULL is set.
// The snapshotIndex field in the corresponding TraceEvent indexes this ring.

struct CPUSnapshot {
    uint8_t  A[16], B[16], C[16], D[16], E[16];
    uint8_t  SCOM[16][16];
    uint8_t  Sout[16];
    uint16_t KR, SR, fA, fB, EXT, PREG, flags;
    uint8_t  R5, digit, REG_ADDR, RAM_ADDR, RAM_OP;
};
