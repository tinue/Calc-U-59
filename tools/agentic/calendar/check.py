"""Check calendar day rows against Python's calendar module (Sunday first).

CLI: check.py printout.txt year
  printout.txt is any text with the printer lines (e.g. from
  ti59file.py --lines); only 20-character lines of digits and spaces count
  as day rows. Prints (rows found, rows expected, first mismatches).
Library: check(lines, year)."""
import sys, re, calendar
calendar.setfirstweekday(calendar.SUNDAY)


def check(lines, year):
    """(rows printed, rows expected, up to 3 (index, got, expected) mismatches)"""
    rows = [l for l in lines if re.fullmatch(r'[ \d]{20}', l) and l.strip()]
    got = [[int(x) if x.strip() else 0 for x in re.findall(r'.{3}', ' ' + l)[:7]] for l in rows]
    exp = [w for mth in range(1, 13) for w in calendar.monthcalendar(year, mth)]
    bad = [(i, g, e) for i, (g, e) in enumerate(zip(got, exp)) if g != e]
    return len(got), len(exp), bad[:3]


if __name__ == '__main__':
    print(check(open(sys.argv[1]).read().split('\n'), int(sys.argv[2])))
