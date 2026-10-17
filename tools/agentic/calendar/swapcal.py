"""Generator of the first fast calendar design (swap version), kept for reference.

Galidas/Acosta row engine, 5 unrolled rows with a Dsz re-entry for 6-row
months, days after the month end blanked by Exc swaps run as an inline
two-pass loop (undo the previous month, apply the new one), January weekday
and leap year from ML-20 SBR 086 under key A (normal mode). Correct output,
but 92.6 s for 2026 (Acosta 82.3 s): the per-month tests and swaps cost
more than they save. The successor is fastcal.py.
Usage: swapcal.py out.ti59"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from asm59 import assemble, digits

PB = 28                        # P(x) lives in R(PB + x), x = -5..35  -> R23..R63
H = {28: 67, 29: 65, 30: 66}   # one-day entries "dd   "
B1, B2, B3 = 64, 68, 69        # blank entries swapped in for days after L
# R64 doubles as P(36), read by the last row when the 1st is a Friday in a 31-day month.
# It is only swapped (with P29) in a 28-day February, which never reads it.
MONTHS = 7                     # JAN record in R07 .. DEC in R18 (int part = days, low digits = name)
FEB = MONTHS + 1
WD1, WD3, WD4 = 19, 20, 21     # weekday line (R20 gives chunk 3 and, via INV Int, chunk 2)
K9899 = 22
# variables: R00 table pointer, R01 month counter (ML-20's month input in A), R02 weekday of the 1st (Sun = 0),
# R03 month pointer (also ML-20's year input), R04 year, R05 extra-row counter, R06 days in month
# (R00 also holds the new month's length during the tail fix-up and dn(Y) in A)


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
MONTH_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]


def registers():
    r = {}
    for i, (nm, L) in enumerate(zip(MONTH_NAMES, MONTH_DAYS)):
        s = '%02d' % L + '0' + nm          # 2 + 1 + 10 = 13 digits
        r[MONTHS + i] = s[:2] + '.' + s[2:]
    r[WD1] = '1.000036000030'; r[WD3] = '1.014300003700'; r[WD4] = '1.000021000036'
    r[K9899] = '98.99'
    r[6] = '31'                    # previous month's length: none swapped (a run leaves it at 31 again)
    for x in range(-5, 36):
        r[PB + x] = P(x)
    for L, reg in H.items():
        r[reg] = Hval(L)
    for reg in (B1, B2, B3):
        r[reg] = P(-1)
    return r


def swap(a, b):                 # exchange Ra and Rb
    return ['RCL', a, 'Exc', b, 'STO', a]


def row():
    return ['RC*', 0, 'HIR', 5, 'SUM', 0,
            'RC*', 0, 'HIR', 6, 'RCL', K9899, 'HIR', 36, 'Op', 20,
            'RC*', 0, 'SUM', 0, 'INV', 'Int', 'HIR', 7,
            'RC*', 0, 'SUM', 0, 'HIR', 8, 'Op', 5]


def program():
    p = ['R/S', 0, 0, 0, 0, 0, 0, 'StFlg']            # 000 R/S after the final RST; 007 fast-mode trigger
    # ── fast-mode part, starts at 008 ──
    p += ['Adv', 'INV', 52, 1, 2, 'STO', 1, 7, 'STO', 3]   # INV EE: leave the entry's sci format
    p += [('L', 'MONTH'),
          'RC*', 3, 'HIR', 8, 'Int', 'STO', 0,              # name into the buffer, new L into R00
          'RCL', 4, 'Op', 6,                                # header line: year + name
          'RCL', WD3, 'HIR', 7, 'INV', 'Int', 'HIR', 6, 'RCL', WD1, 'HIR', 5,
          'RCL', WD4, 'HIR', 8, 'Op', 5]                    # weekday line
    # Blank the days after L, inline (SBR/RTN do not survive fast mode). R06 holds the
    # previous month's length, R00 the new one. Pass 1 undoes the previous month's swaps
    # (a swap is self-inverse), pass 2 applies the new month's. At TEND t is the length
    # this pass worked on; if it already equals the new length, the table is right.
    p += [('L', 'TAIL'), 'RCL', 6, 'x<>t', 3, 0, 'x=t', ('A', 'S30'), 2, 9, 'x=t', ('A', 'S29'),
          3, 1, 'x=t', ('A', 'TEND'),                       # 31 days: nothing to do; else 28
          ('L', 'S28')] + swap(PB + 28, H[28]) + swap(PB + 29, B1) + ['GTO', ('A', 'T2'),
          ('L', 'S29')] + swap(PB + 29, H[29]) + [
          ('L', 'T2')] + swap(PB + 30, B2) + ['GTO', ('A', 'T3'),
          ('L', 'S30')] + swap(PB + 30, H[30]) + [
          ('L', 'T3')] + swap(PB + 31, B3) + [
          ('L', 'TEND'), 'RCL', 0, 'STO', 6, 'INV', 'x=t', ('A', 'TAIL')]
    p += [2, 9, '-', 'RCL', 2, '=', 'STO', 0,               # pointer = R(PB + 1 - s)
          'Op', 25,                                         # R05: 0 -> 1 (one pass)
          'RCL', 2, '+', 'RCL', 6, '-', 2, 8, '=', 'STO', 2,  # t = s + L - 28  (0..9)
          'x<>t', 0, 'x=t', ('A', 'C2'),                    # t = 0: 4 rows
          7, 'x>=t', ('A', 'W'),                            # t <= 7: 5 rows
          7, 'INV', 'SUM', 2, 'Op', 25, 'GTO', ('A', 'C1'),  # t >= 8: 6 rows (R05 = 2), next s = t - 7
          ('L', 'W'), 'x=t', ('A', 'W7'), 'GTO', ('A', 'C1'),
          ('L', 'W7'), 0, 'STO', 2]                         # t = 7: next s = 0
    p += [('L', 'C1')] + row() + [('L', 'C2')] + row() + row() + row() + [('L', 'C5')] + row()
    p += ['Dsz', 5, ('A', 'C5'),                            # 6-row month: one more pass through the last copy
          'Adv', 'Op', 23, 'Dsz', 1, ('A', 'MONTH'),
          'Adv', 'HIR', 14, 'INV', 'SUM', FEB, 'CLR', 'RST']
    # ── normal-mode preparation: YYYY A ──
    # s = weekday of Jan 1 (ML-20 day number of "Jan 0", mod 7), leap = dn(Y+1) - dn(Y) - 365.
    p += [('L', 'A'), 76, 11, 'STO', 4, 'STO', 3, 1, 'STO', 1, 0, 'STO', 2,
          36, 20, 'SBR', 0, 86, 'STO', 0,
          'Op', 23, 'Op', 23, 36, 20, 'SBR', 0, 86,   # ML-20 left R03 = Y-1 (Jan/Feb shift): +2 -> Y+1
          '-', 'RCL', 0, '-'] + digits('365') + ['=',
          'HIR', 4, 'SUM', FEB,                              # leap kept in HIR register 4
          'RCL', 0, '-', '(', 24, '/', 7, ')', 'Int', '*', 7, '=', 'STO', 2,   # s = dn mod 7
          'R/S']
    return assemble(p)


def write_ti59(path):
    code, labels = program()
    regs = registers()
    out = ['MODEL: TI-59', 'SOLID-STATE-MODULE: ML', 'PRINTER: on', 'PARTITION: 399.69', '', 'PROGRAM:']
    for i in range(0, len(code), 20):
        out.append(' '.join('%02d' % k for k in code[i:i+20]) + '   # %03d-%03d' % (i, min(i+19, len(code)-1)))
    out += ['', 'REGISTERS:'] + ['%02d = %s' % (k, v) for k, v in sorted(regs.items())]
    out += ['', 'KEYSTROKES:', '83', '92', '83', '74', '11', '82', '85', '72', '52', '82', '83', '94', '95', '61', '92', '92', '62', '41', '92', '42']
    open(path, 'w').write('\n'.join(out) + '\n')
    return code, labels


if __name__ == '__main__':
    code, labels = write_ti59(sys.argv[1] if len(sys.argv) > 1 else '/dev/null')
    print(len(code), 'steps', labels)
