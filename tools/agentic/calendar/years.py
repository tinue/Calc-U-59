"""Run a calendar program for several years and check each printout.

CLI: years.py file.ti59 year...
  For each year: replaces the four digit keys before the first A (matrix
  code 11) in the file's KEYSTROKES, runs it, checks the day rows against
  Python's calendar module and compares the printout line for line with
  Acosta's program (examples/calendar-08-acosta.ti59) run for the same year.
  The printed time is from the last key until the display lights up
  again (ti59file.run).
Library: with_year(path, year) -> keys for runtime.key_runtimes etc."""
import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE)); sys.path.insert(0, HERE)
from ti59file import ROOT, DIGIT, parse, run  # noqa: E402
from check import check  # noqa: E402

ACOSTA = os.path.join(ROOT, 'examples', 'calendar-08-acosta.ti59')


def with_year(path, year):
    """the file's KEYSTROKES with the year digits before the first A (11) replaced"""
    keys = parse(path)[3]
    a = keys.index('11')
    return keys[:a - 4] + [DIGIT[c] for c in '%04d' % year] + keys[a:]


if __name__ == '__main__':
    path = sys.argv[1]
    for y in map(int, sys.argv[2:]):
        t, lines, ok, _ = run(path, with_year(path, y))
        _, ref, _, _ = run(ACOSTA, with_year(ACOSTA, y))
        got, exp, bad = check(lines, y)
        print(f'{y}: {t:6.1f} s  finished={ok}  rows {got}/{exp}  bad={bad}  same as Acosta: {lines == ref}')
