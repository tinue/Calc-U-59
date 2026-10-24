# Agentic tools

Command-line tools for interactive work by a coding agent (or a person at a
terminal) on TI-59 programs: run a `.ti59` file headless, time it, see where
the time goes, measure what single steps cost, disassemble and assemble
keycode programs. Each tool prints a few plain lines that are easy to read
back in a conversation; none of them opens a window or needs the app.

They sit on top of the headless harness in `tools/headless/` (the
unmodified `Core/` emulator driven from Python via ctypes). That harness is
for ROM-level traces; these tools work at the level of a user program and
its printout.

## Running

From the repository root:

```bash
uv run python tools/agentic/<tool>.py <args>
```

- Paths inside the tools are resolved from their own location, so they also
  work from another directory.
- The headless library builds itself on first import
  (`tools/headless/build.sh`). After changes to `Core/` or
  `tools/headless/capi.cpp`, rebuild it.
- In zsh, `uv` may be aliased with `noglob`, so `examples/calendar-0*.ti59`
  is passed on literally. Expand globs with `$(ls examples/calendar-0*.ti59)`.
- A full calendar year takes about 1–2 s of real time to emulate; the slow
  1978 programs take up to ~30 s.

## Time base

All times are **emulated seconds**: weighted CPU instructions (an idle-loop
instruction counts 4) divided by `INSTR_PER_SEC` = 455 kHz / 32 = 14219
(`tools/headless/ti59.py`, `Machine.elapsed()`). They match the published
real-hardware times of the calendar programs within a few seconds.

## The tools

| Tool | What it answers |
|---|---|
| `ti59file.py` | Does the file run, how long from the start key, what did it print? Also the shared library for the other tools. |
| `linetimes.py` | When did each printer line appear? Which lines are slow? |
| `runtime.py` | How much program run time does each key cost, including preparation keys before the start key? |
| `hotsteps.py` | Which program steps are hot; is the printer the bottleneck; is fast mode on; what runs between two lines? |
| `stepcost.py` | What does one step (or a short sequence) cost in fast mode and in normal mode? |
| `fastmode_matrix.py` | Which instructions work in fast mode, and which stops hang the calculator? |
| `kdis.py` | What does the program in a `.ti59` file say, instruction by instruction? |
| `asm59.py` | Library: write a keycode program with mnemonics and labels instead of numbers. |
| `calendar/` | Tools for the calendar-printer programs (see below). |

### ti59file.py — load and run

```bash
uv run python tools/agentic/ti59file.py examples/calendar-09-dispatch.ti59 [--lines]
# examples/calendar-09-dispatch.ti59:    89.1 s  finished=True  lines=113 (non-blank 85)  printer floor  27.6 s
```

Loads the file (PARTITION via `n Op 17`, PROGRAM, REGISTERS), plays its
KEYSTROKES, each key to idle, and times the **last** key until the program
has stopped, the printer is idle and the CPU sits in the keyboard idle
loop. That end condition includes a few seconds of trailing idle checks, so
the figure is a little higher than the time of the last printed line (use
`linetimes.py` for that). `printer floor` = the printer's own minimum: 4168
instruction cycles per printed line, 1370 per blank (PRT.FEED) line. `--lines` appends the printout.

Library use (`sys.path.insert(0, 'tools/agentic')`):

- `parse(path)` → `(keycodes, {reg: value}, steps, keys)`
- `load(path, extra_regs=None)` → `(Machine, keys)`
- `run(path, keys=None)` → `(seconds, lines, finished, Machine)`
- `press`, `settle`, `idle`, `play_until_last`, `real_keys`, `regbytes`,
  `DIGIT` (digit → KEYSTROKES matrix code)

The machine always gets the printer and the ML module, whatever the file
says. `ZeroElapseTime:`, `FullSpeed:` and the other directive lines are
kept in `keys` as `'Name:'` entries and skipped when keys are played.

### linetimes.py — time of each printed line

```bash
uv run python tools/agentic/linetimes.py file.ti59 [--lines] [--limit S]
# blank  n= 28 avg  0.29s  total    8.1s  min 0.00 max 0.44
# text   n= 24 avg  0.45s  total   10.7s  min 0.37 max 0.48
# week   n= 61 avg  0.97s  total   59.4s  min 0.89 max 1.34
# total 79.04
```

Seconds from the last key to each printed line. The summary groups the gaps
by line kind (`week` = a 20-character line of digits and spaces). `--lines`
lists `time gap |line|` for every line, which shows at once which lines carry
extra work (e.g. the first row of each month). `total` is the time of the
last printed line: the figure used for the calendar comparisons.

### runtime.py — program run time per key

```bash
uv run python tools/agentic/runtime.py file.ti59 [--keys "83 92 83 74 11 ..."]
# 11:0.15 42:78.39  total 78.5 s
```

Counts only the time a program is running (`fB[0]` set) for every key, so a
label key that does preparation work before the start key is counted too.
**Use this when comparing two programs that split their work differently.**
Timing only from the start key can hide seconds of preparation: a version of
the calendar-09 program whose `A` key called ML-20 looked 4 s faster than
Acosta's from the start key, but was 1.5 s slower in total. `--keys`
replaces the file's KEYSTROKES (matrix codes).

### hotsteps.py — where the time goes

```bash
uv run python tools/agentic/hotsteps.py file.ti59 [--until S]
# ...: 20s  printer busy 24% of samples, print-wait spin 0%, Prg Src {2: 2869}
# hottest program steps: 377:2.2%, 124:1.4%, ...
uv run python tools/agentic/hotsteps.py file.ti59 --window A B
# 049:2 050:11 051:29 ... 018:14 019:20 ...
```

The default mode samples the run every 97 instructions:
- **Printer busy:** when this is low, the program is limited by its own
  calculation, not by the printer.
- **Print-wait spin:** time in the ROM loops that wait for the printer.
- **Prg Src:** the Prg Src Flag values seen. 2, 4 or 6 means fast mode; 0 is
  normal mode.
- **Hottest steps:** the 25 program steps with the most samples.

`--window A B` lists the program steps executed between A and B seconds as
`step:samples` (one sample per 20 instructions, about 1.4 ms). Take A and B
from `linetimes.py --lines` to see exactly what runs before a slow line.

### stepcost.py — cost of single steps

```bash
uv run python tools/agentic/stepcost.py                 # table of common steps
uv run python tools/agentic/stepcost.py "43 22" "73 00" # your own keycode sequences
# 43 22            fast    580  normal   1332  instructions  (41 / 94 ms)
```

Each sequence runs 30 times from step 008, once in fast mode (SST entry) and
once in normal mode, minus an empty program. Registers are preset (see the
docstring); choose register numbers in the cases accordingly. Useful values
from the table: RCL/STO ≈ 580, SUM/Exc ≈ 650–700, RC* ≈ 930, Op 05 (print a
line) ≈ 3200, a digit ≈ 120 instructions in fast mode. Normal mode costs about
twice as much.

### fastmode_matrix.py — what works in fast mode

```bash
uv run python tools/agentic/fastmode_matrix.py          # all cases, then the stop table
uv run python tools/agentic/fastmode_matrix.py label    # only cases whose name contains "label"
# SAME GTO nnn                          fast [0, 2]  normal [0]
# DIFF SBR nnn                          fast [0, 1]  normal [0]
# RCL 01 RST           HANGS 030A-030E  Prg Src 0  display ['']
```

Runs each instruction class once in fast mode (SST entry) and once in
normal mode, and compares X, the data registers, the printout and the
display. The brackets list the Prg Src Flag values seen while the program
ran: a 1 means the run went into the module. The stop table ends a fast
program with R/S or RST in various X states and reports whether the
calculator hangs. The results are summarized in `rom/fastmode.md`; the ROM
explanation is in `rom/TI59-ROM-Guide.md` § "What a fast-mode program can do".

### kdis.py — disassembler

```bash
uv run python tools/agentic/kdis.py file.ti59
# 000  R/S
# 001  Lbl A
# 003  STO 69
```

One line per instruction with its operands folded in. Then come the
registers, the keys and the number of steps. `dis(keycodes)` is the library
form.

### asm59.py — assembler (library)

```python
from asm59 import assemble, digits
code, labels = assemble(['RCL', 4, ('L', 'LOOP'), 'Op', 20, 'Dsz', 1, ('A', 'LOOP'), 'R/S'])
```

Tokens:
- mnemonic strings (table `KC`) and raw keycode ints;
- `('L', name)` defines a label, `('A', name)` emits a 2-byte absolute
  address;
- `('D2', a, b)` emits the label distance a − b as two digit steps;
- `('N', text)` attaches a comment to the next step.

`assemble(tokens, listing={})` fills `listing` with step → (shown text,
notes) for writing an annotated `PROGRAM:` section (see
`calendar/fastcal.py`). Add missing mnemonics to `KC` as needed.

## Calendar tools (`calendar/`)

For the 1978–1981 calendar-printer programs (`examples/calendar-0*.ti59`,
`examples/CALENDAR_PROGRAMS.md`).

| Tool | Use |
|---|---|
| `check.py printout.txt year` | Day rows against Python's `calendar` (Sunday first). Library: `check(lines, year)`. |
| `years.py file.ti59 year…` | Runs the file for each year (replaces the 4 digit keys before the first `A`), checks the dates, and compares line by line with Acosta's program for the same year. Library: `with_year(path, year)`, e.g. for `runtime.py`'s `key_runtimes`. |
| `compare.py file.ti59…` | Steps, time of the last printed line, and date check for each program with its own KEYSTROKES. |
| `fastcal.py out.ti59` | Generator of `examples/calendar-09-dispatch.ti59` (program, registers, annotated listing; header text from `calendar-09-header.txt`). Edit the generator, not the example. |
| `swapcal.py out.ti59` | Generator of the earlier swap design (correct but 92.6 s), kept for reference. |

Typical check after changing `fastcal.py`:

```bash
uv run python tools/agentic/calendar/fastcal.py examples/calendar-09-dispatch.ti59
uv run python tools/agentic/calendar/years.py examples/calendar-09-dispatch.ti59 1900 2000 2024 2026
uv run python tools/agentic/runtime.py examples/calendar-09-dispatch.ti59
```

## Pitfalls

- **Two numbering systems.** KEYSTROKES and `press()` use key matrix codes
  (row × 10 + column: `2` is 83, `A` is 11). PROGRAM uses keycodes (`2` is 02,
  `A` is 11). See `reference/StateFileFormat.md`.
- **Program longer than the partition.** `write_program` silently writes
  past the partition into the top registers and corrupts them. Check that the
  step count fits.
- **Op 2x / Op 3x** increment or decrement only R00–R09.
- **Values in REGISTERS** are written with 13 significant digits. For print
  codes, the position of the digits within the 13-digit mantissa matters (a
  2-digit vs 3-digit integer part shifts them).
- **Fast mode:** the rules (no SBR, no labels as targets, safe endings) are
  in `rom/fastmode.md`; `examples/fastmode-sst.ti59` is the SST entry.
- **Settle overhead.** Key handling plus the idle checks cost ~1.6 s of
  emulated time per key. Don't sum the per-key times of `ti59file.run`;
  use `runtime.py`.
- **Harness requirements.** The tools need `h_elapsed` in
  `tools/headless/capi.cpp` and `Machine.elapsed()` / `INSTR_PER_SEC` in
  `tools/headless/ti59.py`.
