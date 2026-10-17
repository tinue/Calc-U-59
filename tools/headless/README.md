# Headless harness

Drives the unmodified `Core/` emulator from Python (ctypes) to capture ROM
traces of keystroke sequences — the tool behind the trace annotations in
`rom/TI59-commented.asm`.

```bash
tools/headless/build.sh                  # once (auto-run on first import)
tools/headless/ti59.py 5 + 7 =           # trace each key, idle loop collapsed
tools/headless/ti59.py --full 5          # don't collapse the idle loop
tools/headless/ti59.py --boot            # power-on trace
tools/headless/ti59.py --printer --module ML 2nd Pgm 0 1 …
```

Each trace line: `PC OPCODE dDIGIT [c0 = COND active] mnemonic  changes…`,
where *changes* lists the registers / SCOM rows (`S<n>`, MSD first) the
instruction modified. Labels from `rom/TI59-labels.asm` are shown inline.

Key names: see `KEYS` in `ti59.py` (plus `PRINT` / `PAPER` for the PC-100's own buttons) (`2nd`, `INV`, `lnx`, `x<>t`, `x2`,
`sqrt`, `1/x`, `y^x`, `+/-`, …); 2nd functions are two presses, as on the
hardware. Library use: `from ti59 import Machine` — `Machine().key("5")`
returns per-instruction `HRec` records (post-execution CPU state).

For running, timing and profiling whole `.ti59` programs (rather than
tracing the ROM), see `tools/agentic/`.
