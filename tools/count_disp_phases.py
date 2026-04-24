#!/usr/bin/env python3
"""
count_disp_phases.py — Analyze DISP ON/OFF phases from binary trace file.

Reads CALCU58C_TRACE.bin and generates:
  1. Raw phase counts (one entry per state change)
  2. Human-visible pattern (filters sub-1/60s OFF phases)

Uses TI-59 clock frequency: 14,219 instructions/sec (cycles/sec).

Usage:
    python3 count_disp_phases.py ../CALCU58C_TRACE.bin
    python3 count_disp_phases.py --raw ../CALCU58C_TRACE.bin
    python3 count_disp_phases.py --visible ../CALCU58C_TRACE.bin
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from read_trace import load_trace, trace_events_only

def analyze_phases(path, show_raw=True, show_visible=True):
    """Load binary trace and analyze DISP state phases."""
    print(f"Reading {path}...", file=sys.stderr)
    records = load_trace(path)
    traces = trace_events_only(records)

    print(f"Found {len(traces)} trace records\n", file=sys.stderr)

    if not traces:
        print("No trace events found")
        return

    # Convert dispFilter to ON/OFF state (flipped: ON if >= 3)
    states = []
    cycle_weights = []
    for trace in traces:
        disp_filter = trace['dispFilter']
        state = 'OFF' if disp_filter >= 3 else 'ON'
        states.append(state)
        cycle_weights.append(trace['cycleWeight'])

    # Count phases (consecutive same-state entries) and track line numbers in text trace.
    # Text trace format: 5 lines per instruction + 1 blank = 6 lines per instruction.
    # Instruction i starts at line (i * 6 + 1) in the text output (1-indexed).
    phases = []
    phase_lines = []  # Line number where each phase starts
    if states:
        current_state = states[0]
        current_count = 1
        current_cycles = cycle_weights[0]
        phase_start_idx = 0

        for i in range(1, len(states)):
            if states[i] == current_state:
                current_count += 1
                current_cycles += cycle_weights[i]
            else:
                phases.append((current_state, current_count, current_cycles))
                line_num = phase_start_idx * 6 + 1  # 1-indexed line number in text file
                phase_lines.append(line_num)
                current_state = states[i]
                current_count = 1
                current_cycles = cycle_weights[i]
                phase_start_idx = i

        phases.append((current_state, current_count, current_cycles))
        line_num = phase_start_idx * 6 + 1
        phase_lines.append(line_num)

    # Convert cycles to milliseconds using TI-59 frequency
    ti59_freq = 14_219  # Hz (cycles/sec in active mode)
    phases_ms = [(state, cycles / ti59_freq * 1000) for state, _, cycles in phases]

    total_ms = sum(t for _, t in phases_ms)
    total_s = total_ms / 1000

    # ── Raw Phase Sequence ──
    if show_raw:
        print("=" * 80)
        print("RAW PHASE SEQUENCE (entry counts, no filtering)")
        print("=" * 80)
        phase_str = ' - '.join(f"{state}({count})@L{line}" for (state, count, _), line in zip(phases, phase_lines))
        print(f"{phase_str}\n")
        print(f"Total phases: {len(phases)}", file=sys.stderr)

    # ── Human-Visible Pattern ──
    if show_visible:
        threshold_ms = 1000 / 60  # 1/60th second

        print("=" * 80)
        print(f"HUMAN-VISIBLE PATTERN (filtering OFF < {threshold_ms:.1f}ms)")
        print("=" * 80)

        filtered = []
        filtered_lines = []
        for (state, time_ms), line in zip(phases_ms, phase_lines):
            if state == 'OFF' and time_ms < threshold_ms:
                continue
            filtered.append([state, time_ms])
            filtered_lines.append(line)

        # Merge consecutive same states
        merged = []
        merged_lines = []
        for (state, time_ms), line in zip(filtered, filtered_lines):
            if merged and merged[-1][0] == state:
                merged[-1][1] += time_ms
                # Keep the original line number of the first occurrence
            else:
                merged.append([state, time_ms])
                merged_lines.append(line)

        phase_str = ' - '.join(f"{state}({time_ms:.0f}ms)@L{line}" for (state, time_ms), line in zip(merged, merged_lines))
        print(f"{phase_str}\n")

        on_phases = [(t, line) for (s, t), line in zip(merged, merged_lines) if s == 'ON']
        off_phases = [(t, line) for (s, t), line in zip(merged, merged_lines) if s == 'OFF']

        print(f"ON phases ({len(on_phases)}):", file=sys.stderr)
        for i, (t, line) in enumerate(on_phases, 1):
            print(f"  {i}: {t:.0f}ms ({t/1000:.2f}s) @ line {line}", file=sys.stderr)

        if off_phases:
            print(f"\nOFF phases ({len(off_phases)}):", file=sys.stderr)
            for i, (t, line) in enumerate(off_phases, 1):
                print(f"  {i}: {t:.0f}ms ({t/1000:.2f}s) @ line {line}", file=sys.stderr)

    print(f"\n{'='*80}", file=sys.stderr)
    print(f"Total trace time: {total_s:.2f} seconds ({total_ms:.0f}ms)", file=sys.stderr)
    print(f"Clock frequency used: {ti59_freq:,} Hz", file=sys.stderr)

if __name__ == '__main__':
    args = sys.argv[1:]

    # Parse flags
    show_raw = True
    show_visible = True
    paths = []

    for arg in args:
        if arg == '--raw':
            show_visible = False
        elif arg == '--visible':
            show_raw = False
        elif not arg.startswith('--'):
            paths.append(arg)

    if not paths:
        print(__doc__)
        sys.exit(1)

    for path in paths:
        analyze_phases(path, show_raw=show_raw, show_visible=show_visible)
