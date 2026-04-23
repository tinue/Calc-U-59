PROGRAM:
; A simple counter on the display, counting up
; Original comment:
;
; Simple count test
; This test simply displays counter. It assumes IDLE mode is selected. Incrementing speed is about 1185
; loops per second.
1800:   01D8    MOV     A.ALL,#0
        01DB    MOV     B.ALL,#0
1802:   0D00    ADD     A.MLSD,A,#1
        0A37    MOV     R5,#3
        1805    BRA1    -2      ;1802
        1007    BRA0    -3      ;1802

HEX:
01D8 01DB 0D00 0A37 1805 1007
