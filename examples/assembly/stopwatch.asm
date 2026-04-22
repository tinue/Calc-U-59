; Load the program and start
; Press R/S once to start the stopwatch.
; Press R/S again to stop
; Press CLR to reset
;
; Original comment:
;
Stopwatch
; This example is more complex. It uses WAIT Dn instruction to make timing more precise (without
; counting instructions). Increment cycle repeats 222 times per second (455kHz÷2÷16÷16), increment
; value should be 4.5010989ms. Attention should be payed to DPT digit, which is hexadecimal (no BCD
; correction). Also R5 register should be always set to correct value to display seconds and milliseconds
; correctly after ALU instruction.

;initialization
1800:   01D8    MOV     A.ALL,#0
        01DB    MOV     B.ALL,#0
;display mask to correctly display last digit
        07DB    MOV     B.EXP,#-1       ;#99
        01DE    MOV     D.ALL,#0
;4.50ms step value
        0A47    MOV     R5,#4
        02F6    MOV     D.DPT,R5
        0176    SHL     D.ALL,D
        0A57    MOV     R5,#5
        02F6    MOV     D.DPT,R5
        0176    SHL     D.ALL,D
;stopwatch is not running here
;wait for key press
;R5 contains DPT (decimal point) position
180A:   0A57    MOV     R5,#5
        0A30    WAIT    D3
;test CLR key
        087F    KEY     7F
        1804    BRA1    +2              ;180F
;clear counter
        01D8    MOV     A.ALL,#0
;test R/S key
180F:   0AA0    WAIT    D10
        08FD    KEY     FD
        180F    BRA1    -7              ;180A
;stopwatch is running here
;wait for R/S key released
1812:   01B0    ADD     A.ALL,A,D
        0A57    MOV     R5,#5
        1002    BRA0    +1              ;1815
1815:   0AA0    WAIT    D10
        08FD    KEY     FD
        100B    BRA0    -5              ;1812
;stopwatch is still running here
;wait for R/S key pressed
1818:   01B0    ADD     A.ALL,A,D
        0A57    MOV     R5,#5
        1002    BRA0    +1              ;181B
181B:   0AA0    WAIT    D10
        08FD    KEY     FD
        180B    BRA1    -5              ;1818
;stopwatch is not running here anymore
;wait for R/S key released
181E:   0AA0    WAIT    D10
        08FD    KEY     FD
        1005    BRA0    -2              ;181E
        182F    BRA1    -23             ;180A