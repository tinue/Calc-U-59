# Card Recovery

*Status: idea / feasibility analysis, not implemented. Goal: build a
standalone, Raspberry Pi Pico–based reader that reuses a donor TI-59's
magnetic-card transport (head, motor, pinch roller, pressure pad,
card-sense switches) to image cards more reliably than the original 1970s
electronics, without routing anything through the TI-59's own logic board.
Captured data is stored/transmitted from the Pico to a host PC for
decoding — it never needs to reach the TI-59's ROM at all.*

Source for the hardware facts below: *TI Programmable 58/59 Service Manual*
(local copy: `~/SynologyDrive/Dokumente/PDF/Vintage/TI/manuals/TI 59-service-manual.pdf`),
and `rom/TI59-commented.asm` in this repository (the actual disassembled,
trace-verified TI-59 ROM). See also [`ideas/Pico.md`](Pico.md) for the
broader Pico-interfacing context this grew out of.

---

## 1. The documented signal chain

**Analog front end (manual p.11-14, Fig.5).** Each of the 4 tracks has its
own `LM324` op-amp channel: ~500× gain (825KΩ feedback resistor), AC-coupled
to the head through a 1210Ω/33µF series network shared with the tri-state
write driver on the same node. Head output is tiny — 3-4mV peak, alternating
polarity, one pulse per flux transition (inherent to any inductive read
head: output ∝ dΦ/dt). The manual states explicitly that "the frequency of
the pulses/square wave varies depending upon the particular program" (p.11)
— a self-clocking scheme where transition *spacing*, not polarity or count,
carries the data.

**Digitization (`TMC0594`, Fig.5).** The amplified signal (LM324 output pins
1, 7, 8, 14 — labeled `READ1`–`READ4`) feeds directly into the `TMC0594`
magnetic-I/O chip, which "conditions the signals... to make them compatible
with MOS logic levels" (p.7). No separate comparator IC appears in the
schematic, so pulse-slicing happens inside that chip.

## 2. What the ROM disassembly reveals — and what it doesn't

`rom/TI59-commented.asm`, card-read routine around `0x16BB`–`0x17F1`, shows
a clean repeating pattern, e.g. at `0x16CC`–`0x16DB`:

```
16CC: CRD.RD
16CD: CRD.IN            ; IN CRD — pulls one already-formed nibble off EXT
16CE: MOV KR,EXT[4..15]
16D0: MOV R5,KR[4..7]   ; extract the 4-bit nibble
16D2: A=A+D DPT         ; decimal-add it into an accumulator (1-digit field)
...
16D4: CRD.IN            ; next nibble
...
16DA: A=A+B DPT         ; accumulate again
16DB: JNC 16DC
16DC: A=A-1 EXP1        ; decrement a byte/nibble counter
16DD: JC 16D3           ; loop
```

Two conclusions follow:

1. **The ROM never sees a raw pulse or a timing measurement.** Every
   `IN CRD` returns a complete, already-decoded 4-bit BCD nibble over the
   `EXT` bus. All flux-transition timing recovery happens **inside the
   TMC0594 silicon**, invisible to software and therefore invisible to us
   via disassembly. It's a black box.
2. **The checksum is a simple decimal digit-sum** — nibbles are decimally
   added into an accumulator (`A=A+D DPT` / `A=A+B DPT`, using the ALU's
   1-digit `DPT` field width purely as a "1 nibble wide" selector) as they
   stream in. Around `0x17AA`, a mismatch sets `fB[4]`, which feeds the
   error/printer path from `0x17C1`. There's no visible redundancy or
   error-correcting structure — one bad nibble anywhere in a bank fails the
   whole bank's checksum, with zero recovery margin built into the format.
   This matches the symptom (partial reads, all-or-nothing checksum
   failure) exactly.

## 3. What's still unknown, and what the ferrofluid image adds

The exact self-clocking encoding scheme (bit-cell length, FM/single-frequency
doubling vs. F2F/Aiken-biphase vs. something TI-proprietary) lives entirely
inside the `TMC0594` and isn't recoverable from ROM disassembly. Given the
era (mid-1970s) and the manual's "frequency varies with data" description,
an F2F/biphase-style scheme (à la ISO magstripe tracks) is a reasonable
working hypothesis, not a confirmed fact.

The ferrofluid-developed card photo is genuinely useful evidence here — it's
the first look at the *actual recorded pattern* rather than an inference
from documentation:

- The image shows roughly 7-8 distinct horizontal band-like regions with
  vertical tick marks (individual flux transitions). Since the hardware
  documents exactly 4 tracks (Fig.5: `TRACK1`–`TRACK4`, 4 independent R/W
  channels), the most likely reading is **4 tracks × 2 visible sub-lines
  each** — ferrofluid/magnetic-viewer images commonly show both edges of a
  recorded domain boundary as separate fine lines, not 8 independent
  tracks. Treat this as an inference, not a pixel-measured fact.
- Adjacent bands alternate between **densely, regularly ticked** regions
  and **sparser, irregularly spaced** regions. The most likely explanation
  is not "clock track vs. data track" (the hardware has no such split — all
  4 channels are symmetric data tracks) but rather that this *is* the
  self-clocking encoding directly: a run of repetitive content (headers,
  sync fields, or program data that happens to repeat) produces a highly
  regular transition pattern, while general program data produces the
  irregular spacing visible elsewhere. This is consistent with — though not
  proof of — the frequency-varies-with-data description in the manual.
- There's a heavily stained, blotchy dark region in the upper-left of the
  card, concentrated near the start of the tracks. This looks like
  localized oxide damage, contamination, or accumulated debris rather than
  recorded data, and is a plausible independent cause of read failures on
  *this specific card* regardless of what reader is used.
- **Worth checking specifically for the azimuth question:** pick a moment
  in time during writing (a vertical line at some horizontal position on
  the card) and check whether the flux transitions across all 4 tracks line
  up in a straight vertical line, or are diagonally offset from track to
  track. A consistent diagonal offset is the direct visual signature of a
  head that was tilted (non-zero azimuth) relative to the track direction
  at write time — worth a careful pixel-level cross-track alignment check
  on a high-resolution version of the image, which a casual visual read
  can't fully confirm.

Two independent, additive problems are therefore in play: **azimuth
mismatch** between the head that originally wrote most of your cards and
the head in your current donor unit, and **motor speed variance** (audible,
per your report) during reads. Both degrade signal quality/timing in ways a
fixed 1970s comparator threshold and fixed-rate assumption can't compensate
for — which is exactly the opening for a Pico-based rebuild.

## 4. Design implication: read-only, standalone, bypass the TI-59 electronics entirely

Since the goal is imaging cards to a host PC — not feeding data back into
the TI-59's ROM — there's no need to interface with the `TMC0594`, the
MOS-domain voltage rails (`Vdd`/`Vgg`), or any calculator logic at all. The
only parts worth keeping from the donor unit are the **mechanical/electrical
transport**: magnetic head (`A1`), drive roller/motor (`B1`), pinch roller,
pressure pad, and the card-sense/card-position switches (Fig.6 — simple
mechanical NC switches, no silicon). Everything downstream of the head is
new, breadboard-built electronics under the Pico's control. This also
sidesteps a real risk: the *original* 40-year-old LM324/passives may
themselves have drifted and be contributing to the marginal reads — a fresh
build removes that variable rather than trying to characterize it.

---

## 5. Breadboard circuit design

### 5.1 Block diagram

```
                     ┌─────────────────────────────────────────┐
   Magnetic head     │   Per-track preamp (×4, on breadboard)   │
   (donor A1, 4      │   AC-couple → gain stage 1 → gain stage 2│
   tracks) ──────────┤   → AC-couple → bias to Vref             │
                      └─────────────┬─────────────────────────┘
                                    │  4 analog channels, ~0-3.3V,
                                    │  biased around Vref (~1.65V)
                                    ▼
                     ┌─────────────────────────────────────────┐
                     │  External 4/8-ch 12-bit ADC (SPI)         │
                     │  e.g. MCP3208                             │
                     └─────────────┬─────────────────────────┘
                                    │ SPI
                                    ▼
                     ┌─────────────────────────────────────────┐
                     │  Raspberry Pi Pico / Pico 2                │
                     │  - reads all 4 channels each pass          │
                     │  - PLL-style clock recovery                │
                     │  - adaptive threshold per track             │
                     │  - checksum-guided multi-pass reconstruction│
                     │  - drives motor on/off via MOSFET            │
                     │  - reads card-sense switches (GPIO+pull-up) │
                     └─────────────┬─────────────────────────┘
                                    │ USB CDC (serial)
                                    ▼
                              Host PC (decode, storage, tooling)

   Motor power:  adjustable buck module → Pico-switched N-MOSFET → donor motor (B1)
   Card sense:   donor NC switches → Pico GPIO (internal pull-up)
```

Write capability is intentionally out of scope — this is a read/imaging
rig, so the `TMC0594`'s TRI-state write buffers and the original ±1.5V
square-wave write drive aren't needed at all.

### 5.2 Per-track preamp (×4 identical channels)

Reuse the classic topology from the service manual, but on fresh,
modern-manufactured parts and a conventional positive supply — the
`LM324` is still in production today and was originally designed for
single-supply operation, so there's no need to reproduce the calculator's
`Vss`/`Vdd`/`Vgg` negative-rail domain at all.

```
 Head track (2 wires, one per track, common return to head ground)
   │
   ├── C1 (2.2-10 µF, non-polarized/film) ── AC-couples out any DC bias
   │
   │         ┌── R2 (fixed) ──┐
   │         │                │
   Vbias ─ R1 ─┤+  op-amp A ├── out1 ── C2 ── Vbias ─ R3 ─┤+  op-amp B ├── out2 (to ADC ch. N)
              │-              │                          │-           │
              └──── R2 ────────┘ (gain stage 1,           └──── R4 ─────┘ (gain stage 2,
                                   gain ≈ 1+R2/R1 ≈ 20-30×)              gain ≈ 1+R4/R3 ≈ 20×)

 Vbias = Vcc/2, generated once by an R-R divider (e.g. 10K/10K from
         Vcc to GND) + 10 µF decoupling cap, shared across all 4 channels.
```

- **Op-amp:** one quad package per instrument (`LM324`, `TL074`, or
  `MCP6004` all work) powered from a single 3.3V or 5V rail relative to
  Pico ground. Using 5V for the analog stage gives more headroom, then a
  final resistor divider (or the ADC's own reference) brings the signal
  into range.
- **Total gain:** ~500-1000× across both stages — comparable to or
  exceeding the original circuit's ~500×, which gives useful margin for
  weak signal from worn cards or a still-imperfect azimuth.
- **AC-coupling twice** (`C1` at the input, `C2` between stages) keeps any
  DC drift/offset from railing the second stage — the same principle the
  original circuit uses (its 33µF caps "decouple common mode voltage
  caused by the DC bias supplied to the magnetic heads," p.11).
- **Anti-alias filter:** a simple single-pole RC (a few kΩ + a few nF) after
  the second stage, cutoff set comfortably above the expected transition
  frequency (unknown precisely until the encoding is characterized, but
  card speed is only ~2.3 IPS, so this is a low-frequency signal — start
  around 10-20 kHz cutoff and adjust after capturing real data).
- Build 4 of these (one quad-op-amp IC covers all 4 tracks, 2 sections
  per channel).

### 5.3 ADC

The Pico's own onboard ADC only exposes 3 external channels (`GPIO26-28`)
and they share a single physical SAR converter anyway — no true
simultaneous sampling either way. Cleaner to use an external SPI ADC:

- **`MCP3208`** (8-channel, 12-bit, SPI) — cheap, breadboard-friendly,
  well-documented, leaves 4 channels spare for later (e.g. a tachometer
  signal, see below). `MCP3204` (4-channel) is the minimal equivalent.
- Wire `SCK`/`MOSI`/`MISO`/`CS` to any 4 Pico GPIOs, `Vref`/`Vdd` to the
  Pico's 3.3V rail so ADC codes map directly to 0-3.3V.
- Round-robin all 4 channels every capture cycle. Given card speed is
  slow and the signal bandwidth is low (§5.2), the achievable channel rate
  from even a modest SPI clock is enormous overkill relative to what's
  needed — no risk of missing transitions from multiplexing overhead.

### 5.4 Motor drive

Simpler than the original: no need to reproduce the 1970s constant-voltage
transistor regulator (manual p.13, `Q1`/`Q2`/`R2`/`R4`), because the plan
is to compensate for residual speed variation in software (§5.6), not
eliminate it mechanically.

```
 5-12V supply ── adjustable buck module (e.g. LM2596-based) ── set to
     approx. the donor motor's rated voltage ── N-channel MOSFET
     (gate driven by a Pico GPIO through a series resistor, source to
     GND, drain to motor -) ── donor motor (B1)
```

- Trim the buck module's output while watching captured waveform quality
  live on the host PC — treat "motor voltage" as a tunable parameter, same
  as the original's `R2` trim pot (p.13: adjusted "until the X in Texas on
  the card is split by the left edge of the calculator case").
- A flyback diode across the motor is standard practice with any brushed
  DC motor driven by a MOSFET switch.
- Optional but valuable: add a simple photo-interrupter or magnetic
  tachometer on the drive roller/pinch roller shaft, feeding a spare ADC
  channel or a GPIO interrupt. This gives the Pico a direct, independent
  measurement of instantaneous card speed — useful both as a diagnostic
  (confirms and quantifies the audible speed wobble) and as an optional
  input to the clock-recovery algorithm (§5.6), rather than relying purely
  on inferring speed from the transition pattern itself.

### 5.5 Card-sense switches

The donor's card-sense and card-position switches (manual Fig.6 — both
normally-closed mechanical switches) wire directly to two Pico GPIOs with
internal pull-ups enabled, exactly like a push-button: switch to GND,
GPIO reads high when open (card present/positioned) and low when closed.
No level-shifting needed — these are pure mechanical contacts, same as the
keyboard matrix discussed in `ideas/Pico.md`.

### 5.6 Software: what "modern methods" concretely means here

- **PLL-style / data-separator clock recovery**, not a fixed nominal bit
  rate. Standard technique from floppy/tape data separators: track the
  actual observed transition spacing continuously and adapt the expected
  bit-cell window, rather than assuming constant 2.3 IPS. This directly
  addresses the audible motor speed variance — as long as the wobble is
  slow relative to the bit rate (very likely, given it's mechanically
  driven low-frequency wobble, not per-transition jitter), a software PLL
  tracks it without needing the mechanical transport to be perfect.
- **Adaptive, per-track amplitude thresholding** instead of a fixed
  hardware comparator level — likely the single biggest win against a
  weakened/uneven signal from head wear, tape wear, or the azimuth
  mismatch, all of which reduce peak amplitude and blur transition edges
  rather than eliminating them outright.
- **Azimuth correction is partly mechanical, not purely a software
  problem.** If the cross-track skew check in §3 confirms an azimuth
  mismatch, the most effective fix is adjusting the physical head angle
  (an azimuth screw, if the mechanism has one, or a shim) while watching
  live captured waveform amplitude/edge sharpness on the host PC — the
  same "align by ear/scope" procedure used in tape-deck restoration.
  Software can compensate for some residual smear, but a genuinely
  misaligned head reduces the fundamental information content of what's
  captured; no amount of downstream processing recovers information that
  never made it into the amplified signal.
- **Multi-pass, checksum-guided reconstruction.** Because the TI-59's
  checksum (§2) is only a single decimal digit-sum with no built-in
  redundancy, a bad nibble anywhere fails the whole bank on real hardware
  with no way to know *which* nibble was wrong. With raw waveforms
  captured on the Pico, this weakness becomes exploitable: read the same
  card several passes, flag nibbles with low-confidence analog features
  (marginal amplitude, ambiguous timing) rather than accepting the
  hardware's binary decision, and try local corrections against the
  checksum across the small set of marginal nibbles. This can recover
  banks that would fail outright on stock hardware, at the cost of being
  probabilistic rather than certain — worth flagging to the user when a
  reconstructed bank relied on checksum-guided correction rather than a
  clean, unambiguous read.
- **Log raw waveforms, not just decoded bits**, at least during
  development. Until the actual self-clocking scheme is empirically
  confirmed (§3), having full raw capture (ideally from a card with known,
  simple, repetitive content written specifically as a calibration
  reference) is what makes reverse-engineering the encoding tractable in
  the first place.

### 5.7 Rough bill of materials

| Part | Qty | Notes |
|---|---|---|
| Raspberry Pi Pico / Pico 2 | 1 | brain + USB link to host |
| Quad op-amp (`LM324`/`TL074`/`MCP6004`) | 1 | new part, not the donor's aged chip |
| `MCP3208` (or `MCP3204`) SPI ADC | 1 | true multi-channel capture |
| N-channel MOSFET (logic-level) | 1 | motor switch |
| Flyback diode | 1 | across motor |
| Adjustable buck regulator module | 1 | motor supply |
| Resistors/capacitors for preamp stages | ~20-30 | values per §5.2, tune empirically |
| Donor transport: head, motor, pinch roller, pressure pad, card-sense switches | 1 set | salvaged from the broken TI-59 |
| Breadboard + jumper wires | — | |
| Optional: photo-interrupter/tachometer | 1 | speed diagnostics + optional PLL input |

---

## Suggested order of attack

1. Salvage and mechanically verify the transport (motor spins, pinch
   roller grips, pressure pad seats correctly) independent of any
   electronics.
2. Build one preamp channel first, feed it into an oscilloscope or the
   Pico's ADC with simple logging, and pull a known/simple test card
   through by hand (not motorized yet) to sanity-check signal shape and
   amplitude against the manual's numbers (3-4mV at the head × ~500-1000×
   gain).
3. Add the motor drive and card-sense switches; get a full automated pass
   capturing raw waveforms for all 4 tracks.
4. Do the azimuth cross-track alignment check (§3) on captured data (not
   just the photo) and, if confirmed, do a physical azimuth adjustment
   pass using live waveform quality as feedback.
5. Only then invest in the software decode pipeline (§5.6) — there's
   limited point tuning clock recovery and adaptive thresholds against a
   transport that still has a known, fixable mechanical problem.
