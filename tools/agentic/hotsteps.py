"""Where a running program spends its time: sampled program steps.

CLI: hotsteps.py file.ti59 [--until S]
       Samples the run (every 97 instructions, from the last key to S
       emulated seconds, default 200). Prints the share of samples with the
       printer busy, the share spent in the ROM's print-wait spin loops, the
       Prg Src Flag values seen (non-zero 2/4/6 = fast mode) and the 25
       hottest program steps.
     hotsteps.py file.ti59 --window A B
       The sequence of program steps executed between A and B seconds, as
       step:samples (one sample per 20 instructions), e.g. to see what runs
       between two printed lines (take A and B from linetimes.py --lines).

The step is read from SCOM[0] (nibbles 5-7 register, nibble 4 byte), so a
multi-byte instruction shows up at the byte being fetched."""
import os
import sys
from collections import Counter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ti59file import LIB, INSTR_PER_SEC, FLG_BUSY, play_until_last, press  # noqa: E402

PRINT_SPIN = (0x154C, 0x154D, 0x1425, 0x1426, 0x1427, 0x17C1, 0x17C2, 0x17C3, 0x15E4, 0x15E5, 0x1612, 0x1613)


def step_of(s):
    return int('%d%d%d' % (s.SCOM[0][7], s.SCOM[0][6], s.SCOM[0][5])) * 8 + s.SCOM[0][4]


def start(path):
    m, last = play_until_last(path)
    t0 = m.elapsed(); press(m, last)
    return m, t0


def profile(path, until=200.0):
    m, t0 = start(path)
    n = busy = spin = 0; steps = Counter(); src = Counter()
    while (m.elapsed() - t0) / INSTR_PER_SEC <= until:
        LIB.h_stepn(m.h, 97)
        s = m.snapshot(); n += 1
        busy += bool(s.flags & FLG_BUSY); spin += s.pc in PRINT_SPIN
        steps[step_of(s)] += 1; src[s.SCOM[0][3]] += 1
    print(f'{path}: {until:.0f}s  printer busy {100 * busy / n:.0f}% of samples, '
          f'print-wait spin {100 * spin / n:.0f}%, Prg Src {dict(src)}')
    print('hottest program steps:', ', '.join(f'{k:03d}:{100 * v / n:.1f}%' for k, v in steps.most_common(25)))


def window(path, a, b):
    m, t0 = start(path)
    seq = []
    while True:
        LIB.h_stepn(m.h, 20)
        t = (m.elapsed() - t0) / INSTR_PER_SEC
        if t > b:
            break
        if t >= a:
            st = step_of(m.snapshot())
            if seq and seq[-1][0] == st:
                seq[-1][1] += 1
            else:
                seq.append([st, 1])
    print(' '.join(f'{st:03d}:{k}' for st, k in seq))


if __name__ == '__main__':
    args = sys.argv[1:]
    if '--window' in args:
        i = args.index('--window')
        window(args[0], float(args[i + 1]), float(args[i + 2]))
    else:
        profile(args[0], float(args[args.index('--until') + 1]) if '--until' in args else 200.0)
