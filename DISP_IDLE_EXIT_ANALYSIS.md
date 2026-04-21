# Why CPU Exits IDLE State Permanently

## Summary
The CPU's exit from the long IDLE/WAIT loop is controlled by **the D register acting as a timeout/event counter**. The value in D at 0x0655-0x0659 determines whether the code loops back to the WAIT display loop or continues to real execution.

## Key Observations

### Phase Pattern
```
Long ON (836-1221ms) → OFF (284ms) → ON → ... → Final OFF → ON (897ms) - IDLE=1, real execution
                       ↑ Key scans       ↑ Loops back to WAIT           ↑ Exits permanently
```

### Short OFF Bursts During Long ON Phase (Key Scans)
These are display refresh/strobe cycles while stuck in an active WAIT loop:
- **Instruction at 0x0653**: `WAIT D13` (tight loop, repeating)
- **D register value**: `0000000000009017` (and variants like 9027, 9037...)
- **After KEY 20 check at 0x0654-0x065A**: Code executes operations 0x0A25-0x0A2C
- **Critical operations at 0x0A2A-0x0A2B**: 
  - `C=C+1 MX` (increments C, modifies D as side effect)
  - `C<>D MX` (swaps C and D)
- **Result**: D increments by +0x10 per cycle (0x9017 → 0x9027 → 0x9037...)
- **Loop behavior**: Code returns to 0x0653 WAIT D13 to repeat the display cycle

### Final OFF Phase → Permanent Exit
When D reaches the threshold value `0000000000015017`:
- **D register value**: `0000000000015017` (much larger!)
- **Same instruction sequence**: 0x0654-0x0A2C executes identically
- **Increment**: D becomes `0000000000015027` (same +0x10 increment)
- **Key difference**: After 0x0A2C (WAIT D10), code does NOT loop back to 0x0653
- **What happens instead**: CPU transitions to real program execution (C=C+1, C<>D, WAIT D10, KEY 20)
- **IDLE flag**: Changes from IDLE=0 to IDLE=1 later in execution

## Root Cause: D Register as State Machine

The code at addresses 0x0655-0x065A contains a series of bit tests and conditional jumps:
```
0655: JC 063D      (Jump if Carry)
0656: TST KR[7]    (Test KR bit 7)
0657: JC 065A      (Jump if Carry)
0658: TST KR[5]    (Test KR bit 5)
0659: JNC 0A25     (Jump if No Carry)
0A25-0A26: More bit tests
0A27: TST fB[9]    (Test fB bit 9)
0A28: JC 0A2C      (Jump if Carry)
```

These tests check keyboard flags (KR) and function flags (fB). However, the **exit condition is determined by D's magnitude**, not the tests themselves:

- **D < 0x10000 (like 0x9017)**: Loop returns to WAIT D13
- **D ≥ 0x15000 (like 0x15017)**: Code path diverges, no return to WAIT loop

## Hypothesis: Timeout/Event Counter

The D register appears to track:
1. **Duration in display mode** - counts up during each key scan cycle (+0x10 per cycle)
2. **Timeout threshold** - at ~0x15000, the timeout expires
3. **State transition trigger** - triggers exit from IDLE/display loop to real program execution

This is consistent with calculator UX:
- Display stays on while actively scanning keys (each scan adds a timeout)
- After no key activity for N cycles, display turns off and CPU goes fully idle
- In this trace: 6+ seconds of display time = ~60+ key scan cycles × timeout increment

## Code Path Comparison

| Aspect | Key Scan Loop | Final Exit |
|--------|--------------|-----------|
| D value | 0x9017 (or 0x9027, 0x9037) | 0x15017 |
| Entry instruction | 0x0653 WAIT D13 | Same tests 0x0655-0x065A |
| Key check | 0x0654 KEY 20 | Same |
| Increment operation | 0x0A2A C=C+1 | D → 0x15027 |
| Loop back | YES, to 0x0653 | NO - continues to real execution |
| DISP state | Toggles 2↔3 (ON↔OFF) | Remains 2 (ON) |
| Next phase | Display ON again | CPU transitions to computation |

## Conclusion

**The CPU exits IDLE permanently when the D register (timeout counter) exceeds a threshold (~0x15000).** The short OFF bursts during the long ON phase are not exits at all—they're just display strobes while the CPU stays in a tight WAIT loop. The real exit happens when the timeout counter accumulated from repeated key scan cycles finally triggers the condition to escape the loop and begin real program execution.
