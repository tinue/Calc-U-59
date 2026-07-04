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
; (texas-print.ti59 scripted pseudo-code insertion: SBR 444 … P/R, LRN, Ins).
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
02E2  DISP_REBUILD       [T] display / working-register rebuild; drops pending trace record (02E3)

; ── Keyboard dispatch table and key handlers ────────────────────────────────
; The computed jump at 06B1 lands at 0x0<col><row>. Slots at x1–x9 only;
; x0/xA–xF addresses inside the table hold helper stubs (see the table
; annotations in TI59-commented.asm). Key identities follow from the matrix
; position encoding; [T] where a keypress trace exercised the slot.
0010  KEY_RET            [S] handler return vector (SR := 0x0100 at 06AB); sets KR[8], falls into 0011 → KEY_OP_ENTRY
0011  KEY_TABLE          [T] keyboard dispatch table (0011–0059)
0110  KEY_EE             [D] "EE" handler (slot 0025)
012D  KEY_LPAREN         [D] "(" handler (slot 0035)
013A  KEY_MUL            [D] "×"/"÷" stub (slots 0056/0055): op code 6 → KEY_ARITH; "÷" arrives with fA[1] set
013C  KEY_YX             [D] "y^x" stub (slot 0054): op code 10 → KEY_ARITH; fA[8] set → tags fA[1] (inverse pair)
0140  KEY_ARITH          [T] arithmetic-op common tail: sets fA[9], falls into KEY_OP_ENTRY; op code in R5 (+ − = 2 via 00A0, × ÷ = 6, y^x = 10; fA[1] = inverse-pair bit) — traced for "+"
0141  KEY_OP_ENTRY       [T] common pending-op/prefix recorder; operation code in R5, variants tagged via fA[1]/KR[8]/KR[9] (used by + − = STO RCL SUM …)
0163  DIGIT_SLIDE        [T] INC KR slide 0163–016C; digit d enters at 016C−d ("6"→0166 traced, "0"→016C traced)
020B  KEY_LNX            [D] "lnx" handler (slot 0032); R5 := 2, falls through 020F into FN_ENTRY
020F  FN_ENTRY_KR8       [D] FN_ENTRY variant: sets KR[8] first ("√x" enters here with R5=0)
0210  FN_ENTRY           [D] common unary-function entry; function code in R5 ("x²" R5=7, "1/x" R5=10)
0266  KEY_INV            [D] "INV" handler (slot 0022)
0268  KEY_2ND            [D] "2nd" handler (slot 0012); TOG fA[9]
027A  KEY_XT             [D] "x⇄t" handler (slot 0023)
0291  KEY_RST            [D] "RST" handler (slot 0018)
02AC  KEY_GTO            [D] "GTO" handler (slot 0016)
0318  KEY_DPT            [D] "." handler (slot 0039)
039F  KEY_CLR            [D] "CLR" handler (slot 0052); checks pending trace record (fA[10]) at entry
03B9  KEY_CE             [D] "CE" handler (slot 0042)
03E9  KEY_SBR            [D] "SBR" handler (slot 0017)
03F8  KEY_SST            [D] "SST" handler (slot 0014)
03FB  KEY_LRN            [D] "LRN" handler (slot 0013)
040A  KEY_RS             [D] "R/S" handler (slot 0019)
040B  KEY_BST            [D] "BST" handler (slot 0015)
0462  KEY_PR             [T] "P/R" handler (2nd slot 0073); launches the P→R keycode sub-program: Prg Src Flag := 8 via 0A4B–0A53
0B11  OP_INS             [T] "Ins" operation body (2nd slot 0064 → KEY_OP_ENTRY chain, vector 0xB11); per-register shift loop uses PRGREG_RAM_READ / PRGREG_CACHE / 1213
0089  KEY_PSEUDO_ADV     [D] pseudo table entry for the printer paper-ADVANCE key (remapped at 0679–0688)
0099  KEY_PSEUDO_PRINT   [D] pseudo table entry for the printer PRINT key (remapped at 0679–0688)

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
08B2  PRGREG_FETCH       [T] source-aware program-register fetch: dispatches on Prg Src Flag (SCOM[0] nibble 3) to CROM (082B), constant table (0B9D), or RAM (0EDB); fB[11] = SCOM[10] cache stale
0B9D  PRGREG_FETCH_CON   [T] constant-table branch of PRGREG_FETCH: step counter → row 16 + step/8 (index in KR[10:8]·8 + KR[6:4]), C=C+CON reads 8 packed keycodes (step 008 → row 17 traced)
0EDB  PRGREG_RAM_READ    [T] read a program register from RAM (RAM.OP read; register number in the next IO value, nibbles 3·2)
0F85  PRGREG_RAM_WRITE   [T] write a program register to RAM (RAM.OP write; specifier then data on the two following IO values)
0C10  PRGREG_CACHE       [T] cache the fetched program register in SCOM[10] (reused by LRN display and Ins/Del shift; never source-revalidated)

086F  STEP_TO_REG        [T] split a program-transfer target step into register·offset (÷8 loop), range-check the register against the program partition (SCOM[13] mantissa, 0887), and commit the new calculator PC to SCOM[0] (089A) or abandon at 0B0A

; ── Named instruction sites (not jump targets) ──────────────────────────────
02E3  —                  [T] CLR fA[10]: digit keys discard their pending trace record here
06B1  —                  [T] computed keyboard jump: PREG := 0x0<col><row> (redirects one instruction late)
0EFD  —                  [T] CLR fA[10] after the trace line is printed
1377  —                  [D] CROM module-header read (IN LIB); does not move the user-visible library PC
137C  —                  [D] CROM module-header read (IN LIB); same note as 1377
1390  —                  [D] CROM label-search read (LIB.HI/IN LIB); same note as 1377
1394  —                  [D] CROM label-search read (IN LIB); same note as 1377
