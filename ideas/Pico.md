# Running Calc-U-59 on a Raspberry Pi Pico, Wired to Real TI-59 Hardware

*Status: idea / feasibility analysis, not a design doc and not implemented.
Two independent sub-projects: (1) porting `Core/` to run on RP2040/RP2350,
(2) physically interfacing that Pico with a donor TI-59's keyboard, display,
and optionally its magnetic card reader, reusing the calculator's
electromechanical parts while discarding a dead logic board.*

Source for the hardware facts below: *TI Programmable 58/59 Service Manual*
(local copy: `~/SynologyDrive/Dokumente/PDF/Vintage/TI/manuals/TI 59-service-manual.pdf`).
Page numbers refer to that document.

---

## 1. Running the emulation core on RP2040 / RP2350

Feasible with large margin; this half of the project is low-risk.

- **Performance.** The real hardware runs at ~14,219 instr/s active / ~3,555
  instr/s idle (455 kHz crystal ÷ 2 ÷ 16 — see `reference/CoreArchitecture.md`
  and confirmed by the manual's clock-tolerance table, p.4-5: high speed
  225.2–229.8 kHz, low speed 56.3–57.5 kHz, both two-phase). A single RP2040
  Cortex-M0+ core at 133 MHz has roughly four orders of magnitude of headroom;
  RP2350 is even more so. The bottleneck is *pacing* emulation down to real
  speed, not keeping up with it.
- **Memory.** ROM is 6144×13-bit words (~12 KB packed), user RAM is 120×16
  BCD nibbles, SCOM is 16×16 nibbles — all well under 1 KB of live state.
  RP2040's 264 KB SRAM / 2 MB flash (or RP2350's 520 KB / up to 16 MB)
  swallow this trivially.
- **Portability.** `Core/` is ~3,100 lines of plain C++17 (`Core/TMC0501.cpp`
  is the bulk at 1,861 lines), using only `<string>`, `<vector>`, `<mutex>`,
  `<atomic>`, `<cstdint>`-class STL, no thrown exceptions, no OS assumptions.
  This maps cleanly onto the Pico SDK's newlib/libstdc++. The two-thread
  model (`m_keyMutex`, `m_displayMutex`, `m_prnMutex`, atomic trace flags)
  is a nice fit for RP2040/2350's two real cores (emulation core vs. I/O
  core) but isn't required — a single-core cooperative loop is plenty at
  this instruction rate.
- **Real work.** None of it is in the emulation logic — it's a new thin
  platform layer (in the spirit of the existing `tools/` CLI, but targeting
  `arm-none-eabi`/Pico SDK/CMake instead of macOS): a real-time pacing loop
  around `step()`'s cycle-weight return, GPIO-based keyboard scan feeding
  `key[]`, and a driver that reads `getDisplay()` and pushes it to real
  segments. The card-reader/library-module state (`m_libData`,
  `m_cardBankBuffer`) is already pure software and ports trivially; physical
  card hardware is a separate concern (§3 below).

---

## 2. Interfacing the Pico with the real keyboard and display

This is the genuine reverse-engineering/electrical-engineering half of the
project. `Core/` only models keyboard and display *logically*; none of the
original chips' electrical drive characteristics are in this codebase.

### Voltage domain (manual p.3)

The whole machine is 1970s PMOS logic, referenced negative from system
ground, not anything 3.3V-CMOS-compatible:

| Signal | Min | Max |
|---|---|---|
| `Vss` (system ground) | 0V | 0V |
| `-VBatt` | −3.3V | −4.5V |
| `Vdd` | −9.5V | −10.5V (40 mA max sink) |
| `Vgg` | −15.3V | −16.3V (18 mA max sink) |

Every internal signal (D-lines, K-lines, IRG, EXT, IDLE, segment outputs)
swings within this negative-rail domain — confirmed by the scope photos
(p.44-45: 5V/div traces sitting several divisions below the 0 line). None of
it is directly compatible with Pico GPIO without translation.

### Keyboard — low risk (manual p.7-8, Fig.3)

The keyboard has **zero silicon**: "a plastic board with metallic discs
serving as switches to connect one D-line output to one K-line input." The
switches are just momentary shorts, so the voltage domain of the original
chips is irrelevant to them — the matrix can be scanned directly at 3.3V
from the Pico, ignoring the calculator's MOS chips entirely.

Exact 14-pin connector pinout from Fig.3:

- **Rows D1–D9** → pins 14, 6, 3, 9, 8, 11, 12, 2, 5
- **Columns KD / KP / KQ / KS / KT** → pins 1, 4, 7, 10, 13

A diode **CR5** is built into the matrix on the KP column — likely related
to the printer-detect signal that shares that line (see
`reference/CoreArchitecture.md`'s notes on PRN_CONNECTED sharing K-lines) —
worth accounting for polarity when scanning that column.

**Open question:** the manual's 5 K-lines (`KD, KP, KQ, KS, KT`) vs.
`reference/CoreArchitecture.md`'s 7-line `KN…KT` naming for the emulator's
internal model. Reconcile against the real connector (continuity test)
before wiring, and before assuming a 1:1 naming match.

### Display — needs a small driver board (manual p.9-10, Fig.4)

Standard multiplexed 12-digit 7-segment array: 9 shared segment lines
(`SA–SH` + `DPT`), 12 digit-select lines (`L1–L12`), plus one extra pin (21)
carrying a combined A+D+E+F segment for digit 12's special "℩" calc-mode
indicator. A "digit driver" block sits between the DSCOM chip and the
display for the digit-common lines specifically (p.9), while segment lines
run straight from the ALU chip's pins — implying asymmetric drive: low
current per segment, higher current on digit-commons (which each sink the
sum of up to 9 lit segments). Expect to need small transistor drivers (or a
driver IC) on the digit-common lines; segment lines likely just need
current-limiting resistors.

The manual does not give LED forward-voltage/current specs or
anode/cathode polarity — these must be measured on the donor unit with a
multimeter (diode-test mode) before designing the driver stage. The Pico's
PIO state machines are a good fit for generating the digit/segment
multiplex pattern in hardware, off the CPU's critical path.

---

## 3. Interfacing with the magnetic card reader (optional)

More tractable than it first appears, if the donor's card-reader
daughtercard survives.

### The `TMC0594` chip already does the analog work (manual p.11-14, Fig.5-6)

- 4-channel `LM324` read preamp: 825 KΩ feedback resistor, ~500× gain; the
  raw head signal is only 3-4 mV peak.
- TRI-state write buffers drive a ±1.5V square wave (around `-VBatt`) into
  the head through 1210Ω/33µF networks per track.
- A discrete-transistor constant-voltage circuit (`Q1` TIS93, `Q2`
  SKA3136) regulates card speed to a nominal 2.3 IPS (functional range
  2.0–2.5 IPS).
- Mechanical card-sense and card-position switches (normally closed,
  open when a card is inserted/positioned) feed digital status back.

### The reusable insight: it's already on the same digital bus

Per p.7: *"Communications between the Magnetic I/O chip and arithmetic
logic are carried on the IDLE, EXT, and IRG signal lines"* — **the same
3-wire serial bus** the printer interface uses, and that bus is documented
in full timing detail in the printer section (p.15-22): 16 state-times
(`S0`–`S15`) per ~70µs instruction cycle, two-phase clock `φ1`/`φ2` at
227.5 kHz ±1%, IRG carries 16-bit instructions LSB-first from `S3`, EXT
carries serial data LSB-first from `S3` to `S9`, IDLE's falling edge marks
state-time sync (Fig.8).

**Implication:** if the donor board's card-reader daughtercard
(594 + LM324 + head + motor) still works, there is no need to build a
magnetic-signal decoder from scratch. Keep that whole analog/mixed-signal
subsystem intact and have the Pico speak the existing IRG/EXT/IDLE protocol
to it (level-shifted into the MOS domain) — the same role the original 501
arithmetic-logic chip played. That turns "decode 3-4mV magnetic pulses"
into "emulate a documented digital protocol," a much smaller and
better-scoped problem.

Fall back to raw analog decoding (Pico ADC/PIO reading the head signal
directly, doing FM-style pulse decode in software) only if that daughtercard
itself is dead and must be replaced outright.

---

## Suggested order of attack

1. **Core-on-Pico** — software only, testable against the existing trace
   infrastructure, no hardware risk.
2. **Keyboard** — cheap, digital, exact pinout already known from the
   manual.
3. **Display** — needs a small transistor driver board; multimeter session
   on the donor unit first to pin down polarity/Vf.
4. **Card reader** (optional/stretch) — only after confirming the donor's
   594/LM324 daughtercard is alive; then it's protocol emulation against a
   documented bus rather than analog reverse-engineering.
