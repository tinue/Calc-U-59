"""Generate examples/calendar/calendar-09-dispatch.ti59, the fast calendar printer.

Same row engine as Galidas/Acosta, entered with the SST fast-mode method.
Per month, the record's integer part is the address of a fix-up routine for
the change of month length (GTO Ind). The month loop reads the record first
and jumps to its routine, which copies the right day pairs into P28..P31,
sets t to the row-end threshold and falls into the header code. A 13th
record holds the address of the end of the run, so there is no month
counter. February enters the second row copy after its own copy of the
header code. Usage: fastcal.py out.ti59   (e.g. examples/calendar/calendar-09-dispatch.ti59)"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from asm59 import assemble, digits

PB = 6                         # P(x) lives in R(PB + x), x = -5..36  -> R01..R42. PB = 6 makes the
                               # next month's pointer simply R00 - T (see END).
BLANK = PB - 5                 # P(-5): an all-blank entry
N = {28: 43, 29: 44, 30: 45, 31: 46}   # the normal P28..P31, for restoring
H = {28: 47, 29: 48, 30: 49}           # one-day entries "dd   "
MONTHS = 50                    # JAN record in R50 .. DEC in R61 (int part = fix-up address, low digits = name)
FEB = MONTHS + 1
ENDREC = 62                    # 13th record: the address of EXIT
WD1, WD3, WD4 = 63, 64, 65     # weekday line (R64 gives chunk 3 and, via INV Int, chunk 2)
K9899 = 66
FIX, MPTR, YEAR = 67, 68, 69   # fix-up address, month pointer, year
# The preparation borrows R00 (year z), FIX (E) and MPTR (pass counter).


def T(L):                      # row-end threshold: stop once the pointer reaches day L + 1
    return PB + L + 1


def ch(n):
    """two print codes for day n (blank outside 1..31)"""
    if n < 1 or n > 31:
        return '0000'
    t, u = divmod(n, 10)
    code = lambda d: '%02d' % (d + 1 if d < 7 else d + 3)   # 0->01 .. 6->07, 7->10 8->11 9->12
    return ('00' if t == 0 else code(t)) + code(u)


def pval(chunk10, top='201'):
    s = top + chunk10                      # 13 significant digits
    return s[0] + '.' + s[1:]


def P(x):
    return pval(ch(x) + '00' + ch(x + 1))


def Hval(L):
    return pval(ch(L) + '000000')


MONTH_NAMES = ['0000251331', '0000211714', '0000301335', '0000133335', '0000301345', '0025413117',
               '0025412745', '0000134122', '0036173337', '0000321537', '0000313242', '0000161715']
# fix-up routine per month: the change of length from the month before
MONTH_FIX = ['J', 'F28', 'MAR', 'F30', 'R30', 'F30', 'R30', 'J', 'F30', 'R30', 'F30', 'R30']


def registers(labels):
    """register -> (value, comment)"""
    r = {}
    for i, (nm, fx) in enumerate(zip(MONTH_NAMES, MONTH_FIX)):
        a = str(labels[fx])
        r[MONTHS + i] = (a + '.' + nm.rjust(13 - len(a), '0'),   # name in the low 10 of 13 digits
                         'JAN FEB MAR APR MAY JUNE JULY AUG SEPT OCT NOV DEC'.split()[i] + f', fix-up {fx} at {a}')
    r[ENDREC] = (str(labels['EXIT']), f'end of the year: EXIT at {labels["EXIT"]}')
    r[WD1] = ('1.000036000030', 'weekday line, chunk 1');  r[WD3] = ('1.014300003700', 'chunks 3 and 2')
    r[WD4] = ('1.000021000036', 'chunk 4');  r[K9899] = ('98.99', 'shifts chunk 2 by two digits')
    for x in range(-5, 37):
        r[PB + x] = (P(x), f'P({x})')
    for L, reg in N.items():
        r[reg] = (P(L), f'normal P({L})')
    for L, reg in H.items():
        r[reg] = (Hval(L), f'P({L}) of a {L}-day month')
    return r


def copy(src, dst):
    return ['RCL', src, 'STO', dst]


def row():
    return ['RC*', 0, 'HIR', 5, 'SUM', 0,
            'RC*', 0, 'HIR', 6, 'RCL', K9899, 'HIR', 36, 'Op', 20,
            'RC*', 0, 'SUM', 0, 'INV', 'Int', 'HIR', 7,
            'RC*', 0, 'SUM', 0, 'HIR', 8, 'Op', 5]


def tset(L):
    return digits(str(T(L))) + ['x<>t']


def header():
    """the year with the month name (Op 06), then the weekday line"""
    return ['RCL', YEAR, 'Op', 6,
            'RCL', WD3, 'HIR', 7, 'INV', 'Int', 'HIR', 6, 'RCL', WD1, 'HIR', 5, 'RCL', WD4, 'HIR', 8, 'Op', 5]


def program():
    n = lambda text: ('N', text)
    p = [n('After the final RST: stop. Fast-mode entry runs 001-006 as 00 from the drained'),
         n('program cache, so they can hold the normal-mode code for YYYY A.'),
         'R/S', 'Lbl', 'A', 'STO', YEAR, 'R/S', 0,
         n('Fast-mode trigger: GTO 007 SST, a digit, STO.'), 'StFlg',
         n('Fast mode from here. INV EE leaves the entry\'s scientific format.'),
         'INV', 'EE',
         n('E(z) = Int(z/4) - Int(z/100) + Int(z/400) for z = Y, then Y - 1.'),
         'RCL', YEAR, 'STO', 0, 2, 'STO', MPTR,
         ('L', 'E'), 'RCL', 0, '/', 4, '=', 'Int', '-', '(', 'RCL', 0, '/', 1, 0, 0, ')', 'Int',
         '+', '(', 'RCL', 0, '/', 4, 0, 0, ')', 'Int', '=',
         n('Op 30: z - 1. After two passes x = E(Y), FIX = E(Y-1).'),
         'Exc', FIX, 'Op', 30, 'Dsz', MPTR, ('A', 'E'),
         n('Leap year E(Y) - E(Y-1): FEB then dispatches to F29, which subtracts it again.'),
         '-', 'RCL', FIX, '=', '*', ('D2', 'F29', 'F28'), '=', 'SUM', FEB,
         n('Month pointer: NEXT adds 1 before reading the JAN record.'),
         4, 9, 'STO', MPTR,
         n('n = Y + E(Y-1); Jan 1 falls on weekday n mod 7 (Sun = 0). t = n and'),
         n('x = 7 Int(n/7) + 7: END makes the pointer x - t = 7 - (n mod 7) = P(1 - s).'),
         'RCL', FIX, '+', 'RCL', YEAR, '=', 'STO', 0, 'x<>t', 'RCL', 0, '/', 7, '+', 1, '=', 'Int', '*', 7, '=',
         'GTO', ('A', 'END')]
    p += [('L', 'F30'), n('31 -> 30 days: t = threshold, P30 = "30", P31 blank.')] + tset(30) + \
         copy(H[30], PB + 30) + copy(BLANK, PB + 31) + ['GTO', ('A', 'HEADER')]
    p += [('L', 'MAR'), n('28/29 -> 31 days: restore P28-P31 ...')] + copy(N[28], PB + 28) + copy(N[29], PB + 29)
    p += [('L', 'R30'), n('30 -> 31 days: restore P30, P31.')] + copy(N[30], PB + 30) + copy(N[31], PB + 31)
    p += [('L', 'J'), n('31 -> 31 days (JAN, AUG): only the threshold.')] + tset(31)
    p += [('L', 'HEADER'), n('Header line: the year (Op 06) with the name from NEXT in chunk 4. Weekday line.')] + \
         header()
    p += [('L', 'ROWS'), n('Four row copies: one printed line of 7 days each.')] + row() + \
         [('L', 'ROWS2')] + row() + row() + row()
    p += [('L', 'R5'), n('Row 5, and row 6 while the pointer is below day L + 1.')] + row() + \
         ['RCL', 0, 'INV', 'x>=t', ('A', 'R5')]
    assert PB == 6
    p += [('L', 'END'), n('Next pointer = Int(R00) - t, or P(1) when the last row was full (Z).'),
          'Int', 'x=t', ('A', 'Z'),
          ('L', 'S'), '-', 'x<>t', '=', 'STO', 0,
          ('L', 'NEXT'), n('Two blank lines, then the next record: name into chunk 4, jump to its fix-up.'),
          'Adv', 1, 'SUM', MPTR, 'RC*', MPTR, 'HIR', 8, 'STO', FIX, 'GO*', FIX]
    p += [('L', 'EXIT'), n('13th record: year done. Leave fast mode (RST, then R/S at 000).'),
          'Adv', 'CLR', 'RST']
    p += [('L', 'Z'), n('The month ended on Saturday: the next one starts on Sunday.'),
          PB + 1, 'STO', 0, 'GTO', ('A', 'NEXT')]
    p += [('L', 'F28'), n('31 -> 28 days: P28 = "28", P29-P31 blank.')] + tset(28) + \
         copy(H[28], PB + 28) + ['RCL', BLANK, 'STO', PB + 29,
          ('L', 'X'), 'STO', PB + 30, 'STO', PB + 31,
          n('February\'s own header code, then the second row copy: 4 rows from the copies,'),
          n('a 5th from R5 unless the 28-day February started on Sunday.')] + header() + \
         ['GTO', ('A', 'ROWS2')]
    p += [('L', 'F29'), n('31 -> 29 days. Restores the FEB record.')] + tset(29) + copy(H[29], PB + 29) + \
         [('D2', 'F29', 'F28'), 'INV', 'SUM', FEB, 'RCL', BLANK, 'GTO', ('A', 'X')]
    listing = {}
    code, labels = assemble(p, listing)
    # the leap-year delta must not change the number of digits of the FEB record
    assert 100 <= labels['F28'] < labels['F29'] <= 999 and labels['F29'] - labels['F28'] < 100
    assert len(code) <= 400, len(code)
    return code, labels, listing


HEADER = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'calendar-09-header.txt')).read()

KEYSTROKES = """KEYSTROKES:
FullSpeed:
83              # 2
92              # 0
83              # 2
74              # 6
11              # A      store the year
82              # 1
85              # +
83              # 2
52              # EE
82              # 1
83              # 2
94              # +/-
95              # =      X = 1.000000000002
61              # GTO
92              # 0
92              # 0
62              # 7      step 007, the St flg
41              # SST    St flg executes, its operand is pending
92              # 0      first operand digit
ZeroElapseTime:
42              # STO    fast mode starts: print the year
ReportElapseTime:
"""


def write_ti59(path):
    code, labels, listing = program()
    regs = registers(labels)
    out = [HEADER.rstrip('\n'), '', 'MODEL: TI-59', 'PRINTER: on', 'PARTITION: 399.69', '',
           'CUECARD:', 'Template: MagnetCard', 'Title: Calendar - fast mode, dispatch version', 'Banks: 1,2',
           'Row1: Key year, A; then 1 + 2 EE 12 +/- = GTO 007 SST 0 STO', 'Row1Align: left',
           'A: YEAR', '', 'PROGRAM:']
    for a, k in enumerate(code):
        text, notes = listing.get(a, ('', []))
        out += ['# ' + t for t in notes]
        out.append(f'{a:03d}  {k:02d} {text}'.rstrip())
    out += ['', 'REGISTERS:'] + [f'{k:02d} = {v:<16} # {c}' for k, (v, c) in sorted(regs.items())]
    out += ['', KEYSTROKES]
    open(path, 'w').write('\n'.join(out))
    return code, labels


if __name__ == '__main__':
    code, labels = write_ti59(sys.argv[1] if len(sys.argv) > 1 else '/dev/null')
    print(len(code), 'steps', labels)
