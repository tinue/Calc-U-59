# Headless harness

Drives the unmodified `Core/` emulator from Python (ctypes) to capture ROM
traces of keystroke sequences — the tool behind the trace annotations in
`rom/*-commented.asm`. `build.sh` compiles a `.dylib` with clang++, so the
harness runs on macOS only.

```bash
tools/headless/build.sh                                  # once (auto-run on first import)
uv run python tools/headless/ti59.py 5 + 7 =             # trace each key, idle loop collapsed
uv run python tools/headless/ti59.py --full 5            # don't collapse the idle loop
uv run python tools/headless/ti59.py --boot              # also print the power-on trace
uv run python tools/headless/ti59.py --summary 5 + 7 =   # distinct PCs per key with hit counts
uv run python tools/headless/ti59.py --program 2,99,91 RST R/S   # keycodes written to step 000…
uv run python tools/headless/ti59.py --printer --module ML 2nd Pgm 0 1 …
uv run python tools/headless/ti59.py --variant TI58C 5 + 7 =     # TI-58C ROM (labels: rom/TI58C-labels.asm)
```

Each trace line: `PC OPCODE dDIGIT [c0 = COND active] mnemonic  changes…`,
where *changes* lists the registers / SCOM rows (`S<n>`, MSD first) the
instruction modified. Labels from `rom/TI59-labels.asm` are shown inline.

Key names: see `KEYS` in `ti59.py` (`2nd`, `INV`, `lnx`, `x<>t`, `x2`,
`sqrt`, `1/x`, `y^x`, `+/-`, …, plus `PRINT` / `PAPER` for the PC-100's own
buttons); 2nd functions are two presses, as on the hardware. Library use:
`from ti59 import Machine` — `Machine().key("5")` returns per-instruction
`HRec` records (post-execution CPU state).

`coverage.py` maps keystroke scenarios to the ROM words they execute
(`build`, `show`, `unique`, `gaps`; see its docstring).

For running, timing and profiling whole `.ti59` programs (rather than
tracing the ROM), see `tools/agentic/`.
