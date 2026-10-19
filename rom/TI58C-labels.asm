; ══════════════════════════════════════════════════════════════════════════
; TI-58C ROM — Label table (named jump targets)
; Companion to TI58C-commented.asm. The Phase-1 listing is generated without a
; label column, so labels live here; comments in the listing refer to these
; names. Addresses are ROM addresses (hex, 0x0000–0x17FF).
;
; Confidence tags:
;   [T] trace-confirmed      (address exercised and behaviour observed)
;   [D] derived              (from code analysis / the key-matrix encoding)
;   [S] speculative
; Tags carried over from rom/TI59-labels.asm refer to the TI-59 unless the
; line was revisited for the TI-58C (all routines that differ were traced on
; the TI-58C with tools/headless/ti59.py --variant TI58C and coverage.py
; --variant TI58C). Labels that kept their TI-59 name at a new address say
; "moved from TI-59 XXXX".
; ══════════════════════════════════════════════════════════════════════════

; ── Reset / idle / keyboard front end ───────────────────────────────────────
0000  RESET              [T] cold-start vector at every power-on: clear flags, zero all 16 SCOM rows (CRD.OFF kept from the TI-59, no effect), → POWERON_SETUP
0350  POWERON_SETUP      [T] power-on setup 0350–03A6: settle delay, RAM-size probe (raw 0x7F), E000 signature check, first-power-up RAM clear, restore of partition and Fix from E000; falls into KEY_CLR
060A  PREIDLE_CHECKS     [T] flag gauntlet before settling into the idle loop (from 042F); no SCOM backup here
062A  IDLE_LOOP          [T] main idle loop: release gate (twice, fA[11]), error blink, test-line polls, arming/confirmation scans
0650  IDLE_SCAN          [T] steady-state scan window: ARMING scan rows 12–1 (new keypress seen here first; printer line at D10 → 0A25)
065A  KEY_ACCEPT         [T] key accepted: leave idle, decode matrix position (065A–06AA)
0688  KEY_PRINT_GATE     [T] keystroke print/trace gate: queues trace symbol, never prints
069A  KEY_DISPATCH       [T] normal dispatch continuation after the print/trace gate
0784  KEY_ENCODE         [T] pack key row/col into 2-digit position code in D
02CA  KEY_USERDEF        [D] keyboard row 1 (A–E user-defined label keys); bypasses KEY_TABLE
02D9  DISP_REBUILD       [T] entry display build (02D9–02E9, continued at 0417–0432): control image in B for the number being typed in A (sign marker, dp position, EE layout); drops pending trace record (02DA)
063F  ERR_BLINK          [T] error-blink service: runs each idle pass while fB[9] set; D[1..3] pass counter, hundreds-digit parity gates SET.IDLE (100 dark : 100 lit passes, ≈ 400 + 533 ms; TI-59 counts 4 per lit pass to offset its ¼-speed idle)

; ── Keyboard dispatch table and key handlers ────────────────────────────────
; The computed jump at 06A9 lands at 0x0<col><row>. Slots at x1–x9 only;
; x0/xA–xF addresses inside the table hold helper stubs (see the table
; annotations in TI58C-commented.asm). Key identities follow from the matrix
; position encoding; [T] where a keypress trace exercised the slot.
0010  KEY_RET            [S] handler return vector (SR := 0x0100 at 06A3); sets KR[8], falls into 0011 → KEY_OP_ENTRY
0011  KEY_TABLE          [T] keyboard dispatch table (0011–0059)
0110  KEY_EE             [T] "EE" handler (slot 0025): scientific display (fB[15]), exponent entry (fA[15]); INV EE → 0487
012D  KEY_LPAREN         [T] "(" handler (slot 0035): SCOM[13] paren level + 1; 10th level → error
013A  KEY_MUL            [D] "×"/"÷" stub (slots 0056/0055): op code 6 → KEY_ARITH; "÷" arrives with fA[1] set
013C  KEY_YX             [D] "y^x" stub (slot 0054): op code 10 → KEY_ARITH; fA[8] set → tags fA[1] (inverse pair)
0140  KEY_ARITH          [T] arithmetic-op common tail: sets fA[9], falls into KEY_OP_ENTRY; op code in R5 (+ − = 2 via 00A0, × ÷ = 6, y^x = 10; fA[1] = inverse-pair bit) — traced for "+"
0141  KEY_OP_ENTRY       [T] builds KR = 0x0C00|tag|code<<4 and jumps into OP_SEQ_TABLE slot 0x00C0+code (+0x10 KR[8], +0x20 KR[9])
015F  DIGIT_SLIDE        [T] INC KR slide 015F–0168; digit d enters at 0168−d ("6"→0162, "0"→0168 traced on the TI-58C)
0204  KEY_LNX            [D] "lnx" handler (slot 0032); R5 := 2, falls through 0208 into FN_ENTRY
0208  FN_ENTRY_KR8       [D] FN_ENTRY variant: sets KR[8] first ("√x" enters here with R5=0)
0209  FN_ENTRY           [T] common unary-function entry; function code in R5 ("x²" R5=7, "1/x" R5=10); PREG jump to FN_TABLE 0x0500+fn — traced for 1/x
0260  KEY_INV            [T] "INV" handler (slot 0022)
0262  KEY_2ND            [T] "2nd" handler (slot 0012); TOG fA[9]
0274  KEY_XT             [D] "x⇄t" handler (slot 0023)
02A4  KEY_GTO            [D] "GTO" handler (slot 0016)
02F3  KEY_DPT            [T] "." handler (slot 0039)
03A7  KEY_CLR            [T] "CLR" handler (slot 0052), also the tail of POWERON_SETUP; checks pending trace record (fA[10]) at entry; flag wipe at 03B8 + CLR fB[9] at 03C2 end an error blink (traced: 1 ÷ 0 = CLR)
03C1  KEY_CE             [D] "CE" handler (slot 0042)
03F2  KEY_SBR            [D] "SBR" handler (slot 0017)
0401  KEY_SST            [D] "SST" handler (slot 0014)
0410  KEY_RS             [D] "R/S" handler (slot 0019)
0411  KEY_BST            [D] "BST" handler (slot 0015)
0451  KEY_PR             [T] "P/R" handler (2nd slot 0073); launches the P→R keycode sub-program: Prg Src Flag := 8 via 0A4D–0A55
0B11  OP_INS             [T] "Ins" operation body (2nd slot 0064 → KEY_OP_ENTRY chain, vector 0xB11); per-register shift loop uses PRGREG_RAM_READ / PRGREG_CACHE / 1219
0089  KEY_ADV            [T] 2nd-table slot of Adv (2nd .); the printer's ADV button is remapped to it (0678–0687)
0099  KEY_PRT            [T] 2nd-table slot of Prt (2nd +/-); the printer's PRINT button is remapped to it (0678–0687)

; ── Operation sequences and AOS ─────────────────────────────────────────────
00B1  OP_SEQ_TABLE       [T] threaded operation-sequence table (00B1–010F): runs of JC slots, each routine returns to the next slot via SR
006C  AOS_EQUALS         [T] "=": incoming precedence 0 → AOS reduce (0147)
0146  AOS_RPAREN         [T] ")": incoming precedence 1 → reduce the current paren level
0147  AOS_REDUCE_ENTRY   [T] reduce entry with precedence in B[3]; rejects ")"/"=" right after an operator (014F, error)
0190  AOS_PUSH           [T] operator push, precedence in R5 (+− 2, ×÷ 4, y^x 6); rejects operator after operator (0192)
0197  AOS_REDUCE_LOOP    [T] pop while top entry has same paren level and precedence ≥ incoming; exec slot 0x00C0+2·prec
01C5  AOS_FINISH         [T] stack exhausted: close paren level (01F0) or push operand/operator (01C8); 8-level limit → 04CC
0413  AOS_CONTINUE       [T] reduce-loop continuation after an executed operation (slots 00C5/00C9, 050F, 0547/0549); moved from TI-59 015F
0333  ADD                [T] A := B ± A (fA[1] = subtract): align exponents, add/subtract magnitudes
0228  ARG_COLLECT_SETUP  [T] suspend the operation sequence until count+1 argument digits are typed (fB[12]); count already in A[0..1] from 0223–0227; state in E
02F5  NUMBER_ENTRY       [T] digit / "." entry into the display image in A (digit limits 0313–0316); argument digits diverted to 06BE

; ── Arithmetic / number pipeline (trace: errorblink.txt, 1/x of 0) ──────────
0442  NORM_CALL          [T] "normalize, then do the work" prologue: parks KR+1 (caller's next FN_TABLE slot) in SR, runs NUM_NORM, PREG-returns via 02C9/02CA
043E  ARITH_OVFL_EXIT    [T] arithmetic overflow exit (fA[4] tag): bumps the pending continuation, then exits to OVFL_CLAMP
043F  ARITH_EXIT         [T] arithmetic exit: advance SR (current slot) by one, NUM_NORM, return to the next slot
0230  NUM_NORM           [T] finish number entry: entry image in A (or full-precision X in C when fB[5]) → normalized A = C; zero case 02B7; clamps at OVFL_CLAMP
0254  OVFL_CLAMP         [T] over/underflow clamp: SET fB[9] (ERROR blink) unless fA[14]; clamps A to 9.9999999E99 (fA[3] clear) or 1E−99 (fA[3] set, [S] not exercised)
03D4  MULDIV             [T] A := B × A or B ÷ A (fA[1]); exponent handling 0433–043D, loops moved to 06FD–072A (multiply 0718, divide 0708); x÷0 → 043E, 0÷0 → error + 1.0
076C  RECIP              [T] "1/x" implementation (FN_TABLE slot 050B): B := 1.0, divide mode, → MULDIV with X as divisor
05B9  DISP_ROUND         [T] first-pass display rounding: +5 at the guard digit, clear it, re-run NUM_NORM (a carry can re-overflow → OVFL_CLAMP again)

; ── Printer / TRACE ─────────────────────────────────────────────────────────
0A6C  TRC_QUEUE_GATE     [T] trace-queue gate (from KEY_PRINT_GATE): fA[10] = record pending; 1st pass queues, 2nd pass dispatches
05A8  TRC_PRINT_TRIGGER  [T] after an operation completes: re-check fA[10] + TRACE switch, print queued line (fall-through entry, not a jump target)
141A  TRC_SYM_QUEUE      [T] queue keystroke's 3-char print symbol into printer line buffer; no PRT.GO (printer present at D11)
1117  PRT_SYM_TABLE      [T] JC dispatch table (≈1117–112F) into PRT_CHAR_SLIDE, one entry per symbol character
1390  PRT_CHAR_SLIDE     [T] INC KR chains (1390–13B2) that build 6-bit printer character codes; end in PRT.OUT at 13B3
152B  PRT_VALUE_FMT      [T] numeric print formatter: appends display value to line buffer, ends in PRT.GO at 0EFD
0EF1  PRT_QUIRK_LANDING  [T] landing of pseudo-keycode 1F (MOV R5,#10 of the leading-zero branch; then PRT.GO 0EFD)
0EFD  PRT_LINE_PRINT     [T] PRT.GO that commits the assembled line to paper; 0EFE clears fA[10]

; ── User-program execution ──────────────────────────────────────────────────
0F81  PRG_DISPATCH       [T] RAM-program keycode fetch & computed-jump dispatch (0F81–0F9B); no keycode validation
0823  LIB_EXEC_FETCH     [T] solid-state (CROM) execution-interpreter IN LIB fetch site — latches the user-visible library PC (see reference/CoreArchitecture.md); instruction site, not an entry point
0B95  PRGREG_FETCH_CON   [T] constant-table branch of PRGREG_FETCH: step counter → row 16 + step/8 (index in KR[10:8]·8 + KR[6:4]), C=C+CON reads 8 packed keycodes (step 008 → row 17 traced)
0EDA  PRGREG_RAM_READ    [T] read a program register from RAM (MEMRD, binary address A[1..0]; byte position parked D[1] → A[3] → A[0])
0F6A  PRGREG_RAM_WRITE   [T] write a program register to RAM (MEMWR: address A[1..0] on the bus, data D on the next IO); Ins/Del and Op 09
0C0B  PRGREG_CACHE       [T] cache the fetched program register in SCOM[10] (reused by LRN display and Ins/Del shift; never source-revalidated)

0863  STEP_TO_REG        [T] generic transfer-to-step tail: split target into register·offset (÷8 loop); fB[0] set = keycode-sub-program target (no range check, flag 8); clear = RAM target, range-checked against the program partition (SCOM[13] mantissa, 087B); commit PC to SCOM[0] (088E) or abandon at 0B0A

; ── Named instruction sites (not jump targets) ──────────────────────────────
02DA  —                  [T] CLR fA[10]: digit keys discard their pending trace record here
06A9  —                  [T] computed keyboard jump: PREG := 0x0<col><row> (redirects one instruction late)
0EFE  —                  [T] CLR fA[10] after the trace line is printed

; ── Added 2026-10-17 (headless-harness pass) ───────────────────────────────
0500  FN_SEQ_TABLE       [T] function sequence table 0500–0545 (√x 0510, ln 0512, e^x 0515, 10^x 0518, log 051B, trig 0523, SBR 0534, Pgm 053A, Op 053F)
06E3  EXP                [T] e^x: argument reduction by ln 10, kernel in exp mode, finish 0ACD
0738  LN                 [T] ln x entry (error for 0, flag for negative); kernel 073E in ln mode
073E  LNEXP_KERNEL       [T] Meggitt pseudo-multiplication with constants ln(1+10^-k)
0811  SQRT               [T] √x: exponent halving, digit-by-digit body 0AA7
05D0  ANGLE_CONVERT      [T] angle unit ↔ radians (SCOM[13] nibble 0: 0 DEG, 1 GRAD, C RAD)
0C52  TAN_KERNEL         [T] decimal CORDIC (atan(10^-k) constants 8–12), tan = y/x; moved from TI-59 08C7 (x-step / arc part at 0F24–0F4D)
044A  LOAD_PI            [T] A := π (044A) / A += π (044B)
054C  DISP_FORMAT        [T] result display image: Fix/sci/eng layout, two-pass rounding (fB[5])
0D15  REG_ADDR           [T] data register nn → RAM index 59 − nn (BCD), partition check → RAM_ADDR
0D9E  RAM_READ           [T] MEMRD of the register addressed by A into A; LRN → 1155, Ind → 0F5D, else signs → fA[1..4]
0DFE  RAM_WRITE          [T] MEMWR of C (signs from fB[1..4]) to the register whose binary address is in D
06BE  ARG_COLLECTOR      [T] digit → argument in E; complete → 07A9
07A9  ARG_COMPLETE       [T] resume the suspended sequence (Ind → read pointer first)
077F  ARG_TERMINATE      [T] non-digit key ends an argument; keycode parked in SCOM[0] nibbles 1–2, fB[14]
04C8  ARG_TWO_DIGITS     [T] collect a 2-digit argument (register, Op, Pgm)
01ED  ARG_ONE_DIGIT      [T] collect a 1-digit argument (flag, Dsz register, Fix): R5 = 0 → 0221 (+1 when running)
028B  KEY_RST            [T] RST (slot 0018 lands here): step 000, return stack cleared, library deselected (was 028C in the draft; 028C is the RCLF one word in)
0404  KEY_LRN            [T] LRN toggle (refused without program memory; no protected-card test on the TI-58C)
098B  LRN_KEY            [T] key in LRN mode: edit keys act, others encoded and stored
0D5C  LRN_STORE          [T] replace the keycode at the current step (MEMRD 0D9F … MEMWR 0C1C), advance
08A7  PRGREG_FETCH       [T] advance the step and fetch its keycode (source dispatch, SCOM[10] shift cache)
13DD  LRN_DISPLAY        [T] "SSS KK" display
07BD  RUN_LOOP           [T] between steps: R/S and GTO-peek polls, fetch, dispatch
082B  STEP_DISPATCH      [T] keycode → matrix position → key pipeline (0688)
07DE  RUN_RS            [T] R/S: stop, or start after the key is released
1175  RTN_POP            [T] return from subroutine; empty stack ends the run
0E11  SCANNER_TABLE      [T] program scanner: per-keycode operand classes, slots 0x0E<units><tens> (0E11–0E98; units/tens 0 never dispatched)
0F74  LABEL_SEARCH       [T] walk RAM program registers looking for Lbl x (MEMRD at 0F75)
173B  PGM_SELECT         [T] Pgm nn: check against the module's program count (TI-59 12E1, moved; entered 105F → 1416)
081F  LIB_EXEC_ENTRY    [T] module keycode fetch; RST held → abort (082A)
0495  COND_TRANSFER      [T] x=t, x≥t, If flg, Dsz: branch on fA[9] (INV inverts)
15B7  FLAG_OP            [T] St flg / INV St flg: flag n = bit ⌊n/5⌋ of SCOM[0] nibble 11 + n mod 5
04E2  DISPLAY_PEEK       [T] light the display ~256 cycles (GTO held while a RAM program runs)
08D5  OP_DISPATCH        [T] Op nn: 00–19 table, 2x/3x register inc/dec, 40 printer test (flag 7), 41–99 error
0A00  OP_TABLE           [T] Op 00–19, slot 0x0A00 + 16·tens + units (Op 40 is decoded separately, 08D8 → OP_40)
1000  PRT_MNEMONIC_TABLE [T] 3-character PC-100 mnemonic per keycode (0x1000 + 32·tens + 3·units)
11BC  HIR_STO            [T] HIR STO: X → hierarchy register SCOM[m] (entry 11BB with SET fB[5])
00FA  HIR                [T] HIR nm sequence (keycode 82): n = 0 STO, 1 RCL, 3 SUM, 4 Prd, 5 INV SUM, 6 INV Prd; m = SCOM row 1–8
0B20  COMPACT_BANK       [T] compact keycodes by digit position: 92 RTN, 82 HIR, 83/84/72–74/62–64 Ind forms (0EA4)
1413  PGM_ERROR_HALT     [T] error blink and stop (e.g. Pgm out of range)
; Keycode sub-programs (Prg Src 8) are listed in rom/TI59-keycode-programs.asm.


; ── TI-58C-specific and relocated routines ──────────────────────────────────
0289  RST_ABORT          [T] RST held during a library fetch (04DF ← 082A): borrow at 0289 marks the path (COND) through the RST body, then 029E → 022F shows X
0352  PWR_SETTLE_DELAY   [T] 51-pass countdown (≈100 cycles) before the first MEMWR/MEMRD after power-on (purpose derived)
035C  RAM_SIZE_PROBE     [T] MEMWR/MEMRD raw register 0x7F: read-back only on a 128-register RAM (then E000 = 0x7C, 120 registers); 64 registers → KR[10], E000 = 0x3C
036A  CM_SIGNATURE_CHECK [T] E000 nibbles 3–15 = ln 10 mantissa? yes → CM_RESTORE (0382), no → CM_CLEAR
0370  CM_CLEAR           [T] first power-up: write 0 into every raw register 0–63 (0–127), E000–E003 included (emulator clears only one nibble per register, see findings)
037A  CM_SIGNATURE_WRITE [T] E000 := signature | partition 03 (06) | Fix 0
0381  CM_RESTORE         [T] E000 nibbles 2–0 → SCOM[9] (E000-address nibble + hex partition), SCOM[13] (partition, top register 059), SCOM[0] (Fix); valid path enters at 0382
0417  DISP_REBUILD_LOOP  [T] second part of the entry display build: dp position, sign marker, digit-position loop, INV handling, → PREIDLE_CHECKS 060A (moved from TI-59 02F3–030E)
0474  FIX_SAVE           [T] copy the new Fix setting into E000 nibble 0 (MEMRD/MEMWR at the address from SCOM[9] nibble 1)
064A  TEST_LINE_POLL     [T] every idle pass: KN at D15 → self-test (09FD), KR line at D10 → external program 0x1800 (09F7)
06FD  MULDIV_LOOPS       [T] MULDIV unlike-exponent subtraction and multiply/divide loops 06FD–072A (moved from TI-59 0422–044F; ADD's like-sign add uses the carry tail 0724)
08BB  SELFTEST_CONST63   [T] self-test 2 (0C02): expected value of constant-ROM entry 63 → compare at 09D7
0954  ARG_KEY            [T] key arriving in argument mode (from 06A0): Pgm-mark check, classify (05BF); verdicts at 096C–097C
09CC  SELFTEST_CONST7    [T] self-test 1 (0C01): expected value of constant-ROM entry 7 = ln(1+10^-6); shared compare 09D7–09DC
09DD  SELFTEST_EXIT      [D] self-test end / mismatch: drain printer, KR := 0, → 07B5 → PREG 0x0000 (restart)
09F7  EXT_PROG_ENTRY     [T] KR line at D10 in idle (064F): PREG := 0x1800, outside the 6K ROM (test-fixture program memory?)
09FD  SELFTEST_ENTRY     [T] KN at D15 in idle (064C) or KN on row 8/9 (0666) → self-test 0DB7
0A1A  RAM_ACCESS         [T] binary RAM address in A[1..0] (from RAM_ADDR) → D; dispatch LRN 0B17 / read or Ind 0D9E / write 0DFE
0A25  PRN_LINE_RESCAN    [T] idle loop (from 0659): printer-present line KP@D10 looks like a held row-10 key; rescan rows 9..1 (arming 0A2C, confirmation 0654); extra blink step 0A29
0BFA  OP_40              [T] Op 40 (TI-58C only): set flag 7 if a printer is connected (shares the Op 18/19 tail 0BFE–0C00)
0C01  SELFTEST_TABLE     [T] factory self-test dispatch, PREG 0x0C0n = test n (1–10); bodies 09CC, 08BB, 0FF4–0FFD → 1360–138F / 16C7 / 16C8 / 1680
0C16  PRGREG_WRITE       [T] LRN write-back of the edited program register: address (B) → MEMWR → data (TI-59 0BF4 RAM.OP write)
0D34  PROG_OPERAND       [T] operand step of a running program fed as two digit keys (from STEP_DISPATCH 082F → 09FF); moved from TI-59 096C
0D3E  PGM_IN_PROGRAM     [T] "Pgm nn" mark in SCOM[13] nibble 15: next label / SBR / R/S step goes to the module; moved from TI-59 0976
0D96  RAM_ADDR           [T] BCD RAM index → binary MEMRD/MEMWR address (count-down loop, ≤ 59 passes); data and program registers
0DB7  SELF_TEST          [T] factory self-test sequencer (hidden key KN at row 8/9 → 09FD): print test number, dispatch 0C01+n; end/fail → 09DD cold restart
0E5A  INS_DEL            [T] Ins / Del in LRN: shift every program register from the cursor to the partition end
0EA4  COMPACT_IND        [T] compact Ind keycode (ST*, RC*, GO* …): park Ind as pending key, dispatch the base op
0F06  PRGREG_ADDR_PREP   [T] LRN store: step counter → BCD register number in A[5..3] for the binary count loop 0D96
0F2E  ARC_ACCUM          [T] arc-function CORDIC angle accumulation (moved from TI-59 0C97; entry 0F49)
0F4E  PAPER_ADVANCE      [T] Adv: feed two lines, keep feeding while ADV / "." held
0F5D  IND_POINTER        [T] Ind: pointer register (read at 0D9E) → integer operand; negative or < 1 → 0
0FA9  INV_LIST_LOOP      [T] INV List per-register loop (start 12FE via 103F, end 1142)
0FF4  SELFTEST_RELAYS    [T] self-test table targets 0FF4–0FFD (tests 4, 5, 6, 8, 9, 10 → 1360–138F)
10BE  SELFTEST_FAIL      [T] self-test result relay: failed → 0DD6 → 09DD
10BF  SELFTEST_PASS      [T] self-test result relay: passed → 0DC3 (next test)
1155  LRN_REPLACE       [T] keycode replace in a program register (from 0DA2)
11C3  CLEAR_MEM          [T] CMs / CP (from 0BE6 → 0FCC); CP at 1556
11D7  CLEAR_LOOP         [T] clear one RAM register per MEMWR (zero bus during C=C−B), raw address in C counting down
1287  LIB_XFER_TARGET    [T] library SBR/GTO nnn: resolve against the module header (start/next start), range check, commit CROM PC
12E2  HIR_EXEC           [T] HIR nm (from slot 00FC via 103E): m 1–8, n = 0 STO / 1 RCL / 3 SUM / 4 Prd, n ≥ 5 INV; = TI-59 11BC but X signs from fB (FIX)
12FE  INV_LIST_START     [T] INV List start (from 0D0D via 103F): SCOM[0] nibbles 1–2 := Int(X), SCOM[9] nibble 15 := 1 → 0FB1 (= TI-59 0F6E)
1333  LIB_LABEL_TRAMP    [T] trampoline 0FB9 → LIB_LABEL_SEARCH 157A
1334  RET_PUSH           [T] push a return level onto SCOM[15]/[14] (via 0D33 → 0FFE); = TI-59 0D50, moved unchanged
1360  SELFTEST8_SCOM    [T] factory self-test 8: SCOM[k] := k·1000+k for all rows, verify rows 0–7 (pass 10BF / fail 10BE)
1368  SELFTEST9_SCOM    [T] factory self-test 9 (from 0FF9, A = row 8): verify SCOM rows 8–15
1375  SELFTEST10_RAM    [T] factory self-test 10: RAM[k] := k for k = 63…0 (MEMWR), read back (MEMRD) and compare
1416  PGM_TRAMP          [T] Pgm sequence (105F) → PGM_SELECT 173B
147B  OP09_DOWNLOAD      [T] Op 09: copy the selected library program into RAM program memory (protect byte, length check)
14EB  TRC_MARK_TAIL      [T] tail of the TRACE conditional marker (17D4–17E9): label operand → 1165, else PRT.GO 15F6
14FC  LIB_RETURN         [T] RTN into a library program: find the program holding the return address, reload the CROM PC
1556  CP_CLEAR           [T] CP: t := 0; keyboard: return stack, SCOM[0] to Fix, program registers (MEMWR, 11D7)
1570  CLR_RANGE_BIN      [T] CP/CMs: top register number (BCD) → binary RAM address in C, then clear loop 11D7
157A  LIB_LABEL_SEARCH   [T] same for a library program (header start/end); = TI-59 1364, moved unchanged
158D  —                  [D] CROM module-header read (LIB.HI); does not move the user-visible library PC
1592  —                  [D] CROM module-header read (LIB.IN); same note as 158D
15A6  —                  [D] CROM label-search read (LIB.HI); same note as 158D
15AA  —                  [D] CROM label-search read (LIB.IN); same note as 158D
15E1  TRACE_OPERAND_LINE [T] TRACE mode: operand on its own line ("*" for Ind; ▴ before a taken conditional's address)
167F  PRINT_EXIT         [T] common exit of the print ops and PARTITION → 1330 → 11F3 (display)
1680  SELFTEST6_RAM     [T] self-test 6: clear and checkerboard-test every raw RAM register (MEMWR/MEMRD); "D" first on a 128-register RAM
16C7  SELFTEST4_SCOM    [T] self-test 4: SCOM rows 0–7 checkerboard (test 5 enters at 16C8 with first row 8)
16C8  SELFTEST_PATTERN   [T] build the 6969… pattern; SCOM rows A[0]…A[0]+7 (KR[7] clear) or the RAM test (KR[7] set → 1698)
1739  PARTITION_ERROR    [T] Op 17 with more data decades than RAM: error, show the unchanged partition
176F  OP09_PAD           [T] Op 09: program end inside a register, pad with 00 and write (TI-59 15B4, moved)
1775  PARTITION          [T] Op 16 / Op 17: show / set the partition; Op 17 also writes E000 nibbles 1–2 (17AE)
17D4  TRACE_XFER_MARK    [T] TRACE: '▴' (code 61) before the address of a taken x=t / x≥t / If flg transfer
