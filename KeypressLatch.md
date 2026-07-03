# Latching Keypresses While the Debugger Is Frozen

*Status: design proposal (not implemented). Based on the keypress analysis in
`rom/TI59-commented.asm` (idle loop 0x062A–0x0660, decode 0x0661–0x06B2) and
the trace `KEYPRESS_59.txt`.*

## The problem

When a debug panel (CPU Inspector or Calculator Debugger) freezes the
emulation, tapping a calculator key does nothing. The chain is:

```
KeyboardView (touch-down / touch-up)
  → EmulatorViewModel.pressKey / releaseKey
  → TI59MachineWrapper.pressMatrixKey / releaseMatrixKey
  → TMC0501::pressKey / releaseKey  →  key[digitSlot] bit set / cleared
```

`key[]` is pure matrix state — a wire level, not an event. The ROM only
notices a key by *scanning* the matrix with `KEY ... ALL` during the idle
loop. While frozen, no instructions execute, so a tap sets the bit and clears
it again with no scan in between. By the time the user clicks **Step** or
**Resume**, the press has evaporated.

## What the ROM requires (playback constraints)

From the debounce analysis (see the idle-loop header comment at 0x062A in
`rom/TI59-commented.asm`):

1. **Two agreeing samples, one display sweep apart.** A new key is first seen
   at the *arming* scan (0x0657), then re-sampled at the *confirmation* scan
   (0x065A) one full 16-digit sweep later. Only if the key is down at **both**
   scans is it accepted at 0x0661.
2. **After acceptance the matrix no longer matters.** The row/column is
   latched in KR; decode, dispatch, and execution never re-read `key[]` for
   this keypress. Releasing any time after 0x0661 is safe.
3. **Releasing too early loses the key** (the confirmation scan fails and the
   ROM discards the press as bounce).
4. **Releasing late is harmless.** A still-held key makes the loop spin in the
   release gates (0x0627–0x0633) after processing; it can never re-trigger.
   The only cost is a delayed return to the steady idle cycle.
5. Worst case from injection to acceptance is roughly three sweeps (~48
   emulated digit slots): up to ~2 sweeps for the arming scan to reach the
   key's digit line, plus one sweep to the confirmation scan.

So a latched keypress must be **played back in emulated time**: hold the
`key[]` bit from resume/step until the ROM has demonstrably accepted the key,
then release it.

## Proposed design: key latch in the core

Put the latch in `TMC0501` (it owns `key[]` and `step()`), exposed through
`TI59Machine` so every access takes `m_keyMutex` like all other public calls.

### State

```cpp
bool     m_keyLatchEnabled = false;  // set while a debugger freeze is active
bool     m_latchArmed      = false;  // a key is being played back
uint8_t  m_latchBit, m_latchSlot;    // which key[] bit is held
bool     m_latchReleasePending = false;
uint32_t m_latchSteps = 0;           // safety budget counter
```

### Behaviour

- **Freeze / unfreeze.** `TI59Machine::setKeyLatchEnabled(bool)`; the Swift
  side calls it from `freeze()` / `unfreeze()`. Disabling latch mode must
  **not** cancel an armed latch — resume is exactly when playback happens.
- **Press while enabled**: apply `pressKey` normally (bit set) and record
  `{bit, slot}`; arm the latch.
- **Release while enabled**: if it targets the armed key and the key has not
  been consumed yet, set `m_latchReleasePending` and leave the bit set.
  Otherwise release normally.
- **In `TMC0501::step()`** (one check per instruction, only when armed):

  ```cpp
  if (m_latchArmed && m_latchReleasePending &&
      (addr == keyAcceptPC() || ++m_latchSteps > kLatchBudget)) {
      key[m_latchSlot] &= ~(1u << m_latchBit);   // deferred release
      m_latchArmed = m_latchReleasePending = false;
  }
  ```

### Release criteria

- **Primary — accept-PC**: release when the CPU fetches the instruction at the
  ROM's key-accept point, the `CLR.IDLE` immediately after the confirmation
  scan: **0x0661 on TI-59/TI-58** (shared ROM). At that point the key is
  latched in KR and `key[]` is dead weight (constraint 2). This is exact for
  both **Resume** (runs through acceptance in microseconds) and **Step**
  (the user single-steps through arming → confirmation → accept and watches
  the whole mechanism — the original goal of this feature).
- **TI-58C**: different ROM set, address unknown. Determine it the same way
  0x0661 was found on the TI-59: capture a keypress trace on the 58C and find
  the `CLR.IDLE` following the second (confirmation) `KEY ... ALL`. Implement
  `keyAcceptPC()` as a variant-aware member next to `libExecFetchPC()` in
  `TMC0501.hpp`, which already encodes per-variant ROM addresses the same way.
- **Fallback — step budget**: if the accept PC is never reached (frozen inside
  keycode processing, inside a running program, or in the release-gate spin),
  force the release after `kLatchBudget` steps (e.g. 4096 ≈ 250 sweeps —
  generous; correctness only needs "past acceptance", and a late release is
  harmless per constraint 4).

### Why not simpler alternatives

- **Duration-only playback** (hold N steps, then release): variant-independent
  and nearly as good, but N must straddle "long enough to be accepted from any
  freeze point" and there is no single safe N when the freeze lands mid-keycode
  processing — the ROM may not scan the keyboard for thousands of steps. The
  accept-PC criterion survives that case for free; the budget is then only a
  safety valve instead of the primary mechanism.
- **UI-side deferral** (Swift queues the release and re-applies it after a
  wall-clock delay on resume): couples playback to real time instead of
  emulated time, and breaks completely under single-stepping.

### Edge cases

- **Freeze point on the idle-entry path (0x0627–0x0635).** The ROM sees the
  latched key first at a *release gate* and treats it as "previous key still
  held": it spins until the budget releases the key, and the press is
  swallowed. This mirrors real hardware (a key already down while the ROM
  passes the gates is ignored until released). Rare enough to accept;
  a future refinement could replay as release → one empty sweep → press.
- **Key pressed while frozen mid-program (RUN mode).** Running programs poll
  the keyboard elsewhere (e.g. R/S detection), so the accept PC never fires;
  the budget applies. Holding through the budget is enough for the R/S poll to
  see it in most cases, but this feature explicitly targets idle-loop
  keypresses first.
- **Multiple taps while frozen.** Latch the first key and ignore further
  presses while armed (the hardware rejects multi-key chords anyway — see the
  `kmask & (kmask - 1)` check in the KEY handler). Once a latch is consumed,
  the slot frees up, so when single-stepping the user can feed keys one at a
  time (e.g. `2nd` then `Deg`).

## Implementation checklist

1. `Core/TMC0501.hpp/.cpp`: latch state, `keyAcceptPC()` (0x0661 for
   TI59/TI58; 58C TODO), hook in `step()`, latch-aware `pressKey`/`releaseKey`.
2. `Core/TI59Machine.hpp/.cpp`: `setKeyLatchEnabled(bool)` under `m_keyMutex`.
3. `Bridge/TI59MachineWrapper.h/.mm`: `- (void)setKeyLatchEnabled:(BOOL)`.
4. `App/EmulatorViewModel.swift`: call it from `freeze()` / `unfreeze()`
   (both freeze owners); optional UI badge "key latched" while armed.
5. TI-58C: capture a keypress trace, fill in the accept address.
6. Verify: freeze in idle → tap "6" → Step repeatedly and watch arming
   (0x0657), confirmation (0x065A), accept (0x0661), dispatch (0x0047), INC
   slide (0x0166); then the same with Resume instead of Step.
