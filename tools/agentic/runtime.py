"""Program run time of every key in a .ti59 file's KEYSTROKES.

Times every key that runs a program (fB[0] set) from the key press until the
display lights up again (ti59file.dark_time), so work that a label key such
as A does before the timed start key is counted too. Use this to compare
programs that split their work differently between preparation keys and the
start key.

CLI: runtime.py file.ti59 [--keys "83 92 83 74 11 ..."]
  --keys replaces the file's KEYSTROKES (matrix codes, space separated).
  Prints key:seconds for each key that ran a program, and the total."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ti59file import load, real_keys, dark_time  # noqa: E402


def key_runtimes(path, keys=None):
    """[(key, seconds of program run time)]; 0 for a key that ran no program"""
    m, k0 = load(path)
    res = []
    for k in real_keys(keys if keys is not None else k0):
        t, _, ran = dark_time(m, k)
        res.append((k, t if ran else 0.0))
    return res


if __name__ == '__main__':
    args = sys.argv[1:]
    keys = args[args.index('--keys') + 1].split() if '--keys' in args else None
    r = key_runtimes(args[0], keys)
    print(' '.join(f'{k}:{t:.2f}' for k, t in r if t > 0), f' total {sum(t for _, t in r):.1f} s')
