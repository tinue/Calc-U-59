#!/usr/bin/env python3
"""
read_trace.py — TI-59 binary trace reader.

Parses TI59_TRACE.bin (format documented in DebugAPI.md) and either:
  • Prints a human-readable TI59E.LOG-style text trace to stdout (default)
  • Emits a JSON array (--json)
  • Exposes load_trace(path) for import by compare_trace.py

Usage:
    python3 read_trace.py TI59_TRACE.bin
    python3 read_trace.py --json TI59_TRACE.bin
"""

import sys
import struct
import json

# ── Constants (must match DebugAPI.md) ────────────────────────────────────────

MAGIC   = 0x54493539   # 'TI59' in LE memory
VERSION = 1

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
        raise ValueError(f"Unsupported version: {version}")

def _parse_trace_event(payload):
    """Parse a 120-byte TRACE_EVENT payload into a dict."""
    if len(payload) != 120:
        raise ValueError(f"TRACE_EVENT payload length {len(payload)}, expected 120")

    # Fixed fields (32 bytes)
    (suppressed, seqno, pc, opcode, fA, fB, KR, SR,
     EXT, PREG, cpu_flags, R5, digit,
     RAM_ADDR, RAM_OP, REG_ADDR, cycle_weight) = struct.unpack_from(
        '<IIHHHHHHHHH BBBBBB', payload, 0)

    # A–E registers: 16 unpacked nibbles each (index 0 = LSN)
    regs = {}
    off = 32
    for name in ('A', 'B', 'C', 'D', 'E'):
        regs[name] = list(payload[off:off+16])
        off += 16

    # Sout: 8 bytes, nibble-packed (low nibble = Sout[2i], high = Sout[2i+1])
    sout = []
    for b in payload[112:120]:
        sout.append(b & 0x0F)
        sout.append((b >> 4) & 0x0F)

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
        'EXT':          f'{EXT & 0xFF:02X}',
        'PREG':         f'{PREG:X}',
        'cpuFlags':     cpu_flags,
        'COND':         str(cond),
        'IDLE':         str(idle),
        'R5':           f'{R5:X}',
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
    """
    records = []
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
                records.append(_parse_trace_event(payload))
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

def _user_banner(rec):
    label = rec['label']
    if rec['kind'] in (0x01, 0x02):
        label += f"  row={rec['row']}  col={rec['col']}"
    return f"\n{BANNER}\n{label}\n{BANNER}\n"

def format_as_log(records):
    """
    Render records as TI59E.LOG-style text (4 lines + blank per instruction).
    USER_EVENT records are rendered as a prominent banner.
    SESSION_START/END are rendered as a brief comment line.
    """
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
        elif t == 'trace':
            r = rec
            sup = r['suppressedBefore']

            # Last-of-run: don't expand — just show a compact skip marker.
            if sup > 0:
                out.append(f"... {sup} ...")
                continue

            # RAMOP: show RAM_OP hex when flags bit 6 set, else '-'
            ramop_str = (f"{r['RAM_OP']:X}" if (r['cpuFlags'] & 0x0040) else '-')

            line1 = f"{r['pc']} {r['opcode']}"
            line2 = (f"A={r['A']} B={r['B']} C={r['C']} "
                     f"D={r['D']} E={r['E']}")
            line3 = (f"FA={r['fA']} [{_bin16(int(r['fA'],16))}] "
                     f"KR={r['KR']} [{_bin16(int(r['KR'],16))}] "
                     f"EXT={r['EXT']} COND={r['COND']} IDLE={r['IDLE']} "
                     f"IO={r['IO']}")
            line4 = (f"FB={r['fB']} [{_bin16(int(r['fB'],16))}] "
                     f"SR={r['SR']} R5={r['R5']} PREG={r['PREG']} "
                     f"RAMOP={ramop_str} RAMREG={r['RAM_ADDR']:03d} "
                     f"ROMREG={r['REG_ADDR']:02d}")
            out.append(line1 + '\n' + line2 + '\n' + line3 + '\n' + line4 + '\n')
    return '\n'.join(out)

# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    args = sys.argv[1:]
    as_json = '--json' in args
    paths = [a for a in args if not a.startswith('--')]
    if not paths:
        print(__doc__)
        sys.exit(1)

    for path in paths:
        records = load_trace(path)
        if as_json:
            print(json.dumps(records, indent=2))
        else:
            print(format_as_log(records))

if __name__ == '__main__':
    main()
