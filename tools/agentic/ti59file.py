"""Load a .ti59 state file into the headless emulator and run it.

Shared base of the tools in tools/agentic/ (see README.md there). Parses
PROGRAM, REGISTERS, PARTITION and KEYSTROKES, sets up a Machine from
tools/headless/ with printer and ML module, plays the keys, and times the run
in emulated seconds.

CLI: ti59file.py file.ti59 [--lines]
  Runs the file's KEYSTROKES and prints the time from the last key until the
  program has stopped and the printer is idle; --lines adds the printout."""
import os
import re
import sys
import ctypes as C
from decimal import Decimal

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'headless'))
from ti59 import Machine, LIB, INSTR_PER_SEC, IDLE_LO, IDLE_HI, FLG_IDLE  # noqa: E402

FLG_BUSY = 0x8000              # printer busy
# printer BUSY in instruction cycles (Core/TMC0501.hpp kPrinterLineCycles / kPrinterFeedCycles)
LINE_CYCLES, FEED_CYCLES = 4168, 1370
# KEYSTROKES matrix codes of the digit keys
DIGIT = {'0': '92', '1': '82', '2': '83', '3': '84', '4': '72', '5': '73', '6': '74', '7': '62', '8': '63', '9': '64'}


def regbytes(v):
    """16-nibble register image of a decimal value (13-digit mantissa)"""
    d = Decimal(v); neg = d < 0; d = abs(d)
    if d == 0:
        return bytes(16)
    e = d.adjusted()
    digs = (format(d.scaleb(-e), 'f').replace('.', '') + '0' * 13)[:13]
    nib = [0] * 16
    for i, ch in enumerate(digs):
        nib[15 - i] = int(ch)
    ae = abs(e); nib[2] = ae // 10; nib[1] = ae % 10
    nib[0] = (2 if neg else 0) | (4 if e < 0 else 0)
    return bytes(nib)


def parse(path):
    """(program keycodes, {register: value string}, total steps or None, keys).
    keys are KEYSTROKES matrix codes as strings; directive lines such as
    FullSpeed: are kept as 'FullSpeed:' entries."""
    sections = {}; cur = None
    for raw in open(path).read().split('\n'):
        line = raw.split('#')[0].rstrip()
        m = re.match(r'^([A-Z][A-Z-]*):\s*(.*)$', line.strip())
        if m and m.group(1) in ('PROGRAM', 'REGISTERS', 'KEYSTROKES', 'PARTITION', 'MODEL',
                                 'SOLID-STATE-MODULE', 'PRINTER', 'CUECARD'):
            cur = m.group(1); sections.setdefault(cur, [])
            if m.group(2):
                sections[cur].append(m.group(2))
            continue
        if cur and line.strip():
            sections[cur].append(line.strip())
    prog = {}; step = 0
    for l in sections.get('PROGRAM', []):
        if l.startswith('...'):
            continue
        m = re.match(r'^(\d{3})\s+(\d{1,2})\b', l)
        if m:
            prog[int(m.group(1))] = int(m.group(2)); step = int(m.group(1)) + 1; continue
        for t in re.findall(r'\b\d\d\b', l):
            prog[step] = int(t); step += 1
    regs = {}
    for l in sections.get('REGISTERS', []):
        m = re.match(r'^(\d\d)\s*=\s*(\S+)', l)
        if m:
            regs[int(m.group(1))] = m.group(2)
    part = None
    if sections.get('PARTITION'):
        part = int(sections['PARTITION'][0].split('.')[0]) + 1
    keys = []
    for l in sections.get('KEYSTROKES', []):
        if re.match(r'^[A-Za-z]+:', l):
            keys.append(l.split(':')[0] + ':')
        else:
            keys += re.findall(r'\b\d\d\b', l)[:2] if l.startswith('21') else re.findall(r'^\d\d', l)
    return [prog.get(i, 0) for i in range(max(prog) + 1 if prog else 0)], regs, part, keys


def real_keys(keys):
    """keys without the directive entries"""
    return [k for k in keys if not k.endswith(':')]


def press(m, code, hold=6000):
    """press and release a key (matrix code), holding it for `hold` instructions"""
    m.press(code); LIB.h_stepn(m.h, hold); m.release(code)


def idle(m):
    """program stopped, printer idle, CPU in the keyboard idle loop"""
    s = m.snapshot()
    return (not s.fB & 1) and not (s.flags & FLG_BUSY) and IDLE_LO <= s.pc <= IDLE_HI and s.flags & FLG_IDLE


def settle(m, limit_s=4000, chunk=20000):
    """Run until idle (three checks in a row) or limit_s emulated seconds."""
    start = m.elapsed(); quiet = 0
    while (m.elapsed() - start) / INSTR_PER_SEC < limit_s:
        LIB.h_stepn(m.h, chunk)
        quiet = quiet + 1 if idle(m) else 0
        if quiet >= 3:
            return True
    return False


def load(path, extra_regs=None):
    """(Machine with the file's partition, program and registers, its keys).
    The machine always has the printer and the ML module."""
    prog, regs, part, keys = parse(path)
    m = Machine(printer=True)
    if part:                                    # n Op 17: partition of (960 - 80 n) steps
        n = (960 - part) // 80
        for k in ([str(n)] if n < 10 else ['1', '0']) + ['2nd', '64', '82', '62', 'CLR']:
            m.key(k)
    m.write_program(prog)
    for n, v in {**regs, **(extra_regs or {})}.items():
        LIB.h_ram_write(m.h, 119 - n, (C.c_uint8 * 16)(*regbytes(v)))
    return m, keys


def play_until_last(path, keys=None):
    """Load the file and play all keys but the last, each to idle.
    Returns (machine, last key)."""
    m, k0 = load(path)
    keys = real_keys(keys if keys is not None else k0)
    for k in keys[:-1]:
        press(m, k); settle(m, 120)
    return m, keys[-1]


def run(path, keys=None):
    """Play the keys; time from the last key until idle.
    Returns (seconds, printed lines, finished, machine)."""
    m, last = play_until_last(path, keys)
    t0 = m.elapsed()
    press(m, last)
    ok = settle(m)
    return (m.elapsed() - t0) / INSTR_PER_SEC, m.printer_lines(), ok, m


def printer_floor(lines):
    """The printer's own minimum time for these lines; a blank line is one PRT.FEED"""
    printed = sum(1 for l in lines if l.strip())
    return (printed * LINE_CYCLES + (len(lines) - printed) * FEED_CYCLES) / INSTR_PER_SEC


if __name__ == '__main__':
    path = sys.argv[1]
    t, lines, ok, m = run(path)
    print(f'{path}: {t:7.1f} s  finished={ok}  lines={len(lines)} '
          f'(non-blank {sum(1 for l in lines if l.strip())})  printer floor {printer_floor(lines):5.1f} s')
    if '--lines' in sys.argv:
        print('\n'.join(lines))
