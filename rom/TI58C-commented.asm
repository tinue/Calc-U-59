; ══════════════════════════════════════════════════════════════════════════
; TI-58C ROM Disassembly — annotated
; ROM chips CD2400 (0x0000–0x09FF), CD2401 (0x0A00–0x13FF), TMC0573 (0x1400–0x17FF).
; Comments on code shared with the TI-59 are carried over from rom/TI59-commented.asm
; (addresses rewritten to TI-58C addresses); "; Δ" headers mark code that differs
; from the TI-59 and say how. Named jump targets: rom/TI58C-labels.asm.
; Narrative and the TI-59 comparison: rom/TI58C-ROM-Guide.md.
; 6144 × 13-bit words  |  addresses 0x0000–0x17FF
; ══════════════════════════════════════════════════════════════════════════

; ── CD2400   0x0000–0x09FF  2,560 words  (ROM chip 1) ────────────────────

; ═══════════════════════════════════════════════════════════════════════════
; RESET / POWER-ON ENTRY  (0x0000)
; Cold-start vector, run at every power-on. The constant memory (RAM) keeps
; its contents over a power cycle; the CPU registers, flags and SCOM do not.
; Brings the chip out of display-idle, clears the flag registers, zeroes all
; sixteen SCOM rows (F…0), then hands off to the main power-on setup at 0x0350,
; which rebuilds SCOM from the constant memory.
; ═══════════════════════════════════════════════════════════════════════════
0000: 0A01  CLR.IDLE          ; leave display-idle: CPU drives the bus instead of the multiplexer
0001: 0A0A  CLR fB
0002: 00B9  SET fB[11]        ; program-register cache (SCOM[10]) invalid: the first fetch reads RAM (08AE)
0003: 03DC  C=-1 DPT1         ; C := F in the digit-pointer slot → loop counter / first SCOM row to clear
0004: 01D8  A=0 ALL           ; A = 0 is the value written into each cleared row
0005: 0A48  CRD.OFF           ; card-reader motor off — kept from the TI-59 code; the TI-58C has
                              ;   no card reader, so it has no effect
0006: 1002  JNC 0007 ; clear COND
; SCOM status-row clear loop: STOF stores the I/O bus into the SCOM register
; whose number is on the bus. IO=C selects the row, IO=A(=0) supplies the data,
; so each pass zeroes one row; C counts F→0 to wipe all the status rows.
0007: 0121  IO=C ALL          ; put counter C on the bus = select SCOM row to clear
0008: 0A0F  STOF              ; latch that row as the store target
0009: 0101  IO=A ALL          ; A(=0) on the bus → deferred store writes 0 into the row
000A: 032C  C=C-1 DPT1        ; next row
000B: 1809  JC 0007           ; repeat until C borrows past 0
000C: 0A02  CLR fA
000D: 01D7  A<>E ALL          ; A↔E (both 0 here) — also leaves E cleared
000E: 1E84  JC 0350           ; → main power-on setup (unconditional here: COND=1 after the loop)
000F: 0A77  MOV R5,#7         ; "SUM" stub (from slot 0044): op code 7, falls in
0010: 0085  SET KR[8]         ; KEY_RET: handler return vector (SR = 0x0100, see
                              ;   06A3); tags KR[8], falls into 0011 → KEY_OP_ENTRY
; ═══════════════════════════════════════════════════════════════════════════
; KEYBOARD DISPATCH TABLE  (0x0011–0x0059)
; Landing zone of the keyboard computed jump at 0x06A9 (see the decode block
; at 0x065A): after a debounced keypress the CPU branches to 0x0<col><row> —
; the key's matrix position IS the ROM address (column 1–5 in the second
; nibble, row 1–9 in the low nibble; the same two digits, reversed, as the
; LRN keycode row·10+col). Each slot holds the first instruction of that
; key's handler, usually a JC. Digit keys are the exception: their slots jump
; into the INC KR slide at 0x015F at a depth equal to the digit value (see
; there), which is how a row/column position becomes the 00–09 keycode:
;     col 2          col 3          col 4
;   0026 "7"→0161  0036 "8"→0160  0046 "9"→015F   (row 6)
;   0027 "4"→0164  0037 "5"→0163  0047 "6"→0162   (row 7)
;   0028 "1"→0167  0038 "2"→0166  0048 "3"→0165   (row 8)
;   0029 "0"→0168  (zero INCs)                    (row 9)
; Keyboard row 1 (A–E) is dispatched at 0x02CA instead and never lands here;
; the printer's PRINT/ADV buttons are remapped onto the Prt/Adv slots 0x0099/0x0089.
; Trace-checked on the TI-58C (headless harness) for key "6" (row 7, col 4 →
; 0x0047 → 0162) and for keys "0" (slot 0029) and "+" (slot 0058).
; 2nd-shifted keys land in a mirror table at 0x0062–0x00A9: same scheme with
; column+5 (fA[9], toggled by KEY_2ND, biases the column decode). Trace-
; checked for "P/R" (2nd x⇄t, matrix 32 → slot 0073) and "Ins" (2nd SST,
; matrix 41 → slot 0064).
; Slot targets are annotated with labels below; the label table (all named
; jump targets, with confidence tags) lives in rom/TI58C-labels.asm. Key slots
; exist at x1–x9 only; the x0/xA–xF gaps between them hold helper stubs,
; mostly funnels that load an op/function code into R5 before entering
; KEY_OP_ENTRY (0141, pending two-operand/memory ops) or FN_ENTRY (0209,
; unary functions).
; ═══════════════════════════════════════════════════════════════════════════
0011: 1A60  JC 0141           ; col1·row1 "A" — unreachable (row 1 → KEY_USERDEF
                              ;   02CA); doubles as KEY_RET's fall-through → KEY_OP_ENTRY
0012: 1CA0  JC 0262           ; "2nd"  → KEY_2ND
0013: 1FE2  JC 0404           ; "LRN"  → KEY_LRN
0014: 1FDA  JC 0401           ; "SST"  → KEY_SST
0015: 1FF8  JC 0411           ; "BST"  → KEY_BST
0016: 1D1C  JC 02A4           ; "GTO"  → KEY_GTO
0017: 1FB6  JC 03F2           ; "SBR"  → KEY_SBR
0018: 1CE6  JC 028B           ; "RST" → KEY_RST (028B; the run-abort entry is one word earlier,
                              ;   0289)
0019: 1FEE  JC 0410           ; "R/S"  → KEY_RS
; ── 001A–0020: helper stubs in the non-slot gap (no keyboard rows A–F / 0) ──
001A: 0AB7  MOV R5,#11        ; "STO" stub (from slot 0024): op code 11 …
001B: 1820  JC 002B           ; … → 002B (tag KR[9]) → KEY_OP_ENTRY
001C: 0AC7  MOV R5,#12        ; "RCL" stub (from slot 0034): op code 12 …
001D: 181B  JC 0010           ; … → KEY_RET (tag KR[8]) → KEY_OP_ENTRY
001E: 0A07  MOV R5,#0         ; stub (from 0094): op code 0 …
001F: 1818  JC 002B           ; … → 002B (tag KR[9]) → KEY_OP_ENTRY
0020: 0A77  MOV R5,#7         ; "x²" stub (from slot 0033): fn code 7 …
0021: 1BD0  JC 0209           ; … → FN_ENTRY  (0021 = col2·row1 "B" slot, unreachable)
0022: 1C7C  JC 0260           ; "INV"  → KEY_INV
0023: 1CA2  JC 0274           ; "x⇄t"  → KEY_XT
0024: 1815  JC 001A           ; "STO"  → stub 001A (op code 11)
0025: 19D6  JC 0110           ; "EE"   → KEY_EE
0026: 1A76  JC 0161           ; "7"    → DIGIT_SLIDE (7 INCs)
0027: 1A7A  JC 0164           ; "4"    → DIGIT_SLIDE (4 INCs)
0028: 1A7E  JC 0167           ; "1"    → DIGIT_SLIDE (1 INC)
0029: 1A7E  JC 0168           ; "0"    → DIGIT_SLIDE (0 INCs) — trace-confirmed
; ── 002A–0030: helper stubs in the non-slot gap ──
002A: 0A57  MOV R5,#5         ; stub (from 0084): op code 5, falls in
002B: 0095  SET KR[9]         ; shared tail: tag KR[9] …
002C: 1A2A  JC 0141           ; … → KEY_OP_ENTRY
002D: 0AA7  MOV R5,#10        ; "1/x" stub (from slot 0053): fn code 10 …
002E: 1BB6  JC 0209           ; … → FN_ENTRY
002F: 0A0C  MOV KR,EXT[4..15] ; stub: KR := 0, fn code 12 …
0030: 0AC7  MOV R5,#12
0031: 1BB0  JC 0209           ; … → FN_ENTRY  (0031 = col3·row1 "C" slot, unreachable)
0032: 1BA4  JC 0204           ; "lnx"  → KEY_LNX (fn code 2)
0033: 1827  JC 0020           ; "x²"   → stub 0020 (fn code 7)
0034: 1831  JC 001C           ; "RCL"  → stub 001C (op code 12)
0035: 19F0  JC 012D           ; "("    → KEY_LPAREN
0036: 1A54  JC 0160           ; "8"    → DIGIT_SLIDE (8 INCs)
0037: 1A58  JC 0163           ; "5"    → DIGIT_SLIDE (5 INCs)
0038: 1A5C  JC 0166           ; "2"    → DIGIT_SLIDE (2 INCs)
0039: 1D74  JC 02F3           ; "."    → KEY_DPT
; SUM step (slot 00DA): A := register value, B := X; fB[8] = INV (saved at
; 022E) → subtract. Then ADD.
003A: 0CD2  A<>B MAEX
003B: 0213  B=B DPT
003C: 0007  MOV fA[1..4],R5
003D: 0088  TST fB[8]         ; INV SUM?
003E: 1DEA  JC 0333           ; no → ADD (register + X)
003F: 15EC  JNC 0335          ; yes → subtract (register − X)
0040: 00B1  SET fA[11]
0041: 18E0  JC 00B1           ; col4·row1 "D" slot — unreachable (row 1 → 02CA)
0042: 1EFE  JC 03C1           ; "CE"   → KEY_CE
0043: 181A  JC 0050           ; "√x"   → stub 0050 (fn code 0)
0044: 186B  JC 000F           ; "SUM"  → stub 000F (op code 7 → KEY_RET → KEY_OP_ENTRY)
0045: 1836  JC 0060           ; ")"    → stub 0060 (op code 2 → KEY_RET → KEY_OP_ENTRY)
0046: 1A32  JC 015F           ; "9"    → DIGIT_SLIDE (9 INCs)
0047: 1A36  JC 0162           ; "6"    → DIGIT_SLIDE (6 INCs) — trace-confirmed
0048: 1A3A  JC 0165           ; "3"    → DIGIT_SLIDE (3 INCs)
0049: 00F0  TST fA[15]        ; "+/-" handler (inline in its slot): exponent entry active?
004A: 1476  JNC 0285          ; yes → toggle the exponent sign (0285)
004B: 0023  TOG fA[2]         ; mantissa sign …
004C: 002B  TOG fB[2]         ; … and its saved copy
004D: 0058  TST fB[5]         ; result on display (not an entry)?
004E: 150E  JNC 02D5          ; yes → redisplay via 02D5
004F: 1D9E  JC 031E           ; entry → rebuild the entry display (031E)
0050: 0A07  MOV R5,#0         ; "√x" stub (from slot 0043): fn code 0 …
0051: 1B6E  JC 0208           ; … → FN_ENTRY_KR8  (0051 = col5·row1 "E" slot, unreachable)
0052: 1EAA  JC 03A7           ; "CLR"  → KEY_CLR
0053: 184D  JC 002D           ; "1/x"  → stub 002D (fn code 10)
0054: 19D0  JC 013C           ; "y^x"  → KEY_YX (op code 10)
0055: 0011  SET fA[1]         ; "÷"    — tag fA[1] (INV pair bit), fall into "×"
0056: 19C8  JC 013A           ; "×"    → KEY_MUL (op code 6)
0057: 0011  SET fA[1]         ; "−"    — tag fA[1] (INV pair bit), fall into "+"
0058: 1890  JC 00A0           ; "+"    → 00A0 (op code 2) → KEY_ARITH — trace-confirmed
0059: 0A97  MOV R5,#9         ; "="    — op code 9 …
005A: 185F  JC 002B           ; … → 002B (tag KR[9]) → KEY_OP_ENTRY
005B: 0111  IO=B ALL
005C: 0A0F  STOF
005D: 0121  IO=C ALL
005E: 01D5  C<>D ALL
005F: 1BA0  JC 022F
0060: 0A27  MOV R5,#2         ; ")" stub (from slot 0045): op code 2 …
0061: 18A3  JC 0010           ; … → KEY_RET (tag KR[8]) → KEY_OP_ENTRY
0062: 1C02  JC 0263           ; 2nd slot: (2nd 2nd) (keycode 26)
0063: 1F2C  JC 03F9           ; 2nd slot: Pgm (keycode 36)
0064: 1C12  JC 026D           ; 2nd slot: "Ins" (2nd SST) — trace-confirmed; op
                              ;   dispatch continues via KEY_OP_ENTRY chain → OP_INS 0B11
0065: 1C0E  JC 026C           ; 2nd slot: Del (keycode 56)
0066: 1C34  JC 0280           ; 2nd slot: Pause (keycode 66)
0067: 1F2A  JC 03FC           ; 2nd slot: Lbl (keycode 76)
0068: 180C  JC 006E           ; 2nd slot: St flg (keycode 86)
0069: 1B8C  JC 022F           ; 2nd slot: Write (keycode 96) — Δ [HW] no card reader: Write only
                              ;   finishes number entry and redisplays (022F); TI-59 0069 → 045F
                              ;   card sequence
006A: 0A47  MOV R5,#4         ; Fix stub (from slot 0085): code 4 …
006B: 18B7  JC 0010           ; … KR[8] bank → slot 00D4
; "=" (from slot 00EA): incoming precedence 0, so the reduce loop pops every
; entry, and 01FD repeats it for each paren level still open.
006C: 09DB  B=0 MANT          ; incoming precedence 0
006D: 19B4  JC 0147           ; → AOS reduce (0147)
006E: 0AD7  MOV R5,#13        ; St flg stub (from slot 0068): code 13 → slot 00CD
006F: 19A4  JC 0141
0070: 0AE7  MOV R5,#14        ; x=t stub (from slot 0076): code 14 …
0071: 1A14  JC 017B           ; … bank 0x00B0 → slot 00BE
0072: 1BDE  JC 0261           ; 2nd slot: (2nd INV) (keycode 27)
0073: 1FBC  JC 0451           ; 2nd slot: "P/R" (2nd x⇄t) → KEY_PR — trace-confirmed
0074: 1C14  JC 027E           ; 2nd slot: CMs (keycode 47)
0075: 1C02  JC 0276           ; 2nd slot: Eng (keycode 57)
0076: 180D  JC 0070           ; 2nd slot: x=t (keycode 67)
0077: 1A06  JC 017A           ; 2nd slot: x≥t (keycode 77)
0078: 1BE4  JC 026A           ; 2nd slot: If flg (keycode 87)
0079: 0A37  MOV R5,#3         ; Dsz (2nd slot 0079, inline): code 3 …
007A: 1C56  JC 02A5           ; … KR[9]+KR[8] → slot 00F3
; "×"/"÷" push (from slot 00C7)
007B: 0A47  MOV R5,#4         ; precedence 4
007C: 1A28  JC 0190           ; → AOS_PUSH
; |x| (slot 00D1): clear the mantissa sign.
007D: 0022  CLR fA[2]
007E: 002A  CLR fB[2]
007F: 1B60  JC 022F
0080: 0AE7  MOV R5,#14        ; Int stub (from slot 0095): fn 14 …
0081: 1B0E  JC 0208           ; … FN_ENTRY_KR8 → slot 051E
0082: 1832  JC 009B           ; 2nd slot: log (keycode 28)
0083: 185C  JC 00B1           ; 2nd slot: sin (keycode 38)
0084: 18B5  JC 002A           ; 2nd slot: Exc (keycode 48)
0085: 1837  JC 006A           ; 2nd slot: Fix (keycode 58)
0086: 1BBA  JC 0263           ; 2nd slot: Nop (keycode 68)
0087: 1FB2  JC 0460           ; 2nd slot: Σ+ (keycode 78)
0088: 19CC  JC 016E           ; 2nd slot: D.MS (keycode 88)
; KEY_ADV: 2nd-table slot of Adv (2nd .), shared with the printer's ADV button
; (remapped here at 0678–0687) → paper advance (0483).
0089: 1FF4  JC 0483           ; 2nd slot: Adv (keycode 98)
008A: 0A07  MOV R5,#0         ; |x| stub (from slot 00A5): code 0 …
008B: 18F7  JC 0010           ; … KR[8] bank → slot 00D0
; Prd step (slot 00E3): same for multiply; INV Prd divides.
008C: 0CD2  A<>B MAEX
008D: 0213  B=B DPT
008E: 0007  MOV fA[1..4],R5
008F: 0088  TST fB[8]         ; INV Prd?
0090: 1E88  JC 03D4           ; no → MULDIV multiply
0091: 168A  JNC 03D6          ; yes → divide
0092: 1FF6  JC 048D           ; 2nd slot: CP (keycode 29)
0093: 183A  JC 00B0           ; 2nd slot: cos (keycode 39)
0094: 18ED  JC 001E           ; 2nd slot: Prd (keycode 49)
0095: 182B  JC 0080           ; 2nd slot: Int (keycode 59)
0096: 1BE2  JC 0287           ; 2nd slot: Op (keycode 69)
0097: 19CE  JC 017E           ; 2nd slot: x̄ (keycode 79)
0098: 1F60  JC 0448           ; 2nd slot: π (keycode 89)
; KEY_PRT: 2nd-table slot of Prt (2nd +/-), shared with the printer's PRINT
; button (remapped at 0678–0687): print X (fA[10] path, PRT_VALUE 152B).
0099: 00A1  SET fA[10]        ; print the value through the trace-record machinery
009A: 1B2A  JC 022F           ; → NUM_NORM / DISP_FORMAT, which prints at 05A8
009B: 0AB7  MOV R5,#11
009C: 0080  TST fA[8]
009D: 1AD6  JC 0208
009E: 0A87  MOV R5,#8
009F: 1AD2  JC 0208
00A0: 0A27  MOV R5,#2         ; "+"/"−" stub (from slot 0058): op code 2 …
00A1: 193E  JC 0140           ; … → KEY_ARITH — trace-confirmed ("+")
00A2: 1E0A  JC 03A7           ; 2nd slot: 2nd CLR (keycode 20) — same as CLR (trace-checked)
00A3: 18C7  JC 0040           ; 2nd slot: tan (keycode 30)
00A4: 1EA6  JC 03F7           ; 2nd slot: Ind (keycode 40)
00A5: 1837  JC 008A           ; 2nd slot: |x| (keycode 50)
00A6: 1C02  JC 02A7           ; 2nd slot: Deg (keycode 60)
00A7: 1FEC  JC 049D           ; 2nd slot: Rad (keycode 70)
00A8: 1FEE  JC 049F           ; 2nd slot: Grad (keycode 80)
; List (2nd =, slot 00A9): only with a printer (KEY [P] at digit 10); fB[10] =
; listing (borrowed, as in LRN, so the step fetch builds the LRN display),
; fn 7 in the KR[8]+KR[9] bank → slots 0537 (flush a pending trace line) and
; 0538 (091E → 0D12 → LIST loop).
; Δ [HW] TI-59 00A9: printer-present is sensed on KP at digit 10 (WAIT D11 +
; KEY [P]) instead of digit 0 (WAIT D1): the TI-58C board wires the printer's
; detect line to another digit-scan line. Same change at 0483 (Adv).
00A9: 0AB0  WAIT D11          ; printer present? (the next instruction samples digit 10)
00AA: 08FB  KEY [P]
00AB: 1B08  JC 022F           ; no → nothing
00AC: 00A9  SET fB[10]        ; listing: steps are fetched as in LRN
00AD: 0051  SET fA[5]
00AE: 0A77  MOV R5,#7
00AF: 1E8C  JC 03F5
; Trig keys (2nd-table slots for sin/cos/tan land here; cos enters at 00B0,
; tan arrives with fA[11] set): fA[12] = cos. INV → arc functions, fn 0
; (slot 0500); otherwise fn 3 in the KR[9] bank → slot 0523.
00B0: 00C1  SET fA[12]        ; cos
; ═══════════════════════════════════════════════════════════════════════════
; OPERATION SEQUENCE TABLE  (0x00B1–0x010F) — threaded "macro" code
; Trace-confirmed (headless harness, tools/headless/coverage.py).
; KEY_OP_ENTRY (0141) builds KR = 0x0C00 | tag | code<<4 and jumps through
; PREG to slot 0x00C0 + code (+0x10 if KR[8] was set by KEY_RET 0010, +0x20 if
; KR[9] was set by 002B). Entering at 0142 skips KR[10] (−0x40): 017B uses
; that for bank 0x00B0 (KR[11]+KR[9]+KR[8]: If flg 00B6, x≥t 00BA, x=t 00BE). A slot holds one JC to a subroutine; the routine
; returns to the NEXT slot because NORM_CALL (0442) and the AOS reduce loop
; park KR+1 in SR, and routines end with SET KR[1] + SWAP KR,SR (02D1/02CA).
; An operation is therefore a run of consecutive slots, and a sequence that
; needs keyboard arguments (STO nn, SUM nn, …) parks its resume slot in SR and
; returns to the idle loop (04C8 → 0228 sets fB[12]).
; Most runs begin with "JC 0442" = finish number entry, normalize X.
; Arithmetic slots come in pairs at 0x00C0 + 2·precedence:
;   00C2/C3 push "+ −" (prec 2)    00C4/C5 execute ADD (0333), continue
;   00C6/C7 push "× ÷" (prec 4)    00C8/C9 execute MULDIV (03D4), continue
;   00CA/CB push "y^x" (prec 6)    00CC     execute y^x (fn 12 via 002F)
; The operation each remaining run belongs to (from the scenarios that reach
; it) is noted on its first slot.
; ═══════════════════════════════════════════════════════════════════════════
00B1: 0080  TST fA[8]         ; INV?
00B2: 0A07  MOV R5,#0
00B3: 12AC  JNC 0209          ; yes → arc function (slot 0500)
00B4: 0A37  MOV R5,#3         ; sin/cos/tan: fn 3 …
00B5: 1FB4  JC 048F           ; … + KR[9] → slot 0523
00B6: 1F18  JC 0442           ; If flg (program): normalize …
00B7: 1A6C  JC 01ED           ; … collect the flag digit (ARG_ONE_DIGIT 01ED)
00B8: 1FEE  JC 04AF           ; … test the flag (0894 → 0C68): fA[9] := flag set …
00B9: 1FB8  JC 0495           ; … conditional transfer (COND_TRANSFER)
00BA: 1F10  JC 0442           ; x≥t: normalize …
00BB: 1FF0  JC 04B3           ; … B := t (SCOM[11]) …
00BC: 1AA6  JC 020F           ; … x − t ≥ 0? → fA[9]
00BD: 1FB0  JC 0495           ; … conditional transfer
00BE: 1F08  JC 0442           ; x=t: normalize …
00BF: 1FE8  JC 04B3           ; … B := t (SCOM[11]) …
00C0: 1AA2  JC 0211           ; … x − t = 0? → fA[9]
00C1: 1FA8  JC 0495           ; … conditional transfer
00C2: 1F00  JC 0442           ; "+"/"−" push: normalize X …
00C3: 1934  JC 015D           ; … then AOS_PUSH with precedence 2
00C4: 1CDE  JC 0333           ; AOS reduce of a prec-2 entry: ADD (fA[1] = subtract)
00C5: 1E9C  JC 0413           ; … continue the reduce loop
00C6: 1EF8  JC 0442           ; "×"/"÷" push: normalize X …
00C7: 1899  JC 007B           ; … then AOS_PUSH with precedence 4
00C8: 1E18  JC 03D4           ; AOS reduce of a prec-4 entry: MULDIV (fA[1] = divide)
00C9: 1E94  JC 0413           ; … continue the reduce loop
00CA: 1EF0  JC 0442           ; "y^x" push: normalize X …
00CB: 1988  JC 018F           ; … then AOS_PUSH with precedence 6
00CC: 193B  JC 002F           ; AOS reduce of a prec-6 entry: fn 12 = y^x (fA[1] = INV y^x, the
                              ;   root)
00CD: 1EEA  JC 0442           ; St flg / INV St flg: normalize …
00CE: 1A3E  JC 01ED           ; … collect the flag digit
00CF: 1FC2  JC 04B0           ; … set / clear it (0B14 → 11E1 → FLAG_OP 15B7)
00D0: 1EE4  JC 0442           ; |x|: normalize …
00D1: 18A9  JC 007D           ; … clear the sign
00D2: 1EE0  JC 0442           ; ")": normalize X …
00D3: 18E6  JC 0146           ; … then AOS reduce with precedence 1: close one paren level
00D4: 1EDC  JC 0442           ; Fix n: normalize …
00D5: 1A2A  JC 01EA           ; … collect the digit (01EA → ARG_ONE_DIGIT)
00D6: 1F26  JC 0469           ; … set Fix
00D7: 1ED6  JC 0442           ; SUM nn (also used by Σ+): normalize …
00D8: 1FE0  JC 04C8           ; … collect the register number
00D9: 1BE8  JC 02CD           ; … read the register (B := X)
00DA: 1941  JC 003A           ; … register ± X
00DB: 1FF6  JC 04D6           ; … store back
00DC: 1ECC  JC 0442           ; RCL nn: normalize …
00DD: 1FD6  JC 04C8           ; … collect the register number
00DE: 0051  SET fA[5]         ; … result to display
00DF: 1BE4  JC 02D1           ; … read the register into X
00E0: 1EC4  JC 0442           ; Prd nn: normalize …
00E1: 1FCE  JC 04C8           ; … collect the register number
00E2: 1BD6  JC 02CD           ; … read the register (B := X)
00E3: 18AF  JC 008C           ; … register × / ÷ X
00E4: 1FE4  JC 04D6           ; … store back
00E5: 1EBA  JC 0442           ; Exc nn: normalize …
00E6: 1FC4  JC 04C8           ; … collect the register number
00E7: 1BCC  JC 02CD           ; … read the register (B := X)
00E8: 1FD2  JC 04D1           ; … X := register, register := old X
00E9: 1EB2  JC 0442           ; "=": normalize X …
00EA: 18FD  JC 006C           ; … then AOS reduce with precedence 0: close everything
00EB: 1EAE  JC 0442           ; STO nn: normalize …
00EC: 1FB8  JC 04C8           ; … collect the register number
00ED: 1F80  JC 04AD           ; … write X into the register
00EE: 1EA8  JC 0442           ; x⇄t (also inside P→R, Σ+, x̄): normalize …
00EF: 1F86  JC 04B2           ; … swap X and t (SCOM[11])
00F0: 1EA4  JC 0442           ; GTO nnn / GTO label (keyboard): normalize …
00F1: 1A5A  JC 021E           ; … collect the address (label or 3 digits)
00F2: 1F68  JC 04A6           ; … transfer (STEP_TO_REG)
00F3: 1E9E  JC 0442           ; Dsz: normalize …
00F4: 19F2  JC 01ED           ; … collect the register digit 0–9 …
00F5: 1BB0  JC 02CD           ; … read the register …
00F6: 1F62  JC 04A7           ; … decrement its magnitude (06F5) …
00F7: 1E08  JC 03FB           ; … write it back (076B → 0A24) …
00F8: 1A28  JC 020C           ; … zero? → fA[9] (inverted: Dsz branches while non-zero) …
00F9: 1F38  JC 0495           ; … conditional transfer
00FA: 1E90  JC 0442           ; HIR nm (keycode 82, programs only): normalize …
00FB: 1F9A  JC 04C8           ; … operand nm: n = operation, m = hierarchy register 1–8
                              ;   (SCOM[m])
00FC: 1FC8  JC 04E0           ; … recall / combine: n = 1 RCL, 3 SUM, 4 Prd, 5 INV SUM, 6 INV
                              ;   Prd (0CBC)
00FD: 1987  JC 003A           ; … SUM / INV SUM: ADD
00FE: 1FC6  JC 04E1           ; … store the result back (0CBD → HIR_STO) …
00FF: 18E7  JC 008C           ; … Prd / INV Prd: MULDIV
0100: 1FC2  JC 04E1           ; … store back
; ── Sequence bank 0x0100 (entered through 020A with only KR[12] set):
; 0101 Op (0287), 0108 EE on a result (0112), 010A Eng (0276), 010C D.MS
; (0170), 010E Pause from the keyboard (0282). 0104–0107 continue the Op
; sequence for Op 20–39 (from 0CAD): read the register, ±1, write it back
; (trace-checked: 5 STO 03, Op 23 → R03 = 6).
0101: 1E82  JC 0442           ; Op nn: normalize …
0102: 1F8C  JC 04C8           ; … collect the 2-digit Op number
0103: 1FF0  JC 04FB           ; … dispatch on nn (04FB → 08D5 OP_DISPATCH)
0104: 1B92  JC 02CD           ; Op 2x/3x: read the register …
0105: 1C8C  JC 034B
0106: 1DEA  JC 03FB           ; … write it back (076B)
0107: 1A1C  JC 0215           ; … and finish
0108: 1F46  JC 04AB           ; EE on a result: flush trace, normalize …
0109: 1814  JC 0113           ; … then KEY_EE's result branch (sci format / INV EE)
010A: 1F42  JC 04AB           ; Eng
010B: 1B3C  JC 02A9           ; … Eng / INV Eng display flags (02A9)
010C: 1E6C  JC 0442           ; D.MS: normalize …
010D: 18C8  JC 0171           ; … launch the D.MS keycode program (0171)
010E: 1F3A  JC 04AB           ; Pause from the keyboard: flush trace …
010F: 1AE8  JC 0283           ; … and just redisplay
; ═══════════════════════════════════════════════════════════════════════════
; KEY_EE: "EE" handler (slot 0025) — trace-confirmed (1 2 EE 3, 12.34 EE 5).
; Switches the display to scientific format (fB[15]) and, during number entry,
; opens exponent entry (fA[15]): following digits go to the exponent (0303 →
; 02D3). Only possible while the mantissa leaves room for the two exponent
; digits (011B–0128); otherwise the key is ignored. INV EE leaves scientific
; format (0487). With a result on display (fB[5]) EE only reformats (0277).
; ═══════════════════════════════════════════════════════════════════════════
0110: 0A87  MOV R5,#8         ; R5 := 8 (for the result case at 0277)
0111: 0058  TST fB[5]         ; result on display?
0112: 12CA  JNC 0277          ; yes → reformat the result in scientific notation
0113: 0080  TST fA[8]         ; INV EE?
0114: 0052  CLR fA[5]
0115: 16E4  JNC 0487          ; yes → leave scientific format (0487)
0116: 0058  TST fB[5]
0117: 1806  JC 011A
0118: 005A  CLR fB[5]
0119: 0049  SET fB[4]
011A: 00F9  SET fB[15]        ; scientific display format on
; 011B: shared with the prefix keys (0269): does the entry leave room for the
; exponent? Digits after the point must be < 9 and the mantissa < 10^8.
011B: 0A97  MOV R5,#9
011C: 02F3  B=R5 DPT
011D: 0289  IO=A-B DPT        ; digits after the point − 9
011E: 1C00  JC 031E           ; too many → just redisplay
011F: 02D2  A<>B DPT          ; B[0] := count, A[0] := 0 for the loop
0120: 0ED3  B=LOAD MMSD1      ; marker 1 in nibble 15 …
0121: 095B  B=SRB MANT        ; … slid right while A[0] counts up to 12 …
0122: 0300  A=A+1 DPT1
0123: 0409  IO=A-xC DPTC
0124: 1007  JNC 0121
0125: 02D2  A<>B DPT
0126: 095B  B=SRB MANT        ; … marker now at the 10^8 position (nibble 11)
0127: 0989  IO=A-B MANT       ; mantissa ≥ marker?
0128: 1BEC  JC 031E           ; yes → no room, just redisplay
0129: 00A8  TST fB[10]        ; reached from a prefix key (fB[10] borrowed, see 0266)?
012A: 1356  JNC 02D5          ; yes → redisplay only
012B: 00F1  SET fA[15]        ; EE key: exponent entry on
012C: 1B52  JC 02D5
; KEY_LPAREN: "(" handler (slot 0035). Opens a paren level: SCOM[13] nibble 1
; (current paren level) += 1. A tenth unclosed level carries into nibble 2 and
; sets the error flag (0138). fB[6] is cleared, so an operator directly after
; "(" is rejected just like an operator after an operator.
012D: 0AD7  MOV R5,#13        ; B[0] := 13 …
012E: 02F3  B=R5 DPT
012F: 01D5  C<>D ALL
0130: 0111  IO=B ALL          ; … IO-bus nibble 0 selects the SCOM row for RCLF
0131: 0A1F  RCLF              ; recall SCOM[13] (AOS status) …
0132: 01D4  C=LOAD ALL        ; … into C
0133: 006A  CLR fB[6]         ; no fresh operand
0134: 0724  C=C+1 EXP1        ; paren level (nibble 1) += 1
0135: 0663  B=SLC EXP         ; B[2] := new level (zero only if it wrapped 9 → 0)
0136: 0619  IO=-B EXP         ; level 1–9? (0 − B[EXP] borrows when non-zero)
0137: 11B9  JNC 005B          ; yes → 005B: store C back into SCOM[13]
0138: 0099  SET fB[9]         ; tenth level: ERROR
0139: 19B7  JC 005E
; KEY_MUL: "×"/"÷" stub (slots 0056/0055; "÷" arrives with fA[1] set):
; op code 6 → KEY_ARITH
013A: 0A67  MOV R5,#6
013B: 180A  JC 0140
; KEY_YX: "y^x" stub (slot 0054): op code 10 → KEY_ARITH
; (fA[8] set → tag fA[1] first, the inverse-pair variant, 013D–013F)
013C: 0AA7  MOV R5,#10
013D: 0080  TST fA[8]
013E: 1804  JC 0140
013F: 0011  SET fA[1]
; KEY_ARITH: common tail of the arithmetic operators — op code in R5
; (+ − = 2 via 00A0, × ÷ = 6 via 013A, y^x = 10 via 013C; the second key of
; each pair arrives with fA[1] set). Sets fA[9], falls into KEY_OP_ENTRY.
; Trace-checked for "+" (0058 → 00A0 → 0140, TI-58C headless).
0140: 0091  SET fA[9]
; KEY_OP_ENTRY: common pending-op/prefix recorder — operation code in R5,
; variants tagged via fA[1]/KR[8]/KR[9]. Funnel target of + − = STO RCL SUM ")"
; and of KEY_RET (0010); see the dispatch-table annotations at 0011.
0141: 00A5  SET KR[10]
0142: 00B5  SET KR[11]
0143: 0A18  MOV KR[4..7],R5   ; op/fn code into the PREG address
0144: 0015  SET KR[1] ; PREG  ; arm PREG: after one delay-slot instruction, fetch continues at
                              ;   KR[15..4] — for FN_ENTRY the fn table at 0x0500+fn
                              ;   (trace-checked: 1/x → 0x050A)
0145: 0100  A=A ALL           ; delay slot — still executes before the target
; ═══════════════════════════════════════════════════════════════════════════
; AOS ENGINE  (0x0146–0x0203) — the algebraic operating system. Trace-
; confirmed with 5+7×3=, (5+(7×2)×3)= and 5+= (headless harness).
; State lives in three SCOM rows:
;   SCOM[1..8]  one pending left operand per level (level n in SCOM[n]); its
;               nibble 0 holds fA[1..4] at push time: bit 0 = inverse-pair bit
;               (− ÷ INV y^x), bit 1 = mantissa sign, bit 2 = exponent sign.
;   SCOM[12]    operator stack, two nibbles per entry, top entry in nibbles
;               1/0: high = precedence (+− 2, ×÷ 4, y^x 6), low = the paren
;               level the entry was pushed at.
;   SCOM[13]    nibble 1 = current paren level, nibble 2 = depth (max 8).
; Working registers: B is the control word — B[3] = incoming precedence,
; B[1..2] = paren level/depth copied from SCOM[13]; C = X while the loop
; runs; E keeps the control word while a popped operation executes.
; Entries: 0146 ")" (precedence 1), 0147 "=" (precedence 0 already in B[3]),
; 0190 AOS_PUSH (operator precedence in R5).
; ═══════════════════════════════════════════════════════════════════════════
0146: 0DD3  B=LOAD MLSD1      ; ")": incoming precedence 1 in B[3]
0147: 0300  A=A+1 DPT1        ; A[0] 0xC → 0xD (NUM_NORM left 0xC there): select SCOM[13]
0148: 0101  IO=A ALL
0149: 0A1F  RCLF
014A: 06D3  B=LOAD EXP        ; B[1..2] := paren level, depth
014B: 0060  TST fA[6]         ; fresh operand since the last push? (COND := 0 if so)
014C: 0658  A=SRB EXP         ; A[1] := depth
014D: 0709  IO=A-1 EXP1       ; depth − 1: borrows (COND := 0) when nothing is pending
014E: 1092  JNC 0197          ; operand present, or stack empty → reduce
014F: 0099  SET fB[9]         ; operator directly followed by ")"/"=" (5 + =): ERROR …
0150: 070B  B=A-1 EXP1        ; … and drop the dangling entry: depth − 1 …
0151: 0121  IO=C ALL          ; … (C[0] = 0xC → SCOM[12])
0152: 0A1F  RCLF
0153: 01D0  A=LOAD ALL        ; … pop the operator stack by one entry …
0154: 0148  A=SRA ALL
0155: 02F3  B=R5 DPT
0156: 0148  A=SRA ALL
0157: 0121  IO=C ALL          ; … store it back …
0158: 0A0F  STOF
0159: 0101  IO=A ALL
015A: 0153  B=SLB ALL
015B: 095B  B=SRB MANT
015C: 1876  JC 0197           ; … then reduce what is left
; "+"/"−" push (from slot 00C3)
015D: 0A27  MOV R5,#2         ; precedence 2
015E: 1864  JC 0190           ; → AOS_PUSH
; ── DIGIT_SLIDE: digit-key value slide (0x015F–0x0168) ──────────────────────
; Keyboard digit keys have no row/col-shaped keycode; their dispatch-table
; slots (see 0x0011) jump into this run of INC KR instructions with KR
; already zeroed (by 0x06AA). The entry depth equals the digit: "9" enters at
; 015F (nine INCs), "6" at 0162 (six), "0" at 0168 (none) — trace-checked on
; the TI-58C. On exit KR[4..7] holds the digit value — identical to the low
; digit of the 00–09 program keycode — and 016A hands it to the number-entry
; path, which reads it at 0x0301 via MOV R5,KR[4..7].
; Δ [REORG] TI-59 015F–0162: the AOS reduce-loop continuation that precedes
; the slide on the TI-59 moved to 0413; the slide itself sits four words lower
; (TI-59 0163–016C). Same behaviour.
015F: 0A04  INC KR
0160: 0A04  INC KR            ; "8" enters here (8 INCs)
0161: 0A04  INC KR
0162: 0A04  INC KR
0163: 0A04  INC KR
0164: 0A04  INC KR
0165: 0A04  INC KR
0166: 0A04  INC KR
0167: 0A04  INC KR
0168: 0008  TST fB[0]
0169: 00D8  TST fB[13]
016A: 1B18  JC 02F6           ; → number entry with the digit in KR[4..7]
; DIGIT_SLIDE exit for a running program (fB[0]/fB[13]): a keycode at a
; digit key's matrix position is not a digit (digits are stored as 00–09) but
; one of the compact codes — dispatch on the digit through bank 0x0B20 + d.
016B: 0A08  MOV R5,KR[4..7]   ; d = the digit of that key position …
016C: 0095  SET KR[9]         ; … → slot 0x0B20 + d
016D: 1A08  JC 0271
; D.MS key (2nd slot 0088 → 016E): fn 12 bank → sequence slots 010C/010D →
; 0171: entry step 303 (D.MS) or, with INV, 341 (027A) of the keycode ROM.
016E: 00A0  TST fA[10]
016F: 0AC7  MOV R5,#12
0170: 1A0E  JC 0277
0171: 005A  CLR fB[5]         ; (slot 010D) D.MS launch:
0172: 0052  CLR fA[5]
0173: 0080  TST fA[8]         ; INV?
0174: 120C  JNC 027A          ; yes → entry 341
0175: 0A37  MOV R5,#3         ; entry step 303: digits 3, 0, 3 …
0176: 01F3  B=R5 ALL
0177: 0153  B=SLB ALL
0178: 0A37  MOV R5,#3
0179: 1DC0  JC 0459
017A: 0AA7  MOV R5,#10        ; x≥t (from slot 0077): code 10, falls into …
017B: 0095  SET KR[9]         ; bank 0x00B0: KR[11]+KR[9]+KR[8], entering KEY_OP_ENTRY at 0142
017C: 0085  SET KR[8]
017D: 1877  JC 0142           ; (skips KR[10]) → slot 0x00B0 + code
; x̄ key (2nd slot 0097 → 017E): clear SCOM[14] (return levels 4–6) for the
; sub-program, entry step 067 (x̄) or with INV 107 (σ).
017E: 02DB  B=0 DPT
017F: 0AE7  MOV R5,#14        ; SCOM[14] := 0 …
0180: 02F6  D=R5 DPT
0181: 0131  IO=D ALL
0182: 0A1F  RCLF
0183: 0CD3  B=LOAD MAEX
0184: 0131  IO=D ALL
0185: 0A0F  STOF
0186: 0111  IO=B ALL
0187: 0A77  MOV R5,#7
0188: 01F3  B=R5 ALL
0189: 0080  TST fA[8]         ; INV?
018A: 15B8  JNC 0466          ; yes → entry 107
018B: 0A67  MOV R5,#6         ; entry 067
018C: 06F3  B=R5 EXP
018D: 0153  B=SLB ALL
018E: 1D98  JC 045A
; "y^x" push (from slot 00CB); falls into AOS_PUSH
018F: 0A67  MOV R5,#6         ; precedence 6
; AOS_PUSH: operator with precedence R5 arrives, X normalized in A.
0190: 09F3  B=R5 MANT         ; AOS_PUSH: B[3] := incoming precedence
0191: 0060  TST fA[6]         ; fresh operand since the last push?
0192: 1E72  JC 04CB           ; no (5 + × …) → error
0193: 0300  A=A+1 DPT1        ; A[0] := 0xD → SCOM[13]
0194: 0101  IO=A ALL
0195: 0A1F  RCLF
0196: 06D3  B=LOAD EXP        ; B[1..2] := paren level, depth
; Reduce loop: while the top entry belongs to the current paren level and its
; precedence ≥ the incoming one, pop and execute it.
0197: 0658  A=SRB EXP         ; A[1] := depth
0198: 0709  IO=A-1 EXP1       ; stack empty?
0199: 1058  JNC 01C5          ; yes → push or finish (01C5)
019A: 04D4  C=LOAD DPTC       ; C[0] := 0xC → SCOM[12]
019B: 0121  IO=C ALL
019C: 0A1F  RCLF
019D: 01D0  A=LOAD ALL        ; A := operator stack; top entry A[1] = precedence, A[0] = paren
                              ;   level
019E: 015B  B=SRB ALL         ; B[0] := current paren level (B[1]) for the compare …
019F: 0289  IO=A-B DPT        ; entry level − current level
01A0: 0153  B=SLB ALL         ; … control word restored
01A1: 1048  JNC 01C5          ; entry belongs to an outer paren level → stop reducing
01A2: 0C48  A=SRA MAEX        ; R5 := top-entry precedence …
01A3: 09F0  A=R5 MANT         ; … into A[3]
01A4: 0989  IO=A-B MANT       ; top precedence − incoming precedence
01A5: 1046  JNC 01C8          ; lower → stop, push the incoming operator
; Pop the top entry and execute it.
01A6: 0658  A=SRB EXP         ; depth − 1 in the control word …
01A7: 0708  A=A-1 EXP1
01A8: 0140  A=SLA ALL
01A9: 09D2  A<>B MANT         ; … new control word → B …
01AA: 01D7  A<>E ALL          ; … kept in E while the operation runs
01AB: 0121  IO=C ALL          ; RCLF SCOM[12] …
01AC: 0A1F  RCLF
01AD: 01D0  A=LOAD ALL
01AE: 0148  A=SRA ALL         ; … drop the top entry (two nibble shifts) …
01AF: 0148  A=SRA ALL
01B0: 0121  IO=C ALL          ; … and store the stack back
01B1: 0A0F  STOF
01B2: 0101  IO=A ALL
01B3: 015B  B=SRB ALL
01B4: 0911  IO=B MANT         ; R5 := popped precedence
01B5: 02F0  A=R5 DPT
01B6: 02F3  B=R5 DPT
01B7: 0A0D  SWAP KR,SR        ; SR := the caller's continuation …
01B8: 0A0C  MOV KR,EXT[4..15] ; … KR := 0x0C00 + 2·precedence …
01B9: 00B5  SET KR[11]
01BA: 00A5  SET KR[10]
01BB: 0280  A=A+B DPT         ; (2 · precedence)
01BC: 0A18  MOV KR[4..7],R5   ; … exec slot: + → 00C4, × → 00C8, y^x → 00CC
01BD: 015B  B=SRB ALL         ; B[0] := popped level (depth before the pop)
01BE: 0111  IO=B ALL
01BF: 0A1F  RCLF
01C0: 01D3  B=LOAD ALL        ; B := SCOM[level], the pending left operand
01C1: 000F  MOV fB[1..4],R5   ; fB[1..4] := its stored flags (nibble 0) …
01C2: 0014  SWAP fA[1],fB[1]  ; … fA[1] := its inverse-pair bit; caller's fA[1] → fB[1]
01C3: 0120  A=C ALL           ; A := X (right operand)
01C4: 1A0A  JC 02C9           ; execute: A := B op A; the exec slot's successor (00C5/00C9)
                              ;   resumes at 0413
; Stack exhausted at this paren level: finish ")"/"=" or push the operator.
01C5: 0DD0  A=LOAD MLSD1      ; A[3] := 1
01C6: 0989  IO=A-B MANT       ; incoming precedence ≤ 1, i.e. ")" or "="?
01C7: 1852  JC 01F0           ; yes → close the paren level (01F0)
01C8: 0658  A=SRB EXP         ; push: A[0] := depth
01C9: 0148  A=SRA ALL
01CA: 0A87  MOV R5,#8         ; limit 8 levels
01CB: 02F3  B=R5 DPT
01CC: 0289  IO=A-B DPT
01CD: 1DFE  JC 04CC           ; ninth level → error
01CE: 006A  CLR fB[6]         ; the next operator needs a fresh operand
01CF: 0300  A=A+1 DPT1        ; new level = depth + 1
01D0: 0A06  MOV R5,fA[1..4]   ; operand flags (inverse-pair bit, signs) …
01D1: 02F4  C=R5 DPT          ; … into nibble 0 of X
01D2: 0101  IO=A ALL          ; STOF SCOM[level] := X
01D3: 0A0F  STOF
01D4: 0121  IO=C ALL
01D5: 04D4  C=LOAD DPTC       ; C[0] := 0xC → SCOM[12]
01D6: 0121  IO=C ALL
01D7: 0A1F  RCLF
01D8: 01D0  A=LOAD ALL        ; A := operator stack
01D9: 0140  A=SLA ALL         ; make room for a new top entry: precedence …
01DA: 0911  IO=B MANT
01DB: 02F0  A=R5 DPT
01DC: 0140  A=SLA ALL         ; … then the current paren level
01DD: 0611  IO=B EXP
01DE: 02F0  A=R5 DPT
01DF: 0121  IO=C ALL          ; STOF SCOM[12]
01E0: 0A0F  STOF
01E1: 0101  IO=A ALL
01E2: 0323  B=C+1 DPT1        ; B[0] := 0xD → SCOM[13]
01E3: 0111  IO=B ALL
01E4: 0A1F  RCLF
01E5: 01D0  A=LOAD ALL        ; A := SCOM[13] …
01E6: 07D0  A=LOAD EXP1       ; … with its paren-level/depth field replaced by
01E7: 0640  A=SLA EXP
01E8: 0680  A=A+B EXP         ; … B's paren level and depth + 1 …
01E9: 182E  JC 0200           ; … → store it (0200)
01EA: 01DE  D=0 ALL           ; Fix: collect one digit (INV Fix needs none, 01EB)
01EB: 0080  TST fA[8]
01EC: 1508  JNC 0470
; ARG_ONE_DIGIT (slots 00B7, 00CE, 00F4, also 05E9): one-digit argument (flag
; number, Dsz register, Fix). R5 = 0 (one digit) → 0221, where a running
; program or SST adds one (a program operand byte arrives as two digits).
; Δ [REORG] TI-59 01F1–01F3: the TI-59 makes the running/SST test here and
; then takes the two-digit path (its 04CC, R5 = 1); the TI-58C uses the common
; test at 0221–0227. Same digit counts (traced: Fix 3, St flg / If flg in a
; program on both machines), three words shorter.
01ED: 01D7  A<>E ALL          ; X → E …
01EE: 0A07  MOV R5,#0         ; … one digit (two when running, 0226)
01EF: 1864  JC 0221           ; → running test (0221), then ARG_COLLECT_SETUP
01F0: 0158  A=SRB ALL         ; ")"/"=": A[0] := current paren level
01F1: 0308  A=A-1 DPT1        ; level − 1 (borrows at level 0)
01F2: 1006  JNC 01F5          ; already at level 0 → leave it
01F3: 0140  A=SLA ALL
01F4: 0603  B=A EXP           ; B[1] := the decremented level
01F5: 0AD7  MOV R5,#13        ; B[0] := 0xD → SCOM[13]
01F6: 02F3  B=R5 DPT
01F7: 0111  IO=B ALL
01F8: 0A1F  RCLF
01F9: 01D0  A=LOAD ALL        ; A := SCOM[13]
01FA: 0610  A=B EXP           ; with the new paren level / depth
01FB: 0919  IO=-B MANT        ; ")" (precedence 1)?
01FC: 1008  JNC 0200          ; yes → done, store
01FD: 0648  A=SRA EXP         ; "=": another paren level still open? …
01FE: 0709  IO=A-1 EXP1
01FF: 18D1  JC 0197           ; … yes → reduce that level too
0200: 0111  IO=B ALL          ; STOF SCOM[13]
0201: 0A0F  STOF
0202: 0101  IO=A ALL
0203: 1D94  JC 04CD           ; → show the result (04CD → 048B → display)
; KEY_LNX: "lnx" handler (slot 0032, fn code 2); falls through FN_ENTRY_KR8
0204: 0A27  MOV R5,#2
0205: 0080  TST fA[8]
0206: 1804  JC 0208
0207: 0A57  MOV R5,#5
; FN_ENTRY_KR8: FN_ENTRY variant that tags KR[8] first ("√x" enters with fn code 0)
0208: 0085  SET KR[8]
; FN_ENTRY: common unary-function entry, function code in R5
; ("x²" code 7, "1/x" code 10, "lnx" code 2 via 0204). KR[14]+KR[12] plus the
; code moved into KR[4..7] at 0143 form fetch address 0x0500+fn — see the
; unary-function dispatch table there.
0209: 00E5  SET KR[14]
020A: 00C5  SET KR[12]
020B: 1991  JC 0143
; ── Comparison helpers for x=t / x≥t / Dsz (slots 00BC, 00C0, 00F8) ────────
; Enter with the difference (or decremented counter) in A; leave fA[9] set
; when the test is true. 0214 onward also serves as the start of the
; argument collector set-up (0228).
020C: 0D09  IO=A-1 MLSD1      ; Dsz: counter (mantissa) zero?
020D: 100C  JNC 0213
020E: 180C  JC 0214
020F: 0020  TST fA[2]         ; x≥t: difference negative?
0210: 1808  JC 0214
0211: 0D09  IO=A-1 MLSD1      ; x=t: difference zero?
0212: 1004  JNC 0214
0213: 0091  SET fA[9]         ; condition true
0214: 07D8  A=-1 EXP1         ; condition result → collector state; fA[9] = true
0215: 01D7  A<>E ALL
0216: 0201  IO=A DPT
0217: 0007  MOV fA[1..4],R5
0218: 04D0  A=LOAD DPTC
0219: 182C  JC 022F
021A: 0090  TST fA[9]         ; test true? (INV inverts in COND_TRANSFER)
021B: 0092  CLR fA[9]
021C: 1804  JC 021E
021D: 0083  TOG fA[8]
; Address operand (GTO / SBR / x=t / Dsz targets, slot 00F1): fA[0] = a label
; name may follow; from the keyboard collect 3 digits (R5 = 2) for a step
; number, in a program the operand step(s) come from memory (count 3, 0226).
021E: 01D7  A<>E ALL
021F: 0001  SET fA[0]         ; label or step number
0220: 0A27  MOV R5,#2         ; keyboard: three digits
0221: 0008  TST fB[0]         ; running … (ARG_ONE_DIGIT enters here from 01EF)
0222: 00D8  TST fB[13]        ; … or single step?
; Δ [REORG] TI-59 022A–022E: the collector count is loaded first (A[0] = A[1]
; = R5) and incremented when running (0226/0227), instead of the TI-59's
; MOV R5,#3 for the running case. Keyboard / running: 2 → 3 digits for step
; numbers (0220), 0 → 1 for ARG_ONE_DIGIT (01EF). ARG_TWO_DIGITS jumps in at
; 0223 (04CA) with COND at rest, so its count 1 is never incremented.
0223: 01F0  A=R5 ALL          ; collector state: count in A[0] …
0224: 06F0  A=R5 EXP          ; … and A[1]
0225: 1806  JC 0228           ; keyboard → as is
0226: 0300  A=A+1 DPT1        ; running / SST: one digit more (a program operand byte is fed as
                              ;   two digits) …
0227: 0700  A=A+1 EXP1        ; … in both counters
; 0228 ARG_COLLECT_SETUP: suspend the current operation sequence until its
; numeric argument has been typed. The count (digits expected − 1) is already
; in A[0] and A[1] (0223–0227): 0 = one digit, 1 = two register digits
; (04C8), 2 = three-digit step number from the keyboard, 3 from a program
; (0220). The collector state goes to E (digit counters in E[1..2]); X moves
; back to A.
0228: 00C9  SET fB[12]        ; argument entry mode: digit keys feed the collector (069F)
0229: 0140  A=SLA ALL         ; collector state shifted to E[1..2] …
022A: 01D7  A<>E ALL          ; … to E; X back to A
022B: 0072  CLR fA[7]
022C: 00A8  TST fB[10]
022D: 1794  JNC 05F7
022E: 008E  MOV fB[8],fA[8]   ; remember INV for the suspended operation
022F: 0051  SET fA[5]         ; then normalize and display X (falls into NUM_NORM)
; ═══════════════════════════════════════════════════════════════════════════
; NUM_NORM  (0x0230–0x02CA) — finish number entry and normalize X.
; Trace-checked on the TI-58C (headless: 5, 21, 7×3, 1/x of 0). Two registers
; represent X: A is the DISPLAY IMAGE while digits are typed (digits from
; nibble 3 up, A[0] = digits after the point), C holds the full-precision
; value once a result is shown (fB[5] set). On exit A = C = X normalized:
; mantissa left-aligned (MSD in nibble 15), exponent in A[1..2], A[0] = 0xC,
; signs in fA[2] (mantissa) / fA[3] (exponent), copied to fB[2]/fB[3].
; Loop 0238–0253: A[0] counts towards 12 — each pass either shifts the
; mantissa left (while the MSD is 0) or steps the exponent (fA[3] = sign,
; 0250/0251 cross zero), so the typed digits/decimal point become a proper
; exponent. Zero → 02B7; exponent overflow → OVFL_CLAMP 0254.
; Exit 02BA: if fA[5] or fA[10] is set the display is reformatted (054C)
; first; returns through 02C9/02CA to the continuation parked in SR.
; Note: COND accumulates borrows across several ALU steps until the next
; branch (e.g. 023B + 023C → 023D).
; ═══════════════════════════════════════════════════════════════════════════
0230: 0058  TST fB[5]         ; result on display (X already normalized in C)?
0231: 180A  JC 0236           ; no → normalize the entry image in A
0232: 005A  CLR fB[5]         ; yes: restore the saved signs …
0233: 0026  MOV fA[2],fB[2]
0234: 0036  MOV fA[3],fB[3]
0235: 0120  A=C ALL           ; … and take X from C
0236: 0D09  IO=A-1 MLSD1      ; mantissa zero?
0237: 1100  JNC 02B7          ; yes → X := 0
0238: 0709  IO=A-1 EXP1       ; exponent zero?
0239: 1804  JC 023B
023A: 0032  CLR fA[3]         ; yes → it can't be negative
023B: 0308  A=A-1 DPT1        ; A[0] − 1 …
023C: 0409  IO=A-xC DPTC      ; … still below 0xC?
023D: 1818  JC 0249           ; no → step the exponent
023E: 0300  A=A+1 DPT1
023F: 180A  JC 0244
0240: 0300  A=A+1 DPT1        ; shift loop: count …
0241: 0E09  IO=A-1 MMSD1      ; … MSD already non-zero?
0242: 1814  JC 024C           ; yes → step the exponent instead
0243: 0940  A=SLA MANT        ; shift mantissa left one digit
0244: 0409  IO=A-xC DPTC      ; count reached 12?
0245: 100B  JNC 0240
0246: 0E09  IO=A-1 MMSD1      ; normalized (MSD ≠ 0)?
0247: 18E6  JC 02BA           ; yes → done
0248: 0940  A=SLA MANT
0249: 0030  TST fA[3]         ; exponent negative? (choose the step direction)
024A: 1010  JNC 0252
024B: 1806  JC 024E
024C: 0030  TST fA[3]
024D: 180A  JC 0252
024E: 0708  A=A-1 EXP1        ; exponent − 1 …
024F: 182F  JC 0238
0250: 06D8  A=0 EXP           ; … crossed below zero: 0, sign flips
0251: 0033  TOG fA[3]
0252: 0700  A=A+1 EXP1        ; exponent + 1; a carry out of 99 overflows into …
0253: 1837  JC 0238           ; … OVFL_CLAMP below (falls through on carry)
; ── OVER/UNDERFLOW CLAMP (0x0254–0x025D) — trace-checked (1/x of 0, TI-58C).
; 1/x of 0 lands here twice: once from the divide's overflow exit at 0447, and
; again when display rounding (05B9) carries the all-9s image back over the
; top. Sets the ERROR blink flag fB[9] (idle gate at 063D) unless fA[14] is
; set — routines that tolerate the clamp pre-set fA[14] (03C7, 0A32, 0CFB),
; and the epilogues at 02C1/055B clear it again. Then clamps the value in A:
; fA[3] (exponent-negative) clear → overflow, +9.9999999…E99; set → underflow,
; 1E−99 (verified with the headless harness: 1 EE 99 +/- x² → 1 E−99, error). ──
0254: 00E0  TST fA[14]        ; error suppressed?
0255: 1004  JNC 0257          ; fA[14] set → clamp silently
0256: 0099  SET fB[9]         ; ERROR — start the display blink
0257: 0030  TST fA[3]
0258: 1808  JC 025C           ; exponent positive → overflow clamp
0259: 0ED0  A=LOAD MMSD1      ; underflow: mantissa := 1.0000000…
025A: 0708  A=A-1 EXP1        ; exponent := 0−1 → 99 (borrow) ≙ 1E−99
025B: 10BE  JNC 02BA          ; borrow guarantees the jump → display epilogue
025C: 0FD8  A=-1 MAEX1        ; overflow: borrow floods A[1..15] with 9s
025D: 10BA  JNC 02BA          ; = 9.9999999 99 → display epilogue
025E: 00A1  SET fA[10]        ; SBR (slot 0535): flush trace, then collect the address (021E)
025F: 1883  JC 021E
; KEY_INV: "INV" handler (slot 0022): toggle INV (fA[8]); the SET + TOG of fA[9]
; cancels a pending 2nd. Falls into the shared prefix-key tail.
0260: 0091  SET fA[9]
0261: 0083  TOG fA[8]         ; INV pending ↔
; KEY_2ND: "2nd" handler (slot 0012)
; KEY_2ND: "2nd" handler (slot 0012): toggle 2nd (fA[9] biases the next key's
; column by +5 → mirror dispatch table at 0x0062).
0262: 0093  TOG fA[9]         ; 2nd pending ↔
0263: 006E  MOV fB[6],fA[6]   ; a prefix key doesn't consume the fresh-operand state
0264: 00A8  TST fB[10]        ; LRN mode?
0265: 175C  JNC 0613          ; yes → record the prefix key as a program step (0613)
0266: 00A9  SET fB[10]        ; run mode: borrow fB[10] as a transient "prefix key" mark — keeps
                              ;   INV through the redisplay (042A) and stops EE entry (0129);
                              ;   cleared at 042B
0267: 0058  TST fB[5]         ; result on display?
0268: 10DA  JNC 02D5          ; yes → redisplay it
0269: 1A9D  JC 011B           ; entry in progress → redisplay the entry (via the EE room check)
026A: 0A67  MOV R5,#6         ; If flg (from slot 0078): code 6 …
026B: 19E1  JC 017B           ; … bank 0x00B0 → slot 00B6
026C: 0081  SET fA[8]         ; Del: fA[8] = delete, falls into Ins …
026D: 0A17  MOV R5,#1         ; Ins / Del: code 1 in the 0x0B10 bank → slot 0B11 → INS_DEL 0E5A
026E: 00A8  TST fB[10]        ; BST / Ins / Del only act in LRN mode …
026F: 1866  JC 02A2           ; … outside LRN they are ignored (trace-checked: BST in run mode
                              ;   leaves the step counter alone)
0270: 0085  SET KR[8]         ; KR := 0xB1x0 (0270–0273 + 020A) → slot 0x0B10 + code
0271: 00F5  SET KR[15]
0272: 00D5  SET KR[13]
0273: 18D3  JC 020A
; KEY_XT: "x⇄t" handler (slot 0023): operation code 14 in the KR[9] bank → slot 00EE
0274: 0AE7  MOV R5,#14
0275: 1C95  JC 002B
0276: 0AA7  MOV R5,#10
0277: 00A9  SET fB[10]
0278: 0051  SET fA[5]
0279: 18DF  JC 020A
027A: 03D3  B=LOAD DPT1       ; INV D.MS: entry 341 …
027B: 0A47  MOV R5,#4
027C: 06F3  B=R5 EXP
027D: 1A0D  JC 0177
027E: 0082  CLR fA[8]
027F: 1C1E  JC 048E
0280: 0AE7  MOV R5,#14
0281: 0058  TST fB[5]
0282: 1017  JNC 0277
0283: 0051  SET fA[5]
0284: 183C  JC 02A2
0285: 0033  TOG fA[3]         ; "+/-" in exponent entry: exponent sign ↔
0286: 189E  JC 02D5           ; → redisplay
0287: 0A17  MOV R5,#1
0288: 18FD  JC 020A
; RST_ABORT (from 04DF: RST held during a library-program fetch, 082A): stop
; the run, perform RST (028B–029D), then normalize and show X (029E → 022F).
; Δ [REORG] TI-59 028F–0290, 02A4–02A5: the TI-59 marks this path in fB[10]
; (SET here, TST/CLR after the RST body). Here the borrow of D=-1 DPT1 is the
; mark: COND stays activated until the next branch, 029E. Keyboard and program
; RST enter at 028B by a jump, i.e. with COND at rest. Same behaviour (RST held
; while ML-01 runs, traced on both machines); RST no longer clears fB[10].
0289: 03DE  D=-1 DPT1         ; borrow → COND := 0, the "abort" mark tested at 029E (D itself is
                              ;   reloaded at 028D)
028A: 000A  CLR fB[0]         ; stop the run …
; KEY_RST: "RST" handler (slot 0018 enters here), also the RST keycode in a
; program. Step counter := 000 with Prg Src Flag 0 (SCOM[0] nibbles 3–15
; cleared, Fix kept), subroutine return stack emptied (SCOM[15] := 0), library
; program deselected (SCOM[9] nibbles 3–15 cleared, partition / E000-address
; nibble / security kept), program cache invalidated (fB[11]). Trace-checked
; (GTO 012 RST; RST held while ML-01 runs).
; Δ [REORG] TI-59 0294: SET fB[11] comes first here, so the keyboard entry
; (TI-59 0291) is one word earlier than the RCLF.
028B: 00B9  SET fB[11]        ; cached program register stale
028C: 0A1F  RCLF              ; SCOM[0] (bus idle → row 0) …
028D: 01D6  D=LOAD ALL
028E: 09DE  D=0 MANT          ; … step 000, source 0
028F: 0A0F  STOF
0290: 0131  IO=D ALL
0291: 0AF7  MOV R5,#15        ; SCOM[15] := 0 (the next instruction drives no IO: zero is
                              ;   stored)
0292: 02F3  B=R5 DPT
0293: 0111  IO=B ALL
0294: 0A0F  STOF
0295: 0A97  MOV R5,#9         ; SCOM[9] …
0296: 02F3  B=R5 DPT
0297: 0111  IO=B ALL
0298: 0A1F  RCLF
0299: 01D6  D=LOAD ALL
029A: 09DE  D=0 MANT          ; … library program number cleared
029B: 0111  IO=B ALL          ; store D into the SCOM row named by B[0] (angle unit, RST)
029C: 0A0F  STOF
029D: 0131  IO=D ALL
029E: 10DF  JNC 022F          ; abort (COND from 0289) → normalize and show X; keyboard /
                              ;   program RST continues
029F: 00A0  TST fA[10]        ; R/S as a program step (0609): print a pending trace line, stop
02A0: 1804  JC 02A2
02A1: 0AA8  PRT.GO
02A2: 0082  CLR fA[8]         ; common key epilogue: INV used up, then redisplay (0264)
02A3: 187F  JC 0264
; KEY_GTO: "GTO" handler (slot 0016)
02A4: 0A07  MOV R5,#0
02A5: 0095  SET KR[9]
02A6: 1D2D  JC 0010
02A7: 02DE  D=0 DPT           ; Deg: 0
02A8: 1BF0  JC 04A0
02A9: 0080  TST fA[8]         ; Eng: INV Eng → clear fB[7], else set it
02AA: 0079  SET fB[7]
02AB: 0091  SET fA[9]
02AC: 18FB  JC 022F
02AD: 00FA  CLR fB[15]
02AE: 007A  CLR fB[7]
02AF: 1901  JC 022F
02B0: 0030  TST fA[3]         ; unlike exponent signs: A's exponent negative?
02B1: 10FE  JNC 0330          ; yes → swap so A has the positive exponent
02B2: 0684  C=A+B EXP         ; difference = sum of the magnitudes
02B3: 1318  JNC 043F          ; ≥ 100 → B is negligible, result A
02B4: 0D09  IO=A-1 MLSD1      ; A zero?
02B5: 1916  JC 0340           ; no → align and add
02B6: 110E  JNC 033D          ; yes → result B (swap)
02B7: 01D8  A=0 ALL           ; X := 0 …
02B8: 0022  CLR fA[2]         ; … positive
02B9: 0032  CLR fA[3]
; NUM_NORM exit / display epilogue: keep the full-precision X in C, save its
; signs, then return (reformatting the display first when fA[5]/fA[10]).
02BA: 0058  TST fB[5]
02BB: 04D0  A=LOAD DPTC       ; A[0] := 0xC (also the SCOM row of the AOS stack, see 0147)
02BC: 1008  JNC 02C0
02BD: 0104  C=A ALL           ; C := normalized X
02BE: 002E  MOV fB[2],fA[2]   ; save mantissa sign …
02BF: 003E  MOV fB[3],fA[3]   ; … and exponent sign
02C0: 004A  CLR fB[4]         ; decimal point no longer "typed"
02C1: 00E2  CLR fA[14]        ; re-arm the error clamp (fA[14] = suppress, 0254)
02C2: 0A0C  MOV KR,EXT[4..15] ; KR := 0x0100 …
02C3: 0085  SET KR[8]
02C4: 0A0D  SWAP KR,SR        ; … SR := 0x0100, KR := the continuation
02C5: 0050  TST fA[5]         ; result needs formatting? …
02C6: 00A0  TST fA[10]        ; … or a trace line is pending?
02C7: 150A  JNC 054C          ; yes → DISP_FORMAT, which returns here via 05BC/05BE
02C8: 005A  CLR fB[5]
02C9: 0015  SET KR[1] ; PREG  ; NUM_NORM return: arm PREG; the delay-slot SWAP below pulls the
                              ;   continuation saved at 0443 from SR (e.g. back into the 0x0500
                              ;   fn table — trace-checked: 050B for 1/x)
; KEY_USERDEF: keyboard row 1, user-defined label keys A–E and (with 2nd)
; A′–E′ (from 06A8); bypasses the dispatch table at 0011. Builds KR for the
; 0x0B10 sequence bank (0270: KR[8], KR[15], KR[13] + FN_ENTRY's KR[12]) with
; code 2 → slot 0B12: search the program for the label and run it as a
; subroutine. (02CA doubles as the PREG-return delay slot of 02C9.)
02CA: 0A0D  SWAP KR,SR
02CB: 0A27  MOV R5,#2         ; slot 0B12
02CC: 18B9  JC 0270
; Register read-modify-write prologue (slots 00D9 SUM, 00E2 Prd, 00E7 Exc):
; B := X with its flags, then read the register (fA[9] = read).
02CD: 0120  A=C ALL           ; A := X
02CE: 0A16  MOV R5,fB[1..4]   ; with its signs
02CF: 02F0  A=R5 DPT
02D0: 0103  B=A ALL           ; B := X
02D1: 0091  SET fA[9]         ; RCL (slot 00DF) enters here: read the register
02D2: 1BB8  JC 04AE           ; → REG_ACCESS
; Exponent digit (from 0304, the digit in B[1]): shift the exponent left and
; add the digit.
; Δ [REORG] TI-59 02DB–02DD, 0328: the TI-59 moves the digit to B[2] before
; the exponent test and back with B=SRB EXP here; the TI-58C shifts only on
; the mantissa path (0305). Same result.
02D3: 0640  A=SLA EXP         ; exponent digit: shift the exponent left …
02D4: 0680  A=A+B EXP         ; … and add the new digit
; Redisplay entry: fB[0] = LRN/program-step display (06B1); otherwise rebuild
; the entry display image.
02D5: 0008  TST fB[0]
02D6: 17B6  JNC 06B1
02D7: 00F8  TST fB[15]
02D8: 0078  TST fB[7]
; ═══════════════════════════════════════════════════════════════════════════
; ENTRY DISPLAY BUILD  (0x02D9–0x02E9, continued at 0x0417–0x0432) — trace-
; checked (1 2 . 3 4 +/- EE 5 +/- → "-12.34-05" on both machines). Builds the
; display-control image in B for the number being typed in A. B nibble codes
; (decoded by the display hardware, cf. App/Views/LEDDisplayView.swift):
; 0 = digit with leading-zero blanking, 9 = digit always shown, 3 = blank
; (positive sign), 6 = minus sign; B[0] = decimal-point position (R5 at idle,
; 0626). The sign marker (3/6) is slid left until it sits just left of the
; most significant digit, so all positions beyond it blank. In EE mode
; B[1..4] become "99" (exponent digits) plus the exponent sign 3/6 —
; generated by negating 7/4 (02E7–02E8) — and the pre-idle code (060A)
; shifts A two places left to make room.
; ═══════════════════════════════════════════════════════════════════════════
02D9: 0030  TST fA[3]         ; exponent negative?
02DA: 00A2  CLR fA[10]        ; drop any pending trace record (see 0688): digit keys never print
                              ;   theirs
02DB: 01DB  B=0 ALL           ; start with an empty control image
02DC: 0DD6  D=LOAD MLSD1      ; D := digit marker at nibble 3 (units position)
02DD: 001A  CLR fB[1]
02DE: 1008  JNC 02E2          ; negative exponent → EE layout
02DF: 0709  IO=A-1 EXP1       ; exponent zero?
02E0: 0A37  MOV R5,#3         ; plain layout: decimal point base position 3
02E1: 126E  JNC 0418          ; yes → plain layout (0418, base position 3)
02E2: 0FD6  D=LOAD MAEX1      ; EE layout: digit marker at nibble 1
02E3: 0030  TST fA[3]
02E4: 0A77  MOV R5,#7         ; exponent sign positive → 7 …
02E5: 1804  JC 02E7
02E6: 0A47  MOV R5,#4         ; … negative → 4
02E7: 06F3  B=R5 EXP
02E8: 061B  B=-B EXP          ; 100 − 7 = "93", 100 − 4 = "96": forced exponent digits + sign
                              ;   code
; Δ [REORG] TI-59 02F2–030E: the rest of the build (decimal point, sign
; marker, digit-position loop, INV handling, redisplay tail) moved to
; 0417–0432 to make room for the power-on code; 02EA–02F2 are filler.
02E9: 125C  JNC 0417          ; always taken (B=-B borrows) → EE layout, base position 5 (0417)
; Unused filler: A=A ALL (no-op) words, the gap left by the code moved to
; 0417; never executed (no coverage scenario reaches them).
02EA: 0100  A=A ALL
02EB: 0100  A=A ALL
02EC: 0100  A=A ALL
02ED: 0100  A=A ALL
02EE: 0100  A=A ALL
02EF: 0100  A=A ALL
02F0: 0100  A=A ALL
02F1: 0100  A=A ALL
02F2: 0100  A=A ALL
; KEY_DPT: "." handler (slot 0039): mark the decimal point (fB[4]); following
; digits count up A[0]. Falls into the number-entry path at 02F5.
02F3: 0049  SET fB[4]         ; decimal point typed
02F4: 00F2  CLR fA[15]        ; leaves exponent entry
; ═══════════════════════════════════════════════════════════════════════════
; NUMBER ENTRY  (0x02F5–0x0320) — trace-confirmed (headless harness).
; Digit keys enter at 02F6 from DIGIT_SLIDE (016A) with the digit in KR[4..7];
; "." enters at 02F5 with KR[8] set, which skips the digit insert (02FF).
; A digit key with a result on display (fB[5]) starts a new number (02FC).
; Limits: 10 mantissa digits (8 while an exponent is shown), and as many
; digits after the point (0313–0316). In exponent entry (fA[15]) the digit is
; shifted into A[1..2] instead (02D3).
; ═══════════════════════════════════════════════════════════════════════════
02F5: 0085  SET KR[8]         ; "." : no digit to insert
02F6: 00C8  TST fB[12]        ; argument entry pending (STO nn, GTO nnn, …)?
02F7: 178E  JNC 06BE          ; yes → the digit goes to the argument collector
02F8: 00A8  TST fB[10]        ; LRN mode?
02F9: 15FC  JNC 05F7          ; yes → the digit becomes a program step
02FA: 0058  TST fB[5]         ; result on display?
02FB: 1808  JC 02FF           ; no → continue the entry
02FC: 01D8  A=0 ALL           ; yes → start a new number: clear the image …
02FD: 0A02  CLR fA            ; … and the entry flags
02FE: 005A  CLR fB[5]
02FF: 0A85  TST KR[8]         ; "."?
0300: 103C  JNC 031E          ; yes → just redisplay
0301: 0A08  MOV R5,KR[4..7]   ; R5 := digit
0302: 0EF3  B=R5 MMSD1        ; B[1] := digit, B[15] := 1 (limit marker) …
0303: 00F0  TST fA[15]        ; exponent entry?
0304: 1063  JNC 02D3          ; yes → shift the digit into the exponent
; Δ [REORG] TI-59 0328: B=SLB EXP now follows the exponent test (see 02D3).
0305: 0653  B=SLB EXP         ; mantissa entry: digit moved to B[2]
0306: 095B  B=SRB MANT        ; limit marker 10 digits up: nibble 12 …
0307: 095B  B=SRB MANT
0308: 095B  B=SRB MANT
0309: 0AA7  MOV R5,#10
030A: 02F3  B=R5 DPT          ; … and at most 10 digits after the point
030B: 0030  TST fA[3]         ; exponent shown (negative, …
030C: 1006  JNC 030F
030D: 0709  IO=A-1 EXP1       ; … or non-zero)?
030E: 100A  JNC 0313          ; exponent 00 → keep the 10-digit limit
030F: 095B  B=SRB MANT        ; yes → only 8 digits: marker to nibble 10 …
0310: 095B  B=SRB MANT
0311: 0A87  MOV R5,#8
0312: 02F3  B=R5 DPT          ; … and at most 8 after the point
0313: 0989  IO=A-B MANT       ; mantissa already at the limit?
0314: 1814  JC 031E           ; yes → ignore the digit
0315: 0289  IO=A-B DPT        ; too many digits after the point?
0316: 1810  JC 031E           ; yes → ignore the digit
0317: 0048  TST fB[4]         ; after the decimal point?
0318: 1804  JC 031A
0319: 0300  A=A+1 DPT1        ; yes → one more fractional digit
031A: 0940  A=SLA MANT        ; make room at nibble 3 …
031B: 09DB  B=0 MANT
031C: 0C53  B=SLB MAEX        ; … B[3] := digit …
031D: 0980  A=A+B MANT        ; … insert it
; ── Branch on fB[0] (0x031E) ───────────────────────────────────────────────
031E: 0008  TST fB[0]         ; LRN mode? (program-step display)
031F: 157C  JNC 05DD          ; fB[0] handler (not taken on cold start)
0320: 188F  JC 02D9           ; → build the entry display
; Entry used by the trig / P→R code (asin, acos, R→P): sets up a subtract or
; swap before falling into ADD.
0321: 0011  SET fA[1]
0322: 00C3  TOG fA[12]
0323: 0092  CLR fA[9]
0324: 00C0  TST fA[12]
0325: 00B0  TST fA[11]
0326: 0093  TOG fA[9]
0327: 1804  JC 0329
0328: 0011  SET fA[1]
0329: 0080  TST fA[8]
032A: 1808  JC 032E
032B: 0ED3  B=LOAD MMSD1      ; B := 1.0
032C: 002A  CLR fB[2]
032D: 003A  CLR fB[3]
032E: 0090  TST fA[9]
032F: 1008  JNC 0333
; ADD_SWAP: exchange the operands (value and signs) and retry.
0330: 0CD2  A<>B MAEX
0331: 0024  SWAP fA[2],fB[2]
0332: 0034  SWAP fA[3],fB[3]
; ═══════════════════════════════════════════════════════════════════════════
; ADD  (0x0333–0x034A) — A := B + A, or B − A with fA[1] set (AOS slot 00C4).
; Trace-confirmed (12 + .034, 3 − 5). Signs: fA[2]/fA[3] for A, fB[2]/fB[3]
; for B. Subtraction negates A's sign. The operands are swapped (0330) until
; A has the larger exponent, B is shifted right by the exponent difference,
; then magnitudes are added (via the multiply loop's carry tail at 0724) or,
; for unlike signs, the smaller magnitude is subtracted from the larger.
; An exponent difference ≥ 100 (only possible with unlike exponent signs)
; leaves A unchanged (02B3). Exit through ARITH_EXIT 043F.
; ═══════════════════════════════════════════════════════════════════════════
0333: 0010  TST fA[1]         ; subtract?
0334: 1804  JC 0336
0335: 0023  TOG fA[2]         ; yes → negate A
0336: 0012  CLR fA[1]
0337: 003C  CMP fA[3],fB[3]   ; exponent signs equal?
0338: 1911  JC 02B0           ; no → 02B0
0339: 068C  C=A-B EXP         ; same sign: A.exp − B.exp
033A: 1015  JNC 0330          ; A.exp smaller → swap, retry
033B: 0030  TST fA[3]         ; both exponents negative: the larger exponent value is the
033C: 1808  JC 0340           ; smaller number → swap (033D)
033D: 0CD2  A<>B MAEX         ; ADD: swap operands (sign of the larger magnitude wins)
033E: 0024  SWAP fA[2],fB[2]
033F: 0034  SWAP fA[3],fB[3]
0340: 072C  C=C-1 EXP1        ; align: for each unit of exponent difference …
0341: 1006  JNC 0344
0342: 095B  B=SRB MANT        ; … shift B right one digit
0343: 1807  JC 0340
0344: 01DC  C=0 ALL
0345: 002C  CMP fA[2],fB[2]   ; like signs?
0346: 17BC  JNC 0724          ; yes → A += B, carry handled by the multiply tail (0724)
0347: 0989  IO=A-B MANT       ; unlike: |A| < |B|?
0348: 1017  JNC 033D          ; yes → swap (sign of the larger wins)
0349: 0988  A=A-B MANT        ; A := |A| − |B|
034A: 19EA  JC 043F           ; → ARITH_EXIT
034B: 0022  CLR fA[2]         ; Op 2x/3x (slot 0105): result sign
034C: 00B0  TST fA[11]
034D: 1F5A  JC 06FA
034E: 0021  SET fA[2]
034F: 1F56  JC 06FA
; ═══════════════════════════════════════════════════════════════════════════
; MAIN POWER-ON SETUP  (0x0350–0x03A6, entered from 0x000E)
; Checks the constant memory and rebuilds the SCOM status rows from it, then
; falls into CLR (03A7). Trace-checked (headless): first power-up; power
; cycle after Fix 2, Rad, St flg 3, Eng, 4 Op 17, a program, LRN position,
; Pgm 02 and a pending "7 + 3 ("; power-up with a corrupted E000.
;   0352  settle delay (≈100 cycles) before the first constant-memory access
;   035C  RAM-size probe: raw register 0x7F (127) written and read back
;   036A  signature check: E000 (raw register 0x3C = 60) nibbles 3–15 = the
;         ln 10 mantissa?
;   0370  no → first power-up: zero all 64 raw registers (user registers and
;         E000–E003), write E000 = signature, partition 3, Fix floating
;   0381  restore partition and Fix from E000 into SCOM[9], [13] and [0]
; E000 layout: nibbles 15–3 signature (constant 0 = ln 10, 2302585092994),
; 2–1 partition ÷ 10 (BCD; written by Op 17, 17A6–17B5), 0 Fix (n + 2,
; 0 = floating; written by Fix, 0474–0481). Everything else starts cleared as
; on the TI-59: angle unit (DEG), Eng/Sci, user flags, AOS, t, step counter,
; return stack, the selected module program, X. Program and data registers
; are not touched on a power cycle.
; Δ [HW] TI-59 0377–039E: the TI-59 probes register 90 (RAM_OP write, read,
; clear) and loads fixed values for 60 or 120 registers, partition 3 or 6:
; its serial RAM is lost at power-off, so there is nothing to check or
; restore. The TI-58C keeps a probe (MEMWR/MEMRD, raw register 127) and adds
; the signature check, the RAM clear and the restore.
; ═══════════════════════════════════════════════════════════════════════════
0350: 01D8  A=0 ALL
0351: 0A88  PRT.CLR           ; reset the print buffer — issued unconditionally; reset never probes for a printer
; Settle delay: A[2..1] = 50 is counted down to a borrow, 51 passes of two
; instructions. The CPU is active here; this is not an idle-timing loop.
; Δ [HW] new, no TI-59 counterpart. Derived: it delays the first MEMWR/MEMRD
; after power-on (likely for the CMOS RAM supply/interface to settle; not
; documented).
0352: 0BD0  A=LOAD MLSD5      ; A := 0x5000 …
0353: 0148  A=SRA ALL         ; … A[2..1] := 50: pass counter
0354: 0708  A=A-1 EXP1        ; count down …
0355: 1803  JC 0354           ; … until it borrows (A[2..0] = 990)
0356: 0A0C  MOV KR,EXT[4..15] ; KR := 0: constant index 0; also the clear-loop start for a
                              ;   128-register RAM
0357: 09C0  A=A+CON MANT      ; A[15..3] := ln 10 mantissa 2302585092994: probe value and
                              ;   signature
0358: 0A77  MOV R5,#7         ; B := 0x7F: raw register 127 …
0359: 0CF3  B=R5 MAEX
035A: 0AF7  MOV R5,#15
035B: 02F3  B=R5 DPT
; RAM-size probe: write A to raw register 0x7F and read it back. Only a
; 128-register RAM has that register (120 user registers, like a TI-59); the
; 64-register TI-58C RAM ignores the write and reads 0, so the probe also
; relies on the hardware not aliasing 0x7F onto 0x3F. MEMWR/MEMRD take a
; binary address from the bus (Sout[1]·16 + Sout[0]); the data is the IO
; value of the next instruction, within that instruction's field.
; Δ [HW] TI-59 0377–0386: RAM_OP probe of register 90, cleared afterwards.
035C: 0111  IO=B ALL          ; address 0x7F …
035D: 0A76  MEMWR             ; … write …
035E: 0101  IO=A ALL          ; … the probe value
035F: 0111  IO=B ALL          ; address 0x7F …
0360: 0A86  MEMRD             ; … read it back …
0361: 01D6  D=LOAD ALL        ; … D := RAM[0x7F] (0 when absent)
0362: 05D3  B=LOAD LLSD1      ; B[3] := 1: "128-register RAM" mark (B = 0x107F)
0363: 01BE  D=A-D ALL         ; read-back = written value?
0364: 0139  IO=-D ALL
0365: 1808  JC 0369           ; yes (128 registers): E000 at 0x7C, KR = 0 → 128 clear passes
0366: 00A5  SET KR[10]        ; 64 registers: KR := 0x400 → 64 clear passes …
0367: 0A37  MOV R5,#3
0368: 0CF3  B=R5 MAEX         ; … B := 0x3F, mark cleared
0369: 04D3  B=LOAD DPTC       ; B[0] := 0xC: E000 = raw register 0x3C (0x7C)
; Signature check: nibbles 3–15 of E000 must hold the ln 10 mantissa written
; at the last first power-up (0380). Nibbles 0–2 carry state and are not
; compared.
036A: 0111  IO=B ALL          ; address of E000 …
036B: 0A86  MEMRD
036C: 01D6  D=LOAD ALL        ; D := E000
036D: 09BE  D=A-D MANT        ; signature − E000 mantissa; D[2..0] keeps the saved state
036E: 0939  IO=-D MANT        ; zero?
036F: 1826  JC 0382           ; yes: constant memory valid → restore (0382) with D = 0…0 |
                              ;   partition | Fix
; First power-up (no valid signature, e.g. after the batteries were removed):
; write zero into every raw register, 0–63 (0–127 on a 128-register RAM),
; E000–E003 included. C[1..0] is the binary address; KR counts the passes up
; to KR[11] (from 0x400, or from 0 for 128 registers, to 0x800).
0370: 01DC  C=0 ALL           ; address 0
0371: 0121  IO=C ALL          ; address …
0372: 0A76  MEMWR             ; … write: the next instruction drives no IO, so the register is
                              ;   written with 0
0373: 0A04  INC KR            ; count the pass
0374: 0AB5  TST KR[11]        ; all registers done?
0375: 100A  JNC 037A          ; yes → write the signature
0376: 0324  C=C+1 DPT1        ; next address: low nibble …
0377: 180D  JC 0371
0378: 0724  C=C+1 EXP1        ; … carry into C[1]
0379: 1811  JC 0371
; Write E000 with the signature and the default state: partition ÷ 10 = 03
; (A[2..1] := B[2..1] = 03 from the address 0x3C; 07 − 1 = 06 for a
; 128-register RAM), Fix 0 = floating (A[0] = 0 from the delay loop).
037A: 0610  A=B EXP           ; A[2..1] := 03 (07)
037B: 0919  IO=-B MANT        ; 128-register mark (B[3]) set?
037C: 1804  JC 037E           ; no → partition 3
037D: 0708  A=A-1 EXP1        ; yes: 07 − 1 → partition 6
037E: 0111  IO=B ALL          ; address of E000 …
037F: 0A76  MEMWR
0380: 0101  IO=A ALL          ; … E000 := signature | partition | Fix 0
; Restore from E000 (D[2..1] = partition ÷ 10 in BCD, D[0] = Fix; the valid
; path enters at 0382):
;   SCOM[9]  := B: nibble 1 = high nibble of the E000 address (3; 7 for a
;               128-register RAM), nibble 0 = partition in hex (BCD 10–12 →
;               0xA–0xC, 0384–038A)
;   SCOM[13] := A: nibble 8 = partition, nibbles 5–3 = top register 059 (119),
;               all else 0 (angle unit DEG, no pending AOS)
;   SCOM[0]  := Fix in nibble 0, all else 0 (03A4–03A6)
; Δ [HW] TI-59 0387–039E: fixed values from the probe result — SCOM[9] 0x23
; or 0x46 (RAM chips, partition 3/6), SCOM[13] 060/120 registers. On the
; TI-58C SCOM[9] nibble 1 is no chip count: 0479 and Op 17 build the E000
; address from it.
0381: 0106  D=A ALL           ; first power-up: D := the state just written
0382: 0631  IO=D EXP          ; R5 := D[1], the partition's units digit (valid path enters here)
0383: 02F3  B=R5 DPT          ; B[0] := units (B[1] = 3 or 7 from the E000 address)
0384: 067E  D=SRD EXP         ; D[1] := tens digit
0385: 0639  IO=-D EXP         ; tens ≠ 0 (partition 10–12: 128-register RAM only)?
0386: 0A07  MOV R5,#0
0387: 1804  JC 0389           ; no → + 0
0388: 0AA7  MOV R5,#10        ; yes → + 10
0389: 02F0  A=R5 DPT          ; A[0] := 0 or 10
038A: 0283  B=A+B DPT         ; B[0] := partition as one hex digit
038B: 0919  IO=-B MANT        ; 128-register mark (B[3])? (COND for 038F)
038C: 09DB  B=0 MANT          ; B = 0x3p (0x7p): the SCOM[9] value
038D: 01D8  A=0 ALL
038E: 0A67  MOV R5,#6         ; register count ÷ 10: 6 …
038F: 1804  JC 0391           ; 64 registers → 6
0390: 0AC7  MOV R5,#12        ; 128 registers → 12
0391: 06F0  A=R5 EXP          ; A[1] := register count ÷ 10
0392: 0A97  MOV R5,#9
0393: 02F4  C=R5 DPT          ; C[0] := 9 …
0394: 0121  IO=C ALL          ; … STOF SCOM[9] := B
0395: 0A0F  STOF
0396: 0111  IO=B ALL
0397: 0211  IO=B DPT          ; R5 := B[0], the partition
0398: 09F0  A=R5 MANT         ; A[3] := partition …
0399: 0940  A=SLA MANT
039A: 0940  A=SLA MANT
039B: 0C40  A=SLA MAEX        ; … three more shifts: partition to nibble 8, count ÷ 10 to
                              ;   nibbles 5–4 …
039C: 0C40  A=SLA MAEX
039D: 0C40  A=SLA MAEX
039E: 0D08  A=A-1 MLSD1       ; … count − 1: top register 059 (119) in nibbles 5–3
039F: 0AD7  MOV R5,#13
03A0: 01F4  C=R5 ALL          ; C := 13 …
03A1: 0121  IO=C ALL          ; … STOF SCOM[13] := A
03A2: 0A0F  STOF
03A3: 0101  IO=A ALL
03A4: 0CDE  D=0 MAEX          ; D := Fix nibble only
03A5: 0A0F  STOF              ; the bus is idle after 03A4 → row 0 …
03A6: 0131  IO=D ALL          ; … SCOM[0] := Fix (flags, step counter, pending key all 0)
; ═══════════════════════════════════════════════════════════════════════════
; KEY_CLR / KEY_CE  (0x03A7–0x03C6) — also the tail of the power-on setup.
; Trace-confirmed (headless: 1 2 CE → 0; 5+3= CE → 8.; 5+3 CE 2= → 7.;
; 5+3 CLR 2= → 2.; CE/CLR end the error blink).
; CLR: print a pending trace line, empty the AOS (SCOM[13] paren level and
; depth := 0), X := 0, clear every fB flag except fB[0] (running), fB[7]
; (Eng), fB[11] (cache) and fB[13] (SST) — this includes the error flag —,
; abandon any suspended operation sequence (KR = SR = 0), then fall into CE.
; CE: clear the error flag; a displayed result stays as it is, a number being
; typed is cleared (treated as a fresh "." entry, 02F5). Pending operations
; survive CE.
; ═══════════════════════════════════════════════════════════════════════════
03A7: 00A0  TST fA[10]
03A8: 1804  JC 03AA           ; if fA[10] clear, skip PRT.GO (no print pending)
03A9: 0AA8  PRT.GO
03AA: 0AD7  MOV R5,#13        ; SCOM[13] …
03AB: 01F0  A=R5 ALL
03AC: 0101  IO=A ALL
03AD: 0A1F  RCLF              ; recall a SCOM register onto the bus
03AE: 01D3  B=LOAD ALL
03AF: 06DB  B=0 EXP           ; … paren level / depth := 0 (AOS emptied)
03B0: 0101  IO=A ALL
03B1: 0A0F  STOF
03B2: 0111  IO=B ALL
03B3: 01DC  C=0 ALL           ; X := 0
; Idiom: clear all of fB EXCEPT bits {0,7,11,13}. The four SWAPs park those
; bits in fA, CLR fB wipes the rest, and the second four SWAPs restore them.
; Net effect: reset the volatile flag bits, keep the 4 sticky status bits.
; The wipe includes the ERROR flag fB[9] — this is what makes CLR end the
; error blink (trace-checked: 1 ÷ 0 = CLR).
03B4: 0074  SWAP fA[7],fB[7]
03B5: 00D4  SWAP fA[13],fB[13]
03B6: 0004  SWAP fA[0],fB[0]
03B7: 00B4  SWAP fA[11],fB[11]
03B8: 0A0A  CLR fB
03B9: 0074  SWAP fA[7],fB[7]
03BA: 00D4  SWAP fA[13],fB[13]
03BB: 0004  SWAP fA[0],fB[0]
03BC: 00B4  SWAP fA[11],fB[11]
03BD: 0A0C  MOV KR,EXT[4..15] ; KR = SR = 0: no suspended sequence …
03BE: 0A0D  SWAP KR,SR        ; swap KR with the subroutine-return register
03BF: 0A0C  MOV KR,EXT[4..15]
03C0: 0069  SET fB[6]         ; … and a fresh operand
03C1: 0058  TST fB[5]         ; KEY_CE: result on display?
03C2: 009A  CLR fB[9]         ; clear ERROR — the CE entry at 03C1 also passes
                              ;   here, so CE too stops the error blink
03C3: 11DD  JNC 02D5          ; yes → leave it, redisplay
03C4: 0059  SET fB[5]         ; entry: start over …
03C5: 004A  CLR fB[4]
03C6: 19A3  JC 02F5           ; … as an empty number entry
; Trig/R→P helpers in front of MULDIV (03C7–03D3): set up a divide (fA[1]) of
; D by A, optionally swapping operands; fA[14] tolerates an overflow clamp.
03C7: 00E1  SET fA[14]        ; tolerate over/underflow clamp silently (0254)
03C8: 00C3  TOG fA[12]
03C9: 00C0  TST fA[12]
03CA: 0092  CLR fA[9]
03CB: 0011  SET fA[1]         ; divide
03CC: 0133  B=D ALL           ; multiply variant of 03CB (fA[1] clear): B := D
03CD: 000F  MOV fB[1..4],R5
03CE: 1808  JC 03D2
03CF: 0CD2  A<>B MAEX
03D0: 0024  SWAP fA[2],fB[2]
03D1: 0034  SWAP fA[3],fB[3]
03D2: 0090  TST fA[9]
03D3: 13D4  JNC 05BD
; ═══════════════════════════════════════════════════════════════════════════
; MULDIV  (0x03D4–0x03DF, 0x0433–0x043D, loops 0x06FD–0x072A) — A := B × A,
; or B ÷ A with fA[1] set (AOS slot 00C8; RECIP 076C for 1/x). Trace-checked
; on the TI-58C (7 × 3, 5 ÷ 3, 1/x of 0).
; Exponents are added (division toggles the divisor's exponent sign first,
; 0433); the result sign is the XOR of the operand signs.
;   multiply 0718–072A: C holds the multiplier; for each of its digits
;            (LSD first, 0722) B is added into the product A that many times;
;            then either the product is shifted right or the multiplicand
;            left (071B–0721), keeping 13 significant digits. A carry out of
;            the product shifts it right and bumps A[0] (0726–072A).
;   divide   0708–0717: restoring division — C (dividend) is reduced by B
;            (divisor) until it borrows, counting the quotient digit in A[3]
;            (070A–070D); then the divisor shifts right and the quotient left
;            until 13 digits are produced (070F).
; Exit: ARITH_EXIT 043F; exponent overflow → 043E.
; Δ [REORG] TI-59 0422–044F: the unlike-exponent subtraction and both loops
; moved, unchanged, to 06FD–072A (043B/043D jump there) to make room in
; this chip for the power-on code.
; ═══════════════════════════════════════════════════════════════════════════
03D4: 0010  TST fA[1]         ; divide?
03D5: 18BE  JC 0434           ; no → multiply
03D6: 0011  SET fA[1]
03D7: 0D09  IO=A-1 MLSD1      ; divisor zero?
03D8: 18B6  JC 0433           ; no → divide
03D9: 0989  IO=A-B MANT       ; divisor 0 — dividend zero too?
03DA: 0026  MOV fA[2],fB[2]
03DB: 10C6  JNC 043E          ; x ÷ 0, x ≠ 0 → overflow exit → 9.9999999 99, blinking
03DC: 0099  SET fB[9]         ; 0 ÷ 0: ERROR …
03DD: 0022  CLR fA[2]
03DE: 0ED0  A=LOAD MMSD1      ; … with result 1.0
03DF: 18E2  JC 0450           ; for 0÷0 (verified: 0 ÷ 0 = → 1, error flag set)
; LRN toggle: fB[10] ↔, clear INV, error, run/trace flags.
03E0: 00AB  TOG fB[10]        ; LRN mode ↔
03E1: 00A8  TST fB[10]
03E2: 0082  CLR fA[8]
; Δ [FIX] new: drop a pending Ind when LRN toggles. On the TI-59 an Ind
; pressed before LRN stays pending in LRN mode and shifts the first recorded
; key: "Ind LRN 5 LRN" stores 00 05 at steps 000–001 (TI-59) instead of 05 at
; 000 (TI-58C); trace-checked on both.
03E3: 0072  CLR fA[7]         ; cancel a pending Ind
03E4: 009A  CLR fB[9]         ; clear a pending error
03E5: 000A  CLR fB[0]
03E6: 00D2  CLR fA[13]
03E7: 00A2  CLR fA[10]
03E8: 15D6  JNC 06D3          ; entering LRN → fetch and show the current step
03E9: 00B9  SET fB[11]
03EA: 0168  A=SRC ALL
03EB: 0007  MOV fA[1..4],R5
03EC: 0042  CLR fA[4]
03ED: 04D4  C=LOAD DPTC
03EE: 00D8  TST fB[13]        ; LRN refused (no program memory): plain redisplay
03EF: 0058  TST fB[5]
03F0: 1383  JNC 022F
03F1: 1A9F  JC 02A2
; KEY_SBR: "SBR" handler (slot 0017)
03F2: 0080  TST fA[8]
03F3: 178A  JNC 07B8
03F4: 0A47  MOV R5,#4
03F5: 0095  SET KR[9]         ; FN_ENTRY in the KR[9] bank (0x0520 + fn / with KR[8] 0x0530 +
                              ;   fn)
03F6: 1BDD  JC 0208
03F7: 0073  TOG fA[7]         ; Ind (2nd y^x, slot 00A4): toggle Ind
03F8: 1B29  JC 0264
03F9: 0AA7  MOV R5,#10        ; Pgm (2nd LRN, slot 0063): fn 10, KR[8]+KR[9] → slot 053A
03FA: 180B  JC 03F5
03FB: 1EE0  JC 076B           ; Dsz (slot 00F7): write the counter back (076B → 0A24)
03FC: 0008  TST fB[0]         ; Lbl: from the keyboard it does nothing — number entry even
                              ;   continues ("5 Lbl 3" → 53, trace-checked) …
03FD: 00D8  TST fB[13]
03FE: 1B35  JC 0264
03FF: 0001  SET fA[0]         ; … in a program: the label name follows (skipped as an operand)
0400: 1B39  JC 0264
; KEY_SST: "SST" handler (slot 0014). In LRN mode (fB[10]) step forward
; (06DD → PRGREG_FETCH); in run mode execute one program step (fB[13]).
0401: 00A8  TST fB[10]        ; LRN mode?
0402: 15B6  JNC 06DD          ; yes → advance one step and redisplay
0403: 00D9  SET fB[13]        ; run mode: single-step flag, falls into …
; KEY_LRN: "LRN" handler (slot 0013). Refused (→ 03EE) when the partition has
; no program registers (SCOM[9] nibble 0 = 0). Otherwise toggles LRN mode
; (fB[10], 03E0) and fetches/displays the current step (06D3).
0404: 0A97  MOV R5,#9         ; (keycode 31 executed as a program step — not recordable by keys
                              ;   — lands here too: the run stops in LRN mode at the next step;
                              ;   trace-checked "7 LRN 5 …" → "002 05")
0405: 02F3  B=R5 DPT
0406: 0111  IO=B ALL
0407: 0A1F  RCLF
0408: 01D3  B=LOAD ALL
0409: 0219  IO=-B DPT         ; partition (nibble 0) zero?
040A: 1839  JC 03EE           ; yes → no program memory, ignore
; Δ [HW] TI-59 0402–0404: no "memory protected" test (SCOM[9] nibble 2, set by
; reading a protected magnetic card on the TI-59): there is no card reader.
040B: 00D8  TST fB[13]        ; SST (0403 set fB[13])?
040C: 1859  JC 03E0           ; no → LRN toggle
040D: 006E  MOV fB[6],fA[6]   ; SST in run mode: execute exactly one step …
040E: 00A2  CLR fA[10]
040F: 1F8C  JC 07D5           ; … (07D5 → fetch, dispatch; fB[13] ends after it, 07C6)
; KEY_RS: "R/S" handler (slot 0019)
0410: 1F9C  JC 07DE           ; KEY_RS slot target
; KEY_BST: "BST" handler (slot 0015): code 5 in the 0x0B10 bank → 0B15 →
; 0EBD: step − 1 (cache reload), redisplay.
0411: 0A57  MOV R5,#5
0412: 1B49  JC 026E
; AOS_CONTINUE: reduce-loop continuation after an executed operation (slots
; 00C5/00C9, 050F, 0547/0549): restore the caller's fA[1], bring the control
; word back from E, loop again.
; Δ [REORG] moved here from TI-59 015F–0162 (same code).
0413: 0014  SWAP fA[1],fB[1]  ; restore the caller's fA[1] (parked in fB[1] at 01C2)
0414: 01D7  A<>E ALL          ; A := control word, E := result of the operation
0415: 01D2  A<>B ALL          ; B := control word
0416: 1CFF  JC 0197           ; → reduce-loop test
; ENTRY DISPLAY BUILD, second part (from 02E9: EE layout, base position 5;
; from 02E1 into 0418 with R5 = 3: plain layout): decimal-point position and
; sign marker, then the digit-position loop: slide D and B one BCD place per
; pass while A counts the position up; exit when A reaches the field limit
; (IO=A-xC sets carry). Then INV handling and the redisplay tail.
; Δ [REORG] moved here from TI-59 02F3–030E (same code).
0417: 0A57  MOV R5,#5         ; EE layout: decimal point base position 5
0418: 02F3  B=R5 DPT
0419: 0283  B=A+B DPT         ; decimal point position = base + digits after the point
041A: 0020  TST fA[2]         ; mantissa negative?
041B: 0A37  MOV R5,#3         ; blank sign …
041C: 1804  JC 041E           ; fA[2] selects between two field widths (#3 vs #6)
041D: 0A67  MOV R5,#6         ; … or minus
041E: 09F3  B=R5 MANT         ; sign marker at nibble 3
041F: 0206  D=A DPT           ; keep the digits-after-point count
0420: 0A27  MOV R5,#2
0421: 02F0  A=R5 DPT          ; A[0] := 2: position counter
0422: 0C76  D=SLD MAEX        ; slide the digit marker …
0423: 0953  B=SLB MANT        ; … and the sign marker one place left …
0424: 0300  A=A+1 DPT1        ; advance position counter
0425: 0409  IO=A-xC DPTC      ; … until position 12, or …
0426: 1806  JC 0429           ; reached the limit → leave the loop
0427: 0289  IO=A-B DPT        ; … until past the decimal point
0428: 100D  JNC 0422          ; otherwise keep scanning
0429: 0230  A=D DPT           ; restore the digits-after-point count in A[0]
042A: 00A8  TST fB[10]        ; transient prefix mark set (0266)?
042B: 00AA  CLR fB[10]
042C: 1004  JNC 042E          ; yes → keep INV
042D: 0082  CLR fA[8]         ; any other key cancels INV
042E: 09B9  IO=A-D MANT       ; digits left of the marker?
042F: 13B6  JNC 060A          ; no → done, go idle (060A)
0430: 0953  B=SLB MANT        ; yes → slide sign and digit markers further left
0431: 0976  D=SLD MANT
0432: 1809  JC 042E
0433: 0033  TOG fA[3]         ; divide: negate the divisor's exponent, then add exponents
0434: 0114  C=B ALL           ; C := left operand (multiplicand / dividend)
0435: 0903  B=A MANT          ; B := right operand mantissa (multiplier / divisor)
0436: 002C  CMP fA[2],fB[2]   ; result sign = XOR of the signs
0437: 0022  CLR fA[2]
0438: 1004  JNC 043A
0439: 0021  SET fA[2]
043A: 003C  CMP fA[3],fB[3]   ; exponent signs equal?
043B: 1D88  JC 06FF           ; no → subtract the exponents (06FF, moved loop)
043C: 0680  A=A+B EXP         ; yes → add them …
043D: 1D8A  JC 0702           ; … no carry → multiply / divide loops (0702)
; ARITH_EXIT: shared arithmetic exit. 043E marks an exponent overflow (fA[4]).
; 043F: advance the continuation parked in SR by one slot (SR = the slot being
; executed, set at 02C9/02CA), then NUM_NORM (or OVFL_CLAMP on overflow) and
; return to that next slot. NORM_CALL (0442) is the same code entered from a
; slot directly. In argument mode (fB[12]) only normalizes (0236).
043E: 0041  SET fA[4]         ; mark: overflow exit
043F: 00C8  TST fB[12]        ; ARITH_EXIT
0440: 1415  JNC 0236
0441: 0A0D  SWAP KR,SR
0442: 0A04  INC KR            ; NORM_CALL: continuation := next table slot (+0x10 in KR)
0443: 0A0D  SWAP KR,SR        ; … parked in SR
0444: 0040  TST fA[4]
0445: 1C2B  JC 0230           ; no overflow → NUM_NORM, return to the next slot via 02C9
0446: 0042  CLR fA[4]
0447: 1BE7  JC 0254           ; overflow → OVFL_CLAMP, error blink
; LOAD_PI (slots 0526/0527, 052B/052C): 044A sets A := π, 044B adds π again
; (A := 2π). Constant 14 (KR[8] set by the 02C4 convention + index 6).
0448: 0085  SET KR[8]
0449: 0051  SET fA[5]
044A: 01D8  A=0 ALL           ; A := 0 …
044B: 0A67  MOV R5,#6         ; … + constant 14 = π
044C: 0A18  MOV KR[4..7],R5
044D: 0022  CLR fA[2]
044E: 0CC0  A=A+CON MAEX
044F: 005A  CLR fB[5]
0450: 1F6C  JC 0806           ; → ARITH_EXIT (next slot)
; KEY_PR: "P→R" (2nd x⇄t, slot 0073): entry step 284 of the keycode ROM, or
; with INV 250 (R→P, 04C3).
; Δ [HW] TI-59 0459–0461 removed: the second card-path gate of the idle loop's
; card-switch poll and the Write / card-inserted entry into the card sequence.
; No card reader: nothing enters a card sequence, and Write (slot 0069) only
; redisplays ("5 Write" → 5., traced).
0451: 0080  TST fA[8]         ; INV?
0452: 10E2  JNC 04C3          ; yes → entry 250
0453: 0A47  MOV R5,#4         ; entry 284: digits 4, 8, 2 …
0454: 02F3  B=R5 DPT
0455: 0A87  MOV R5,#8
0456: 06F3  B=R5 EXP
0457: 0153  B=SLB ALL
0458: 0A27  MOV R5,#2
0459: 09F3  B=R5 MANT
; KEYPROG_LAUNCH tail: entry step in B[3..5], then FN_ENTRY bank KR[8]+KR[9]
; code 13 → slots 053D (normalize) / 053E (→ 0927 → launch prologue 0A3F,
; return push 0D33, transfer 0863 with Prg Src Flag 8). Trace-confirmed for
; Σ+, INV Σ+, x̄, σ, P→R, R→P, D.MS, Op 11–15 (headless harness).
045A: 0153  B=SLB ALL         ; entry step into position
045B: 01D7  A<>E ALL
045C: 0150  A=SLB ALL
045D: 01D7  A<>E ALL
045E: 0AD7  MOV R5,#13        ; slot 053D
045F: 18D5  JC 03F5
; Σ+ key (2nd slot 0087 → 0460): entry step 192 (Σ+) or with INV 213 (Σ−).
0460: 0080  TST fA[8]         ; INV?
0461: 1060  JNC 0491          ; yes → entry 213
0462: 0A27  MOV R5,#2         ; entry 192: digits 2, 9, 1 …
0463: 01F3  B=R5 ALL
0464: 0A97  MOV R5,#9
0465: 06F3  B=R5 EXP
0466: 0153  B=SLB ALL
0467: 05D3  B=LOAD LLSD1
0468: 181D  JC 045A
; Fix n (slot 00D6): SCOM[0] nibble 0 := n + 2 (0 for INV Fix and Fix 9),
; then redisplay. Trace-confirmed (Fix 0/1/2/5/8, INV Fix).
0469: 01D7  A<>E ALL
046A: 02DE  D=0 DPT
046B: 0500  A=A+1 LLSD1       ; n = 9 → floating …
046C: 1006  JNC 046F
046D: 02F0  A=R5 DPT
046E: 0306  D=A+1 DPT1        ; … else n + 2
046F: 01D7  A<>E ALL
0470: 02DB  B=0 DPT
0471: 0A1F  RCLF              ; SCOM[0] …
0472: 0CD6  D=LOAD MAEX
0473: 0A0F  STOF
; Δ [HW] new (no TI-59 counterpart): Fix is also kept in constant memory.
; Read E000 (address = SCOM[9] nibble 1 with 0xC), replace its nibble 0 with
; the new Fix setting and write it back; the power-on restore (03A4–03A6)
; brings it back. INV Fix (0470, from 01EC) is saved the same way.
0474: 0131  IO=D ALL          ; … nibble 0 := Fix setting
0475: 0A97  MOV R5,#9
0476: 01F3  B=R5 ALL          ; B := 9 → SCOM[9] …
0477: 0111  IO=B ALL
0478: 0A1F  RCLF
0479: 06D3  B=LOAD EXP        ; … B[1] := high nibble of the E000 address (B[2], the security
                              ;   nibble, is not part of the address) …
047A: 04D3  B=LOAD DPTC       ; … B[0] := 0xC: B = E000's raw address (0x3C)
047B: 0111  IO=B ALL          ; address of E000 …
047C: 0A86  MEMRD
047D: 0CD6  D=LOAD MAEX       ; D[15..1] := E000[15..1], D[0] = the new Fix
047E: 1802  JC 047F ; clear COND
047F: 0111  IO=B ALL          ; address of E000 …
0480: 0A76  MEMWR
0481: 0131  IO=D ALL          ; … E000 := D: signature and partition unchanged, Fix updated
0482: 1812  JC 048B
; Adv (2nd ., 2nd-table slot 0089) and the printer's ADV button (remapped to
; the same slot at 0678–0687): only with a printer → 084B → 0C20 →
; PAPER_ADVANCE 0F4E.
; Δ [HW] TI-59 0487: printer-present on KP at digit 10 (WAIT D11), see 00A9.
0483: 0AB0  WAIT D11          ; printer present? (the next instruction samples digit 10)
0484: 08FB  KEY [P]
0485: 178C  JNC 084B          ; yes → advance
0486: 1BC9  JC 02A2
; INV EE (0115): leave scientific display and exponent entry.
0487: 00FA  CLR fB[15]
0488: 00F2  CLR fA[15]
0489: 0058  TST fB[5]
048A: 1AD9  JC 031E
048B: 0051  SET fA[5]
048C: 1CB5  JC 0232
048D: 0081  SET fA[8]         ; CP (fA[8] marks CP) …
048E: 0A17  MOV R5,#1         ; CMs / CP: fn 1 in the KR[9] bank → slots 0521/0522 (→ 084F →
                              ;   0BE6 → CLEAR_MEM 0FCC)
048F: 0095  SET KR[9]         ; FN_ENTRY in the KR[9] bank (0x0520+fn)
0490: 1D0F  JC 0209
0491: 0A37  MOV R5,#3         ; INV Σ+: entry 213 …
0492: 02F3  B=R5 DPT
0493: 0A17  MOV R5,#1
0494: 1862  JC 04C5
; COND_TRANSFER (slots 00B9, 00BD, 00C1, 00F9): the preceding slot left the
; test result in fA[9]; INV (saved in fB[8]) inverts it. True → read the
; transfer address (label or 3-digit step) and branch (0850 …); false →
; skip the address operand and continue with the next step.
0495: 1F76  JC 0850
0496: 0051  SET fA[5]         ; Int / INV Int result (slot 0520):
0497: 0080  TST fA[8]         ; INV Int?
0498: 0133  B=D ALL           ; B := original X
0499: 000F  MOV fB[1..4],R5
049A: 10B7  JNC 043F          ; no → Int result
049B: 1ACD  JC 0335           ; yes → frac = X − Int(X)
049C: 1FE7  JC 00A9
; Angle-unit keys: SCOM[13] nibble 0 := 0xC (Rad, 049D), 1 (Grad, 049F),
; 0 (Deg, 02A7). Trace-confirmed.
049D: 04D6  D=LOAD DPTC       ; Rad: 0xC
049E: 1804  JC 04A0
049F: 03D6  D=LOAD DPT1       ; Grad: 1
04A0: 0AD7  MOV R5,#13        ; SCOM[13] nibble 0 := D[0] …
04A1: 02F3  B=R5 DPT
04A2: 0111  IO=B ALL
04A3: 0A1F  RCLF
04A4: 0CD6  D=LOAD MAEX
04A5: 1C15  JC 029B
04A6: 1F58  JC 0852           ; GTO (slot 00F2): transfer (STEP_TO_REG via 0852)
04A7: 1C9C  JC 06F5           ; Dsz (slot 00F6): decrement (06F5)
04A8: 00A0  TST fA[10]        ; CP / CMs (slot 0521): flush a pending trace line …
04A9: 18CF  JC 0442
04AA: 0AA8  PRT.GO
04AB: 00A2  CLR fA[10]
04AC: 18D5  JC 0442
; REG_ACCESS entry (slots 00ED STO, via 02D2 for reads): fA[9] clear = write
; X, set = read into A. → 084A → 0B10 → REG_ADDR (0D15).
04AD: 0092  CLR fA[9]         ; STO: write
04AE: 1F38  JC 084A
04AF: 1FCA  JC 0894           ; If flg: test the user flag (0C68)
04B0: 0A47  MOV R5,#4         ; St flg / INV St flg: sequence bank 0x0B10, code 4 …
04B1: 1C83  JC 0270           ; … → 0B14 → 0E0D → 11E1 → FLAG_OP
; x⇄t (slot 00EF, fA[5] set) / x=t, x≥t compare (04B3): t lives in SCOM[11].
; Trace-confirmed (5 x⇄t; x=t / x≥t programs).
04B2: 0051  SET fA[5]         ; x⇄t (not a compare)
04B3: 0A06  MOV R5,fA[1..4]   ; x=t / x≥t: compare X with t (SCOM[11])
04B4: 02F0  A=R5 DPT
04B5: 0103  B=A ALL           ; B := X with its flags
04B6: 01D7  A<>E ALL
04B7: 032C  C=C-1 DPT1        ; C[0] = 0xC − 1 = 11 → SCOM[11] (t) …
04B8: 0121  IO=C ALL
04B9: 0A1F  RCLF
04BA: 01D0  A=LOAD ALL        ; … A := t
04BB: 0007  MOV fA[1..4],R5
04BC: 04D0  A=LOAD DPTC
04BD: 0050  TST fA[5]         ; compare?
04BE: 1847  JC 049B           ; yes → X − t via ADD (0335), tested by the next slot
04BF: 0121  IO=C ALL
04C0: 0A0F  STOF              ; x⇄t: t := old X …
04C1: 0111  IO=B ALL
04C2: 1D19  JC 0236           ; … X := old t, normalize and show
04C3: 02DB  B=0 DPT           ; R→P: entry 250 …
04C4: 0A57  MOV R5,#5
04C5: 06F3  B=R5 EXP
04C6: 18DF  JC 0457
04C7: 00A1  SET fA[10]
; ARG_TWO_DIGITS (slots 00D8/00DD/00E1/00E6/00EC/0102): collect a 2-digit
; register / Op number. X is parked in E meanwhile.
04C8: 01D7  A<>E ALL          ; X → E (restored when the sequence resumes)
04C9: 0A17  MOV R5,#1         ; two digits
04CA: 1D4F  JC 0223           ; → ARG_COLLECT_SETUP at 0223 (COND at rest after the jump: no
                              ;   running increment)
04CB: 006A  CLR fB[6]         ; error entry from AOS_PUSH (0192): no fresh operand …
04CC: 0099  SET fB[9]         ; … ERROR (also the 9th-level overflow, 01CD)
04CD: 04D4  C=LOAD DPTC       ; result exit after the AOS (0203)
04CE: 1887  JC 048B
04CF: 0051  SET fA[5]         ; digit keycode from a program (083A): result display, → key
                              ;   pipeline
04D0: 1B70  JC 0688
; Exc step (slot 00E8): register value becomes X, old X is written back.
04D1: 0A06  MOV R5,fA[1..4]
04D2: 02F0  A=R5 DPT
04D3: 01D7  A<>E ALL
04D4: 0104  C=A ALL
04D5: 000F  MOV fB[1..4],R5
; Store-back step (slots 00DB SUM, 00E4 Prd): write the result into the
; register addressed in E.
04D6: 01D7  A<>E ALL
04D7: 0201  IO=A DPT
04D8: 0007  MOV fA[1..4],R5
04D9: 04D0  A=LOAD DPTC
04DA: 005A  CLR fB[5]
04DB: 1D1E  JC 076A           ; → 0A23 write
04DC: 0ED3  B=LOAD MMSD1
04DD: 1CA0  JC 072D
04DE: 14F5  JNC 0264
04DF: 14AD  JNC 0289          ; RST abort from the library fetch (082A) → RST_ABORT 0289
04E0: 1FDA  JC 08CD
04E1: 1FDA  JC 08CE
; DISPLAY_PEEK (from 07D0): light the display — wait for the printer,
; SET.IDLE, count KR up to KR[13] (≈256 instruction cycles), back to active
; mode and continue the run.
; Same loop as on the TI-59. Derived: the TI-58C does not slow idle-state
; instructions, so the display stays lit for about a quarter of the TI-59's
; time (headless, weighted cycles of a program Pause: 4096 vs 15331).
04E2: 0A0C  MOV KR,EXT[4..15]
04E3: 00C5  SET KR[12]        ; KR := 0x1000: counts to 0x2000
04E4: 0619  IO=-B EXP
04E5: 1806  JC 04E8
04E6: 0940  A=SLA MANT
04E7: 0C40  A=SLA MAEX
; Pause (keycode 66) enters DISPLAY_PEEK here with KR starting at 0: the
; display is held for 512 loop passes (twice as long as the GTO peek).
04E8: 0A98  PRT.STEP
04E9: 0A0B  TST.BUSY
04EA: 1005  JNC 04E8
04EB: 0213  B=B DPT           ; reload R5 = dp digit before SET.IDLE (R5 is the display's
                              ;   decimal-point position; cf. 0647)
04EC: 0A10  WAIT D1
04ED: 0A09  SET.IDLE          ; display on
04EE: 0A04  INC KR            ; hold it …
04EF: 0AD5  TST KR[13]
04F0: 1805  JC 04EE
04F1: 0A01  CLR.IDLE          ; … display off, continue
04F2: 0619  IO=-B EXP         ; EE-image realign, same idiom as 065B–065E:
04F3: 1806  JC 04F6           ; if the display image carries exponent digits
04F4: 0C48  A=SRA MAEX        ; (B EXP ≠ 0), shift A's mantissa right twice
04F5: 0948  A=SRA MANT        ; back into the mantissa/EXP working layout
04F6: 0050  TST fA[5]
04F7: 15AE  JNC 07CE
04F8: 00E8  TST fB[14]        ; key pending from an argument terminator?
04F9: 1756  JNC 08A4          ; yes → execute it (08A4 → 0BF5 → STEP_DISPATCH)
04FA: 1D2F  JC 0263
04FB: 1FB4  JC 08D5
; Unused filler: A=A ALL (no-op) words, never executed. The code in front of
; the function table is four words shorter than on the TI-59, and
; FN_SEQ_TABLE stays at 0500.
; Δ [REORG] new, no TI-59 counterpart.
04FC: 0100  A=A ALL
04FD: 0100  A=A ALL
04FE: 0100  A=A ALL
04FF: 0100  A=A ALL
; ═══════════════════════════════════════════════════════════════════════════
; FUNCTION SEQUENCE TABLE  (0x0500–0x0545) — threaded like OP_SEQ_TABLE.
; Entered from FN_ENTRY (0209): KR = 0x5000 | code<<4 (+0x100 for FN_ENTRY_KR8
; (0208), +0x200 when KR[9] is also set, +0x400 via KR[10]) → slot 0x0500 +
; code + 0x10·tag. A "JC 0442" slot normalizes X; 0442's INC KR makes the
; return land on the following slot. Slot runs (trace-confirmed, headless
; harness scenarios in tools/headless/coverage.py):
;   0500–0506  arc functions (INV sin/cos/tan) and R→P
;   0507–0509  x²            050A–050B  1/x          050C–050F  y^x / root
;   0510–0511  √x            0512–0514  ln x         0515–0517  e^x
;   0518–051A  10^x          051B–051D  log x        051E–0520  Int/frac, D.MS
;   0521–0522  CP / CMs      0523–0533  sin/cos/tan, P→R
;   0534–0536  SBR           0537–0539  List         053A–053C  Pgm
;   053D–053E  shared by D.MS, P→R, Σ+, x̄   053F–0545  Op
; ═══════════════════════════════════════════════════════════════════════════
0500: 197D  JC 0442           ; arc functions / R→P: normalize …
0501: 1F9C  JC 08CF           ; … atan → CORDIC directly; asin/acos: …
0502: 1BC3  JC 0321           ; … 1 − x² …
0503: 1E1E  JC 0812           ; … √(1 − x²) …
0504: 1A7B  JC 03C7           ; … tan-form argument x/√(1−x²) (or its inverse for acos) …
0505: 1FD4  JC 08EF           ; … CORDIC backwards: angle in radians …
0506: 1994  JC 05D0           ; … radians → angle unit, result
0507: 198B  JC 0442           ; x²: normalize …
0508: 0051  SET fA[5]         ; result to be displayed
0509: 1CD0  JC 0771           ; X × X (0771: B := X → MULDIV)
050A: 1991  JC 0442           ; 1/x: normalize X, return to 050B …
050B: 1CC2  JC 076C           ; … → RECIP (1 ÷ X)
050C: 1C3E  JC 072B           ; y^x (AOS exec, slot 00CC): ln y …
050D: 1D58  JC 07B9           ; … × x (÷ x for the root) …
050E: 1BA2  JC 06DF           ; … e^(result) …
050F: 19F9  JC 0413           ; … back into the AOS reduce loop
0510: 199D  JC 0442           ; √x: normalize …
0511: 1E00  JC 0811           ; … → SQRT
0512: 19A1  JC 0442           ; ln x: normalize …
0513: 0051  SET fA[5]
0514: 1C48  JC 0738           ; … → LN
0515: 19A7  JC 0442           ; e^x (INV lnx): normalize …
0516: 0051  SET fA[5]
0517: 1B98  JC 06E3           ; … → EXP
0518: 19AD  JC 0442           ; 10^x (INV log): normalize …
0519: 19D8  JC 0605           ; … × ln 10 …
051A: 1809  JC 0516           ; … then e^x
051B: 19B3  JC 0442           ; log x: normalize …
051C: 1C38  JC 0738           ; … LN …
051D: 1FBC  JC 08FB           ; … ÷ ln 10
051E: 19B9  JC 0442           ; Int / INV Int / D.MS: normalize …
051F: 1FC6  JC 0902
0520: 1915  JC 0496
0521: 18F3  JC 04A8           ; CP / CMs
0522: 1E5A  JC 084F
0523: 19C3  JC 0442           ; sin / cos / tan / P→R: normalize …
0524: 195A  JC 05D1           ; … angle unit → radians
0525: 1DB8  JC 0801           ; … D := θ
0526: 19B9  JC 044A           ; … A := π …
0527: 19B9  JC 044B           ; … A := 2π
0528: 1ABB  JC 03CB           ; … θ ÷ 2π …
0529: 1FB8  JC 0905           ; … fractional part (whole turns dropped) …
052A: 1DAE  JC 0801
052B: 19C3  JC 044A
052C: 19C3  JC 044B
052D: 1AC3  JC 03CC           ; … × 2π: θ reduced to [0, 2π)
052E: 1F7C  JC 08EC           ; … octant fold + CORDIC → t = tan θ (tan ends here)
052F: 1AF8  JC 06AB           ; … sin/cos: t·t (cos: numerator 1) …
0530: 1C0B  JC 032B           ; … 1 + t² …
0531: 1DC2  JC 0812           ; … √(1 + t²) …
0532: 0051  SET fA[5]
0533: 1AD1  JC 03CB           ; … sin = t / √(1+t²), cos = 1 / √(1+t²)
0534: 19E5  JC 0442           ; SBR: normalize …
0535: 1DAF  JC 025E
0536: 1FAE  JC 090D
0537: 1919  JC 04AB           ; List
0538: 1FCC  JC 091E
0539: 1FC6  JC 091C
053A: 19F1  JC 0442           ; Pgm nn: normalize …
053B: 18E9  JC 04C7           ; … collect the program number
053C: 1FC2  JC 091D           ; … validate and select (091D → PGM_SELECT)
053D: 19F7  JC 0442
053E: 1FD2  JC 0927
053F: 0A27  MOV R5,#2         ; Op nn
0540: 00A5  SET KR[10]
0541: 1E71  JC 0209
0542: 192F  JC 04AB
0543: 1F7E  JC 0902
0544: 195B  JC 0497
0545: 1FDE  JC 0934
0546: 0020  TST fA[2]
0547: 1A69  JC 0413
0548: 0FDC  C=-1 MAEX1
0549: 126D  JNC 0413
054A: 03D3  B=LOAD DPT1       ; Op 11 variant flag …
054B: 1F99  JC 017F           ; … → x̄ launch stub
; ═══════════════════════════════════════════════════════════════════════════
; DISP_FORMAT  (0x054C–0x05B8) — turn the normalized X (A = C) into the
; display image for a RESULT. Trace-confirmed (5÷3, 2÷3 with Fix 0/1/2/5/8,
; Eng, EE). Entered from the NUM_NORM epilogue (02C7) when fA[5] (result to
; show) or fA[10] (trace line pending) is set; returns there via 05BC/05BE or
; 059F/05A0. Format state:
;   SCOM[0] nibble 0 = Fix: n + 2 for Fix n (0–8), 0 = floating (Fix 9 /
;                      INV Fix)
;   fB[15] = scientific (EE) display, fB[7] = engineering (Eng) display
; Two passes, told apart by fB[5]:
;   pass 1  shift the mantissa to the display field (A[3..13], A[0] = digit
;           position counter), choose the layout (fixed / sci / eng, 0563–
;           0591; values that don't fit switch to sci, 0942), round with +5
;           at the first hidden digit (DISP_ROUND 05B9), SET fB[5] and
;           renormalize (0236) — the rounding carry may change the exponent.
;   pass 2  same layout again, then strip trailing zeros after the point
;           (0594–059B), then the trace-print check (05A8) and the display
;           control image is built by the redisplay tail (02A2 → 0264 → 02D5
;           → DISP_REBUILD).
; While a keycode sub-program or library program runs (Prg Src Flag in
; SCOM[0] nibble 3 non-zero, 054F–0553) formatting is skipped (0895).
; ═══════════════════════════════════════════════════════════════════════════
054C: 00A0  TST fA[10]        ; trace line pending …
054D: 00A8  TST fB[10]        ; … or LRN / reformat-only marker → always format
054E: 100C  JNC 0554
054F: 0A1F  RCLF              ; SCOM[0] (bus zero → row 0) …
0550: 09D3  B=LOAD MANT
0551: 06F3  B=R5 EXP          ; … B[1] := nibble 3 = Prg Src Flag
0552: 0619  IO=-B EXP         ; non-zero = keycode / library program running
0553: 1684  JNC 0895          ; yes → no display formatting (0895)
0554: 0948  A=SRA MANT        ; mantissa → display field (MSD in nibble 13)
0555: 0948  A=SRA MANT
0556: 0AA7  MOV R5,#10
0557: 02F0  A=R5 DPT          ; A[0] := 10: digit position counter
0558: 0103  B=A ALL           ; B := working copy …
0559: 0A87  MOV R5,#8
055A: 02F3  B=R5 DPT
055B: 00E2  CLR fA[14]
055C: 095B  B=SRB MANT        ; … two digits lower (sci/eng mantissa room)
055D: 095B  B=SRB MANT
055E: 0A1F  RCLF              ; SCOM[0] …
055F: 02D6  D=LOAD DPT        ; … D[0] := Fix setting (n+2, 0 = floating)
0560: 0050  TST fA[5]
0561: 1004  JNC 0563
0562: 02DE  D=0 DPT           ; trace-only formatting: floating
0563: 00F8  TST fB[15]        ; sci …
0564: 0078  TST fB[7]         ; … or eng display?
0565: 183C  JC 0583           ; neither → fixed-point layout (0583)
0566: 0110  A=B ALL
0567: 0078  TST fB[7]         ; eng?
0568: 1828  JC 057C           ; sci → 057C
; Engineering: reduce the exponent to a multiple of 3, moving the remainder
; into the mantissa (more integer digits).
0569: 0A37  MOV R5,#3
056A: 06F6  D=R5 EXP          ; D[1..2] := 3
056B: 06B8  A=A-D EXP         ; exponent mod 3 …
056C: 1803  JC 056B
056D: 06B0  A=A+D EXP
056E: 1002  JNC 056F ; clear COND
056F: 0709  IO=A-1 EXP1       ; remainder 0?
0570: 06D2  A<>B EXP
0571: 1016  JNC 057C
0572: 0030  TST fA[3]         ; negative exponent: round towards the next lower multiple
0573: 180C  JC 0579
0574: 068B  B=A-B EXP
0575: 06D2  A<>B EXP
0576: 06B0  A=A+D EXP
0577: 068B  B=A-B EXP
0578: 1804  JC 057A
0579: 0688  A=A-B EXP
057A: 015B  B=SRB ALL
057B: 0288  A=A-B DPT         ; integer digits += remainder
; Fix (and sci/eng) digit limit: drop digits beyond the Fix setting.
057C: 0239  IO=-D DPT         ; Fix active?
057D: 182A  JC 0592           ; no → round
057E: 02B9  IO=A-D DPT        ; more digits than Fix allows?
057F: 1026  JNC 0592
0580: 0948  A=SRA MANT        ; drop one …
0581: 0308  A=A-1 DPT1
0582: 1809  JC 057E
; Fixed-point layout: move the decimal point by the exponent.
0583: 0030  TST fA[3]         ; negative exponent?
0584: 1806  JC 0587
0585: 0940  A=SLA MANT
0586: 0300  A=A+1 DPT1
0587: 0709  IO=A-1 EXP1       ; exponent left?
0588: 1F64  JC 093A           ; yes → shift one place (093A) and loop
0589: 0032  CLR fA[3]
058A: 0239  IO=-D DPT         ; Fix?
058B: 101B  JNC 057E          ; yes → apply the digit limit
058C: 0058  TST fB[5]         ; pass 2?
058D: 1806  JC 0590
058E: 0509  IO=A-1 LLSD1
058F: 1F66  JC 0942
0590: 0B09  IO=A-5 MLSD5      ; pass 1: rounding digit ≥ 5? (IO only)
0591: 1762  JNC 0942
0592: 0058  TST fB[5]         ; pass 1 → round (05B9)
0593: 184C  JC 05B9
0594: 0948  A=SRA MANT        ; pass 2: strip trailing zeros after the point …
0595: 0308  A=A-1 DPT1
0596: 0239  IO=-D DPT         ; … unless Fix is set …
0597: 100A  JNC 059C
0598: 0509  IO=A-1 LLSD1      ; … stop at a non-zero digit …
0599: 1806  JC 059C
059A: 0309  IO=A-1 DPT1       ; … or at the decimal point
059B: 180F  JC 0594
059C: 00A8  TST fB[10]        ; reformat-only (fB[10] borrowed outside LRN, e.g. EE/Fix on a
                              ;   result)?
059D: 00AA  CLR fB[10]
059E: 1806  JC 05A1
059F: 0059  SET fB[5]         ; yes: result displayed, return to the caller
05A0: 1DAF  JC 02C9
05A1: 0A1F  RCLF              ; printer / trace checks (D[MSD] test as at 0695)
05A2: 09D6  D=LOAD MANT
05A3: 09D5  C<>D MANT
05A4: 0E2C  C=C-1 MMSD1       ; (flag 9 test as at 0695)
05A5: 0E2C  C=C-1 MMSD1
05A6: 09D5  C<>D MANT
05A7: 180A  JC 05AC
; Trace-line trigger (trace-checked on the TI-58C with printer and TRACE:
; 5 + 3 = prints "5. +", "3. =", "8."): once an operation key's processing
; gets here, re-check the pending trace record (fA[10], queued at the 0688
; gate) and re-poll the printer TRACE switch (KP at digit 15, WAIT D0). With
; both set, the branch at 05AE runs (via 08BA→0BE5→0FCD→13A1→152B) into the
; numeric print formatter: it appends the display value to the already-queued
; key symbol and PRT.GO at 0EFD finally prints the line ("0.     +").
05A8: 00A0  TST fA[10]        ; trace record pending?
05A9: 0A00  WAIT D0
05AA: 08FB  KEY [P]           ; printer TRACE switch still on?
05AB: 1808  JC 05AF
05AC: 0000  TST fA[0]
05AD: 00C8  TST fB[12]
05AE: 1E18  JC 08BA           ; → print the queued trace line
05AF: 0A06  MOV R5,fA[1..4]   ; cleanup: keep only the sign bits of fA …
05B0: 0000  TST fA[0]
05B1: 0A02  CLR fA
05B2: 1804  JC 05B4
05B3: 0001  SET fA[0]
05B4: 0007  MOV fA[1..4],R5   ; DISP_FORMAT cleanup: keep the sign bits
05B5: 0012  CLR fA[1]
05B6: 0042  CLR fA[4]
05B7: 0A0D  SWAP KR,SR
05B8: 1E2D  JC 02A2           ; → redisplay tail (control image, idle)
05B9: 0B00  A=A+5 MLSD5       ; DISP_ROUND: +5 at the first hidden digit
05BA: 0948  A=SRA MANT        ; drop it …
05BB: 0940  A=SLA MANT        ; … (guard digit now 0)
05BC: 0A0D  SWAP KR,SR
05BD: 0059  SET fB[5]         ; pass 1 done
05BE: 1F11  JC 0236           ; renormalize (a carry 9.99… → 10.0… adjusts the exponent), then
                              ;   pass 2
; Argument-key classification (from 095C / 098C while fB[12] is set): digits
; feed the collector (0970 → 06A9 → DIGIT_SLIDE → 02F6 → 06BE); other keys
; either complete/abort the pending sequence or are handled specially
; (0773, 097D, 0981 — e.g. Ind, labels, 2nd keys).
05BF: 0AB5  TST KR[11]        ; (in LRN every non-editing key ends up stored as its keycode: STO
                              ;   B → 42 12)
05C0: 1366  JNC 0773
05C1: 0AA5  TST KR[10]
05C2: 1776  JNC 097D
05C3: 0A95  TST KR[9]
05C4: 1F7A  JC 0981
05C5: 0A75  TST KR[7]
05C6: 1808  JC 05CA
05C7: 0A85  TST KR[8]
05C8: 0A55  TST KR[5]
05C9: 1F4E  JC 0970
05CA: 0A75  TST KR[7]
05CB: 1F42  JC 096C
05CC: 0A55  TST KR[5]
05CD: 0A45  TST KR[4]
05CE: 1F44  JC 0970
05CF: 1748  JNC 0973
; ═══════════════════════════════════════════════════════════════════════════
; ANGLE UNIT CONVERSION  (0x05D0–0x05DC, 0x0944–0x0953) — trace-confirmed
; (sin 30 in DEG, sin 1 in RAD, sin 50 in GRAD, INV sin .5). The unit is
; SCOM[13] nibble 0: 0 = DEG, 1 = GRAD, 0xC = RAD. 05D1 converts X to
; radians (slot 0524, before sin/cos/tan); 05D0 sets fA[5] first and converts
; radians back to the unit (arc results, slot 0506).
;   DEG:  ÷ / × constant 15 = 180/π                      (0944)
;   GRAD: × / ÷ constant 13 used as π/200 — the ROM stores it as
;         1.5707963…E01 (5π) and flips/raises its exponent to 10^−2 (094A)
;   RAD:  unchanged
; ═══════════════════════════════════════════════════════════════════════════
05D0: 0051  SET fA[5]         ; radians → angle unit (arc results)
05D1: 02D7  A<>E DPT          ; units → radians: A[0] := 0xD → SCOM[13] …
05D2: 0AD7  MOV R5,#13
05D3: 02F0  A=R5 DPT
05D4: 0101  IO=A ALL
05D5: 0A1F  RCLF
05D6: 02D0  A=LOAD DPT        ; … A[0] := angle unit
05D7: 0309  IO=A-1 DPT1       ; DEG (0)?
05D8: 16D8  JNC 0944          ; yes → 0944
05D9: 0409  IO=A-xC DPTC      ; GRAD (1)?
05DA: 16E0  JNC 094A          ; yes → 094A
05DB: 02D7  A<>E DPT          ; RAD: no conversion
05DC: 1B3B  JC 043F           ; → ARITH_EXIT
05DD: 0A1F  RCLF              ; digit entry while a program runs (031F, fB[0]): no display
                              ;   rebuild
05DE: 09D3  B=LOAD MANT
05DF: 06F3  B=R5 EXP
05E0: 0619  IO=-B EXP
05E1: 11AE  JNC 06B8
05E2: 1E13  JC 02D9
05E3: 0A65  TST KR[6]
05E4: 0A55  TST KR[5]
05E5: 0A45  TST KR[4]
05E6: 1776  JNC 09A1
05E7: 0082  CLR fA[8]
05E8: 00D2  CLR fA[13]
05E9: 1FF9  JC 01ED
05EA: 1B59  JC 043E
05EB: 0A55  TST KR[5]
05EC: 1F9E  JC 09BB
05ED: 0A45  TST KR[4]
05EE: 1F6C  JC 09A4
05EF: 0080  TST fA[8]
05F0: 00D2  CLR fA[13]
05F1: 0082  CLR fA[8]
05F2: 1FA9  JC 021E
05F3: 0A27  MOV R5,#2
05F4: 02F6  D=R5 DPT
05F5: 07DE  D=-1 EXP1
05F6: 17D8  JNC 09E2
05F7: 1756  JNC 09A2          ; LRN digit (from 02F9) → encode and store
05F8: 1EA7  JC 02A5
05F9: 1FBF  JC 021A
; Unused filler: A=A ALL (no-op) words, never executed.
05FA: 0100  A=A ALL
05FB: 0100  A=A ALL
05FC: 0100  A=A ALL
05FD: 0100  A=A ALL
05FE: 0100  A=A ALL
05FF: 0100  A=A ALL
0600: 0100  A=A ALL
0601: 0100  A=A ALL
0602: 0100  A=A ALL
0603: 0C40  A=SLA MAEX
0604: 1F4E  JC 09AB
; 10^x prologue (slot 0519): X × ln 10, then e^x (051A → 0516).
0605: 0011  SET fA[1]         ; 08FC toggles fA[1] back → multiply
0606: 1DEC  JC 08FC
0607: 1EB1  JC 02AF           ; end of a sequence: → 02AF → 022F: normalize and display X
0608: 1395  JNC 043E
0609: 1ED5  JC 029F           ; R/S executed as a program step
; ═══════════════════════════════════════════════════════════════════════════
; PRE-IDLE CONDITION CHECKS  (0x060A, reached from 0x042F)
; Last gauntlet of flag tests before the calculator settles into its display/
; keyscan idle loop. Each branch targets a special-case handler; on a clean
; power-up none fire and execution reaches the idle loop at 0x0627.
; No SCOM backup to RAM happens on this path or in the idle loop (no MEMWR
; in 0600–09FF; traced: 0 MEMWR/MEMRD while idling) — the TI-58C writes its
; one persistent setting, Fix, through to RAM 60 when it is set (0480).
; ═══════════════════════════════════════════════════════════════════════════
060A: 0619  IO=-B EXP
060B: 1818  JC 0617
060C: 095B  B=SRB MANT
060D: 095B  B=SRB MANT
060E: 095B  B=SRB MANT
060F: 0C53  B=SLB MAEX
0610: 0C53  B=SLB MAEX
0611: 071B  B=-B EXP1
0612: 0C53  B=SLB MAEX
0613: 0619  IO=-B EXP         ; 2nd / INV in LRN mode (0265)
0614: 1806  JC 0617
0615: 0940  A=SLA MANT
0616: 0C40  A=SLA MAEX
0617: 0309  IO=A-1 DPT1
0618: 180A  JC 061D
0619: 0058  TST fB[5]
061A: 0048  TST fB[4]
061B: 1004  JNC 061D
061C: 02DB  B=0 DPT
061D: 0050  TST fA[5]
061E: 0052  CLR fA[5]
061F: 126F  JNC 04E8          ; fA[5] handler (not taken)
0620: 00E8  TST fB[14]
0621: 125F  JNC 04F2          ; fB[14] handler (not taken)
0622: 0008  TST fB[0]         ; program running?
0623: 1334  JNC 07BD          ; yes → RUN_LOOP instead of idling
; Drain the printer before idling: PRT.STEP advances one position, then spin on
; TST.BUSY until the (possibly absent) printer reports not-busy. At reset the
; printer is already idle, so this passes immediately: diffing the printer vs
; no-printer TI-59 traces shows this loop (and the whole reset path) runs
; identically either way — reset behaviour is fully printer-independent.
0624: 0DD6  D=LOAD MLSD1      ; D[3] := 1 (side effect: seeds the error-blink counter at 063F —
                              ;   the blink starts dark)
0625: 00DA  CLR fB[13]
0626: 0213  B=B DPT           ; reload R5 = dp digit before idling (cf. 04EB)
0627: 0A98  PRT.STEP          ; advance the printer one column
0628: 0A0B  TST.BUSY          ; here reading printer-busy (the FLG_BUSY half of TST.BUSY)
0629: 1005  JNC 0627          ; wait here until it finishes (no wait at reset); also guarantees
                              ;   the printer is not busy in the idle loop (064E)
; ═══════════════════════════════════════════════════════════════════════════
; MAIN IDLE LOOP — display multiplex + keyboard scan  (0x062A–0x0659, 0x0A25–0x0A30)
; The calculator's resting state and the first keyboard scan after reset.
; SET.IDLE hands the display to the hardware multiplexer. On the TI-58C the
; CPU keeps its full instruction rate while idle (384 kHz / 32 = 12 000
; instructions/s); the TI-59 drops to ¼ speed there. Hence the timings below.
;
; KEY...ALL HOLDs across digit slots until it reaches D0 (never sampled):
;   • no key down  → COND stays 1 → the following JC jumps on
;   • key detected → COND=0 and KR := row (KR[4..7]) + K-line (KR[8..10]).
; The printer-present line is KP at D10 on the TI-58C (TI-59: D0, the last row
; a scan-all samples, where the TI-59 discards it as "row 0"), so the scans
; here have to step around it.
;
; KEY ACCEPTANCE (trace-checked with the headless harness, TI-58C):
;   062D–063C — release gate on the way in (from reset or a finished key):
;       KEY [N,O,Q,S,T] ALL rows 14–1, KEY [P] at row 12 (printer PRINT),
;       KEY [P] ALL rows 9–1 — every line except KP at rows 10/11/13/14. A hit
;       is the previous key still held: back to 0627 until it is released, so
;       a held key never repeats. fA[11] runs the window twice (063A–063C).
;   0650/0651 — ARMING scan, rows 12–1, all lines. The steady-state idle pass
;       063D→0652 is 48 instructions (3 digit sweeps) ≈ 4.0 ms.
;   0653/0654 — CONFIRMATION scan one sweep later (16 instructions ≈ 1.3 ms;
;       TI-59 ≈ 4.5 ms); the key must still be down. 0656–0659 accept rows
;       1–9 and 12, discard 14/15 and send rows 10/11 — the printer-present
;       line — to 0A25, which rescans rows 9–1 as the real arming scan and
;       re-enters the confirmation scan at 0654 (with a printer attached the
;       idle pass is 80 instructions ≈ 6.7 ms).
; Every pass also polls two test lines (064A–064F): KN at D15 → self-test,
; KR line at D10 → program at 0x1800.
; ═══════════════════════════════════════════════════════════════════════════
; Δ [HW] TI-59 062A–0640, 0656–0660: scan windows rebuilt around the
; printer-present line at D10 (TI-59 D0) and the TI-59 card-switch poll
; (063C–0640, WAIT D11 + TST.BUSY → 0459) dropped — no card reader. The
; "row ≠ 0" TST KR[4..7] guards are gone (nothing is wired at D0 any more).
062A: 00B2  CLR fA[11]        ; release-gate pass toggle: first pass
062B: 0A10  WAIT D1           ; sync to digit 1
062C: 0A09  SET.IDLE          ; enter idle: hardware multiplexes the display (TI-58C: CPU keeps
                              ;   full speed)
; Release-gate window (run twice, see fA[11] at 063A): a key seen here is the
; previous one still held → 0627, wait for its release.
062D: 0AF0  WAIT D15          ; next instruction at digit 14
062E: 0824  KEY [N,O,Q,S,T] ALL ; rows 14–1, all lines except KP (printer-present at D10) and KR
062F: 1011  JNC 0627          ; key still held → wait for release
0630: 0AD0  WAIT D13
0631: 08FB  KEY [P]           ; row 12, KP = printer PRINT button
0632: 1017  JNC 0627          ; held → wait
0633: 0AA0  WAIT D10          ; next instruction at digit 9
0634: 08F3  KEY [P] ALL       ; KP on rows 9–1 (keyboard column 2), below the printer-present
                              ;   line
0635: 180A  JC 063A           ; no key → housekeeping
0636: 0A75  TST KR[7]         ; hit → 0627, unless row ≥ 12 (KR[6] and KR[7] set) …
0637: 1821  JC 0627           ; … which a scan of rows 9–1 never reports
0638: 0A65  TST KR[6]
0639: 1825  JC 0627
063A: 00B0  TST fA[11]        ; second pass done?
063B: 00B3  TOG fA[11]
063C: 181F  JC 062D           ; no → run the release window once more
; Error gate: fB[9] = ERROR flag (set by the over/underflow clamp at 0254, the
; 0÷0 path at 03DC, failed SBR at 11E9, …; cleared by CLR/CE at 03B8/03C2).
063D: 0098  TST fB[9]         ; error pending?
063E: 1818  JC 064A           ; no → test-line polls and the scan window
; ═══════════════════════════════════════════════════════════════════════════
; ERROR BLINK SERVICE  (0x063F–0x0649)
; Runs once per idle pass while fB[9] is set (trace-checked: CLR 1/x →
; blinking 9.9999999 99, ended by CLR). D[1..3] is a pass counter (the MAEX
; swaps leave D's nibble 0 alone); the PARITY of its hundreds digit (nibble
; 3) drives the blink: odd → the display, blanked by CLR.IDLE at 063F, stays
; dark for the pass; even → SET.IDLE at 0649 re-lights it. +1 per pass in
; both phases: 100 dark passes of 48 instructions (≈ 400 ms) alternate with
; 100 lit passes of 64 (the WAIT D1 at 0648 adds a sweep, ≈ 533 ms). With a
; printer each pass also takes the 0A25 detour and 0A29–0A2B count one more:
; 50 + 50 passes of 80 / 96 instructions (≈ 333 + 400 ms). The epilogue at
; 0624 (D=LOAD MLSD1) leaves D[3] = 1, so the blink always opens dark. The
; arming scan keeps running, so any key stays live during the blink.
; ═══════════════════════════════════════════════════════════════════════════
; Δ [HW] TI-59 064B–0655: the lit phase no longer adds 3 extra counts and the
; PRT.STEP poll is gone. On the TI-59 a lit pass runs at the ¼-speed idle
; rate, so counting 4 per lit pass makes both phases ≈ 0.45 s; with full-speed
; idle the TI-58C counts 1 in both (period ≈ 0.93 s against the TI-59's
; 0.90 s, measured on a real TI-59).
063F: 0A01  CLR.IDLE          ; blank the display; CPU takes the bus back
0640: 0CD5  C<>D MAEX         ; blink counter (D[1..3]) into C
0641: 0F24  C=C+1 MAEX1       ; counter += 1 (units digit = nibble 1)
0642: 0921  IO=C MANT         ; ALU pass: R5 latches the digit at the MANT
                              ;   constant position, nibble 3 = hundreds digit
0643: 0A18  MOV KR[4..7],R5   ; park it in KR so it can be bit-tested
0644: 0CD5  C<>D MAEX         ; counter back into D
0645: 0A45  TST KR[4]         ; hundreds digit odd?
0646: 1008  JNC 064A          ; odd → dark phase: skip the re-light
0647: 0213  B=B DPT           ; even → lit phase: ALU pass reloads R5 = decimal-point digit (R5
                              ;   doubles as the display dp position, clobbered at 0642)
0648: 0A10  WAIT D1
0649: 0A09  SET.IDLE          ; display back on at the sweep boundary
; Test-line polls, every idle pass (TI-58C only; neither line is driven in
; normal use): KN at D15 → factory self-test (09FD → 0DB7, trace-checked: it
; prints the test numbers 1–11 and overwrites all RAM); KR line at D10 →
; 09F7, a jump to 0x1800 outside the 6K ROM (program memory of a test
; fixture, presumably). TST.BUSY also fires on printer busy, which the
; pre-idle drain (0627–0629) rules out here.
; Δ [ENH] new (diagnostics); takes the place of the TI-59 card-switch poll,
; which tested the same digit 10 (TI-59 063E–0640).
064A: 0A00  WAIT D0           ; next instruction at digit 15
064B: 08FE  KEY [N]           ; KN at D15: self-test request?
064C: 1762  JNC 09FD          ; yes → self-test (0DB7)
064D: 0AB0  WAIT D11          ; next instruction at digit 10
064E: 0A0B  TST.BUSY          ; KR line at D10 (or printer busy)?
064F: 1750  JNC 09F7          ; yes → external program at 0x1800 (09F7)
; Steady-state scan window: arming scan, then back to the error gate at 063D
; — the steady-state idle pass 063D→0652. A new keypress is always seen here
; first.
; Δ [HW] TI-59 0656–065B: scans start at row 12 (WAIT D13; TI-59 WAIT D14,
; row 13) — the highest row in use is the printer's PRINT/ADV row 12.
0650: 0AD0  WAIT D13          ; next instruction at digit 12
0651: 0820  KEY [N,O,P,Q,S,T] ALL ; ARMING scan, rows 12–1 — first sight of a new key (or of the
                              ;   printer line at D10)
0652: 182B  JC 063D           ; no key → back to top of the idle loop
0653: 0AD0  WAIT D13          ; key seen — wait one full sweep (16 instructions ≈ 1.3 ms) …
0654: 0820  KEY [N,O,P,Q,S,T] ALL ; … CONFIRMATION scan (debounce sample #2; 0A30 enters here at
                              ;   row 9)
0655: 1831  JC 063D           ; released in between → bounce/glitch, discard
; Row filter (KR[4..7] = row): rows 1–7 → accept; 8, 9, 12 → accept;
; 10, 11 (the printer-present KP line at D10) → 0A25; 14, 15 → 0A25 → discard.
; Δ [HW] replaces the TI-59 "row ≠ 0" guard (065C–0660), new for the
; printer-present line at D10.
0656: 0A75  TST KR[7]         ; row < 8?
0657: 1806  JC 065A           ; yes → accept
0658: 0A55  TST KR[5]         ; rows 8/9/12/13 (KR[5] clear) → accept; 10/11/14/15 …
0659: 1798  JNC 0A25          ; … → printer-line path (0A25)
; ═══════════════════════════════════════════════════════════════════════════
; KEYBOARD DECODE & DISPATCH  (0x065A–0x06AA)
; Trace-checked with the headless harness (key "6", printer buttons). The
; hardware never produces a TI keycode — KEY...ALL latches the raw matrix
; position into KR:
;   KR[4..7]  = digit line D1–D13 at detection = physical keyboard ROW (1–9)
;   KR[8..10] = K-line index (KO=1, KP=2, KQ=3, KS=5, KT=6) = physical COLUMN
;   (key "6" = row 7, col 4 → K-line KS at D7 → KR = 0x0570)
; Pipeline:
;   065F–0670  D12 pseudo-keys (printer PRINT = KP, paper ADV = KN, the only
;              keys with KR[6] and KR[7] both set): remap row 12 → 9, tag with
;              fA[9]; real keyboard rows 1–7 skip via the JC at 0660. KN at
;              rows 8/9 (no keyboard key: a test signal) → self-test (0661).
;   0671–0677  K-line index → column number: the unscanned KR line (bit 4 of
;              the K mask) is collapsed out of the 3-bit index, mapping
;              {1,2,3,5,6} → {1,2,3,4,5}, so KR[8..11] = keyboard column 1–5.
;   0678–0687  second remap for the fA[9]-tagged printer pseudo-keys into
;              pseudo table entries 0x0089 (ADV) / 0x0099 (PRINT), i.e. the
;              2nd Adv / 2nd Prt slots. Trace-checked (headless PRINT/PAPER
;              buttons): PRINT prints X like Prt ("5 + 3 PRINT =" prints 3.
;              and still gives 8), PAPER feeds lines while held, like Adv.
;   0688–0699  keystroke print/trace gate: with printer + TRACE it QUEUES the
;              key's print symbol (no immediate print) — see notes inline.
;   06A1–06AA  computed dispatch: PC := 0x0<col><row> via SET KR[1]/PREG,
;              landing in the per-key dispatch table at 0x0011 (see there).
; ═══════════════════════════════════════════════════════════════════════════
065A: 0A01  CLR.IDLE          ; KEY ACCEPTED — leave idle (display off)
065B: 0619  IO=-B EXP         ; display image in EE form? (B's exponent field
065C: 1806  JC 065F           ; is non-zero when an exponent is shown)
065D: 0C48  A=SRA MAEX        ; yes → shift A's mantissa right twice, back to
065E: 0948  A=SRA MANT        ; the mantissa/EXP working layout (trace-checked: CLR pressed on
                              ;   the blinking 9.9999999 99; cf. twin at 04F2)
065F: 0A75  TST KR[7]         ; rows 12+ (KR[6] and KR[7] both set) are the
0660: 1822  JC 0671           ; D12 printer pseudo-keys; rows 1–7 skip ahead
; Rows 8–13 here. K-line index 0 (KN) on a row with KR[6] clear (8/9) is no
; keyboard key: → self-test, as KN at D15 in the idle loop (064B).
; Δ [ENH] new (diagnostics), TI-58C only.
0661: 0A85  TST KR[8]         ; K-line index 0 (KN)? …
0662: 0A95  TST KR[9]
0663: 0AA5  TST KR[10]
0664: 1006  JNC 0667          ; no → printer pseudo-key test
0665: 0A65  TST KR[6]         ; KN on row 8/9 …
0666: 1F2E  JC 09FD           ; … → self-test (09FD → 0DB7)
0667: 0A65  TST KR[6]         ; row 12 (KR[6] and KR[7] set)? else skip ahead
0668: 1812  JC 0671
0669: 0045  SET KR[4]         ; printer PRINT/ADV: row 12 → 9, tag fA[9],
066A: 006D  CLR KR[6]         ; and adjust the K-line bits for the remap
066B: 0085  SET KR[8]
066C: 0091  SET fA[9]
066D: 0A95  TST KR[9]
066E: 0095  SET KR[9]
066F: 1804  JC 0671
0670: 00A5  SET KR[10]
; K-line index → keyboard column number (see pipeline note above).
0671: 0AA5  TST KR[10]        ; index < 4 (KO/KP/KQ = cols 1–3) → unchanged
0672: 180C  JC 0678
0673: 009D  CLR KR[9]         ; KS (101) → 100 = col 4;  KT (110) → 101 = col 5
0674: 0A85  TST KR[8]
0675: 008D  CLR KR[8]
0676: 1004  JNC 0678
0677: 0085  SET KR[8]
0678: 0090  TST fA[9]         ; D12 printer pseudo-key? → second remap below
0679: 181E  JC 0688
067A: 0092  CLR fA[9]
067B: 0A85  TST KR[8]
067C: 0085  SET KR[8]
067D: 180C  JC 0683
067E: 008D  CLR KR[8]
067F: 0A95  TST KR[9]
0680: 009D  CLR KR[9]
0681: 100C  JNC 0687
0682: 0095  SET KR[9]
0683: 0AA5  TST KR[10]
0684: 00A5  SET KR[10]
0685: 1806  JC 0688
0686: 00AD  CLR KR[10]
0687: 00B5  SET KR[11]
0688: 00A8  TST fB[10]
0689: 1604  JNC 098B
; Keystroke print/trace gate: poll printer-present (KP at D10, via WAIT D11 +
; KEY[P]) and the printer TRACE switch (KP at D15, via WAIT D0 + KEY[P]) —
; see the idle-loop header note on these dedicated polls. With the printer
; attached and TRACE on, 0694 branches to 0A6C — but nothing is printed yet
; (trace-checked on the TI-58C: keys "0" then "+" print "0.      +"). The
; keystroke's print symbol is only QUEUED into the printer's 20-column line
; buffer, so the display value can later share the same printed line. The
; gate is traversed twice per keypress:
;   pass 1  fA[10] ("trace record pending") clear → 0A6C sets it, tags fA[4]
;           and jumps to 0784: the key's row/col is packed into a 2-digit
;           position code, and the queue routine at 141A (reached via 0B1B/
;           0E8A/1277) PRT.CLRs the line buffer (1420) and writes the code's
;           3-char print symbol right-justified (3× PRT.OUT at 13B3). No
;           PRT.GO — no paper output. Control returns to 0688 via
;           12CE → 10DE → 0D32 → 0BF9 → 0833 → 0849.
;   pass 2  fA[10] now set → 0A6E jumps to 069A, the key dispatches normally.
; The queued record is consumed later, depending on the key:
;   digit keys   the display-rebuild path clears fA[10] at 02DA without ever
;                printing; the symbol sits in the buffer until the next key's
;                PRT.CLR wipes it. Hence pressing "0" prints nothing.
;   operation keys  after the operation completes, 05A8–05AE re-check fA[10]
;                and the TRACE switch, then the numeric formatter (152B/160B)
;                appends the display value and PRT.GO at 0EFD finally prints
;                the whole line — e.g. "0" then "+" prints "0.      +".
; Δ [HW] TI-59 068B: printer-present is KP at D10 (WAIT D11; TI-59 WAIT D1 →
; D0), as at 00A9 and 0483.
068A: 0AB0  WAIT D11          ; next instruction at digit 10
068B: 08FB  KEY [P]           ; printer present (KP at D10)?
068C: 181C  JC 069A           ; no printer → skip straight to dispatch
; Δ [HW] TI-59 068E–0693, 0698: the memory-protection test (SCOM[9] nibble 2,
; set by reading a protected card) is gone — no card reader, so memory can't
; be protected; only the Prg Src test remains.
068D: 0A1F  RCLF              ; D := SCOM[0] (bus zero → row 0) …
068E: 09D6  D=LOAD MANT       ; … R5 latches nibble 3 = Prg Src Flag
068F: 02F6  D=R5 DPT
0690: 0239  IO=-D DPT         ; a module or keycode program running (Prg Src ≠ 0)?
0691: 1012  JNC 069A          ; yes → no trace, straight to dispatch
0692: 0A00  WAIT D0
0693: 08FB  KEY [P]           ; printer TRACE switch on?
0694: 17B0  JNC 0A6C          ; → queue the keystroke's print symbol (no print yet)
; ── 0695–0699: printer present, TRACE switch off: user flag 9 traces too.
; ── D = SCOM[0] (068E); subtracting 1 twice from its nibble 15 tests bit 1 =
; ── flag 9 (flags 5–9 are bit 1 of nibbles 11–15). Trace-checked: a program
; ── with St flg 9 prints "2.  +", "3.  =" … with the TRACE switch off.
0695: 09D5  C<>D MANT
0696: 0E2C  C=C-1 MMSD1       ; flag 9 set?
0697: 0E2C  C=C-1 MMSD1
0698: 09D5  C<>D MANT
0699: 1FA6  JC 0A6C           ; yes → queue the trace symbol as with the TRACE switch
069A: 0066  MOV fA[6],fB[6]
069B: 0069  SET fB[6]
069C: 0050  TST fA[5]
069D: 0052  CLR fA[5]
069E: 1751  JNC 02F6
069F: 00C8  TST fB[12]
06A0: 1568  JNC 0954          ; argument pending → ARG_KEY (0954)
; Computed dispatch (trace-confirmed): stash a return vector in SR, then
; branch through PREG to the table entry addressed by the key's row/column.
06A1: 0A0D  SWAP KR,SR
06A2: 0A0C  MOV KR,EXT[4..15] ; KR := 0
06A3: 0085  SET KR[8]         ; KR = 0x0100 → return address 0x0010 stashed in
06A4: 0A0D  SWAP KR,SR        ; SR (the neutral continuation, as restored at 02C2–02C4)
06A5: 0A75  TST KR[7]         ; keyboard row 1 (A–E: KR[5..7] all clear) is
06A6: 0A65  TST KR[6]         ; dispatched separately at 02CA (user-defined
06A7: 0A55  TST KR[5]         ; label keys) and never reaches the table
06A8: 1FBD  JC 02CA
; 06A9 arms the computed jump: PC := 0x0<col><row> — for "6" (col 4, row 7)
; PREG = 0x047 → dispatch table entry 0x0047. PREG redirects one instruction
; late, so 06AA still executes, conveniently zeroing KR for the handler.
06A9: 0015  SET KR[1] ; PREG
06AA: 0A0C  MOV KR,EXT[4..15]
; After the kernel (slot 052F): tan → result. sin/cos continue with
; 1 + tan² → √ → divide: sin = t/√(1+t²), cos = 1/√(1+t²) (slots 0530–0533,
; 0A31–0A39 picks the numerator). Tan at an exact multiple of 90° → 03DE.
06AB: 0F01  IO=A+1 MAEX1
06AC: 1F0A  JC 0A31
06AD: 00C0  TST fA[12]
06AE: 0051  SET fA[5]
06AF: 1DA3  JC 03DE
06B0: 17F3  JNC 02B7
06B1: 0A1F  RCLF              ; key epilogue while a program runs (02D6): Prg Src ≠ 0 → keep
                              ;   running (08A2)
06B2: 09D3  B=LOAD MANT
06B3: 06F3  B=R5 EXP
06B4: 0619  IO=-B EXP
06B5: 1FBD  JC 02D7
06B6: 0050  TST fA[5]
06B7: 17C1  JNC 02D7
06B8: 00A8  TST fB[10]        ; sub-program / library run continues (→ 08A2 on both branches)
06B9: 00AA  CLR fB[10]
06BA: 00A2  CLR fA[10]
06BB: 13CE  JNC 08A2
06BC: 0082  CLR fA[8]
06BD: 1BCA  JC 08A2
; ═══════════════════════════════════════════════════════════════════════════
; ARGUMENT COLLECTOR  (0x06BE–0x06D2) — trace-confirmed (STO 05, SUM 05,
; STO Ind 01). Entered from NUMBER_ENTRY (02F7) when fB[12] is set: the digit
; in KR[4..7] is shifted into the argument held in E (the suspended X sits
; in E's place in A meanwhile); E[1..2] count the digits still expected
; (set at 0228). When the count runs out → 07A9: resume the operation.
; ═══════════════════════════════════════════════════════════════════════════
06BE: 0A08  MOV R5,KR[4..7]   ; digit …
06BF: 09F6  D=R5 MANT         ; … into D[3]
06C0: 0002  CLR fA[0]
06C1: 01D7  A<>E ALL          ; A := collector state
06C2: 0070  TST fA[7]         ; Ind?
06C3: 180A  JC 06C8
06C4: 0309  IO=A-1 DPT1
06C5: 1806  JC 06C8
06C6: 0AB7  MOV R5,#11
06C7: 0CF0  A=R5 MAEX
06C8: 0940  A=SLA MANT        ; shift the argument one digit …
06C9: 09B0  A=A+D MANT        ; … and add the new digit
06CA: 0148  A=SRA ALL
06CB: 0308  A=A-1 DPT1        ; one digit fewer to go …
06CC: 0140  A=SLA ALL
06CD: 03D0  A=LOAD DPT1
06CE: 11B6  JNC 07A9          ; … none left → complete (07A9)
06CF: 01D7  A<>E ALL          ; more digits: collector back to E
06D0: 00A8  TST fB[10]
06D1: 1163  JNC 0620
06D2: 1A35  JC 05B8
; Enter LRN: save X (C) and the sign flags, then fetch the current step
; through PRGREG_FETCH without advancing (fB[11] path) with KR := 0x6200
; parked in SR as the continuation.
; Δ [REORG] TI-59 06DB–06F2 (key arriving in argument mode) moved to 0954–096B.
06D3: 0058  TST fB[5]
06D4: 1004  JNC 06D6
06D5: 0144  C=SLA ALL
06D6: 0A06  MOV R5,fA[1..4]
06D7: 02F4  C=R5 DPT
06D8: 0022  CLR fA[2]
06D9: 0095  SET KR[9]         ; continuation KR = 0x6200 …
06DA: 00E5  SET KR[14]
06DB: 00D5  SET KR[13]
06DC: 0A0D  SWAP KR,SR        ; … into SR
06DD: 0032  CLR fA[3]
06DE: 1B92  JC 08A7           ; → PRGREG_FETCH
; y^x, last step (slot 050E): e^(x·ln y); 06E1/06E2 handle the root sign case.
06DF: 0010  TST fA[1]
06E0: 1806  JC 06E3
06E1: 0939  IO=-D MANT
06E2: 1BA7  JC 050F
; ═══════════════════════════════════════════════════════════════════════════
; EXP  (0x06E3–0x06FC) — e^x (slot 0517, also y^x and 10^x). Trace-confirmed
; (e^2 = 7.389056099, 10^2, 2^3, 8^(1/3)).
; Argument reduction: x = n·ln 10 + r with 0 ≤ r < ln 10 — n is counted by
; repeated subtraction of ln 10 (constant 0) at 06EF–06F3, small/negative x
; handled at 09A5–09F6. Then the shared kernel at 073E runs with fB[4] clear
; (pseudo-multiplication): for k = 0…6, while r ≥ ln(1+10^−k), subtract it
; and multiply the product (C, starting at 1.0) by (1+10^−k). The result
; e^r is finished at 0ACD–0AD8 (remainder correction ≈ ×(1+r)) and n becomes
; the decimal exponent. x = 0 → 1 directly (06E4 → 03DD).
; ═══════════════════════════════════════════════════════════════════════════
06E3: 0D09  IO=A-1 MLSD1      ; x = 0?
06E4: 160F  JNC 03DD          ; yes → result 1
06E5: 008D  CLR KR[8]         ; constant 0 = ln 10 …
06E6: 01D8  A=0 ALL
06E7: 0CC3  B=A+CON MAEX      ; … into B
06E8: 0920  A=C MANT          ; A := |x|
06E9: 0030  TST fA[3]         ; |x| < 1 (negative exponent)?
06EA: 15F6  JNC 09E5          ; yes → scale down (09E5) and go straight to the kernel
06EB: 09DC  C=0 MANT
06EC: 016C  C=SRC ALL
06ED: 0729  IO=C-1 EXP1
06EE: 1D7E  JC 09AD
06EF: 0C89  IO=A-B MAEX       ; n := number of whole ln 10 in x …
06F0: 156A  JNC 09A5
06F1: 0C88  A=A-B MAEX
06F2: 0724  C=C+1 EXP1
06F3: 1809  JC 06EF
06F4: 1572  JNC 09AD          ; too large → overflow / underflow (09AD → 05EA)
; Dsz decrement (slot 00F6 → 04A7): |register| − 1 towards zero via ADD
; (0335) with B = 1; a register already below 1 becomes 0 (06FB).
06F5: 01DB  B=0 ALL
06F6: 0086  MOV fA[8],fB[8]
06F7: 0D09  IO=A-1 MLSD1      ; register zero?
06F8: 1787  JNC 0335
06F9: 0030  TST fA[3]         ; |register| < 1?
06FA: 1FC4  JC 0ADC
06FB: 01D8  A=0 ALL           ; yes → 0
06FC: 1F8F  JC 0335
; MULDIV core loops (moved here from TI-59 0422–044F): sign/exponent combine,
; restoring division and shift-and-add multiplication. Entries: 06FF/0702
; from MULDIV (043B/043D), 0708 from the pseudo-division users (0AF2),
; 070D from the LN/EXP kernel (080C), 0724 from ADD's like-sign add (0346).
; Δ [REORG] TI-59 0422–044F, same code (moved, presumably to free space in 0300–04FF for the added RAM code).
; The TI-59 trampoline 075E (JC 042D, for 0AF5) is no longer needed: 0AF2
; reaches 0708 directly.
06FD: 0033  TOG fA[3]         ; unlike exponent signs: the larger magnitude's sign wins …
06FE: 06D2  A<>B EXP
06FF: 0689  IO=A-B EXP
0700: 1007  JNC 06FD
0701: 0688  A=A-B EXP         ; … exponent := difference
0702: 09D8  A=0 MANT          ; clear the product / quotient
0703: 06DC  C=0 EXP
0704: 0D29  IO=C-1 MLSD1      ; left operand zero?
0705: 1016  JNC 0710          ; yes → result 0
0706: 0010  TST fA[1]
0707: 1836  JC 0722           ; multiply → 0722
0708: 06DB  B=0 EXP           ; divide (also entered from 0AF2)
0709: 1804  JC 070B
070A: 0D00  A=A+1 MLSD1       ; quotient digit + 1
070B: 0C9C  C=C-B MAEX        ; remainder − divisor …
070C: 1805  JC 070A           ; … until it borrows
070D: 0C94  C=C+B MAEX        ; restore the last subtraction (also entered from 080C)
070E: 1878  JC 074A           ; COND at rest only for the 080C entry (transcendentals) → 074A
070F: 0E09  IO=A-1 MMSD1      ; 13 quotient digits done (MSD reached nibble 15)?
0710: 0012  CLR fA[1]
0711: 1DA5  JC 043F           ; yes → ARITH_EXIT
0712: 0C5B  B=SRB MAEX        ; next quotient digit: divisor ÷ 10 …
0713: 0940  A=SLA MANT        ; … quotient × 10
0714: 0D09  IO=A-1 MLSD1      ; quotient still zero (leading zero digit)?
0715: 1815  JC 070B
0716: 0300  A=A+1 DPT1        ; yes → one less integer digit (A[0] tracks the exponent shift)
0717: 1819  JC 070B
0718: 096C  C=SRC MANT        ; multiply: next multiplier digit
0719: 0D29  IO=C-1 MLSD1      ; multiplier exhausted?
071A: 15B7  JNC 043F          ; yes → ARITH_EXIT
071B: 0CD2  A<>B MAEX         ; multiplicand MSD still zero?
071C: 0E0A  A<>B=A-1 MMSD1    ; (test on B's MSD by exchanging around an IO-only ALU op)
071D: 1808  JC 0721
071E: 0953  B=SLB MANT        ; yes → shift the multiplicand left …
071F: 0300  A=A+1 DPT1        ; … and count it
0720: 1804  JC 0722
0721: 0948  A=SRA MANT        ; no → shift the product right
0722: 052C  C=C-1 LLSD1       ; multiplier digit − 1 …
0723: 1017  JNC 0718          ; … exhausted → next digit
0724: 0980  A=A+B MANT        ; product += multiplicand (also ADD's like-sign add, 0346)
0725: 1807  JC 0722           ; no carry → next
0726: 0948  A=SRA MANT        ; carry out: shift the product right …
0727: 095B  B=SRB MANT        ; … and the multiplicand …
0728: 0E00  A=A+1 MMSD1       ; … insert the carry digit at the top …
0729: 0308  A=A-1 DPT1        ; … and count the shift
072A: 1811  JC 0722
; y^x first step (slot 050C): save x in D, ln y via the kernel. Guards: y or
; x zero (0732–0734 → 04DC), y negative is an error (0735 → 0546).
072B: 0A0D  SWAP KR,SR
072C: 0A0C  MOV KR,EXT[4..15]
072D: 0106  D=A ALL           ; D := x (exponent operand) with its flags
072E: 0A06  MOV R5,fA[1..4]
072F: 02F6  D=R5 DPT
0730: 0114  C=B ALL           ; C := y (the pending AOS operand)
0731: 0120  A=C ALL
0732: 0919  IO=-B MANT        ; y zero? …
0733: 0939  IO=-D MANT        ; … or x zero?
0734: 1CB1  JC 04DC
0735: 0D09  IO=A-1 MLSD1
0736: 13E1  JNC 0546
0737: 0036  MOV fA[3],fB[3]
; ═══════════════════════════════════════════════════════════════════════════
; LN  (0x0738) and the shared LN/EXP KERNEL (0x073E–0x0769) — Meggitt
; pseudo-multiplication with the constant ROM (C=C+CON / A=A±CON, index in
; KR[4..6]/KR[8..11]; constant 0 = ln 10, constants 1–7 = ln(1+10^−k) for
; k = 0…6). Trace-confirmed (ln 2 = .6931471806, log 2, e^2, 2^3).
;   ln mode (fB[4] set): the mantissa m (in C) is multiplied by (1+10^−k)
;       as long as it stays below 10 (080B tests the carry), each factor
;       adding ln(1+10^−k) to the sum in A; after k = 6, ln(10/m) ≈ Σ +
;       (10 − m)/10 (075B–075F), and ln x = (e+1)·ln 10 − that (0760–0769,
;       finished at 0B2A–0B3B with the decimal exponent e).
;   exp mode (fB[4] clear): the reverse — subtract constants from r,
;       multiply the product (see EXP 06E3).
; ln of zero → error (073A → 0A0C); a negative argument sets the error flag
; (073D) and continues with |x|.
; ═══════════════════════════════════════════════════════════════════════════
0738: 0D09  IO=A-1 MLSD1      ; LN: x zero?
0739: 0049  SET fB[4]         ; kernel in ln mode
073A: 15A4  JNC 0A0C          ; zero → error
073B: 0028  TST fB[2]         ; negative?
073C: 1804  JC 073E
073D: 0099  SET fB[9]         ; yes → ERROR flag, continue with |x|
073E: 0148  A=SRA ALL         ; KERNEL: scale the mantissa down two digits (headroom) …
073F: 0022  CLR fA[2]
0740: 0203  B=A DPT
0741: 0148  A=SRA ALL
0742: 06DC  C=0 EXP
0743: 008D  CLR KR[8]         ; KR := 0x0010: k = 0, constant 1 = ln 2
0744: 0A04  INC KR
0745: 0CD8  A=0 MAEX          ; A := sum of logarithms = 0
0746: 0048  TST fB[4]         ; exp mode?
0747: 100A  JNC 074C
0748: 0C20  A=C MAEX          ; exp: A := reduced argument r …
0749: 0ED4  C=LOAD MMSD1      ; … C := product = 1.0
074A: 0048  TST fB[4]
074B: 1012  JNC 0754
074C: 0C23  B=C MAEX          ; B := C · 10^−k: copy …
074D: 0A08  MOV R5,KR[4..7]   ; … shift count k (+1) from the constant index …
074E: 02F4  C=R5 DPT
074F: 032C  C=C-1 DPT1
0750: 0048  TST fB[4]
0751: 1170  JNC 0809          ; ln → shift B (0809/075D loop), try C·(1+10^−k)
0752: 0CC8  A=A-CON MAEX      ; exp: r − ln(1+10^−k) …
0753: 196C  JC 0809           ; … fits → multiply C by (1+10^−k)
0754: 0CC0  A=A+CON MAEX      ; ln: Σ += ln(1+10^−k) / exp: undo the over-subtraction …
0755: 1813  JC 074C           ; … (ln: try the same factor again; exp: carry → next k)
0756: 0A04  INC KR            ; next k (constant index + 1) …
0757: 0A75  TST KR[7]         ; … up to k = 6 (index 7)
0758: 1819  JC 074C
0759: 0048  TST fB[4]         ; exp → finish at 0ACE
075A: 1EE8  JC 0ACE
075B: 0C23  B=C MAEX          ; ln: remainder term (10 − m), scaled …
075C: 0C1B  B=-B MAEX
075D: 0C5B  B=SRB MAEX
075E: 1956  JC 0809
075F: 0C83  B=A+B MAEX        ; … added to the sum: B = ln(10/m)
0760: 0A0C  MOV KR,EXT[4..15] ; KR := 0 → constant 0 = ln 10
0761: 0144  C=SLA ALL
0762: 0214  C=B DPT
0763: 0164  C=SLC ALL
0764: 01D8  A=0 ALL
0765: 01C0  A=A+CON ALL       ; A := ln 10
0766: 0030  TST fA[3]         ; exponent sign selects the combination at 0B2A / 0B2C
0767: 1786  JNC 0B2A
0768: 0C8B  B=A-B MAEX
0769: 1F86  JC 0B2C
076A: 1D72  JC 0A23           ; store-back entry (from 04DB) → 0A23 write
; Δ [REORG] TI-59 075D–076F: the division trampoline (075E) is gone (see
; 06FD) and the argument-key classification (075F–076F) moved to 096C–097C.
076B: 1D72  JC 0A24           ; Dsz (03FB): write the counter back (→ 0A24 → RAM write)
; RECIP: "1/x" (slot 050B; X already normalized by the 0442 slot before it).
; Trace-confirmed (1/4, and 1/0 → x÷0 exit → error blink).
076C: 0051  SET fA[5]         ; result to be displayed
076D: 0ED4  C=LOAD MMSD1      ; C := 1.0
076E: 003A  CLR fB[3]
076F: 002A  CLR fB[2]
0770: 0013  TOG fA[1]         ; divide (08FB/0605 enter here: ±ln 10 with fA[1] preset)
0771: 0123  B=C ALL           ; B := C (1.0 for 1/x; X itself for x², slot 0509) → MULDIV
0772: 1F3D  JC 03D4           ; 0509's entry) → MUL/DIV core, divisor in A
0773: 0AA5  TST KR[10]        ; argument key in columns 4–5 (from 05C0): Ind, EE, …
0774: 0A85  TST KR[8]
0775: 0A75  TST KR[7]
0776: 0A55  TST KR[5]
0777: 0A45  TST KR[4]
0778: 13F6  JNC 0973
0779: 0A95  TST KR[9]
077A: 1BF2  JC 0973
077B: 02D7  A<>E DPT
077C: 0309  IO=A-1 DPT1
077D: 02D7  A<>E DPT
077E: 11AB  JNC 06A9
; ARG_TERMINATE: a non-digit key ends a pending argument ("5 STO 3 +" stores
; into R03, then executes +). The key is encoded (KEY_ENCODE) and parked as
; a keycode in SCOM[0] nibbles 1–2 with fB[14] = key pending (07A4–07A7); the
; suspended sequence then resumes (07A9) and the pending key is executed via
; 0620 → 04F2 → STEP_DISPATCH. Missing safeguard: KEY_ENCODE's column bits stay
; in KR and can offset the resumed sequence's bank dispatch (St flg → 0B34) —
; one link of the fast-mode chain, see examples/fastmode.ti59.
077F: 0A1F  RCLF              ; SCOM[0] …
0780: 01D6  D=LOAD ALL
0781: 017E  D=SRD ALL
0782: 017E  D=SRD ALL
0783: 00E9  SET fB[14]        ; terminating key pending
; KEY_ENCODE: build the program keycode of the key being recorded from the
; matrix position in KR (row in KR[4..7], column in KR[8..11]) into D[1..2]
; as two BCD digits row·10 + column (2nd keys arrive with the column already
; +5). Digit keys are recorded as their value 00–09 instead (0799–079C picks
; the DIGIT_SLIDE value when the row nibble is a digit).
0784: 0A08  MOV R5,KR[4..7]   ; row …
0785: 02F6  D=R5 DPT
0786: 0176  D=SLD ALL         ; … into the tens position
0787: 0A07  MOV R5,#0
0788: 0A18  MOV KR[4..7],R5   ; KR[4..7] := column bits (3-bit K-line index → 1–5) …
0789: 0AB5  TST KR[11]
078A: 1808  JC 078E
078B: 0A95  TST KR[9]
078C: 1022  JNC 079D
078D: 0075  SET KR[7]
078E: 0AA5  TST KR[10]
078F: 1804  JC 0791
0790: 0065  SET KR[6]
0791: 0A95  TST KR[9]
0792: 1804  JC 0794
0793: 0055  SET KR[5]
0794: 0A85  TST KR[8]
0795: 1804  JC 0797
0796: 0045  SET KR[4]
0797: 0A08  MOV R5,KR[4..7]   ; … as the units digit
0798: 02F6  D=R5 DPT
0799: 0239  IO=-D DPT
079A: 1006  JNC 079D
079B: 017E  D=SRD ALL
079C: 0C76  D=SLD MAEX
079D: 00E8  TST fB[14]
079E: 1006  JNC 07A1
079F: 00A8  TST fB[10]        ; LRN mode?
07A0: 1676  JNC 0ADB          ; yes → store the keycode (0ADB → 0D5C)
07A1: 0176  D=SLD ALL
07A2: 0040  TST fA[4]         ; printer trace symbol (0A6C path)?
07A3: 16F0  JNC 0B1B
07A4: 0A1F  RCLF              ; SCOM[0] nibbles 1–2 := its keycode …
07A5: 02D6  D=LOAD DPT
07A6: 0A0F  STOF
07A7: 0131  IO=D ALL
07A8: 01D7  A<>E ALL
; ARG_COMPLETE: all digits typed. Clear argument mode, leave the number in E
; (A := X again) and resume the suspended sequence at the slot after the
; collector call: SR holds that slot address; INC KR + SET KR[1] jump to it.
; With Ind (fA[7]) the register is read first (04AD → indirect address).
07A9: 00CA  CLR fB[12]        ; argument complete
07AA: 00A8  TST fB[10]
07AB: 16D6  JNC 0B16
07AC: 00A0  TST fA[10]
07AD: 1760  JNC 0B5D
07AE: 06D8  A=0 EXP
07AF: 014E  D=SRA ALL
07B0: 01D7  A<>E ALL          ; A := X, E := argument
07B1: 0070  TST fA[7]         ; Ind?
07B2: 160B  JNC 04AD          ; yes → read the pointer register first
07B3: 0A0D  SWAP KR,SR        ; resume: KR := suspended slot …
07B4: 0A04  INC KR            ; … + 1 …
07B5: 0015  SET KR[1] ; PREG ; … jump there
07B6: 0A0D  SWAP KR,SR
07B7: 17AF  JNC 03E0
07B8: 16CE  JNC 0B1F
; y^x second step (slot 050D): ln y × x (÷ x for INV y^x).
07B9: 0130  A=D ALL           ; A := x (saved in D at 072D) …
07BA: 0007  MOV fA[1..4],R5   ; … with its flags; fA[1] = root
07BB: 04D0  A=LOAD DPTC
07BC: 1897  JC 0771           ; → ln y × x, or ÷ x for INV y^x
; ═══════════════════════════════════════════════════════════════════════════
; RUN_LOOP  (0x07BD–0x07DD) — between two program steps (reached from the
; pre-idle checks at 0623 while fB[0] is set). Trace-confirmed (5 + 3 = R/S,
; loops, labels). Keycode sub-programs and library programs (Prg Src ≠ 0)
; continue at 08A2. Otherwise, unless an argument is pending, poll two keys
; (07CB): GTO held → display "peek" every second step (04E2); R/S held →
; stop (07DE). Then fetch the next step (08A5 → PRGREG_FETCH) and dispatch it
; (STEP_DISPATCH 082B).
; ═══════════════════════════════════════════════════════════════════════════
07BD: 0619  IO=-B EXP         ; EE layout image? → realign A (as at 065B)
07BE: 1806  JC 07C1
07BF: 0C48  A=SRA MAEX
07C0: 0948  A=SRA MANT
07C1: 0A1F  RCLF              ; SCOM[0] …
07C2: 09D6  D=LOAD MANT
07C3: 06F6  D=R5 EXP          ; … D[1] := Prg Src Flag
07C4: 0639  IO=-D EXP         ; sub-program / library running?
07C5: 11BA  JNC 08A2          ; yes → their fetch loop
07C6: 00DA  CLR fB[13]        ; single step done
07C7: 0080  TST fA[8]         ; INV pending …
07C8: 00C8  TST fB[12]        ; … argument pending …
07C9: 0000  TST fA[0]         ; … or label byte pending?
07CA: 11B6  JNC 08A5          ; yes → next step immediately (no key poll)
; Run-loop key polls (trace-checked, headless harness): holding the key at
; matrix row 6 / column 1 (GTO) while a RAM program runs makes every second
; step light the display for 256 hold-loop passes (04E2; ≈ 64 ms on the
; TI-58C, ≈ 216 ms on the TI-59 whose idle runs at ¼ speed — the count was
; not adapted), showing the intermediate X values — an undocumented "peek".
; Holding R/S (row 9 / column 1) stops the run.
07CB: 0A70  WAIT D7           ; poll row 6 / column 1 (the GTO key) …
07CC: 08FD  KEY [O]
07CD: 1808  JC 07D1           ; not held → R/S poll
; Δ [HW] TI-59 07D2–07D9: the "memory protected → no peek" test (SCOM[9]
; nibble 2) is gone — without a card reader memory can't be protected.
07CE: 0053  TOG fA[5]         ; every second step …
07CF: 0050  TST fA[5]
07D0: 15DD  JNC 04E2          ; … show the display (DISPLAY_PEEK 04E2)
07D1: 0AA0  WAIT D10          ; poll the R/S key (digit 9 / K-line O)
07D2: 08FD  KEY [O]
07D3: 1016  JNC 07DE          ; pressed → stop (KEY_RS)
07D4: 0098  TST fB[9]         ; error pending?
07D5: 19A0  JC 08A5           ; no → next step
07D6: 01D7  A<>E ALL          ; error during a run: user flag 8 set (bit 1 of SCOM[0] nibble
                              ;   14)?
07D7: 0A1F  RCLF
07D8: 09D0  A=LOAD MANT
07D9: 0140  A=SLA ALL
07DA: 0E08  A=A-1 MMSD1
07DB: 0E09  IO=A-1 MMSD1
07DC: 01D7  A<>E ALL
07DD: 1190  JNC 08A5          ; no → keep running (error flag stays, blinks at the stop); yes →
                              ;   stop at once (07DE). Trace-checked: "1/0= 5 R/S" ends showing
                              ;   a blinking 5, with St flg 8 it halts at 9.9999999 99
; KEY_RS: "R/S" handler (slot 0019 → 0410; also the run loop's R/S poll at
; 07D3). Running → stop (07F1 TOG fB[0]). Stopped → first wait until R/S is
; released (07E0–07E2: WAIT D10 + KEY [O] samples the R/S key, row 9 column 1),
; so execution starts on the release, then start (0BAB). A selected library
; program in SCOM[9] is resumed rather than restarted (07ED → 0BC4/091A).
07DE: 0008  TST fB[0]         ; running?
07DF: 1008  JNC 07E3          ; yes → stop without waiting
07E0: 0AA0  WAIT D10          ; stopped: wait for the R/S key to be released …
07E1: 08FD  KEY [O]
07E2: 1009  JNC 07DE
07E3: 0A97  MOV R5,#9         ; SCOM[9] (library page) …
07E4: 02F6  D=R5 DPT
07E5: 0131  IO=D ALL
07E6: 0A1F  RCLF
07E7: 01D3  B=LOAD ALL
07E8: 0C5E  D=SRB MAEX
07E9: 0C7E  D=SRD MAEX
07EA: 0008  TST fB[0]
07EB: 00D8  TST fB[13]
07EC: 1F7E  JC 0BAB           ; stopped and not single-stepping → start
07ED: 0939  IO=-D MANT
07EE: 17AC  JNC 0BC4
07EF: 00D8  TST fB[13]
07F0: 1006  JNC 07F3
07F1: 000B  TOG fB[0]         ; running → stop
07F2: 0008  TST fB[0]
07F3: 0072  CLR fA[7]
07F4: 0082  CLR fA[8]
07F5: 17D1  JNC 040D
07F6: 1BDB  JC 0609           ; R/S executed as a program step: halt
; Op 16 / Op 17 entry (OP_TABLE 0A16/0A17; Op 16 sets fB[14] first): R5 := 9
; and into the print-op sequence like Op 01–04/07, whose tail (0934 → 0D11)
; hands it to PARTITION (≈1775). On the TI-59 this prefix was shared with the
; card code; the TI-58C has none.
07F7: 0A97  MOV R5,#9
07F8: 02F6  D=R5 DPT          ; D[0] := 9 (Op 16 / Op 17)
; Print-op entry (Op 01–04, 07): Op number into A (E), then the print
; sequence 053F (fn-table bank 0x0540) dispatches on it (print engine 165A).
; Op 00, 05 and 06 enter at 092A instead.
07F9: 01D7  A<>E ALL
07FA: 0231  IO=D DPT
07FB: 09F0  A=R5 MANT
07FC: 01D7  A<>E ALL
07FD: 0082  CLR fA[8]
07FE: 1D7F  JC 053F
07FF: 1E6D  JC 04C9           ; LRN: operand recording via the collector
; Op 11 (OP_TABLE 0A11): variance — the x̄ keycode program (entry 067, via
; 017F) with a variant flag in B[0] (054A).
0800: 1D6D  JC 054A
0801: 0126  D=C ALL
0802: 0A06  MOV R5,fA[1..4]
0803: 02F6  D=R5 DPT
0804: 0024  SWAP fA[2],fB[2]
0805: 0034  SWAP fA[3],fB[3]
0806: 04D0  A=LOAD DPTC       ; A[0] := 0xC (normalized marker) …
0807: 1F91  JC 043F           ; … → ARITH_EXIT
0808: 1F87  JC 0445
; Kernel shift/test helper (from 0751/0753): shift B right by the count in
; C[0], then test whether C + B stays below 10.
0809: 032C  C=C-1 DPT1
080A: 195B  JC 075D           ; more shifts → 075D
080B: 0C91  IO=C+B MAEX       ; C · (1+10^−k) < 10?
080C: 19FF  JC 070D           ; yes → C += B (via 070D in the moved MULDIV loop, which returns
                              ;   to 074A)
080D: 116F  JNC 0756          ; no → next k
; Op 08 (OP_TABLE 0A08): List with fA[13] = labels only (1160), → 049C → LIST.
080E: 0082  CLR fA[8]
080F: 00D1  SET fA[13]        ; Op 08: list labels only (tested at 1160)
0810: 1EE9  JC 049C
; ═══════════════════════════════════════════════════════════════════════════
; SQRT  (0x0811–0x081E, body 0x0AA7–0x0ACB, exit 0x0AFA) — trace-confirmed (√2 =
; 1.414213562, √−2 → error). Exponent halved (0819–081E; an odd exponent
; shifts the mantissa one digit, 0AA7), then the root is built digit by digit
; by subtracting successive odd multiples (C = remainder, B = 2·root + odd
; increment, A = digit weight) at 0AB4–0AC6, one root digit per pass.
; ═══════════════════════════════════════════════════════════════════════════
0811: 0051  SET fA[5]         ; result to be displayed
0812: 0020  TST fA[2]         ; negative?
0813: 1804  JC 0815
0814: 0099  SET fB[9]         ; yes → ERROR flag, continue with |x|
0815: 01DB  B=0 ALL
0816: 0E09  IO=A-1 MMSD1      ; zero?
0817: 16FB  JNC 049A          ; yes → result 0
0818: 0ED0  A=LOAD MMSD1      ; A := 1 (digit weight at the MSD)
0819: 072C  C=C-1 EXP1        ; halve the exponent: count C's exponent down in twos …
081A: 1522  JNC 0AAB          ; even → body
081B: 072C  C=C-1 EXP1
081C: 1516  JNC 0AA7          ; odd → shift first
081D: 0700  A=A+1 EXP1        ; … one result exponent unit per two
081E: 180B  JC 0819
; LIB_EXEC_ENTRY: next keycode of a library program from the CROM (FETCH
; HIGH then FETCH, which advances the module's internal PC): tens → D[1],
; units → D[0]. Then poll row 8 / column 1 (the RST key): held → abort the
; run and perform RST (082A → 04DF → 028A → 028C; trace-confirmed with
; ML-01).
081F: 0A3E  LIB.HI            ; high digit of the byte (no advance) …
0820: 0A0C  MOV KR,EXT[4..15]
0821: 0A08  MOV R5,KR[4..7]
0822: 06F6  D=R5 EXP          ; … tens digit → D[1]
0823: 0A0E  LIB.IN            ; fetch the byte, CROM PC + 1 (user-visible step latch)
0824: 0A0C  MOV KR,EXT[4..15]
0825: 0A08  MOV R5,KR[4..7]
0826: 02F6  D=R5 DPT          ; units digit → D[0]
0827: 01D2  A<>B ALL
0828: 0A90  WAIT D9           ; poll row 8 / column 1 (the RST key)
0829: 08FD  KEY [O]
082A: 1697  JNC 04DF          ; held → stop and RST
; ═══════════════════════════════════════════════════════════════════════════
; STEP_DISPATCH  (0x082B–0x084A) — execute the fetched keycode (D[1..0]) by
; turning it back into a keyboard matrix position and entering the normal
; key pipeline at the print/trace gate (0688). Trace-confirmed (run of
; 5 + 3 =, Lbl A … x² …). keycode = tens·10 + units, tens = row, units =
; column (2nd functions have column 6–9/0 and land in the 2nd mirror table);
; digit keycodes 00–09 are routed to number entry directly (083A → 04CF).
; ═══════════════════════════════════════════════════════════════════════════
082B: 0008  TST fB[0]         ; running …
082C: 00D8  TST fB[13]        ; … or single-stepping?
082D: 180C  JC 0833
082E: 00C8  TST fB[12]        ; argument pending → the keycode is an operand (09FF →
                              ;   PROG_OPERAND 0D34)
082F: 13A0  JNC 09FF          ; → 09FF → 0D34 (jump-range trampoline)
0830: 0000  TST fA[0]
0831: 0002  CLR fA[0]
0832: 16A9  JNC 04DE
0833: 0A0C  MOV KR,EXT[4..15] ; KR := 0
0834: 0239  IO=-D DPT
0835: 0231  IO=D DPT          ; units digit …
0836: 0A18  MOV KR[4..7],R5
0837: 017E  D=SRD ALL         ; … tens digit into D[0]
0838: 1F72  JC 0BF1
0839: 0239  IO=-D DPT         ; tens 0 = digit keycode 00–09?
083A: 1ED7  JC 04CF           ; yes → number entry (04CF → 0688)
083B: 0A45  TST KR[4]         ; column bits → KR[8..11] …
083C: 1804  JC 083E
083D: 0085  SET KR[8]
083E: 0A55  TST KR[5]
083F: 1804  JC 0841
0840: 0095  SET KR[9]
0841: 0A65  TST KR[6]
0842: 1804  JC 0844
0843: 00A5  SET KR[10]
0844: 0A75  TST KR[7]
0845: 1804  JC 0847
0846: 00B5  SET KR[11]
0847: 0231  IO=D DPT          ; … row (tens) → KR[4..7]
0848: 0A18  MOV KR[4..7],R5
0849: 1B83  JC 0688           ; → key pipeline, as if the key had been pressed
084A: 1D8C  JC 0B10           ; REG_ACCESS → 0B10 → REG_ADDR
084B: 17AA  JNC 0C20          ; Adv → paper advance
084C: 0A0C  MOV KR,EXT[4..15] ; HIR (from 0B21): → slot 00FA
084D: 0AA7  MOV R5,#10
084E: 1CAD  JC 05F8
084F: 1F2E  JC 0BE6
; COND_TRANSFER body (0495): INV (fB[8]) inverts the test. True → read the
; address operand and transfer (0852 → LABEL_SEARCH 0BCA for a label, or a
; 3-digit step checked against the partition at 0858–0862 → 0B0A on
; overflow). False → skip the operand (0C14 → 0893).
0850: 0088  TST fB[8]         ; INV?
0851: 1786  JNC 0C14
0852: 0000  TST fA[0]         ; transfer: label (→ LABEL_SEARCH 0BCA) or step number
                              ;   (STEP_TO_REG)
0853: 01D7  A<>E ALL
0854: 0A1F  RCLF
0855: 09D3  B=LOAD MANT
0856: 0002  CLR fA[0]
0857: 16E6  JNC 0BCA          ; label → search
0858: 0CF6  D=R5 MAEX
0859: 01D5  C<>D ALL
085A: 072B  B=C-1 EXP1
085B: 0619  IO=-B EXP
085C: 1EDA  JC 0BC9
085D: 0DD3  B=LOAD MLSD1
085E: 0953  B=SLB MANT
085F: 0953  B=SLB MANT
0860: 0953  B=SLB MANT
0861: 0989  IO=A-B MANT       ; absolute step inside program memory?
0862: 1D50  JC 0B0A           ; no → error
; ── Program-transfer target: split into register·offset, validate, commit ───
; Generic "transfer to step N" tail, shared by RAM-program transfers and
; ROM keycode sub-program launches. The divide-by-8 loop at 0865–0867
; splits the target step into register number and offset (assembled in C,
; e.g. step 284 → "35·4"). fB[0], tested at 0872, selects the target type:
;   set   → keycode sub-program target: skip the range check (0877 → 087D)
;           and encode Prg Src Flag 8 into the new SCOM[0] — the normal
;           P→R path, partition-independent (P→R entry step is 284,
;           constant rows 51+).
;   clear → RAM-program target: 0871 loads SCOM[13], whose mantissa also
;           holds the PROGRAM-partition register count (30 under 239.89,
;           60 under 479.59); the compare at 087B range-checks the target
;           register — in range → commit, out of range → 0B0A abandons
;           the transfer, leaving any source flag written by the launch
;           prologue (0A4D) in place.
; The new calculator PC is committed to SCOM[0] at 088E/088F. fB[0] is not
; persisted state: the launch prologue derives it fresh each launch from
; the caller's Prg Src Flag (dispatch at 0A59 — keyboard/RAM callers set it
; at 0A5E, library callers take the 0D83 path and leave it clear). Quirk: a
; P/R pressed in the halt state left by the R/S-resumed SBR 444 run
; launches with SCOM[0] still saying source 1, so it reaches the 0872 test
; with fB[0] clear and the keycode sub-program target mis-routes into the
; RAM range check — see examples/texas-print.ti59.
0863: 0A87  MOV R5,#8
0864: 09F3  B=R5 MANT
0865: 0988  A=A-B MANT
0866: 0D24  C=C+1 MLSD1
0867: 1805  JC 0865
0868: 0983  B=A+B MANT
0869: 0D2C  C=C-1 MLSD1
086A: 1002  JNC 086B ; clear COND
086B: 0964  C=SLC MANT
086C: 0994  C=C+B MANT
086D: 0AD7  MOV R5,#13
086E: 02F3  B=R5 DPT
086F: 0111  IO=B ALL
0870: 0A1F  RCLF
0871: 01D3  B=LOAD ALL
0872: 0008  TST fB[0]
0873: 0A1F  RCLF
0874: 01D0  A=LOAD ALL
0875: 1806  JC 0878
0876: 0509  IO=A-1 LLSD1
0877: 180C  JC 087D
0878: 095B  B=SRB MANT
0879: 095B  B=SRB MANT
087A: 095B  B=SRB MANT
087B: 099B  B=C-B MANT
087C: 1D1C  JC 0B0A
087D: 014B  B=SRA ALL
087E: 095B  B=SRB MANT
087F: 095B  B=SRB MANT
0880: 095B  B=SRB MANT
0881: 095B  B=SRB MANT
0882: 095B  B=SRB MANT
0883: 0953  B=SLB MANT
0884: 0953  B=SLB MANT
0885: 0953  B=SLB MANT
0886: 0953  B=SLB MANT
0887: 0953  B=SLB MANT
0888: 0993  B=C+B MANT
0889: 0008  TST fB[0]
088A: 1004  JNC 088C
088B: 06DB  B=0 EXP
088C: 0C53  B=SLB MAEX
088D: 0910  A=B MANT
088E: 0A0F  STOF
088F: 0101  IO=A ALL
0890: 01D5  C<>D ALL
0891: 00B9  SET fB[11]
0892: 01D7  A<>E ALL
0893: 1DB7  JC 05B8
0894: 1FA8  JC 0C68           ; If flg test (04AF)
0895: 0F21  IO=C+1 MAEX1      ; DISP_FORMAT skipped while a sub-program / library runs (0553)
0896: 1804  JC 0898
0897: 0099  SET fB[9]
0898: 0030  TST fA[3]
0899: 000E  MOV fB[0],fA[0]
089A: 0A02  CLR fA
089B: 0026  MOV fA[2],fB[2]
089C: 0006  MOV fA[0],fB[0]
089D: 0009  SET fB[0]
089E: 0A0D  SWAP KR,SR
089F: 0059  SET fB[5]
08A0: 1804  JC 08A2
08A1: 0031  SET fA[3]
; Continue a keycode sub-program / library run (from 07C5, 06BB/06BD).
08A2: 00E8  TST fB[14]
08A3: 001A  CLR fB[1]
08A4: 16A2  JNC 0BF5
08A5: 01D2  A<>B ALL
; (The run loop enters at 08A5 from 07CA, 07D5 and 07DD.)
; Δ [?] CLR fA[9] is new: every RAM/module step fetch now starts with fA[9]
; (2nd pending / register read marker) clear. Defensive — no TI-59 case
; found where fA[9] is still set here (coverage scenarios + 17 test programs).
08A6: 0092  CLR fA[9]         ; fA[9] (2nd pending) clear for the next step
; ═══════════════════════════════════════════════════════════════════════════
; PRGREG_FETCH  (0x08A7–0x08BA, 0x0B86–0x0B94) — advance the program step and
; fetch its keycode. Trace-confirmed (LRN entry/store, SST/BST, run).
; Step counter = SCOM[0] nibbles 4–7: nibble 4 = byte 0–7 within the 8-step
; program register, nibbles 5–7 = register number (BCD); nibble 3 = Prg Src
; Flag (KR[4..7] after 08AA): 1 → library module (081F), 8 → keycode table in
; the constant ROM (0B95), 0 → RAM.
; SCOM[10] caches the current program register as a SHIFT REGISTER: the
; current step's keycode is in nibbles 1..0; each advance within the register
; shifts it right by one keycode (0EE3–0EE7). fB[11] = cache invalid: the next
; fetch reads the register from RAM (0B90) instead of shifting the cache.
; fB[11] clear → advance: byte + 1; at byte 7 the step carries into the next
; register (08B5–08B8) and fB[11] is set so that register gets loaded.
; ═══════════════════════════════════════════════════════════════════════════
08A7: 0A1F  RCLF              ; SCOM[0] (bus zero → row 0) …
08A8: 01D0  A=LOAD ALL
08A9: 0948  A=SRA MANT        ; … A[3] := byte, A[4..6] := register; R5 := Prg Src Flag
08AA: 0A18  MOV KR[4..7],R5
08AB: 06F6  D=R5 EXP
08AC: 0A45  TST KR[4]         ; library program?
08AD: 111D  JNC 081F          ; yes → fetch from the module (LIB_EXEC_ENTRY 081F)
08AE: 00B8  TST fB[11]        ; cache invalid?
08AF: 15BC  JNC 0B8D          ; yes → reload without advancing
08B0: 0A67  MOV R5,#6
08B1: 09F6  D=R5 MANT
08B2: 05B9  IO=A-D LLSD1      ; byte < 7?
08B3: 0500  A=A+1 LLSD1       ; byte + 1
08B4: 15A4  JNC 0B86          ; yes → store the step
08B5: 00B9  SET fB[11]        ; byte 7 → next register (+2 more at nibble 3 carries) and reload
08B6: 0D00  A=A+1 MLSD1
08B7: 0D00  A=A+1 MLSD1
08B8: 1D9C  JC 0B86
08B9: 1615  JNC 05AF          ; after a printed trace line: DISP_FORMAT cleanup
08BA: 1E56  JC 0BE5
; ═══════════════════════════════════════════════════════════════════════════
; SELF-TEST 2  (0x08BB–0x08CC → 0x09D7–0x09DC) — factory self-test entry
; 0C02 (dispatched from 07B5, see 0DB7). Builds 0000000092540100 in B and
; compares it with constant-ROM entry 63 (KR[4..6] = 7, KR[8..10] = 7 →
; index 7 + 8·7), sharing the compare with test 1 at 09D7. Trace-checked:
; the values match and the self-test goes on to test 3.
; ═══════════════════════════════════════════════════════════════════════════
; Δ [ENH] new (diagnostics). The TI-59 TAN KERNEL CORDIC loop that sat here
; (08C6–08DB) moved to 0C52–0C67 [REORG].
08BB: 01D8  A=0 ALL           ; build the expected value of constant 63 …
08BC: 05D8  A=-1 LLSD1
08BD: 0940  A=SLA MANT
08BE: 0D00  A=A+1 MLSD1
08BF: 0D00  A=A+1 MLSD1
08C0: 0940  A=SLA MANT
08C1: 0B00  A=A+5 MLSD5
08C2: 0940  A=SLA MANT
08C3: 0B00  A=A+5 MLSD5
08C4: 0D08  A=A-1 MLSD1
08C5: 07D0  A=LOAD EXP1
08C6: 0140  A=SLA ALL         ; … A = 0000000092540100
08C7: 0095  SET KR[9]         ; constant index high part: KR[8..10] = 7 …
08C8: 0085  SET KR[8]
08C9: 00A5  SET KR[10]
08CA: 01D2  A<>B ALL          ; B := expected value
08CB: 0A77  MOV R5,#7         ; … low part 7 (set at 09D7): constant 63
08CC: 1216  JNC 09D7          ; → shared compare (COND is 0 here: borrow at 08C4)
; Jump-range trampolines for 04E0/04E1 (→ 0CBC/0CBD → …), as TI-59 08DC/08DD.
; Δ [REORG] TI-59 08D8–08DB (arc-mode CORDIC tail) moved to 0C64–0C67.
08CD: 1FDE  JC 0CBC           ; (from 04E0)
08CE: 1FDE  JC 0CBD           ; (from 04E1)
; Arc functions (slot 0501): atan → 0CC3; asin/acos first form x/√(1−x²) or
; √(1−x²)/x (slots 0502–0504), then all run the CORDIC backwards (0505).
08CF: 00B0  TST fA[11]        ; INV tan?
08D0: 1FE6  JC 0CC3           ; INV tan → atan (0CC3)
08D1: 0A0D  SWAP KR,SR
08D2: 0A57  MOV R5,#5
08D3: 0A18  MOV KR[4..7],R5
08D4: 1E69  JC 05A0
; OP_DISPATCH (after slot 0102 collected nn): Op 50–99 → error (0CD1 → 0CCB);
; Op 40 → 0BFA, printer test: sets user flag 7 if the printer is connected
; (no printer: flag 7 unchanged; trace-checked); Op 41–49 → error; Op 2x / 3x
; → 0CAD: increment / decrement data register x (fA[11] = decrement) through
; the register read-modify-write path; Op 00–19 → 0CA8 → computed jump into
; OP_TABLE at 0x0A00 + 16·tens + units (0F8A). Trace-checked for Op 39, 40,
; 41, 45, 49, 50, 59, 99 on the TI-58C (TI-59: Op 40–99 are all errors).
08D5: 01D7  A<>E ALL          ; A := nn
08D6: 0948  A=SRA MANT
08D7: 02F6  D=R5 DPT          ; D[0] := units digit (R5 latched at 08D6)
; Δ [ENH] TI-59 08EA–08EF: Op 40 (printer present → flag 7) is new; the
; 00–39 split (TI-59 08EB–08EF) moved to 0CA4.
08D8: 0BD6  D=LOAD MLSD5      ; D[3] := 5
08D9: 09B9  IO=A-D MANT       ; nn ≥ 50?
08DA: 1FEE  JC 0CD1           ; yes → error
08DB: 0A47  MOV R5,#4
08DC: 09F6  D=R5 MANT
08DD: 09B9  IO=A-D MANT       ; nn ≥ 40?
08DE: 178C  JNC 0CA4          ; nn < 40 → 00–19 / 20–39 split (0CA4)
08DF: 0239  IO=-D DPT         ; 40–49: units digit 0?
08E0: 17E2  JNC 0CD1          ; no (41–49) → error
08E1: 1E32  JC 0BFA           ; Op 40 → printer test (0BFA)
; Unused filler: A=A ALL (no-op) words, never executed.
08E2: 0100  A=A ALL
08E3: 0100  A=A ALL
08E4: 0100  A=A ALL
08E5: 0100  A=A ALL
08E6: 0100  A=A ALL
08E7: 0100  A=A ALL
08E8: 0100  A=A ALL
08E9: 0100  A=A ALL
08EA: 0100  A=A ALL
08EB: 0100  A=A ALL
; Range reduction before the CORDIC (slot 052E): very small angles skip the
; kernel (sin θ ≈ θ, exponent ≤ −7 → 0C82); otherwise 0C8E/0FCE–0FE5 fold
; θ ∈ [0, 2π) into [0, π/4] by subtracting π/4 multiples, toggling the
; result sign (fA[2]) and the sin↔cos role (fA[12]) per octant.
08EC: 00B0  TST fA[11]        ; tan?
08ED: 1804  JC 08EF
08EE: 0051  SET fA[5]
08EF: 0030  TST fA[3]         ; arc functions (slot 0505): CORDIC backwards
08F0: 0D09  IO=A-1 MLSD1
08F1: 1F3A  JC 0C8E
08F2: 0A77  MOV R5,#7         ; |θ| < 10^−7?
08F3: 06F3  B=R5 EXP
08F4: 0689  IO=A-B EXP
08F5: 1F1A  JC 0C82           ; yes → small-angle result
08F6: 0090  TST fA[9]
08F7: 11ED  JNC 0801
08F8: 06D8  A=0 EXP
08F9: 1F26  JC 0C8C
08FA: 1615  JNC 05F0
; log x final step (slot 051D): ln x ÷ ln 10. 08FC is also the 10^x entry
; (× ln 10, fA[1] preset at 0605).
08FB: 0051  SET fA[5]
08FC: 0A0C  MOV KR,EXT[4..15] ; constant 0 …
08FD: 01D8  A=0 ALL
08FE: 01C0  A=A+CON ALL       ; … A := ln 10
08FF: 0032  CLR fA[3]
0900: 0022  CLR fA[2]
0901: 1B23  JC 0770           ; → MULDIV (fA[1] toggled: ÷ for log, × for 10^x)
; Int (slot 051F): keep the integer digits — shift the mantissa by the
; exponent and truncate (0B39); |x| < 1 → 0 (0817). The original X stays in D
; for INV Int (0496). Trace-confirmed (2.7 Int → 2, INV Int → 0.7).
0902: 0106  D=A ALL           ; D := X (for INV Int)
0903: 0A06  MOV R5,fA[1..4]
0904: 02F6  D=R5 DPT
0905: 0D09  IO=A-1 MLSD1      ; zero?
0906: 0012  CLR fA[1]
0907: 0030  TST fA[3]         ; |x| < 1?
0908: 11E3  JNC 0817          ; yes → 0
0909: 0940  A=SLA MANT        ; align by the exponent …
090A: 072C  C=C-1 EXP1
090B: 1805  JC 0909
090C: 145A  JNC 0B39          ; … and drop the fraction
; SBR / label-key call (slot 0B13): read SCOM[9] (library page) and push a
; return level unless the call comes from the keyboard with no program
; running (fB[0]/fB[13] clear → 0BAC: just start running).
090D: 0A97  MOV R5,#9
090E: 02F6  D=R5 DPT
090F: 0131  IO=D ALL
0910: 0A1F  RCLF
0911: 01D3  B=LOAD ALL        ; B := SCOM[9]
0912: 0C5E  D=SRB MAEX
0913: 0C7E  D=SRD MAEX
0914: 0008  TST fB[0]         ; called from a running program …
0915: 00D8  TST fB[13]        ; … or single step?
0916: 1D2C  JC 0BAC           ; no → keyboard call: start the run without a return level
0917: 02DB  B=0 DPT
0918: 0939  IO=-D MANT
0919: 1A66  JC 0A4C
091A: 03D3  B=LOAD DPT1       ; R/S resume of a library program (0BBB)
091B: 1A62  JC 0A4C
091C: 1FE4  JC 0D0E
091D: 1FE4  JC 0D0F           ; Pgm (slot 053C) → PGM_SELECT
091E: 0080  TST fA[8]         ; List (slot 0538) → LIST loop (0D12)
091F: 0052  CLR fA[5]
; Δ [FIX] new: List drops a pending Ind (fA[7]). TI-59: "Ind List" starts
; one step late and prints step 001's operand as a label ("001 12 B" for a
; STO 12 at 000); TI-58C lists from 000 normally (both trace-checked).
0920: 0072  CLR fA[7]         ; drop a pending Ind
0921: 1FE2  JC 0D12           ; → LIST
0922: 014E  D=SRA ALL
0923: 0A1F  RCLF
0924: 01D3  B=LOAD ALL
0925: 017E  D=SRD ALL
0926: 1FCE  JC 0D0D
; Keycode-program launch (slot 053E): descriptor = entry step (B) + source 8
; → launch prologue 0A3F/0A4D.
0927: 01D7  A<>E ALL
0928: 0103  B=A ALL
0929: 1A2C  JC 0A3F
; Op 00 / 05 / 06 (OP_TABLE 0A00/0A05/0A06; Op 06 prints X with the four
; characters loaded by Op 04): the Op number (D[0]) into A (E) and straight
; to the print-op sequence's slot 0545 (→ 0934), skipping the Int(X) slots
; 053F–0544 that Op 01–04 need.
092A: 01D7  A<>E ALL
; Δ [REORG] TI-59 0938 (MOV R5,#6, Op 06 only): Op 00 and 05 now share this
; entry (TI-59: via 0805 → 053F); output identical (trace-checked Op 00/05/06).
092B: 0231  IO=D DPT          ; R5 := D[0] = Op number (0, 5 or 6)
092C: 09F0  A=R5 MANT
092D: 01D7  A<>E ALL
092E: 00E5  SET KR[14]
092F: 00C5  SET KR[12]
0930: 00A5  SET KR[10]
0931: 0A57  MOV R5,#5         ; slot 0545
0932: 0A18  MOV KR[4..7],R5
0933: 0A0D  SWAP KR,SR
0934: 0053  TOG fA[5]         ; print-op / partition sequence tail
0935: 0050  TST fA[5]
0936: 1FB6  JC 0D11           ; → print / partition engine (0D11 → 0FFF → 1332 → 165A)
0937: 00A9  SET fB[10]
0938: 1E63  JC 0607           ; → display X
0939: 1691  JNC 05F1
; Δ [REORG] TI-59 0947–0951 (atan prologue, undefined-Op error) moved to
; 0CC3–0CCD.
093A: 0708  A=A-1 EXP1        ; fixed layout step: exponent − 1 …
093B: 0030  TST fA[3]
093C: 1806  JC 093F
093D: 0948  A=SRA MANT        ; … positive: one more integer digit (shift right)
093E: 1F6F  JC 0587
093F: 0308  A=A-1 DPT1        ; … negative: one more leading zero
0940: 0309  IO=A-1 DPT1
0941: 1F75  JC 0587
0942: 0036  MOV fA[3],fB[3]   ; doesn't fit fixed format → scientific layout
0943: 1FBB  JC 0566
0944: 0050  TST fA[5]         ; DEG: direction — to radians: ÷ 180/π, from radians: ×
0945: 1804  JC 0947
0946: 0011  SET fA[1]
0947: 0A77  MOV R5,#7         ; constant 15 = 180/π …
0948: 0A18  MOV KR[4..7],R5
0949: 1899  JC 08FD           ; … via 08FD → MULDIV (fA[1] toggled at 0770)
094A: 0050  TST fA[5]         ; GRAD: direction (opposite sense: × π/200 to radians)
094B: 1004  JNC 094D
094C: 0011  SET fA[1]
094D: 0A57  MOV R5,#5         ; constant 13 …
094E: 0A18  MOV KR[4..7],R5
094F: 01D8  A=0 ALL
0950: 01C0  A=A+CON ALL       ; … = 1.5707963E01
0951: 0031  SET fA[3]         ; exponent negative …
0952: 0700  A=A+1 EXP1        ; … and 02: 1.5707963E−02 = π/200
0953: 18A7  JC 0900           ; → MULDIV
; ═══════════════════════════════════════════════════════════════════════════
; ARG_KEY  (0x0954–0x097C) — a key arriving while an argument is pending
; (fB[12], from 06A0). Fetch SCOM[13] into D (the stack status); with the Pgm
; mark (nibble 15, set by a "Pgm nn" step) clear, classify the key (05BF).
; 096C–097C: the classifier's verdicts — digit (→ 0970) or not (→ 0973).
; ═══════════════════════════════════════════════════════════════════════════
; Δ [REORG] TI-59 06DB–06F2 and 075F–076F joined here, same code. The
; PROG_OPERAND / PGM_IN_PROGRAM code that sat here on the TI-59 (096C–098F)
; is at 0D34–0D57 (reached via 09FF).
0954: 0AD7  MOV R5,#13
0955: 02F3  B=R5 DPT
0956: 0111  IO=B ALL
0957: 0A1F  RCLF              ; SCOM[13] …
0958: 01D6  D=LOAD ALL        ; D := SCOM[13]
0959: 01D5  C<>D ALL
095A: 0E2C  C=C-1 MMSD1       ; Pgm mark (SCOM[13] nibble 15) set?
095B: 01D5  C<>D ALL
095C: 173B  JNC 05BF          ; no → classify
095D: 0AB5  TST KR[11]        ; yes (only while single-stepping after a Pgm nn step): sort the
                              ;   key —
095E: 0AA5  TST KR[10]
095F: 0A95  TST KR[9]
0960: 0A55  TST KR[5]
0961: 100E  JNC 0968
0962: 0A75  TST KR[7]
0963: 1A1C  JC 0A71
0964: 0A65  TST KR[6]
0965: 1006  JNC 0968
0966: 0A45  TST KR[4]
0967: 158D  JNC 06A1
0968: 0111  IO=B ALL          ; … other keys: SCOM[13] written back with the mark cleared, the
                              ;   pending operation dropped (097A)
0969: 0A0F  STOF
096A: 0131  IO=D ALL
096B: 181E  JC 097A           ; → argument mode off
096C: 0A65  TST KR[6]         ; argument key (from 05CB): digit (→ 0970) or not (→ 0973)
096D: 180C  JC 0973
096E: 0A55  TST KR[5]
096F: 1808  JC 0973
; Digit key in argument mode: dispatch it normally (06A9) — DIGIT_SLIDE then
; routes it to the collector because fB[12] is set (02F7).
0970: 0008  TST fB[0]
0971: 00D8  TST fB[13]
0972: 1D93  JC 06A9
0973: 02D7  A<>E DPT          ; non-digit key in argument mode: digits already collected?
0974: 0309  IO=A-1 DPT1
0975: 02D7  A<>E DPT
0976: 1BF1  JC 077E           ; yes → it terminates the argument (077E → ARG_TERMINATE)
0977: 0000  TST fA[0]         ; none yet: a transfer address (fA[0]) or Ind (fA[7]) pending?
0978: 0070  TST fA[7]
0979: 0002  CLR fA[0]
097A: 00CA  CLR fB[12]        ; argument mode off either way
097B: 1200  JNC 0A7B          ; yes → the key is a label (0A7B)
097C: 1DE9  JC 0688           ; no: the operation is dropped and the key runs normally ("5 STO
                              ;   x²" → 25)
097D: 0A85  TST KR[8]
097E: 1017  JNC 0973
097F: 0A95  TST KR[9]
0980: 1F6D  JC 05CA
0981: 0A75  TST KR[7]
0982: 0A45  TST KR[4]
0983: 1021  JNC 0973
0984: 0A65  TST KR[6]
0985: 1DB9  JC 06A9
0986: 0A55  TST KR[5]
0987: 0A95  TST KR[9]
0988: 00A8  TST fB[10]
0989: 102D  JNC 0973
098A: 1DC3  JC 06A9
; ═══════════════════════════════════════════════════════════════════════════
; LRN_KEY  (0x098B–0x09A4) — every key in LRN mode arrives here from the
; print gate (0689: fB[10] set). Trace-confirmed (headless: LRN 5 + sin STO
; 12, BST, SST, Ins, Del). The keys that edit the program act at once — SST
; and BST (05EB), Ins and Del (0CD5), LRN itself (06A9 → 0404) and the
; prefixes 2nd/INV; every other key is encoded (KEY_ENCODE 0784) and stored
; at the current step (0D5C → LRN_STORE). Digit keys pass DIGIT_SLIDE first
; (0A89 → 06A9), which hands them to 05F7 because fB[10] is set (02F9).
; Keys that take an argument (STO nn, GTO …) suspend through ARG_COLLECT as in
; run mode (0992/0B3D), so their digits are recorded as separate steps.
; ═══════════════════════════════════════════════════════════════════════════
098B: 00C8  TST fB[12]        ; argument pending (after STO etc.)?
098C: 179B  JNC 05BF          ; yes → argument key classification
098D: 0A0D  SWAP KR,SR        ; SR := 0x6200: continuation for PRGREG_FETCH …
098E: 0A0C  MOV KR,EXT[4..15]
098F: 00D5  SET KR[13]
0990: 00E5  SET KR[14]
0991: 0095  SET KR[9]
0992: 00C8  TST fB[12]
0993: 13BD  JNC 07B5
0994: 0A0D  SWAP KR,SR        ; … KR = the key's matrix position again
0995: 0AB5  TST KR[11]        ; classify by column / row bits:
0996: 104E  JNC 09BD
0997: 0AA5  TST KR[10]
0998: 167A  JNC 0CD5
0999: 0A95  TST KR[9]
099A: 138A  JNC 0B5F
099B: 0A75  TST KR[7]
099C: 100A  JNC 09A1
099D: 0A65  TST KR[6]
099E: 1767  JNC 05EB
099F: 0A55  TST KR[5]
09A0: 15EF  JNC 06A9
09A1: 0082  CLR fA[8]
09A2: 01DE  D=0 ALL
09A3: 1C3F  JC 0784           ; → KEY_ENCODE, then store
09A4: 1B30  JC 0B3C
; EXP argument-reduction helpers (09A5–09F6): align the remaining argument,
; detect exponent overflow/underflow (09AD → 05EA), handle |x| < 1 (09E5).
09A5: 032C  C=C-1 DPT1
09A6: 1084  JNC 09E8
09A7: 0C64  C=SLC MAEX
09A8: 0E09  IO=A-1 MMSD1
09A9: 174D  JNC 0603
09AA: 0C5B  B=SRB MAEX
09AB: 0D29  IO=C-1 MLSD1
09AC: 157B  JNC 06EF
09AD: 0020  TST fA[2]         ; n out of range: overflow for positive x, underflow for negative
09AE: 0032  CLR fA[3]
09AF: 1F8B  JC 05EA
09B0: 0033  TOG fA[3]
09B1: 0023  TOG fA[2]
09B2: 1F91  JC 05EA
09B3: 0A85  TST KR[8]
09B4: 1602  JNC 0CB5
09B5: 0A75  TST KR[7]
09B6: 17A7  JNC 05E3
09B7: 0A65  TST KR[6]
09B8: 1E0C  JC 0CBE
09B9: 0A55  TST KR[5]
09BA: 1528  JNC 0C4E
09BB: 0082  CLR fA[8]
09BC: 1E27  JC 06A9
09BD: 0AA5  TST KR[10]
09BE: 0A95  TST KR[9]
09BF: 0A75  TST KR[7]
09C0: 103F  JNC 09A1
09C1: 0A65  TST KR[6]
09C2: 1843  JC 09A1
09C3: 0A85  TST KR[8]
09C4: 1640  JNC 0CE4
09C5: 0A55  TST KR[5]
09C6: 104B  JNC 09A1
09C7: 0A45  TST KR[4]
09C8: 1E2A  JC 0CDD
09C9: 0080  TST fA[8]
09CA: 1FC7  JC 05E7
09CB: 1055  JNC 09A1
; ═══════════════════════════════════════════════════════════════════════════
; SELF-TEST 1  (0x09CC–0x09DC) — factory self-test entry 0C01 (dispatched
; from 07B5, see 0DB7). Builds 0000000999999500 in B and compares it with
; constant-ROM entry 7 = ln(1+10^−6) (09D7–09DB, shared with test 2 at
; 08BB). Equal → 0DC3: print the next test number, run the next test;
; different → 09DD: abort. Trace-checked (all tests pass, numbers 1–11).
; SELF-TEST EXIT  (0x09DD–0x09E1): wait for the printer, KR := 0, → 07B5 →
; PREG = 0x0000, i.e. restart at the reset vector (derived; the emulator
; treats a PREG target of 0 as "no jump" and runs on at 07B7).
; ═══════════════════════════════════════════════════════════════════════════
; Δ [ENH] new (diagnostics). The TI-59 CORDIC y-step (09DF–09E9) moved to
; 0C98–0CA2 [REORG].
09CC: 01DB  B=0 ALL           ; build the expected value of constant 7 …
09CD: 0A57  MOV R5,#5
09CE: 06F3  B=R5 EXP
09CF: 06F0  A=R5 EXP          ; loop count
09D0: 0953  B=SLB MANT
09D1: 05DB  B=-1 LLSD1
09D2: 1002  JNC 09D3 ; clear COND
09D3: 0708  A=A-1 EXP1
09D4: 1809  JC 09D0
09D5: 0653  B=SLB EXP         ; … B = 0000000999999500
09D6: 0A77  MOV R5,#7
09D7: 0A18  MOV KR[4..7],R5   ; constant index (test 2 enters here with KR[8..10] = 7)
09D8: 01D8  A=0 ALL
09D9: 01C0  A=A+CON ALL       ; A := constant
09DA: 018B  B=A-B ALL
09DB: 0119  IO=-B ALL         ; equal?
09DC: 1FCE  JC 0DC3           ; yes → next test number (0DC3)
09DD: 0A98  PRT.STEP          ; self-test exit (mismatch here, or 0DD6 after the last test):
                              ;   drain the printer …
09DE: 0A0B  TST.BUSY
09DF: 1005  JNC 09DD
09E0: 0A0C  MOV KR,EXT[4..15] ; KR := 0 …
09E1: 1C59  JC 07B5           ; … → SET KR[1] at 07B5: PREG 0 = restart (self-test dispatch:
                              ;   0DDA → 09E1 → 07B5 → 0C0n)
09E2: 1728  JNC 0D76
09E3: 1FD5  JC 05F9
09E4: 0C48  A=SRA MAEX
09E5: 072C  C=C-1 EXP1        ; |x| < 1: shift the argument right by its exponent
09E6: 1805  JC 09E4
09E7: 06DC  C=0 EXP
09E8: 0CD2  A<>B MAEX
09E9: 0E09  IO=A-1 MMSD1
09EA: 1806  JC 09ED
09EB: 0C53  B=SLB MAEX
09EC: 0C40  A=SLA MAEX
09ED: 0020  TST fA[2]
09EE: 180A  JC 09F3
09EF: 0C8B  B=A-B MAEX
09F0: 0031  SET fA[3]
09F1: 0724  C=C+1 EXP1
09F2: 17D5  JNC 0608
09F3: 004A  CLR fB[4]         ; kernel in exp mode …
09F4: 0620  A=C EXP
09F5: 0C14  C=B MAEX
09F6: 1D71  JC 073E           ; … → KERNEL
; External program entry (from 064F, KR line at D10 in the idle loop): KR :=
; 0x8001, SET KR[1] → PREG = KR>>4 | KR[0]·0x1000 = 0x1800, just beyond the
; 6K ROM — presumably test-fixture program memory. Trace-checked: holding
; that line makes the emulator jump to 1800.
; Δ [ENH] new, TI-58C only (09F7–09FF); 09FD–09FE is the self-test entry,
; 09FF a jump-range trampoline for STEP_DISPATCH (082F → 0D34).
09F7: 0A01  CLR.IDLE          ; display off
09F8: 0A0C  MOV KR,EXT[4..15] ; KR := 0
09F9: 0005  SET KR[0]         ; address bit 12 …
09FA: 00F5  SET KR[15]        ; … + bit 11: target 0x1800
09FB: 0015  SET KR[1] ; PREG  ; jump there …
09FC: 000D  CLR KR[0]         ; … after this delay slot
; Self-test entry (from 064C: KN at D15 in the idle loop; 0666: KN on row 8/9).
09FD: 0A01  CLR.IDLE          ; display off
09FE: 1F72  JC 0DB7           ; → self-test (0DB7: print test numbers, dispatch tests via 07B5)
09FF: 166A  JNC 0D34          ; operand step while an argument is pending (082F) → PROG_OPERAND
                              ;   0D34

; ── CD2401   0x0A00–0x13FF  2,560 words  (ROM chip 2) ────────────────────

; ═══════════════════════════════════════════════════════════════════════════
; OP_TABLE  (0x0A00–0x0A19) — Op 00–19, slot 0x0A00 + 16·tens + units (BCD;
; 0x0A0A–0x0A0F are ordinary code). Functions as in the TI-59 manual; the
; TI-58C-only Op 40 is decoded in OP_DISPATCH (08DE–08E1 → 0BFA). Trace-
; confirmed with the headless harness (tools/headless/coverage.py op*).
; ═══════════════════════════════════════════════════════════════════════════
0A00: 19AD  JC 092A           ; Op 00: clear the alphanumeric print buffer — enters the print-op
                              ;   sequence at slot 0545 (092A, the Op 06 entry), not via 07F9 /
                              ;   053F as on the TI-59; same printout
0A01: 1C11  JC 07F9           ; Op 01: load print columns 1–5 from X
0A02: 1C13  JC 07F9           ; Op 02: columns 6–10
0A03: 1C15  JC 07F9           ; Op 03: columns 11–15
0A04: 1C17  JC 07F9           ; Op 04: columns 16–20
0A05: 19B7  JC 092A           ; Op 05: print the alphanumeric buffer (via 092A, as Op 00 / 06)
0A06: 19B9  JC 092A           ; Op 06: print X with the 4 characters of Op 04
0A07: 1C1D  JC 07F9           ; Op 07: plot (asterisk at column X)
0A08: 1BF5  JC 080E           ; Op 08: list the labels
0A09: 1F5A  JC 0DB6           ; Op 09: download the selected library program into RAM (0DB6 →
                              ;   11AB)
0A0A: 03D3  B=LOAD DPT1       ; Op 15: variant 1
0A0B: 1F40  JC 0DAB
; ln of zero / non-positive argument: ERROR.
0A0C: 0099  SET fB[9]
0A0D: 0051  SET fA[5]
0A0E: 18BB  JC 09B1
0A0F: 17DF  JNC 0620
0A10: 1FD2  JC 0DF9           ; Op 10: signum of X
0A11: 1C23  JC 0800           ; Op 11: variance (statistics)
0A12: 1F30  JC 0DAA           ; Op 12: slope and intercept
0A13: 184E  JC 0A3A           ; Op 13: correlation coefficient
0A14: 1DA6  JC 0CE7           ; Op 14: y′ for a given x
0A15: 1817  JC 0A0A           ; Op 15: x′ for a given y
0A16: 00E9  SET fB[14]        ; Op 16: show the partition (fB[14] = query only), falls into …
0A17: 1C41  JC 07F7           ; Op 17: set the partition (n · 10 data registers)
0A18: 0081  SET fA[8]         ; Op 18: set flag 7 if no error (inverted test), falls into …
0A19: 1FD8  JC 0E05           ; Op 19: set flag 7 if an error is pending
; ── RAM_ACCESS (0x0A1A–0x0A24, from RAM_ADDR 0D9B) ───────────────────────────
; Δ [HW] TI-59 0A1A–0A23, 0A29: no RAM.OP bus word with a hex tens nibble
; for registers ≥ 100. RAM_ADDR (0D96–0D9D) has turned the BCD RAM index into
; the binary MEMRD/MEMWR address (0x00–0x3B) in A[1..0]. Dispatch: LRN →
; 0B17, read or Ind → RAM_READ 0D9E (Ind is told apart after the read, 0DA3;
; the TI-59 had a separate pointer read at 0DDC), write → RAM_WRITE 0DFE.
0A1A: 09D8  A=0 MANT          ; drop the exhausted BCD count: A[1..0] = binary RAM address
0A1B: 0106  D=A ALL           ; D := RAM address
0A1C: 00A8  TST fB[10]
0A1D: 11F4  JNC 0B17
0A1E: 0090  TST fA[9]         ; read …
0A1F: 0092  CLR fA[9]
0A20: 0070  TST fA[7]         ; … or Ind (pointer value needed)?
0A21: 16FA  JNC 0D9E          ; yes → RAM_READ (MEMRD)
0A22: 01D7  A<>E ALL          ; write: A := X …
0A23: 0051  SET fA[5]         ; (store-back entries: SUM / Prd 04DB → 076A → here; Dsz 03FB →
                              ;   076B → 0A24)
0A24: 1FB4  JC 0DFE           ; → RAM_WRITE (MEMWR)
; ═══════════════════════════════════════════════════════════════════════════
; PRN_LINE_RESCAN  (0x0A25–0x0A30) — idle-loop continuation (from 0659).
; Δ [HW] TI-58C only. The printer-present line is KP at digit 10 (TI-59: D0,
; below the scanned rows), so with a PC-100C attached the arming scan from
; D13 (0651) and the confirmation scan (0654) stop at "row 10" as if a key
; were held. 0656–0659 send rows 10/11 here; rows 14/15 are discarded.
; Both scans are repeated below the printer line, from D9: arming 0A2C–0A2E,
; then the confirmation scan 0654 (via 0A2F/0A30). While an error blinks,
; the blink counter gets one extra step per pass (0A29–0A2B, as at
; 0640–0644) because a pass with the printer is longer. Measured over 400k
; cycles: 44 dark phases with the printer, 35 without, 22 with 0A2A patched
; out — the blink keeps roughly its rate.
; ═══════════════════════════════════════════════════════════════════════════
0A25: 0A65  TST KR[6]         ; row 14/15?
0A26: 17D3  JNC 063D          ; yes → discard: top of the idle loop
0A27: 0098  TST fB[9]         ; error blinking?
0A28: 1808  JC 0A2C
0A29: 0CD5  C<>D MAEX         ; yes: blink counter (D[1..3]) + 1 …
0A2A: 0F24  C=C+1 MAEX1
0A2B: 0CD5  C<>D MAEX         ; …
0A2C: 0AA0  WAIT D10          ; arming scan again, starting below the printer line (rows 9..1)
0A2D: 0820  KEY [N,O,P,Q,S,T] ALL
0A2E: 1FE3  JC 063D           ; no key → top of the idle loop
0A2F: 0AB0  WAIT D11          ; key → confirmation scan, again from row 9 down …
0A30: 1FB9  JC 0654           ; … (0654)
0A31: 00C0  TST fA[12]        ; cos? (numerator 1 instead of t)
0A32: 00E1  SET fA[14]        ; tolerate overflow while squaring
0A33: 0106  D=A ALL           ; D := t
0A34: 0012  CLR fA[1]
0A35: 0A06  MOV R5,fA[1..4]
0A36: 02F6  D=R5 DPT
0A37: 1D8D  JC 0771           ; → t · t
0A38: 0ED6  D=LOAD MMSD1      ; cos: numerator 1.0
0A39: 1D91  JC 0771
0A3A: 01D7  A<>E ALL          ; Op 13: correlation keycode program
0A3B: 0AF7  MOV R5,#15
0A3C: 09F0  A=R5 MANT
0A3D: 0940  A=SLA MANT
0A3E: 0D0B  B=A-1 MLSD1
0A3F: 0A87  MOV R5,#8         ; keycode-program launch (0927): Prg Src Flag 8 → launch prologue
                              ;   0A4D
0A40: 02F3  B=R5 DPT
0A41: 0082  CLR fA[8]
0A42: 0AD7  MOV R5,#13        ; keycode sub-program launch: SCOM[13] nibble 2 = AOS depth …
0A43: 01F0  A=R5 ALL
0A44: 0101  IO=A ALL
0A45: 0A1F  RCLF
0A46: 06D0  A=LOAD EXP
0A47: 0C40  A=SLA MAEX        ; … into A[3]
0A48: 0B09  IO=A-5 MLSD5      ; five or more levels pending?
0A49: 1D0A  JC 0CCE           ; yes → error (the sub-program needs AOS levels of its own)
0A4A: 0110  A=B ALL           ; launch descriptor (entry step, source 8) → E
0A4B: 01D7  A<>E ALL
0A4C: 01D2  A<>B ALL
; ── Set Prg Src Flag: program-source switch of the launch prologue ──────────
; Rewrites SCOM[0] with nibble 3 (Prg Src Flag) := R5 while keeping the
; step counter in nibbles 4–7. Generic launch step: traced with R5=1
; (SBR into a library program, E descriptor "…444001" = target 444,
; source 1) and R5=8 (P→R keycode sub-program via KEY_PR, E "…284008" =
; entry step 284, source 8). Missing safeguard: the flag is written before
; the target-step range check at 0865–087C, so an abandoned launch leaves
; the new source flag in place — see examples/texas-print.ti59.
; The 0A4F–0A53 shuffle also stashes the CALLER's source (SCOM[0]'s old
; nibble 3) into nibble 1 of the rewritten SCOM[0]; 0A56–0A59 then dispatch
; on it (traces pr-after-halt1/2, memory/sbr444-quirk-analysis.md):
;   0        → keyboard/RAM caller: fall through to 0A5A; 0A5E/0A5F set
;              fB[0]+fB[13], so 0872 later skips the RAM range check.
;   non-zero → library caller: 0A59 branches to 0D83 to save the CROM PC
;              as the return address; fB[0]/fB[13] stay clear.
0A4D: 0A1F  RCLF
0A4E: 01D6  D=LOAD ALL
0A4F: 0C78  A=SRD MAEX
0A50: 0940  A=SLA MANT
0A51: 0201  IO=A DPT
0A52: 09F6  D=R5 MANT
0A53: 09B6  D=A+D MANT
0A54: 0A0F  STOF
0A55: 0131  IO=D ALL
0A56: 0948  A=SRA MANT
0A57: 064E  D=SRA EXP
0A58: 0639  IO=-D EXP
0A59: 1654  JNC 0D83
0A5A: 0309  IO=A-1 DPT1       ; keyboard / RAM caller:
0A5B: 0008  TST fB[0]         ; running already?
0A5C: 100E  JNC 0A63
0A5D: 00D8  TST fB[13]        ; no: start the run (fB[0]) as a sub-program call (fB[13])
0A5E: 0009  SET fB[0]
0A5F: 00D9  SET fB[13]
; Δ [FIX] TI-59 0A5E (JC 0A66): from the keyboard the TI-59 pushes the step
; counter unchanged. After a halt or SST the program-register cache is valid
; (fB[11] clear) and the counter names the step last executed, so R/S after a
; keyboard Σ+, x̄, D.MS, P→R, Op 11–15 runs that step again (program
; 1 2 3 4 5 R/S: RST SST SST Σ+ R/S → TI-59 "2345", TI-58C "345"; a halted
; R/S step costs one dead R/S). The TI-58C adds + 1 unless fB[11] is set
; (after GTO / RST the counter already is the next step).
0A60: 1006  JNC 0A63          ; was single-stepping (fB[13]) → + 1
0A61: 00B8  TST fB[11]        ; keyboard: cache stale …
0A62: 1010  JNC 0A6A          ; … → the counter is the next step: push it as is (else + 1)
0A63: 0A67  MOV R5,#6         ; running RAM program, SST or valid cache: return address = the
                              ;   step …
0A64: 09F6  D=R5 MANT
0A65: 05B9  IO=A-D LLSD1      ; … + 1; at byte 7 the extra +2 (0A68–0A69) carries into the next
                              ;   register
0A66: 0500  A=A+1 LLSD1
0A67: 1006  JNC 0A6A
0A68: 0D00  A=A+1 MLSD1
0A69: 0D00  A=A+1 MLSD1
0A6A: 0140  A=SLA ALL         ; → push the return level (0D33 → 0FFE → RET_PUSH 1334)
0A6B: 1D90  JC 0D33
; Trace-queue gate (from 0694/0699, printer + TRACE on; trace-confirmed on the
; TI-59: KEYPRESS_TRC_59.txt, same path here with --printer --trace).
; fA[10] = "trace record pending"; run twice per key — see the keystroke
; print/trace gate header at 0688.
0A6C: 00A0  TST fA[10]        ; record already queued for this keypress?
0A6D: 00A1  SET fA[10]        ; mark pending
0A6E: 17A9  JNC 069A          ; 2nd pass (was set) → normal dispatch at 069A
0A6F: 0041  SET fA[4]         ; 1st pass: tag "trace queue" (tested at 07A2)
0A70: 1DD9  JC 0784           ; → pack key position code, queue print symbol
; Δ [REORG] TI-59 0A6D–0A70 (end of CP / CMs → display X) is gone: CP / CMs
; now end at 0FE6–0FE9 → 0C00 → 0938.
0A71: 0A65  TST KR[6]         ; SST keeps stepping (→ 06A1 normal dispatch, trace-checked) …
0A72: 1A15  JC 0968
0A73: 0A45  TST KR[4]
0A74: 1219  JNC 0968
0A75: 1FA9  JC 06A1
0A76: 0082  CLR fA[8]
0A77: 0A65  TST KR[6]
0A78: 0A55  TST KR[5]
0A79: 11AF  JNC 09A2
0A7A: 1FA3  JC 06A9
0A7B: 0070  TST fA[7]         ; label key: Ind pending → 0C21
0A7C: 134A  JNC 0C21
0A7D: 0AB5  TST KR[11]
0A7E: 0A75  TST KR[7]
0A7F: 1016  JNC 0A8A
0A80: 0AA5  TST KR[10]
0A81: 1508  JNC 0D05
0A82: 0A95  TST KR[9]
0A83: 100E  JNC 0A8A
0A84: 0A65  TST KR[6]
0A85: 150A  JNC 0D0A
0A86: 0A55  TST KR[5]
0A87: 1806  JC 0A8A
0A88: 0A45  TST KR[4]
0A89: 17C1  JNC 06A9
0A8A: 00A8  TST fB[10]        ; LRN: record the label key's keycode as a step (09A1)
0A8B: 11D5  JNC 09A1
; Δ [REORG] TI-59 0A8C–0A8F flushed a pending TRACE record (fA[10],
; "0.  GTO") with PRT.GO before the label operand was built; the TI-58C does
; it afterwards: 0AA3–0AA6 → 0E0E → 11F4 → 15EF … → 0E0F → 0B1D PRT.GO →
; 07B0. Same printout (trace-checked, PC-100, TRACE: GTO E′, SBR E′).
0A8C: 0001  SET fA[0]         ; KEY_TO_KEYCODE: the label key's own keycode becomes the operand
                              ;   — tens = row (KR[4..7]), units = column code (KR[8..11], 2nd
                              ;   keys 6–10), column 10 → 0 (E′ = 10, tan = 30 …).
                              ;   Trace-checked: A → 11, C → 13, C′ → 18, E′ → 10.
0A8D: 01D7  A<>E ALL
0A8E: 0A08  MOV R5,KR[4..7]   ; tens := row …
0A8F: 0CF0  A=R5 MAEX
0A90: 0A07  MOV R5,#0         ; … units built in KR[4..7] from the column bits:
0A91: 0A18  MOV KR[4..7],R5
0A92: 0AB5  TST KR[11]        ; column 8–10?
0A93: 1808  JC 0A97
0A94: 0A95  TST KR[9]         ; column 10 → units 0 (0AA1)
0A95: 1018  JNC 0AA1
0A96: 0075  SET KR[7]         ; 8 / 9: bit 3
0A97: 0AA5  TST KR[10]        ; bits 2, 1, 0 copied from KR[10], KR[9], KR[8]
0A98: 1804  JC 0A9A
0A99: 0065  SET KR[6]
0A9A: 0A95  TST KR[9]
0A9B: 1804  JC 0A9D
0A9C: 0055  SET KR[5]
0A9D: 0A85  TST KR[8]
0A9E: 1804  JC 0AA0
0A9F: 0045  SET KR[4]
0AA0: 0A08  MOV R5,KR[4..7]
0AA1: 02F0  A=R5 DPT          ; A[1..0] := tens, units …
0AA2: 0140  A=SLA ALL
0AA3: 00A0  TST fA[10]        ; trace record pending (label key as operand, TRACE on)?
0AA4: 00A2  CLR fA[10]
0AA5: 1DEB  JC 07B0           ; no → ARG_COMPLETE: run the transfer with this label
0AA6: 16D0  JNC 0E0E          ; yes → print it first (0E0E → 11F4 → 15EF, back 0E0F → 0B1D)
; SQRT body (from 081A/081C)
0AA7: 0030  TST fA[3]         ; odd exponent: pre-shift the mantissa
0AA8: 1804  JC 0AAA
0AA9: 0700  A=A+1 EXP1
0AAA: 0948  A=SRA MANT
0AAB: 0022  CLR fA[2]         ; result positive
0AAC: 0148  A=SRA ALL
0AAD: 02D2  A<>B DPT
0AAE: 0148  A=SRA ALL
0AAF: 0204  C=A DPT
0AB0: 0C40  A=SLA MAEX
0AB1: 0C40  A=SLA MAEX
0AB2: 06DC  C=0 EXP
0AB3: 1824  JC 0AC5
0AB4: 0C5B  B=SRB MAEX        ; next root digit: halve the increment weight …
0AB5: 0C48  A=SRA MAEX
0AB6: 181C  JC 0AC4
0AB7: 0C9C  C=C-B MAEX        ; subtract the odd increment …
0AB8: 0C9C  C=C-B MAEX
0AB9: 0C83  B=A+B MAEX        ; … and grow it by 2·weight …
0ABA: 0C99  IO=C-B MAEX       ; … while the remainder allows
0ABB: 1809  JC 0AB7
0ABC: 01D2  A<>B ALL
0ABD: 0C88  A=A-B MAEX
0ABE: 01D2  A<>B ALL
0ABF: 0C94  C=C+B MAEX
0AC0: 1802  JC 0AC1 ; clear COND
0AC1: 0E29  IO=C-1 MMSD1
0AC2: 181D  JC 0AB4
0AC3: 0C64  C=SLC MAEX
0AC4: 0C48  A=SRA MAEX
0AC5: 0F09  IO=A-1 MAEX1      ; all digits done?
0AC6: 181D  JC 0AB8
0AC7: 0C10  A=B MAEX          ; result := B (2·root) adjusted …
0AC8: 0E09  IO=A-1 MMSD1
0AC9: 1862  JC 0AFA
0ACA: 0C40  A=SLA MAEX
0ACB: 1807  JC 0AC8
; Δ [REORG] TI-59 0ACD–0AD1 (SQRT result tail) moved to 0AFA–0AFE (0AC9).
0ACC: 1CC3  JC 086B
; EXP finish (from 075A): multiply the product by (1 + remaining r), then
; place the integer part n as the decimal exponent.
0ACD: 0C83  B=A+B MAEX
0ACE: 0E2C  C=C-1 MMSD1
0ACF: 1805  JC 0ACD
0AD0: 0C64  C=SLC MAEX
0AD1: 0C48  A=SRA MAEX
0AD2: 0F09  IO=A-1 MAEX1
0AD3: 180B  JC 0ACE
0AD4: 0140  A=SLA ALL
0AD5: 0210  A=B DPT
0AD6: 0140  A=SLA ALL
0AD7: 0910  A=B MANT
0AD8: 1DA5  JC 0806           ; → ARITH_EXIT
0AD9: 0A0D  SWAP KR,SR
0ADA: 189D  JC 0A8C
0ADB: 1502  JNC 0D5C
; Δ [REORG] Moved from TI-59 0AFD–0AFF: helper of 06FA (B := 1.0, swap,
; back to 06FC).
0ADC: 0ED3  B=LOAD MMSD1      ; B := 1.0 …
0ADD: 0CD2  A<>B MAEX
0ADE: 1FC5  JC 06FC           ; … → 06FC
; Division y ÷ x for the tan kernel (pseudo-division digit loop), result
; normalized through 0708.
0ADF: 0CB8  A=A-D MAEX
0AE0: 1265  JNC 09AE
0AE1: 0E2C  C=C-1 MMSD1
0AE2: 1807  JC 0ADF
0AE3: 0C64  C=SLC MAEX
0AE4: 0C7E  D=SRD MAEX
0AE5: 0F29  IO=C-1 MAEX1
0AE6: 180B  JC 0AE1
0AE7: 0E09  IO=A-1 MMSD1
0AE8: 1806  JC 0AEB
0AE9: 0C40  A=SLA MAEX
0AEA: 0308  A=A-1 DPT1
0AEB: 06D8  A=0 EXP
0AEC: 0E09  IO=A-1 MMSD1
0AED: 0C14  C=B MAEX
0AEE: 1010  JNC 0AF6
0AEF: 0903  B=A MANT
0AF0: 09D8  A=0 MANT
0AF1: 0E29  IO=C-1 MMSD1
0AF2: 1FD5  JC 0708
0AF3: 0C64  C=SLC MAEX
0AF4: 0700  A=A+1 EXP1
0AF5: 1809  JC 0AF1
0AF6: 0032  CLR fA[3]
0AF7: 0940  A=SLA MANT
0AF8: 0700  A=A+1 EXP1
0AF9: 181B  JC 0AEC
; Δ [REORG] SQRT result tail, moved here from TI-59 0ACD–0AD1 (from 0AC9).
0AFA: 0164  C=SLC ALL
0AFB: 0214  C=B DPT
0AFC: 0164  C=SLC ALL
0AFD: 0620  A=C EXP
0AFE: 1DF1  JC 0806           ; → ARITH_EXIT (also the error exit 0CCD and 0DA9 → here)
; Δ [REORG] TI-59 0AFF was the tail of the 0AFD helper (now 0ADE); this word
; is a hop of the Ind path: 1282 → 0E8B → 0AFF → 07AE (TI-59 0F34 → 0B5D →
; 07B2).
0AFF: 1EA3  JC 07AE           ; Ind resolved → ARG_COMPLETE (07AE) with the new register number
0B00: 01D7  A<>E ALL
0B01: 0001  SET fA[0]
0B02: 0A27  MOV R5,#2
0B03: 01F0  A=R5 ALL
0B04: 06F0  A=R5 EXP
0B05: 0140  A=SLA ALL
0B06: 01D7  A<>E ALL
0B07: 0072  CLR fA[7]
0B08: 00C9  SET fB[12]
0B09: 1AF9  JC 098D
; ── Transfer reject: target step out of range (from 087C) ───────────────────
; Sets the error blink and clears the transfer-type flag, then exits via
; 0890 WITHOUT undoing the launch: the Prg Src Flag written by the
; prologue (0A54) stays in SCOM[0], and the return-stack level pushed at
; 1334 is never popped (contrast the 11E2 error halt, which resets the
; stack). TI-59 trace pr-after-halt2: the abandoned P/R launch leaves SCOM[0]
; = "…108010" (leaked source 8, stashed caller source 1, step 008) and a
; dead stack level naming the leftover CROM position — the state quirk 3
; of examples/texas-print.ti59 builds on.
0B0A: 0099  SET fB[9]
0B0B: 000A  CLR fB[0]
0B0C: 1CF9  JC 0890
0B0D: 0A45  TST KR[4]
0B0E: 12E2  JNC 0C7F
0B0F: 1ADE  JC 0C7E
; ── 0x0B10 sequence bank (KR[15]+KR[13]+KR[12]+KR[8]): program-related slots.
0B10: 1C0A  JC 0D15           ; → REG_ADDR (via 084A, register operand)
0B11: 1E92  JC 0E5A           ; Ins / Del (via KEY_OP_ENTRY, labels OP_INS)
0B12: 1873  JC 0AD9           ; user label key A–E′: take the key itself as the label operand …
0B13: 1C0D  JC 090D           ; … push the return level (090D), set running (0BAC), then search
                              ;   (0852 → 0BCA)
0B14: 1DF2  JC 0E0D           ; St flg / INV St flg (04B0): → 0E0D → 11E1 → FLAG_OP
0B15: 1F50  JC 0EBD           ; BST (0411): step − 1
; Δ [HW] TI-59 0B16–0B1E: the LRN register access shifts the keycode up two
; nibbles only (0B17–0B18; the binary RAM address is 2 nibbles, the RAM.OP
; word was 4) and reads with MEMRD (0B1A → 0D9E). The trace-symbol queue
; entry (TI-59 0B16–0B17) moved to 0B1B–0B1C; 0B1D–0B1E are the PRT.GO
; tail of the label-operand trace flush (0AA6 … 0E0F).
0B16: 1774  JNC 0ED0          ; argument completed in LRN mode (07AB): record it
0B17: 0153  B=SLB ALL         ; LRN (0A1D): the new keycode up past the address …
0B18: 0153  B=SLB ALL
0B19: 0183  B=A+B ALL         ; … + RAM address
0B1A: 1D08  JC 0D9E           ; → RAM_READ of the program register (fB[10] → 1155)
0B1B: 0042  CLR fA[4]         ; trace-symbol queue (from KEY_ENCODE 07A3) …
0B1C: 1EDC  JC 0E8A           ; … → 1277 → trace-symbol queue
0B1D: 0AA8  PRT.GO            ; label-operand trace flush (from 0E0F): print the pending record
                              ;   …
0B1E: 1EDD  JC 07B0           ; … then ARG_COMPLETE (07B0)
0B1F: 0100  A=A ALL
; ── Compact keycodes (bank 0x0B20 + d, d = digit at the key position):
; 92 RTN, 82 HIR, 83 GO*, 84 OP*, 72 ST*, 73 RC*, 74 SM*, 62 PG*, 63 EX*,
; 64 PD* — the Ind forms go to 0EA4 (operation + fA[7]). Trace-confirmed for
; RTN and HIR (headless: HIR 05/15/33/43/53/63 programs).
0B20: 1E14  JC 0E2A           ; RTN (INV SBR, keycode 92) → 0E2A → RTN_POP 1175
0B21: 1DAB  JC 084C           ; 82 HIR → 084C → slot 00FA
0B22: 1F04  JC 0EA4           ; 83 GO* (Ind)
0B23: 0A0C  MOV KR,EXT[4..15] ; 84 OP*: KR cleared, then as the other Ind forms
0B24: 1F00  JC 0EA4           ; 72 ST*
0B25: 1EFE  JC 0EA4           ; 73 RC*
0B26: 1EFC  JC 0EA4           ; 74 SM*
0B27: 1EFA  JC 0EA4           ; 62 PG*
0B28: 1EF8  JC 0EA4           ; 63 EX*
0B29: 1EF6  JC 0EA4           ; 64 PD*
; LN finish (from 0767/0769): combine ln(10/m) with the decimal exponent e:
; ln x = (e+1)·ln 10 − ln(10/m), sign in fA[2].
0B2A: 072C  C=C-1 EXP1
0B2B: 0021  SET fA[2]
0B2C: 0CD2  A<>B MAEX
0B2D: 072C  C=C-1 EXP1
0B2E: 1010  JNC 0B36
0B2F: 0C80  A=A+B MAEX
0B30: 1807  JC 0B2D
0B31: 0C48  A=SRA MAEX
0B32: 0C5B  B=SRB MAEX
0B33: 0E00  A=A+1 MMSD1
; LN finish, continued. 0B34 is also where the St flg mis-dispatch of the
; fast-mode chain lands — unchanged on the TI-58C (traced: SST entry, then
; 0B34 … 08CE → 0CBD → 0E4A → HIR STO 11BC writes SCOM[0]).
0B34: 0308  A=A-1 DPT1        ; (fast-mode chain entry, examples/fastmode.ti59 /
                              ;   fastmode-sst.ti59)
0B35: 1811  JC 0B2D
0B36: 0E09  IO=A-1 MMSD1
0B37: 1806  JC 0B3A
0B38: 0C40  A=SLA MAEX
0B39: 0300  A=A+1 DPT1
0B3A: 06D8  A=0 EXP
0B3B: 1E69  JC 0807           ; → ARITH_EXIT
; LRN_OPERAND_SETUP (from 0CE0, after an instruction with an operand was
; recorded): arm argument mode (fB[12]) and operand-only mode (fA[13]) so the
; following keys are recorded as the operand: the instruction's column bits
; select the operand shape (0B3F–0B51); the state is parked in SCOM[14] (the
; upper return-stack levels, unused in LRN). Trace-confirmed: LRN Fix 3 STO 45
; GTO 123 Op 17 If flg 2 B → 58 03 42 45 61 01 23 69 17 87 02 12.
0B3C: 00C9  SET fB[12]        ; argument mode …
0B3D: 00D1  SET fA[13]        ; LRN: an operand is being recorded — no register range check
                              ;   (0D2D)
0B3E: 01D7  A<>E ALL
0B3F: 0A45  TST KR[4]
0B40: 0A77  MOV R5,#7
0B41: 101A  JNC 0B4E
0B42: 0AA5  TST KR[10]
0B43: 0A55  TST KR[5]
0B44: 0A47  MOV R5,#4
0B45: 180A  JC 0B4A
0B46: 0AB5  TST KR[11]
0B47: 180E  JC 0B4E
0B48: 0A07  MOV R5,#0
0B49: 180A  JC 0B4E
0B4A: 0AB5  TST KR[11]
0B4B: 0A87  MOV R5,#8
0B4C: 1004  JNC 0B4E
0B4D: 0A27  MOV R5,#2
0B4E: 02F0  A=R5 DPT
0B4F: 0A85  TST KR[8]
0B50: 1804  JC 0B52
0B51: 0300  A=A+1 DPT1
0B52: 0AE7  MOV R5,#14        ; … state into SCOM[14]
0B53: 00C8  TST fB[12]
0B54: 02F6  D=R5 DPT
0B55: 0131  IO=D ALL
0B56: 0A1F  RCLF
0B57: 0CD0  A=LOAD MAEX
0B58: 0131  IO=D ALL
0B59: 0A0F  STOF
0B5A: 0101  IO=A ALL
0B5B: 1445  JNC 0939
0B5C: 1EBB  JC 07FF
; Δ [REORG] TI-59 0B5D (JC 07B2, the Ind-path hop from 0F34) is gone; that
; path now hops 1282 → 0E8B → 0AFF → 07AE. 07AD jumps straight here.
0B5D: 178C  JNC 0F23
0B5E: 174F  JNC 07B7
0B5F: 0A85  TST KR[8]
0B60: 12F2  JNC 0CD9
0B61: 0A75  TST KR[7]
0B62: 11D9  JNC 0A76
0B63: 0A65  TST KR[6]
0B64: 12F2  JNC 0CDD
0B65: 0A45  TST KR[4]
0B66: 138B  JNC 09A1
0B67: 0083  TOG fA[8]
0B68: 1B8D  JC 09A2
; RAM program register: check it lies inside the program partition
; (SCOM[13] nibbles 8–9 × 10), turn the BCD register number into its binary
; RAM address (0B7D–0B85; program register n = raw RAM register n) and read
; it (0EDA, MEMRD). Beyond the partition → 0F0D (end of program memory).
0B69: 0901  IO=A MANT
0B6A: 09F0  A=R5 MANT
0B6B: 0140  A=SLA ALL
0B6C: 0140  A=SLA ALL
0B6D: 0AD7  MOV R5,#13
0B6E: 02F6  D=R5 DPT
0B6F: 0131  IO=D ALL
0B70: 0A1F  RCLF              ; SCOM[13] …
0B71: 09D6  D=LOAD MANT
0B72: 0976  D=SLD MANT
0B73: 097E  D=SRD MANT
0B74: 097E  D=SRD MANT
0B75: 097E  D=SRD MANT
0B76: 097E  D=SRD MANT
0B77: 097E  D=SRD MANT
0B78: 09BE  D=A-D MANT        ; register − partition registers
0B79: 1F28  JC 0F0D           ; ≥ → outside program memory
0B7A: 0A75  TST KR[7]         ; Ins / Del pass (KR[7], 0E5E)?
0B7B: 1804  JC 0B7D
0B7C: 0903  B=A MANT          ; yes: B := register address (recovered at 1201)
; Δ [HW] TI-59 0B7E–0B8D: no RAM.OP encoding (≥ 100 as n − 20 + marker,
; hex tens nibble A/B). Count the BCD register number down (A=A-1 MLSD1)
; while A[1..0] counts up in binary (A[0], carry into A[1]); the borrow ends
; the loop → 0EDA (MEMRD).
0B7D: 064E  D=SRA EXP
0B7E: 06D8  A=0 EXP           ; binary counter A[2..0] := 0 …
0B7F: 02D8  A=0 DPT
0B80: 0D08  A=A-1 MLSD1       ; register number − 1 (BCD) …
0B81: 16B2  JNC 0EDA          ; borrow → done: read it (0EDA)
0B82: 0300  A=A+1 DPT1        ; … binary + 1 …
0B83: 1807  JC 0B80
0B84: 0700  A=A+1 EXP1        ; … carry into A[1]
0B85: 180B  JC 0B80
0B86: 0940  A=SLA MANT        ; store the step back into SCOM[0] …
0B87: 0A08  MOV R5,KR[4..7]   ; … with the Prg Src Flag in nibble 3
0B88: 09F6  D=R5 MANT
0B89: 09B0  A=A+D MANT
0B8A: 0A0F  STOF
0B8B: 0101  IO=A ALL
0B8C: 0948  A=SRA MANT
0B8D: 00B8  TST fB[11]        ; reload needed?
0B8E: 00BA  CLR fB[11]
0B8F: 1D16  JC 0E1A           ; no → shift the cached register (0E1A)
0B90: 0A75  TST KR[7]         ; keycode-table sub-program (flag 8)?
0B91: 0148  A=SRA ALL         ; A[0] := byte, A[1..3] := register number
0B92: 0148  A=SRA ALL
0B93: 0148  A=SRA ALL
0B94: 1857  JC 0B69           ; RAM → 0B69
; ── PRGREG_FETCH, constant-table branch (Prg Src Flag = 8) ──────────────────
; ROM-resident keycode sub-programs (P/R etc.) live in the SCOM constant
; table (rows 16–63; see the constant-table note in Core/TMC0501.cpp). This
; branch converts the step counter into a constant-table row index: the
; divide-by-8 loop at 0B96–0B98 yields the register number, the KR[8..10]
; tagging below builds the row index (KR[10:8]·8 + KR[6:4]; KR[7] is not an
; index bit — it carries the flag-8 tag), and C=C+CON at 0BA8 (C pre-cleared)
; reads the row's 8 packed keycodes. Row = 16 + register number.
; Trace-confirmed: step 008 → row 17 = 5403435501436504 (same row in the
; TI-59's TMC0582 and the TI-58C's CD2400/CD2401 constant ROMs).
0B95: 05D0  A=LOAD LLSD1
0B96: 06B8  A=A-D EXP
0B97: 0500  A=A+1 LLSD1
0B98: 1805  JC 0B96
0B99: 0A0C  MOV KR,EXT[4..15]
0B9A: 0A18  MOV KR[4..7],R5
0B9B: 0A65  TST KR[6]
0B9C: 1804  JC 0B9E
0B9D: 00A5  SET KR[10]
0B9E: 0A55  TST KR[5]
0B9F: 1804  JC 0BA1
0BA0: 0095  SET KR[9]
0BA1: 0A45  TST KR[4]
0BA2: 1804  JC 0BA4
0BA3: 0085  SET KR[8]
0BA4: 06B0  A=A+D EXP
0BA5: 0A18  MOV KR[4..7],R5
0BA6: 01DE  D=0 ALL
0BA7: 01D5  C<>D ALL
0BA8: 01E4  C=C+CON ALL
0BA9: 01D5  C<>D ALL
0BAA: 1672  JNC 0EE3
; Start a run: fB[0] := running, merge the current step into SCOM[0] (0BAC–
; 0BB6, also the label-key entry from 0916), then continue at 07ED.
0BAB: 0009  SET fB[0]         ; program running
0BAC: 09DE  D=0 MANT          ; start a run from a label key (0916): step into SCOM[0]
0BAD: 0C76  D=SLD MAEX
0BAE: 0C76  D=SLD MAEX
0BAF: 0973  B=SLD MANT
0BB0: 0953  B=SLB MANT
0BB1: 01D2  A<>B ALL
0BB2: 09B0  A=A+D MANT
0BB3: 01D2  A<>B ALL
0BB4: 0131  IO=D ALL
0BB5: 0A0F  STOF
0BB6: 0111  IO=B ALL
0BB7: 0008  TST fB[0]
0BB8: 000A  CLR fB[0]
0BB9: 1799  JNC 07ED
0BBA: 0939  IO=-D MANT
0BBB: 1543  JNC 091A
0BBC: 01DB  B=0 ALL
0BBD: 0AF7  MOV R5,#15
0BBE: 02F6  D=R5 DPT
0BBF: 0131  IO=D ALL
0BC0: 0A0F  STOF
0BC1: 0111  IO=B ALL
; Δ [REORG] TI-59 0BC4: SET fB[0] now follows the return-stack clear
; (0BBC–0BC1) instead of preceding it; same effect.
0BC2: 0009  SET fB[0]
0BC3: 1EE3  JC 0852           ; (also the entry after a return-stack push: 135F → 0F69 → here)
0BC4: 01D7  A<>E ALL
0BC5: 01D8  A=0 ALL
0BC6: 01D7  A<>E ALL
0BC7: 1D5B  JC 091A
0BC8: 1F81  JC 0808
0BC9: 1FDE  JC 0FB8           ; library SBR resolve (085C)
; LABEL_SEARCH start: set up the scan from step 000 of the current program,
; then read register by register (0BDC–0BE3 → 0F74).
0BCA: 02F3  B=R5 DPT
0BCB: 0219  IO=-B DPT
0BCC: 0603  B=A EXP
0BCD: 0A97  MOV R5,#9
0BCE: 01F0  A=R5 ALL
0BCF: 17D4  JNC 0FB9
0BD0: 0AD7  MOV R5,#13        ; partition limit from SCOM[13] (nibbles 8–9) …
0BD1: 02F6  D=R5 DPT
0BD2: 0131  IO=D ALL
0BD3: 0A1F  RCLF
0BD4: 09D6  D=LOAD MANT
0BD5: 017E  D=SRD ALL
0BD6: 017E  D=SRD ALL
0BD7: 017E  D=SRD ALL
0BD8: 017E  D=SRD ALL
0BD9: 09B9  IO=A-D MANT       ; … past the end of program memory?
0BDA: 1D20  JC 0E6A           ; yes → label not found (0E6A → error)
0BDB: 0903  B=A MANT
; Δ [HW] TI-59 0BE4–0BF8: the label search addresses program register n by
; the same BCD → binary count (0BDF–0BE3) and reads it at 0F74 (MEMRD). The
; RAM.OP encoding for registers ≥ 100 and the PRGREG_WRITE (RAM.OP write)
; that followed in the TI-59 are gone; the LRN write-back is 0C16–0C1F.
0BDC: 02D8  A=0 DPT           ; binary counter := 0 …
0BDD: 06D8  A=0 EXP
0BDE: 01DE  D=0 ALL
; Count loop: register number down in BCD, A[1..0] up in binary; the borrow
; → 0F74 (MEMRD, LABEL_SEARCH loop).
0BDF: 03D6  D=LOAD DPT1       ; D := 1
0BE0: 0D08  A=A-1 MLSD1       ; register number − 1 (BCD) …
0BE1: 1726  JNC 0F74          ; borrow → read the register (0F74)
0BE2: 01B0  A=A+D ALL         ; … binary + 1
0BE3: 1807  JC 0BE0           ; next
0BE4: 1657  JNC 08B9          ; after printing (0F02)
0BE5: 1FD0  JC 0FCD           ; print the value (from the trace trigger 08BA): → 13A1 →
                              ;   PRT_VALUE
0BE6: 1FCC  JC 0FCC           ; CMs / CP → CLEAR_MEM
; Unused filler: A=A ALL (no-op) words, never executed.
0BE7: 0100  A=A ALL
0BE8: 0100  A=A ALL
0BE9: 0100  A=A ALL
0BEA: 0100  A=A ALL
0BEB: 0100  A=A ALL
0BEC: 0100  A=A ALL
0BED: 0100  A=A ALL
0BEE: 0100  A=A ALL
0BEF: 0100  A=A ALL
0BF0: 0100  A=A ALL
0BF1: 0239  IO=-D DPT         ; keycode with tens digit 0 (0838): digit
0BF2: 1F71  JC 083A
0BF3: 0095  SET KR[9]
0BF4: 1F5D  JC 0846
0BF5: 0A1F  RCLF              ; continue a sub-program / library run (08A4)
0BF6: 01D6  D=LOAD ALL
0BF7: 017E  D=SRD ALL
0BF8: 00EA  CLR fB[14]
0BF9: 1F8D  JC 0833
; ═══════════════════════════════════════════════════════════════════════════
; OP_40  (0x0BFA–0x0C00) — printer check, TI-58C only.
; Δ [ENH] New: Op 40 (OP_DISPATCH 08E1) sets flag 7 if a printer is
; connected (KP at D10, as at 00A9 / 068A), else leaves flag 7 alone; TI-59:
; Op 40 is an error. Shares the Op 18 / 19 tail 0BFE–0C00 (TI-59 0C56–0C58).
; Trace-checked: printer → SCOM[0] nibble 13 = 2; no printer → unchanged
; (also after St flg 7); INV has no effect (fB[8] cleared).
; ═══════════════════════════════════════════════════════════════════════════
0BFA: 01D7  A<>E ALL
0BFB: 008A  CLR fB[8]         ; no INV: FLAG_OP sets the flag
0BFC: 0AB0  WAIT D11          ; printer present? …
0BFD: 08FB  KEY [P]
0BFE: 0080  TST fA[8]         ; … (Op 18 / 19 from 0E06, no error pending: Op 18?)
0BFF: 1414  JNC 0E09          ; yes → set flag 7 (0E09 → FLAG_OP)
0C00: 1D91  JC 0938           ; → display X (also the exit of CP / CMs 0FE9 and Op 18 / 19 0DF8)
; ═══════════════════════════════════════════════════════════════════════════
; SELFTEST_TABLE  (0x0C01–0x0C0A) — factory self-test, TI-58C only.
; Δ [ENH] New. Test n (1–10) is reached as PREG 0x0C0n from the sequencer
; (0DD7–0DDA → 09E1 → 07B5). Pass → 10BF → 0DC3 (next number); fail → 10BE →
; 0DD6 → 09DD → cold restart. Test 10 sets fA[5] (last). The tests overwrite
; SCOM and all 64 RAM registers (constant memory and E000 lost). Bodies:
; a0600 / a1200 / a1600 (09CC, 08BB, 1360–138F, 16C7, 16C8, 1680).
; ═══════════════════════════════════════════════════════════════════════════
0C01: 1C6B  JC 09CC           ; test 1: constant-ROM entry 7 (09CC)
0C02: 1E8F  JC 08BB           ; test 2: constant-ROM entry 63 (08BB)
0C03: 1B80  JC 0DC3           ; test 3: none
0C04: 1FEC  JC 0FFA           ; test 4: SCOM rows 0–7 (0FFA → 138D → 16C7)
0C05: 1FE0  JC 0FF5           ; test 5: SCOM rows 8–15 (0FF5 → 138F → 16C8)
0C06: 1FEA  JC 0FFB           ; test 6: all RAM registers, checkerboard (0FFB → 138E → 1680)
0C07: 1B78  JC 0DC3           ; test 7: none
0C08: 1FE8  JC 0FFC           ; test 8: SCOM[k] := pattern k, check rows 0–7 (0FFC → 1360)
0C09: 1FD6  JC 0FF4           ; test 9: check rows 8–15 (0FF4 → 1368)
0C0A: 1FE6  JC 0FFD           ; test 10: RAM[k] := k, read back (0FFD → 1375)
; PRGREG_CACHE: SCOM[10] := D (current keycode in nibbles 1..0). In LRN mode
; continue to the LRN display (0E2D → 107E → 13DD).
0C0B: 0AA7  MOV R5,#10
0C0C: 02F0  A=R5 DPT
0C0D: 0101  IO=A ALL
0C0E: 0A0F  STOF
0C0F: 0131  IO=D ALL          ; SCOM[10] := D
0C10: 00A8  TST fB[10]        ; LRN mode?
0C11: 1438  JNC 0E2D          ; yes → LRN display
0C12: 01D2  A<>B ALL
0C13: 1FD1  JC 082B
0C14: 0002  CLR fA[0]         ; condition false: no transfer, continue
0C15: 1F05  JC 0893           ; end of a flag / transfer op: display
; Δ [HW] PRGREG_WRITE (TI-59 0C1B–0C27 + 0BF4–0BF8): LRN write-back of the
; edited program register (LRN_STORE chain, from 0FCB). The binary address
; (from 0B17, in B) goes out with MEMWR, then the data; no RAM.OP word and no
; ≥ 100 encoding.
0C16: 0C48  A=SRA MAEX
0C17: 09D8  A=0 MANT
0C18: 0C48  A=SRA MAEX
0C19: 01D2  A<>B ALL
0C1A: 01B0  A=A+D ALL         ; new keycode
0C1B: 0111  IO=B ALL          ; RAM address …
0C1C: 0A76  MEMWR             ; … write …
0C1D: 0101  IO=A ALL          ; … the register
0C1E: 01D2  A<>B ALL
0C1F: 1EF1  JC 08A7           ; → PRGREG_FETCH (step + 1; also List 0D14)
0C20: 165C  JNC 0F4E
0C21: 00A8  TST fB[10]
0C22: 1FB3  JC 0849
0C23: 00C9  SET fB[12]
0C24: 0A0D  SWAP KR,SR
0C25: 1A7A  JC 0D62
0C26: 01D2  A<>B ALL
0C27: 017E  D=SRD ALL         ; D[1..0] := operand keycode
0C28: 0309  IO=A-1 DPT1       ; digits still expected …
0C29: 1836  JC 0C44
0C2A: 0070  TST fA[7]         ; Ind?
0C2B: 1032  JNC 0C44
0C2C: 0000  TST fA[0]         ; label operand?
0C2D: 1012  JNC 0C36
0C2E: 0A0D  SWAP KR,SR        ; inspect the suspended slot (SR) …
0C2F: 0A65  TST KR[6]
0C30: 1808  JC 0C34
0C31: 0A75  TST KR[7]
0C32: 16D4  JNC 0F9C
0C33: 0A85  TST KR[8]
0C34: 0A0D  SWAP KR,SR
0C35: 181E  JC 0C44
0C36: 01D5  C<>D ALL
0C37: 0A47  MOV R5,#4
0C38: 06F3  B=R5 EXP
0C39: 0621  IO=C EXP
0C3A: 0CF4  C=R5 MAEX
0C3B: 069B  B=C-B EXP
0C3C: 0619  IO=-B EXP
0C3D: 01D5  C<>D ALL
0C3E: 0239  IO=-D DPT
0C3F: 1A2E  JC 0D56
0C40: 0000  TST fA[0]
0C41: 1806  JC 0C44
0C42: 0639  IO=-D EXP
0C43: 1226  JNC 0D56
0C44: 0A1F  RCLF              ; SCOM[0] nibble 1 := units digit (pending key) …
0C45: 01D3  B=LOAD ALL
0C46: 0231  IO=D DPT
0C47: 06F3  B=R5 EXP
0C48: 0A0F  STOF
0C49: 0111  IO=B ALL
0C4A: 017E  D=SRD ALL         ; D := tens digit
0C4B: 06DE  D=0 EXP
0C4C: 00E9  SET fB[14]        ; pending key
; Δ [REORG] TI-59 0C55–0C58: the tens digit goes out through the moved
; PROG_OPERAND tail (0D56); the Op 18 test moved to 0BFE.
0C4D: 1A12  JC 0D56           ; → dispatch the tens digit (0D56 → 0BF9 → 0833)
0C4E: 0A45  TST KR[4]
0C4F: 1D5D  JC 09A1
0C50: 0001  SET fA[0]
0C51: 1D0F  JC 09CA
; ═══════════════════════════════════════════════════════════════════════════
; TAN_KERNEL  (0x0C52–0x0C67, 0x0C96–0x0CA3, 0x0F24–0x0F4D) — decimal CORDIC.
; Δ [REORG] Moved from TI-59 08C6–08DB and 09DF–09EA (the old sites hold
; self-test code); the x-step and the arc accumulation (TI-59 0C5D–0C63,
; 0C97–0CB6) went to 0F24–0F4D. Same results: 864 cases of sin, cos, tan,
; their inverses, P→R, √, ln, eˣ, log, 10ˣ, yˣ, D.MS in Deg / Rad / Grad give
; the same C register and error flag on both machines.
; Constants 8–12 = atan(10^−k), k = 0…4 (KR[8] + index k). Registers: C =
; remaining angle θ (C[0] reused as the shift count), A = y, B = x, starting
; at (0, 1). For each k, while θ ≥ atan(10^−k): θ −= atan(10^−k) and the
; vector is rotated by that angle, unnormalized:
;     x' = x − y·10^−k   (0F24–0F2A)       y' = y + x·10^−k   (0C98–0C9D)
; After k = 4 the small remainder is applied as y += θ·x (0CE9–0CFE) and
; tan θ = y / x (0ADF–0AF9). The rotation gain cancels in the ratio.
; With INV (fA[8], arc functions) the same loop runs backwards from (x, y)
; = (1, t), rotating y towards 0 and accumulating the angle (0C96, 0F2E–0F4D).
; ═══════════════════════════════════════════════════════════════════════════
0C52: 095B  B=SRB MANT
0C53: 0708  A=A-1 EXP1        ; align θ to a fixed-point mantissa (shift by its exponent)
0C54: 1805  JC 0C52
0C55: 06D8  A=0 EXP
0C56: 0A07  MOV R5,#0         ; k := 0 (constant 8 = atan 1 = π/4)
0C57: 0A18  MOV KR[4..7],R5
0C58: 0C06  D=A MAEX          ; D := y (for the y' step)
0C59: 0A08  MOV R5,KR[4..7]   ; C[0] := k (shift count)
0C5A: 02F4  C=R5 DPT
0C5B: 0080  TST fA[8]         ; arc mode?
0C5C: 1592  JNC 0F25          ; yes → x-step (0F24)
0C5D: 0CEC  C=C-CON MAEX      ; θ − atan(10^−k) …
0C5E: 1D8E  JC 0F25           ; … fits → rotate (x-step 0F24)
0C5F: 0CE4  C=C+CON MAEX      ; … doesn't: restore θ …
0C60: 187A  JC 0C9D
0C61: 0A65  TST KR[6]         ; … k = 4 done?
0C62: 0A04  INC KR            ; next k
0C63: 15CC  JNC 0F49          ; yes → remainder step (0F49 → 0CE9)
0C64: 0080  TST fA[8]
0C65: 181B  JC 0C58
0C66: 0C33  B=D MAEX
0C67: 185E  JC 0C96           ; arc mode → accumulation (0C96)
; If flg test (slot 00B8 → 04AF → 0894): read the flag bit (layout as at
; FLAG_OP) into KR, fA[9] := flag set; INV (fB[8] → fA[8]) inverts later.
0C68: 01D7  A<>E ALL
0C69: 0086  MOV fA[8],fB[8]
0C6A: 0148  A=SRA ALL
0C6B: 09D8  A=0 MANT
0C6C: 0140  A=SLA ALL
0C6D: 0B09  IO=A-5 MLSD5      ; flag ≥ 5 → bit 1 …
0C6E: 1806  JC 0C71
0C6F: 03D0  A=LOAD DPT1
0C70: 0B00  A=A+5 MLSD5
0C71: 0D00  A=A+1 MLSD1
0C72: 0D00  A=A+1 MLSD1
0C73: 0A1F  RCLF              ; SCOM[0] flags …
0C74: 09D6  D=LOAD MANT
0C75: 097E  D=SRD MANT        ; … slid to the flag's nibble
0C76: 0D08  A=A-1 MLSD1
0C77: 1805  JC 0C75
0C78: 0931  IO=D MANT
0C79: 0A18  MOV KR[4..7],R5
0C7A: 0309  IO=A-1 DPT1       ; flag number > 9?
0C7B: 1ADD  JC 0B0D           ; → error
0C7C: 0A55  TST KR[5]         ; bit set?
0C7D: 1004  JNC 0C7F
0C7E: 0091  SET fA[9]         ; condition true
0C7F: 01D7  A<>E ALL
0C80: 1D3B  JC 09E3
0C81: 1672  JNC 0FBA
0C82: 0090  TST fA[9]
0C83: 1808  JC 0C87
0C84: 00C0  TST fA[12]
0C85: 188E  JC 0CCC
0C86: 01DE  D=0 ALL
0C87: 00C0  TST fA[12]
0C88: 1A9B  JC 0B3B
0C89: 01D8  A=0 ALL
0C8A: 1A9F  JC 0B3B
0C8B: 0C48  A=SRA MAEX
0C8C: 072C  C=C-1 EXP1
0C8D: 1805  JC 0C8B
0C8E: 0080  TST fA[8]
0C8F: 1E86  JC 0FD2
0C90: 01DC  C=0 ALL
0C91: 0030  TST fA[3]
0C92: 0ED3  B=LOAD MMSD1
0C93: 1881  JC 0C53
0C94: 0E09  IO=A-1 MMSD1
0C95: 187F  JC 0C56
; Arc mode (fA[8], from 0C67): swap and rotate again (0C58); the count of the
; atan(10^−k) steps (the angle, built in C) is kept at 0F2E–0F4D. Then the
; y-step (0C98–0C9E, TI-59 09DF–09E5) and the arc rescale step (0C9F–0CA3,
; TI-59 09E6–09EA).
0C96: 0CD2  A<>B MAEX
0C97: 187F  JC 0C58
0C98: 0C48  A=SRA MAEX        ; y-step: x · 10^−k …
0C99: 032C  C=C-1 DPT1
0C9A: 1805  JC 0C98
0C9B: 0080  TST fA[8]
0C9C: 107B  JNC 0C5F
0C9D: 0CB0  A=A+D MAEX        ; … y' = y + x·10^−k
0C9E: 188D  JC 0C58           ; next rotation
0C9F: 0C48  A=SRA MAEX
0CA0: 0C7E  D=SRD MAEX
0CA1: 0E00  A=A+1 MMSD1
0CA2: 0C5B  B=SRB MAEX
0CA3: 1897  JC 0C58           ; next rotation
; Δ [REORG] OP_DISPATCH tail, moved here from TI-59 08EB–08EF (Op 00–39,
; from 08DE): 20–39 → register increment / decrement, 00–19 → OP_TABLE.
0CA4: 0D08  A=A-1 MLSD1       ; nn − 20 …
0CA5: 0D09  IO=A-1 MLSD1
0CA6: 0501  IO=A+1 LLSD1
0CA7: 180C  JC 0CAD           ; … 20–39 → register increment / decrement (0CAD); 00–19 fall
                              ;   through
0CA8: 0A0D  SWAP KR,SR
0CA9: 0A0C  MOV KR,EXT[4..15]
0CAA: 0A18  MOV KR[4..7],R5
0CAB: 01D7  A<>E ALL
0CAC: 1DBC  JC 0F8A           ; build KR = 0xA000 | tens<<8 | units<<4 and jump
0CAD: 0D08  A=A-1 MLSD1       ; Op 2x/3x: register number x …
0CAE: 0D09  IO=A-1 MLSD1
0CAF: 0231  IO=D DPT
0CB0: 09F0  A=R5 MANT
0CB1: 01D7  A<>E ALL
0CB2: 1AEF  JC 0B3B           ; Op 2x: + 1
0CB3: 00B1  SET fA[11]        ; Op 3x: − 1
0CB4: 1AF3  JC 0B3B
0CB5: 0A75  TST KR[7]         ; LRN operand / key routing by row bits (sweep-checked: B′ here,
                              ;   CMs 0CB9, A′ 0CBE, Pgm 0CC0) — all reach 09A1 (store the
                              ;   keycode)
0CB6: 1668  JNC 0FEA
0CB7: 0A65  TST KR[6]
0CB8: 1AA7  JC 0B65
0CB9: 0A55  TST KR[5]
0CBA: 1781  JNC 08FA
0CBB: 1E35  JC 09A1
0CBC: 1F04  JC 103E           ; slot hop (08CD): → 103E → HIR dispatch 12E2 (TI-59 0CCB → 0E8A →
                              ;   11BC)
0CBD: 1B1A  JC 0E4A           ; slot hop (08CE) → 0E4A (HIR STO; second hop of the fast-mode
                              ;   chain)
0CBE: 0A55  TST KR[5]
0CBF: 1E3D  JC 09A1
0CC0: 0A45  TST KR[4]
0CC1: 103C  JNC 0CDF
0CC2: 1C91  JC 0A7A
; Δ [REORG] Moved from TI-59 0947–0951 (atan front end and the undefined-Op
; error) and 0CE1–0CE7 (keycode sub-program refused / Op 41–99), next to the
; new OP_DISPATCH; the error 0CCB is also REG_ADDR's (0D31).
0CC3: 0030  TST fA[3]         ; atan (INV tan, from 08D0)
0CC4: 1525  JNC 0A32
0CC5: 0709  IO=A-1 EXP1
0CC6: 180A  JC 0CCB
0CC7: 0E08  A=A-1 MMSD1
0CC8: 0D09  IO=A-1 MLSD1
0CC9: 0E00  A=A+1 MMSD1
0CCA: 152F  JNC 0A33
0CCB: 0099  SET fB[9]         ; ERROR: undefined Op, register out of range, AOS too deep for a
                              ;   keycode program
0CCC: 0051  SET fA[5]
0CCD: 1B9F  JC 0AFE           ; → 0806 → ARITH_EXIT
0CCE: 0A1F  RCLF              ; keycode launch refused (from 0A49) …
0CCF: 09D0  A=LOAD MANT
0CD0: 0509  IO=A-1 LLSD1
0CD1: 01D7  A<>E ALL          ; Op 41–49, 50–99 (08DA / 08E0): no such Op → error (0CCB)
0CD2: 180F  JC 0CCB
0CD3: 000A  CLR fB[0]
0CD4: 1813  JC 0CCB
; LRN key classification (from 0998/0B60): column/row bits pick the keys that
; act immediately (09B3 2nd-row editing keys, 09A1, 0E2E) or that are followed
; by an operand (0CE0 → LRN_OPERAND_SETUP 0B3D); digits go to 0A89 → 06A9.
0CD5: 0A95  TST KR[9]
0CD6: 1647  JNC 09B3
0CD7: 0A85  TST KR[8]
0CD8: 166F  JNC 09A1
0CD9: 0A75  TST KR[7]
0CDA: 12A8  JNC 0E2E
0CDB: 0A65  TST KR[6]
0CDC: 1E77  JC 09A1
0CDD: 0A55  TST KR[5]
0CDE: 0A45  TST KR[4]
0CDF: 0082  CLR fA[8]
0CE0: 1B47  JC 0B3D           ; instruction with an operand → operand setup
0CE1: 0A55  TST KR[5]
0CE2: 14B3  JNC 0A89          ; digit → DIGIT_SLIDE (then 05F7: stored as a step)
0CE3: 1E85  JC 09A1
; Δ [REORG] TI-59 0CE1–0CE7 moved to 0CCE–0CD4, 0CE8–0CF1 (LRN key routing)
; to 0FEA–0FF3 (via 0CB6).
0CE4: 0A45  TST KR[4]
0CE5: 1689  JNC 09A1
0CE6: 180F  JC 0CDF
0CE7: 04D3  B=LOAD DPTC
0CE8: 1986  JC 0DAB
; Δ [HW] TI-59 0CF7–0CFE (RAM_WRITE with the ≥ 100 bias) is gone; RAM_WRITE
; is 0DFE.
; Remainder step: y += θ·x for the angle left after k = 4 (tan r ≈ r), then
; divide y / x (0AE1).
0CE9: 04D4  C=LOAD DPTC
0CEA: 0CD8  A=0 MAEX
0CEB: 032C  C=C-1 DPT1
0CEC: 052C  C=C-1 LLSD1
0CED: 1008  JNC 0CF1
0CEE: 0C80  A=A+B MAEX
0CEF: 0E24  C=C+1 MMSD1
0CF0: 1809  JC 0CEC
0CF1: 0C6C  C=SRC MAEX
0CF2: 0C48  A=SRA MAEX
0CF3: 032C  C=C-1 DPT1
0CF4: 1811  JC 0CEC
0CF5: 00C0  TST fA[12]
0CF6: 1804  JC 0CF8
0CF7: 0F36  D=D MAEX1
0CF8: 0CB0  A=A+D MAEX
0CF9: 0F0A  A<>B=A-1 MAEX1
0CFA: 1447  JNC 0AD7
0CFB: 00E1  SET fA[14]
0CFC: 0031  SET fA[3]
0CFD: 0CD5  C<>D MAEX
0CFE: 1C3B  JC 0AE1           ; → y ÷ x
0CFF: 00C8  TST fB[12]
0D00: 00CA  CLR fB[12]
0D01: 16E7  JNC 098E
0D02: 01D7  A<>E ALL
0D03: 01DE  D=0 ALL
0D04: 18A8  JC 0D58
0D05: 0A95  TST KR[9]
0D06: 1CF9  JC 0A8A
0D07: 0A65  TST KR[6]
0D08: 1CFD  JC 0A8A
0D09: 0A85  TST KR[8]
0D0A: 0A55  TST KR[5]
0D0B: 1D23  JC 0A7A
0D0C: 1505  JNC 0A8A
; Δ [REORG] TI-59 0D23–0D27: long-jump hops for the slot table at
; 091C–0936; the targets moved (INV List start 12FE, PGM_SELECT 173B, print
; engine 165A).
0D0D: 1E64  JC 103F           ; INV List start (0926) → 103F → 12FE
0D0E: 1D36  JC 0FA9           ; INV List, next register (091C) → 0FA9
0D0F: 1EA0  JC 105F           ; Pgm (091D) → 105F → 1416 → PGM_SELECT 173B
; (0D10–0D11: hops, continued — see 0D0D.)
0D10: 1603  JNC 0A0F          ; (hop from 105E → 0A0F)
0D11: 1DDC  JC 0FFF           ; print-op sequence tail (0936) → 0FFF → 1332 → print engine 165A
; Δ [HW] TI-59 0D28–0D2F (no listing of a program protected by a card,
; SCOM[9] nibble 2) dropped: no card reader.
; LIST loop (entry from slot 0921): for each step from the current one —
; fetch it (0D14 → 0C1F → 08A7 → LRN display 13DD), poll R/S (1417: held →
; stop, 11F0), wait for the printer and clear its buffer (141D–1420), let the
; scanner (1427 → 1283 → 0F79) classify the keycode (operand bytes print as
; plain numbers), print the mnemonic through the table at 0x1000 (142A–145A:
; computed jump to 0x1000 + 32·tens + 3·units), the keycode and step-number
; digits (12D1–12E1), PRT.GO (1314), next (10FF → 0D14). Ends at the
; partition boundary. Trace-confirmed on both (List of LBL A STO 12 …:
; "000  76 LBL", "001  11  A", "002  42 STO", "003  12  12").
0D12: 00A9  SET fB[10]
0D13: 0041  SET fA[4]         ; printing mode for the step fetch
0D14: 19EB  JC 0C1F           ; → 0C1F → PRGREG_FETCH (next step)
; ═══════════════════════════════════════════════════════════════════════════
; REG_ADDR  (0x0D15–0x0D2C) — data register number → RAM register, with the
; partition check. Trace-confirmed (STO/RCL 05, STO Ind 01).
; SCOM[13] nibbles 3–5 hold the index of the top RAM register, 059 (restored
; from E000 at power-on, 0381–03A6): Rnn lives at RAM[59 − nn] (R05 → RAM 54
; = 0x36, traced). The result must lie above the program partition (SCOM[13]
; nibbles 8–9 × 10 registers; default 30: 240 steps, R00–R29), else error
; (0D2F–0D31 → 0CCB; LRN operand / INV List → 0FAE). The BCD index is then
; made binary by RAM_ADDR (0D96).
; ═══════════════════════════════════════════════════════════════════════════
0D15: 01D7  A<>E ALL          ; A := register number (E), E := X
0D16: 0906  D=A MANT
0D17: 0AD7  MOV R5,#13        ; SCOM[13] …
0D18: 02F6  D=R5 DPT
0D19: 0131  IO=D ALL
0D1A: 0A1F  RCLF
0D1B: 09D0  A=LOAD MANT
0D1C: 0148  A=SRA ALL         ; … isolate nibbles 3–5 = top RAM register …
0D1D: 0148  A=SRA ALL
0D1E: 0148  A=SRA ALL
0D1F: 09D8  A=0 MANT
0D20: 0140  A=SLA ALL
0D21: 0140  A=SLA ALL
0D22: 0140  A=SLA ALL
0D23: 09B8  A=A-D MANT        ; … RAM index = top − nn
0D24: 0131  IO=D ALL
0D25: 0A1F  RCLF
0D26: 09D6  D=LOAD MANT       ; SCOM[13] again …
0D27: 097E  D=SRD MANT        ; … nibbles 8–9 = partition / 10 …
0D28: 097E  D=SRD MANT
0D29: 097E  D=SRD MANT
0D2A: 097E  D=SRD MANT
0D2B: 09B9  IO=A-D MANT       ; RAM index ≥ first data register?
0D2C: 18D4  JC 0D96           ; yes → RAM_ADDR (binary address)
0D2D: 00D0  TST fA[13]        ; out of range: fine while recording an operand in LRN (fA[13]),
                              ;   else error
0D2E: 1500  JNC 0FAE
0D2F: 0092  CLR fA[9]
; Δ [FIX] New CLR fA[10] before the out-of-range error. An Ind whose pointer
; register lies outside the data partition left fA[10] (trace record pending)
; set, and the TI-59 then printed no TRACE error line: "5 STO Ind 65" (any op
; with Ind, also Pgm / SBR / GTO / Fix / Op Ind) prints "5.  ?" here and
; nothing on the TI-59. Verified on both; a TI-58C with 0D30 patched out
; behaves like the TI-59.
0D30: 00A2  CLR fA[10]
0D31: 18CD  JC 0CCB           ; → ERROR (0CCB)
0D32: 1A73  JC 0BF9           ; hop (from 10DF) → 0BF9 → STEP_DISPATCH 0833
0D33: 1D96  JC 0FFE           ; → return-stack push (0FFE → RET_PUSH 1334)
; ═══════════════════════════════════════════════════════════════════════════
; PROG_OPERAND  (0x0D34–0x0D3D, 0x0C26–0x0C4D, 0D56) — an operand step read
; while a running program's operation waits for its argument (fB[12], from
; STEP_DISPATCH 082F → 09FF). Trace-confirmed on the TI-59 (program 7 STO 12
; R/S → R12 = 7): the step's two digits are fed to the argument collector as
; two digit keys — the tens digit is dispatched at once (0D56 → 0BF9 →
; 0833), the units digit is parked as a pending key in SCOM[0] (nibble 1, as
; at ARG_TERMINATE) with fB[14], and is dispatched on the next pass (0620 →
; 04F2). Operands that are not digits (label names, fA[0]) and Ind (fA[7])
; branch off at 0C29–0C2D; 0C2F–0F9C check the pending sequence's slot to
; tell one-digit operands.
; Δ [REORG] Moved verbatim from TI-59 096C–098F (with PGM_IN_PROGRAM, 0D3E).
; The TI-59's return-stack push at this address (0D50–0D7A) moved to
; 1334–135F (via 0D33); it still skips a 7th level silently (re-verified: a
; 7-deep SBR chain gives R01 = 15 on both machines, 21 if all returned).
; ═══════════════════════════════════════════════════════════════════════════
0D34: 01D7  A<>E ALL          ; A := collector state
0D35: 0176  D=SLD ALL
0D36: 0AD7  MOV R5,#13
0D37: 02F6  D=R5 DPT
0D38: 0131  IO=D ALL
0D39: 0A1F  RCLF              ; SCOM[13] …
0D3A: 01D3  B=LOAD ALL
0D3B: 01D2  A<>B ALL
0D3C: 0E08  A=A-1 MMSD1       ; … nibble 15: Pgm mark?
0D3D: 122F  JNC 0C26          ; no → operand digits (0C26)
; PGM_IN_PROGRAM (0x0D3E–0x0D55): "Pgm nn" executed inside a running program
; only marks SCOM[13] nibble 15 (13CC). The next operation step sees the mark
; here, clears it and checks its keycode: a user label key (tens 1, 0D44–
; 0D48) or SBR 71 / R/S 91 (0D4A–0D55) take the library path (0C81 → 0FBA);
; anything else runs as if Pgm had not been there. Trace-checked on the
; TI-59 (RAM program "3 Pgm 02 …"): "SBR C" and plain "C" run ML-02's C;
; "x²" gives 9 and "5 + 1 =" gives 6, the Pgm selection simply dropped.
0D3E: 0131  IO=D ALL          ; SCOM[13] nibble 15 := 0
0D3F: 0A0F  STOF
0D40: 0101  IO=A ALL
0D41: 09DE  D=0 MANT
0D42: 017E  D=SRD ALL
0D43: 00CA  CLR fB[12]
0D44: 07D0  A=LOAD EXP1       ; keycode tens 1 (label key)?
0D45: 06B8  A=A-D EXP
0D46: 1002  JNC 0D47 ; clear COND
0D47: 0709  IO=A-1 EXP1
0D48: 118F  JNC 0C81          ; yes → library label call
0D49: 0DD0  A=LOAD MLSD1
0D4A: 0A77  MOV R5,#7         ; 71 (SBR), then 91 (R/S) …
0D4B: 06F0  A=R5 EXP
0D4C: 03D0  A=LOAD DPT1
0D4D: 06B8  A=A-D EXP
0D4E: 02B8  A=A-D DPT
0D4F: 1008  JNC 0D53
0D50: 0709  IO=A-1 EXP1
0D51: 0309  IO=A-1 DPT1
0D52: 11A3  JNC 0C81          ; match → library path
0D53: 0D08  A=A-1 MLSD1
0D54: 0A97  MOV R5,#9
0D55: 1815  JC 0D4B
0D56: 01D7  A<>E ALL          ; → dispatch the step's digit / keycode
0D57: 1ABD  JC 0BF9           ; dispatch the tens digit as a key (0BF9 → 0833)
0D58: 0606  D=A EXP
0D59: 01D8  A=0 ALL
0D5A: 017E  D=SRD ALL
0D5B: 01D7  A<>E ALL
; LRN_STORE  (0x0D5C → 0FA2 → 0F06 → 0D96 → 0A1A → 0B17 → 0D9E → 1155 → 1467
; → 15F8 → 1331 → 0FCB → 0C16): read the program register holding the
; current step (MEMRD 0D9F), replace the keycode at the step's byte
; position, write the register back (MEMWR 0C1C), then advance the step
; (PRGREG_FETCH 08A7) and redisplay. With Ind (fA[7]) → 0FA2 too. Trace-
; checked (LRN 5).
0D5C: 0070  TST fA[7]
0D5D: 1C8A  JC 0FA2
; LRN_IND_MERGE (0x0D5E–0x0D82, 0FA0) — Ind in LRN mode, applied when the Ind
; operand's second digit is stored. If the op recorded before Ind has a
; compact Ind form (fA[13] set), that step is rewritten: STO/RCL/SUM →
; 72/73/74, Exc/Prd → 63/64, Pgm → 62, GTO → 83, Op → 84 (tens digit at
; 0D6E / 0D75, units for GTO / Op from 113E / 1140), and the step counter
; goes back one (0D76–0D80) so the merged code overwrites it. Any other op
; records Ind as its own step, keycode 40 (0FA0). Trace-checked on the TI-59
; (headless, LRN): "STO Ind 05" → 72 05, "INV SUM Ind 07" → 22 74 07, "Exc
; Ind 05" → 63 05, "Fix Ind 02" → 58 40 02, "SBR Ind 22" → 71 40 22.
0D5E: 0176  D=SLD ALL
0D5F: 01D7  A<>E ALL
0D60: 0630  A=D EXP
0D61: 01D7  A<>E ALL
0D62: 00D0  TST fA[13]        ; previous step mergeable?
0D63: 1C7A  JC 0FA0           ; no → record Ind as keycode 40
0D64: 0AE7  MOV R5,#14        ; which op it was …
0D65: 02F6  D=R5 DPT
0D66: 0131  IO=D ALL
0D67: 0A1F  RCLF
0D68: 02D6  D=LOAD DPT
0D69: 09F0  A=R5 MANT
0D6A: 0D0E  D=A-1 MLSD1
0D6B: 0939  IO=-D MANT
0D6C: 1D64  JC 101E
0D6D: 0A77  MOV R5,#7
0D6E: 0CF6  D=R5 MAEX         ; new tens digit 7 (STO, RCL, SUM)
0D6F: 0B09  IO=A-5 MLSD5
0D70: 100C  JNC 0D76
0D71: 02F6  D=R5 DPT
0D72: 0239  IO=-D DPT
0D73: 1F96  JC 113E
0D74: 0A67  MOV R5,#6
0D75: 0CF6  D=R5 MAEX         ; or 6 (Exc, Prd, Pgm), 8 (GTO, Op via 1141)
0D76: 0A1F  RCLF              ; step counter − 1 …
0D77: 01D0  A=LOAD ALL
0D78: 0948  A=SRA MANT
0D79: 0508  A=A-1 LLSD1       ; … byte − 1 …
0D7A: 1808  JC 0D7E
0D7B: 0AC7  MOV R5,#12
0D7C: 09F3  B=R5 MANT
0D7D: 0988  A=A-B MANT        ; … byte 0: back into the previous register
0D7E: 0940  A=SLA MANT
0D7F: 0A0F  STOF
0D80: 0101  IO=A ALL          ; SCOM[0] written
0D81: 00D2  CLR fA[13]        ; merged
0D82: 1C40  JC 0FA2           ; → store the merged keycode
; ── Launch prologue, library-caller path (from 0A59) ────────────────────────
; Reached when the caller's Prg Src digit is non-zero: the (believed-)
; running program lives in the module, so the caller's return address is
; the CROM chip's internal PC. The 0D8A–0D90 loop reads it digit-by-digit
; (LIB.PC.IN ×4, LSD first, non-destructive) and 0D91–0D94 assemble it into
; the launch descriptor, then rejoin the common return-stack push at 0A6A.
; fB[0]/fB[13] are NOT set on this path, so at 0872 the transfer target
; gets the RAM-partition range check even when it is a keycode
; sub-program — the quirk-2 flag leak of examples/texas-print.ti59
; (trace pr-after-halt2: P/R after the R/S-resumed garbage run lands here
; because SCOM[0] still says source 1; its entry step 284 then fails the
; check at 087C).
0D83: 00D8  TST fB[13]
0D84: 1808  JC 0D88
0D85: 0A27  MOV R5,#2
0D86: 06F0  A=R5 EXP
0D87: 0640  A=SLA EXP
0D88: 0A37  MOV R5,#3
0D89: 09F0  A=R5 MANT
0D8A: 017E  D=SRD ALL
0D8B: 0A2E  LIB.PC.IN
0D8C: 0A0C  MOV KR,EXT[4..15]
0D8D: 0A08  MOV R5,KR[4..7]
0D8E: 09F6  D=R5 MANT
0D8F: 0D08  A=A-1 MLSD1
0D90: 180D  JC 0D8A
0D91: 0176  D=SLD ALL
0D92: 0176  D=SLD ALL
0D93: 0176  D=SLD ALL
0D94: 0930  A=D MANT
0D95: 1E57  JC 0A6A
; ═══════════════════════════════════════════════════════════════════════════
; RAM_ADDR / RAM_READ  (0x0D96–0x0DA9) — data and program registers.
; Δ [HW] TI-59 0DBA–0DC6 and 0DDC–0DE3 (RAM.OP read, hex tens nibble for
; registers ≥ 100, separate Ind pointer read). The CMOS RAM takes a binary
; register address with MEMRD / MEMWR. 0D96–0D9D converts the BCD RAM index
; (from REG_ADDR 0D2C; program registers from 0F06) by counting it down in
; BCD while A[1..0] counts up in binary, then 0A1A dispatches; a read comes
; back to 0D9E. The loop runs (index) times, 4 instructions each, so access
; time grows with 59 − nn: RCL 00 takes 691 active instructions, RCL 29 594
; (TI-59: 466 / 479).
; ═══════════════════════════════════════════════════════════════════════════
0D96: 06D8  A=0 EXP           ; binary counter A[2..0] := 0 …
0D97: 02D8  A=0 DPT
0D98: 01DE  D=0 ALL
0D99: 03D6  D=LOAD DPT1       ; D := 1
0D9A: 0D08  A=A-1 MLSD1       ; RAM index − 1 (BCD) …
0D9B: 1703  JNC 0A1A          ; borrow → done: A[1..0] = address (0A1A)
0D9C: 01B0  A=A+D ALL         ; … binary + 1
0D9D: 1807  JC 0D9A
0D9E: 0101  IO=A ALL          ; RAM_READ: address …
0D9F: 0A86  MEMRD             ; … read
0DA0: 01D0  A=LOAD ALL        ; A := RAM register
0DA1: 00A8  TST fB[10]
0DA2: 1766  JNC 1155          ; LRN: program register → replace the byte (1155)
0DA3: 0070  TST fA[7]         ; Ind?
0DA4: 1372  JNC 0F5D          ; yes → the value is the register number (0F5D → 1278 → 1282 →
                              ;   0E8B → 0AFF → 07AE)
0DA5: 00D2  CLR fA[13]
0DA6: 0201  IO=A DPT          ; its nibble 0 (signs) …
0DA7: 0007  MOV fA[1..4],R5   ; … into fA[1..4]
0DA8: 005A  CLR fB[5]
0DA9: 1D57  JC 0AFE           ; → 0806 → ARITH_EXIT
; Op 12 / Op 15 (0A12, 0A15 → 0A0A): least-squares keycode program at entry
; 000 with the variant (0 = slope/intercept, 1 = x′) in B[0], parked in
; SCOM[14] (return levels 4–6) for the program to test.
0DAA: 02DB  B=0 DPT           ; Op 12: variant 0
0DAB: 0AE7  MOV R5,#14        ; SCOM[14] := variant …
0DAC: 02F6  D=R5 DPT
0DAD: 0131  IO=D ALL
0DAE: 0A1F  RCLF
0DAF: 0CD3  B=LOAD MAEX
0DB0: 0131  IO=D ALL
0DB1: 0A0F  STOF
0DB2: 0111  IO=B ALL
0DB3: 01D7  A<>E ALL
0DB4: 01DB  B=0 ALL
0DB5: 1EED  JC 0A3F
; Δ [REORG] Op 09 hop (TI-59 0DE4).
0DB6: 1FEA  JC 11AB           ; Op 09 → 11AB → OP09_DOWNLOAD
; ═══════════════════════════════════════════════════════════════════════════
; SELF_TEST  (0x0DB7–0x0DDA) — factory diagnostic sequencer, TI-58C only.
; Δ [ENH] New (TI-59 0DDC–0DE3 here was the Ind-pointer address encoding).
; Entered from 09FE when the hidden key on K-line N at row 8 or 9 (0661–0666
; → 09FD; also KN at digit 15, idle loop 064B) is seen. E[3] = test number
; (from 1), SR = 0xC000 + 16·n (next table slot, 0C01–0C0A). Each pass
; prints the number on the printer and runs the next test; tests return to
; 0DC3 (pass, via 10BF) or 0DD6 (fail, via 10BE). After test 10 (fA[5]) or a
; failure → 09DD: wait for the printer, then PREG 0x0000 = cold restart.
; Trace-checked (harness m.press("80"), printer): prints 1, 2, … 11.
; ═══════════════════════════════════════════════════════════════════════════
0DB7: 0DD0  A=LOAD MLSD1      ; test number 1 (A[3]) …
0DB8: 0A97  MOV R5,#9
0DB9: 02F3  B=R5 DPT
0DBA: 0111  IO=B ALL
0DBB: 0A1F  RCLF              ; … with SCOM[9] nibbles 1–2 (RAM size) in A[2..1] …
0DBC: 06D0  A=LOAD EXP
0DBD: 01D7  A<>E ALL          ; … into E
0DBE: 0A0C  MOV KR,EXT[4..15] ; SR := 0xC000 (table base 0x0C00) …
0DBF: 00F5  SET KR[15]
0DC0: 00E5  SET KR[14]
0DC1: 0A0D  SWAP KR,SR
0DC2: 0052  CLR fA[5]         ; fA[5] = "last test done" (set by test 10)
0DC3: 0A98  PRT.STEP          ; next test (pass, 10BF): wait for the printer …
0DC4: 0A0B  TST.BUSY
0DC5: 1005  JNC 0DC3
0DC6: 0A88  PRT.CLR           ; … clear its line buffer
0DC7: 01D7  A<>E ALL
0DC8: 0104  C=A ALL
0DC9: 0A0C  MOV KR,EXT[4..15]
0DCA: 0A78  PRT.FUNC
0DCB: 0A98  PRT.STEP
0DCC: 0948  A=SRA MANT        ; test-number digits → printer characters …
0DCD: 0A18  MOV KR[4..7],R5
0DCE: 0A04  INC KR
0DCF: 0D09  IO=A-1 MLSD1
0DD0: 0A68  PRT.OUT
0DD1: 180B  JC 0DCC
0DD2: 0AA8  PRT.GO            ; print the line
0DD3: 0D20  A=C+1 MLSD1       ; test number + 1
0DD4: 01D7  A<>E ALL
0DD5: 0050  TST fA[5]         ; all tests done?
0DD6: 17F3  JNC 09DD          ; yes (or a failure, 10BE) → 09DD: restart
0DD7: 0A0C  MOV KR,EXT[4..15] ; next table slot: SR + 16 …
0DD8: 0A0D  SWAP KR,SR
0DD9: 0A04  INC KR
0DDA: 1FF3  JC 09E1           ; … → 09E1 → 07B5: jump to test n (0x0C0n)
; RTN stack shift (from 14F9): drop level 1 — SCOM[15] levels 2–3 move down
; one level (5 nibbles), level 4 comes back from SCOM[14], depth − 1; cache
; reload (fB[11]). Trace-confirmed (nested SBR).
0DDB: 032C  C=C-1 DPT1
0DDC: 0121  IO=C ALL
0DDD: 0A1F  RCLF              ; D := SCOM[14] (levels 4–6) …
0DDE: 01D6  D=LOAD ALL
0DDF: 0C30  A=D MAEX
0DE0: 0A47  MOV R5,#4
0DE1: 02F4  C=R5 DPT
0DE2: 0C7E  D=SRD MAEX        ; … shift both rows by one level (5 nibbles) …
0DE3: 0C5B  B=SRB MAEX
0DE4: 0C40  A=SLA MAEX
0DE5: 0C40  A=SLA MAEX
0DE6: 032C  C=C-1 DPT1
0DE7: 180B  JC 0DE2
0DE8: 0983  B=A+B MANT
0DE9: 0121  IO=C ALL
0DEA: 0A0F  STOF              ; SCOM[15] := levels 1–3 after the pop
0DEB: 0111  IO=B ALL
0DEC: 032C  C=C-1 DPT1
0DED: 0121  IO=C ALL
0DEE: 0A0F  STOF              ; SCOM[14] := levels 4–6
0DEF: 0131  IO=D ALL
0DF0: 00B9  SET fB[11]        ; program cache stale
0DF1: 00D8  TST fB[13]
0DF2: 1808  JC 0DF6
0DF3: 0308  A=A-1 DPT1
0DF4: 1804  JC 0DF6
0DF5: 000A  CLR fB[0]         ; program stops
0DF6: 01D7  A<>E ALL
0DF7: 04D4  C=LOAD DPTC
0DF8: 1BF1  JC 0C00
; Op 10 (signum): X := −1, 0 or 1 with X's sign.
0DF9: 0D29  IO=C-1 MLSD1      ; X zero → stays 0
0DFA: 108A  JNC 0E3F
0DFB: 0ED4  C=LOAD MMSD1      ; else 1.0 (sign kept, exponent sign cleared)
0DFC: 003A  CLR fB[3]
0DFD: 1884  JC 0E3F
; ═══════════════════════════════════════════════════════════════════════════
; RAM_WRITE  (0x0DFE–0x0E04) — write C (the value; signs from fB[1..4] into
; nibble 0) to the register whose binary address is in D (from 0A24: STO,
; SUM / Prd / Exc store-back, Dsz).
; Δ [HW] Replaces TI-59 0CF7–0CFE + 0FF4–0FFF (RAM.OP write, op 1 in nibble
; 0, uncorrected-sum hex tens nibble): MEMWR, then the 16 data nibbles.
; ═══════════════════════════════════════════════════════════════════════════
0DFE: 0A16  MOV R5,fB[1..4]   ; value signs …
0DFF: 02F4  C=R5 DPT          ; … into nibble 0
0E00: 0131  IO=D ALL          ; RAM address …
0E01: 0A76  MEMWR             ; … write …
0E02: 0121  IO=C ALL          ; … the value
0E03: 04D4  C=LOAD DPTC       ; C[0] := 0xC again
0E04: 1AF5  JC 0C8A           ; → 0B3B → ARITH_EXIT
; Op 19: set flag 7 if an error is pending; Op 18 (fA[8] set): if none.
; Both go through FLAG_OP with n = 7 (0E09 → 11E1).
0E05: 0098  TST fB[9]         ; error pending?
0E06: 1C11  JC 0BFE
0E07: 0080  TST fA[8]
0E08: 1023  JNC 0DF7
0E09: 01D7  A<>E ALL
0E0A: 0A77  MOV R5,#7         ; flag 7 …
0E0B: 09F0  A=R5 MANT
0E0C: 01D7  A<>E ALL
0E0D: 1FA8  JC 11E1           ; … set (FLAG_OP)
; Δ [REORG] TI-59 0E10 (JC 11E0, the Op 18/19 tail) is 0E0D here, one word
; earlier. 0E0E/0E0F are new relay jumps (JNC chains keep COND), 0E10 is an
; unused no-op. 0E10 is the address of keycode 01 but not a slot: digits are
; never dispatched (0F87), so the change does not affect scanning.
0E0E: 17CC  JNC 11F4          ; relay: 0AA6 (traced label operand) → 11F4 → 15EF
0E0F: 15E5  JNC 0B1D          ; relay: 1165 (from 14EE) → 0B1D
0E10: 0100  A=A ALL           ; unused (never executed)
; ═══════════════════════════════════════════════════════════════════════════
; PROGRAM SCANNER TABLE  (0x0E11–0x0E98) — trace-confirmed on the TI-58C
; (Lbl A … SBR A, GTO B, Dsz loop). While the label search (0F74) walks a
; program it dispatches each keycode through PREG to 0x0E<units><tens>
; (built at 0F81–0F9B), so it can skip the operand bytes that follow an
; instruction — a register number after STO looks like a keycode but must
; not be mistaken for a Lbl. The slots hold one JC each; the non-slot
; addresses in between (x0, xA–xF) are ordinary code: keycodes with units 0
; or tens 0 (the digits 00–09 and E′, CLR′ … List) go to 0E99 before the
; jump (0F84–0F88), so 0E0x and 0Ex0 are never slots (verified: a program of
; 00–09 and 10–90 is walked without a single PREG landing). Classes:
;   0E99 plain step          11B8 one operand byte (register / Op / Pgm)
;   0E90 address follows     0E50 Lbl: the next byte is a label name
;   0E64 INV prefix toggle   0E8C/0E8E operand unless INV (Fix, SBR → RTN)
;   0E68/0E79 Dsz, If flg: digit then address
; Δ [REORG] All 81 slots as on the TI-59 (same classes); only the in-between
; words 0E0D–0E10, 0E2A, 0E8A, 0E8B and 0E9D changed (relays, see there).
; ═══════════════════════════════════════════════════════════════════════════
0E11: 1910  JC 0E99           ; keycode 11 A: no operand
0E12: 190E  JC 0E99           ; keycode 21 2nd: no operand
0E13: 190C  JC 0E99           ; keycode 31 LRN: no operand
0E14: 190A  JC 0E99           ; keycode 41 SST: no operand
0E15: 1908  JC 0E99           ; keycode 51 BST: no operand
0E16: 18F4  JC 0E90           ; keycode 61 GTO: followed by a transfer address (label or 3-digit
                              ;   step)
0E17: 18EE  JC 0E8E           ; keycode 71 SBR: address follows unless INV (RTN)
0E18: 1902  JC 0E99           ; keycode 81 RST: no operand
0E19: 1900  JC 0E99           ; keycode 91 R/S: no operand
; Cache path: D := SCOM[10], shift by one keycode (A[0] = 1) → 0EE3.
0E1A: 0AA7  MOV R5,#10
0E1B: 02F6  D=R5 DPT
0E1C: 0131  IO=D ALL
0E1D: 0A1F  RCLF
0E1E: 01D6  D=LOAD ALL        ; D := cached register
0E1F: 03D0  A=LOAD DPT1       ; one keycode
0E20: 1986  JC 0EE3
0E21: 18F0  JC 0E99           ; keycode 12 B: no operand
0E22: 1884  JC 0E64           ; keycode 22 INV: toggles INV (fA[8]) for the next keycode
0E23: 18EC  JC 0E99           ; keycode 32 x⇄t: no operand
0E24: 1F28  JC 11B8           ; keycode 42 STO: one operand byte (register / Op / Pgm number) —
                              ;   skipped
0E25: 18E8  JC 0E99           ; keycode 52 EE: no operand
0E26: 1F24  JC 11B8           ; keycode 62 Pgm Ind: one operand byte (register / Op / Pgm
                              ;   number) — skipped
0E27: 1F22  JC 11B8           ; keycode 72 STO Ind: one operand byte (register / Op / Pgm
                              ;   number) — skipped
0E28: 1F20  JC 11B8           ; keycode 82 HIR: one operand byte (register / Op / Pgm number) —
                              ;   skipped
0E29: 18E0  JC 0E99           ; keycode 92 RTN: no operand
; Δ [REORG] TI-59 0E2A: JNC 0A6D, the end-of-CMs/CP relay (that end is 0FE6
; here, reached directly). Here the RTN relay the TI-59 had at 0E8B.
0E2A: 1E96  JC 1175           ; relay: RTN (compact keycode 92, 0B20) → RTN_POP
0E2B: 0A67  MOV R5,#6
0E2C: 1918  JC 0EB8
0E2D: 14A2  JNC 107E
0E2E: 0A45  TST KR[4]
0E2F: 1F73  JC 0A76
0E30: 12B1  JNC 0CD8
0E31: 18D0  JC 0E99           ; keycode 13 C: no operand
0E32: 18CE  JC 0E99           ; keycode 23 lnx: no operand
0E33: 18CC  JC 0E99           ; keycode 33 x²: no operand
0E34: 1F08  JC 11B8           ; keycode 43 RCL: one operand byte (register / Op / Pgm number) —
                              ;   skipped
0E35: 18C8  JC 0E99           ; keycode 53 (: no operand
0E36: 1F04  JC 11B8           ; keycode 63 Exc Ind: one operand byte (register / Op / Pgm
                              ;   number) — skipped
0E37: 1F02  JC 11B8           ; keycode 73 RCL Ind: one operand byte (register / Op / Pgm
                              ;   number) — skipped
0E38: 1F00  JC 11B8           ; keycode 83 GTO Ind: one operand byte (register / Op / Pgm
                              ;   number) — skipped
0E39: 18C0  JC 0E99           ; keycode 93 .: no operand
0E3A: 00AA  CLR fB[10]
0E3B: 0042  CLR fA[4]
0E3C: 00CA  CLR fB[12]
0E3D: 0002  CLR fA[0]
0E3E: 0091  SET fA[9]
0E3F: 0059  SET fB[5]
0E40: 1893  JC 0DF7
0E41: 18B0  JC 0E99           ; keycode 14 D: no operand
0E42: 18AE  JC 0E99           ; keycode 24 CE: no operand
0E43: 18AC  JC 0E99           ; keycode 34 √x: no operand
0E44: 1EE8  JC 11B8           ; keycode 44 SUM: one operand byte (register / Op / Pgm number) —
                              ;   skipped
0E45: 18A8  JC 0E99           ; keycode 54 ): no operand
0E46: 1EE4  JC 11B8           ; keycode 64 Prd Ind: one operand byte (register / Op / Pgm
                              ;   number) — skipped
0E47: 1EE2  JC 11B8           ; keycode 74 SUM Ind: one operand byte (register / Op / Pgm
                              ;   number) — skipped
0E48: 1EE0  JC 11B8           ; keycode 84 Op Ind: one operand byte (register / Op / Pgm number)
                              ;   — skipped
0E49: 18A0  JC 0E99           ; keycode 94 +/-: no operand
0E4A: 01D7  A<>E ALL
0E4B: 0201  IO=A DPT
0E4C: 0007  MOV fA[1..4],R5
0E4D: 04D0  A=LOAD DPTC
0E4E: 005A  CLR fB[5]
0E4F: 1EDA  JC 11BC
0E50: 0001  SET fA[0]
0E51: 1890  JC 0E99           ; keycode 15 E: no operand
0E52: 188E  JC 0E99           ; keycode 25 CLR: no operand
0E53: 188C  JC 0E99           ; keycode 35 1/x: no operand
0E54: 188A  JC 0E99           ; keycode 45 y^x: no operand
0E55: 1888  JC 0E99           ; keycode 55 ÷: no operand
0E56: 1886  JC 0E99           ; keycode 65 ×: no operand
0E57: 1884  JC 0E99           ; keycode 75 −: no operand
0E58: 1882  JC 0E99           ; keycode 85 +: no operand
0E59: 1880  JC 0E99           ; keycode 95 =: no operand
; ═══════════════════════════════════════════════════════════════════════════
; INS_DEL  (0x0E5A, loop 0B92 / 1200–123C / 0F6A) — Ins (fA[8] clear) and Del
; (fA[8] set) in LRN mode. Trace-confirmed on the TI-58C (LRN 5 + 3 BST Ins /
; Del: 30 register passes under 239.29). Starting with the register that
; holds the current step and running to the end of the program partition,
; every program register is read (0EDA, MEMRD), shifted by one keycode — up
; for Ins (00 inserted at the current step), down for Del (the next
; register's first keycode carried in at the top) — and written back (0F6A,
; MEMWR; binary address from the count loop 122B–122E). The current step's
; register is combined with its SCOM[10] cache copy (1219; see the
; missing-safeguard note there). Steps beyond the partition are lost / 00.
; ═══════════════════════════════════════════════════════════════════════════
0E5A: 00B9  SET fB[11]        ; cache must be reloaded afterwards
0E5B: 0A1F  RCLF              ; SCOM[0]: start at the current step's register …
0E5C: 09D0  A=LOAD MANT
0E5D: 0A0C  MOV KR,EXT[4..15]
0E5E: 0075  SET KR[7]
0E5F: 0148  A=SRA ALL
0E60: 1D9F  JC 0B91           ; … read loop via PRGREG_FETCH's RAM branch
0E61: 1870  JC 0E99           ; keycode 16 A': no operand
0E62: 186E  JC 0E99           ; keycode 26 2nd': no operand
0E63: 1EAA  JC 11B8           ; keycode 36 Pgm: one operand byte (register / Op / Pgm number) —
                              ;   skipped
0E64: 0083  TOG fA[8]
0E65: 186A  JC 0E9A           ; keycode 56 Del: no operand
0E66: 1866  JC 0E99           ; keycode 66 Pause: no operand
0E67: 182F  JC 0E50           ; keycode 76 Lbl: next byte is a label name
0E68: 00C9  SET fB[12]
0E69: 1860  JC 0E99           ; keycode 96 Write: no operand
0E6A: 01D5  C<>D ALL
0E6B: 0092  CLR fA[9]
0E6C: 00CA  CLR fB[12]
0E6D: 0052  CLR fA[5]
0E6E: 0002  CLR fA[0]
0E6F: 1ECB  JC 0B0A
0E70: 1F49  JC 0ACC           ; label found → 0ACC → STEP_TO_REG (086B): transfer to the step
                              ;   after the label
0E71: 1850  JC 0E99           ; keycode 17 B': no operand
0E72: 181D  JC 0E64           ; keycode 27 INV': toggles INV (fA[8]) for the next keycode
0E73: 184C  JC 0E99           ; keycode 37 P→R: no operand
0E74: 184A  JC 0E99           ; keycode 47 CMs: no operand
0E75: 1848  JC 0E99           ; keycode 57 Eng: no operand
0E76: 1834  JC 0E90           ; keycode 67 x=t: followed by a transfer address (label or 3-digit
                              ;   step)
0E77: 1832  JC 0E90           ; keycode 77 x≥t: followed by a transfer address (label or 3-digit
                              ;   step)
0E78: 0100  A=A ALL
0E79: 0051  SET fA[5]
0E7A: 1825  JC 0E68
0E7B: 019C  C=C-B ALL         ; Del, current register: C := steps below the cursor (register −
                              ;   cache)
0E7C: 0148  A=SRA ALL         ; A := cached steps from the cursor up, one keycode down
0E7D: 0148  A=SRA ALL         ; (the deleted keycode drops out)
0E7E: 01D5  C<>D ALL
0E7F: 01B4  C=A+D ALL         ; C := low part + shifted high part; top byte still empty
0E80: 19DE  JC 0F6F           ; write deferred: the next register's first keycode fills the top
0E81: 1830  JC 0E99           ; keycode 18 C': no operand
0E82: 182E  JC 0E99           ; keycode 28 log: no operand
0E83: 182C  JC 0E99           ; keycode 38 sin: no operand
0E84: 1E68  JC 11B8           ; keycode 48 Exc: one operand byte (register / Op / Pgm number) —
                              ;   skipped
0E85: 180E  JC 0E8C           ; keycode 58 Fix: one digit unless INV
0E86: 1828  JC 0E9A           ; keycode 68 Nop: no operand
0E87: 1824  JC 0E99           ; keycode 78 Σ+: no operand
0E88: 1822  JC 0E99           ; keycode 88 D.MS: no operand
0E89: 1820  JC 0E99           ; keycode 98 Adv: no operand
; Δ [REORG] 0E8A/0E8B keep their place but serve other callers: TI-59 0E8A
; was the HIR relay (0CCB → 11BC; HIR now goes 0CBC → 103E → 12E2) and 0E8B
; the RTN relay (now 0E2A). Here the trace-symbol relay of TI-59 0EA4 and an
; Ind relay.
0E8A: 1FDA  JC 1277           ; relay: trace-symbol queue (0B1C) → 1277 → 141A
0E8B: 1F19  JC 0AFF           ; relay: Ind operand converted (1282) → 0AFF → 07AE
0E8C: 0080  TST fA[8]
0E8D: 184B  JC 0E68
0E8E: 0080  TST fA[8]
0E8F: 1014  JNC 0E99
0E90: 0051  SET fA[5]
0E91: 1810  JC 0E99           ; keycode 19 D': no operand
0E92: 180E  JC 0E99           ; keycode 29 CP: no operand
0E93: 180C  JC 0E99           ; keycode 39 cos: no operand
0E94: 1E48  JC 11B8           ; keycode 49 Prd: one operand byte (register / Op / Pgm number) —
                              ;   skipped
0E95: 1808  JC 0E99           ; keycode 59 Int: no operand
0E96: 1E44  JC 11B8           ; keycode 69 Op: one operand byte (register / Op / Pgm number) —
                              ;   skipped
0E97: 1804  JC 0E99           ; keycode 79 x̄: no operand
0E98: 1802  JC 0E99 ; clear COND ; keycode 89 π: no operand
0E99: 0082  CLR fA[8]         ; next keycode (INV no longer pending) …
0E9A: 0040  TST fA[4]         ; scanner: next keycode (Nop, Del, INV …)
0E9B: 158A  JNC 1160
0E9C: 0219  IO=-B DPT
0E9D: 16C2  JNC 11FE          ; library program → next byte (11FE → 15A2)
0E9E: 017E  D=SRD ALL         ; … shift the next keycode into nibbles 1..0
0E9F: 0308  A=A-1 DPT1        ; … keycodes left in this register?
0EA0: 19B2  JC 0F79           ; yes → classify it
0EA1: 0910  A=B MANT          ; no → next register …
0EA2: 0D00  A=A+1 MLSD1
0EA3: 1DA7  JC 0BD0           ; … (end-of-memory check at 0BD0)
; COMPACT_IND (bank slots 0B22–0B29): a compact Ind keycode is expanded into
; two keystrokes — Ind (keycode 40) is parked as the pending key in SCOM[0]
; nibbles 1–2 (fB[14], 0EA7–0EAB), and the base operation is dispatched now
; (0EAC–0EBC derive it from the digit: 72 → 42 STO, 73 → 43 RCL, 74 → 44 SUM,
; 62 → 36 Pgm, 63 → 48 Exc, 64 → 49 Prd, 83 → 61 GTO, 84 → 69 Op). Trace-
; confirmed on the TI-58C: 7 STO 01, program "5 STO Ind 01 R/S" (stored as
; ST* 01) → R07 = 5.
; Δ [REORG] TI-59 0EA4 (JC 1278, trace-symbol relay from 0B17) removed — that
; relay is 0E8A here — so COMPACT_IND starts one word earlier (TI-59 0EA5).
0EA4: 01D7  A<>E ALL
0EA5: 0A1F  RCLF              ; SCOM[0] …
0EA6: 01D0  A=LOAD ALL
0EA7: 0A47  MOV R5,#4         ; … pending key := 40 (Ind) …
0EA8: 06F6  D=R5 EXP
0EA9: 0670  A=SLD EXP
0EAA: 0A0F  STOF
0EAB: 0101  IO=A ALL
0EAC: 0A08  MOV R5,KR[4..7]   ; the digit of the key position → base operation keycode
0EAD: 09F0  A=R5 MANT
0EAE: 02F6  D=R5 DPT
0EAF: 0D08  A=A-1 MLSD1
0EB0: 0D08  A=A-1 MLSD1
0EB1: 0D09  IO=A-1 MLSD1
0EB2: 110F  JNC 0E2B
0EB3: 0B0E  D=A-5 MLSD5
0EB4: 100C  JNC 0EBA
0EB5: 0939  IO=-D MANT
0EB6: 14D5  JNC 0C4C
0EB7: 0A37  MOV R5,#3
0EB8: 06F6  D=R5 EXP
0EB9: 0D00  A=A+1 MLSD1
0EBA: 0901  IO=A MANT
0EBB: 02F6  D=R5 DPT
0EBC: 1CE1  JC 0C4C           ; → fB[14], dispatch the base operation (0D56 → 0BF9 → 0833)
0EBD: 00B9  SET fB[11]        ; BST: cache reload …
0EBE: 0A1F  RCLF              ; SCOM[0] step …
0EBF: 01D0  A=LOAD ALL
0EC0: 0948  A=SRA MANT
0EC1: 0A18  MOV KR[4..7],R5
0EC2: 0508  A=A-1 LLSD1       ; … − 1 (borrow from the register digits)
0EC3: 1E7B  JC 0B86           ; store and show
0EC4: 0948  A=SRA MANT        ; byte 0: previous register, byte 7 (BST 008 → 007) …
0EC5: 014E  D=SRA ALL
0EC6: 017E  D=SRD ALL
0EC7: 017E  D=SRD ALL
0EC8: 09DE  D=0 MANT
0EC9: 0139  IO=-D ALL         ; … but at step 000 BST stays at 000 (no wrap; trace-checked)
0ECA: 1806  JC 0ECD
0ECB: 0A37  MOV R5,#3
0ECC: 09F6  D=R5 MANT
0ECD: 0940  A=SLA MANT
0ECE: 09B8  A=A-D MANT
0ECF: 1E93  JC 0B86
0ED0: 0148  A=SRA ALL         ; LRN: completed argument → record it (0B16)
0ED1: 0148  A=SRA ALL
0ED2: 0308  A=A-1 DPT1
0ED3: 0308  A=A-1 DPT1
0ED4: 01DE  D=0 ALL
0ED5: 12FB  JNC 0D58
0ED6: 00B1  SET fA[11]
0ED7: 0901  IO=A MANT
0ED8: 02F6  D=R5 DPT
0ED9: 1AFD  JC 0D5B
; PRGREG_RAM_READ: MEMRD of the program register into D, then shift it right
; by A[0] keycodes (the byte position) so the current step's keycode lands
; in nibbles 1..0, and cache it (0C0B). Entry: A[1..0] = binary RAM address
; (= register number, from the count loop 0B80–0B83 or 122B–122E), D[1] =
; byte position. Trace-confirmed (SST at step 013: address 01, byte 5).
; Δ [HW] TI-59 0EDB–0EE0: A=SLA ALL, RAM.OP, IO=A+D (op 0 + BCD address in
; bus nibbles 3·2), A=SRA ALL. Here MEMRD takes the binary address from bus
; nibbles 1·0, so the byte position is parked (D[1] → R5 → A[3]) during the
; read and put into A[0] afterwards (0EE0–0EE1).
0EDA: 0631  IO=D EXP          ; R5 := byte position (D[1]) …
0EDB: 09F0  A=R5 MANT         ; … parked in A[3] (A[15..4] := 0)
0EDC: 0101  IO=A ALL          ; bus: A[1..0] = RAM address
0EDD: 0A86  MEMRD             ; read the program register …
0EDE: 01D6  D=LOAD ALL        ; … D := program register
0EDF: 0A75  TST KR[7]         ; Ins / Del pass?
0EE0: 0901  IO=A MANT         ; R5 := byte position (A[3]) …
0EE1: 02F0  A=R5 DPT          ; … A[0] := byte count
0EE2: 163C  JNC 1200          ; yes → shift this register (no byte positioning)
0EE3: 0308  A=A-1 DPT1        ; byte count …
0EE4: 15B3  JNC 0C0B          ; … exhausted → cache it
0EE5: 017E  D=SRD ALL         ; shift one keycode (two nibbles)
0EE6: 017E  D=SRD ALL
0EE7: 1809  JC 0EE3
0EE8: 0130  A=D ALL           ; sign and print
0EE9: 0D09  IO=A-1 MLSD1      ; X = 0? → leading 0 (0EF1)
0EEA: 100E  JNC 0EF1
0EEB: 0038  TST fB[3]         ; exponent positive: integer digits present, no leading 0
0EEC: 1818  JC 0EF8
0EED: 0709  IO=A-1 EXP1       ; negative exponent shown in sci form ("1.-02"): none either
0EEE: 1814  JC 0EF8
0EEF: 0C19  IO=-B MAEX
0EF0: 1810  JC 0EF8
; ── Pseudo-keycode landing zone ─────────────────────────────────────────────
; 0x0EF1 is an ordinary instruction of the numeric print formatter (leading
; '0' branch, ends in PRT.GO at 0EFD); no keycode legitimately targets it.
; The unvalidated scanner dispatch (0F81–0F9B) lands here for the
; pseudo-keycode 1F (units F, tens 1). On the TI-58C (headless: label search
; over a register holding 1F) MOV R5,#10 / B=R5 DPT / IO=A-B DPT then decide
; whether a '0' is sent (0EF7), and PRT.GO prints the line ("0" observed).
; The TI-59's 0x0EF1 is its B=R5 DPT (≙ 0EF2): this code sits one word later
; here (0EE0–0EE1 are two words), so 1F skips the R5 := 10 there and goes
; straight to PRT.GO — the printer-interrupt trick of examples/texas-print.ti59.
0EF1: 0AA7  MOV R5,#10        ; yes: '0' before the point when all digits are fraction
0EF2: 02F3  B=R5 DPT
0EF3: 0289  IO=A-B DPT
0EF4: 1808  JC 0EF8
0EF5: 0A0C  MOV KR,EXT[4..15]
0EF6: 0045  SET KR[4]
0EF7: 0A68  PRT.OUT           ; the leading 0 ("0.5", "0.001", "0.")
0EF8: 0A0C  MOV KR,EXT[4..15]
0EF9: 0085  SET KR[8]         ; code 16 = '−' …
0EFA: 0020  TST fA[2]         ; … if negative
0EFB: 1804  JC 0EFD
0EFC: 0A68  PRT.OUT
0EFD: 0AA8  PRT.GO            ; print the line (also reached by pseudo-keycode 1F, 0EF1)
0EFE: 00A2  CLR fA[10]        ; trace record printed → clear pending flag
0EFF: 0042  CLR fA[4]
0F00: 0002  CLR fA[0]
0F01: 0050  TST fA[5]
0F02: 163D  JNC 0BE4
0F03: 1E77  JC 0BC8
; Unused filler: A=A ALL (no-op) words, never executed.
; Δ [REORG] TI-59 0F03–0F0C: ten filler words. Two remain; 0F06–0F0C hold
; the new program-register address preparation.
0F04: 0100  A=A ALL
0F05: 0100  A=A ALL
; PRGREG_ADDR_PREP (from 0FA8, LRN store): after the shifts at 0FA5/0FA6 and
; here, the step counter's register digits are in A[3..1]; they become the
; BCD register number in A[5..3] with the rest cleared, which the count loop
; at 0D96 turns into the binary RAM address for the MEMRD at 0D9E (→ 1155).
; Trace-confirmed (LRN store at step 008: register 001 → address 01).
; Δ [HW] new: TI-59 0F98 → 0D4A → 0A1A built the BCD RAM.OP bus address.
0F06: 0148  A=SRA ALL         ; register digits: units A[1] …
0F07: 0148  A=SRA ALL         ; … tens A[2], hundreds A[3]
0F08: 0901  IO=A MANT         ; R5 := hundreds digit
0F09: 09F0  A=R5 MANT         ; A[3] := hundreds, A[15..4] := 0
0F0A: 0C40  A=SLA MAEX        ; register number to A[5..3] …
0F0B: 0C40  A=SLA MAEX        ; … A[2..0] = 0
0F0C: 1AED  JC 0D96           ; → BCD → binary (0D96), MEMRD (0D9E), LRN_STORE (1155)
; END_OF_PROGRAM_MEMORY (from 0B79): the step counter left the program
; partition. Running → stop with the error blink (0F1F–0F21; trace-confirmed:
; GTO Ind to an empty area runs off the end); LRN mode → 0B5E.
0F0D: 0A75  TST KR[7]         ; Ins / Del pass: last register done → 1263
0F0E: 16AA  JNC 1263
0F0F: 0939  IO=-D MANT
0F10: 1014  JNC 0F1A
0F11: 0A1F  RCLF
0F12: 01D0  A=LOAD ALL
0F13: 0948  A=SRA MANT
0F14: 0D08  A=A-1 MLSD1
0F15: 0D08  A=A-1 MLSD1
0F16: 0D08  A=A-1 MLSD1
0F17: 0940  A=SLA MANT
0F18: 0A0F  STOF
0F19: 0101  IO=A ALL
0F1A: 00B9  SET fB[11]
0F1B: 0040  TST fA[4]
0F1C: 11C5  JNC 0E3A
0F1D: 00A8  TST fB[10]        ; LRN mode?
0F1E: 1781  JNC 0B5E
0F1F: 000A  CLR fB[0]         ; running: stop …
0F20: 01D2  A<>B ALL
0F21: 0099  SET fB[9]         ; … with ERROR
0F22: 1A57  JC 0DF7
; Δ [REORG] TI-59 0F23–0F33 read the Ind pointer register (RAM.OP) and took
; its integer part; that is 0D9E (MEMRD) and 0F5D–0F68 here. 0F23 is the
; relay of TI-59 0F35, 0F24–0F4D are CORDIC pieces moved from TI-59
; 0C5D–0C66 and 0C97–0CB6 (identical results: sin, cos, tan and their
; inverses for six arguments, headless, both machines).
0F23: 1732  JNC 12BC          ; relay: 0B5D → 12BC
0F24: 0C48  A=SRA MAEX        ; x-step: y · 10^−k … (entered at 0F25 from 0C5C)
0F25: 032C  C=C-1 DPT1
0F26: 1805  JC 0F24
0F27: 0CD2  A<>B MAEX
0F28: 0C89  IO=A-B MAEX
0F29: 1591  JNC 0C61
0F2A: 0C8B  B=A-B MAEX        ; … x' = x − y·10^−k
0F2B: 0A08  MOV R5,KR[4..7]
0F2C: 02F4  C=R5 DPT
0F2D: 1D29  JC 0C99           ; → y-step
; Arc mode accumulation (backwards CORDIC): count how often each atan(10^−k)
; rotation is needed to drive y to zero; the angle is built in C. Entered at
; 0F49 (from 0C63); finished → 0B3A (0F32 / 0F48).
0F2E: 0F24  C=C+1 MAEX1       ; angle digit + 1 …
0F2F: 0C88  A=A-B MAEX        ; … while y can be reduced
0F30: 1805  JC 0F2E
0F31: 0C80  A=A+B MAEX
0F32: 1FF1  JC 0B3A
0F33: 0C64  C=SLC MAEX
0F34: 0C5B  B=SRB MAEX
0F35: 0C19  IO=-B MAEX
0F36: 100F  JNC 0F2F
0F37: 0C6C  C=SRC MAEX
0F38: 01A3  B=C+D ALL
0F39: 00B0  TST fA[11]
0F3A: 1804  JC 0F3C
0F3B: 0A06  MOV R5,fA[1..4]
0F3C: 0030  TST fA[3]
0F3D: 0007  MOV fA[1..4],R5
0F3E: 0CC4  C=A+CON MAEX
0F3F: 1004  JNC 0F41
0F40: 0C9B  B=C-B MAEX
0F41: 00C0  TST fA[12]
0F42: 1823  JC 0F31
0F43: 0020  TST fA[2]
0F44: 1827  JC 0F31
0F45: 0022  CLR fA[2]
0F46: 0CE4  C=C+CON MAEX
0F47: 0C98  A=C-B MAEX
0F48: 182D  JC 0F32
0F49: 0080  TST fA[8]
0F4A: 1CC3  JC 0CE9
0F4B: 0C26  D=C MAEX
0F4C: 01DC  C=0 ALL
0F4D: 183D  JC 0F2F
; PAPER_ADVANCE: feed two blank lines (PRT.FEED, paced by TST.BUSY), then keep
; feeding while the printer's ADV button (digit 12 / K-line N) or the
; calculator's "." key (row 9 / column 3 — Adv is 2nd .) is still held.
; Trace-confirmed (ADV button held: one line per printer cycle).
0F4E: 0A01  CLR.IDLE
0F4F: 0A0C  MOV KR,EXT[4..15]
0F50: 0A98  PRT.STEP          ; wait until the printer is idle …
0F51: 0A0B  TST.BUSY
0F52: 1005  JNC 0F50
0F53: 0AB8  PRT.FEED          ; … one blank line
0F54: 0A04  INC KR
0F55: 0A55  TST KR[5]         ; two lines done?
0F56: 180D  JC 0F50
0F57: 0AD0  WAIT D13          ; printer ADV button still held …
0F58: 08FE  KEY [N]
0F59: 0AA0  WAIT D10          ; … or the "." key?
0F5A: 08EF  KEY [Q]
0F5B: 1019  JNC 0F4F          ; yes → keep feeding
0F5C: 1E8F  JC 0C15
; IND_POINTER (from 0DA4; the pointer register was read by the MEMRD at
; 0D9E): the pointer's integer part becomes the register / address operand.
; A negative pointer or one below 1 (KR[5] / KR[6] = mantissa / exponent
; sign bits of A[0]) gives 0 (0F67 → 127D); otherwise 1278 takes the integer
; digits. Verified on both machines: pointer −3 or 0.5 → STO Ind stores R00.
; Δ [REORG] TI-59 0F29–0F33 (after its own RAM.OP read at 0F23–0F28); CLR
; fA[7] moved here from TI-59 0DDC.
0F5D: 0072  CLR fA[7]         ; Ind consumed
0F5E: 0A08  MOV R5,KR[4..7]   ; save KR[4..7] in D[0]
0F5F: 02F6  D=R5 DPT
0F60: 0201  IO=A DPT          ; R5 := A[0], the pointer's sign bits
0F61: 0A18  MOV KR[4..7],R5
0F62: 0A55  TST KR[5]         ; mantissa negative …
0F63: 0A65  TST KR[6]         ; … or exponent negative (|x| < 1)?
0F64: 0231  IO=D DPT          ; restore KR[4..7]
0F65: 0A18  MOV KR[4..7],R5
0F66: 1E24  JC 1278           ; no → integer part (1278)
0F67: 01D8  A=0 ALL           ; yes → 0
0F68: 1E2A  JC 127D
0F69: 1F4D  JC 0BC3           ; relay: 1262 / 135F → 0BC3
; PRGREG_RAM_WRITE (Ins / Del pass from 122C, Op 09 download): MEMWR of D
; into the program register at the binary address A[1..0]; Op 09 (fB[10]
; clear) continues at 1319, Ins / Del with the next register (address + 1,
; KR[4] = "not the cursor's register", → 0B92: partition check and read).
; Trace-confirmed (Ins at step 002: 30 register writes under 239.29).
; Δ [HW] TI-59 0F84–0F8F: RAM.OP write (op 1 + BCD address in bus nibbles
; 3·2, then the data). Here the binary address goes on the bus, MEMWR, then
; the data on the next IO.
0F6A: 0101  IO=A ALL          ; bus: A[1..0] = RAM address
0F6B: 0A76  MEMWR             ; write the program register …
0F6C: 0131  IO=D ALL          ; … data D
0F6D: 00A8  TST fB[10]        ; LRN (Ins / Del)? no → Op 09 download (1319)
0F6E: 1F56  JC 1319
0F6F: 01D7  A<>E ALL          ; next register: address + 1 …
0F70: 0603  B=A EXP
0F71: 0D00  A=A+1 MLSD1
0F72: 0045  SET KR[4]         ; … KR[4] = "not the cursor's register"
0F73: 1FC3  JC 0B92           ; … → partition check and read (0B69)
; ═══════════════════════════════════════════════════════════════════════════
; LABEL_SEARCH loop  (0x0F74–0x0F9B, 0x0E99–0x0EA3, 0x1242–0x125B) — read the
; next program register (8 keycodes) into D and walk it keycode by keycode
; (A[0] = keycodes left). Each keycode (D[1..0]) is classified through the
; PROGRAM SCANNER TABLE (0x0E11); fA[9] = skip the next byte (an operand),
; fA[0] = the next byte is a label name, compared with the wanted label at
; 1242. A match transfers to the step after it (0E70 → 0ACC → STEP_TO_REG).
; Entered from 0BE1 with the binary register address in A[1..0] (count loop
; 0BDC–0BE1); library programs feed the same loop through 1284 → 0F79.
; Δ [HW] TI-59 0F45–0F47: A=SLA ALL, RAM.OP, IO=A+D (BCD bus address). Here
; IO=A + MEMRD.
; ═══════════════════════════════════════════════════════════════════════════
0F74: 0101  IO=A ALL          ; bus: A[1..0] = RAM address
0F75: 0A86  MEMRD             ; read the program register
0F76: 01D6  D=LOAD ALL        ; D := 8 keycodes, the first in nibbles 1..0
0F77: 0A77  MOV R5,#7
0F78: 02F0  A=R5 DPT          ; A[0] := keycodes left in this register − 1
0F79: 0090  TST fA[9]         ; operand byte to skip?
0F7A: 0092  CLR fA[9]
0F7B: 1684  JNC 12BD          ; yes → skip it
0F7C: 00C8  TST fB[12]
0F7D: 0050  TST fA[5]
0F7E: 145C  JNC 11AC          ; address operand pending → 11AC
0F7F: 0000  TST fA[0]         ; label name byte?
0F80: 1584  JNC 1242          ; yes → compare with the wanted label
; ── Scanner dispatch (0x0F81–0x0F9B) ────────────────────────────────────────
; Splits the current keycode D[1..0] into its digits (IO=D DPT / IO=-D DPT /
; D=SRD ALL) and jumps through PREG to 0x0E00 + 16·units + tens: KR[15:13] =
; 111, KR[11:8] = units (bit-copied from KR[7:4] at 0F8C–0F97, there is no
; nibble shift for KR), KR[7:4] = tens (0F98–0F99); SET KR[1] at 0F9A jumps
; after the delay slot 0F9B. Units 0 or tens 0 → 0E99 (0F84–0F88). Missing
; safeguard: no range check on the digits, so a pseudo-keycode with a hex
; digit lands wherever its address points (1F → 0EF1, see there).
0F81: 0A0C  MOV KR,EXT[4..15] ; classify: KR := 0 …
0F82: 0231  IO=D DPT          ; … units digit …
0F83: 0A18  MOV KR[4..7],R5
0F84: 0239  IO=-D DPT         ; … units 0 →
0F85: 017E  D=SRD ALL
0F86: 19DB  JC 0E99           ; … plain step
0F87: 0239  IO=-D DPT         ; digit keycode 00–09 →
0F88: 19DF  JC 0E99           ; … plain step
0F89: 00E5  SET KR[14]        ; KR := 0xE000 | units<<8 | tens<<4 → slot 0x0E<units><tens>
0F8A: 00F5  SET KR[15]
0F8B: 00D5  SET KR[13]
0F8C: 0A75  TST KR[7]
0F8D: 1804  JC 0F8F
0F8E: 00B5  SET KR[11]
0F8F: 0A65  TST KR[6]
0F90: 1804  JC 0F92
0F91: 00A5  SET KR[10]
0F92: 0A55  TST KR[5]
0F93: 1804  JC 0F95
0F94: 0095  SET KR[9]
0F95: 0A45  TST KR[4]
0F96: 1804  JC 0F98
0F97: 0085  SET KR[8]
0F98: 0231  IO=D DPT
0F99: 0A18  MOV KR[4..7],R5
0F9A: 0015  SET KR[1] ; PREG ; jump into the scanner table
0F9B: 0A0C  MOV KR,EXT[4..15]
; Δ [REORG] TI-59 0F6E–0F8F: the INV List start moved to 12FE (entered via
; 103F), the program-register write-back to 0F6A. 0F9C–0F9F is TI-59
; 0F99–0F9C (argument completion, from 0C32), three words later.
0F9C: 0A55  TST KR[5]         ; argument completion (0C32: KR[7] of the suspended slot set):
                              ;   KR[5] too?
0F9D: 0A0D  SWAP KR,SR
0F9E: 16D1  JNC 0C36          ; yes → 0C36
0F9F: 1EB7  JC 0C44           ; no → 0C44 (pending key, dispatch)
0FA0: 0A47  MOV R5,#4         ; Ind as its own step: keycode 40
0FA1: 06F6  D=R5 EXP
0FA2: 0133  B=D ALL           ; B := new keycode
0FA3: 0A1F  RCLF              ; SCOM[0] (bus zero → row 0) …
0FA4: 09D0  A=LOAD MANT       ; … step counter: register number nibbles 5–7, byte nibble 4
0FA5: 0948  A=SRA MANT
0FA6: 0948  A=SRA MANT
0FA7: 0A18  MOV KR[4..7],R5   ; KR[4..7] := byte position 0–7
; Δ [HW] TI-59 0F98 → 0D4A → 0A1A (BCD RAM.OP bus address). Here → 0F06,
; which prepares the BCD register number for the binary conversion and MEMRD.
0FA8: 1945  JC 0F06           ; → address prep (0F06) → MEMRD (0D9E) → LRN_STORE (1155)
; INV_LIST (start 0x12FE–0x1313 via 0D0D → 103F; per-register loop
; 0x0FA9–0x0FB7, 0D0E via slot 0539; end 1142) — INV List: print the data
; registers from Int(X) up to the last one of the data partition, one line
; each: the value, then the register number in the function column.
; Trace-checked on the TI-58C (PC-100, 239.29, 7 STO 28, X = 28: "7.  28",
; "0.  29", then stop). The register number is kept in SCOM[0] nibbles 1–2
; (the pending-key field); SCOM[9] nibble 15 = 1 marks the listing while it
; runs. Each register goes through REG_ADDR with fA[13] set, so the first
; register past the partition ends the list (0D2D → 0FAE → 1142) instead of
; erroring. Holding R/S stops it (0FAA). The start (12FE) enters at 0FB1.
; Δ [REORG] TI-59 0F6E–0F83 (the start) is at 12FE–1313 here.
0FA9: 0AA0  WAIT D10
0FAA: 08FD  KEY [O]
0FAB: 0A1F  RCLF
0FAC: 01D0  A=LOAD ALL
0FAD: 0700  A=A+1 EXP1        ; next register …
0FAE: 1328  JNC 1142          ; … past 99 → done
0FAF: 0A0F  STOF
0FB0: 0101  IO=A ALL          ; SCOM[0] updated
0FB1: 09D8  A=0 MANT
0FB2: 0C40  A=SLA MAEX
0FB3: 0C40  A=SLA MAEX
0FB4: 0091  SET fA[9]         ; read it, print value + number (fA[10]); fA[13]: the partition
                              ;   check ends the list instead of an error
0FB5: 00A1  SET fA[10]
0FB6: 00D1  SET fA[13]
0FB7: 1D43  JC 0D16
0FB8: 1D9E  JC 1287
0FB9: 16F4  JNC 1333          ; relay → 1333 → LIB_LABEL_SEARCH (157A)
0FBA: 0A97  MOV R5,#9
0FBB: 02F3  B=R5 DPT
0FBC: 0111  IO=B ALL
0FBD: 0A1F  RCLF
0FBE: 01D0  A=LOAD ALL
0FBF: 0948  A=SRA MANT
0FC0: 06F3  B=R5 EXP
0FC1: 0948  A=SRA MANT
0FC2: 09F0  A=R5 MANT
0FC3: 0940  A=SLA MANT
0FC4: 0C53  B=SLB MAEX
0FC5: 0C53  B=SLB MAEX
0FC6: 0980  A=A+B MANT
0FC7: 0111  IO=B ALL
0FC8: 0A0F  STOF
0FC9: 0101  IO=A ALL
0FCA: 1EFB  JC 0C4D
; Δ [REORG] TI-59 0FBF–0FD1 (CLEAR_MEM entry and the CMs range) moved to
; 11C3–11D4; three relays are left here.
0FCB: 176B  JNC 0C16          ; relay: LRN store (1603 → 1331) → 0C16, add and write back
0FCC: 1BEE  JC 11C3           ; relay: CMs / CP (0BE6) → CLEAR_MEM 11C3
0FCD: 1FA8  JC 13A1           ; relay: print the value (0BE5) → 13A1 → PRT_VALUE
; Octant folding (see 08EC): subtract π/4 multiples (constant 8 via KR),
; swapping sin↔cos (fA[12]) and adjusting the sign (fA[2]) per octant.
0FCE: 0CC8  A=A-CON MAEX
0FCF: 00C0  TST fA[12]
0FD0: 1010  JNC 0FD8
0FD1: 0023  TOG fA[2]
0FD2: 0A57  MOV R5,#5
0FD3: 0A18  MOV KR[4..7],R5
0FD4: 0CDB  B=0 MAEX
0FD5: 00C0  TST fA[12]
0FD6: 1804  JC 0FD8
0FD7: 0022  CLR fA[2]
0FD8: 0CCC  C=A-CON MAEX
0FD9: 1014  JNC 0FE3
0FDA: 0CC8  A=A-CON MAEX
0FDB: 00C0  TST fA[12]
0FDC: 00B0  TST fA[11]
0FDD: 1804  JC 0FDF
0FDE: 0023  TOG fA[2]
0FDF: 0CCC  C=A-CON MAEX
0FE0: 1825  JC 0FCE
0FE1: 0CD2  A<>B MAEX
0FE2: 0CC0  A=A+CON MAEX
0FE3: 0C8C  C=A-B MAEX
0FE4: 0CD8  A=0 MAEX
0FE5: 1EA7  JC 0C92
; CLEAR_MEM end (11D5 / 11E0): display X.
; Δ [REORG] 0FE6–0FE9 is TI-59 0A6D–0A70 (reached there through the relay
; 0E2A); 0FEA–0FF3 is the LRN routing of If flg / Dsz moved from TI-59
; 0CE8–0CF1 (from 0CB6; LRN key sweep: only If flg and Dsz pass here).
0FE6: 005A  CLR fB[5]         ; end of CP / CMs
0FE7: 01D7  A<>E ALL
0FE8: 0091  SET fA[9]
0FE9: 1FD3  JC 0C00           ; → 0C00 → 0938: display X
0FEA: 0A65  TST KR[6]         ; LRN, If flg / Dsz (0CB6): KR[6] …
0FEB: 0A55  TST KR[5]         ; … or KR[5] set?
0FEC: 1629  JNC 0CD8          ; yes → KEY_ENCODE and store (0CD8)
0FED: 0A0D  SWAP KR,SR        ; no: suspended continuation …
0FEE: 0A0C  MOV KR,EXT[4..15]
0FEF: 00F5  SET KR[15]
0FF0: 00D5  SET KR[13]
0FF1: 00C5  SET KR[12]
0FF2: 0A0D  SWAP KR,SR        ; … SR := 0xB000 (bank 0x0B00)
0FF3: 1F45  JC 0C51           ; → 0C51 → 09CA
; SELFTEST_RELAYS — targets of the self-test table 0C04–0C0A (sequencer
; 0DB7): test 4 0FFA → 138D, test 5 0FF5 (A := 8 in nibbles 3 and 0) → 138F,
; test 6 0FFB → 138E, test 8 0FFC → 1360, test 10 0FFD → 1375. Test 9 enters
; at 0FF4: A=-1 DPT1 borrows, COND stays clear through 0FF5–0FF7, so 0FF8
; falls through and 0FF9 takes 1368. Tests 4, 5, 8, 9 exercise SCOM
; (STOF/RCLF), 6 and 10 the RAM (MEMWR/MEMRD). Trace-confirmed (self-test
; run, KN line held at row 8, printer: "1" … "11").
; Δ [ENH] TI-59 0FF4–0FFF: the data-register RAM.OP write (now 0DFE–0E04).
; The self-test is TI-58C only.
0FF4: 03D8  A=-1 DPT1         ; test 9: borrow → COND clear
0FF5: 0A87  MOV R5,#8         ; test 5 enters here
0FF6: 09F0  A=R5 MANT
0FF7: 02F0  A=R5 DPT
0FF8: 1F2E  JC 138F           ; test 5 → 138F
0FF9: 16DE  JNC 1368          ; test 9 → 1368
0FFA: 1F26  JC 138D           ; test 4
0FFB: 1F26  JC 138E           ; test 6 (RAM)
0FFC: 1EC8  JC 1360           ; test 8
0FFD: 1EF0  JC 1375           ; test 10 (RAM)
0FFE: 1E6C  JC 1334           ; relay: return-stack push (0D33) → 1334
0FFF: 1E66  JC 1332           ; relay: print / partition sequence (0D11) → 1332 → 165A
; ═══════════════════════════════════════════════════════════════════════════
; PRINT MNEMONIC TABLE  (0x1000–0x113D) — trace-confirmed on the TI-58C with
; List (LBL A, STO 12, SIN, +, GO* 03, OP* 04). Each program keycode has
; three consecutive slots at 0x1000 + 32·tens + 3·units, one per character
; of its 3-character printer mnemonic, rightmost character first (the PC-100
; buffer fills right to left). A slot jumps into the INC KR slide at
; 0x1390–0x13DC, entering at a depth equal to the 6-bit printer character
; code (KR[4..9]); the slide's tails add 16/32/48 via KR[8]/KR[9] and end in
; PRT.OUT at 13B3. The two words after each 30-slot row (xx1E/xx1F) and
; 113E–1154 are ordinary code. Character codes follow the PC-100 set
; (Core/TMC0501.cpp PRN_CODE).
; Δ [REORG] All 300 slots as on the TI-59 (each target 9 words lower, the
; slide moved); the free words xx1E/xx1F serve other callers (see there).
; ═══════════════════════════════════════════════════════════════════════════
1000: 1F3E  JC 139F           ; keycode 00 " 0 ": right char ' ' (code 0)
1001: 1F3A  JC 139E           ; keycode 00 " 0 ": middle char '0' (code 1)
1002: 1F3A  JC 139F           ; keycode 00 " 0 ": left char ' ' (code 0)
1003: 1F38  JC 139F           ; keycode 01 " 1 ": right char ' ' (code 0)
1004: 1F32  JC 139D           ; keycode 01 " 1 ": middle char '1' (code 2)
1005: 1F34  JC 139F           ; keycode 01 " 1 ": left char ' ' (code 0)
1006: 1F32  JC 139F           ; keycode 02 " 2 ": right char ' ' (code 0)
1007: 1F2A  JC 139C           ; keycode 02 " 2 ": middle char '2' (code 3)
1008: 1F2E  JC 139F           ; keycode 02 " 2 ": left char ' ' (code 0)
1009: 1F2C  JC 139F           ; keycode 03 " 3 ": right char ' ' (code 0)
100A: 1F22  JC 139B           ; keycode 03 " 3 ": middle char '3' (code 4)
100B: 1F28  JC 139F           ; keycode 03 " 3 ": left char ' ' (code 0)
100C: 1F26  JC 139F           ; keycode 04 " 4 ": right char ' ' (code 0)
100D: 1F1A  JC 139A           ; keycode 04 " 4 ": middle char '4' (code 5)
100E: 1F22  JC 139F           ; keycode 04 " 4 ": left char ' ' (code 0)
100F: 1F20  JC 139F           ; keycode 05 " 5 ": right char ' ' (code 0)
1010: 1F12  JC 1399           ; keycode 05 " 5 ": middle char '5' (code 6)
1011: 1F1C  JC 139F           ; keycode 05 " 5 ": left char ' ' (code 0)
1012: 1F1A  JC 139F           ; keycode 06 " 6 ": right char ' ' (code 0)
1013: 1F0A  JC 1398           ; keycode 06 " 6 ": middle char '6' (code 7)
1014: 1F16  JC 139F           ; keycode 06 " 6 ": left char ' ' (code 0)
1015: 1F14  JC 139F           ; keycode 07 " 7 ": right char ' ' (code 0)
1016: 1F02  JC 1397           ; keycode 07 " 7 ": middle char '7' (code 8)
1017: 1F10  JC 139F           ; keycode 07 " 7 ": left char ' ' (code 0)
1018: 1F0E  JC 139F           ; keycode 08 " 8 ": right char ' ' (code 0)
1019: 1EFA  JC 1396           ; keycode 08 " 8 ": middle char '8' (code 9)
101A: 1F0A  JC 139F           ; keycode 08 " 8 ": left char ' ' (code 0)
101B: 1F08  JC 139F           ; keycode 09 " 9 ": right char ' ' (code 0)
101C: 1EF2  JC 1395           ; keycode 09 " 9 ": middle char '9' (code 10)
101D: 1F04  JC 139F           ; keycode 09 " 9 ": left char ' ' (code 0)
; Δ [REORG] TI-59 101E/101F: relays Pgm (0D25 → 12E1) and 1263 → 0D7B. Here
; the LRN Ind merge entry for Op Ind (TI-59 113E/113F).
101E: 0A47  MOV R5,#4         ; LRN Ind merge (0D6C): Op Ind → 84
101F: 1A40  JC 113F           ; → 113F
1020: 1EFE  JC 139F           ; keycode 10 "E' ": right char ' ' (code 0)
1021: 1F6A  JC 13D6           ; keycode 10 "E' ": middle char ''' (code 53)
1022: 1EDC  JC 1390           ; keycode 10 "E' ": left char 'E' (code 15)
1023: 1EF8  JC 139F           ; keycode 11 " A ": right char ' ' (code 0)
1024: 1EE0  JC 1394           ; keycode 11 " A ": middle char 'A' (code 11)
1025: 1EF4  JC 139F           ; keycode 11 " A ": left char ' ' (code 0)
1026: 1EF2  JC 139F           ; keycode 12 " B ": right char ' ' (code 0)
1027: 1ED8  JC 1393           ; keycode 12 " B ": middle char 'B' (code 12)
1028: 1EEE  JC 139F           ; keycode 12 " B ": left char ' ' (code 0)
1029: 1EEC  JC 139F           ; keycode 13 " C ": right char ' ' (code 0)
102A: 1ED0  JC 1392           ; keycode 13 " C ": middle char 'C' (code 13)
102B: 1EE8  JC 139F           ; keycode 13 " C ": left char ' ' (code 0)
102C: 1EE6  JC 139F           ; keycode 14 " D ": right char ' ' (code 0)
102D: 1EC8  JC 1391           ; keycode 14 " D ": middle char 'D' (code 14)
102E: 1EE2  JC 139F           ; keycode 14 " D ": left char ' ' (code 0)
102F: 1EE0  JC 139F           ; keycode 15 " E ": right char ' ' (code 0)
1030: 1EC0  JC 1390           ; keycode 15 " E ": middle char 'E' (code 15)
1031: 1EDC  JC 139F           ; keycode 15 " E ": left char ' ' (code 0)
1032: 1EDA  JC 139F           ; keycode 16 "A' ": right char ' ' (code 0)
1033: 1F46  JC 13D6           ; keycode 16 "A' ": middle char ''' (code 53)
1034: 1EC0  JC 1394           ; keycode 16 "A' ": left char 'A' (code 11)
1035: 1ED4  JC 139F           ; keycode 17 "B' ": right char ' ' (code 0)
1036: 1F40  JC 13D6           ; keycode 17 "B' ": middle char ''' (code 53)
1037: 1EB8  JC 1393           ; keycode 17 "B' ": left char 'B' (code 12)
1038: 1ECE  JC 139F           ; keycode 18 "C' ": right char ' ' (code 0)
1039: 1F3A  JC 13D6           ; keycode 18 "C' ": middle char ''' (code 53)
103A: 1EB0  JC 1392           ; keycode 18 "C' ": left char 'C' (code 13)
103B: 1EC8  JC 139F           ; keycode 19 "D' ": right char ' ' (code 0)
103C: 1F34  JC 13D6           ; keycode 19 "D' ": middle char ''' (code 53)
103D: 1EA8  JC 1391           ; keycode 19 "D' ": left char 'D' (code 14)
; Δ [REORG] TI-59 103E/103F: scanner, library-program branch (0E9D → 138C;
; now 11FE/11FF). Here two new relays.
103E: 1D48  JC 12E2           ; relay: HIR (compact keycode 82, 0CBC) → 12E2 (HIR decode)
103F: 1D7E  JC 12FE           ; relay: INV List (0D0D) → 12FE
1040: 1EC8  JC 13A4           ; keycode 20 "CLR": right char 'R' (code 29)
1041: 1ED2  JC 13AA           ; keycode 20 "CLR": middle char 'L' (code 23)
1042: 1EA0  JC 1392           ; keycode 20 "CLR": left char 'C' (code 13)
1043: 1E9C  JC 1391           ; keycode 21 "2ND": right char 'D' (code 14)
1044: 1EC8  JC 13A8           ; keycode 21 "2ND": middle char 'N' (code 25)
1045: 1EAE  JC 139C           ; keycode 21 "2ND": left char '2' (code 3)
1046: 1EF6  JC 13C1           ; keycode 22 "INV": right char 'V' (code 34)
1047: 1EC2  JC 13A8           ; keycode 22 "INV": middle char 'N' (code 25)
1048: 1ECA  JC 13AD           ; keycode 22 "INV": left char 'I' (code 20)
1049: 1EEC  JC 13BF           ; keycode 23 "LNX": right char 'X' (code 36)
104A: 1EBC  JC 13A8           ; keycode 23 "LNX": middle char 'N' (code 25)
104B: 1EBE  JC 13AA           ; keycode 23 "LNX": left char 'L' (code 23)
104C: 1EA6  JC 139F           ; keycode 24 "CE ": right char ' ' (code 0)
104D: 1E86  JC 1390           ; keycode 24 "CE ": middle char 'E' (code 15)
104E: 1E88  JC 1392           ; keycode 24 "CE ": left char 'C' (code 13)
104F: 1EAA  JC 13A4           ; keycode 25 "CLR": right char 'R' (code 29)
1050: 1EB4  JC 13AA           ; keycode 25 "CLR": middle char 'L' (code 23)
1051: 1E82  JC 1392           ; keycode 25 "CLR": left char 'C' (code 13)
1052: 1E7E  JC 1391           ; keycode 26 "2ND": right char 'D' (code 14)
1053: 1EAA  JC 13A8           ; keycode 26 "2ND": middle char 'N' (code 25)
1054: 1E90  JC 139C           ; keycode 26 "2ND": left char '2' (code 3)
1055: 1ED8  JC 13C1           ; keycode 27 "INV": right char 'V' (code 34)
1056: 1EA4  JC 13A8           ; keycode 27 "INV": middle char 'N' (code 25)
1057: 1EAC  JC 13AD           ; keycode 27 "INV": left char 'I' (code 20)
1058: 1EAE  JC 13AF           ; keycode 28 "LOG": right char 'G' (code 18)
1059: 1E9C  JC 13A7           ; keycode 28 "LOG": middle char 'O' (code 26)
105A: 1EA0  JC 13AA           ; keycode 28 "LOG": left char 'L' (code 23)
105B: 1E88  JC 139F           ; keycode 29 "CP ": right char ' ' (code 0)
105C: 1E94  JC 13A6           ; keycode 29 "CP ": middle char 'P' (code 27)
105D: 1E6A  JC 1392           ; keycode 29 "CP ": left char 'C' (code 13)
105E: 169D  JNC 0D10
; Δ [REORG] TI-59 105F: relay of the print / card sequence (0D27 → 1333; now
; 0FFF). Here the Pgm relay (TI-59 101E).
105F: 1F6E  JC 1416           ; relay: Pgm (0D0F) → 1416 → PGM_SELECT (173B)
1060: 1E90  JC 13A8           ; keycode 30 "TAN": right char 'N' (code 25)
1061: 1E66  JC 1394           ; keycode 30 "TAN": middle char 'A' (code 11)
1062: 1E80  JC 13A2           ; keycode 30 "TAN": left char 'T' (code 31)
1063: 1E8A  JC 13A8           ; keycode 31 "LRN": right char 'N' (code 25)
1064: 1E80  JC 13A4           ; keycode 31 "LRN": middle char 'R' (code 29)
1065: 1E8A  JC 13AA           ; keycode 31 "LRN": left char 'L' (code 23)
1066: 1E78  JC 13A2           ; keycode 32 "X⇄T": right char 'T' (code 31)
1067: 1EE4  JC 13D9           ; keycode 32 "X⇄T": middle char '⇄' (code 50)
1068: 1EAE  JC 13BF           ; keycode 32 "X⇄T": left char 'X' (code 36)
1069: 1E6C  JC 139F           ; keycode 33 "X² ": right char ' ' (code 0)
106A: 1ED2  JC 13D3           ; keycode 33 "X² ": middle char '²' (code 56)
106B: 1EA8  JC 13BF           ; keycode 33 "X² ": left char 'X' (code 36)
106C: 1E66  JC 139F           ; keycode 34 "√X ": right char ' ' (code 0)
106D: 1EA4  JC 13BF           ; keycode 34 "√X ": middle char 'X' (code 36)
106E: 1E96  JC 13B9           ; keycode 34 "√X ": left char '√' (code 42)
106F: 1EA0  JC 13BF           ; keycode 35 "1/X": right char 'X' (code 36)
1070: 1ED0  JC 13D8           ; keycode 35 "1/X": middle char '/' (code 51)
1071: 1E58  JC 139D           ; keycode 35 "1/X": left char '1' (code 2)
1072: 1E6E  JC 13A9           ; keycode 36 "PGM": right char 'M' (code 24)
1073: 1E78  JC 13AF           ; keycode 36 "PGM": middle char 'G' (code 18)
1074: 1E64  JC 13A6           ; keycode 36 "PGM": left char 'P' (code 27)
1075: 1E5E  JC 13A4           ; keycode 37 "P/R": right char 'R' (code 29)
1076: 1EC4  JC 13D8           ; keycode 37 "P/R": middle char '/' (code 51)
1077: 1E5E  JC 13A6           ; keycode 37 "P/R": left char 'P' (code 27)
1078: 1E60  JC 13A8           ; keycode 38 "SIN": right char 'N' (code 25)
1079: 1E68  JC 13AD           ; keycode 38 "SIN": middle char 'I' (code 20)
107A: 1E52  JC 13A3           ; keycode 38 "SIN": left char 'S' (code 30)
107B: 1E50  JC 13A3           ; keycode 39 "COS": right char 'S' (code 30)
107C: 1E56  JC 13A7           ; keycode 39 "COS": middle char 'O' (code 26)
107D: 1E2A  JC 1392           ; keycode 39 "COS": left char 'C' (code 13)
107E: 16BE  JNC 13DD
107F: 1701  JNC 0CFF
1080: 1E22  JC 1391           ; keycode 40 "IND": right char 'D' (code 14)
1081: 1E4E  JC 13A8           ; keycode 40 "IND": middle char 'N' (code 25)
1082: 1E56  JC 13AD           ; keycode 40 "IND": left char 'I' (code 20)
1083: 1E3E  JC 13A2           ; keycode 41 "SST": right char 'T' (code 31)
1084: 1E3E  JC 13A3           ; keycode 41 "SST": middle char 'S' (code 30)
1085: 1E3C  JC 13A3           ; keycode 41 "SST": left char 'S' (code 30)
1086: 1E42  JC 13A7           ; keycode 42 "STO": right char 'O' (code 26)
1087: 1E36  JC 13A2           ; keycode 42 "STO": middle char 'T' (code 31)
1088: 1E36  JC 13A3           ; keycode 42 "STO": left char 'S' (code 30)
1089: 1E42  JC 13AA           ; keycode 43 "RCL": right char 'L' (code 23)
108A: 1E10  JC 1392           ; keycode 43 "RCL": middle char 'C' (code 13)
108B: 1E32  JC 13A4           ; keycode 43 "RCL": left char 'R' (code 29)
108C: 1E3A  JC 13A9           ; keycode 44 "SUM": right char 'M' (code 24)
108D: 1E6A  JC 13C2           ; keycode 44 "SUM": middle char 'U' (code 33)
108E: 1E2A  JC 13A3           ; keycode 44 "SUM": left char 'S' (code 30)
108F: 1E20  JC 139F           ; keycode 45 "Yˣ ": right char ' ' (code 0)
1090: 1E8A  JC 13D5           ; keycode 45 "Yˣ ": middle char 'ˣ' (code 54)
1091: 1E5A  JC 13BE           ; keycode 45 "Yˣ ": left char 'Y' (code 37)
1092: 1E22  JC 13A3           ; keycode 46 "INS": right char 'S' (code 30)
1093: 1E2A  JC 13A8           ; keycode 46 "INS": middle char 'N' (code 25)
1094: 1E32  JC 13AD           ; keycode 46 "INS": left char 'I' (code 20)
1095: 1E1C  JC 13A3           ; keycode 47 "CMS": right char 'S' (code 30)
1096: 1E26  JC 13A9           ; keycode 47 "CMS": middle char 'M' (code 24)
1097: 1DF6  JC 1392           ; keycode 47 "CMS": left char 'C' (code 13)
1098: 1DF4  JC 1392           ; keycode 48 "EXC": right char 'C' (code 13)
1099: 1E4C  JC 13BF           ; keycode 48 "EXC": middle char 'X' (code 36)
109A: 1DEC  JC 1390           ; keycode 48 "EXC": left char 'E' (code 15)
109B: 1DEC  JC 1391           ; keycode 49 "PRD": right char 'D' (code 14)
109C: 1E10  JC 13A4           ; keycode 49 "PRD": middle char 'R' (code 29)
109D: 1E12  JC 13A6           ; keycode 49 "PRD": left char 'P' (code 27)
109E: 0910  A=B MANT
109F: 1C24  JC 12B1
10A0: 1E1A  JC 13AD           ; keycode 50 "IxI": right char 'I' (code 20)
10A1: 1E34  JC 13BB           ; keycode 50 "IxI": middle char 'x' (code 40)
10A2: 1E16  JC 13AD           ; keycode 50 "IxI": left char 'I' (code 20)
10A3: 1DFE  JC 13A2           ; keycode 51 "BST": right char 'T' (code 31)
10A4: 1DFE  JC 13A3           ; keycode 51 "BST": middle char 'S' (code 30)
10A5: 1DDC  JC 1393           ; keycode 51 "BST": left char 'B' (code 12)
10A6: 1DF2  JC 139F           ; keycode 52 "EE ": right char ' ' (code 0)
10A7: 1DD2  JC 1390           ; keycode 52 "EE ": middle char 'E' (code 15)
10A8: 1DD0  JC 1390           ; keycode 52 "EE ": left char 'E' (code 15)
10A9: 1DEC  JC 139F           ; keycode 53 " ( ": right char ' ' (code 0)
10AA: 1E18  JC 13B6           ; keycode 53 " ( ": middle char '(' (code 45)
10AB: 1DE8  JC 139F           ; keycode 53 " ( ": left char ' ' (code 0)
10AC: 1DE6  JC 139F           ; keycode 54 " ) ": right char ' ' (code 0)
10AD: 1E10  JC 13B5           ; keycode 54 " ) ": middle char ')' (code 46)
10AE: 1DE2  JC 139F           ; keycode 54 " ) ": left char ' ' (code 0)
10AF: 1DE0  JC 139F           ; keycode 55 " ÷ ": right char ' ' (code 0)
10B0: 1E42  JC 13D1           ; keycode 55 " ÷ ": middle char '÷' (code 58)
10B1: 1DDC  JC 139F           ; keycode 55 " ÷ ": left char ' ' (code 0)
10B2: 1DF0  JC 13AA           ; keycode 56 "DEL": right char 'L' (code 23)
10B3: 1DBA  JC 1390           ; keycode 56 "DEL": middle char 'E' (code 15)
10B4: 1DBA  JC 1391           ; keycode 56 "DEL": left char 'D' (code 14)
10B5: 1DF4  JC 13AF           ; keycode 57 "ENG": right char 'G' (code 18)
10B6: 1DE4  JC 13A8           ; keycode 57 "ENG": middle char 'N' (code 25)
10B7: 1DB2  JC 1390           ; keycode 57 "ENG": left char 'E' (code 15)
10B8: 1E0E  JC 13BF           ; keycode 58 "FIX": right char 'X' (code 36)
10B9: 1DE8  JC 13AD           ; keycode 58 "FIX": middle char 'I' (code 20)
10BA: 1DEC  JC 13B0           ; keycode 58 "FIX": left char 'F' (code 17)
10BB: 1DCE  JC 13A2           ; keycode 59 "INT": right char 'T' (code 31)
10BC: 1DD8  JC 13A8           ; keycode 59 "INT": middle char 'N' (code 25)
10BD: 1DE0  JC 13AD           ; keycode 59 "INT": left char 'I' (code 20)
; Δ [ENH] TI-59 10BE/10BF: library scanner path (D=SRD ALL, JC 0F4B; now
; 1284 → 0F79). Here the self-test result relays.
10BE: 15D1  JNC 0DD6          ; self-test failed (136F, 1389) → 0DD6 → 09DD
10BF: 15F9  JNC 0DC3          ; self-test passed (1374, 138C) → 0DC3: next test
10C0: 1DDE  JC 13AF           ; keycode 60 "DEG": right char 'G' (code 18)
10C1: 1D9E  JC 1390           ; keycode 60 "DEG": middle char 'E' (code 15)
10C2: 1D9E  JC 1391           ; keycode 60 "DEG": left char 'D' (code 14)
10C3: 1DC8  JC 13A7           ; keycode 61 "GTO": right char 'O' (code 26)
10C4: 1DBC  JC 13A2           ; keycode 61 "GTO": middle char 'T' (code 31)
10C5: 1DD4  JC 13AF           ; keycode 61 "GTO": left char 'G' (code 18)
10C6: 1DE8  JC 13BA           ; keycode 62 "PG*": right char '*' (code 41)
10C7: 1DD0  JC 13AF           ; keycode 62 "PG*": middle char 'G' (code 18)
10C8: 1DBC  JC 13A6           ; keycode 62 "PG*": left char 'P' (code 27)
10C9: 1DE2  JC 13BA           ; keycode 63 "EX*": right char '*' (code 41)
10CA: 1DEA  JC 13BF           ; keycode 63 "EX*": middle char 'X' (code 36)
10CB: 1D8A  JC 1390           ; keycode 63 "EX*": left char 'E' (code 15)
10CC: 1DDC  JC 13BA           ; keycode 64 "PD*": right char '*' (code 41)
10CD: 1D88  JC 1391           ; keycode 64 "PD*": middle char 'D' (code 14)
10CE: 1DB0  JC 13A6           ; keycode 64 "PD*": left char 'P' (code 27)
10CF: 1DA0  JC 139F           ; keycode 65 " x ": right char ' ' (code 0)
10D0: 1DD6  JC 13BB           ; keycode 65 " x ": middle char 'x' (code 40)
10D1: 1D9C  JC 139F           ; keycode 65 " x ": left char ' ' (code 0)
10D2: 1DE0  JC 13C2           ; keycode 66 "PAU": right char 'U' (code 33)
10D3: 1D82  JC 1394           ; keycode 66 "PAU": middle char 'A' (code 11)
10D4: 1DA4  JC 13A6           ; keycode 66 "PAU": left char 'P' (code 27)
10D5: 1DA0  JC 13A5           ; keycode 67 " EQ": right char 'Q' (code 28)
10D6: 1D74  JC 1390           ; keycode 67 " EQ": middle char 'E' (code 15)
10D7: 1D90  JC 139F           ; keycode 67 " EQ": left char ' ' (code 0)
10D8: 1D9C  JC 13A6           ; keycode 68 "NOP": right char 'P' (code 27)
10D9: 1D9C  JC 13A7           ; keycode 68 "NOP": middle char 'O' (code 26)
10DA: 1D9C  JC 13A8           ; keycode 68 "NOP": left char 'N' (code 25)
10DB: 1D88  JC 139F           ; keycode 69 "OP ": right char ' ' (code 0)
10DC: 1D94  JC 13A6           ; keycode 69 "OP ": middle char 'P' (code 27)
10DD: 1D94  JC 13A7           ; keycode 69 "OP ": left char 'O' (code 26)
10DE: 017E  D=SRD ALL
10DF: 1F5B  JC 0D32
10E0: 1D62  JC 1391           ; keycode 70 "RAD": right char 'D' (code 14)
10E1: 1D66  JC 1394           ; keycode 70 "RAD": middle char 'A' (code 11)
10E2: 1D84  JC 13A4           ; keycode 70 "RAD": left char 'R' (code 29)
10E3: 1D82  JC 13A4           ; keycode 71 "SBR": right char 'R' (code 29)
10E4: 1D5E  JC 1393           ; keycode 71 "SBR": middle char 'B' (code 12)
10E5: 1D7C  JC 13A3           ; keycode 71 "SBR": left char 'S' (code 30)
10E6: 1DA8  JC 13BA           ; keycode 72 "ST*": right char '*' (code 41)
10E7: 1D76  JC 13A2           ; keycode 72 "ST*": middle char 'T' (code 31)
10E8: 1D76  JC 13A3           ; keycode 72 "ST*": left char 'S' (code 30)
10E9: 1DA2  JC 13BA           ; keycode 73 "RC*": right char '*' (code 41)
10EA: 1D50  JC 1392           ; keycode 73 "RC*": middle char 'C' (code 13)
10EB: 1D72  JC 13A4           ; keycode 73 "RC*": left char 'R' (code 29)
10EC: 1D9C  JC 13BA           ; keycode 74 "SM*": right char '*' (code 41)
10ED: 1D78  JC 13A9           ; keycode 74 "SM*": middle char 'M' (code 24)
10EE: 1D6A  JC 13A3           ; keycode 74 "SM*": left char 'S' (code 30)
10EF: 1D60  JC 139F           ; keycode 75 " - ": right char ' ' (code 0)
10F0: 1D82  JC 13B1           ; keycode 75 " - ": middle char '-' (code 16)
10F1: 1D5C  JC 139F           ; keycode 75 " - ": left char ' ' (code 0)
10F2: 1D70  JC 13AA           ; keycode 76 "LBL": right char 'L' (code 23)
10F3: 1D40  JC 1393           ; keycode 76 "LBL": middle char 'B' (code 12)
10F4: 1D6C  JC 13AA           ; keycode 76 "LBL": left char 'L' (code 23)
10F5: 1D36  JC 1390           ; keycode 77 " GE": right char 'E' (code 15)
10F6: 1D72  JC 13AF           ; keycode 77 " GE": middle char 'G' (code 18)
10F7: 1D50  JC 139F           ; keycode 77 " GE": left char ' ' (code 0)
10F8: 1D4E  JC 139F           ; keycode 78 "∑+ ": right char ' ' (code 0)
10F9: 1D86  JC 13BC           ; keycode 78 "∑+ ": middle char '+' (code 39)
10FA: 1DAA  JC 13CF           ; keycode 78 "∑+ ": left char '∑' (code 63)
10FB: 1D48  JC 139F           ; keycode 79 " x̄ ": right char ' ' (code 0)
10FC: 1DB0  JC 13D4           ; keycode 79 " x̄ ": middle char 'x̄' (code 55)
10FD: 1D44  JC 139F           ; keycode 79 " x̄ ": left char ' ' (code 0)
; Δ [REORG] 10FE/10FF and 111E/111F swapped roles with the TI-59 (there
; 10FE/10FF = A<>E → 0ED3, 111E/111F = next step).
10FE: 0100  A=A ALL           ; next step (from 1161, 1265, 12C2, 1318) …
10FF: 1FD7  JC 0D14           ; … → 0D14
1100: 1D22  JC 1391           ; keycode 80 "GRD": right char 'D' (code 14)
1101: 1D46  JC 13A4           ; keycode 80 "GRD": middle char 'R' (code 29)
1102: 1D5A  JC 13AF           ; keycode 80 "GRD": left char 'G' (code 18)
1103: 1D3E  JC 13A2           ; keycode 81 "RST": right char 'T' (code 31)
1104: 1D3E  JC 13A3           ; keycode 81 "RST": middle char 'S' (code 30)
1105: 1D3E  JC 13A4           ; keycode 81 "RST": left char 'R' (code 29)
1106: 1D3C  JC 13A4           ; keycode 82 "HIR": right char 'R' (code 29)
1107: 1D4C  JC 13AD           ; keycode 82 "HIR": middle char 'I' (code 20)
1108: 1D4C  JC 13AE           ; keycode 82 "HIR": left char 'H' (code 19)
1109: 1D62  JC 13BA           ; keycode 83 "GO*": right char '*' (code 41)
110A: 1D3A  JC 13A7           ; keycode 83 "GO*": middle char 'O' (code 26)
110B: 1D48  JC 13AF           ; keycode 83 "GO*": left char 'G' (code 18)
110C: 1D5C  JC 13BA           ; keycode 84 "OP*": right char '*' (code 41)
110D: 1D32  JC 13A6           ; keycode 84 "OP*": middle char 'P' (code 27)
110E: 1D32  JC 13A7           ; keycode 84 "OP*": left char 'O' (code 26)
110F: 1D20  JC 139F           ; keycode 85 " + ": right char ' ' (code 0)
1110: 1D58  JC 13BC           ; keycode 85 " + ": middle char '+' (code 39)
1111: 1D1C  JC 139F           ; keycode 85 " + ": left char ' ' (code 0)
1112: 1D3C  JC 13B0           ; keycode 86 "STF": right char 'F' (code 17)
1113: 1D1E  JC 13A2           ; keycode 86 "STF": middle char 'T' (code 31)
1114: 1D1E  JC 13A3           ; keycode 86 "STF": left char 'S' (code 30)
1115: 1D36  JC 13B0           ; keycode 87 "IFF": right char 'F' (code 17)
1116: 1D34  JC 13B0           ; keycode 87 "IFF": middle char 'F' (code 17)
1117: 1D2C  JC 13AD           ; keycode 87 "IFF": left char 'I' (code 20)
1118: 1D16  JC 13A3           ; keycode 88 "DMS": right char 'S' (code 30)
1119: 1D20  JC 13A9           ; keycode 88 "DMS": middle char 'M' (code 24)
111A: 1CEE  JC 1391           ; keycode 88 "DMS": left char 'D' (code 14)
111B: 1D08  JC 139F           ; keycode 89 " π ": right char ' ' (code 0)
111C: 1D38  JC 13B8           ; keycode 89 " π ": middle char 'π' (code 43)
111D: 1D04  JC 139F           ; keycode 89 " π ": left char ' ' (code 0)
111E: 01D7  A<>E ALL          ; from 13E2 …
111F: 1C9B  JC 0ED2           ; … → 0ED2
1120: 1D04  JC 13A2           ; keycode 90 "LST": right char 'T' (code 31)
1121: 1D04  JC 13A3           ; keycode 90 "LST": middle char 'S' (code 30)
1122: 1D10  JC 13AA           ; keycode 90 "LST": left char 'L' (code 23)
1123: 1D00  JC 13A3           ; keycode 91 "R/S": right char 'S' (code 30)
1124: 1D68  JC 13D8           ; keycode 91 "R/S": middle char '/' (code 51)
1125: 1CFE  JC 13A4           ; keycode 91 "R/S": left char 'R' (code 29)
1126: 1D04  JC 13A8           ; keycode 92 "RTN": right char 'N' (code 25)
1127: 1CF6  JC 13A2           ; keycode 92 "RTN": middle char 'T' (code 31)
1128: 1CF8  JC 13A4           ; keycode 92 "RTN": left char 'R' (code 29)
1129: 1CEC  JC 139F           ; keycode 93 " . ": right char ' ' (code 0)
112A: 1D32  JC 13C3           ; keycode 93 " . ": middle char '.' (code 32)
112B: 1CE8  JC 139F           ; keycode 93 " . ": left char ' ' (code 0)
112C: 1D0A  JC 13B1           ; keycode 94 "+/-": right char '-' (code 16)
112D: 1D56  JC 13D8           ; keycode 94 "+/-": middle char '/' (code 51)
112E: 1D1C  JC 13BC           ; keycode 94 "+/-": left char '+' (code 39)
112F: 1CE0  JC 139F           ; keycode 95 " = ": right char ' ' (code 0)
1130: 1D4E  JC 13D7           ; keycode 95 " = ": middle char '=' (code 52)
1131: 1CDC  JC 139F           ; keycode 95 " = ": left char ' ' (code 0)
1132: 1CE0  JC 13A2           ; keycode 96 "WRT": right char 'T' (code 31)
1133: 1CE2  JC 13A4           ; keycode 96 "WRT": middle char 'R' (code 29)
1134: 1D18  JC 13C0           ; keycode 96 "WRT": left char 'W' (code 35)
1135: 1D10  JC 13BD           ; keycode 97 "DSZ": right char 'Z' (code 38)
1136: 1CDA  JC 13A3           ; keycode 97 "DSZ": middle char 'S' (code 30)
1137: 1CB4  JC 1391           ; keycode 97 "DSZ": left char 'D' (code 14)
1138: 1D12  JC 13C1           ; keycode 98 "ADV": right char 'V' (code 34)
1139: 1CB0  JC 1391           ; keycode 98 "ADV": middle char 'D' (code 14)
113A: 1CB4  JC 1394           ; keycode 98 "ADV": left char 'A' (code 11)
113B: 1CCE  JC 13A2           ; keycode 99 "PRT": right char 'T' (code 31)
113C: 1CD0  JC 13A4           ; keycode 99 "PRT": middle char 'R' (code 29)
113D: 1CD2  JC 13A6           ; keycode 99 "PRT": left char 'P' (code 27)
; Δ [REORG] TI-59 113E/113F (Op Ind → 84) moved to 101E/101F; the GTO Ind
; entry starts here.
113E: 0A37  MOV R5,#3         ; GTO Ind → 83
113F: 02F6  D=R5 DPT
1140: 0A87  MOV R5,#8
1141: 1F99  JC 0D75
1142: 00A2  CLR fA[10]        ; INV List done: clear the listing mark (SCOM[9] nibble 15) …
1143: 0091  SET fA[9]
1144: 0A97  MOV R5,#9
1145: 02F6  D=R5 DPT
1146: 0131  IO=D ALL
1147: 0A1F  RCLF
1148: 01D0  A=LOAD ALL
1149: 0E08  A=A-1 MMSD1
114A: 0131  IO=D ALL
114B: 0A0F  STOF
114C: 0101  IO=A ALL
114D: 01D7  A<>E ALL          ; … and restore X
114E: 0051  SET fA[5]
114F: 1F55  JC 0DA5
1150: 0051  SET fA[5]
1151: 0131  IO=D ALL
1152: 0A1F  RCLF
1153: 01D0  A=LOAD ALL
1154: 1F5D  JC 0DA6
; Keycode replace (LRN_STORE, from 0DA2 after the MEMRD at 0D9E): shift the
; register image right by the byte position (115B–115F), cache it in
; SCOM[10] (1467–146B), isolate the old keycode and shift it back into place
; (146B–1477), subtract it from the register (15F8), shift the new keycode
; into place (15FC–1602) and add it (1603 → 1331 → 0FCB → 0C16).
1155: 01D2  A<>B ALL          ; B := register image read from RAM
; Δ [HW] TI-59 1158–115C: A=SLA ALL, byte count in A[0] (A=R5 DPT, A=A-1
; DPT1). Here A[1..0] hold the binary RAM address: its nibble 1 moves up to
; A[3] (A[0] stays) and the byte count runs in A[1]; 0C16 moves it back.
1156: 0C40  A=SLA MAEX        ; address nibble 1 → A[3] (A[0] stays) …
1157: 0C40  A=SLA MAEX        ; …
1158: 0A08  MOV R5,KR[4..7]   ; byte position
1159: 06F0  A=R5 EXP          ; A[1] := byte position
115A: 0116  D=B ALL
115B: 0708  A=A-1 EXP1        ; byte count …
115C: 1616  JNC 1467          ; … exhausted → cache it (1467)
115D: 017E  D=SRD ALL         ; shift two nibbles per byte
115E: 017E  D=SRD ALL
115F: 1809  JC 115B
1160: 00D0  TST fA[13]        ; Op 08 label listing: skip lines that are not label names
1161: 10C7  JNC 10FE
1162: 0A0C  MOV KR,EXT[4..15]
1163: 0116  D=B ALL
1164: 1D8C  JC 142A
; Δ [REORG] new relay (no TI-59 counterpart).
1165: 16AD  JNC 0E0F          ; relay: 14EE → 0E0F → 0B1D
1166: 0A1F  RCLF
1167: 09D0  A=LOAD MANT
1168: 0509  IO=A-1 LLSD1
1169: 1655  JNC 0E3F          ; Op 09 refused: error display
116A: 0AE7  MOV R5,#14
116B: 02F3  B=R5 DPT
116C: 0111  IO=B ALL
116D: 0A1F  RCLF
116E: 02D0  A=LOAD DPT
116F: 0409  IO=A-xC DPTC
1170: 19D8  JC 125C
1171: 0CD7  A<>E MAEX
1172: 0309  IO=A-1 DPT1
1173: 04D0  A=LOAD DPTC
1174: 1E6B  JC 0E3F
; ═══════════════════════════════════════════════════════════════════════════
; RTN_POP  (0x1175–0x11AB) — return from a subroutine (keycode 92 / INV SBR).
; Trace-confirmed (Lbl A SBR B R/S Lbl B SBR C RTN Lbl C 4 RTN). Level 1 of the
; return stack (SCOM[15] nibbles 1–5: caller's Prg Src Flag, then the
; position LSD-first = register·10 + byte) is converted back into the
; SCOM[0] step format (1183–1192) and the stack shifted down (14F9 → 0DDB).
; Depth 0 (nothing pushed — the subroutine was started from the keyboard)
; ends the run instead (1195 → 0DF5 clears fB[0]).
; ═══════════════════════════════════════════════════════════════════════════
1175: 01D7  A<>E ALL
1176: 0AF7  MOV R5,#15        ; SCOM[15] …
1177: 02F4  C=R5 DPT
1178: 06F3  B=R5 EXP
1179: 0121  IO=C ALL
117A: 0A1F  RCLF
117B: 01D0  A=LOAD ALL        ; … A := return stack
117C: 0308  A=A-1 DPT1        ; depth − 1 …
117D: 1030  JNC 1195          ; … was 0 → return to the keyboard: stop
117E: 0A1F  RCLF
117F: 01D6  D=LOAD ALL        ; D := stack image (SCOM[15] again) for the shifts
1180: 0103  B=A ALL
1181: 042C  C=C-xC DPTC
1182: 0320  A=C+1 DPT1
1183: 0C40  A=SLA MAEX        ; unpack level 1's position digits …
1184: 0C40  A=SLA MAEX
1185: 097E  D=SRD MANT
1186: 0308  A=A-1 DPT1
1187: 1809  JC 1183
1188: 0C48  A=SRA MAEX        ; … into the step-counter layout (register nibbles 5–7, byte 4)
1189: 0C48  A=SRA MAEX
118A: 0976  D=SLD MANT
118B: 032C  C=C-1 DPT1
118C: 1809  JC 1188
118D: 0976  D=SLD MANT
118E: 09B6  D=A+D MANT
118F: 06F3  B=R5 EXP
1190: 06F0  A=R5 EXP
1191: 0A0F  STOF              ; SCOM[0] := return step (with the caller's Prg Src Flag)
1192: 0131  IO=D ALL
1193: 0708  A=A-1 EXP1
1194: 1ECA  JC 14F9           ; → shift the remaining levels down (0DDB)
1195: 09DE  D=0 MANT          ; empty stack: library program finished → back to the RAM page …
1196: 0A97  MOV R5,#9
1197: 02F6  D=R5 DPT
1198: 0131  IO=D ALL
1199: 0A1F  RCLF              ; … (SCOM[9] page fields)
119A: 01D0  A=LOAD ALL
119B: 0606  D=A EXP
119C: 0C48  A=SRA MAEX
119D: 0C48  A=SRA MAEX
119E: 0930  A=D MANT
119F: 0C40  A=SLA MAEX
11A0: 0C40  A=SLA MAEX
11A1: 0630  A=D EXP
11A2: 0131  IO=D ALL
11A3: 0A0F  STOF
11A4: 0101  IO=A ALL
11A5: 0611  IO=B EXP
11A6: 02F0  A=R5 DPT
11A7: 065B  B=SRB EXP
11A8: 0619  IO=-B EXP
11A9: 1769  JNC 0DF5          ; → stop the run (0DF5: CLR fB[0])
11AA: 1F9F  JC 0DDB
11AB: 1DA0  JC 147B
; Scanner: address operand after GTO / SBR / x=t / x≥t (fA[5], from 0F7E):
; a label name is one byte (a keycode ≥ 10), an absolute step number two
; bytes, the first one 00–09 = the hundreds digit (11B0–11B5); the bytes are
; skipped (126D → 12BE).
11AC: 0631  IO=D EXP
11AD: 0A18  MOV KR[4..7],R5
11AE: 0239  IO=-D DPT
11AF: 017E  D=SRD ALL
11B0: 0A75  TST KR[7]
11B1: 0A55  TST KR[5]
11B2: 0A45  TST KR[4]
11B3: 1174  JNC 126D          ; label name byte → skip one
11B4: 0A65  TST KR[6]
11B5: 1970  JC 126D
11B6: 00C8  TST fB[12]        ; two-byte step number: skip both (fA[9] set at 1273)
11B7: 1978  JC 1273
11B8: 0091  SET fA[9]         ; operand follows: skip one byte
11B9: 00CA  CLR fB[12]
11BA: 1E43  JC 0E99
; Δ [REORG] TI-59 11BB–11D7 (HIR decode, relay to 0E40) moved to 12E2–12FD
; (entered via 103E) and 11F3; HIR_STO (TI-59 11D8–11DF) follows directly.
11BB: 0059  SET fB[5]         ; HIR STO (from 12F2) / store-back
; HIR_STO: store X (C, flags from fB[1..4]) into hierarchy register SCOM[D[0]]
; (HIR 0m, and the store-back of HIR SUM/Prd). The fast-mode chain of the
; TI-59 reaches it with D[0] = 0, writing X's digit image into SCOM[0]
; (examples/fastmode.ti59). Trace-confirmed (Σ+ / x̄ on the TI-58C).
11BC: 0A16  MOV R5,fB[1..4]
11BD: 02F4  C=R5 DPT
11BE: 0131  IO=D ALL
11BF: 0A0F  STOF
11C0: 0121  IO=C ALL
11C1: 0051  SET fA[5]
11C2: 1F7F  JC 0E03           ; → 0E03 → ARITH_EXIT (0C8A)
; ═══════════════════════════════════════════════════════════════════════════
; CLEAR_MEM  (0x11C3–0x11E0, CP 0x1556–…, end 0FE6; entry 0BE6 → 0FCC) — CMs
; and CP. CMs (fA[8] clear): clear all data registers, i.e. RAM from the
; partition boundary up to the top register (count from SCOM[13],
; 11C6–11D4; none → straight to the end, 11D5). CP (fA[8] set, 1556): t
; (SCOM[11]) := 0; from the keyboard also the return stack (SCOM[15]), step
; counter / Prg Src / user flags (SCOM[0] keeps only Fix), the module
; security nibble in SCOM[9], and all PROGRAM registers (through the loop at
; 11D7); inside a running program only t. (In LRN mode CP is recorded as
; step 29.) Verified (raw RAM filled, then): CMs clears raw 30–59 (default),
; 50–59 with 1 Op 17, none with 0 Op 17; CP with 2 Op 17 clears raw 0–39;
; E000–E003 (raw 60–63) are never touched.
; Δ [HW] TI-59 0FC0–0FF3 / 1355–1363 used the RAM chips' block operation
; (RAM.OP op 4: ten registers, op 2: one). The CMOS RAM has none: 11D7–11DF
; clear one register per MEMWR — the write takes the bus during C=C−B, which
; drives no IO, so zero is written (derived; matches the emulator) — while C
; counts the raw address down (start address and count from 1570).
; ═══════════════════════════════════════════════════════════════════════════
11C3: 01D7  A<>E ALL          ; A := X …
11C4: 0080  TST fA[8]         ; CP?
11C5: 1722  JNC 1556          ; yes → CP
11C6: 0AD7  MOV R5,#13        ; CMs: data-register range from SCOM[13] (partition … top
                              ;   register)
11C7: 02F0  A=R5 DPT
11C8: 0101  IO=A ALL
11C9: 0A1F  RCLF
11CA: 09D0  A=LOAD MANT
11CB: 0948  A=SRA MANT
11CC: 0148  A=SRA ALL
11CD: 0148  A=SRA ALL
11CE: 094B  B=SRA MANT
11CF: 095B  B=SRB MANT
11D0: 09D8  A=0 MANT
11D1: 0C40  A=SLA MAEX
11D2: 0C40  A=SLA MAEX
11D3: 098B  B=A-B MANT
11D4: 02F0  A=R5 DPT
11D5: 13DF  JNC 0FE6          ; no data registers (0 Op 17) → end
11D6: 1F34  JC 1570           ; → start address and count to binary (1570), then the loop
11D7: 0A97  MOV R5,#9         ; ten registers per pass …
11D8: 06F0  A=R5 EXP
11D9: 0121  IO=C ALL          ; bus: raw RAM address (C)
11DA: 0A76  MEMWR             ; clear this register: the write takes the bus of the next word …
11DB: 019C  C=C-B ALL         ; … which drives no IO → zero; address − 1
11DC: 0708  A=A-1 EXP1        ; inner count …
11DD: 1809  JC 11D9
11DE: 0308  A=A-1 DPT1        ; … outer count (tens)
11DF: 1811  JC 11D7
11E0: 13F5  JNC 0FE6          ; done → display X (0FE6)
11E1: 1FAC  JC 15B7           ; FLAG_OP (from 0E0D)
; ── Transfer-error halt: reject a library transfer and blink ────────────────
; Error exit of the library transfer resolver (12B0) for an out-of-range
; target; LIB_LABEL_SEARCH enters at 11E3 when the label is not in the
; library program (15A4). Rewrites SCOM[0] with the Prg Src Flag nibble
; cleared (the SRB/SLB MANT pair drops nibble 3, keeping the step counter),
; resets the subroutine return stack in SCOM[15] (11EA–11ED: level slots
; cleared, caller PC in level 1, F in the depth nibble — discarding the
; return the failed SBR had pushed at 1334), sets the error flag fB[9]
; (blinking display), clears fB[0] and idles (keyboard: 11F1). The cleanup
; is minimal: the CROM PC and the SCOM[9] descriptor keep what the rejected
; launch left (the TI-59 "SBR 444" quirk, examples/texas-print.ti59).
11E2: 01D5  C<>D ALL
11E3: 0A1F  RCLF
11E4: 01D3  B=LOAD ALL
11E5: 095B  B=SRB MANT
11E6: 0953  B=SLB MANT
11E7: 0A0F  STOF
11E8: 0111  IO=B ALL
11E9: 0099  SET fB[9]
11EA: 0AF7  MOV R5,#15
11EB: 02F3  B=R5 DPT
11EC: 0111  IO=B ALL
11ED: 0A0F  STOF
11EE: 0008  TST fB[0]
11EF: 000A  CLR fB[0]
11F0: 176D  JNC 0E3A
; Δ [REORG] TI-59 15A9–15AB ("show it": CLR fB[5], CLR fA[3], → 11BB → 0E40)
; moved here and jumps to 0E40 directly; also the end of 1330.
11F1: 005A  CLR fB[5]         ; keyboard: show X …
11F2: 0032  CLR fA[3]
11F3: 1F67  JC 0E40           ; … → 0E40 → display
; Δ [REORG] new relay (no TI-59 counterpart).
11F4: 17F6  JNC 15EF          ; relay: 0E0E (from 0AA6) → 15EF, end of the trace operand line
; Unused filler: A=A ALL (no-op) words, never executed.
11F5: 0100  A=A ALL
11F6: 0100  A=A ALL
11F7: 0100  A=A ALL
11F8: 0100  A=A ALL
11F9: 0100  A=A ALL
11FA: 0100  A=A ALL
11FB: 0100  A=A ALL
11FC: 0100  A=A ALL
11FD: 0100  A=A ALL
; Δ [REORG] TI-59 103E/103F moved here: scanner, library program (0E9D).
11FE: 0176  D=SLD ALL         ; library program: undo the shift …
11FF: 1F46  JC 15A2           ; … next byte (15A2, LIB_LABEL_SEARCH loop)
1200: 0A45  TST KR[4]         ; the cursor's register (first pass)?
1201: 0910  A=B MANT          ; A := register address (saved at 0B7C)
1202: 105A  JNC 122F          ; no → carry the neighbour keycode (122F)
1203: 02D7  A<>E DPT          ; E[0] := byte position of the cursor
; ── Ins per-register shift: recall the SCOM[10] register cache ──────────────
; B := SCOM[10], the program-register copy cached by PRGREG_FETCH/0C0B.
; The shift arithmetic below trusts this cache to equal the register's
; actual content (see 1219).
1204: 0AA7  MOV R5,#10
1205: 02F0  A=R5 DPT
1206: 0101  IO=A ALL
1207: 0A1F  RCLF
1208: 01D3  B=LOAD ALL
1209: 0101  IO=A ALL
120A: 0A0F  STOF
120B: 0121  IO=C ALL          ; SCOM[10] := 0: cache invalidated (C = 0)
120C: 01D7  A<>E ALL
120D: 0C58  A=SRB MAEX        ; A := cache with the byte count in nibble 0 …
120E: 0C40  A=SLA MAEX
120F: 0308  A=A-1 DPT1        ; … per byte below the cursor:
1210: 100C  JNC 1216
1211: 0153  B=SLB ALL         ; B := cache back in register position (2 nibbles per byte)
1212: 0153  B=SLB ALL
1213: 0C40  A=SLA MAEX        ; A follows (upper part, for Del at 0E7C)
1214: 0C40  A=SLA MAEX
1215: 180D  JC 120F
1216: 01D5  C<>D ALL          ; C := register read from RAM
1217: 0080  TST fA[8]         ; Del?
1218: 173B  JNC 0E7B          ; yes → 0E7B
; ── Ins shift arithmetic ────────────────────────────────────────────────────
; new register := (C − B) + (B << 2 nibbles), with C = the register's actual
; RAM content (read at 0EDD, MEMRD) and B = the SCOM[10] cache of the same
; register (recalled at 1207). With B == C this reduces to "shift the register
; up one keycode and insert 00" — the classic Ins. Missing safeguard: B is
; trusted as-is, never re-read from RAM, and the digit-serial ALU applies no BCD
; correction to digit 0 (hexadecimal in hardware; see Core/TMC0501.cpp), so
; a stale cache yields keycode digits outside 0–9 (same code as the TI-59, where
; texas-print.ti59's pseudo-code insertion exploits it; see that file's header).
1219: 0920  A=C MANT          ; Ins: A := register (for the carry-out below)
121A: 019C  C=C-B ALL
121B: 0153  B=SLB ALL
121C: 0153  B=SLB ALL
121D: 0194  C=C+B ALL
121E: 01D5  C<>D ALL
121F: 04D0  A=LOAD DPTC       ; carry-out: shift A right 12 keycode nibbles …
1220: 0C48  A=SRA MAEX
1221: 0308  A=A-1 DPT1
1222: 1805  JC 1220
1223: 09D7  A<>E MANT         ; … the register's old top keycode
; Δ [HW] TI-59 121E–122E: the register is addressed for MEMWR by a binary CMOS-RAM
; address instead of the RAM.OP bus code (hex tens nibble for registers ≥ 100).
; B keeps the register number (BCD, nibbles 3–5) next to the carry keycode
; (nibbles 1–0); 1226–122E turn the number into binary in A[1..0] and write at
; 0F6A. Ins/Del results traced identical on both machines.
1224: 0903  B=A MANT          ; B := register number (nibbles 3–5), carry keycode stays in
                              ;   nibbles 1–0
1225: 01D7  A<>E ALL          ; E := address / carry / count word for the next pass (0F6F)
1226: 0910  A=B MANT          ; A := register number alone …
1227: 06D8  A=0 EXP           ; … (Op 09 enters here, 14EA)
1228: 02D8  A=0 DPT
1229: 01DB  B=0 ALL
122A: 03D3  B=LOAD DPT1       ; B := 1
122B: 0D08  A=A-1 MLSD1       ; BCD register number − 1 …
122C: 1585  JNC 0F6A          ; … done: A[1..0] = binary RAM address → write the register (0F6A,
                              ;   MEMWR)
122D: 0180  A=A+B ALL         ; … binary count + 1 (digit 0 counts in hex and carries into
                              ;   nibble 1)
122E: 1807  JC 122B
122F: 0080  TST fA[8]         ; later registers: Ins or Del?
1230: 01D5  C<>D ALL
1231: 1EFC  JC 15AF           ; Ins → 15AF: shift up, carry byte in at the bottom
1232: 0160  A=SLC ALL         ; Del: this register's first keycode …
1233: 04D0  A=LOAD DPTC       ; … moved up 12 nibbles …
1234: 0C40  A=SLA MAEX
1235: 0308  A=A-1 DPT1
1236: 1805  JC 1234
1237: 016C  C=SRC ALL         ; C := this register shifted down one keycode
1238: 016C  C=SRC ALL
1239: 09B6  D=A+D MANT        ; … into the top of the previous register (D)
123A: 01D2  A<>B ALL          ; A := previous register's address
123B: 0D0B  B=A-1 MLSD1       ; (register number − 1: the one still pending)
; Δ [HW] TI-59 123C (B=SRB ALL) dropped: B already holds the register number in
; the mantissa form that 1226 expects.
123C: 182F  JC 1225           ; → write the previous register (1225)
123D: 0100  A=A ALL
123E: 1E81  JC 0EFE
123F: 0082  CLR fA[8]
1240: 017E  D=SRD ALL
1241: 19BF  JC 1162
1242: 0002  CLR fA[0]         ; label byte: compare with the wanted label (B EXP) …
1243: 0040  TST fA[4]
1244: 100B  JNC 123F
1245: 0CD2  A<>B MAEX
1246: 0219  IO=-B DPT
1247: 0173  B=SLD ALL
1248: 1804  JC 124A
1249: 03D3  B=LOAD DPT1
124A: 068B  B=A-B EXP
124B: 0619  IO=-B EXP         ; … equal?
124C: 0CD2  A<>B MAEX
124D: 1591  JNC 0F85          ; no → keep scanning
124E: 0219  IO=-B DPT
124F: 01D5  C<>D ALL
1250: 1365  JNC 109E
1251: 01D2  A<>B ALL
1252: 0A87  MOV R5,#8
1253: 02F0  A=R5 DPT
1254: 0219  IO=-B DPT
1255: 1006  JNC 1258
1256: 0203  B=A DPT
1257: 0D00  A=A+1 MLSD1
1258: 0904  C=A MANT
1259: 0288  A=A-B DPT
125A: 09F3  B=R5 MANT
125B: 1FD7  JC 0E70           ; yes → transfer to the step after the label
125C: 0BD0  A=LOAD MLSD5
125D: 0A87  MOV R5,#8
125E: 06F0  A=R5 EXP
125F: 0640  A=SLA EXP
1260: 0C40  A=SLA MAEX
1261: 0CD7  A<>E MAEX
1262: 1DF3  JC 0F69
1263: 0080  TST fA[8]         ; past the partition: Del with a register still pending?
1264: 0082  CLR fA[8]         ; (only once)
1265: 1ACF  JC 10FE           ; Ins, or Del done → redisplay the current step (0D14)
1266: 01D5  C<>D ALL          ; Del: next register = SCOM[10] (0) — the top keycode becomes 00
1267: 0AA7  MOV R5,#10
1268: 02F0  A=R5 DPT
1269: 0101  IO=A ALL
126A: 0A1F  RCLF
126B: 01D4  C=LOAD ALL
126C: 1863  JC 123B           ; → write the last register
126D: 00C8  TST fB[12]        ; Dsz / If flg: digit operand first, then the address
126E: 00CA  CLR fB[12]
126F: 109E  JNC 12BE
1270: 0239  IO=-D DPT
1271: 1006  JNC 1274
1272: 0040  TST fA[4]
1273: 0091  SET fA[9]         ; skip the next byte too
1274: 0052  CLR fA[5]         ; address operand handled
1275: 1092  JNC 12BE
1276: 1FBB  JC 0E99           ; next keycode
1277: 1B46  JC 141A
; Ind address / library SBR operand: convert the operand into a step number
; (1278–1286) before the transfer.
1278: 04D0  A=LOAD DPTC
1279: 0308  A=A-1 DPT1
127A: 1016  JNC 1285
127B: 0708  A=A-1 EXP1
127C: 1807  JC 1279
127D: 0948  A=SRA MANT
127E: 0308  A=A-1 DPT1
127F: 1805  JC 127D
1280: 00A0  TST fA[10]
1281: 16C0  JNC 15E1
; Δ [REORG] 1282 is TI-59 1283 (exit → 0E8B ≙ TI-59 0F34). 1283–1284 are TI-59
; 10BE–10BF (drop a byte, → scanner), moved out of the mnemonic table's spare
; words, which now hold the self-test's fail/pass exits (10BE/10BF).
1282: 1FEF  JC 0E8B           ; → continue the sequence (0E8B → 0AFF)
1283: 017E  D=SRD ALL         ; drop a byte (List / Op 08 label lines, from 1427) …
1284: 1E17  JC 0F79           ; … → scanner (0F79); the library label search enters here (15AE)
1285: 02D8  A=0 DPT
1286: 1813  JC 127D
; ── Library transfer target: resolve against module header, bounds-check ────
; SBR/GTO nnn while the target program lives in a solid-state module (reached
; from the shared transfer routine via 085C → 0BC9 → 0FB8, traced; the launch
; prologue at 0A4D has already written Prg Src Flag := 1). 1287 selects
; SCOM[9] (R5 = 9); 128C-1291 recall it — its current/new-page fields
; (nibbles 6-5 / 4-3, see reference/CoreArchitecture.md § SCOM registers)
; hold the selected library program number p ("Pgm nn") — and form the
; header offset 2p (one 2-byte BCD start address per program from module
; address 0002). The LIB.PC loop at 1294-1298 points the CROM pointer there;
; 1299-12AB read TWO consecutive header entries: B := start address of program
; p, C := start of program p+1, i.e. p's end bound. 12AC adds the keyed offset
; (A := start + nnn) and 12AF/12B0 range-check the result: target >= next
; program's start → out of range → error halt at 11E2, with nothing executed
; and the CROM pointer left in the header; in range → 12B1-12B7 commit the
; target to the CROM PC via LIB.PC. Same code as the TI-59; ML Pgm 12 SBR 444
; (target 2609 + 444 = 3053 ≥ 2764) ends at 11E2 on the TI-58C too (traced) —
; see examples/texas-print.ti59.
1287: 0A97  MOV R5,#9
1288: 02F0  A=R5 DPT
1289: 0D09  IO=A-1 MLSD1
128A: 105C  JNC 12B8
128B: 0101  IO=A ALL
128C: 0A1F  RCLF
128D: 09D4  C=LOAD MANT
128E: 096C  C=SRC MANT
128F: 096C  C=SRC MANT
1290: 0923  B=C MANT
1291: 0994  C=C+B MANT
1292: 0A37  MOV R5,#3
1293: 02F4  C=R5 DPT
1294: 096C  C=SRC MANT
1295: 0A18  MOV KR[4..7],R5
1296: 0A1E  LIB.PC
1297: 032C  C=C-1 DPT1
1298: 1809  JC 1294
1299: 03D0  A=LOAD DPT1
129A: 07D8  A=-1 EXP1
129B: 01DC  C=0 ALL
129C: 0153  B=SLB ALL
129D: 0A3E  LIB.HI
129E: 0A0C  MOV KR,EXT[4..15]
129F: 0A08  MOV R5,KR[4..7]
12A0: 02F4  C=R5 DPT
12A1: 0164  C=SLC ALL
12A2: 0A0E  LIB.IN
12A3: 0A0C  MOV KR,EXT[4..15]
12A4: 0A08  MOV R5,KR[4..7]
12A5: 02F4  C=R5 DPT
12A6: 0164  C=SLC ALL
12A7: 1017  JNC 129C
12A8: 0308  A=A-1 DPT1
12A9: 1006  JNC 12AC
12AA: 0123  B=C ALL
12AB: 1823  JC 129A
12AC: 0980  A=A+B MANT
12AD: 0163  B=SLC ALL
12AE: 0153  B=SLB ALL
12AF: 098B  B=A-B MANT
12B0: 199D  JC 11E2
12B1: 0A37  MOV R5,#3         ; found: commit the address to the CROM PC …
12B2: 02F0  A=R5 DPT
12B3: 0948  A=SRA MANT
12B4: 0A18  MOV KR[4..7],R5
12B5: 0A1E  LIB.PC
12B6: 0308  A=A-1 DPT1
12B7: 1809  JC 12B3
12B8: 01D5  C<>D ALL
12B9: 01D7  A<>E ALL
12BA: 1EBD  JC 0F5C
12BB: 1FA7  JC 0EE8
12BC: 1650  JNC 15E4
; Scanner: operand byte to skip (fA[9], from 0F7B). During Op 08 / List the
; label names are printed here (12C1–12CD: PRT.OUT digit codes).
12BD: 017E  D=SRD ALL         ; drop the operand byte
12BE: 0082  CLR fA[8]
12BF: 0040  TST fA[4]         ; printing (List / Op 08)?
12C0: 1895  JC 1276           ; no → next keycode
12C1: 00D0  TST fA[13]        ; Op 08 label list …
12C2: 1389  JNC 10FE
12C3: 0A0C  MOV KR,EXT[4..15]
12C4: 07DE  D=-1 EXP1
12C5: 0C16  D=B MAEX
12C6: 0631  IO=D EXP
12C7: 0A18  MOV KR[4..7],R5
12C8: 0A04  INC KR
12C9: 067E  D=SRD EXP
12CA: 0A68  PRT.OUT
12CB: 100B  JNC 12C6
12CC: 0616  D=B EXP
12CD: 0A98  PRT.STEP
12CE: 0A98  PRT.STEP
12CF: 00A0  TST fA[10]        ; trace-queue call (fA[10] set)? …
12D0: 13E5  JNC 10DE          ; … yes → back to the keystroke gate via 10DE → 0D32 → 0BF9 → 0833
12D1: 07D0  A=LOAD EXP1       ; digits: keycode (2) and step number (3), right to left …
12D2: 03D0  A=LOAD DPT1
12D3: 0A0C  MOV KR,EXT[4..15]
12D4: 0631  IO=D EXP
12D5: 0A18  MOV KR[4..7],R5
12D6: 0A04  INC KR            ; … code = digit + 1
12D7: 0C7E  D=SRD MAEX
12D8: 0A68  PRT.OUT
12D9: 0308  A=A-1 DPT1
12DA: 180F  JC 12D3
12DB: 0708  A=A-1 EXP1
12DC: 1070  JNC 1314
12DD: 0A98  PRT.STEP          ; two blank columns between the fields
12DE: 0A98  PRT.STEP
12DF: 0A27  MOV R5,#2
12E0: 02F0  A=R5 DPT
12E1: 181D  JC 12D3
; ═══════════════════════════════════════════════════════════════════════════
; HIR_EXEC  (0x12E2–0x12FD) — HIR nm (keycode 82, programs only), entered from
; the HIR sequence slot 00FC via 04E0 → 08CD → 0CBC → 103E. Operand: n in A[4],
; m in A[3]. m = 0 or 9, or n = 2 → 1166: no operation (HIR 00 / 09 / 2m keep
; X, as on the TI-59). n ≥ 5 sets INV (fB[8]) and becomes n − 2. Then n = 0 STO
; → 11BB, 1 RCL → 1150, 3 SUM → 1151, 4 Prd (6–9: INV Prd) → 12F9: the
; continuation slot is moved on to the MULDIV slot, then 1151. Traced on both
; machines with HIR 01/11/21/31/41/51/61/71/81/91 programs.
; ═══════════════════════════════════════════════════════════════════════════
; Δ [FIX] TI-59 11BC–11D7 moved here (TI-59 PGM_SELECT 12E1 moved to 173B). One
; change: the copy of X takes its sign nibble from fB[1..4] (12E3), not fA[1..4].
; fA[3] is the display's exponent sign and stale in a running program, so the
; TI-59's HIR SUM/Prd/INV SUM/INV Prd used X = m·10^(+e) for 0 < |X| < 1
; (".5 HIR 48" multiplies by 50). Traced: TI-59 wrong, TI-58C right.
12E2: 0120  A=C ALL           ; A := X (full precision) …
12E3: 0A16  MOV R5,fB[1..4]   ; … with the signs of X from fB (TI-59: fA, see Δ)
12E4: 02F0  A=R5 DPT
12E5: 0103  B=A ALL           ; B := signed X (operand of SUM / Prd)
12E6: 01D7  A<>E ALL          ; A := operand nm: n in nibble 4, m in nibble 3
12E7: 0509  IO=A-1 LLSD1      ; m = 0 …
12E8: 0501  IO=A+1 LLSD1      ; … or m = 9?
12E9: 1307  JNC 1166          ; yes → no operation (1166)
12EA: 0948  A=SRA MANT        ; A[3] := n
12EB: 02F6  D=R5 DPT          ; D[0] := m, the SCOM row
12EC: 0B09  IO=A-5 MLSD5      ; n ≥ 5?
12ED: 1008  JNC 12F1          ; no → dispatch
12EE: 0089  SET fB[8]         ; yes: INV, n − 2 (5 → SUM, 6 → Prd)
12EF: 0D08  A=A-1 MLSD1
12F0: 0D08  A=A-1 MLSD1
12F1: 0D08  A=A-1 MLSD1       ; dispatch on n: 0 …
12F2: 126F  JNC 11BB          ; … STO → 11BB
12F3: 0D08  A=A-1 MLSD1
12F4: 1349  JNC 1150          ; 1: RCL → 1150
12F5: 0D08  A=A-1 MLSD1
12F6: 1321  JNC 1166          ; 2: no operation
12F7: 0D08  A=A-1 MLSD1
12F8: 134F  JNC 1151          ; 3: SUM → 1151
12F9: 0A0D  SWAP KR,SR        ; 4: Prd — the continuation slot …
12FA: 0AE7  MOV R5,#14
12FB: 0A18  MOV KR[4..7],R5   ; … := 14, so the sequence goes on with MULDIV (00FF) instead of
                              ;   ADD
12FC: 0A0D  SWAP KR,SR
12FD: 1B59  JC 1151           ; → 1151
; INV_LIST_START (0x12FE–0x1313, from 0D0D via the spare mnemonic-table word
; 103F) — INV List: SCOM[0] nibbles 1–2 := Int(X) (first register to print),
; SCOM[9] nibble 15 := 1 (listing active), advance the sequence to its print slot
; and enter the print loop at 0FB1 (see INV_LIST there). Traced on both.
; Δ [REORG] TI-59 0F6E–0F83 moved here; the continuation advance (SWAP KR,SR /
; INC KR / SWAP KR,SR) now brackets the final RCLF.
12FE: 0120  A=C ALL           ; first register: SCOM[0] nibbles 1–2 := Int(X)
12FF: 0633  B=D EXP
1300: 0A0F  STOF
1301: 0111  IO=B ALL
1302: 0A06  MOV R5,fA[1..4]
1303: 02F0  A=R5 DPT
1304: 01D7  A<>E ALL
1305: 0A97  MOV R5,#9         ; SCOM[9] …
1306: 02F3  B=R5 DPT
1307: 0111  IO=B ALL
1308: 0A1F  RCLF
1309: 01D0  A=LOAD ALL
130A: 0E00  A=A+1 MMSD1       ; SCOM[9] nibble 15 := 1 (listing active)
130B: 0111  IO=B ALL
130C: 0A0F  STOF
130D: 0101  IO=A ALL
130E: 0A0D  SWAP KR,SR        ; advance the sequence to its print slot
130F: 0A04  INC KR
1310: 0A1F  RCLF
1311: 01D0  A=LOAD ALL
1312: 0A0D  SWAP KR,SR
1313: 1EC5  JC 0FB1           ; → print loop (0FB1 ≙ TI-59 0FA5)
1314: 0AA8  PRT.GO            ; print the line
1315: 0040  TST fA[4]
1316: 0116  D=B ALL
1317: 19D4  JC 1401
1318: 1435  JNC 10FE
1319: 0120  A=C ALL           ; Op 09 after the write (from 0F6E): E := next register address
131A: 01D7  A<>E ALL
131B: 0050  TST fA[5]         ; last register written?
131C: 1B64  JC 14CE           ; no → next 8 keycodes
131D: 0A1F  RCLF              ; done: SCOM[0] …
131E: 01D0  A=LOAD ALL
131F: 0A47  MOV R5,#4
1320: 02F4  C=R5 DPT
1321: 06F4  C=R5 EXP
1322: 0948  A=SRA MANT        ; … drop nibbles 3–7 (step counter 000, Prg Src 0) …
1323: 032C  C=C-1 DPT1
1324: 1805  JC 1322
1325: 0940  A=SLA MANT        ; … and shift back
1326: 072C  C=C-1 EXP1
1327: 1805  JC 1325
1328: 0A0F  STOF
1329: 0101  IO=A ALL          ; SCOM[0] written
132A: 0AA7  MOV R5,#10
132B: 02F0  A=R5 DPT
132C: 0101  IO=A ALL
132D: 0A1F  RCLF
132E: 01D4  C=LOAD ALL        ; C := SCOM[10]
132F: 00B9  SET fB[11]        ; reload the program register at the next fetch
1330: 1A7B  JC 11F3           ; → display (0E40)
1331: 16CD  JNC 0FCB
1332: 1E50  JC 165A
; Δ [REORG] new: trampoline from 0FB9 to LIB_LABEL_SEARCH, which moved to 157A
; (TI-59 0FAD jumps to 1364 directly).
1333: 148E  JNC 157A          ; → LIB_LABEL_SEARCH (157A)
; ── Return-stack push (RET_PUSH): save the caller's calculator-level return ──
; The 6-level subroutine return stack lives in SCOM[15] (levels 1-3) and
; SCOM[14] (levels 4-6); see reference/CoreArchitecture.md § SCOM registers.
; Pushed on every calculator-level call: SBR into a RAM or library program and
; keycode-ROM sub-program launches (traced: P→R, Σ+, x̄, SBR, Pgm 02 A), all
; via 0D33 → 0FFE → 1334. 1337/1338 load SCOM[15]; 133B checks the depth in the
; DPT nibble; the shift loops move the existing levels up, spilling the
; displaced level into SCOM[14] (reloaded at 1350/1351, rewritten at
; 135B/135C), and the new return entry is merged into level 1 before SCOM[15]
; is stored back at 134C/134D. Level entry (5 nibbles): RAM register no. (3) +
; byte no. (1) — or a 4-digit CROM address for library callers — plus the
; caller's Prg Src Flag; SCOM[15] nibble 0 counts the pushed levels.
; Δ [REORG] TI-59 0D50–0D7B moved here unchanged (only the jump targets differ);
; exit → 0F69 → 0BC3 (≙ TI-59 0BCB).
1334: 0AF7  MOV R5,#15        ; D := SCOM[15] (levels 1–3, depth in nibble 0)
1335: 02F4  C=R5 DPT
1336: 0121  IO=C ALL
1337: 0A1F  RCLF
1338: 01D6  D=LOAD ALL
1339: 0A57  MOV R5,#5         ; stack full (depth > 5)?
133A: 02F0  A=R5 DPT
133B: 02B9  IO=A-D DPT
133C: 1042  JNC 135D          ; yes → push silently skipped: a 7th SBR loses its return (no
                              ;   error)
133D: 0304  C=A+1 DPT1        ; shift levels 1–2 up one 5-nibble slot …
133E: 0308  A=A-1 DPT1
133F: 0C76  D=SLD MAEX
1340: 0940  A=SLA MANT
1341: 0308  A=A-1 DPT1
1342: 1807  JC 133F
1343: 0C48  A=SRA MAEX        ; … the displaced level 3 into A for SCOM[14]
1344: 032C  C=C-1 DPT1
1345: 1805  JC 1343
1346: 03D0  A=LOAD DPT1       ; depth + 1, new level merged into nibbles 1–5
1347: 01B6  D=A+D ALL
1348: 0121  IO=C ALL
1349: 0A1F  RCLF
134A: 09D0  A=LOAD MANT
134B: 0121  IO=C ALL
134C: 0A0F  STOF
134D: 0131  IO=D ALL          ; SCOM[15] written
134E: 032C  C=C-1 DPT1        ; SCOM[14] (levels 4–6): shift up, take the displaced level
134F: 0121  IO=C ALL
1350: 0A1F  RCLF
1351: 01D6  D=LOAD ALL
1352: 0A47  MOV R5,#4
1353: 02F0  A=R5 DPT
1354: 0C48  A=SRA MAEX
1355: 0C48  A=SRA MAEX
1356: 0C76  D=SLD MAEX
1357: 0308  A=A-1 DPT1
1358: 1809  JC 1354
1359: 0CB6  D=A+D MAEX
135A: 0121  IO=C ALL
135B: 0A0F  STOF
135C: 0131  IO=D ALL          ; SCOM[14] written
135D: 04D4  C=LOAD DPTC       ; → continue the transfer (0F69 → 0BC3)
135E: 01D2  A<>B ALL
135F: 1FED  JC 0F69
; ═══════════════════════════════════════════════════════════════════════════
; SELFTEST8_SCOM / SELFTEST10_RAM  (0x1360–0x138F) — factory self-test bodies, run
; by the test sequencer 0DB7–0DDA (entered with the hidden key at row 8 /
; column 0) through the table 0C01–0C0A and the stubs 0FF4–0FFD. Each body ends
; in 10BF (pass → next test, 0DC3) or 10BE (fail → 0DD6, the sequence stops).
;   test 8 (0C08 → 0FFC → 1360): SCOM[k] := k·1000 + k (nibbles 3 and 0) for
;     all 16 rows, then rows 0–7 verified;
;   test 9 (0C09 → 0FF4 → 0FF9 → 1368, A preset to row 8): rows 8–15 verified;
;   test 10 (0C0A → 0FFD → 1375), the last (fA[5]): every CMOS-RAM register
;     63…0 := its own binary address (MEMWR), all read back (MEMRD) and compared;
;   tests 4, 5, 6: stubs 138D, 138F, 138E → bodies at 16C7, 16C8, 1680.
; Traced: all tests pass; afterwards RAM register k holds k, so the user's
; constant memory (and the RAM 60 signature) is gone.
; ═══════════════════════════════════════════════════════════════════════════
; Δ [ENH] new (TI-59 1364–1398, LIB_LABEL_SEARCH, moved to 157A): self-test.
1360: 01D8  A=0 ALL           ; test 8: row k := k·1000 + k for k = 0…15 …
1361: 0101  IO=A ALL          ; select row k
1362: 0A0F  STOF
1363: 0101  IO=A ALL          ; SCOM[k] := pattern
1364: 0D00  A=A+1 MLSD1       ; next pattern …
1365: 0300  A=A+1 DPT1        ; … and row
1366: 180B  JC 1361           ; until all 16 rows are written
1367: 01D8  A=0 ALL           ; verify from row 0 …
1368: 0A77  MOV R5,#7         ; (test 9 enters here with A = row 8) eight rows
1369: 06F4  C=R5 EXP
136A: 0101  IO=A ALL          ; select row k
136B: 0A1F  RCLF
136C: 01D6  D=LOAD ALL        ; D := SCOM[k]
136D: 01BE  D=A-D ALL         ; as written?
136E: 0139  IO=-D ALL
136F: 1563  JNC 10BE          ; no → test failed (10BE)
1370: 0D00  A=A+1 MLSD1
1371: 0300  A=A+1 DPT1
1372: 072C  C=C-1 EXP1        ; eight rows done?
1373: 1813  JC 136A
1374: 156B  JNC 10BF          ; yes → test passed (10BF)
1375: 0AF7  MOV R5,#15        ; test 10: C := 3F, register 63 (binary) …
1376: 01F4  C=R5 ALL
1377: 06D7  A<>E EXP
1378: 0604  C=A EXP
1379: 01DB  B=0 ALL
137A: 03D3  B=LOAD DPT1       ; B := 1
137B: 0121  IO=C ALL          ; address k …
137C: 0A76  MEMWR
137D: 0121  IO=C ALL          ; … data k: RAM[k] := k
137E: 019C  C=C-B ALL         ; next register down …
137F: 1809  JC 137B           ; … through register 0
1380: 0AF7  MOV R5,#15        ; read back from register 63 …
1381: 01F4  C=R5 ALL
1382: 0604  C=A EXP
1383: 0121  IO=C ALL
1384: 0A86  MEMRD
1385: 01D6  D=LOAD ALL        ; D := RAM[k]
1386: 0051  SET fA[5]         ; last test: the sequencer ends after it
1387: 01AE  D=C-D ALL         ; = k?
1388: 0139  IO=-D ALL
1389: 1597  JNC 10BE          ; no → test failed
138A: 019C  C=C-B ALL
138B: 1811  JC 1383
138C: 159B  JNC 10BF          ; all 64 registers good → test passed
138D: 1E74  JC 16C7           ; test 4 body (16C7)
138E: 1DE4  JC 1680           ; test 6 body (1680)
138F: 1E72  JC 16C8           ; test 5 body (16C8)
; PRT_CHAR_SLIDE (0x1390–0x13DC): INC KR chains that turn an entry depth into
; a 6-bit PC-100 character code in KR[4..9]: 1390–139F codes 15…0, 13A2–13B1
; 31…16 (+KR[8]), 13B5–13C3 47…32 (+KR[9]), 13D1–13DB 58…48 (+KR[8]+KR[9]),
; each ending in PRT.OUT at 13B3. Entered from the mnemonic table (0x1000)
; and the trace symbol queue (142A–1459).
1390: 0A04  INC KR
1391: 0A04  INC KR
1392: 0A04  INC KR
1393: 0A04  INC KR
1394: 0A04  INC KR
1395: 0A04  INC KR
1396: 0A04  INC KR
1397: 0A04  INC KR
1398: 0A04  INC KR
1399: 0A04  INC KR
139A: 0A04  INC KR
139B: 0A04  INC KR
139C: 0A04  INC KR
139D: 0A04  INC KR
139E: 0A04  INC KR
139F: 008D  CLR KR[8]
13A0: 1824  JC 13B2
13A1: 1B14  JC 152B
13A2: 0A04  INC KR
13A3: 0A04  INC KR
13A4: 0A04  INC KR
13A5: 0A04  INC KR
13A6: 0A04  INC KR
13A7: 0A04  INC KR
13A8: 0A04  INC KR
13A9: 0A04  INC KR
13AA: 0A04  INC KR
13AB: 0A04  INC KR
13AC: 0A04  INC KR
13AD: 0A04  INC KR
13AE: 0A04  INC KR
13AF: 0A04  INC KR
13B0: 0A04  INC KR
13B1: 0085  SET KR[8]
13B2: 009D  CLR KR[9]
13B3: 0A68  PRT.OUT
13B4: 1926  JC 1447
13B5: 0A04  INC KR
13B6: 0A04  INC KR
13B7: 0A04  INC KR
13B8: 0A04  INC KR
13B9: 0A04  INC KR
13BA: 0A04  INC KR
13BB: 0A04  INC KR
13BC: 0A04  INC KR
13BD: 0A04  INC KR
13BE: 0A04  INC KR
13BF: 0A04  INC KR
13C0: 0A04  INC KR
13C1: 0A04  INC KR
13C2: 0A04  INC KR
13C3: 008D  CLR KR[8]
13C4: 0095  SET KR[9]
13C5: 1825  JC 13B3
13C6: 00C9  SET fB[12]        ; Pgm nn while running: mark SCOM[13] nibble 15 for the next step
13C7: 0320  A=C+1 DPT1
13C8: 01D5  C<>D ALL
13C9: 0101  IO=A ALL
13CA: 0A1F  RCLF
13CB: 01D4  C=LOAD ALL
13CC: 0E24  C=C+1 MMSD1
13CD: 01D5  C<>D ALL
13CE: 1F3A  JC 176B           ; → write SCOM[13] back (176B, in PGM_SELECT)
13CF: 0A57  MOV R5,#5
13D0: 0A18  MOV KR[4..7],R5
13D1: 0A04  INC KR
13D2: 0A04  INC KR
13D3: 0A04  INC KR
13D4: 0A04  INC KR
13D5: 0A04  INC KR
13D6: 0A04  INC KR
13D7: 0A04  INC KR
13D8: 0A04  INC KR
13D9: 0A04  INC KR
13DA: 0A04  INC KR
13DB: 0085  SET KR[8]
13DC: 1831  JC 13C4
; LRN_DISPLAY  (0x13DD–0x1415): show "SSS KK" — step number SSS (decimal,
; register·8 + byte computed by doubling at 13ED–13F2) and the keycode KK
; from SCOM[10] nibbles 1..0. Trace-confirmed (LRN, LRN 5 → "001 00").
13DD: 0070  TST fA[7]
13DE: 0072  CLR fA[7]
13DF: 16C1  JNC 107F
13E0: 00B0  TST fA[11]
13E1: 00B2  CLR fA[11]
13E2: 1589  JNC 111E
13E3: 0A1F  RCLF              ; SCOM[0] step counter
13E4: 01D0  A=LOAD ALL
13E5: 0148  A=SRA ALL
13E6: 0148  A=SRA ALL
13E7: 094B  B=SRA MANT
13E8: 095B  B=SRB MANT
13E9: 095B  B=SRB MANT
13EA: 0953  B=SLB MANT
13EB: 0953  B=SLB MANT
13EC: 0953  B=SLB MANT
13ED: 0988  A=A-B MANT        ; decimal step = register·8 + byte …
13EE: 0103  B=A ALL
13EF: 0980  A=A+B MANT
13F0: 0983  B=A+B MANT
13F1: 0980  A=A+B MANT
13F2: 0980  A=A+B MANT
13F3: 09DB  B=0 MANT
13F4: 0153  B=SLB ALL
13F5: 0176  D=SLD ALL
13F6: 0986  D=A+B MANT

13F7: 0040  TST fA[4]
13F8: 103E  JNC 1417
13F9: 0A1F  RCLF
13FA: 09D0  A=LOAD MANT
13FB: 0E08  A=A-1 MMSD1
13FC: 0E08  A=A-1 MMSD1
13FD: 183A  JC 141A
13FE: 0A00  WAIT D0
13FF: 08FB  KEY [P]

; ── TMC0573  0x1400–0x17FF  1,024 words  (ROM chip 3) ────────────────────
; Executable code like chips 1–2 (printer, LRN display, Op 16/17, self-test, …);
; the 64-entry constant table lives in CD2400/CD2401 (roms/calculator/*-CONST-K).

1400: 1034  JNC 141A
1401: 0A37  MOV R5,#3
1402: 01F3  B=R5 ALL
1403: 0A87  MOV R5,#8
1404: 09F3  B=R5 MANT
1405: 0976  D=SLD MANT
1406: 0170  A=SLD ALL
1407: 0140  A=SLA ALL
1408: 0153  B=SLB ALL
1409: 0153  B=SLB ALL
140A: 0153  B=SLB ALL
140B: 0153  B=SLB ALL
140C: 0153  B=SLB ALL
140D: 04D0  A=LOAD DPTC
140E: 00C8  TST fB[12]        ; argument pending?
140F: 1763  JNC 105E
1410: 0A0D  SWAP KR,SR        ; return through the continuation in SR
1411: 0015  SET KR[1] ; PREG
1412: 0A0D  SWAP KR,SR
; Program error halt (Pgm out of range, …): error blink, stop the run.
1413: 0099  SET fB[9]         ; ERROR
1414: 000A  CLR fB[0]         ; program stops
1415: 1AB9  JC 12B9
; Δ [REORG] new: the Pgm sequence's jump (105F) lands here and goes on to
; PGM_SELECT, which moved unchanged from TI-59 12E1–1314 to 173B–176E.
1416: 1E4A  JC 173B           ; Pgm nn → PGM_SELECT (173B)
1417: 0AA0  WAIT D10          ; R/S held? (row 9 / column 1)
1418: 08FD  KEY [O]
1419: 1453  JNC 11F0          ; yes → stop listing
; ── Keystroke trace-symbol QUEUE routine (TRC_SYM_QUEUE; traced on both with
; the printer and flag 9: "5 +"). Reached from the keystroke print/trace gate's
; first pass via 0B1B → 0E8A → 1277. Re-checks printer-present (141A/141B),
; waits until not BUSY (141D–141F), PRT.CLRs the 20-column line buffer, then
; converts the 2-digit key position code into three 6-bit printer character
; codes (JC dispatch table around 1117–112F jumping into the INC-KR chains at
; 1390–13B1) and writes them right-justified via 3× PRT.OUT at 13B3. Crucially,
; no PRT.GO: the symbol only waits in the buffer — an operation key later
; appends the display value and prints the line (05A8/0EFD), a digit key
; discards the record (02DA). Note the symbol is looked up from the raw
; POSITION code, before any digit remapping: key "0" (row 9, col 2 → code 92)
; queues "RTN" — the symbol of keycode 92 (INV SBR). Harmless, since digit
; records are never printed.
; Δ [HW] TI-59 1422: printer-present is sensed at digit 11 (WAIT D11) instead of D1.
141A: 0AB0  WAIT D11          ; printer present? (KP sensed at D11 on the TI-58C) …
141B: 08FB  KEY [P]           ; …
141C: 1837  JC 1401
141D: 0A98  PRT.STEP          ; wait until the printer is idle …
141E: 0A0B  TST.BUSY          ; wait for any running print to finish
141F: 1005  JNC 141D
1420: 0A88  PRT.CLR           ; … new line
1421: 0A0C  MOV KR,EXT[4..15]
1422: 0133  B=D ALL
1423: 00A0  TST fA[10]
1424: 100C  JNC 142A
1425: 0A78  PRT.FUNC
1426: 0040  TST fA[4]
1427: 1349  JNC 1283
1428: 00A8  TST fB[10]
1429: 12B1  JNC 12D1
142A: 01D5  C<>D ALL          ; keycode → address in the mnemonic table …
142B: 016C  C=SRC ALL
142C: 0624  C=C EXP
142D: 0A18  MOV KR[4..7],R5
142E: 0A75  TST KR[7]
142F: 1804  JC 1431
1430: 00C5  SET KR[12]        ; … 0x1000 base …
1431: 0A65  TST KR[6]
1432: 1804  JC 1434
1433: 00B5  SET KR[11]
1434: 0A55  TST KR[5]
1435: 1804  JC 1437
1436: 00A5  SET KR[10]
1437: 0A45  TST KR[4]
1438: 06DC  C=0 EXP
1439: 1808  JC 143D
143A: 0A27  MOV R5,#2
143B: 06F4  C=R5 EXP
143C: 0095  SET KR[9]
143D: 0005  SET KR[0]
143E: 0A37  MOV R5,#3
143F: 09F4  C=R5 MANT
1440: 0223  B=C DPT
1441: 0294  C=C+B DPT
1442: 1804  JC 1444
1443: 0724  C=C+1 EXP1
1444: 0294  C=C+B DPT
1445: 1804  JC 1447
1446: 0724  C=C+1 EXP1
1447: 0D2C  C=C-1 MLSD1
1448: 1026  JNC 145B
1449: 0624  C=C EXP
144A: 0A18  MOV KR[4..7],R5
144B: 0A55  TST KR[5]
144C: 009D  CLR KR[9]
144D: 1804  JC 144F
144E: 0095  SET KR[9]
144F: 0A45  TST KR[4]
1450: 008D  CLR KR[8]
1451: 1804  JC 1453
1452: 0085  SET KR[8]
1453: 0224  C=C DPT
1454: 0A18  MOV KR[4..7],R5
1455: 0324  C=C+1 DPT1
1456: 1804  JC 1458
1457: 0724  C=C+1 EXP1
1458: 0A07  MOV R5,#0
1459: 0015  SET KR[1] ; PREG ; … computed jump: three characters, right to left
145A: 0A18  MOV KR[4..7],R5
145B: 0114  C=B ALL
145C: 01D5  C<>D ALL
145D: 000D  CLR KR[0]
145E: 0040  TST fA[4]
145F: 1323  JNC 12CE
1460: 0080  TST fA[8]
1461: 1B27  JC 12CE
1462: 0A0C  MOV KR,EXT[4..15]
1463: 0085  SET KR[8]
1464: 0065  SET KR[6]
1465: 0A68  PRT.OUT
1466: 1B2F  JC 12CF
; Δ [?] TI-59 146F–1478: the byte count is kept in A[1] (EXP) instead of A[0],
; and KR[4..7] (byte position) is parked in A[1] and zeroed (1467–146A) while
; SCOM[10] is stored, then restored (1470–1473). Purpose not established; LRN
; stores and Ins/Del leave identical program memory on both machines (traced).
1467: 0A08  MOV R5,KR[4..7]   ; byte position …
1468: 06F0  A=R5 EXP          ; … parked in A[1]
1469: 0201  IO=A DPT          ; KR[4..7] := A[0] (0) while SCOM[10] is written
146A: 0A18  MOV KR[4..7],R5
146B: 0AA7  MOV R5,#10        ; SCOM[10] := shifted image (PRGREG_CACHE)
146C: 02F0  A=R5 DPT
146D: 0101  IO=A ALL
146E: 0A0F  STOF
146F: 0131  IO=D ALL
1470: 0A08  MOV R5,KR[4..7]
1471: 02F0  A=R5 DPT
1472: 0601  IO=A EXP          ; KR[4..7] := the byte position again (A[1])
1473: 0A18  MOV KR[4..7],R5
1474: 0631  IO=D EXP          ; old keycode = nibbles 1..0 …
1475: 0CF6  D=R5 MAEX
1476: 0708  A=A-1 EXP1        ; per byte position: shift the old keycode up into place
1477: 1302  JNC 15F8
1478: 0176  D=SLD ALL
1479: 0176  D=SLD ALL
147A: 1809  JC 1476
; ═══════════════════════════════════════════════════════════════════════════
; OP09_DOWNLOAD  (0x147B–0x14EA) — Op 09: copy the selected library program
; into RAM program memory from step 000. Traced on both: ML Pgm 01, 05, 10, 21,
; 25 copy identically; on the TI-58C ML Pgm 03 errors under 239.29 and copies
; under 479. (0 Op 17), Pgm 02 (898 steps) always errors (480 steps at most).
; Checks, each failing to 1169 with fB[9] already set (1482):
;   module copy-protect byte (header byte 1) ≠ 0 (1483–1488),
;   program length (next program's start − this start) > program memory
;   (8 · program registers, 14B2–14C4).
; Then 8 keycodes per register are read from the CROM (LIB.HI/LIB.IN pairs,
; 14D2–14DF) and written as RAM program registers (14EA → 1227 → 0F6A, MEMWR)
; until the program's end (14DC → 176F: pad the last register with 00).
; ═══════════════════════════════════════════════════════════════════════════
147B: 0A17  MOV R5,#1         ; CROM PC := 0001 (copy-protect byte) …
147C: 0A18  MOV KR[4..7],R5
147D: 0A1E  LIB.PC
147E: 0A0C  MOV KR,EXT[4..15]
147F: 0A1E  LIB.PC
1480: 0A1E  LIB.PC
1481: 0A1E  LIB.PC
1482: 0099  SET fB[9]         ; assume failure
1483: 0A0E  LIB.IN            ; protect byte
1484: 0A0C  MOV KR,EXT[4..15]
1485: 0A08  MOV R5,KR[4..7]
1486: 02F3  B=R5 DPT
1487: 0219  IO=-B DPT         ; protected?
1488: 163F  JNC 1169          ; yes → error
1489: 0A97  MOV R5,#9         ; SCOM[9] page p → header entry 2p …
148A: 01F0  A=R5 ALL
148B: 0CD7  A<>E MAEX
148C: 0101  IO=A ALL
148D: 0A1F  RCLF
148E: 09D0  A=LOAD MANT
148F: 0C48  A=SRA MAEX
1490: 0C48  A=SRA MAEX
1491: 09D8  A=0 MANT
1492: 0C03  B=A MAEX
1493: 0C80  A=A+B MAEX
1494: 0A37  MOV R5,#3
1495: 02F0  A=R5 DPT
1496: 0C48  A=SRA MAEX
1497: 0A18  MOV KR[4..7],R5
1498: 0A1E  LIB.PC
1499: 0308  A=A-1 DPT1
149A: 1809  JC 1496
149B: 07D0  A=LOAD EXP1
149C: 03D0  A=LOAD DPT1
149D: 0133  B=D ALL
149E: 01DE  D=0 ALL
149F: 0153  B=SLB ALL
14A0: 0A3E  LIB.HI            ; read this program's start and the next one's (end) …
14A1: 0A0C  MOV KR,EXT[4..15]
14A2: 0A08  MOV R5,KR[4..7]
14A3: 02F6  D=R5 DPT
14A4: 0176  D=SLD ALL
14A5: 0A0E  LIB.IN
14A6: 0A0C  MOV KR,EXT[4..15]
14A7: 0A08  MOV R5,KR[4..7]
14A8: 02F6  D=R5 DPT
14A9: 0176  D=SLD ALL
14AA: 0308  A=A-1 DPT1
14AB: 1819  JC 149F
14AC: 0708  A=A-1 EXP1
14AD: 1823  JC 149C
14AE: 0176  D=SLD ALL
14AF: 0170  A=SLD ALL
14B0: 0988  A=A-B MANT        ; length = end − start
14B1: 01D2  A<>B ALL
14B2: 0323  B=C+1 DPT1        ; program memory = 8 · partition registers (SCOM[13]) …
14B3: 0111  IO=B ALL
14B4: 0A1F  RCLF
14B5: 01D6  D=LOAD ALL
14B6: 0A37  MOV R5,#3
14B7: 02F0  A=R5 DPT
14B8: 0948  A=SRA MANT
14B9: 0A18  MOV KR[4..7],R5
14BA: 0A1E  LIB.PC
14BB: 017E  D=SRD ALL
14BC: 0308  A=A-1 DPT1
14BD: 180B  JC 14B8
14BE: 0930  A=D MANT
14BF: 09B0  A=A+D MANT
14C0: 09B6  D=A+D MANT
14C1: 09B0  A=A+D MANT
14C2: 09B0  A=A+D MANT
14C3: 0989  IO=A-B MANT       ; … length fits?
14C4: 16B7  JNC 1169          ; no → error
14C5: 01D2  A<>B ALL
14C6: 009A  CLR fB[9]         ; OK
14C7: 0D08  A=A-1 MLSD1       ; empty program (length 0)?
14C8: 16BF  JNC 1169
14C9: 0AA7  MOV R5,#10
14CA: 02F0  A=R5 DPT
14CB: 0101  IO=A ALL
14CC: 0A0F  STOF
14CD: 0121  IO=C ALL          ; SCOM[10] := C (cache invalidated)
14CE: 0A77  MOV R5,#7         ; register loop: 8 keycodes …
14CF: 02F0  A=R5 DPT
14D0: 06F0  A=R5 EXP
14D1: 01DC  C=0 ALL           ; C collects the keycodes in read order, the first one on top
14D2: 0164  C=SLC ALL
14D3: 0A3E  LIB.HI
14D4: 0A0C  MOV KR,EXT[4..15]
14D5: 0A08  MOV R5,KR[4..7]
14D6: 02F4  C=R5 DPT
14D7: 0164  C=SLC ALL
14D8: 0A0E  LIB.IN
14D9: 0A0C  MOV KR,EXT[4..15]
14DA: 0A08  MOV R5,KR[4..7]
14DB: 02F4  C=R5 DPT
14DC: 0D08  A=A-1 MLSD1       ; program end reached?
14DD: 1524  JNC 176F          ; yes → pad the rest with 00, write, done (176F)
14DE: 0308  A=A-1 DPT1        ; 8 keycodes?
14DF: 181B  JC 14D2
14E0: 0176  D=SLD ALL         ; reverse into register order: C's lowest keycode …
14E1: 0C6C  C=SRC MAEX
14E2: 02F6  D=R5 DPT          ; … goes into D below the earlier ones, so step 0 ends up in byte
                              ;   0
14E3: 0176  D=SLD ALL
14E4: 016C  C=SRC ALL
14E5: 02F6  D=R5 DPT
14E6: 0708  A=A-1 EXP1        ; 8 keycodes moved?
14E7: 180F  JC 14E0
14E8: 01D7  A<>E ALL          ; A := register address (E) …
14E9: 0D04  C=A+1 MLSD1       ; … C := the next one
; Δ [HW] TI-59 14EC–14EE: the register is written through the binary-address
; path (1227 → 0F6A, MEMWR) instead of the RAM.OP encoding at TI-59 1221.
14EA: 1D87  JC 1227           ; write the register (1227 → 0F6A MEMWR → 0F6E → 1319, fB[10]
                              ;   clear)
; Trace operand line, tail of the conditional marker (from 17D4–17E9, see 15F0).
; Δ [ENH] 14EB–14EE new: label operands (fA[0]) go on to 1165 → 0E0F, others print.
14EB: 0A0D  SWAP KR,SR        ; (from 17D8 / 17DF) KR and SR back in place
14EC: 0000  TST fA[0]         ; label operand? (from 17E3 / 17E9)
14ED: 1A12  JC 15F6           ; no → print the line (15F6)
14EE: 1713  JNC 1165          ; yes → 1165 → 0E0F
; Unused filler: A=A ALL (no-op) words, never executed.
14EF: 0100  A=A ALL
14F0: 0100  A=A ALL
14F1: 0100  A=A ALL
14F2: 0100  A=A ALL
14F3: 0100  A=A ALL
14F4: 0100  A=A ALL
14F5: 0100  A=A ALL
14F6: 0100  A=A ALL
14F7: 0100  A=A ALL
14F8: 0100  A=A ALL
; RTN continuation (from 1194): returning into RAM / keyboard → shift the
; return stack down (0DDB); returning into a library program (Prg Src 2 in
; the popped level) → LIB_RETURN 14FC.
14F9: 0708  A=A-1 EXP1        ; library return?
14FA: 1004  JNC 14FC
14FB: 00D9  SET fB[13]
; ═══════════════════════════════════════════════════════════════════════════
; LIB_RETURN  (0x14FC–0x152A) — RTN back into a library program. Trace-
; confirmed on both (ML Pgm 02, key C: return to CROM address 0396). Prg Src 2
; in the popped level means "the module PC must be reloaded": the CROM PC is
; set to the header's program table (0002), SCOM[0]'s source becomes 1 again
; (1504–1506), the start addresses are scanned to find which program holds
; the return address (1507–151B, C counts programs: here 02), the CROM PC is
; loaded with the return address (151C–1522, LIB.PC ×4, LSD first) and the
; program number becomes the current page in SCOM[9] (1523 → 1196).
; ═══════════════════════════════════════════════════════════════════════════
14FC: 0A27  MOV R5,#2         ; CROM PC := 0002 (program table) …
14FD: 0A18  MOV KR[4..7],R5
14FE: 0A1E  LIB.PC
14FF: 0A0C  MOV KR,EXT[4..15]
1500: 0A1E  LIB.PC
1501: 0A1E  LIB.PC
1502: 0A1E  LIB.PC
1503: 0948  A=SRA MANT
1504: 05D6  D=LOAD LLSD1      ; Prg Src 2 → 1
1505: 0A0F  STOF
1506: 0131  IO=D ALL          ; SCOM[0] updated
1507: 01D5  C<>D ALL
1508: 01DC  C=0 ALL           ; program counter := 0
1509: 01DB  B=0 ALL
150A: 03D8  A=-1 DPT1
150B: 0A3E  LIB.HI            ; next program's start address …
150C: 0A0C  MOV KR,EXT[4..15]
150D: 0A08  MOV R5,KR[4..7]
150E: 02F3  B=R5 DPT
150F: 0153  B=SLB ALL
1510: 0A0E  LIB.IN
1511: 0A0C  MOV KR,EXT[4..15]
1512: 0A08  MOV R5,KR[4..7]
1513: 02F3  B=R5 DPT
1514: 0153  B=SLB ALL
1515: 1015  JNC 150B
1516: 0153  B=SLB ALL
1517: 0153  B=SLB ALL
1518: 0989  IO=A-B MANT       ; … beyond the return address?
1519: 1006  JNC 151C          ; yes → found
151A: 0D24  C=C+1 MLSD1       ; no → next program
151B: 1825  JC 1509
151C: 0A37  MOV R5,#3         ; CROM PC := return address, one digit per LIB.PC …
151D: 02F0  A=R5 DPT
151E: 0948  A=SRA MANT
151F: 0A18  MOV KR[4..7],R5
1520: 0A1E  LIB.PC
1521: 0308  A=A-1 DPT1
1522: 1809  JC 151E
1523: 01D5  C<>D ALL
1524: 0121  IO=C ALL
1525: 0A1F  RCLF              ; SCOM[9]: current page := the found program …
1526: 01D3  B=LOAD ALL
1527: 02F0  A=R5 DPT
1528: 030B  B=A-1 DPT1
1529: 07D3  B=LOAD EXP1
152A: 1F29  JC 1196
; ═══════════════════════════════════════════════════════════════════════════
; PRT_VALUE  (0x152B–0x1655, 0x0EE8–0x0F03) — print the display value as a
; PC-100 line (Prt, trace lines, Op 06). Trace-confirmed (−12.5 Prt →
; "       -12.5        "). Without a printer (WAIT D11 + KEY [P], 1539) it
; does nothing. Layout: clear the buffer (154F), the 3-character function field
; (PRT.FUNC, blank for Prt or the traced key's mnemonic, 1551/1634), then the
; digits RIGHT TO LEFT from the display image A: code = digit + 1 (164F–1652),
; the decimal point (code 32) when A[0]'s fraction count runs out (1646–1648),
; exponent digits in sci/eng display (162F–1633), finally the sign (code 16 at
; 0EFC) and PRT.GO (0EFD). fA[10] (pending trace record, 153C) selects the
; trace layout with the key's symbol already queued (141A).
; ═══════════════════════════════════════════════════════════════════════════
152B: 0A0D  SWAP KR,SR
152C: 0A0C  MOV KR,EXT[4..15]
152D: 03D3  B=LOAD DPT1
152E: 0A97  MOV R5,#9         ; SCOM[9] …
152F: 02F6  D=R5 DPT
1530: 0131  IO=D ALL
1531: 0A1F  RCLF
1532: 01D6  D=LOAD ALL
1533: 067E  D=SRD EXP
1534: 0050  TST fA[5]
1535: 19AC  JC 160B
1536: 0A0D  SWAP KR,SR
1537: 0090  TST fA[9]
1538: 15F7  JNC 123D
; Δ [HW] TI-59 1539: printer-present is sensed at digit 11 (WAIT D11) instead of D1.
1539: 0AB0  WAIT D11          ; printer present (KP at D11)?
153A: 08FB  KEY [P]
153B: 1DFD  JC 123D           ; no printer → skip
153C: 00A0  TST fA[10]        ; trace record pending?
153D: 182C  JC 1553
153E: 0A1F  RCLF
153F: 09D6  D=LOAD MANT
1540: 02F6  D=R5 DPT
1541: 0239  IO=-D DPT
1542: 0639  IO=-D EXP
1543: 1012  JNC 154C
1544: 01D5  C<>D ALL          ; TRACE switch off: user flag 9 set?
1545: 0E2C  C=C-1 MMSD1
1546: 0E2C  C=C-1 MMSD1
1547: 01D5  C<>D ALL
1548: 19B6  JC 1623           ; …
1549: 0A00  WAIT D0           ; TRACE switch (KP at D15)?
154A: 08FB  KEY [P]
154B: 11B0  JNC 1623
154C: 0A98  PRT.STEP          ; wait until the printer is idle …
154D: 0A0B  TST.BUSY
154E: 1005  JNC 154C
154F: 0A88  PRT.CLR           ; … clear the line buffer
1550: 0A0D  SWAP KR,SR
1551: 0A78  PRT.FUNC          ; function field (code from KR: blank)
1552: 19A0  JC 1622
1553: 0639  IO=-D EXP
1554: 1811  JC 154C
1555: 1631  JNC 123D
; ═══════════════════════════════════════════════════════════════════════════
; CP_CLEAR  (0x1556–0x1579, from CLEAR_MEM 11C3 with fA[8] set) — CP: t
; (SCOM[11]) := 0; from the keyboard also the return stack (SCOM[15]), SCOM[0]
; down to its Fix nibble, and all program registers: n = SCOM[9] nibble 0
; program-register decades, the top register 10n − 1 is converted to a binary
; RAM address in C (1570–1579) and 11D7–11DF clear registers C…0 with MEMWR,
; ten per pass. Inside a running program only t. CMs shares 1570–1579 (from
; 11D6). Traced on both: CP after 0 / 3 / 6 Op 17 clears the same registers.
; ═══════════════════════════════════════════════════════════════════════════
; Δ [REORG] TI-59 1334–1349 (CP) moved here unchanged; the TI-59 code that lived
; here (Op 16 / Op 17 partition) moved to 1775–17D3.
1556: 01DB  B=0 ALL           ; CP: t := 0 …
1557: 0328  A=C-1 DPT1        ; (C[0] = 0xC − 1 = 11 → SCOM[11])
1558: 0101  IO=A ALL
1559: 0A0F  STOF
155A: 0111  IO=B ALL
155B: 0008  TST fB[0]         ; running …
155C: 00D8  TST fB[13]        ; … or single step?
155D: 16FB  JNC 11E0          ; yes → only t
155E: 0AF7  MOV R5,#15        ; keyboard: SCOM[15] := 0 (return stack) …
155F: 01F0  A=R5 ALL
1560: 0101  IO=A ALL
1561: 0A0F  STOF
1562: 0111  IO=B ALL
1563: 00B9  SET fB[11]
1564: 0A1F  RCLF              ; … SCOM[0] := its Fix nibble only (step 000, flags off) …
1565: 02D3  B=LOAD DPT
1566: 0A0F  STOF
1567: 0111  IO=B ALL
1568: 0A97  MOV R5,#9         ; … SCOM[9] …
1569: 01F4  C=R5 ALL
156A: 0121  IO=C ALL
156B: 0A1F  RCLF
; Δ [HW] TI-59 134A–1363: no SCOM[9] security nibble to clear (no card reader,
; hence no protected memory), and the program registers are cleared one MEMWR at
; a time (11D7) instead of with RAM.OP's ten-register block clear.
156C: 01D0  A=LOAD ALL        ; … nibble 0 = program-register decades n
156D: 0308  A=A-1 DPT1        ; n = 0?
156E: 09F0  A=R5 MANT         ; (A[3] := n − 1)
156F: 171F  JNC 11E0          ; yes → no program memory to clear
1570: 0D00  A=A+1 MLSD1       ; top program register 10n − 1 (BCD; CMs enters here with its own)
                              ;   …
1571: 0940  A=SLA MANT
1572: 0D08  A=A-1 MLSD1
1573: 01DC  C=0 ALL           ; … converted to binary in C: count A down, C up
1574: 01DB  B=0 ALL
1575: 03D3  B=LOAD DPT1       ; B := 1
1576: 0D08  A=A-1 MLSD1
1577: 1741  JNC 11D7          ; done → clear registers C…0 (11D7, MEMWR)
1578: 0194  C=C+B ALL
1579: 1807  JC 1576
; ═══════════════════════════════════════════════════════════════════════════
; LIB_LABEL_SEARCH  (0x157A–0x15AE, from 0FB9 via 1333) — find a label inside
; the selected library program. Traced on both (Pgm 02, A). Reads the
; program's start and end addresses from the module header (2 BCD bytes per
; program from address 0002, LIB.PC ×4 to position, 158D–1597 reading high/low
; digits), positions the CROM PC at the program start (159C–15A1) and then
; walks the program byte by byte (15A2–15AE, never past its end: 15A3/15A4)
; through the same scanner loop as RAM programs (1284 → 0F79, scanner table
; 0E0D), which asks for the next byte via 0E9A → 11FE → 15A2. Found → commit
; the CROM PC (12B1–12B7, LIB.PC ×4).
; ═══════════════════════════════════════════════════════════════════════════
; Δ [REORG] TI-59 1364–1398 moved here unchanged; its next-byte entry (TI-59
; 103E–103F) moved to 11FE–11FF.
157A: 0101  IO=A ALL
157B: 0A1F  RCLF              ; SCOM[9] page = program number p …
157C: 09D0  A=LOAD MANT
157D: 0948  A=SRA MANT
157E: 0948  A=SRA MANT
157F: 0903  B=A MANT
1580: 0980  A=A+B MANT        ; … header offset 2p
1581: 0A37  MOV R5,#3
1582: 02F0  A=R5 DPT
1583: 06F0  A=R5 EXP
1584: 0948  A=SRA MANT
1585: 0A18  MOV KR[4..7],R5
1586: 0A1E  LIB.PC            ; CROM PC := 2p (header entry)
1587: 0308  A=A-1 DPT1
1588: 1809  JC 1584
1589: 05D0  A=LOAD LLSD1
158A: 03D8  A=-1 DPT1
158B: 0933  B=D MANT
158C: 01DE  D=0 ALL
158D: 0A3E  LIB.HI            ; read the start address (B) and the next program's start (end) …
158E: 0A0C  MOV KR,EXT[4..15]
158F: 0A08  MOV R5,KR[4..7]
1590: 02F6  D=R5 DPT
1591: 0176  D=SLD ALL
1592: 0A0E  LIB.IN
1593: 0A0C  MOV KR,EXT[4..15]
1594: 0A08  MOV R5,KR[4..7]
1595: 02F6  D=R5 DPT
1596: 0176  D=SLD ALL
1597: 1015  JNC 158D
1598: 0176  D=SLD ALL
1599: 0176  D=SLD ALL
159A: 0508  A=A-1 LLSD1
159B: 1823  JC 158A
159C: 0910  A=B MANT
159D: 0948  A=SRA MANT
159E: 0A18  MOV KR[4..7],R5
159F: 0A1E  LIB.PC            ; CROM PC := program start
15A0: 0708  A=A-1 EXP1
15A1: 1809  JC 159D
15A2: 0CD2  A<>B MAEX
15A3: 09B9  IO=A-D MANT       ; past the program's end?
15A4: 1F83  JC 11E3           ; yes → label not found (error, 11E3)
15A5: 0D03  B=A+1 MLSD1
15A6: 0A3E  LIB.HI            ; next byte: tens …
15A7: 0A0C  MOV KR,EXT[4..15]
15A8: 0A08  MOV R5,KR[4..7]
15A9: 06F6  D=R5 EXP
15AA: 0A0E  LIB.IN            ; … units
15AB: 0A0C  MOV KR,EXT[4..15]
15AC: 0A08  MOV R5,KR[4..7]
15AD: 02F6  D=R5 DPT
15AE: 1E55  JC 1284           ; → scanner (1284 → 0F79)
15AF: 01D7  A<>E ALL          ; Ins, later registers: E := address
15B0: 0920  A=C MANT
15B1: 09DB  B=0 MANT
15B2: 015B  B=SRB ALL         ; B := carry byte from the previous register
15B3: 0164  C=SLC ALL         ; C := register shifted up one keycode …
15B4: 0164  C=SLC ALL
15B5: 0194  C=C+B ALL         ; … with the carry in step 0
15B6: 1F31  JC 121E           ; → carry-out of this register's top keycode, write
; ═══════════════════════════════════════════════════════════════════════════
; FLAG_OP  (0x15B7–0x15DE, 176C) — St flg n / INV St flg n (and the flag test
; for If flg). Trace-confirmed for all ten flags (headless harness): user
; flag n is bit ⌊n/5⌋ of SCOM[0] nibble 11 + (n mod 5) — flags 0–4 bit 0 of
; nibbles 11–15, flags 5–9 bit 1. 15BE–15C5 split n into nibble and bit,
; 15C6–15C9 slide a one-digit mask into place, then the bit is added (set)
; or subtracted (INV, fB[8]) unless it is already in that state, and SCOM[0]
; is written back at 176C (in PGM_SELECT).
; ═══════════════════════════════════════════════════════════════════════════
; Δ [REORG] TI-59 15B4–15B9 (Op 09: pad the last register with 00) moved to 176F–1774.
15B7: 01D7  A<>E ALL          ; A := flag number
15B8: 0A77  MOV R5,#7
15B9: 09F6  D=R5 MANT
15BA: 0A1F  RCLF
15BB: 09D3  B=LOAD MANT
15BC: 0901  IO=A MANT
15BD: 09F0  A=R5 MANT
15BE: 0B09  IO=A-5 MLSD5      ; n ≥ 5?
15BF: 09B0  A=A+D MANT
15C0: 01D5  C<>D ALL
15C1: 0DD4  C=LOAD MLSD1
15C2: 1008  JNC 15C6          ; no → bit 0
15C3: 0B08  A=A-5 MLSD5       ; yes → n − 5, bit 1
15C4: 0D24  C=C+1 MLSD1
15C5: 07D4  C=LOAD EXP1
15C6: 095B  B=SRB MANT        ; slide to nibble 11 + n …
15C7: 0964  C=SLC MANT        ; … building the mask in C …
15C8: 0D08  A=A-1 MLSD1
15C9: 1807  JC 15C6
15CA: 09D2  A<>B MANT
15CB: 0729  IO=C-1 EXP1
15CC: 0948  A=SRA MANT
15CD: 0A18  MOV KR[4..7],R5   ; KR[4..7] := the flag nibble's current value
15CE: 0A1F  RCLF              ; A := SCOM[0]
15CF: 01D0  A=LOAD ALL
15D0: 01D5  C<>D ALL
15D1: 100E  JNC 15D8
15D2: 0A55  TST KR[5]         ; bit 1 currently set?
15D3: 180E  JC 15DA
15D4: 0088  TST fB[8]         ; INV (clear)?
15D5: 1E39  JC 12B9           ; set requested, already set → nothing to do
15D6: 09B8  A=A-D MANT        ; clear the bit
15D7: 180C  JC 15DD
15D8: 0A45  TST KR[4]         ; bit 0 currently set?
15D9: 100B  JNC 15D4
15DA: 0088  TST fB[8]
15DB: 1645  JNC 12B9          ; clear requested, already clear → nothing to do
15DC: 09B0  A=A+D MANT        ; set the bit
15DD: 0106  D=A ALL
15DE: 1B1C  JC 176C           ; → write SCOM[0] (176C)
15DF: 0099  SET fB[9]
15E0: 193C  JC 167E
; TRACE_OPERAND_LINE (0x15E1–0x15F7) — in TRACE mode an operation's operand
; gets a line of its own, digits right-aligned with leading zeros suppressed
; (loop until D = 0), and an Ind operand marked with '*' (code 41) to its
; left. Trace-checked (PC-100, TRACE on): "STO 01" → "1", "Op 06" → "6",
; "Pgm 19" → "19", "RCL Ind 01" → "*1".
15E1: 0A98  PRT.STEP
15E2: 0A0B  TST.BUSY
15E3: 1005  JNC 15E1
15E4: 0A88  PRT.CLR
15E5: 0906  D=A MANT          ; D := operand digits
15E6: 0A0C  MOV KR,EXT[4..15] ; next digit, rightmost first: code = digit + 1 …
15E7: 0931  IO=D MANT
15E8: 0A18  MOV KR[4..7],R5
15E9: 0A04  INC KR
15EA: 097E  D=SRD MANT
15EB: 0A68  PRT.OUT           ; … printed
15EC: 0939  IO=-D MANT        ; more digits?
15ED: 100F  JNC 15E6
15EE: 0070  TST fA[7]         ; Ind?
15EF: 00A2  CLR fA[10]
; Δ [ENH] TI-59 15F3 went straight to PRT.GO. Here 15F0 → 17D4–17E9 → 14EB–14EE:
; on the address line of x=t, x≥t or If flg whose condition is met (the branch
; is taken) a ▴ (code 61) is printed left of the address; label operands
; (fA[0], also entering at 15EF from 11F4) continue at 1165 → 0E0F. Traced with
; TRACE (flag 9): "INV x=t 009" prints "▴9", a false x=t prints "9"; Dsz is
; never marked.
15F0: 1BC8  JC 17D4           ; no Ind → conditional marker check (17D4), back at 14EB / 14EC
15F1: 0A97  MOV R5,#9         ; yes: '*' (9 + KR[9]·32 = 41)
15F2: 0095  SET KR[9]
15F3: 0A18  MOV KR[4..7],R5
15F4: 0A68  PRT.OUT
15F5: 00A1  SET fA[10]
15F6: 0AA8  PRT.GO            ; print the line
15F7: 1EEB  JC 1282           ; → continue the sequence (1282 → 0E8B)
15F8: 01D2  A<>B ALL
15F9: 01B8  A=A-D ALL         ; register − old keycode
15FA: 01D2  A<>B ALL
15FB: 014E  D=SRA ALL
; Δ [REORG] TI-59 15FF: the third SRD now follows D=0 MANT (15FF), so D keeps
; two nibbles instead of three (nibble 2 cleared). LRN stores traced identical.
15FC: 017E  D=SRD ALL
15FD: 017E  D=SRD ALL
15FE: 09DE  D=0 MANT
15FF: 017E  D=SRD ALL
1600: 0A08  MOV R5,KR[4..7]   ; byte index (0–7) of the step within its register …
; Δ [HW] TI-59 1605–1606: the byte-position counter runs in A's EXP field
; (nibbles 1–2) instead of A[0]. On the TI-58C A[0] (with A[3]) carries the
; binary raw RAM address of the program register, which 0C16–0C18 assemble
; for MEMWR; the TI-59 RAM.OP address sat in nibbles 2–3 and left A[0] free.
1601: 06F0  A=R5 EXP          ; … as a count in A[1..2] (A[0] keeps the RAM address)
1602: 0708  A=A-1 EXP1        ; one byte position …
1603: 15A5  JNC 1331          ; done → write the register (1331 → 0FCB → 0C16)
1604: 0176  D=SLD ALL         ; … = two keycode nibbles: move the new keycode up
1605: 0176  D=SLD ALL
1606: 1809  JC 1602
1607: 01D5  C<>D ALL
1608: 0639  IO=-D EXP
1609: 1834  JC 1623
160A: 179B  JNC 123D
160B: 01D5  C<>D ALL
160C: 0E29  IO=C-1 MMSD1
160D: 100D  JNC 1607
160E: 0A98  PRT.STEP
160F: 0A0B  TST.BUSY
1610: 1005  JNC 160E
1611: 0A88  PRT.CLR
1612: 0A1F  RCLF
1613: 06D3  B=LOAD EXP
1614: 07D4  C=LOAD EXP1
1615: 0A0C  MOV KR,EXT[4..15]
1616: 0611  IO=B EXP
1617: 0A18  MOV KR[4..7],R5
1618: 0A04  INC KR
1619: 065B  B=SRB EXP
161A: 0A68  PRT.OUT
161B: 072C  C=C-1 EXP1
161C: 180F  JC 1615
161D: 0A0D  SWAP KR,SR
161E: 0A18  MOV KR[4..7],R5
161F: 0A0D  SWAP KR,SR
1620: 01D5  C<>D ALL
1621: 0A98  PRT.STEP
1622: 0A98  PRT.STEP          ; spacing column
1623: 0106  D=A ALL           ; keep the display image
1624: 0098  TST fB[9]         ; error pending?
1625: 1810  JC 162D
1626: 0A0C  MOV KR,EXT[4..15]
1627: 0A97  MOV R5,#9         ; yes: '?' (code 9 + 16 + 32 = 57) in the column after the number
                              ;   — "9.9999999 99?" for an overflow (trace-checked)
1628: 0A18  MOV KR[4..7],R5
1629: 0085  SET KR[8]
162A: 0095  SET KR[9]
162B: 0A68  PRT.OUT
162C: 1804  JC 162E
162D: 0A98  PRT.STEP
162E: 0A0C  MOV KR,EXT[4..15]
162F: 00F8  TST fB[15]        ; sci …
1630: 0078  TST fB[7]         ; … or eng display: print the exponent field
1631: 100A  JNC 1636
1632: 0709  IO=A-1 EXP1       ; (exponent field)
1633: 1806  JC 1636
1634: 0A78  PRT.FUNC
1635: 181A  JC 1642
1636: 0219  IO=-B DPT         ; exponent digits, rightmost first (code = digit + 1)
1637: 0648  A=SRA EXP
1638: 0A18  MOV KR[4..7],R5
1639: 0A04  INC KR
163A: 0601  IO=A EXP
163B: 0A68  PRT.OUT
163C: 1009  JNC 1638
163D: 0030  TST fA[3]         ; exponent negative?
163E: 0A0C  MOV KR,EXT[4..15]
163F: 1804  JC 1641
1640: 0085  SET KR[8]         ; yes: '-' (code 16) in front, else blank: "1.5-03", "1.5 03"
1641: 0A68  PRT.OUT
1642: 0130  A=D ALL           ; digit loop over the display image (rightmost first):
1643: 0308  A=A-1 DPT1        ; fraction digits left before the point …
1644: 0A0C  MOV KR,EXT[4..15]
1645: 180A  JC 164A
1646: 0095  SET KR[9]         ; … none: the decimal point, code 32
1647: 02DB  B=0 DPT
1648: 0A68  PRT.OUT
1649: 0A0C  MOV KR,EXT[4..15]
164A: 0D09  IO=A-1 MLSD1      ; digits left?
164B: 1806  JC 164E
164C: 0219  IO=-B DPT
164D: 1F25  JC 12BB           ; no → sign and print (0EE8)
164E: 0948  A=SRA MANT        ; next digit into R5 …
164F: 0A18  MOV KR[4..7],R5
1650: 0A04  INC KR            ; … code = digit + 1
1651: 0219  IO=-B DPT
1652: 0A68  PRT.OUT
1653: 1021  JNC 1643
1654: 0CDB  B=0 MAEX
1655: 1825  JC 1643
; Δ [ENH] new (no TI-59 counterpart): part of the self-test SCOM check (16C7);
; phase 2 steps to the next row and writes the complement pattern there.
1656: 0300  A=A+1 DPT1        ; SELF-TEST phase 2: next SCOM row …
1657: 0708  A=A-1 EXP1        ; … rows left?
1658: 1934  JC 16F2           ; yes → write the complement pattern into it (16F2)
1659: 15CB  JNC 1374          ; all eight rows passed → next test (1374 → 10BF → 0DC3)
; ═══════════════════════════════════════════════════════════════════════════
; PRINT_OPS  (0x165A–0x167F, 0x16F6–0x1738) — Op 00–07 (from the print-op
; sequence 053F); code ≥ 8 (Op 16/17 arrive as 9 via 07F7) → PARTITION 1775.
; Trace-confirmed (headless, printer attached):
;   Op 00 clear, Op 01–04 load, Op 05 print the 20-column alphanumeric
;   buffer, which lives in SCOM[5]–[8] (Op 01 → SCOM[5], … Op 04 → SCOM[8]),
;   5 characters = 10 digits each — the same rows as AOS levels 5–8.
;   Characters are TI two-digit codes, octal-like: printer code =
;   tens·8 + units (13 → 'A', 24 → 'I', 17 → 'E', 36 → 'S'; 171C–172C).
;   Op 06 prints X followed by the last four Op 04 characters (1711, 1732);
;   checked: Op 04 with 1324173600, 42 Op 06 → "42.    IES ".
;   Op 07 plots: '*' (code 41) at column Int(X), 0–19 (1667–167D).
; Without a printer the ops do nothing (KEY [P] at D10, 1661).
; ═══════════════════════════════════════════════════════════════════════════
165A: 0103  B=A ALL
165B: 01D7  A<>E ALL
165C: 0901  IO=A MANT         ; Op number → R5 …
165D: 02F6  D=R5 DPT
165E: 0A18  MOV KR[4..7],R5   ; … KR[4..7]
165F: 0A75  TST KR[7]         ; Op ≥ 8 → PARTITION (Op 16/17)
1660: 122A  JNC 1775          ; → PARTITION 1775 (TI-59: card/partition prefix 1680)
; Δ [HW] TI-59 1661: printer-present is sensed on KP at digit 10 (WAIT D11 +
; KEY [P]) instead of digit 0 (WAIT D1), as everywhere on the TI-58C.
1661: 0AB0  WAIT D11          ; printer present? (the next instruction samples digit 10)
1662: 08FB  KEY [P]
1663: 1836  JC 167E           ; no → nothing
1664: 0A04  INC KR            ; Op 07 → KR[7] (8)?
1665: 0A75  TST KR[7]
1666: 1920  JC 16F6           ; Op 00–06 → 16F6
1667: 0619  IO=-B EXP         ; Op 07 PLOT: X must be 0 ≤ X < 20 …
1668: 0030  TST fA[3]
1669: 0020  TST fA[2]
166A: 1117  JNC 15DF
166B: 0AE7  MOV R5,#14
166C: 09F0  A=R5 MANT
166D: 0B00  A=A+5 MLSD5
166E: 0988  A=A-B MANT
166F: 1121  JNC 15DF
1670: 0A0C  MOV KR,EXT[4..15]
1671: 0095  SET KR[9]
1672: 0075  SET KR[7]
1673: 0045  SET KR[4]         ; '*' = code 41 (KR[4]+KR[7]+KR[9])
1674: 0A98  PRT.STEP          ; wait for the printer …
1675: 0A0B  TST.BUSY
1676: 1005  JNC 1674
1677: 0A88  PRT.CLR
1678: 0D08  A=A-1 MLSD1       ; skip X columns …
1679: 1006  JNC 167C
167A: 0A98  PRT.STEP
167B: 1807  JC 1678
167C: 0A68  PRT.OUT           ; the asterisk
167D: 0AA8  PRT.GO
167E: 0110  A=B ALL
; Common exit of the print ops and PARTITION (167E, 1702, 17D3): → 1330 →
; 11F3 → display. Δ [REORG] TI-59 167F JC 15AB: one more hop, as the display
; exit is out of branch range.
167F: 1E9F  JC 1330           ; → 1330 → 11F3 (display)
; ═══════════════════════════════════════════════════════════════════════════
; SELFTEST_MEMORY  (0x1680–0x16F5, 0x1656–0x1659) — tests 4, 5 and 6 of the
; TI-58C factory self-test (sequencer 0DB7 with table 0C01–0C0A, started by
; the KN line at digit 15 in the idle loop, 064A, or a KN "key" at rows 8–11,
; 0661). Trace-confirmed (headless, LIB.h_press(m.h, 0, 15)):
;   test 4 (0C04 → 0FFA → 138D → 16C7): SCOM rows 0–7;
;   test 5 (0C05 → 0FF5–0FF8 → 138F → 16C8, A[0] = 8): SCOM rows 8–15;
;   test 6 (0C06 → 0FFB → 138E → 1680): every raw RAM register, top (0x3F)
;   down to 0, through MEMWR/MEMRD — the 60 user registers and E000–E003.
; Pattern 6969…69 (bits 0110/1001 alternate: a checkerboard), then its
; complement 9696…96; both are valid BCD, so B = C − D compares exactly.
; SCOM (KR[7] clear): write the pattern into all eight rows, read all back,
; then per row write the complement and read it back (KR[4] = phase 2).
; RAM (KR[7] set): clear all, per register check 0 and write the pattern,
; read all back, then per register write the complement and read it back
; (KR[11] = phase 2). Pass → 1374 → 10BF → 0DC3 (print the next number);
; a mismatch → 136F → 10BE → 0DD6 → 09DD → cold restart (checked with a ROM
; patch: the printout ends at the failing test's number). The tests leave
; SCOM and RAM filled with 9696…; test 10 later writes each RAM register's
; index, so the self-test destroys the constant memory (E000 included).
; Δ [ENH] TI-58C only: replaces the TI-59 magnetic-card code (CARD_IO,
; TI-59 1680–17AB), which the TI-58C does not need (no card reader).
; ═══════════════════════════════════════════════════════════════════════════
1680: 06D7  A<>E EXP          ; RAM test (test 6): A[1..2] := E[1..2] = SCOM[9] nibbles 1–2
                              ;   (high nibble of the top raw address, from the sequencer 0DBC)
1681: 0AF7  MOV R5,#15        ; C := 0x0F …
1682: 01F4  C=R5 ALL
1683: 0604  C=A EXP           ; … + high nibble → C[1..0] = top raw RAM address (0x3F; 0x7F with
                              ;   128 registers)
1684: 01DB  B=0 ALL           ; B := 1, the address step
1685: 03D3  B=LOAD DPT1
1686: 0121  IO=C ALL          ; CLEAR all RAM, top down: address on the bus …
1687: 0A76  MEMWR             ; … MEMWR: the next instruction does not drive the bus, so the
                              ;   register is written 0
1688: 019C  C=C-B ALL         ; next address (nibble 0 counts in hex: 3F, 3E … 30, 2F …)
1689: 1807  JC 1686           ; down to 0x00
168A: 0A77  MOV R5,#7         ; D[1..2] := 07 …
168B: 06F6  D=R5 EXP
168C: 0AE7  MOV R5,#14        ; KR[4..7] := 14: KR[7] selects the RAM path at 16D5; 14 is also
                              ;   the code of 'D'
168D: 0A18  MOV KR[4..7],R5
168E: 06B9  IO=A-D EXP        ; address code ≥ 07 (a 128-register RAM)?
168F: 100E  JNC 1696          ; no (the TI-58C's 03) → 1696
1690: 0A98  PRT.STEP          ; yes: print "D" (code 14) in the rightmost column first —
                              ;   verified with a 128-register harness build
1691: 0A0B  TST.BUSY
1692: 1005  JNC 1690
1693: 0A88  PRT.CLR
1694: 0A68  PRT.OUT
1695: 0AA8  PRT.GO
1696: 06D7  A<>E EXP          ; restore A[1..2] / E[1..2]
1697: 1862  JC 16C8           ; → build the pattern (16C8), continues at 1698
; RAM phase 1 (from 16D6): per register, top down: must read 0 (cleared at
; 1686), then write the pattern 6969….
1698: 0AF7  MOV R5,#15        ; C := top raw address again (as 1681–1683, via E)
1699: 01F4  C=R5 ALL
169A: 06D7  A<>E EXP
169B: 0604  C=A EXP
169C: 06D7  A<>E EXP
169D: 0130  A=D ALL           ; A := pattern 6969…69
169E: 0121  IO=C ALL          ; address on the bus …
169F: 0A86  MEMRD             ; … MEMRD …
16A0: 01D6  D=LOAD ALL        ; … D := RAM register
16A1: 0139  IO=-D ALL         ; not 0?
16A2: 1667  JNC 136F          ; yes → FAIL (136F → 10BE)
16A3: 0121  IO=C ALL          ; address …
16A4: 0A76  MEMWR             ; … MEMWR …
16A5: 0101  IO=A ALL          ; … data: RAM register := pattern
16A6: 019C  C=C-B ALL         ; next address
16A7: 1813  JC 169E           ; down to 0x00
; RAM phase 2: read every register back against the pattern (KR[11]
; clear); phase 3 (KR[11] set): per register write the complement 9696…,
; read it back.
16A8: 0AF7  MOV R5,#15        ; C := top raw address
16A9: 01F4  C=R5 ALL
16AA: 06D7  A<>E EXP
16AB: 0604  C=A EXP
16AC: 06D7  A<>E EXP
16AD: 0AB5  TST KR[11]        ; phase 3?
16AE: 102A  JNC 16C3          ; yes → write the complement first (16C3)
16AF: 0121  IO=C ALL          ; address …
16B0: 0A86  MEMRD             ; … MEMRD …
16B1: 01D6  D=LOAD ALL        ; … D := RAM register
16B2: 1802  JC 16B3 ; clear COND
16B3: 01BE  D=A-D ALL         ; pattern − read …
16B4: 0139  IO=-D ALL         ; … ≠ 0?
16B5: 168D  JNC 136F          ; yes → FAIL (136F → 10BE)
16B6: 019C  C=C-B ALL         ; next address
16B7: 1815  JC 16AD           ; down to 0x00
16B8: 0AB5  TST KR[11]        ; phase 3 done?
16B9: 168B  JNC 1374          ; yes → RAM test passed (1374 → 10BF → 0DC3)
16BA: 0140  A=SLA ALL         ; A := complement 9696…96 (shift left, low nibble 6)
16BB: 0A67  MOV R5,#6
16BC: 02F0  A=R5 DPT
16BD: 00B5  SET KR[11]        ; phase 3
16BE: 0AF7  MOV R5,#15        ; C := top raw address
16BF: 01F4  C=R5 ALL
16C0: 06D7  A<>E EXP
16C1: 0604  C=A EXP
16C2: 06D7  A<>E EXP
16C3: 0121  IO=C ALL          ; address …
16C4: 0A76  MEMWR             ; … MEMWR …
16C5: 0101  IO=A ALL          ; … data: RAM register := complement
16C6: 182F  JC 16AF           ; → read it back (16AF)
; SCOM test entries: 16C7 (test 4, from 138D) starts at row 0; 16C8 (test 5,
; from 138F) starts at row A[0] = 8. A[3] keeps the first row for the rewinds.
; 16C8 also builds the pattern for the RAM test (from 1697).
16C7: 01D8  A=0 ALL           ; test 4: first row 0
16C8: 0A77  MOV R5,#7         ; PATTERN: C[0] := 7 (8 passes) …
16C9: 02F4  C=R5 DPT
16CA: 06F0  A=R5 EXP          ; A[1..2] := 7: eight rows to verify
16CB: 06F4  C=R5 EXP          ; C[1..2] := 7: eight rows to write
16CC: 01DE  D=0 ALL           ; D := 0 …
16CD: 0176  D=SLD ALL         ; … shift in 6 …
16CE: 0A67  MOV R5,#6
16CF: 02F6  D=R5 DPT
16D0: 0176  D=SLD ALL         ; … and 9 …
16D1: 0A97  MOV R5,#9
16D2: 02F6  D=R5 DPT
16D3: 032C  C=C-1 DPT1        ; … eight times: D = 6969696969696969
16D4: 180F  JC 16CD
16D5: 0A75  TST KR[7]         ; RAM test (KR[7] set, 168D)?
16D6: 107D  JNC 1698          ; yes → RAM phase 1 (1698)
16D7: 0101  IO=A ALL          ; SCOM phase 1: SCOM[A[0]] := pattern …
16D8: 0A0F  STOF
16D9: 0131  IO=D ALL
16DA: 0300  A=A+1 DPT1        ; … next row …
16DB: 072C  C=C-1 EXP1        ; … eight rows
16DC: 180B  JC 16D7
16DD: 0901  IO=A MANT         ; R5 := A[3] (the first row) …
16DE: 02F0  A=R5 DPT          ; … A[0] := first row: rewind
16DF: 0101  IO=A ALL          ; VERIFY: C := SCOM[A[0]] …
16E0: 0A1F  RCLF
16E1: 01D4  C=LOAD ALL
16E2: 01AB  B=C-D ALL         ; … − D …
16E3: 0119  IO=-B ALL         ; … ≠ 0?
16E4: 16EB  JNC 136F          ; yes → FAIL (136F → 10BE)
16E5: 0A45  TST KR[4]         ; phase 2 (KR[4])?
16E6: 1121  JNC 1656          ; yes → next row (1656)
16E7: 0300  A=A+1 DPT1        ; phase 1: next row …
16E8: 0708  A=A-1 EXP1        ; … eight rows
16E9: 1815  JC 16DF
16EA: 0176  D=SLD ALL         ; phase 2: D := complement 9696…96 …
16EB: 0A67  MOV R5,#6
16EC: 02F6  D=R5 DPT
16ED: 0045  SET KR[4]         ; … KR[4] := phase 2
16EE: 0A77  MOV R5,#7         ; A[1..2] := 7 rows left after this one
16EF: 06F0  A=R5 EXP
16F0: 0901  IO=A MANT         ; rewind to the first row (R5 := A[3]) …
16F1: 02F0  A=R5 DPT
16F2: 0101  IO=A ALL          ; SCOM[A[0]] := complement (also from 1658) …
16F3: 0A0F  STOF
16F4: 0131  IO=D ALL
16F5: 182D  JC 16DF           ; … → read it back (16DF)
; PRINT_OPS, continued: Op 00–06 (from 1666).
16F6: 0508  A=A-1 LLSD1       ; Op 00–05: Op 01–04 → SCOM[4 + n] := X digits (16FD–1700) …
16F7: 0A18  MOV KR[4..7],R5
16F8: 0A47  MOV R5,#4
16F9: 02F0  A=R5 DPT
16FA: 1012  JNC 1703          ; Op 00 → clear SCOM[5]–[8] (1703–170A)
16FB: 0A65  TST KR[6]         ; Op 05 → print (170B)
16FC: 101E  JNC 170B
16FD: 02B6  D=A+D DPT
16FE: 0131  IO=D ALL
16FF: 0A0F  STOF
1700: 0111  IO=B ALL
1701: 01D7  A<>E ALL
1702: 1907  JC 167F           ; → 167F → 1330 → display. Δ [REORG] TI-59 17B8 JC 15AB
1703: 0A0C  MOV KR,EXT[4..15]
1704: 0300  A=A+1 DPT1
1705: 0101  IO=A ALL
1706: 0A0F  STOF
1707: 0A04  INC KR
1708: 0A65  TST KR[6]
1709: 180B  JC 1704
170A: 1013  JNC 1701
170B: 0A98  PRT.STEP          ; Op 05: wait for the printer …
170C: 0A0B  TST.BUSY
170D: 1005  JNC 170B
170E: 0A88  PRT.CLR
170F: 0A45  TST KR[4]         ; Op 06?
1710: 1804  JC 1712           ; no (Op 05) → all four rows
1711: 0011  SET fA[1]         ; Op 06: fA[1] = only row 8 (Op 04), and X to its left
1712: 0A87  MOV R5,#8         ; rows 8, 7, 6, 5 (right to left) …
1713: 02F0  A=R5 DPT
1714: 0101  IO=A ALL
1715: 0A1F  RCLF
1716: 09D0  A=LOAD MANT
1717: 0A47  MOV R5,#4
1718: 06F0  A=R5 EXP
1719: 0010  TST fA[1]
171A: 1804  JC 171C
171B: 0708  A=A-1 EXP1        ; Op 06: only the rightmost four characters
171C: 0A0C  MOV KR,EXT[4..15] ; next character: tens digit → KR[8..9] (·8) …
171D: 0948  A=SRA MANT
171E: 06F6  D=R5 EXP
171F: 0948  A=SRA MANT
1720: 0A18  MOV KR[4..7],R5
1721: 0A55  TST KR[5]
1722: 1804  JC 1724
1723: 0085  SET KR[8]
1724: 0A65  TST KR[6]
1725: 1804  JC 1727
1726: 0095  SET KR[9]
1727: 0A45  TST KR[4]
1728: 0636  D=D EXP
1729: 0A18  MOV KR[4..7],R5   ; … units digit → KR[4..6]
172A: 1804  JC 172C
172B: 0075  SET KR[7]
172C: 0A68  PRT.OUT
172D: 0708  A=A-1 EXP1        ; five characters per row
172E: 1825  JC 171C
172F: 0010  TST fA[1]         ; Op 06?
1730: 0051  SET fA[5]
1731: 01D2  A<>B ALL
1732: 121F  JNC 1623          ; yes → X to the left of them and print (1623)
1733: 01D2  A<>B ALL
1734: 0308  A=A-1 DPT1        ; next row
1735: 02B9  IO=A-D DPT
1736: 1845  JC 1714
1737: 0AA8  PRT.GO            ; print the line
1738: 186F  JC 1701
1739: 0099  SET fB[9]         ; Op 17 (from 1787): more data decades than RAM → ERROR …
; Δ [REORG] TI-59 17EF–17F0, unchanged; it now lies right after the print
; ops because the card code between them is gone.
173A: 18F8  JC 17B6           ; … display the unchanged partition (17B6)
; PGM_SELECT: Pgm nn. Save the CROM PC (LIB.PC.IN ×4 → B), point it at the
; module header (LIB.PC ×4 with 0000), read byte 0 = number of programs N,
; restore the CROM PC, and check nn against N: out of range → error (1413,
; as the garbage run's "Pgm 51" in examples/texas-print.ti59). From the
; keyboard nn becomes the current library page in SCOM[9]; in a program it
; applies to the next SBR / label only (13C6). Entered from the Pgm sequence
; slot 105F via 1416 (two hops: out of branch range). Trace-confirmed
; (coverage pgm01, pgm_select, pgm_sbr).
; Δ [REORG] TI-59 12E1–1314, moved here unchanged; only the exits differ:
; 1761 → 1413, 1764 → 13C6, 176E → 1415 → 12B9. Its store tail 176B–176E is
; shared with Pgm-in-a-program (13CE) and FLAG_OP (15DE), as at TI-59 1311.
173B: 01D7  A<>E ALL          ; A := nn
173C: 0A37  MOV R5,#3
173D: 02F0  A=R5 DPT
173E: 015B  B=SRB ALL
173F: 0A2E  LIB.PC.IN         ; save the CROM PC, one digit per read …
1740: 0A0C  MOV KR,EXT[4..15]
1741: 0A08  MOV R5,KR[4..7]
1742: 09F3  B=R5 MANT
1743: 0308  A=A-1 DPT1
1744: 180D  JC 173E
1745: 0A0E  LIB.IN
1746: 0A0C  MOV KR,EXT[4..15]
1747: 0A37  MOV R5,#3
1748: 02F0  A=R5 DPT
1749: 0A0C  MOV KR,EXT[4..15] ; CROM PC := 0000 (module header) …
174A: 0A1E  LIB.PC
174B: 0A1E  LIB.PC
174C: 0A1E  LIB.PC
174D: 0A1E  LIB.PC
174E: 0A3E  LIB.HI            ; byte 0: number of programs N …
174F: 0A0C  MOV KR,EXT[4..15]
1750: 0A08  MOV R5,KR[4..7]
1751: 09F6  D=R5 MANT
1752: 0A0E  LIB.IN
1753: 0A0C  MOV KR,EXT[4..15]
1754: 0A08  MOV R5,KR[4..7]
1755: 06F6  D=R5 EXP
1756: 0676  D=SLD EXP
1757: 0176  D=SLD ALL
1758: 0211  IO=B DPT
1759: 0A18  MOV KR[4..7],R5
175A: 015B  B=SRB ALL
175B: 0A1E  LIB.PC            ; restore the saved CROM PC …
175C: 0308  A=A-1 DPT1
175D: 180B  JC 1758
175E: 09BE  D=A-D MANT        ; nn vs N
175F: 1006  JNC 1762
1760: 0939  IO=-D MANT
1761: 169D  JNC 1413          ; out of range → error halt (1413)
1762: 0008  TST fB[0]         ; called from a running program …
1763: 00D8  TST fB[13]
1764: 173D  JNC 13C6          ; … yes → one-shot selection (13C6)
1765: 0A97  MOV R5,#9         ; keyboard: SCOM[9] page := nn
1766: 02F0  A=R5 DPT
1767: 0101  IO=A ALL
1768: 0A1F  RCLF
1769: 01D6  D=LOAD ALL
176A: 0906  D=A MANT
176B: 0101  IO=A ALL          ; (entry from 13CE: SCOM[A[0]] := D)
176C: 0A0F  STOF              ; SCOM[9] := new library page (FLAG_OP enters here from 15DE:
                              ;   SCOM[0] := D)
176D: 0131  IO=D ALL
176E: 1EB3  JC 1415           ; → 1415 → 12B9 (A := X, common exit)
; Op 09 (download): program end inside this register (from 14DD).
; Δ [REORG] TI-59 15B4–15B9, moved here unchanged.
176F: 0051  SET fA[5]         ; program end inside this register: last one
1770: 0308  A=A-1 DPT1        ; pad the remaining bytes with 00 …
1771: 1523  JNC 14E0          ; … → reverse and write (14E0)
1772: 0164  C=SLC ALL
1773: 0164  C=SLC ALL
1774: 180B  JC 176F
; ═══════════════════════════════════════════════════════════════════════════
; PARTITION  (0x1775–0x17D3, error 0x1739) — Op 17 (repartition) and Op 16
; (fB[14] set: show only, 177C). Entered from the print-op dispatch (1660).
; n = Int(X) data-register decades, at most 10 and at most all of RAM
; (1786/1787 → 1739 error otherwise; 7 Op 17 errors, the partition stays).
; Program registers = (top + 1) − 10n (top = 59, SCOM[13] nibbles 3–5); their
; decades are written to SCOM[13] nibbles 8–9 (17A3–17A5), SCOM[9] nibble 0
; (17AC/17AD) and E000 nibbles 1–2 (17AE–17B5: constant memory, so the
; partition survives power-off); fB[11] forces a cache reload when the
; current step moved outside (1794). The display shows
; "steps−1 . registers−1" (17B6–17CF: 8 steps per program register).
; Trace-confirmed (TI-58C): power-on 239.29, 2 Op 17 → 319.19 (E000 …040),
; 0 Op 17 → 479., 1.5 Op 17 → 399.09, 6 Op 17 → 0.59; after a power cycle
; Op 16 still shows 399.09.
; Δ [HW] TI-59 1556–15AB (+ the TI-59 entry 1680–1689 in the card code).
; New: the E000 update 17AE–17B5 (constant memory), and 1792 keeps the new
; program decades in A for it. Dropped: the TI-59 test of SCOM[9] nibble 2
; (memory protected by a protected magnetic card) at TI-59 1558, which made
; Op 17 act as Op 16 on a protected TI-59 (verified: read protected card,
; 2 Op 17 → 479.59 unchanged; after CP → 799.19). No cards, no protection.
; ═══════════════════════════════════════════════════════════════════════════
1775: 00E8  TST fB[14]        ; Op 16?
1776: 01D7  A<>E ALL          ; A := X (n); TI-59: at the card entry 1680
1777: 00EA  CLR fB[14]
1778: 0323  B=C+1 DPT1        ; SCOM[13] (top register nibbles 3–5, partition 8–9) → C
1779: 0111  IO=B ALL
177A: 0A1F  RCLF
177B: 01D4  C=LOAD ALL
177C: 1074  JNC 17B6          ; Op 16 → just display the current partition
177D: 0C48  A=SRA MAEX
177E: 0D09  IO=A-1 MLSD1      ; n …
177F: 1004  JNC 1781
1780: 0DD0  A=LOAD MLSD1
1781: 0C4B  B=SRA MAEX
1782: 0D20  A=C+1 MLSD1       ; (top + 1) ÷ 10 = RAM decades (6) …
1783: 0C48  A=SRA MAEX
1784: 0C48  A=SRA MAEX
1785: 0C48  A=SRA MAEX
1786: 068B  B=A-B EXP         ; … more than RAM allows?
1787: 109D  JNC 1739          ; yes → error (1739)
1788: 02F6  D=R5 DPT
1789: 0606  D=A EXP
178A: 0A1F  RCLF              ; A := SCOM[0] (177E put row 0 on the bus) …
178B: 09D0  A=LOAD MANT
178C: 0C48  A=SRA MAEX
178D: 0C48  A=SRA MAEX
178E: 0C48  A=SRA MAEX
178F: 0C48  A=SRA MAEX
1790: 0C48  A=SRA MAEX        ; … A[1..2] = step counter nibbles 6–7: the current register ÷ 10
1791: 0689  IO=A-B EXP        ; at or above the new program decades (outside the program area)?
1792: 0610  A=B EXP           ; A[1..2] := new program decades, for E000 (17B2)
1793: 1004  JNC 1795
1794: 00B9  SET fB[11]        ; yes: program cache must be reloaded
1795: 0C53  B=SLB MAEX
1796: 0919  IO=-B MANT
1797: 0A07  MOV R5,#0
1798: 1804  JC 179A
1799: 0AA7  MOV R5,#10        ; cap at 10 decades (100 data registers; only reachable with a
                              ;   128-register RAM)
179A: 02F0  A=R5 DPT
179B: 0C53  B=SLB MAEX
179C: 02B6  D=A+D DPT
179D: 0953  B=SLB MANT
179E: 0956  D=SLB MANT
179F: 0C76  D=SLD MAEX
17A0: 0C76  D=SLD MAEX
17A1: 0974  C=SLD MANT
17A2: 0D2C  C=C-1 MLSD1
17A3: 0111  IO=B ALL
17A4: 0A0F  STOF              ; SCOM[13] := new partition (nibbles 8–9)
17A5: 0121  IO=C ALL
17A6: 0A97  MOV R5,#9         ; SCOM[9] …
17A7: 02F3  B=R5 DPT
17A8: 0111  IO=B ALL
17A9: 0A1F  RCLF
17AA: 0CD6  D=LOAD MAEX
17AB: 0111  IO=B ALL
17AC: 0A0F  STOF              ; SCOM[9] := new partition (nibble 0)
17AD: 0131  IO=D ALL
; Δ [HW] new: write the partition into the constant memory — E000 (raw RAM
; 0x3C = SCOM[9] nibble 1 · 16 + 0xC) nibbles 1–2, read back by the power-on
; restore (0381–03A6). Trace-confirmed: 2 Op 17 → E000 = 2302585092994040.
17AE: 04D6  D=LOAD DPTC       ; D[1..0] := SCOM[9] nibble 1, 0xC = raw address of E000 (0x3C)
17AF: 0131  IO=D ALL          ; address …
17B0: 0A86  MEMRD             ; … MEMRD …
17B1: 01D3  B=LOAD ALL        ; … B := E000 (signature, partition, Fix)
17B2: 0603  B=A EXP           ; B[1..2] := new program decades (1792)
17B3: 0131  IO=D ALL          ; address …
17B4: 0A76  MEMWR             ; … MEMWR …
17B5: 0111  IO=B ALL          ; … data: E000 := B
17B6: 0D24  C=C+1 MLSD1       ; display: steps = 8 · program registers … (Op 16 and the error
                              ;   join here)
17B7: 016C  C=SRC ALL
17B8: 016C  C=SRC ALL
17B9: 016C  C=SRC ALL
17BA: 096C  C=SRC MANT
17BB: 016E  D=SRC ALL
17BC: 017E  D=SRD ALL
17BD: 017E  D=SRD ALL
17BE: 06AC  C=C-D EXP
17BF: 0926  D=C MANT
17C0: 09A4  C=C+D MANT
17C1: 09A6  D=C+D MANT
17C2: 09A4  C=C+D MANT
17C3: 09A4  C=C+D MANT
17C4: 0D2C  C=C-1 MLSD1       ; … − 1 . data registers − 1
17C5: 1804  JC 17C7
17C6: 09DC  C=0 MANT
17C7: 0729  IO=C-1 EXP1
17C8: 0C64  C=SLC MAEX
17C9: 1004  JNC 17CB
17CA: 0F2C  C=C-1 MAEX1
17CB: 096C  C=SRC MANT
17CC: 0C64  C=SLC MAEX
17CD: 0C60  A=SLC MAEX
17CE: 0A27  MOV R5,#2
17CF: 02F0  A=R5 DPT
17D0: 0022  CLR fA[2]
17D1: 005A  CLR fB[5]
17D2: 0032  CLR fA[3]
17D3: 1AA9  JC 167F           ; show it (→ 167F → 1330 → display)
; ═══════════════════════════════════════════════════════════════════════════
; TRACE_TRANSFER_MARK  (0x17D4–0x17E9) — end of TRACE_OPERAND_LINE (15F0, not
; Ind): when the operand is the address of a conditional transfer that will
; be taken, put '▴' (PC-100 code 61) to the left of it. The operation is told
; by its continuation slot in SR: 0x0C0 (x=t), 0x0BC (x≥t), 0x0B8 (If flg)
; pass the bit test (slot bits 0, 1, 8 clear; bit 6 clear unless bits 2–5
; are); Dsz (0x0F8), GTO, SBR, flag numbers and register operands do not.
; fB[8] clear = the transfer is taken. Exit through 14EB/14EC (PRT.GO 15F6,
; or with fA[0] the label-name path 1165).
; Trace-confirmed (PC-100, TRACE): "1 x≥t 005" → "GE" / "▴5", "x=t 005" (no
; transfer) → "5", INV x=t / INV If flg when true → "▴…", Dsz never; same
; in a running program ("▴6" for a taken x≥t 006). TI-59: no marker.
; Δ [ENH] new (TI-59 15F3 went straight to PRT.GO).
; ═══════════════════════════════════════════════════════════════════════════
17D4: 0A0D  SWAP KR,SR        ; KR := SR (the operation's continuation slot)
17D5: 0AC5  TST KR[12]        ; slot address with KR[12], KR[4] or KR[5] …
17D6: 0A45  TST KR[4]
17D7: 0A55  TST KR[5]
17D8: 15DB  JNC 14EB          ; … → no marker (14EB)
17D9: 0A95  TST KR[9]         ; KR[6..9] all clear (x=t 0x0C0) …
17DA: 0A85  TST KR[8]
17DB: 0A75  TST KR[7]
17DC: 0A65  TST KR[6]
17DD: 1806  JC 17E0           ; … → check the result
17DE: 0AA5  TST KR[10]        ; else KR[10] (Dsz 0x0F8, STO …) …
17DF: 15E9  JNC 14EB          ; … → no marker
17E0: 0A0D  SWAP KR,SR        ; restore KR/SR
17E1: 0A0C  MOV KR,EXT[4..15]
17E2: 0088  TST fB[8]         ; transfer not taken (fB[8])?
17E3: 15EF  JNC 14EC          ; yes → no marker (14EC)
17E4: 0AD7  MOV R5,#13        ; '▴': 13 + KR[8] (16) + KR[9] (32) = 61 …
17E5: 0A18  MOV KR[4..7],R5
17E6: 0085  SET KR[8]
17E7: 0095  SET KR[9]
17E8: 0A68  PRT.OUT           ; … left of the address digits
17E9: 1DFB  JC 14EC           ; → 14EC (print the line)
; Unused filler: A=A ALL (no-op) words, never executed.
; Δ [REORG] the TI-59 uses its ROM up to 17FF; the TI-58C code ends at 17E9.
17EA: 0100  A=A ALL
17EB: 0100  A=A ALL
17EC: 0100  A=A ALL
17ED: 0100  A=A ALL
17EE: 0100  A=A ALL
17EF: 0100  A=A ALL
17F0: 0100  A=A ALL
17F1: 0100  A=A ALL
17F2: 0100  A=A ALL
17F3: 0100  A=A ALL
17F4: 0100  A=A ALL
17F5: 0100  A=A ALL
17F6: 0100  A=A ALL
17F7: 0100  A=A ALL
17F8: 0100  A=A ALL
17F9: 0100  A=A ALL
17FA: 0100  A=A ALL
17FB: 0100  A=A ALL
17FC: 0100  A=A ALL
17FD: 0100  A=A ALL
17FE: 0100  A=A ALL
17FF: 0100  A=A ALL
