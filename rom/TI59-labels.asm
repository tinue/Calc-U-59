; ══════════════════════════════════════════════════════════════════════════
; TI-59 ROM — Label table (named jump targets)
; Companion to TI59-commented.asm. The Phase-1 listing is generated without a
; label column, so labels live here; comments in the listing refer to these
; names. Addresses are ROM addresses (hex, 0x0000–0x17FF).
;
; Confidence tags:
;   [T] trace-confirmed      (address exercised and behaviour observed)
;   [D] derived              (from code analysis / the key-matrix encoding)
;   [S] speculative
; Traces: KEYPRESS_59.txt (key "6", no printer), KEYPRESS_TRC_59.txt (keys
; "0" and "+", printer attached, TRACE switch latched), CALCU59_TRACE.ans
; (examples/texas-print.ti59 single-step), CALCU59_TRACE.txt
; (texas-print.ti59 scripted pseudo-code insertion: SBR 444 … P/R, LRN, Ins),
; errorblink.txt (1/x on a zero display after reset → error blink → CLR,
; no printer).
; ══════════════════════════════════════════════════════════════════════════

; ── Reset / idle / keyboard front end ───────────────────────────────────────
0000  RESET              [T] cold-start vector: clear flags, card reader, SCOM status rows
0375  POWERON_SETUP      [T] main power-on setup (entered from 000E); memory-size autodetect
060A  PREIDLE_CHECKS     [T] flag gauntlet before settling into the idle loop (from 030B)
062A  IDLE_LOOP          [T] main idle loop: display multiplex + keyboard scan
0656  IDLE_SCAN          [T] steady-state scan window (ARMING scan; new keypress seen here first)
0661  KEY_ACCEPT         [T] key accepted: leave idle, decode matrix position (0661–06B2)
0689  KEY_PRINT_GATE     [T] keystroke print/trace gate: queues trace symbol, never prints
06A2  KEY_DISPATCH       [T] normal dispatch continuation after the print/trace gate
0788  KEY_ENCODE         [T] pack key row/col into 2-digit position code in D
02D2  KEY_USERDEF        [D] keyboard row 1 (A–E user-defined label keys); bypasses KEY_TABLE
02E2  DISP_REBUILD       [T] entry display build: control image in B for the number being typed in A (sign marker, dp position, EE layout); drops pending trace record (02E3)
0643  ERR_BLINK          [T] error-blink service: runs each idle pass while fB[9] set; D[1..3] pass counter, hundreds-digit parity gates SET.IDLE (~100 dark : 25 lit passes)

; ── Keyboard dispatch table and key handlers ────────────────────────────────
; The computed jump at 06B1 lands at 0x0<col><row>. Slots at x1–x9 only;
; x0/xA–xF addresses inside the table hold helper stubs (see the table
; annotations in TI59-commented.asm). Key identities follow from the matrix
; position encoding; [T] where a keypress trace exercised the slot.
0010  KEY_RET            [S] handler return vector (SR := 0x0100 at 06AB); sets KR[8], falls into 0011 → KEY_OP_ENTRY
0011  KEY_TABLE          [T] keyboard dispatch table (0011–0059)
0110  KEY_EE             [T] "EE" handler (slot 0025): scientific display (fB[15]), exponent entry (fA[15]); INV EE → 048B
012D  KEY_LPAREN         [T] "(" handler (slot 0035): SCOM[13] paren level + 1; 10th level → error
013A  KEY_MUL            [D] "×"/"÷" stub (slots 0056/0055): op code 6 → KEY_ARITH; "÷" arrives with fA[1] set
013C  KEY_YX             [D] "y^x" stub (slot 0054): op code 10 → KEY_ARITH; fA[8] set → tags fA[1] (inverse pair)
0140  KEY_ARITH          [T] arithmetic-op common tail: sets fA[9], falls into KEY_OP_ENTRY; op code in R5 (+ − = 2 via 00A0, × ÷ = 6, y^x = 10; fA[1] = inverse-pair bit) — traced for "+"
0141  KEY_OP_ENTRY       [T] builds KR = 0x0C00|tag|code<<4 and jumps into OP_SEQ_TABLE slot 0x00C0+code (+0x10 KR[8], +0x20 KR[9])
0163  DIGIT_SLIDE        [T] INC KR slide 0163–016C; digit d enters at 016C−d ("6"→0166 traced, "0"→016C traced)
020B  KEY_LNX            [D] "lnx" handler (slot 0032); R5 := 2, falls through 020F into FN_ENTRY
020F  FN_ENTRY_KR8       [D] FN_ENTRY variant: sets KR[8] first ("√x" enters here with R5=0)
0210  FN_ENTRY           [T] common unary-function entry; function code in R5 ("x²" R5=7, "1/x" R5=10); PREG jump to FN_TABLE 0x0500+fn — traced for 1/x
0266  KEY_INV            [T] "INV" handler (slot 0022)
0268  KEY_2ND            [T] "2nd" handler (slot 0012); TOG fA[9]
027A  KEY_XT             [D] "x⇄t" handler (slot 0023)
02AC  KEY_GTO            [D] "GTO" handler (slot 0016)
0318  KEY_DPT            [T] "." handler (slot 0039)
039F  KEY_CLR            [T] "CLR" handler (slot 0052); checks pending trace record (fA[10]) at entry; flag wipe at 03B0 + CLR fB[9] at 03BA end an error blink — traced in errorblink.txt
03B9  KEY_CE             [D] "CE" handler (slot 0042)
03E9  KEY_SBR            [D] "SBR" handler (slot 0017)
03F8  KEY_SST            [D] "SST" handler (slot 0014)
040A  KEY_RS             [D] "R/S" handler (slot 0019)
040B  KEY_BST            [D] "BST" handler (slot 0015)
0462  KEY_PR             [T] "P/R" handler (2nd slot 0073); launches the P→R keycode sub-program: Prg Src Flag := 8 via 0A4B–0A53
0B11  OP_INS             [T] "Ins" operation body (2nd slot 0064 → KEY_OP_ENTRY chain, vector 0xB11); per-register shift loop uses PRGREG_RAM_READ / PRGREG_CACHE / 1213
0089  KEY_PSEUDO_ADV     [D] pseudo table entry for the printer paper-ADVANCE key (remapped at 0679–0688)
0099  KEY_PSEUDO_PRINT   [D] pseudo table entry for the printer PRINT key (remapped at 0679–0688)

; ── Operation sequences and AOS ─────────────────────────────────────────────
00B1  OP_SEQ_TABLE       [T] threaded operation-sequence table (00B1–010F): runs of JC slots, each routine returns to the next slot via SR
006C  AOS_EQUALS         [T] "=": incoming precedence 0 → AOS reduce (0147)
0146  AOS_RPAREN         [T] ")": incoming precedence 1 → reduce the current paren level
0147  AOS_REDUCE_ENTRY   [T] reduce entry with precedence in B[3]; rejects ")"/"=" right after an operator (014F, error)
0194  AOS_PUSH           [T] operator push, precedence in R5 (+− 2, ×÷ 4, y^x 6); rejects operator after operator (0196)
019B  AOS_REDUCE_LOOP    [T] pop while top entry has same paren level and precedence ≥ incoming; exec slot 0x00C0+2·prec
01C9  AOS_FINISH         [T] stack exhausted: close paren level (01F7) or push operand/operator (01CC); 8-level limit → 04D0
015F  AOS_CONTINUE       [T] reduce-loop continuation after an executed operation (slots 00C5/00C9)
0358  ADD                [T] A := B ± A (fA[1] = subtract): align exponents, add/subtract magnitudes
022C  ARG_COLLECT_SETUP  [T] suspend the operation sequence until R5+1 argument digits are typed (fB[12]); state in E
031A  NUMBER_ENTRY       [T] digit / "." entry into the display image in A (digit limits 0338–033B); argument digits diverted to 06C6

; ── Arithmetic / number pipeline (trace: errorblink.txt, 1/x of 0) ──────────
041C  NORM_CALL          [T] "normalize, then do the work" prologue: parks KR+1 (caller's next FN_TABLE slot) in SR, runs NUM_NORM, PREG-returns via 02D1/02D2
0418  ARITH_OVFL_EXIT    [T] arithmetic overflow exit (fA[4] tag): bumps the pending continuation, then exits to OVFL_CLAMP
0419  ARITH_EXIT         [T] arithmetic exit: advance SR (current slot) by one, NUM_NORM, return to the next slot
0236  NUM_NORM           [T] finish number entry: entry image in A (or full-precision X in C when fB[5]) → normalized A = C; zero case 02BF; clamps at OVFL_CLAMP
025A  OVFL_CLAMP         [T] over/underflow clamp: SET fB[9] (ERROR blink) unless fA[14]; clamps A to 9.9999999E99 (fA[3] clear) or 1E−99 (fA[3] set, [S] not exercised)
03CC  MULDIV             [T] A := B × A or B ÷ A (fA[1]); shift-and-add multiply 0447, restoring division 042D; x÷0 → 0418, 0÷0 → error + 1.0
0770  RECIP              [T] "1/x" implementation (FN_TABLE slot 050B): B := 1.0, divide mode, → MULDIV with X as divisor
05B9  DISP_ROUND         [T] first-pass display rounding: +5 at the guard digit, clear it, re-run NUM_NORM (a carry can re-overflow → OVFL_CLAMP again)

; ── Printer / TRACE ─────────────────────────────────────────────────────────
0A68  TRC_QUEUE_GATE     [T] trace-queue gate (from KEY_PRINT_GATE): fA[10] = record pending; 1st pass queues, 2nd pass dispatches
05A8  TRC_PRINT_TRIGGER  [T] after an operation completes: re-check fA[10] + TRACE switch, print queued line (fall-through entry, not a jump target)
1422  TRC_SYM_QUEUE      [T] queue keystroke's 3-char print symbol into printer line buffer; no PRT.GO
1117  PRT_SYM_TABLE      [T] JC dispatch table (≈1117–112F) into PRT_CHAR_SLIDE, one entry per symbol character
1399  PRT_CHAR_SLIDE     [T] INC KR chains (1399–13BB) that build 6-bit printer character codes; end in PRT.OUT at 13BC
152B  PRT_VALUE_FMT      [T] numeric print formatter: appends display value to line buffer, ends in PRT.GO at 0EFC
0EF1  PRT_QUIRK_LANDING  [T] printer-interrupt "quirk" landing zone (mis-dispatch of corrupt keycode x-F)
0EFC  PRT_LINE_PRINT     [T] PRT.GO that commits the assembled line to paper; 0EFD clears fA[10]

; ── User-program execution ──────────────────────────────────────────────────
0F53  PRG_DISPATCH       [T] RAM-program keycode fetch & computed-jump dispatch (0F53–0F6D); no keycode validation
082F  LIB_EXEC_FETCH     [T] solid-state (CROM) execution-interpreter IN LIB fetch site — latches the user-visible library PC (see reference/CoreArchitecture.md); instruction site, not an entry point
0B9D  PRGREG_FETCH_CON   [T] constant-table branch of PRGREG_FETCH: step counter → row 16 + step/8 (index in KR[10:8]·8 + KR[6:4]), C=C+CON reads 8 packed keycodes (step 008 → row 17 traced)
0EDB  PRGREG_RAM_READ    [T] read a program register from RAM (RAM.OP read; register number in the next IO value, nibbles 3·2)
0F85  PRGREG_RAM_WRITE   [T] write a program register to RAM (RAM.OP write; specifier then data on the two following IO values)
0C10  PRGREG_CACHE       [T] cache the fetched program register in SCOM[10] (reused by LRN display and Ins/Del shift; never source-revalidated)

086F  STEP_TO_REG        [T] generic transfer-to-step tail: split target into register·offset (÷8 loop); fB[0] set = keycode-sub-program target (no range check, flag 8); clear = RAM target, range-checked against the program partition (SCOM[13] mantissa, 0887); commit PC to SCOM[0] (089A) or abandon at 0B0A

; ── Named instruction sites (not jump targets) ──────────────────────────────
02E3  —                  [T] CLR fA[10]: digit keys discard their pending trace record here
06B1  —                  [T] computed keyboard jump: PREG := 0x0<col><row> (redirects one instruction late)
0EFD  —                  [T] CLR fA[10] after the trace line is printed
1377  —                  [D] CROM module-header read (IN LIB); does not move the user-visible library PC
137C  —                  [D] CROM module-header read (IN LIB); same note as 1377
1390  —                  [D] CROM label-search read (LIB.HI/IN LIB); same note as 1377
1394  —                  [D] CROM label-search read (IN LIB); same note as 1377

; ── Added 2026-10-17 (headless-harness pass) ───────────────────────────────
0500  FN_SEQ_TABLE       [T] function sequence table 0500–0545 (√x 0510, ln 0512, e^x 0515, 10^x 0518, log 051B, trig 0523, SBR 0534, Pgm 053A, Op 053F)
0703  EXP                [T] e^x: argument reduction by ln 10, kernel in exp mode, finish 0AD3
072A  LN                 [T] ln x entry (error for 0, flag for negative); kernel 0730 in ln mode
0730  LNEXP_KERNEL       [T] Meggitt pseudo-multiplication with constants ln(1+10^-k)
081D  SQRT               [T] √x: exponent halving, digit-by-digit body 0AA8
05D0  ANGLE_CONVERT      [T] angle unit ↔ radians (SCOM[13] nibble 0: 0 DEG, 1 GRAD, C RAD)
08C7  TAN_KERNEL         [T] decimal CORDIC (atan(10^-k) constants 8–12), tan = y/x
0452  LOAD_PI            [T] A := π (0452) / A += π (0453)
054C  DISP_FORMAT        [T] result display image: Fix/sci/eng layout, two-pass rounding (fB[5])
0D33  REG_ADDR           [T] data register nn → RAM[top − nn], partition check
0A1A  RAM_ADDR_ENCODE    [T] RAM.OP address encoding (hex tens nibble for registers ≥ 100)
0DBA  RAM_READ           [T] RAM.OP read of a data register into A
0CF7  RAM_WRITE          [T] RAM.OP write of X into a data register
06C6  ARG_COLLECTOR      [T] digit → argument in E; complete → 07AD
07AD  ARG_COMPLETE       [T] resume the suspended sequence (Ind → read pointer first)
0783  ARG_TERMINATE      [T] non-digit key ends an argument; keycode parked in SCOM[0] nibbles 1–2, fB[14]
04CC  ARG_TWO_DIGITS     [T] collect a 2-digit argument (register, Op, Pgm)
01F1  ARG_ONE_DIGIT      [T] collect a 1-digit argument (flag, Dsz register) from the keyboard
0291  KEY_RST            [T] RST: step 000, stack cleared, library deselected
03FB  KEY_LRN            [T] LRN toggle (refused without program memory or with a protected module)
099E  LRN_KEY            [T] key in LRN mode: edit keys act, others encoded and stored
0D80  LRN_STORE          [T] replace the keycode at the current step, write back, advance
08B2  PRGREG_FETCH       [T] advance the step and fetch its keycode (source dispatch, SCOM[10] shift cache)
13E6  LRN_DISPLAY        [T] "SSS KK" display
07C1  RUN_LOOP           [T] between steps: R/S and GTO-peek polls, fetch, dispatch
0837  STEP_DISPATCH      [T] keycode → matrix position → key pipeline (0689)
07EA  KEY_RS             [T] R/S: stop, or start after the key is released
1175  RTN_POP            [T] return from subroutine; empty stack ends the run
0E10  SCANNER_TABLE      [T] program scanner: per-keycode operand classes for label search (0x0E<units><tens>)
0F45  LABEL_SEARCH       [T] walk RAM program registers looking for Lbl x
1364  LIB_LABEL_SEARCH   [T] same for a library program (header start/end)
12E1  PGM_SELECT         [T] Pgm nn: check against the module's program count
082B  LIB_EXEC_FETCH     [T] module keycode fetch; RST held → abort (0836)
0499  COND_TRANSFER      [T] x=t, x≥t, If flg, Dsz: branch on fA[9] (INV inverts)
15BA  FLAG_OP            [T] St flg / INV St flg: flag n = bit ⌊n/5⌋ of SCOM[0] nibble 11 + n mod 5
04E6  DISPLAY_PEEK       [T] light the display ~256 cycles (GTO held while a RAM program runs)
08E4  OP_DISPATCH        [T] Op nn: 00–19 table, 2x/3x register inc/dec, ≥ 40 nothing
0A00  OP_TABLE           [T] Op 00–19, slot 0x0A00 + 16·tens + units
1000  PRT_MNEMONIC_TABLE [T] 3-character PC-100 mnemonic per keycode (0x1000 + 32·tens + 3·units)
1680  CARD_IO            [T] magnetic card bank read/write (header, 30 registers, checksum)
11D9  HIR_STO            [T] HIR STO: X → hierarchy register SCOM[m]; the fast-mode chain writes m = 0 (SCOM[0])
00FA  HIR                [T] HIR nm sequence (keycode 82): n = 0 STO, 1 RCL, 3 SUM, 4 Prd, 5 INV SUM, 6 INV Prd; m = SCOM row 1–8
0B20  COMPACT_BANK       [T] compact keycodes by digit position: 92 RTN, 82 HIR, 83/84/72–74/62–64 Ind forms (0EA5)
141C  PGM_ERROR_HALT     [T] error blink and stop (e.g. Pgm out of range)
; Keycode sub-programs (Prg Src 8) are listed in rom/TI59-keycode-programs.asm.
