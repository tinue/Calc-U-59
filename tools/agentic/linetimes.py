"""Time each printed line of a .ti59 file's run.

CLI: linetimes.py file.ti59 [--lines] [--limit S]
  Plays the KEYSTROKES; from the last key on, records the emulated time at
  which each printer line appears. Prints a summary by line kind (blank,
  calendar-style day row of 20 digits/spaces, other text) and the time of the
  last line. --lines lists every line with its time and its gap to the line
  before. --limit caps the run (default 4000 emulated seconds)."""
import os
import re
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ti59file import LIB, INSTR_PER_SEC, play_until_last, press, idle  # noqa: E402


def line_times(path, keys=None, limit=4000):
    """[(seconds after the last key, line)], machine. Stops 15 s after the
    last printed line once the calculator is idle."""
    m, last = play_until_last(path, keys)
    t0 = m.elapsed(); press(m, last)
    out = []
    while (m.elapsed() - t0) / INSTR_PER_SEC < limit:
        LIB.h_stepn(m.h, 200)
        now = (m.elapsed() - t0) / INSTR_PER_SEC
        out += [(now, l) for l in m.printer_lines()]
        if out and now - out[-1][0] > 15 and idle(m):
            break
    return out, m


def kind(line):
    return 'blank' if not line.strip() else ('week' if re.fullmatch(r'[ \d]{20}', line) else 'text')


if __name__ == '__main__':
    args = sys.argv[1:]
    limit = float(args[args.index('--limit') + 1]) if '--limit' in args else 4000
    out, m = line_times(args[0], limit=limit)
    prev = 0; cat = {}
    for t, l in out:
        if '--lines' in args:
            print(f'{t:8.2f} {t - prev:5.2f} |{l}|')
        cat.setdefault(kind(l), []).append(t - prev); prev = t
    for k, v in cat.items():
        print(f'{k:6} n={len(v):3} avg {sum(v) / len(v):5.2f}s  total {sum(v):6.1f}s  min {min(v):.2f} max {max(v):.2f}')
    print('total', round(out[-1][0], 2) if out else None)
