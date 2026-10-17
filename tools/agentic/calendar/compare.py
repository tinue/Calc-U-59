"""Time calendar programs, each with its own KEYSTROKES, and check them.

CLI: compare.py file.ti59...
  For each file: steps (without trailing zeros), seconds from the last key
  to the last printed line (linetimes.py), the year found in the printout,
  and the day-row check against Python's calendar module.
  zsh note: if `uv` is aliased with noglob, expand globs with $(ls ...)."""
import os
import re
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE)); sys.path.insert(0, HERE)
from ti59file import parse  # noqa: E402
from linetimes import line_times  # noqa: E402
from check import check  # noqa: E402

for path in sys.argv[1:]:
    out, m = line_times(path)
    lines = [l for _, l in out]
    years = re.findall(r'(\d{4})\.', ' '.join(lines))
    y = int(years[0]) if years else 2026
    prog = parse(path)[0]
    while prog and prog[-1] == 0:
        prog.pop()
    got, exp, bad = check(lines, y)
    print(f'{path:45} {len(prog):4} steps  {out[-1][0]:7.1f} s  year {y}  rows {got}/{exp}  bad={bad[:1]}')
