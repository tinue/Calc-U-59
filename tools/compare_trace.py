#!/usr/bin/env python3
"""
compare_trace.py — TI-59 execution trace divergence finder.

Parses two trace files, strips idle-loop repetitions and HOLD cycles, aligns
both traces at their first active instruction (IDLE=0, non-zero KR), then
walks forward until the first divergence.

Usage:
    # Both files in TI59E.LOG text format:
    python3 compare_trace.py <reference.LOG> <emulator.LOG>

    # Emulator file in binary format (TI59_TRACE.bin):
    python3 compare_trace.py --bin <reference.LOG> TI59_TRACE.bin

    # Classic example:
    python3 compare_trace.py 1overx.LOG TI59_TRACE.LOG
"""

import sys, re
import read_trace as _bin_reader

# ── ANSI colours ──────────────────────────────────────────────────────────────

RESET  = '\033[0m'
RED    = '\033[31m'
GREEN  = '\033[32m'
YELLOW = '\033[33m'
CYAN   = '\033[36m'
BOLD   = '\033[1m'
DIM    = '\033[2m'

def red(s):    return f'{RED}{s}{RESET}'
def green(s):  return f'{GREEN}{s}{RESET}'
def yellow(s): return f'{YELLOW}{s}{RESET}'
def cyan(s):   return f'{CYAN}{s}{RESET}'
def bold(s):   return f'{BOLD}{s}{RESET}'
def dim(s):    return f'{DIM}{s}{RESET}'

# ── Parser ────────────────────────────────────────────────────────────────────

LINE1 = re.compile(r'^([0-9A-Fa-f]{4})\s+([0-9A-Fa-f]{4})\s+(.*)')
LINE2 = re.compile(
    r'A=([0-9A-Fa-f]{16})\s+B=([0-9A-Fa-f]{16})\s+'
    r'C=([0-9A-Fa-f]{16})\s+D=([0-9A-Fa-f]{16})\s+E=([0-9A-Fa-f]{16})')
LINE3 = re.compile(
    r'FA=([0-9A-Fa-f]+).*?KR=([0-9A-Fa-f]+).*?EXT=([0-9A-Fa-f]+)'
    r'.*?COND=(\d).*?IDLE=(\d).*?IO=([0-9A-Fa-f]+)')
LINE4 = re.compile(
    r'FB=([0-9A-Fa-f]+).*?SR=([0-9A-Fa-f]+).*?R5=([0-9A-Fa-f]+)'
    r'.*?PREG=([0-9A-Fa-f]+).*?RAMOP=(\S+).*?RAMREG=(\d+).*?ROMREG=(\d+)')

def parse(path):
    entries = []
    with open(path) as f:
        lines = f.readlines()
    i = 0
    while i < len(lines):
        if not lines[i].strip():
            i += 1
            continue
        m1 = LINE1.match(lines[i].strip())
        if not m1 or i + 3 >= len(lines):
            i += 1
            continue
        e = dict(pc=m1.group(1).upper(), opcode=m1.group(2).upper(),
                 mnem=m1.group(3).strip())
        l2 = lines[i+1].strip() if i+1 < len(lines) else ''
        l3 = lines[i+2].strip() if i+2 < len(lines) else ''
        l4 = lines[i+3].strip() if i+3 < len(lines) else ''
        m2 = LINE2.match(l2)
        if m2:
            e.update(A=m2.group(1).upper(), B=m2.group(2).upper(),
                     C=m2.group(3).upper(), D=m2.group(4).upper(),
                     E=m2.group(5).upper())
        m3 = LINE3.search(l3)
        if m3:
            e.update(FA=m3.group(1).upper(), KR=m3.group(2).upper(),
                     EXT=m3.group(3).upper(), COND=m3.group(4), IDLE=m3.group(5),
                     IO=m3.group(6).upper())
        m4 = LINE4.search(l4)
        if m4:
            e.update(FB=m4.group(1).upper(), SR=m4.group(2).upper(),
                     R5=m4.group(3).upper(), PREG=m4.group(4).upper(),
                     RAMOP=m4.group(5), RAMREG=m4.group(6), ROMREG=m4.group(7))
        entries.append(e)
        i += 5
    return entries

# ── Filters ───────────────────────────────────────────────────────────────────

def _dedup_key(e):
    """Key for collapsing HOLD cycles and identical idle-loop iterations."""
    return (e['pc'], e.get('A',''), e.get('B',''), e.get('C',''),
            e.get('D',''), e.get('E',''), e.get('KR',''),
            e.get('FA',''), e.get('FB',''), e.get('COND',''), e.get('IDLE',''))

def strip_redundant(entries):
    """
    Remove:
    - IDLE=1 repetitions: keep one entry per unique state per idle run.
    - HOLD cycles: consecutive entries with identical state (any IDLE).
    """
    result = []
    seen_idle = set()
    prev_key  = None

    for e in entries:
        k = _dedup_key(e)
        if k == prev_key:               # HOLD cycle — identical consecutive state
            continue
        if e.get('IDLE') == '1':
            if k in seen_idle:          # idle-loop repetition
                continue
            seen_idle.add(k)
        else:
            seen_idle = set()           # entering active mode — reset idle dedup
        prev_key = k
        result.append(e)
    return result

def find_active_start(entries):
    """
    Index of the first IDLE=0 entry with non-zero KR.
    Skips any startup noise (all-zero state before the machine is initialised).
    """
    for i, e in enumerate(entries):
        if e.get('IDLE') == '0' and e.get('KR', '0000') not in ('0000', ''):
            return i
    # Fallback: first IDLE=0 of any kind
    for i, e in enumerate(entries):
        if e.get('IDLE') == '0':
            return i
    return 0

def sync_active(ref_active, mine_active, lookahead=30):
    """
    Both lists start at their respective active starts but may be offset by a
    few instructions (e.g. the binary trace captured one extra instruction before
    the reference's log began).  Scan forward in each list to find the first
    common (pc, opcode) pair and trim accordingly.  Reports the adjustment.
    """
    ref0_pc  = ref_active[0]['pc']
    ref0_op  = ref_active[0]['opcode']
    mine0_pc = mine_active[0]['pc']
    mine0_op = mine_active[0]['opcode']

    if ref0_pc == mine0_pc and ref0_op == mine0_op:
        return ref_active, mine_active, 0, 0   # already aligned

    # Search: skip N from mine to match ref[0]
    for n in range(1, lookahead):
        if n < len(mine_active):
            if mine_active[n]['pc'] == ref0_pc and mine_active[n]['opcode'] == ref0_op:
                return ref_active, mine_active[n:], 0, n

    # Search: skip N from ref to match mine[0]
    for n in range(1, lookahead):
        if n < len(ref_active):
            if ref_active[n]['pc'] == mine0_pc and ref_active[n]['opcode'] == mine0_op:
                return ref_active[n:], mine_active, n, 0

    return ref_active, mine_active, 0, 0   # no sync found

# ── Diff helpers ──────────────────────────────────────────────────────────────

# Fields to compare, in priority order (PC/OP divergence is most severe).
SCALAR_FIELDS  = ['COND', 'IDLE', 'FA', 'FB', 'KR', 'SR', 'R5', 'PREG',
                  'EXT', 'RAMOP', 'RAMREG', 'ROMREG']
NIBBLE_FIELDS  = ['A', 'B', 'C', 'D', 'E', 'IO']   # 16-char hex strings

def diff_entries(r, m):
    """
    Return a dict of differences between two entries.
    Keys: field names.  Values: (ref_val, mine_val).
    """
    diffs = {}
    pc_match = r['pc'] == m['pc'] and r['opcode'] == m['opcode']
    if not pc_match:
        diffs['PC/OP'] = (f"{r['pc']} {r['opcode']}", f"{m['pc']} {m['opcode']}")
    for f in SCALAR_FIELDS:
        rv, mv = r.get(f, ''), m.get(f, '')
        if rv and mv and rv != mv:
            diffs[f] = (rv, mv)
    for f in NIBBLE_FIELDS:
        rv, mv = r.get(f, ''), m.get(f, '')
        if rv and mv and rv != mv:
            diffs[f] = (rv, mv)
    return diffs

def highlight_nibbles(ref_str, mine_str):
    """Colour differing nibble positions in two 16-char hex strings."""
    hi_r, hi_m = [], []
    for a, b in zip(ref_str.ljust(16,'?'), mine_str.ljust(16,'?')):
        if a != b:
            hi_r.append(red(a));   hi_m.append(green(b))
        else:
            hi_r.append(a);        hi_m.append(b)
    return ''.join(hi_r), ''.join(hi_m)

# ── Formatting ────────────────────────────────────────────────────────────────

def fmt_short(e, prefix='', idx=None):
    """One-line summary: [prefix #N] PC opcode  mnemonic  KR=.. COND=. IDLE=."""
    n = f' #{idx}' if idx is not None else ''
    tag = f'[{prefix}{n}]' if prefix else ''
    flags = (f"  KR={e.get('KR','?')} FA={e.get('FA','?')} "
             f"COND={e.get('COND','?')} IDLE={e.get('IDLE','?')}")
    mnem = e['mnem'][:20].ljust(20)
    return f"{tag:12} {e['pc']} {e['opcode']}  {mnem}{flags}"

def fmt_full(e, label):
    """Four-line block for the diverging entry."""
    lines = [
        f"  {label}: {e['pc']} {e['opcode']}  {e['mnem']}",
        f"    A={e.get('A','?')} B={e.get('B','?')} C={e.get('C','?')} "
        f"D={e.get('D','?')} E={e.get('E','?')}",
        f"    FA={e.get('FA','?')} KR={e.get('KR','?')} "
        f"COND={e.get('COND','?')} IDLE={e.get('IDLE','?')} "
        f"EXT={e.get('EXT','?')} IO={e.get('IO','?')}",
        f"    FB={e.get('FB','?')} SR={e.get('SR','?')} R5={e.get('R5','?')} "
        f"PREG={e.get('PREG','?')} RAMOP={e.get('RAMOP','?')} "
        f"RAMREG={e.get('RAMREG','?')} ROMREG={e.get('ROMREG','?')}",
    ]
    return '\n'.join(lines)

# ── Value-diff reporter ───────────────────────────────────────────────────────

def _print_value_diffs(vdl):
    """Print a block for each value-only difference (no PC/OP change)."""
    if not vdl:
        return
    print(f"\n{bold(yellow(f'Value differences ({len(vdl)}) — execution path continues:'))}")
    for (i, r, m, diffs) in vdl:
        print(f"  {dim(fmt_short(r, '~', i + 1))}")
        for field, (rv, mv) in diffs.items():
            if field in NIBBLE_FIELDS:
                hr, hm = highlight_nibbles(rv, mv)
                print(f"    {field:8}  ref={hr}")
                print(f"    {'':8}  mne={hm}")
            else:
                print(f"    {field:8}  ref={red(rv)}   mine={green(mv)}")

# ── Main analysis ─────────────────────────────────────────────────────────────

CONTEXT_BEFORE = 6    # matching instructions to show before the divergence
AFTER_LINES    = 8    # instructions to show from each file after divergence

def analyse(ref_path, mine_path):
    print(f"\n{bold('Parsing')} {ref_path} …", file=sys.stderr)
    ref_all  = parse(ref_path)
    print(f"{bold('Parsing')} {mine_path} …", file=sys.stderr)
    mine_all = parse(mine_path)

    ref_strip  = strip_redundant(ref_all)
    mine_strip = strip_redundant(mine_all)

    r_start = find_active_start(ref_strip)
    m_start = find_active_start(mine_strip)

    ref_active  = ref_strip[r_start:]
    mine_active = mine_strip[m_start:]
    ref_active, mine_active, r_skip, m_skip = sync_active(ref_active, mine_active)

    # ── Header ────────────────────────────────────────────────────────────────
    sep = '─' * 70
    print(f"\n{bold(sep)}")
    print(f"{bold('Reference:')}  {ref_path}")
    print(f"  total {len(ref_all):,} instructions, "
          f"{len(ref_strip):,} after strip, "
          f"{len(ref_active):,} active (from PC {ref_active[0]['pc']}"
          + (f", skipped {r_skip}" if r_skip else "") + ")")
    print(f"{bold('Emulator: ')}  {mine_path}")
    print(f"  total {len(mine_all):,} instructions, "
          f"{len(mine_strip):,} after strip, "
          f"{len(mine_active):,} active (from PC {mine_active[0]['pc']}"
          + (f", skipped {m_skip}" if m_skip else "") + ")")
    print(sep)

    # ── Walk forward: collect value diffs, stop only on path divergence ──────
    n = min(len(ref_active), len(mine_active))
    value_diffs_list = []   # (idx, r, m, diffs) for value-only differences
    div_idx = None
    for i in range(n):
        diffs = diff_entries(ref_active[i], mine_active[i])
        if not diffs:
            continue
        if 'PC/OP' in diffs:
            div_idx = i
            break
        else:
            value_diffs_list.append((i, ref_active[i], mine_active[i], diffs))

    _print_value_diffs(value_diffs_list)

    if div_idx is None:
        if len(ref_active) == len(mine_active):
            label = '✓ PATHS MATCH' if value_diffs_list else '✓ PERFECT MATCH'
            print(f"\n{green(label)} — all {n} active instructions identical in execution path.")
        else:
            shorter = 'reference' if len(ref_active) < len(mine_active) else 'emulator'
            print(f"\n{yellow('⚠ PARTIAL MATCH')} — first {n} instructions match on path, "
                  f"then {shorter} file ends.")
        return

    # ── Context: last CONTEXT_BEFORE instructions before path divergence ─────
    match_count = div_idx
    print(f"\n{bold('Common path preamble:')}"
          f"  {match_count} instruction(s) share the same PC before path divergence\n")

    ctx_start = max(0, div_idx - CONTEXT_BEFORE)
    if ctx_start > 0:
        print(dim(f"  … {ctx_start} earlier instructions omitted …"))
    for i in range(ctx_start, div_idx):
        marker = yellow(' ≠values') if any(j == i for (j, *_) in value_diffs_list) else ''
        print(dim(fmt_short(ref_active[i], '=', i + 1)) + marker)

    # ── Path divergence ───────────────────────────────────────────────────────
    r = ref_active[div_idx]
    m = mine_active[div_idx]
    diffs = diff_entries(r, m)

    print(f"\n{bold(red(f'PATH DIVERGENCE — instruction #{div_idx + 1}'))}\n")

    # Full state for both sides
    print(fmt_full(r, bold('REF ')))
    print(fmt_full(m, bold('MINE')))

    # Field-by-field diff
    print(f"\n  {bold('Differences:')}")
    for field, (rv, mv) in diffs.items():
        if field == 'PC/OP':
            print(f"  {'PC/OP':8}  ref={red(rv)}   mine={green(mv)}")
        elif field in NIBBLE_FIELDS:
            hr, hm = highlight_nibbles(rv, mv)
            print(f"  {field:8}  ref={hr}")
            print(f"  {'':8}  mne={hm}")
        else:
            print(f"  {field:8}  ref={red(rv)}   mine={green(mv)}")

    # Diagnosis hint
    print(f"\n  {bold('Diagnosis hints:')}")
    if 'PC/OP' in diffs:
        ref_pc, mine_pc = diffs['PC/OP']
        print(f"  • PC diverged: paths are out of sync.")
        print(f"    Ref is at {ref_pc.split()[0]}, emulator at {mine_pc.split()[0]}.")
        print(f"    Look at the preceding branch instruction — one side took it, the other did not.")
    if 'COND' in diffs and 'PC/OP' not in diffs:
        rv_cond, mv_cond = diffs['COND']
        opcode = r['opcode']
        is_branch = int(opcode, 16) & 0x1000
        if is_branch:
            direction = 'branch taken' if rv_cond == '1' else 'branch not taken'
            other = 'not taken' if rv_cond == '1' else 'taken'
            print(f"  • COND={rv_cond} in reference → {direction} ({r['pc']} → next).")
            print(f"  • COND={mv_cond} in emulator  → {other}.")
            print(f"  • The instruction immediately before this set COND differently.")
        else:
            print(f"  • COND differs after a non-branch instruction at PC {r['pc']}.")
            print(f"    The instruction set the condition flag to different values.")
    fa_diff = 'FA' in diffs
    reg_diffs = [f for f in ['A','B','C','D','E'] if f in diffs]
    if reg_diffs or fa_diff:
        print(f"  • Register(s) {', '.join(reg_diffs + (['FA'] if fa_diff else []))} differ"
              f" — an ALU/store/recall instruction produced different results.")

    # ── Subsequent paths ──────────────────────────────────────────────────────
    print(f"\n{bold('Subsequent path — Reference:')}  (next {AFTER_LINES} instructions)")
    for i in range(div_idx, min(div_idx + AFTER_LINES, len(ref_active))):
        e = ref_active[i]
        marker = red('← diverge') if i == div_idx else ''
        print(f"  #{i+1:4}  {e['pc']} {e['opcode']}  "
              f"{e['mnem'][:24]:24}  COND={e.get('COND','?')} {marker}")

    print(f"\n{bold('Subsequent path — Emulator:')}   (next {AFTER_LINES} instructions)")
    for i in range(div_idx, min(div_idx + AFTER_LINES, len(mine_active))):
        e = mine_active[i]
        marker = red('← diverge') if i == div_idx else ''
        print(f"  #{i+1:4}  {e['pc']} {e['opcode']}  "
              f"{e['mnem'][:24]:24}  COND={e.get('COND','?')} {marker}")

    print(f"\n{sep}")

# ── Binary trace loader ───────────────────────────────────────────────────────

def load_bin(path):
    """
    Load a TI59_TRACE.bin file via read_trace and return a list of dicts
    compatible with parse() output (same field names).  USER_EVENT and
    session records are silently dropped; only 'trace' records are returned.
    """
    records = _bin_reader.load_trace(path)
    # Filter to instruction records only; dedup and strip happen later via
    # strip_redundant() which works on the same dict format.
    entries = []
    for r in records:
        if r['type'] != 'trace':
            continue
        # translate binary dict → compare_trace field names
        # RAMOP: interpret flags bit 6 as "RAM op pending"
        ramop = f"{r['RAM_OP']:X}" if (r['cpuFlags'] & 0x0040) else '-'
        entries.append({
            'pc':     r['pc'],
            'opcode': r['opcode'],
            'mnem':   '',          # not stored in binary format
            'A':  r['A'], 'B': r['B'], 'C': r['C'], 'D': r['D'], 'E': r['E'],
            'FA': r['fA'], 'FB': r['fB'],
            'KR': r['KR'], 'SR': r['SR'],
            'EXT':    r['EXT'],
            'COND':   r['COND'],
            'IDLE':   r['IDLE'],
            'IO':     r['IO'],
            'R5':     r['R5'],
            'PREG':   r['PREG'],
            'RAMOP':  ramop,
            'RAMREG': f"{r['RAM_ADDR']:03d}",
            'ROMREG': f"{r['REG_ADDR']:02d}",
        })
    return entries

# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    raw_args = sys.argv[1:]
    use_bin  = '--bin' in raw_args
    args = [a for a in raw_args if not a.startswith('--')]
    if len(args) < 2:
        print(__doc__)
        sys.exit(1)

    ref_path  = args[0]
    mine_path = args[1]

    if use_bin:
        # ref is text (TI59E.LOG format), mine is binary (TI59_TRACE.bin)
        ref_all  = parse(ref_path)
        mine_all = load_bin(mine_path)
        _analyse_preloaded(ref_path, mine_path, ref_all, mine_all)
    else:
        analyse(ref_path, mine_path)


def _analyse_preloaded(ref_path, mine_path, ref_all, mine_all):
    """Run the analysis pipeline with already-parsed lists."""
    ref_strip  = strip_redundant(ref_all)
    mine_strip = strip_redundant(mine_all)

    r_start = find_active_start(ref_strip)
    m_start = find_active_start(mine_strip)

    ref_active  = ref_strip[r_start:]
    mine_active = mine_strip[m_start:]
    ref_active, mine_active, r_skip, m_skip = sync_active(ref_active, mine_active)

    sep = '─' * 70
    print(f"\n{bold(sep)}")
    print(f"{bold('Reference:')}  {ref_path}")
    print(f"  total {len(ref_all):,} instructions, "
          f"{len(ref_strip):,} after strip, "
          f"{len(ref_active):,} active (from PC {ref_active[0]['pc']}"
          + (f", skipped {r_skip}" if r_skip else "") + ")")
    print(f"{bold('Emulator: ')}  {mine_path}  {cyan('[binary]')}")
    print(f"  total {len(mine_all):,} instructions, "
          f"{len(mine_strip):,} after strip, "
          f"{len(mine_active):,} active (from PC {mine_active[0]['pc']}"
          + (f", skipped {m_skip}" if m_skip else "") + ")")
    print(sep)

    n = min(len(ref_active), len(mine_active))
    value_diffs_list = []   # (idx, r, m, diffs) for value-only differences
    div_idx = None
    for i in range(n):
        diffs = diff_entries(ref_active[i], mine_active[i])
        if not diffs:
            continue
        if 'PC/OP' in diffs:
            div_idx = i
            break
        else:
            value_diffs_list.append((i, ref_active[i], mine_active[i], diffs))

    _print_value_diffs(value_diffs_list)

    if div_idx is None:
        if len(ref_active) == len(mine_active):
            label = '✓ PATHS MATCH' if value_diffs_list else '✓ PERFECT MATCH'
            print(f"\n{green(label)} — all {n} active instructions identical in execution path.")
        else:
            shorter = 'reference' if len(ref_active) < len(mine_active) else 'emulator'
            print(f"\n{yellow('⚠ PARTIAL MATCH')} — first {n} instructions match on path, "
                  f"then {shorter} file ends.")
        return

    match_count = div_idx
    print(f"\n{bold('Common path preamble:')}"
          f"  {match_count} instruction(s) share the same PC before path divergence\n")

    ctx_start = max(0, div_idx - CONTEXT_BEFORE)
    if ctx_start > 0:
        print(dim(f"  … {ctx_start} earlier instructions omitted …"))
    for i in range(ctx_start, div_idx):
        marker = yellow(' ≠values') if any(j == i for (j, *_) in value_diffs_list) else ''
        print(dim(fmt_short(ref_active[i], '=', i + 1)) + marker)

    r = ref_active[div_idx]
    m = mine_active[div_idx]
    diffs = diff_entries(r, m)

    print(f"\n{bold(red(f'PATH DIVERGENCE — instruction #{div_idx + 1}'))}\n")
    print(fmt_full(r, bold('REF ')))
    print(fmt_full(m, bold('MINE')))

    print(f"\n  {bold('Differences:')}")
    for field, (rv, mv) in diffs.items():
        if field == 'PC/OP':
            print(f"  {'PC/OP':8}  ref={red(rv)}   mine={green(mv)}")
        elif field in NIBBLE_FIELDS:
            hr, hm = highlight_nibbles(rv, mv)
            print(f"  {field:8}  ref={hr}")
            print(f"  {'':8}  mne={hm}")
        else:
            print(f"  {field:8}  ref={red(rv)}   mine={green(mv)}")

    print(f"\n{bold('Subsequent path — Reference:')}  (next {AFTER_LINES} instructions)")
    for i in range(div_idx, min(div_idx + AFTER_LINES, len(ref_active))):
        e = ref_active[i]
        marker = red('← diverge') if i == div_idx else ''
        print(f"  #{i+1:4}  {e['pc']} {e['opcode']}  "
              f"{e['mnem'][:24]:24}  COND={e.get('COND','?')} {marker}")

    print(f"\n{bold('Subsequent path — Emulator:')}   (next {AFTER_LINES} instructions)")
    for i in range(div_idx, min(div_idx + AFTER_LINES, len(mine_active))):
        e = mine_active[i]
        marker = red('← diverge') if i == div_idx else ''
        print(f"  #{i+1:4}  {e['pc']} {e['opcode']}  "
              f"{'(binary—no mnemonic)':24}  COND={e.get('COND','?')} {marker}")

    print(f"\n{sep}")

if __name__ == '__main__':
    main()
