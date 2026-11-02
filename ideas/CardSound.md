# Card Sound

*Status: idea, not implemented. Goal: play the sound of a real card pass while
the calculator shows "C", and have the emulator take as long as the sound, so
that the result (e.g. "1") appears just as the sound ends. Rough timing is
enough. The emulator does not need to reproduce the real byte rate.*

## The plan

1. **Record the sound.** A cleaner take of a card pushed straight in, with a
   little more wait before it is pushed fully in than `Rasch.m4a` below (about
   0.25–0.30 s from motor start to grab). Quiet room, microphone close, a few
   takes to pick from. Trim to the motor start and keep the fade-out.
2. **Measure that take** as described under "Measurements": motor on, grab,
   motor off. These give the two constants of step 3.
3. **Make the emulator match it:**
   - The card switch opens at once. That is what makes the ROM start the motor
     and show "C" (about 33 ms later), so the wait comes after it, not before.
   - The reader stays busy for the free run, at the `TST.BUSY` loop at `16BE`.
   - `CRD.RD` and `CRD.WR` then hold for about 67 instruction times per byte,
     until the time of the recording's motor stop. Only the total has to be
     right, since nothing visible depends on the spacing of single bytes.
   - The ROM's `CRD.OFF` ends the pass, and the display returns about 30 ms
     later.
4. **Add the sound to the GUIs.** The stall goes in `Core/` and the motor state
   is exposed through `Shared/`. The Swift, Qt and web GUIs only play the file.

One recording is probably enough. A write or a failed read could get their own
later, if they sound different.

## Decisions and checks for the implementation

- **Tie the sound to the motor, not a timer.** Start at the first `CRD.RD` or
  `CRD.WR`, stop at `CRD.OFF`. R/S held during a pass aborts it (`16BF` → `1799`),
  and the sound has to stop with it.
- **Stop holding after a card's worth of bytes.** A refused card makes 261
  `CRD.RD` against 246 for a good read, about 70 ms too long if every one
  holds. The real chip must also stop holding at some point, probably when the
  card has left, because the refused path has more steps than a bank has bytes.
- **Keep the realistic timing with the sound off.** It is an accuracy gain: a
  pass goes from about 0.47 s to about 1.4 s, so programs that use cards get
  slower.
- **To check:** what full speed does during a pass (the sound only lines up at
  normal speed; it may be simplest to skip it there), and whether tests or
  preset playback (`ArmCard:`, `InsertCard:`) depend on the current speed.
- **To decide:** whether the sound includes the card being pulled out by hand.
  Leaning no: the emulator's card just disappears, and that sound would play
  after the display is back.

## Measurements

Two recordings by the project owner on a real TI-59, 2026-11-02: `Rasch.m4a`
(card pushed straight in) and `MitWarten.m4a` (motor left to ramp up first). They
are not in the repository. Times come from a change-point fit on the
band-limited RMS level. Motor on and grab are good to about ±10–30 ms; motor off
less so, because the sound fades over about 50 ms.

| | Rasch | MitWarten |
|---|---|---|
| Motor on | 1.526 s | 1.460 s |
| Card grabbed | 1.679 s | 2.165 s |
| Motor off | 2.840 s | 3.319 s |
| **Free run** (on → grab) | 0.153 s | 0.705 s |
| **Pull-through** (grab → off) | **1.161 s** | **1.154 s** |

So the pull-through is constant and only the free run depends on the hand.

What marks the grab, in both recordings:

- The level steps up, by 6.1 dB in Rasch and 4.4 dB in MitWarten.
- The motor hum falls from about 300 Hz to about 253 Hz within about 150 ms and
  stays there. The motor reaches its free-running speed about 130 ms after
  starting.
- A whine near 5.6 kHz appears (plus about 2.8–3 kHz), and lasts until shortly
  before the motor stops.

The clicks before the motor starts come 0.25 s and 0.55 s ahead of it, so they
cannot be a fixed delay and were taken as handling. The noise at 3.27–3.75 s in
Rasch was taken as the card being pulled out. Both are judgements from the sound
alone.

The emulator today (TI-59, 14218.75 instructions/s), headless, card inserted at
idle:

| Event | Time after insert |
|---|---|
| `CRD.RD` (`16BB`) | 33.5 ms |
| First `CRD.IN` (`16CD`) | 35.3 ms |
| `CRD.OFF` (`1795`) | 466.1 ms |

That is a pull-through of 0.431 s against about 1.155 s. The core has no card
transport timing: `CRD.RD` and `CRD.IN` never wait, so a pass costs ROM time
only (`Core/TMC0501.cpp`, the peripheral I/O case).

| ROM activity per pass | `CRD.RD`/`CRD.WR` | Longest gap between them |
|---|---|---|
| Read | 246 | 31 instruction times |
| Write | 248 | 48 instruction times |
| Refused card (wrong partition) | 261, of which 256 at `16F0` | 39 instruction times |

The real read byte period therefore lies above 31 instruction times (2.2 ms),
and at most about 67 (4.71 ms), the value if data starts right at the grab. The
time from the grab to the first data at the head can't be told from the audio.

## How the hardware paces a pass

- **HOLD stalls the CPU.** The reader chip (TMC0594) sets the HOLD bit on EXT,
  which "blocks address increment, so the same instruction is sent to CPU until
  HOLD bit is cleared", and can do so during `CRD_READ` and `CRD_WRITE` when it
  "needs more time" (Sladký, [*HW programming guide*](https://ti58c.phweb.me/download/system/TI_58_59-HW-manual.pdf),
  pp. 7, 20–21; [US 4006455](https://patents.google.com/patent/US4006455A/en)).
- **The ROM agrees.** The read loop has no status check between bytes, and the
  run-out loop at `16F0` is only `CRD.RD`, `INC KR`, `TST KR[12]`, `JC`. Unstalled,
  its 256 passes take 72 ms, far too short to let the rest of a card through.
- **`TST.BUSY` probably asks the chip.** The chip has a `KR` pin in the schematic
  (Sladký, p. 2) and the patent describes a BUSY signal from it, so the loop at
  `16BE` is likely waiting on the chip. This is an inference.
- **Reading is self-clocking.** Each of the two channels has a "ones" track and a
  "zeros" track, and every bit makes a transition on exactly one of them
  (US 4006455). The read rate follows the motor.
- **Write timing is probably fixed by the calculator's clock.** Nominal card speed
  is 2.3 inches/s, set by R11 on the board. The calculator works from 2.0 to 2.5,
  and above that "the write length exceeds the usable length of the card"
  ([Datamath, TMC0594](http://www.datamath.org/Chips/TMC0594.htm)). A fixed write
  time would also explain why TI's check of how far the card comes out after a
  write measures motor speed. The sources give no write bit rate, so this is an
  inference.

## If exact timing is ever wanted

A recording of a Write pass would give the byte period, if write timing really
is fixed, and comparing it with a read would give the lead-in. A recording of a
refused card would show whether that pass ends with the physical card. A logic
analyser on the printer connector (`EXT`, `IRG`, `IDLE`, both clock phases) at
about 57 kB/s (Sladký, p. 5) would show every stall directly.
