"""Cost of program steps in fast mode and in normal mode.

Each case is repeated 30 times in a small program that starts at step 008,
once entered by the SST fast-mode method and once by GTO 008 R/S. The cost
is the difference to an empty program, divided by 30, in weighted
instructions (INSTR_PER_SEC = 14219 per emulated second).

CLI: stepcost.py                     a table of common steps
     stepcost.py "43 22" "73 00"     the given keycode sequences instead
Registers preset for the cases: R00 = 10, R01 = 5, R04 = 1000,
R10-R12 = 2.000311000312, R22 = 98.99."""
import os
import sys
import ctypes as C
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ti59file import Machine, LIB, IDLE_LO, IDLE_HI, FLG_IDLE, INSTR_PER_SEC, regbytes, press, settle  # noqa: E402

FAST_ENTRY = ['82', '85', '83', '52', '82', '83', '94', '95', '61', '92', '92', '62', '41', '92', '42']
NORMAL_ENTRY = ['61', '92', '92', '63', '91']        # GTO 008 R/S
REGS = {0: '10', 10: '2.000311000312', 11: '2.000311000312', 12: '2.000311000312', 22: '98.99', 4: '1000', 1: '5'}
CASES = {
    'Nop': [68], 'digit 2': [2], 'x<>t': [32], 'RCL 22': [43, 22], 'STO 30': [42, 30], 'SUM 30': [44, 30],
    'Exc 30': [48, 30], 'RC* 00': [73, 0], 'HIR 05': [82, 5], 'HIR 36 (SUM)': [82, 36], 'INV Int': [22, 59],
    'Op 20': [69, 20], 'Op 05 (print)': [69, 5], '+ 1 =': [85, 1, 95],
}


def _cpu_idle(m):
    s = m.snapshot()
    return (not s.fB & 1) and IDLE_LO <= s.pc <= IDLE_HI and s.flags & FLG_IDLE


def measure(body, reps, fast=True, regs=REGS):
    """weighted instructions of body * reps, run from step 008, plus CLR RST"""
    prog = [91, 0, 0, 0, 0, 0, 0, 86] + body * reps + [25, 81]
    m = Machine(printer=True)
    m.write_program(prog)
    for n, v in (regs or {}).items():
        LIB.h_ram_write(m.h, 119 - n, (C.c_uint8 * 16)(*regbytes(v)))
    keys = FAST_ENTRY if fast else NORMAL_ENTRY
    for k in keys[:-1]:
        press(m, k); settle(m, 60)
    m.press(keys[-1]); LIB.h_stepn(m.h, 3000); m.release(keys[-1])
    t0 = m.elapsed(); quiet = 0
    while quiet < 20:
        LIB.h_stepn(m.h, 25)
        quiet = quiet + 1 if _cpu_idle(m) else 0
    return m.elapsed() - t0


def cost(body, reps=30):
    """(fast, normal) weighted instructions per repetition of body"""
    f = (measure(body, reps, True) - measure([], 1, True)) / reps
    n = (measure(body, reps, False) - measure([], 1, False)) / reps
    return f, n


if __name__ == '__main__':
    cases = {a: [int(x) for x in a.split()] for a in sys.argv[1:]} or CASES
    for name, body in cases.items():
        f, n = cost(body)
        print(f'{name:16} fast {f:6.0f}  normal {n:6.0f}  instructions'
              f'  ({f / INSTR_PER_SEC * 1000:.0f} / {n / INSTR_PER_SEC * 1000:.0f} ms)')
