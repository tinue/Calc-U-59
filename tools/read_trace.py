#!/usr/bin/env python3
"""
read_trace.py — TI-59 binary trace reader with disassembly.

Parses TI59_TRACE.bin (and variant filenames) in format documented in DebugAPI.md and either:
  • Prints a human-readable TI59E.LOG-style text trace to stdout (default)
    Includes disassembled mnemonics (e.g., "11DA 0A76 MEMWR")
  • Emits a JSON array (--json)
  • Exposes load_trace(path) for import by compare_trace.py

Version support:
  • v1 (released in v1.0.0): stable, backwards-compatible. File header has no model field.
  • v2+ (after v1.0.0): volatile, may change without backwards-compat guarantees.
    v2 adds model indicator to file header and SESSION_START record.

Usage:
    python3 read_trace.py TI59_TRACE.bin                       # output everything
    python3 read_trace.py --dedup TI59_TRACE.bin               # filter consecutive same-PC
    python3 read_trace.py --skip-repeating TI59_TRACE.bin      # dedup + collapse repeating loops
    python3 read_trace.py --clean TI59_TRACE.bin               # find reset, skip to after first scan loop
    python3 read_trace.py --clean-heavy TI59_TRACE.bin         # skip reset and first keyboard scan loop
    python3 read_trace.py --clean --dedup TI59_TRACE.bin       # clean + dedup
    python3 read_trace.py --clean-heavy --color TI59_TRACE.bin # clean-heavy + coloring
    python3 read_trace.py --clean --json TI59_TRACE.bin        # clean + JSON output
    python3 read_trace.py --dedup --color TI59_TRACE.bin       # filters + coloring
    python3 read_trace.py --json TI59_TRACE.bin

Flags:
    --json                 Output as JSON array
    --dedup                Remove consecutive records with same PC (filter duplicates)
    --skip-repeating       Apply dedup first, then collapse repeating PC sequences
    --clean                Find reset start (PC=0000) and remove incomplete final scan loop.
                           TI-59/58: 063C-0658 (10-instr). TI-58C: 063D-0A2E (25-instr).
    --clean-heavy          Skip reset (PC=0000) and the entire keyboard scan loop.
                           Skips all iterations until loop exits. Useful to start from
                           when calculator is ready for input.
                           TI-59/58: 063C-0658. TI-58C: 063D-0A2E.
                           Takes precedence over --clean.
    --color                Colorize trace entries (DISP ON: light yellow, IDLE=1: darker white,
                           both: dark yellow). Works with any filter combination.

The mnemonic disassembly uses mnemonics.tsv from the same directory.
"""

import sys
import struct
import json
from disasm import disasm

# ── Constants (must match DebugAPI.md) ────────────────────────────────────────

MAGIC      = 0x54493539   # 'TI59' in LE memory
VERSION_V1 = 1             # v1: baseline (released in v1.0.0, stable, no model field)
VERSION_V2 = 2             # v2+: volatile, may change. v2 adds model to header and SESSION_START

MODEL_NAMES = {0: 'TI-59', 1: 'TI-58', 2: 'TI-58C'}

REC_SESSION_START = 0x01
REC_TRACE_EVENT   = 0x02
REC_SESSION_END   = 0x03
REC_USER_EVENT    = 0x04

USER_KIND = {0x01: 'KEY DOWN', 0x02: 'KEY UP',
             0x03: 'CARD INSERT', 0x04: 'CARD EJECT'}

BANNER = '-' * 80

# ── Low-level reader ──────────────────────────────────────────────────────────

def _display_on_from_record(rec):
    """Get displayOn status from the trace record."""
    return rec.get('displayOn', 0)

def _read_exact(f, n):
    data = f.read(n)
    if len(data) != n:
        raise EOFError(f"Expected {n} bytes, got {len(data)}")
    return data

def _parse_file_header(f):
    """Parse and validate file header (16 bytes). Returns model indicator or None."""
    hdr = _read_exact(f, 16)
    magic, version = struct.unpack_from('<IH', hdr, 0)
    if magic != MAGIC:
        raise ValueError(f"Bad magic: 0x{magic:08X} (expected 0x{MAGIC:08X})")
    if version not in (VERSION_V1, VERSION_V2):
        raise ValueError(f"Unsupported version: {version} (expected {VERSION_V1} or {VERSION_V2})")

    # v1: no model field (reserved space). v2: model at offset 6–7
    model = None
    if version >= VERSION_V2:
        model_code, = struct.unpack_from('<H', hdr, 6)
        model = MODEL_NAMES.get(model_code, f'Unknown({model_code})')

    return version, model

def _parse_trace_event(payload):
    """Parse a TRACE_EVENT payload into a dict.

    Supports both legacy v1 payloads (124 bytes) and extended payloads (126 bytes)
    that include displayOn/maxDigitDecay.
    """
    if len(payload) not in (124, 125):
        raise ValueError(f"TRACE_EVENT payload length {len(payload)}, expected 124 or 125")

    if len(payload) == 125:
        # Fixed fields (38 bytes)
        # Unpacks: suppressed(4) + seqno(4) + pc(2) + opcode(2) + fA(2) + fB(2) + KR(2) + SR(2) +
        #          EXT(2) + PREG(2) + flags(2) + m_libAddr(2) + R5(1) + digit(1) + RAM_ADDR(1) +
        #          RAM_OP(1) + REG_ADDR(1) + m_libAddrReadPos(1) + cycle_weight(1) +
        #          displayOn(1) + maxDigitDecay(1) = 37 bytes
        (suppressed, seqno, pc, opcode, fA, fB, KR, SR,
         EXT, PREG, cpu_flags, m_libAddr, R5, digit,
         RAM_ADDR, RAM_OP, REG_ADDR, m_libAddrReadPos, cycle_weight,
         displayOn, maxDigitDecay) = struct.unpack_from(
            '<IIHHHHHHHHHH BBBBBBBBB', payload, 0)
        off = 37
    else:
        # Legacy fixed fields (36 bytes)
        (suppressed, seqno, pc, opcode, fA, fB, KR, SR,
         EXT, PREG, cpu_flags, m_libAddr, R5, digit,
         RAM_ADDR, RAM_OP, REG_ADDR, m_libAddrReadPos, cycle_weight, _dispFilter) = struct.unpack_from(
            '<IIHHHHHHHHHH BBBBBBBB', payload, 0)
        # Legacy: derive displayOn from _dispFilter
        displayOn = 0 if _dispFilter >= 3 else 1
        maxDigitDecay = _dispFilter
        off = 36

    # A–E registers: 16 unpacked nibbles each (index 0 = LSN)
    regs = {}
    for name in ('A', 'B', 'C', 'D', 'E'):
        regs[name] = list(payload[off:off+16])
        off += 16

    # Sout: 8 bytes, nibble-packed (low nibble = Sout[2i], high = Sout[2i+1])
    sout = []
    for b in payload[off:off+8]:
        sout.append(b & 0x0F)
        sout.append((b >> 4) & 0x0F)
    off += 8

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
        'displayOn':    1 if displayOn else 0,
        'maxDigitDecay': maxDigitDecay,
        'R5':           f'{R5:X}',
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

def _parse_session_start(payload, file_version):
    """Parse SESSION_START record. v1: 8 bytes (timestamp only).
    v2+: 9 bytes (timestamp + model byte)."""
    ts, = struct.unpack_from('<Q', payload, 0)
    rec = {'type': 'session_start', 'timestamp': ts, 'model': None}

    if file_version >= VERSION_V2 and len(payload) >= 9:
        model_code = payload[8]
        rec['model'] = MODEL_NAMES.get(model_code, f'Unknown({model_code})')

    return rec

def _parse_session_end(payload):
    count, suppressed = struct.unpack_from('<II', payload, 0)
    return {'type': 'session_end', 'eventCount': count, 'suppressedTotal': suppressed}

# ── Public API ────────────────────────────────────────────────────────────────

def load_trace(path):
    """
    Parse TI59_TRACE.bin (or variant) and return a list of record dicts.

    Record types:
      'session_start'  — session boundary with optional model field
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
            file_version, file_model = _parse_file_header(f)
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
                records.append(_parse_session_start(payload, file_version))
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
    disp_status = "ON" if _display_on_from_record(rec) else "OFF"
    decay = rec.get('maxDigitDecay', 0)
    line4 = (f"FB={rec['fB']} [{_bin16(int(rec['fB'],16))}] "
             f"SR={rec['SR']} R5={rec['R5']} ROM={rom_str} PREG={rec['PREG']} "
             f"RAMOP={ramop_str} RAMREG={rec['RAM_ADDR']:03d} "
             f"ROMREG={rec['REG_ADDR']:02d}")

    line5 = f"DISPLAY={disp_status} DECAY={decay}"

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

    disp_status = "ON" if _display_on_from_record(rec) else "OFF"
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

def _find_reset_start(records):
    """Find the index of the first trace record with PC='0000'.
    Returns the index, or 0 if not found."""
    for i, rec in enumerate(records):
        if rec['type'] == 'trace' and rec['pc'] == '0000':
            return i
    return 0

def _find_scan_loop_completion(records, model):
    """Find the index where the keyboard scan loop finally exits.

    For TI-59/58: loop is 063C-0658
    For TI-58C: loop is 063D-0A2E

    Returns the index of the first instruction after the loop, which is
    the first PC outside the loop range after the loop has started.

    If no exit is found (trace ends inside loop), returns 0.
    """
    loop_start, loop_end = _get_scan_loop_range(model)
    if not loop_start:
        return 0

    found_loop_start = False

    for i, rec in enumerate(records):
        if rec['type'] != 'trace':
            continue

        pc = rec['pc']

        # Mark when we see the loop start
        if pc == loop_start:
            found_loop_start = True

        # Once loop has started, look for first PC outside the range
        if found_loop_start and not (loop_start <= pc <= loop_end):
            return i

    # No exit found (loop ends at EOF or never exits)
    return 0

def _get_scan_loop_range(model):
    """Get the scan loop range (start, end, jump_instr) for the given model.

    Returns (start_pc, end_pc) tuple:
    - TI-59/58: ('063C', '0658') - 10-instruction loop
    - TI-58C: ('063D', '0A2E') - 25-instruction loop
    - Other/None: (None, None)
    """
    if model in ('TI-59', 'TI-58'):
        return ('063C', '0658')
    elif model == 'TI-58C':
        return ('063D', '0A2E')
    return (None, None)

def _remove_incomplete_scan_loop(records, model):
    """Remove the last incomplete keyboard scan loop.

    For TI-59/58: 063C-0658 loop
    For TI-58C: 063D-0A2E loop

    If the trace is interrupted mid-loop, we remove this incomplete final cycle.
    """
    loop_start, loop_end = _get_scan_loop_range(model)
    if not loop_start:
        return records

    # Find last trace record
    last_trace_idx = -1
    for i in range(len(records) - 1, -1, -1):
        if records[i]['type'] == 'trace':
            last_trace_idx = i
            break

    if last_trace_idx == -1:
        return records

    last_pc = records[last_trace_idx]['pc']

    # Check if last trace is within the scan loop range
    if last_pc < loop_start or last_pc > loop_end:
        # No scan loop at end
        return records

    # Find where this loop started (look back for start)
    loop_start_idx = last_trace_idx
    for i in range(last_trace_idx, -1, -1):
        if records[i]['type'] == 'trace':
            pc = records[i]['pc']
            if pc == loop_start:
                loop_start_idx = i
                break
            elif pc < loop_start or pc > loop_end:
                # Reached before the scan loop
                loop_start_idx = i + 1
                break

    # If last trace is not at the end of the loop, it's incomplete
    if last_pc != loop_end:
        return records[:loop_start_idx]

    return records

def _apply_clean(records):
    """Apply --clean filter: find reset start and remove incomplete scan loop.

    Supports TI-59, TI-58, and TI-58C with their respective loop ranges.
    """
    # Get model
    model = None
    for rec in records:
        if rec['type'] == 'session_start' and rec.get('model'):
            model = rec['model']
            break

    # If no model, try to infer from presence of loop PCs (fallback to TI-59)
    if not model:
        model = 'TI-59'

    # Find reset start and trim leading records
    reset_idx = _find_reset_start(records)
    records = records[reset_idx:]

    # Remove incomplete scan loop at end
    records = _remove_incomplete_scan_loop(records, model)

    return records

def _apply_clean_heavy(records):
    """Apply --clean-heavy filter: skip reset and entire keyboard scan loop.

    Finds PC=0000 (reset), then skips all iterations of the scan loop
    until it exits. Starts output from the first instruction after the loop completes.

    Supports TI-59, TI-58 (loop 063C-0658), and TI-58C (loop 063D-0A2E).
    """
    # Get model
    model = None
    for rec in records:
        if rec['type'] == 'session_start' and rec.get('model'):
            model = rec['model']
            break

    # If no model, try to infer (fallback to TI-59)
    if not model:
        model = 'TI-59'

    loop_start, loop_end = _get_scan_loop_range(model)
    if not loop_start:
        return records

    # Find where the scan loop finally exits (without first finding reset)
    # This handles multi-session traces where reset appears multiple times
    loop_exit_idx = _find_scan_loop_completion(records, model)
    if loop_exit_idx > 0:
        records = records[loop_exit_idx:]

    # Remove incomplete scan loop at end
    records = _remove_incomplete_scan_loop(records, model)

    return records

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
            model_str = f"  model={rec['model']}" if rec.get('model') else ""
            out.append(f"\n; SESSION START  {ts.isoformat()}{model_str}\n")
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
    clean_heavy = '--clean-heavy' in args
    clean = '--clean' in args and not clean_heavy
    paths = [a for a in args if not a.startswith('--')]
    if not paths:
        print(__doc__)
        sys.exit(1)

    for path in paths:
        records = load_trace(path)
        if clean_heavy:
            records = _apply_clean_heavy(records)
        elif clean:
            records = _apply_clean(records)
        if as_json:
            print(json.dumps(records, indent=2))
        else:
            print(format_as_log(records, dedup=dedup, skip_repeating=skip_repeating, color=color))

if __name__ == '__main__':
    main()
