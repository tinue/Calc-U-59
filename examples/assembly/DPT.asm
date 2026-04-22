; This doesn't work great on the emulator, because its simulated LED is too fast. On the
; real hardware, the LEDs have a bit of afterglow, and it looks as if all decimal dots
; are on at the same time.
; To test, first fill the display with numbers, e.g. "-88888888-88", the load and start.
; You'll see the decimal point jumping around.
; Original comment:
;
; DPT test
; This example is little bit tricky. It changes R5 for every digit displayed so DPTs are displayed for every
; digit position.
;
1800:   0AF0    WAIT    D15
        0AD7    MOV     R5,#13
        0AC7    MOV     R5,#12
        0AB7    MOV     R5,#11
        0AA7    MOV     R5,#10
        0A97    MOV     R5,#9
        0A87    MOV     R5,#8
        0A77    MOV     R5,#7
        0A67    MOV     R5,#6
        0A57    MOV     R5,#5
        0A47    MOV     R5,#4
        0A37    MOV     R5,#3
        0A27    MOV     R5,#2
        181B    BRA1    -13     ;1800