PROGRAM:
; This program *doesn't work* on the emulator. The emulator takes shortcuts when synchronizing
; WAIT and KEY, and the bad timing that this program uses does not trigger.
;
; If you are interested in details:
;
; The program calls WAIT D12 (opcode 0x0AC0) instead of the canonical WAIT D1 before SET IDLE.
; This shifts the IDLE loop 11 digit positions out of phase with the display strobe cycle.
;
; On real hardware the display is multiplexed in real time: at each digit time Dn, the SCOM chip
; asserts the LED strobe for digit n while the CPU must simultaneously drive the segment data for
; that position. When SET IDLE is phase-shifted, CPU data and strobe get misaligned — the B
; register's DPT nibble (which the 7-segment decoder maps to a hex glyph 0x0–0xF) ends up driving
; an LED position it normally never would. That exposes all 16 hex segment combinations, which is
; exactly the test's goal.

; The emulator's display on the other hand is a phase-independent snapshot taken at digit == 0
; This copies the whole A/B register arrays unconditionally at digit 0. The phase shift from WAIT D12
; has zero influence on which index lands in which slot. The display always shows expected content;
; the DPT-as-digit trick is invisible.
;
; The same is true for keyboard scans. Phase shifted, keys are detected wrongly, or do not even exist.
; Since the ROM often dispatches key presses via the scan code using the PREG mechanism, the handler for
; inexistent keys is just some arbitrary ROM location, and can have any effect.
;
; The emulator again does not phase shift, and reads the keys correctly.
;
; Without some significant rework, the emulator cannot handle this particular ROM program. So far
; it's unknown if other tricks discovered in the 80ies do not work due to the shortcut taken by
; the emulator. It's possible that this needs to be changed in the future.

; Original comment follows:
;
; 7-segment decoder test
; This test is also little bit tricky. It uses "bad" digit synchronization to display DPT on LED. As DPT is
; hexadecimal, this allows to display all combinations available in 7-segment decoder. Value displayed is
; BB.AAX, where BB is value in B.DPT, AA is value in A.DPT and X is resulting 7-segment digit.
; Because of illegal synchronization, some keys behave strange! (RCL makes CPU reset, LRN row
; doesn't work, BST row doesn't detect key press but increment is done until keys are held – this can be
; useful to test higher values...)
; Note: B.DPT can't be used to increment using mask value because B is on the same ALU input as
; mask constant, so B (or D) is or-ed with this constant instead of adding it.

1800:   0A01    CLR     IDL
        01D0    MOV     A.ALL,#0
;prepare digit mask to B register: 99990
        01D3    MOV     B.ALL,#0
        07DB    MOV     B.EXP,#-1
        0153    SHL     B.ALL,B
        0153    SHL     B.ALL,B
        07DB    MOV     B.EXP,#-1
        01D4    MOV     C.ALL,#0
;set IDLE but shifted so DPT is visible
        0AC0    WAIT    D12
        0A09    SET     IDL
;main loop
; wait for key press
180A:   0AE0    WAIT    D14
        0820    KEY     20
        180C    BRA1    +6 ;1812
        0A45    TST     KR[4]
        0A55    TST     KR[5]
        0A65    TST     KR[6]
        0A75    TST     KR[7]
        100F    BRA0    -7            ;180A
;check key press = debounce key
1812:   0AE0    WAIT    D14
        0820    KEY     20
        1805    BRA1    -2            ;1812
;increment A.DPT
        0300    ADD     A.DPT,A,#1
        1806    BRA1    +3            ;1819
;increment C.DPT if carry
        0324    ADD     C.DPT,C,#1
;and copy C.DPT to B.DPT
        0223    ADD     B.DPT,C,#0
;copy A.DPT to display the number
1819:   01D6    MOV     D.ALL,#0
        0206    ADD     D.DPT,A,#0
        0176    SHL     D.ALL,D
        0630    ADD     A.EXP,#0,D
;copy C.DPT to display the number
        01D6    MOV     D.ALL,#0
        0226    ADD     D.DPT,C,#0
        0176    SHL     D.ALL,D
        0176    SHL     D.ALL,D
        0176    SHL     D.ALL,D
        0930    ADD     A.MANT,#0,D
;clear COND
        1002    BRA0    +1              ;1824
;set DPT position
1824:   0A37    MOV     R5,#3
        1837    BRA1    -27             ;180A

HEX:
0A01 01D0 01D3 07DB 0153 0153 07DB 01D4
0AC0 0A09 0AE0 0820 180C 0A45 0A55 0A65
0A75 100F 0AE0 0820 1805 0300 1806 0324
0223 01D6 0206 0176 0630 01D6 0226 0176
0176 0176 0930 1002 0A37 1837
