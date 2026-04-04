# Calc-U-59 Debug Trace Format

`TI59_TRACE.bin` — binary execution trace produced by the emulator when the
**C-DBG** toggle is active.  Designed to be machine-read (Python tools) and
occasionally human-scanned with `read_trace.py`.

---

## 1  File Location

| Platform | Path |
|----------|------|
| iOS / iPadOS | iCloud Drive → *Calc-U-59* → `TI59_TRACE.bin` |
| macOS (simulator or app) | `~/Library/Mobile Documents/iCloud~ch~erzberger~calcu59/Documents/TI59_TRACE.bin` |
| Fallback (no iCloud) | `<NSDocumentDirectory>/TI59_TRACE.bin` |

The file is **appended** across sessions.  Delete it manually between unrelated
capture runs.  The file header is written only when the file is new (size == 0).

---

## 2  Endianness

All multi-byte integers are **little-endian**.  Both the authoring devices
(arm64) and the analysis Mac (x86\_64 or arm64) are LE — no byte-swapping is
needed in readers.  Python: `struct.unpack('<…', …)`.

---

## 3  File Header  (16 bytes, at offset 0)

| Offset | Size | Field | Value |
|--------|------|-------|-------|
| 0 | 4 | `magic` | `0x54493539`  ("TI59" as ASCII bytes in LE order) |
| 4 | 2 | `version` | `1` |
| 6 | 2 | `pad` | `0` |
| 8 | 8 | `reserved` | `0` |

---

## 4  Record Envelope  (3 bytes, prefixes every record)

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 1 | `type` | Record type (see §5) |
| 1 | 2 | `payloadLength` | Byte count of the payload that follows |

Unknown `type` values **must** be skipped by advancing `payloadLength` bytes.
This allows forward-compatible additions.

---

## 5  Record Types

### 5.1  SESSION\_START  (type `0x01`, payload 8 bytes)

Written when C-DBG is toggled **ON**.

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 8 | `unixTimestamp` | Seconds since Unix epoch (`uint64_t`) |

---

### 5.2  TRACE\_EVENT  (type `0x02`, payload 120 bytes)

One record per *surviving* instruction execution after deduplication (see §6).

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 4 | `suppressedBefore` | Events identical to this one that were dropped immediately before it |
| 4 | 4 | `seqno` | Monotonically increasing counter; gaps indicate ring-buffer overflow |
| 8 | 2 | `pc` | ROM address of the instruction |
| 10 | 2 | `opcode` | 13-bit opcode fetched from ROM at `pc` |
| 12 | 2 | `fA` | F-register A (shift register A) |
| 14 | 2 | `fB` | F-register B |
| 16 | 2 | `KR` | Key Row register |
| 18 | 2 | `SR` | Shift register |
| 20 | 2 | `EXT` | External pin state |
| 22 | 2 | `PREG` | P-register (page) |
| 24 | 2 | `cpuFlags` | All `FLG_*` bits: IDLE (bit 0), COND (bit 11), JUMP (bit 12), … |
| 26 | 1 | `R5` | R5 flag register |
| 27 | 1 | `digit` | Digit-counter value at execution time (0–15) |
| 28 | 1 | `RAM_ADDR` | Last RAM address accessed |
| 29 | 1 | `RAM_OP` | Last RAM operation code |
| 30 | 1 | `REG_ADDR` | Last ROM register address |
| 31 | 1 | `cycleWeight` | `1` = active cycle, `4` = idle cycle |
| 32 | 16 | `A[16]` | Register A nibbles — **one nibble per byte**, index 0 = LSN (digit 0), index 15 = MSN |
| 48 | 16 | `B[16]` | Register B nibbles (same layout) |
| 64 | 16 | `C[16]` | Register C nibbles |
| 80 | 16 | `D[16]` | Register D nibbles |
| 96 | 16 | `E[16]` | Register E nibbles |
| 112 | 8 | `Sout[8]` | Serial output (display) — **nibble-packed**: byte *i* = `Sout[2i]` in low nibble, `Sout[2i+1]` in high nibble |

**Total record size:** 3 + 120 = **123 bytes**.

**Nibble order note:** index 0 is the LSN (least-significant nibble, digit position 0).
`read_trace.py` reverses the order when producing human-readable output to match the
MSN-first convention of the reference TI59E.LOG format.

**Snapshot timing — post-auto-restore, pre-instruction-body**

All register and flag fields in a TRACE_EVENT record reflect CPU state **after** the
COND auto-restore but **before** the instruction body has executed.  This matches the
convention used by the reference TI59E.LOG emulator and is essential for correct
comparison with it.

Background: after a run of branch instructions, the TMC0501 automatically sets COND=1
on the first non-branch instruction (the "auto-restore").  The reference emulator
captures its snapshot at that point — after the restore, before the instruction modifies
any state.  Consequently, COND-clearing instructions such as `?TFKR` and `?TST fA[b]`
record COND=1 in the snapshot even though COND is 0 after they finish.

Exception: **branch instructions** (opcode bit 12 set) capture their snapshot
post-execution because they return early before the auto-restore point.  This is
consistent with the reference; branches do not modify registers or COND in a way that
would be affected by timing.

**Excluded fields:**
- `SCOM[16][16]` — internal calculator memory, not useful for instruction-level debugging.
- RAM array contents — excluded per design; `RAM_ADDR`/`RAM_OP` metadata is sufficient.

---

### 5.3  SESSION\_END  (type `0x03`, payload 8 bytes)

Written when C-DBG is toggled **OFF**.

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 4 | `eventCount` | Total TRACE\_EVENT records written in this session |
| 4 | 4 | `suppressedTotal` | Total events suppressed across the entire session |

---

### 5.4  USER\_EVENT  (type `0x04`, payload 4 bytes)

Written immediately when a user interaction occurs.  Not subject to
deduplication.  Interleaved in the stream at the exact position relative to
surrounding TRACE\_EVENT records.

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 1 | `kind` | See table below |
| 1 | 1 | `param1` | Key events: row (0-based); card events: `0` |
| 2 | 1 | `param2` | Key events: col (0-based); card events: `0` |
| 3 | 1 | `param3` | Reserved, `0` |

| `kind` | Meaning |
|--------|---------|
| `0x01` | Key down |
| `0x02` | Key up |
| `0x03` | Card inserted into reader |
| `0x04` | Card ejected from reader |

`read_trace.py` renders USER\_EVENT records as a banner between instruction lines:

```
--------------------------------------------------------------------------------
KEY DOWN  row=3  col=5
--------------------------------------------------------------------------------
```

---

## 6  Deduplication

**Purpose:** IDLE loops and WAIT/KEY\_ALL HOLD cycles re-execute the same
instruction hundreds or thousands of times without changing CPU state.
Storing every repetition would bloat the file and bury the interesting
transitions.

**Dedup key:** `(pc, opcode, digit, fA, fB, KR, SR, cpuFlags, R5, A, B, C, D, E)`

`seqno` and `cycleWeight` are excluded from the key (they always differ).

**Algorithm:**

```
for each new event E:
    if E.key == pending.key:
        pending.suppressedBefore += 1     # accumulate, do NOT write
    else:
        if pending exists:
            write pending                 # last-of-run (carries full count)
        write E with suppressedBefore = 0 # first-of-run
        pending = E
on close:
    if pending exists: write pending
```

A run of *N* identical events produces exactly **2** records:
- First (suppressedBefore = 0)
- Last (suppressedBefore = N − 2)

A unique event (no repetition) produces **1** record (suppressedBefore = 0,
serves as both first and last).

---

## 7  Estimated File Size

| Scenario | Events/s | Bytes/s | 60 s |
|----------|----------|---------|------|
| Full active computation | ~5 000 distinct | ~615 KB | ~37 MB |
| Typical interactive | ~500 distinct | ~62 KB | ~4 MB |
| Idle wait (deduped) | 2 records/loop | ~246 B | ~15 KB |

iCloud syncs files of this size without special treatment.

---

## 8  Python Tools

All scripts live in `tools/`.  Run them from the project root (the working
directory does not matter as long as file paths are given explicitly).

| Script | Purpose |
|--------|---------|
| `tools/read_trace.py` | Parse `TI59_TRACE.bin` → human-readable text or JSON |
| `tools/compare_trace.py` | Find the first divergence between two execution traces |

---

### `tools/read_trace.py`

Parses one or more `TI59_TRACE.bin` files and writes to stdout.

```
python3 tools/read_trace.py <file.bin>           # TI59E.LOG-style text
python3 tools/read_trace.py --json <file.bin>    # JSON array of all records
```

**Output format (text mode)**

- `SESSION START` / `SESSION END` lines mark recording boundaries.
- Each instruction is rendered as four lines matching the TI59E.LOG convention
  (MSN-first register display).
- Duplicate runs are shown as a single first entry followed by `... N ...`
  where N is the number of suppressed identical events.
- User interactions are shown as a banner:
  ```
  --------------------------------------------------------------------------------
  KEY DOWN  row=3  col=5
  --------------------------------------------------------------------------------
  ```

**Importable API**

```python
import tools.read_trace as rt          # or adjust sys.path as needed

records = rt.load_trace("TI59_TRACE.bin")
# records: list of dicts with 'type' in {'session_start','session_end','trace','user'}

trace_only = rt.trace_events_only(records)
# trace_only: list of 'trace' dicts, fields: pc, opcode, A–E, fA, fB, KR, SR,
#             COND, IDLE, EXT, PREG, IO, R5, RAM_ADDR, RAM_OP, REG_ADDR,
#             suppressedBefore, seqno, digit, cycleWeight, cpuFlags
```

---

### `tools/compare_trace.py`

Strips idle-loop repetitions and HOLD cycles from both traces, aligns them at
the first active instruction (IDLE=0, non-zero KR), then walks forward to find
the first divergence.  Reports the matching preamble, the diverging instruction
with per-field diffs highlighted in colour, and the subsequent 8-instruction
path from each trace.

```
# Both files in TI59E.LOG text format (reference vs reference):
python3 tools/compare_trace.py <ref.LOG> <other.LOG>

# Reference in text format, emulator capture in binary format:
python3 tools/compare_trace.py --bin <ref.LOG> TI59_TRACE.bin

# Typical workflow:
python3 tools/compare_trace.py --bin 1x.LOG 1x.bin
```

`compare_trace.py` imports `read_trace` from the same `tools/` directory; no
`PYTHONPATH` changes are needed when both files are present.
