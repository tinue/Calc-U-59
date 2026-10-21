; ═══════════════════════════════════════════════════════════════════════════
; TI-58C KEYCODE ROM — the built-in keycode sub-programs
; 384 program steps stored in constant-ROM rows 16–63 (CD2400/CD2401 CONST-K,
; 8 keycodes per row), executed with Prg Src Flag 8 (PRGREG_FETCH_CON 0x0B95).
; Generated from roms/calculator/CD2400-CONST-K.txt + CD2401-CONST-K.txt with
; the mnemonics of rom/TI59-keycode-programs.asm; entry steps trace-confirmed
; with the headless harness (--variant TI58C; scenarios dms, p2r, r2p, sigma,
; mean, stddev, op11–op15 of tools/headless/coverage.py; the launch target is
; the first step executed) — identical to the TI-59's. Operand bytes (register
; numbers, labels, flags, Hir numbers) follow their instruction and are shown
; as numbers; GTO takes two (absolute step, high/low).
; Differences from the TI-59 (TMC0582/0583) marked `; Δ`: step 031 (row 19)
; and steps 251–283 (rows 47–51, R→P). Rows 0–15 (numeric constants) are
; identical.
; ═══════════════════════════════════════════════════════════════════════════


; ── step 000: Op 12 / Op 14 / Op 15 (shared start: least-squares sums) ──
000  82  HIR
001  08        operand
002  53  (
003  53  (
004  43  RCL
005  06        operand
006  75  −
007  43  RCL
008  04        operand
009  65  ×
010  43  RCL
011  01        operand
012  55  ÷
013  43  RCL
014  03        operand
015  54  )
016  55  ÷
017  53  (
018  43  RCL
019  05        operand
020  75  −
021  43  RCL
022  04        operand
023  33  X²
024  55  ÷
025  43  RCL
026  03        operand
027  54  )
028  54  )
029  53  (
030  53  (
031  29  CP                   ; Δ [FIX] TI-59: CE, which cleared the error of a 0/0 or x/0 slope
032  65  ×                    ; (CP clears t; harmless, t := slope at X⇄T next)
033  32  X⇄T
034  43  RCL
035  04        operand
036  94  +/-
037  85  +
038  43  RCL
039  01        operand
040  54  )
041  55  ÷
042  43  RCL
043  03        operand
044  54  )
045  82  HIR
046  20        operand
047  53  (
048  53  (
049  94  +/-
050  85  +
051  82  HIR
052  18        operand
053  54  )
054  55  ÷
055  32  X⇄T
056  54  )
057  92  RTN
058  53  (
059  32  X⇄T
060  65  ×
061  82  HIR
062  18        operand
063  85  +
064  32  X⇄T
065  54  )
066  92  RTN

; ── step 067: x̄ (mean) and Op 11 (variance) ──
067  53  (
068  43  RCL
069  04        operand
070  55  ÷
071  43  RCL
072  03        operand
073  54  )
074  32  X⇄T
075  53  (
076  43  RCL
077  01        operand
078  55  ÷
079  43  RCL
080  03        operand
081  54  )
082  82  HIR
083  20        operand
084  33  X²
085  53  (
086  94  +/-
087  85  +
088  43  RCL
089  02        operand
090  55  ÷
091  43  RCL
092  03        operand
093  54  )
094  32  X⇄T
095  33  X²
096  53  (
097  94  +/-
098  85  +
099  43  RCL
100  05        operand
101  55  ÷
102  43  RCL
103  03        operand
104  54  )
105  32  X⇄T
106  92  RTN

; ── step 107: INV x̄ (standard deviation σ) ──
107  53  (
108  53  (
109  43  RCL
110  05        operand
111  75  −
112  43  RCL
113  04        operand
114  33  X²
115  55  ÷
116  43  RCL
117  03        operand
118  54  )
119  55  ÷
120  53  (
121  43  RCL
122  03        operand
123  75  −
124  01  1
125  54  )
126  82  HIR
127  08        operand
128  54  )
129  34  √X
130  32  X⇄T
131  53  (
132  53  (
133  43  RCL
134  02        operand
135  75  −
136  43  RCL
137  01        operand
138  33  X²
139  55  ÷
140  43  RCL
141  03        operand
142  54  )
143  55  ÷
144  82  HIR
145  18        operand
146  54  )
147  34  √X
148  92  RTN

; ── step 149: Op 13 (correlation coefficient) ──
149  53  (
150  53  (
151  43  RCL
152  06        operand
153  75  −
154  43  RCL
155  04        operand
156  65  ×
157  43  RCL
158  01        operand
159  55  ÷
160  43  RCL
161  03        operand
162  54  )
163  55  ÷
164  53  (
165  53  (
166  43  RCL
167  05        operand
168  75  −
169  43  RCL
170  04        operand
171  33  X²
172  55  ÷
173  43  RCL
174  03        operand
175  54  )
176  65  ×
177  53  (
178  43  RCL
179  02        operand
180  75  −
181  43  RCL
182  01        operand
183  33  X²
184  55  ÷
185  43  RCL
186  03        operand
187  54  )
188  54  )
189  34  √X
190  54  )
191  92  RTN

; ── step 192: Σ+ ──
192  44  SUM
193  01        operand
194  82  HIR
195  08        operand
196  33  X²
197  44  SUM
198  02        operand
199  32  X⇄T
200  44  SUM
201  04        operand
202  82  HIR
203  48        operand
204  82  HIR
205  07        operand
206  33  X²
207  44  SUM
208  05        operand
209  01  1
210  61  GTO                  ; GTO 236 (two operand bytes): count += 1, shared with INV Σ+
211  02        operand
212  36        operand

; ── step 213: INV Σ+ ──
213  94  +/-
214  44  SUM
215  01        operand
216  82  HIR
217  08        operand
218  33  X²
219  94  +/-
220  44  SUM
221  02        operand
222  32  X⇄T
223  22  INV
224  44  SUM
225  04        operand
226  82  HIR
227  48        operand
228  82  HIR
229  07        operand
230  33  X²
231  94  +/-
232  44  SUM
233  05        operand
234  01  1
235  94  +/-
236  44  SUM
237  03        operand
238  82  HIR
239  37        operand
240  82  HIR
241  18        operand
242  44  SUM
243  06        operand
244  82  HIR
245  17        operand
246  32  X⇄T
247  43  RCL
248  03        operand
249  92  RTN

; ── step 250: INV P→R (R→P) ──
; Δ [FIX] TI-59 steps 251–283 rewritten (TI-59: r = √(y² + x²) with y → Hir 8,
;   x → Hir 7, then θ = acos(x/|x|) + atan(y/x), then CE, RTN). TI-58C: θ first,
;   then CE, then r, so CE only clears the deliberate 0/0 of the quadrant trick (x = 0) and an
;   overflow/underflow in x² + y² now flashes (the TI-59's final CE hid it,
;   leaving e.g. r = 1E50 for y = 2E50). Uses Hir 8 only (TI-59: Hir 7 and 8).
;   In: x in t, y in display. Out: θ in display, r in t. 32 steps (TI-59: 34).
250  53  (                    ; θ = atan(y/x) + acos(x/|x|):
251  53  (
252  24  CE                   ; Δ clear an incoming error (step 270 would too)
253  55  ÷                    ; Δ y ÷ …
254  32  X⇄T                  ; Δ … x (display x, t := y)
255  82  HIR                  ; Δ Hir 8 := x
256  08        operand
257  54  )                    ; Δ y/x
258  22  INV
259  30  TAN                  ; Δ atan(y/x)
260  85  +
261  53  (
262  82  HIR                  ; Δ x
263  18        operand
264  55  ÷
265  50  |X|                  ; Δ x/|x| = ±1 (0/0 = 1 with error at x = 0)
266  54  )
267  22  INV
268  39  COS                  ; Δ acos: 0° or 180°
269  54  )                    ; Δ θ
270  24  CE                   ; Δ clear the 0/0 or x/0 error of x = 0 (TI-59: at the end)
271  53  (
272  32  X⇄T                  ; Δ y (t := θ)
273  33  X²                   ; Δ y²
274  85  +
275  82  HIR                  ; Δ x
276  18        operand
277  33  X²                   ; Δ x²
278  54  )
279  34  √X                   ; Δ r (an overflow now keeps flashing)
280  32  X⇄T                  ; Δ display θ, t := r
281  92  RTN                  ; Δ (TI-59: step 283)
282  00  0                    ; Δ unused (TI-59 282–283: CE, RTN)
283  00  0                    ; Δ unused

; ── step 284: P→R ──
284  53  (
285  82  HIR
286  08        operand
287  39  COS
288  65  ×
289  32  X⇄T
290  82  HIR
291  07        operand
292  54  )
293  32  X⇄T
294  53  (
295  82  HIR
296  18        operand
297  38  SIN
298  65  ×
299  82  HIR
300  17        operand
301  54  )
302  92  RTN

; ── step 303: D.MS ──
303  53  (
304  53  (
305  53  (
306  82  HIR
307  08        operand
308  59  INT
309  65  ×
310  06  6
311  00  0
312  85  +
313  53  (
314  82  HIR
315  18        operand
316  22  INV
317  59  INT
318  65  ×
319  01  1
320  00  0
321  00  0
322  54  )
323  82  HIR
324  08        operand
325  59  INT
326  54  )
327  65  ×
328  93  .
329  06  6
330  85  +
331  82  HIR
332  18        operand
333  22  INV
334  59  INT
335  54  )
336  55  ÷
337  03  3
338  06  6
339  54  )
340  92  RTN

; ── step 341: INV D.MS ──
341  53  (
342  53  (
343  82  HIR
344  08        operand
345  59  INT
346  85  +
347  82  HIR
348  18        operand
349  22  INV
350  59  INT
351  65  ×
352  93  .
353  06  6
354  54  )
355  65  ×
356  01  1
357  00  0
358  00  0
359  54  )
360  82  HIR
361  08        operand
362  53  (
363  53  (
364  59  INT
365  85  +
366  82  HIR
367  18        operand
368  22  INV
369  59  INT
370  65  ×
371  93  .
372  06  6
373  54  )
374  65  ×
375  93  .
376  00  0
377  01  1
378  54  )
379  92  RTN
380  00  0
381  00  0
382  00  0
383  00  0
