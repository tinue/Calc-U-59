# Open Questions

## 1. Where are 2nd and INV latches stored?

The 2nd and INV sticky key states are not stored in SCOM (verified by tracing).
They must be latched, because the are pressed individually, i.e. first 2nd, then the additional key (as opposed to "Shift" on a PC keyboard)

**Observations:**
- KR register shows bit activity (bit 5 for 2nd, bit 9 for INV) but KR is actively managed by ROM code for program redirection, so it's not a simple hardware latch
- SCOM remains unchanged when pressing these keys

## 2. After pressing "2nd Eng", where is this state stored?

Pressing 2nd followed by Eng (engineering notation) activates a specific mode, but the ROM state that tracks this combined operation is not in SCOM.

**Observations:**
- SCOM does not change when this sequence is executed
- Yet the state is remembered, until it is switched off
