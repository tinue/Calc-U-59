#!/usr/bin/env python3
"""
read_trace.py — TI-59 binary trace reader with disassembly.

Parses TI59_TRACE.bin (format documented in DebugAPI.md) and either:
  • Prints a human-readable TI59E.LOG-style text trace to stdout (default)
    Includes disassembled mnemonics (e.g., "11DA 0A76 MEMWR")
  • Emits a JSON array (--json)
  • Exposes load_trace(path) for import by compare_trace.py

Usage:
    python3 read_trace.py TI59_TRACE.bin                       # output everything
    python3 read_trace.py --dedup TI59_TRACE.bin               # filter consecutive same-PC
    python3 read_trace.py --skip-repeating TI59_TRACE.bin      # dedup + collapse repeating loops
    python3 read_trace.py --dedup --color TI59_TRACE.bin       # filters + coloring
    python3 read_trace.py --json TI59_TRACE.bin

Flags:
    --json                 Output as JSON array
    --dedup                Remove consecutive records with same PC (filter duplicates)
    --skip-repeating       Apply dedup first, then collapse repeating PC sequences
    --color                Colorize trace entries (DISP ON: light yellow, IDLE=1: darker white,
                           both: dark yellow). Works with any filter combination.

The mnemonic disassembly uses mnemonics.tsv from the same directory.
"""

import sys
import struct
import json
from disasm import disasm

# ── Constants (must match DebugAPI.md) ────────────────────────────────────────

MAGIC   = 0x54493539   # 'TI59' in LE memory
VERSION = 1            # Baseline version for initial release; do not increment until v1.0.0 ships

REC_SESSION_START = 0x01
REC_TRACE_EVENT   = 0x02
REC_SESSION_END   = 0x03
REC_USER_EVENT    = 0x04

USER_KIND = {0x01: 'KEY DOWN', 0x02: 'KEY UP',
             0x03: 'CARD INSERT', 0x04: 'CARD EJECT'}

BANNER = '-' * 80

# ── Low-level reader ──────────────────────────────────────────────────────────

def _read_exact(f, n):
    data = f.read(n)
    if len(data) != n:
        raise EOFError(f"Expected {n} bytes, got {len(data)}")
    return data

def _parse_file_header(f):
    hdr = _read_exact(f, 16)
    magic, version = struct.unpack_from('<IH', hdr, 0)
    if magic != MAGIC:
        raise ValueError(f"Bad magic: 0x{magic:08X} (expected 0x{MAGIC:08X})")
    if version != VERSION:
        raise ValueError(f"Unsupported version: {version} (expected {VERSION})")

def _parse_trace_event(payload):
    """Parse a 162-byte TRACE_EVENT payload into a dict (includes display snapshot and rendered string)."""
    if len(payload) != 162:
        raise ValueError(f"TRACE_EVENT payload length {len(payload)}, expected 162")

    # Fixed fields (36 bytes)
    # Unpacks: suppressed(4) + seqno(4) + pc(2) + opcode(2) + fA(2) + fB(2) + KR(2) + SR(2) +
    #          EXT(2) + PREG(2) + flags(2) + m_libAddr(2) + R5(1) + digit(1) + RAM_ADDR(1) +
    #          RAM_OP(1) + REG_ADDR(1) + m_libAddrReadPos(1) + cycle_weight(1) + dispFilter(1) = 36 bytes
    (suppressed, seqno, pc, opcode, fA, fB, KR, SR,
     EXT, PREG, cpu_flags, m_libAddr, R5, digit,
     RAM_ADDR, RAM_OP, REG_ADDR, m_libAddrReadPos, cycle_weight, dispFilter) = struct.unpack_from(
        '<IIHHHHHHHHHH BBBBBBBB', payload, 0)

    dpPos_captured = R5  # For compatibility, but actual buffered position comes from display snapshot

    # A–E registers: 16 unpacked nibbles each (index 0 = LSN)
    # Fixed fields total 36 bytes (2 I's + 10 H's + 8 B's)
    regs = {}
    off = 36
    for name in ('A', 'B', 'C', 'D', 'E'):
        regs[name] = list(payload[off:off+16])
        off += 16

    # Sout: 8 bytes, nibble-packed (low nibble = Sout[2i], high = Sout[2i+1])
    sout = []
    for b in payload[off:off+8]:
        sout.append(b & 0x0F)
        sout.append((b >> 4) & 0x0F)
    off += 8

    # Display snapshot: 12 bytes (displayDigits) + 12 bytes (displayCtrl) + 1 byte (displayDpPos) = 25 bytes
    # Display starts at byte 124 (36 fixed + 80 A-E + 8 Sout)
    display_digits = list(payload[off:off+12])  # displayDigits[12] at offset 124-135
    off += 12
    display_ctrl = list(payload[off:off+12])    # displayCtrl[12] at offset 136-147
    off += 12
    display_dpPos = payload[off]                 # displayDpPos at offset 148
    off += 1

    # Swift-rendered display string: 13 bytes (what user actually sees on screen)
    display_rendered_bytes = payload[off:off+13]  # displayRendered[13] at offset 149-161
    # Convert to string, stopping at null terminator if present
    display_rendered = display_rendered_bytes.rstrip(b'\x00').decode('ascii', errors='replace')
    off += 13

    cond = 1 if (cpu_flags & 0x0800) else 0
    idle = 1 if (cpu_flags & 0x0001) else 0

    # Human-readable register strings: MSN-first (index 15 down to 0)
    def reg_str(nibbles):
        return ''.join(f'{n:X}' for n in reversed(nibbles))

    return {
        'type':         'trace',
        'suppressedBefore': suppressed,
        'seqno':        seqno,
        'pc':           f'{pc:04X}',
        'opcode':       f'{opcode:04X}',
        'fA':           f'{fA:04X}',
        'fB':           f'{fB:04X}',
        'KR':           f'{KR:04X}',
        'SR':           f'{SR:04X}',
        'EXT':          f'{(EXT >> 4) & 0xFF:02X}',
        'PREG':         f'{PREG:X}',
        'cpuFlags':     cpu_flags,
        'COND':         str(cond),
        'IDLE':         str(idle),
        'dispFilter':   dispFilter,
        'R5':           f'{R5:X}',
        'dpPos_captured': f'{dpPos_captured:X}',  # Live R5 value at instruction capture
        'ROM':          f'{m_libAddr:04d}.{m_libAddrReadPos}',
        'digit':        digit,
        'RAM_ADDR':     RAM_ADDR,
        'RAM_OP':       RAM_OP,
        'REG_ADDR':     REG_ADDR,
        'cycleWeight':  cycle_weight,
        # register strings (MSN-first, for compare_trace.py compatibility)
        'A':            reg_str(regs['A']),
        'B':            reg_str(regs['B']),
        'C':            reg_str(regs['C']),
        'D':            reg_str(regs['D']),
        'E':            reg_str(regs['E']),
        'IO':           reg_str(sout),
        # raw nibble lists (index 0 = LSN) for any tool that wants them
        '_A': regs['A'], '_B': regs['B'], '_C': regs['C'],
        '_D': regs['D'], '_E': regs['E'], '_Sout': sout,
        # display snapshot fields (buffered display state that Swift renders)
        '_displayDigits': display_digits,      # A[2..13] buffered values (what display shows)
        '_displayCtrl': display_ctrl,          # B[2..13] buffered control nibbles
        '_displayDpPos': display_dpPos,        # Buffered decimal point position (what Swift shows)
        '_displayRendered': display_rendered,  # Swift-rendered display string (actual screen content)
    }

def _parse_user_event(payload):
    if len(payload) < 4:
        raise ValueError("USER_EVENT payload too short")
    kind, p1, p2, _ = struct.unpack_from('BBBB', payload, 0)
    label = USER_KIND.get(kind, f'USER_EVENT_0x{kind:02X}')
    e = {'type': 'user', 'kind': kind, 'label': label}
    if kind in (0x01, 0x02):
        e['row'] = p1
        e['col'] = p2
    return e

def _parse_session_start(payload):
    ts, = struct.unpack_from('<Q', payload, 0)
    return {'type': 'session_start', 'timestamp': ts}

def _parse_session_end(payload):
    count, suppressed = struct.unpack_from('<II', payload, 0)
    return {'type': 'session_end', 'eventCount': count, 'suppressedTotal': suppressed}

# ── Public API ────────────────────────────────────────────────────────────────

def load_trace(path):
    """
    Parse TI59_TRACE.bin and return a list of record dicts.

    Record types:
      'session_start'  — session boundary
      'session_end'    — session boundary with counts
      'trace'          — CPU instruction snapshot
      'user'           — user interaction (key, card)

    For compare_trace.py the 'trace' records include 'pc', 'opcode', 'A'–'E',
    'KR', 'FA', 'FB', 'COND', 'IDLE', 'IO', 'SR', 'R5', 'PREG', 'EXT',
    'RAM_ADDR', 'RAM_OP', 'REG_ADDR' — same field names as the text parser.

    Note: RAMOP and RAMREG are not directly available from the binary format
    (RAM_OP is the raw op code, not the text flag). The compare pipeline uses
    COND/IDLE/KR/FA/registers as the primary match keys; RAMOP is advisory only.

    Each 'trace' record is tagged with _trace_index (1-indexed) for numbering.
    """
    records = []
    trace_index = 0
    with open(path, 'rb') as f:
        try:
            _parse_file_header(f)
        except (ValueError, EOFError) as exc:
            raise ValueError(f"Cannot read {path}: {exc}") from exc

        while True:
            hdr = f.read(3)
            if len(hdr) == 0:
                break
            if len(hdr) < 3:
                break   # truncated file — stop gracefully
            rec_type = hdr[0]
            payload_len = struct.unpack_from('<H', hdr, 1)[0]
            payload = f.read(payload_len)

            if rec_type == REC_SESSION_START:
                records.append(_parse_session_start(payload))
            elif rec_type == REC_TRACE_EVENT:
                trace_index += 1
                rec = _parse_trace_event(payload)
                rec['_trace_index'] = trace_index
                records.append(rec)
            elif rec_type == REC_SESSION_END:
                records.append(_parse_session_end(payload))
            elif rec_type == REC_USER_EVENT:
                records.append(_parse_user_event(payload))
            # Unknown types: skip (forward-compatible per spec)

    return records

def trace_events_only(records):
    """Filter to just 'trace' records (drops session/user markers)."""
    return [r for r in records if r['type'] == 'trace']

# ── Human-readable formatter ──────────────────────────────────────────────────

def _bin16(v):
    return ''.join(str((v >> (15 - i)) & 1) for i in range(16))

def _format_display_content(rec):
    """Format display content from both raw buffered snapshot AND Swift-rendered string.

    Returns: "digits=[...] ctrl=[...] dpPos=N | Swift shows: '...'"

    The raw values show what the CPU buffered at capture time.
    The Swift-rendered string shows what the user actually saw on their screen.
    """
    # Get raw buffered snapshot
    display_digits = rec.get('_displayDigits', [0] * 12)
    display_ctrl = rec.get('_displayCtrl', [0] * 12)
    display_dpPos = rec.get('_displayDpPos', 0)
    display_rendered = rec.get('_displayRendered', '')

    # Format raw values mechanically (no interpretation)
    digits_str = '[' + ','.join(f'{d:X}' for d in display_digits) + ']'
    ctrl_str = '[' + ','.join(f'{c:X}' for c in display_ctrl) + ']'

    # Build output: raw values + Swift-rendered string
    result = f"raw: digits={digits_str} ctrl={ctrl_str} dpPos={display_dpPos}"

    # Add what Swift actually displayed
    if display_rendered:
        result += f" | Swift showed: '{display_rendered}'"

    return result

def _format_trace_record(rec, trace_number=None):
    """Format a single trace record as 5 lines of output.

    If trace_number is provided, prepend it (8-digit right-aligned) to the DISP line.
    """
    ramop_str = (f"{rec['RAM_OP']:X}" if (rec['cpuFlags'] & 0x0040) else '-')
    addr = int(rec['pc'], 16)
    opcode = int(rec['opcode'], 16)
    mnemonic = disasm(addr, opcode)
    line1 = f"{rec['pc']} {rec['opcode']} {mnemonic}"
    line2 = (f"A={rec['A']} B={rec['B']} C={rec['C']} "
             f"D={rec['D']} E={rec['E']}")
    line3 = (f"FA={rec['fA']} [{_bin16(int(rec['fA'],16))}] "
             f"KR={rec['KR']} [{_bin16(int(rec['KR'],16))}] "
             f"EXT={rec['EXT']} COND={rec['COND']} IDLE={rec['IDLE']} "
             f"IO={rec['IO']}")
    rom_str = rec.get('ROM', '0000')
    # Display status based on blanking filter: OFF if blanked (>= 3), else ON
    disp_status = "OFF" if rec['dispFilter'] >= 3 else "ON"
    line4 = (f"FB={rec['fB']} [{_bin16(int(rec['fB'],16))}] "
             f"SR={rec['SR']} R5={rec['R5']} ROM={rom_str} PREG={rec['PREG']} "
             f"RAMOP={ramop_str} RAMREG={rec['RAM_ADDR']:03d} "
             f"ROMREG={rec['REG_ADDR']:02d}")

    # Display content: show the actual rendered display using buffered display snapshot
    display_content = _format_display_content(rec)
    line5 = f"DISP: {rec['dispFilter']} ({disp_status}) | {display_content}"

    if trace_number is not None:
        trace_num_str = f"{trace_number:>8d}"
        line5 = f"{trace_num_str} {line5}"

    return '\n'.join([line1, line2, line3, line4, line5]) + '\n'

def _user_banner(rec):
    label = rec['label']
    if rec['kind'] in (0x01, 0x02):
        label += f"  row={rec['row']}  col={rec['col']}"
    return f"\n{BANNER}\n{label}\n{BANNER}\n"

def _apply_color(formatted, rec, color):
    """Apply ANSI color codes to formatted trace output if color=True.

    Color rules (four states):
      - IDLE=1 / DISP=ON:  light yellow (\033[93m) — display mode (genuinely active)
      - IDLE=1 / DISP=OFF: red (\033[91m) — anomaly (should not happen)
      - IDLE=0 / DISP=ON:  dark olive (\033[38;5;100m) — afterglow fade (display fading)
      - IDLE=0 / DISP=OFF: white (\033[0m) — normal RUN mode (no color)
    """
    if not color:
        return formatted

    disp_status = "OFF" if rec['dispFilter'] >= 3 else "ON"
    idle = rec['IDLE'] == '1'

    if idle and disp_status == "ON":
        # IDLE=1 / DISP=ON: light yellow (display genuinely active)
        return f"\033[93m{formatted}\033[0m"
    elif idle and disp_status == "OFF":
        # IDLE=1 / DISP=OFF: red (anomaly — should not happen)
        return f"\033[91m{formatted}\033[0m"
    elif not idle and disp_status == "ON":
        # IDLE=0 / DISP=ON: dark olive (display fading)
        return f"\033[38;5;100m{formatted}\033[0m"
    else:
        # IDLE=0 / DISP=OFF: white (normal RUN mode)
        return formatted

def _apply_dedup(records):
    """Filter to keep only records where PC changes.

    Removes consecutive trace records with the same PC.
    Non-trace records are always kept.
    """
    deduped = []
    last_pc = None
    for rec in records:
        if rec['type'] != 'trace':
            deduped.append(rec)
        elif rec['pc'] != last_pc:
            deduped.append(rec)
            last_pc = rec['pc']
    return deduped

def _skip_repeating(records):
    """Collapse repeating PC sequences (loops).

    Should be called after dedup. A "true" loop is one where:
    1. We see a sequence of PCs
    2. The last instruction is a jump/branch BACK to the first PC
    3. This sequence repeats (same PCs in same order)

    Jump opcodes detected by checking mnemonic (JC, JNC, JSB, RTN, WAIT, etc).
    """
    out = []
    i = 0
    while i < len(records):
        rec = records[i]

        # Non-trace records pass through
        if rec['type'] != 'trace':
            out.append(rec)
            i += 1
            continue

        loop_start_pc = rec['pc']
        cycle_end = None

        # Find next occurrence of the same PC (loop back point)
        for j in range(i + 1, min(i + 100, len(records))):
            if records[j]['type'] == 'trace' and records[j]['pc'] == loop_start_pc:
                cycle_end = j
                break

        # No loop found, output normally
        if not cycle_end:
            out.append(rec)
            i += 1
            continue

        cycle_len = cycle_end - i

        # Verify this is a real loop: last instruction must be a jump/branch
        # Get mnemonic of last instruction in cycle
        last_rec = records[cycle_end - 1]
        if last_rec.get('type') != 'trace':
            # Not a trace record, can't analyze; skip loop collapsing
            out.append(rec)
            i += 1
            continue
        last_mnem = disasm(int(last_rec['pc'], 16), int(last_rec['opcode'], 16))

        # Extract target from jump mnemonic if present
        is_backward_jump = False
        if last_mnem.startswith(('JC ', 'JNC ', 'JSB ', 'RTN')):
            # These are control flow instructions that could loop back
            is_backward_jump = True

        if not is_backward_jump:
            # Not a backward jump, so not a real loop
            out.append(rec)
            i += 1
            continue

        # Check if this cycle repeats by comparing PC sequences
        repeats = False
        if cycle_end + cycle_len <= len(records):
            repeats = True
            for k in range(cycle_len):
                if (records[i + k]['type'] != 'trace' or
                    records[cycle_end + k]['type'] != 'trace' or
                    records[i + k]['pc'] != records[cycle_end + k]['pc']):
                    repeats = False
                    break

        if repeats:
            # Count total repetitions
            num_reps = 1
            j = cycle_end + cycle_len
            while j + cycle_len <= len(records):
                match = True
                for k in range(cycle_len):
                    if (records[j + k]['type'] != 'trace' or
                        records[i + k]['type'] != 'trace' or
                        records[j + k]['pc'] != records[i + k]['pc']):
                        match = False
                        break
                if match:
                    num_reps += 1
                    j += cycle_len
                else:
                    break

            # Output one full cycle
            for idx in range(i, cycle_end):
                out.append(records[idx])

            # Add marker comment
            out.append({
                'type': 'comment',
                'text': f'; [REPEATING: {cycle_len}-instruction cycle, {num_reps} total repetitions]\n'
            })

            i = cycle_end + cycle_len * num_reps
        else:
            out.append(rec)
            i += 1

    return out

def format_as_log(records, dedup=False, skip_repeating=False, color=False):
    """
    Render records as TI59E.LOG-style text.

    USER_EVENT records are rendered as a prominent banner.
    SESSION_START/END are rendered as a brief comment line.
    TRACE records are formatted as 5-line blocks with register/state info.

    If dedup=True, filter to keep only records where PC changes
    (removes consecutive trace records with the same PC).

    If skip_repeating=True, first apply dedup, then collapse repeating
    PC sequences (loops). Shows one cycle, marks repetition count.

    If color=True, colorize trace entries based on DISP and IDLE state.

    Trace numbers reflect the original binary position, so collapsed loops
    show the true gap in the output.
    """
    # Apply filters if requested
    if skip_repeating:
        records = _apply_dedup(records)
        records = _skip_repeating(records)
    elif dedup:
        records = _apply_dedup(records)

    # Format output
    out = []

    for rec in records:
        t = rec['type']

        if t == 'session_start':
            import datetime
            ts = datetime.datetime.fromtimestamp(rec['timestamp'])
            out.append(f"\n; SESSION START  {ts.isoformat()}\n")
        elif t == 'session_end':
            out.append(f"; SESSION END  events={rec['eventCount']}  "
                       f"suppressed={rec['suppressedTotal']}\n")
        elif t == 'user':
            out.append(_user_banner(rec))
        elif t == 'comment':
            out.append(rec['text'])
        elif t == 'trace':
            trace_num = rec.get('_trace_index')
            formatted = _format_trace_record(rec, trace_number=trace_num)
            formatted = _apply_color(formatted, rec, color)
            out.append(formatted)

    return '\n'.join(out)

# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    args = sys.argv[1:]
    as_json = '--json' in args
    dedup = '--dedup' in args
    skip_repeating = '--skip-repeating' in args
    color = '--color' in args
    paths = [a for a in args if not a.startswith('--')]
    if not paths:
        print(__doc__)
        sys.exit(1)

    for path in paths:
        records = load_trace(path)
        if as_json:
            print(json.dumps(records, indent=2))
        else:
            print(format_as_log(records, dedup=dedup, skip_repeating=skip_repeating, color=color))

if __name__ == '__main__':
    main()
