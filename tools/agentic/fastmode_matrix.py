"""What works in fast mode: every instruction class, run once in fast mode and
once in normal mode, with the outcomes compared.

Each case is a keycode body placed in the program
  000 RCL 59 R/S   007 St flg   008 CLR <body> STO 59 CLR +/- RST
(extra code, e.g. subroutines and label targets, from step 200). Fast mode is
entered by the SST method (examples/fastmode-sst.ti59); normal mode by
St flg 4 (the fast entry sets flag 4 too), GTO 008 R/S. SAME = same X, data
registers, printout and display; DIFF lists what differs. The Prg Src Flag
values seen while the program runs are shown in brackets ([0, 2] = fast mode
throughout, a 1 = the run went into the module).

The second table stops a fast-mode program with R/S or RST in various X
states and reports whether the calculator hangs in the redisplay loop
030A-030E (only power-off ends it).

Results and ROM explanation: rom/TI59-ROM-Guide.md § "Fast mode".

CLI: fastmode_matrix.py [substring]     only cases whose name contains it"""
import os
import sys
import ctypes as C
from collections import Counter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ti59file import Machine, LIB, INSTR_PER_SEC, regbytes, press, settle, idle  # noqa: E402

FAST_ENTRY = ['82', '85', '83', '52', '82', '83', '94', '95', '61', '92', '92', '62', '41', '92', '42']
NORMAL_ENTRY = ['21', '81', '72', '61', '92', '92', '63', '91']   # St flg 4, GTO 008 R/S
REGS = {0: '10', 1: '5', 2: '3', 3: '7', 4: '1000', 5: '2', 6: '30', 7: '0.5', 8: '4', 9: '9'}
EXIT = [42, 59, 25, 94, 81]                                       # STO 59 CLR +/- RST
TO200 = {200: [4, 4] + EXIT}                                      # transfer target: 44 → R59
LBL200 = {200: [76, 11, 4, 4] + EXIT}                             # Lbl A 44 → R59
SUB200 = {200: [4, 4, 92]}                                        # subroutine: 44 INV SBR
SIGMA = [3, 32, 4, 78, 5, 32, 6, 78]                              # two Σ+ data points
CASES = [
    ('AOS ( 2 + 3 ) * 4 ^ 2 =', [53, 2, 85, 3, 54, 65, 4, 45, 2, 95]),
    ('8 levels of parentheses', [53] * 8 + [1, 85, 2] + [54] * 8 + [95]),
    ('lnx log INV lnx sin cos tan', [5, 23, 28, 22, 23, 38, 39, 30]),
    ('sqrt 1/x x2 |x| Int INV Int pi', [7, 94, 50, 34, 35, 33, 22, 59, 89]),
    ('EE entry, INV EE, Fix 2, Eng', [1, 93, 5, 52, 3, 94, 22, 52, 58, 2, 57, 95]),
    ('Rad / Grad', [70, 1, 38, 80, 5, 0, 38, 60]),
    ('STO RCL SUM Prd Exc INV SUM', [7, 42, 20, 44, 20, 49, 20, 22, 44, 20, 48, 21]),
    ('STO/RCL/SUM/Exc/Prd Ind', [9, 72, 8, 73, 8, 74, 8, 63, 8, 64, 8, 73, 4]),
    ('CMs, CP, x<>t, CE', [47, 5, 32, 29, 32, 6, 24, 7]),
    ('HIR STO / RCL / SUM', [7, 82, 5, 3, 82, 35, 82, 15]),
    ('Op 10, Op 20, Op 31, Op 16', [5, 94, 69, 10, 69, 20, 69, 31, 69, 16]),
    ('Op 17 (5 Op 17: R59 gone, error)', [5, 69, 17, 9]),
    ('Op Ind, Fix Ind, Pgm (select)', [2, 0, 42, 30, 84, 30, 3, 42, 30, 58, 40, 30, 36, 1, 43, 0]),
    ('St flg / If flg nnn', [86, 1, 87, 1, 2, 0, 0, 7], TO200),
    ('If flg Ind', [86, 3, 87, 40, 2, 2, 0, 0, 7], TO200),
    ('GTO nnn', [61, 2, 0, 0, 9], TO200),
    ('GTO Ind', [2, 0, 0, 42, 30, 83, 30, 9], TO200),
    ('x=t nnn', [5, 32, 5, 67, 2, 0, 0, 9], TO200),
    ('INV x>=t nnn', [5, 32, 3, 22, 77, 2, 0, 0, 9], TO200),
    ('x=t Ind', [2, 0, 0, 42, 30, 5, 32, 5, 67, 40, 30, 9], TO200),
    ('Dsz nnn loop', [5, 42, 0, 0, 1, 44, 30, 97, 0, 0, 13, 43, 30]),
    ('Lbl and Nop in the flow', [76, 13, 68, 5]),
    ('Pause', [5, 66, 6]),
    ('Prt Adv Op 00-06', [5, 99, 98, 69, 0, 1, 7, 69, 1, 69, 5, 6, 69, 6]),
    ('Op 08 (list labels)', [69, 8], {200: [76, 11, 76, 12, 92]}),
    ('error 1/0, Op 18 / Op 19', [0, 35, 69, 19, 87, 7, 2, 0, 0, 5], TO200),
    ('R/S in digit entry, R/S key', [5, 91, 6], None, ['91']),
    ('GTO label', [61, 11, 9], LBL200),
    ('x=t label', [5, 32, 5, 67, 11, 9], LBL200),
    ('If flg label', [86, 1, 87, 1, 11, 9], LBL200),
    ('Dsz label loop', [5, 42, 0, 0, 76, 12, 1, 44, 30, 97, 0, 12, 43, 30]),
    ('SBR nnn', [71, 2, 0, 0, 85, 1, 95], SUB200),
    ('SBR label', [71, 11, 85, 1, 95], {200: [76, 11, 4, 4, 92]}),
    ('SBR Ind', [2, 0, 0, 42, 30, 71, 40, 30, 85, 1, 95], SUB200),
    ('Pgm 20 SBR 086 (ML-20)', [36, 20, 71, 0, 86, 85, 1, 95]),
    ('Sigma+, x-bar', SIGMA + [79]),
    ('P->R / INV P->R', [4, 5, 32, 2, 37]),
    ('D.MS / INV D.MS', [1, 93, 3, 0, 88]),
    ('Op 11-15 (Op 12 shown)', SIGMA + [69, 12]),
    ('INV SBR at top level', [5, 92, 6]),
    ('error with St flg 8', [86, 8, 0, 35, 5]),
    ('St flg 9 (trace)', [86, 9, 5, 85, 3, 95, 22, 86, 9]),
]
STOPS = [
    ('5 R/S', [5, 91]), ('CLR R/S', [25, 91]), ('5 + 3 = R/S', [5, 85, 3, 95, 91]),
    ('RCL 01 R/S', [43, 1, 91]), ('5 STO 01 R/S', [5, 42, 1, 91]), ('RCL 01 CE R/S', [43, 1, 24, 91]),
    ('RCL 01 Pause R/S', [43, 1, 66, 91]), ('RCL 01 Prt R/S', [43, 1, 99, 91]),
    ('RCL 01 RST', [43, 1, 81]), ('5 + 3 = RST', [5, 85, 3, 95, 81]),
    ('5 + 3 = CLR RST', [5, 85, 3, 95, 25, 81]), ('RCL 01 CLR +/- RST', [43, 1, 25, 94, 81]),
    ('RCL 01 0 RST', [43, 1, 0, 81]), ('RCL 01 Pause RST', [43, 1, 66, 81]), ('RCL 01 Prt RST', [43, 1, 99, 81]),
]


def regval(b):
    """register image → short decimal string"""
    if not any(b):
        return '0'
    m = ''.join(str(b[i]) for i in range(15, 2, -1))
    s = ('-' if b[0] & 2 else '') + m[0] + '.' + m[1:].rstrip('0')
    e = b[2] * 10 + b[1]
    return s + (f'e{"-" if b[0] & 4 else ""}{e}' if e else '')


def watch(m, limit=60):
    """run until idle; (finished, Prg Src values seen while running)"""
    t0 = m.elapsed(); srcs = set(); quiet = 0
    while (m.elapsed() - t0) / INSTR_PER_SEC < limit:
        LIB.h_stepn(m.h, 400)
        s = m.snapshot()
        if s.fB & 1:
            srcs.add(s.SCOM[0][3])
        quiet = quiet + 1 if idle(m) else 0
        if quiet >= 40:
            return True, srcs
    return False, srcs


def run(body, fast, extra=None, keys_after=(), exit_=EXIT, limit=60):
    m = Machine(printer=True)
    prog = [43, 59, 91, 0, 0, 0, 0, 86, 25] + list(body) + list(exit_)
    for at, codes in (extra or {}).items():
        prog += [0] * max(0, at - len(prog))
        prog[at:at + len(codes)] = codes
    m.write_program(prog)
    for n, v in REGS.items():
        LIB.h_ram_write(m.h, 119 - n, (C.c_uint8 * 16)(*regbytes(v)))
    keys = FAST_ENTRY if fast else NORMAL_ENTRY
    for k in keys[:-1]:
        press(m, k); settle(m, 60)
    m.press(keys[-1]); LIB.h_stepn(m.h, 3000); m.release(keys[-1])
    ok, srcs = watch(m, limit)
    for k in keys_after:
        press(m, k); ok2, s2 = watch(m, limit); ok &= ok2; srcs |= s2
    disp = set()                                # sampled, so a blinking display compares equal
    for _ in range(30):
        LIB.h_stepn(m.h, 5000); disp.add(m.display().strip())
    return dict(ok=ok, srcs=sorted(srcs), disp=sorted(disp), lines=m.printer_lines(),
                regs=[regval(m.ram(119 - n)) for n in range(60)], m=m)


def compare(name, body, extra=None, keys_after=()):
    f = run(body, True, extra, keys_after); n = run(body, False, extra, keys_after)
    diffs = [f'{k}: fast={f[k]!r} normal={n[k]!r}' for k in ('ok', 'disp', 'lines') if f[k] != n[k]]
    diffs += [f'R{r:02}: fast={a} normal={b}' for r, (a, b) in enumerate(zip(f['regs'], n['regs'])) if a != b]
    print(f'{"DIFF" if diffs else "SAME"} {name:32} fast {f["srcs"]}  normal {n["srcs"]}')
    for d in diffs[:4]:
        print('      ', d)


def stop_test(name, body):
    r = run(body, True, exit_=[], limit=3)
    m = r['m']; pcs = Counter(x.pc for x in m.record(200000))
    hung = min(pcs) >= 0x030A and max(pcs) <= 0x030E
    print(f'{name:20} {"HANGS 030A-030E" if hung else "stops":16} Prg Src {m.snapshot().SCOM[0][3]}  display {r["disp"]!r}')


if __name__ == '__main__':
    pick = sys.argv[1] if len(sys.argv) > 1 else ''
    for c in CASES:
        if pick in c[0]:
            compare(c[0], c[1], c[2] if len(c) > 2 else None, c[3] if len(c) > 3 else ())
    if not pick:
        print('\nstopping a fast-mode program:')
        for name, body in STOPS:
            stop_test(name, body)
