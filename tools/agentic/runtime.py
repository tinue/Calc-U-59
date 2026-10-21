"""Program run time of every key in a .ti59 file's KEYSTROKES.

Counts only the time the calculator is running a program (fB[0] set), so
work that a label key such as A does before the timed start key is counted
too. Use this to compare programs that split their work differently between
preparation keys and the start key.

CLI: runtime.py file.ti59 [--keys "83 92 83 74 11 ..."]
  --keys replaces the file's KEYSTROKES (matrix codes, space separated).
  Prints key:seconds for each key that ran a program, and the total."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ti59file import LIB, INSTR_PER_SEC, load, settle, real_keys  # noqa: E402


def key_runtimes(path, keys=None):
    """[(key, seconds of program run time)]"""
    m, k0 = load(path)
    res = []
    for k in real_keys(keys if keys is not None else k0):
        m.press(k); run = 0; started = False; quiet = 0
        for i in range(400000):
            LIB.h_stepn(m.h, 100)
            if i == 60:
                m.release(k)
            if m.snapshot().fB & 1:
                started = True; run += 100; quiet = 0
            elif started:
                quiet += 1
                if quiet > 20000:      # stopped for good, not just a short gap
                    break
            elif i > 2000:             # the key started no program
                break
        settle(m, 4000)
        res.append((k, run / INSTR_PER_SEC))
    return res


if __name__ == '__main__':
    args = sys.argv[1:]
    keys = args[args.index('--keys') + 1].split() if '--keys' in args else None
    r = key_runtimes(args[0], keys)
    print(' '.join(f'{k}:{t:.2f}' for k, t in r if t > 0), f' total {sum(t for _, t in r):.1f} s')
