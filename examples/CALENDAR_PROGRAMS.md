# The Calendar Printer Competition

Source: [Calendar printing](https://www.ti59.com/calend.htm), by Palmer Hanson

A calendar printing program was one of the challenges accepted for HP and TI programmers during the so-called friendly competition sponsored by Richard Vanderburgh of 52 Notes and Richard Nelson of the PPC Calculator Journal. For the TI-59 the effort ran from May 1978 through May 1981 and involved many of the most innovative programmers including the work of seven of the "TI-59 People" listed elsewhere in this site. The first calendar printing programs for the TI-59/PC-100 by Jaren Weinberger and Lou Cargile were published in the May 1978 issue of 52 Notes (v3n5). The programs required thirty-four minutes to print out a year. Richard Vanderburgh included a program of his own in the same issue which was based on the Weinberger and Cargile programs but which reduced the print time for a year to twenty-six minutes. The next issue of 52 Notes (v3n6, June 1978) published a revised program by Lou Cargile and Fred Fitzgerald which reduced the print time for a year to ten minutes, a program by Bill Skillman with a print time of seven and one-half minutes, a program by Panos Galidas using code methods devised by Maurice Swinnen which printed a year in five and one-half minutes, and a program by Richard Vanderburgh using the methods devised by Maurice, Bill and Panos which printed a year in five minutes. The July 1978 issue of 52 Notes (v3n7) published even faster programs by Lou Cargile and Panos Galidas that used HIR commands to increase the time to print a year to just under three minutes. The September 1978 issue of 52 Notes published a program by Panos Galidas which would print a year in just two minutes thirty-nine seconds. The program included extensive use of HIR commands and data packing using all thirteen digits of the data registers. At that time the best times for the HP product line were of the order of six minutes. Both the TI and HP programmers seem to have decided that they had done about all they could do and there was no further activity on calendar printing for almost two years.

Soon after the advent of the HP-41 in early 1980, Roger Hill wrote a program for that machine which would print a year in two minutes nineteen seconds. The July/August 1980 issue of the PPC Calculator Journal (v7n5) published Roger's program and claimed the lead for the HP product line for the first time. Their lead was short-lived, for Palmer Hanson had applied Martin Neef's fast mode technique to Panos Galidas' program and the August 1980 issue of TI PPC Notes (v5n7) published his program which would print a year in only one minute thirty-two seconds. The December 1980 issue of TI PPC Notes (v5n9-10) reported that Palmer had reduced the printout time for the TI-59 to one minute twenty-six seconds by incorporating an idea by Richard Snow to separate print commands so that calculations would continue while printing was in progress. Late in 1980 Roger Hill responded with an HP-41 program which would print a year in just one minute fourteen seconds. That time was just one second more than the theoretical minimum printing time. Finally, in mid-1981 Patrick Acosta incorporated fast mode entry using the h12 technique into Palmer's program which made room for other improvements which reduced the print time for the TI-59 to one minute twenty-three seconds. That program was not published until March 1984 in the v9n2 issue of TI PPC Notes.

## Programs present vs. missing

The "Volume/Issue" and "Time" columns are taken directly from the narrative text above. The "Notes" column records what checking the actual program listings on the source page turned up — which don't always match the narrative exactly.

| Text description | Volume/Issue (per text) | Time (per text) | File | Notes |
|---|---|---|---|---|
| Weinberger & Cargile | v3n5 (May 1978) | 34 min | `calendar-01-Weinberger.ti59` (+ `calendar-02-cargile.ti59`) | — |
| Vanderburgh (1st) | v3n5 | 26 min | `calendar-03-vanderburgh.ti59` | — |
| Cargile & Fitzgerald (revised) | v3n6 (June 1978) | 10 min | **missing** | No full listing found on the source page beyond Skillman's and Vanderburgh's (byline "Ed") v3n6 programs |
| Skillman | v3n6 | 7.5 min | `calendar-04-skillman.ti59` | — |
| Galidas (Swinnen method) | v3n6 | 5.5 min | never published | Per Vanderburgh's own v3n6 article, only *his* modified version was printed — the program as received from Galidas never appeared in print, despite the narrative implying it was published independently |
| Vanderburgh (2nd, Maurice/Bill/Panos methods) | v3n6 | 5 min | `calendar-05-vanderburgh.ti59` | Published under byline "Ed" — Vanderburgh, as editor of 52 Notes |
| Cargile (HIR) | v3n7 (July 1978) | just under 3 min | `calendar-06-cargile.ti59` (corrected — file was mislabeled V3N6) | Article gives the precise time: 2:57 |
| Galidas (HIR) | v3n7 | just under 3 min | never published | Only mentioned secondhand (~3:15–3:17) in other articles — e.g. `calendar-06-cargile.ti59`'s header ("Lou barely edging out Panos 3 min 15 sec to 3 min 17 sec") and `calendar-07-calidas.ti59`'s header ("Lou's V3N7p4 program") — v3n7 itself lists no separate Galidas program; distinct from the September program below |
| Galidas (HIR + full 13-digit packing) | Sept 1978 (v3n9) | 2:39 | `calendar-07-calidas.ti59` (corrected — file was mislabeled V3N7) | Article gives 2:38.6 |
| Roger Hill, HP-41 | PPC Journal v7n5 (Jul/Aug 1980) | 2:19 | N/A — HP-41 program, not TI-59 | Elsewhere reported as 2:17. The Jul/Aug 1980 issue is v7n6 (p15, per [Gene Wright's listing](https://www.rskey.org/gene/calcgene/41cal.htm)); v7n5 is June 1980 |
| Palmer Hanson (Neef's fast mode applied to Galidas's program) | TI PPC Notes v5n7 (Aug 1980) | 1:32 | **missing** | Confirmed present as a full listing on the source page, needs to be captured; elsewhere reported as 1:31; combines Galidas's v3n9p3-4 program with Neef's Fast Mode from v5n6p4 |
| Palmer Hanson (Richard Snow idea) | TI PPC Notes v5n9-10 (Dec 1980) | 1:26 | **missing** | v5n9-10 is a short article mentioning several programs; only the 1:26 one is actually listed and needs to be captured — the others it mentions were never published |
| Roger Hill, HP-41 (late 1980) | not given in the narrative | 1:14 | N/A — HP-41 program, not TI-59 | PPC Calculator Journal v7n8p18 (Oct 1980), per the program index of Ángel Martin's [HP-41 Vintage Games collection](https://literature.hpcalc.org/community/hp41-games-vol1.pdf). TI PPC Notes v9n2 cites it as v7n5p15, a mix-up with the Jul/Aug program. The 1:14 is Hill's own figure, reported in TI PPC Notes v5n9-10p3 as "1 sec above the theoretical maximum speed"; the PPC Journal article itself was not checked |
| Acosta | TI PPC Notes v9n2 (written mid-1981, published Mar 1984) | 1:23 | `calendar-08-acosta.ti59` | — |

Note: TI PPC Notes v5n8 — not mentioned in the narrative text at all — contains no calendar program listing of its own, only narrative text confirming Roger Hill's HP-41 program (2:17) and reaffirming that Palmer Hanson's v5n7 entry (1:31) was still the TI-59 champion.

Still to capture from the source page: the two Palmer Hanson programs (v5n7 and v5n9-10). The Cargile & Fitzgerald program has no listing there; the two Galidas programs marked "never published" cannot be recovered.

## Comparison of the programs

Times are emulated seconds in the Calc-U-59 headless harness for 2026, from
the key that starts the year's printing to the last printed line. Each
program's own preparation after that key is included. "Published" is the
time given in the article, for 1978 (52 Notes) or 2000 (Acosta) on a real
TI-59. Steps are the program length without trailing zero steps.

| File | Published | Emulator (2026) | Steps | Technique introduced |
|---|---|---|---|---|
| `calendar-01-Weinberger.ti59` | 34 min | 34:55 | 442 | ML-20 gives the weekday of each 1st, and February's length from a day-number difference. Each line fills a block of 7 registers with day numbers and converts them to print codes with a translator routine. (This file prints a February 29 in 2026; not investigated.) |
| `calendar-02-cargile.ti59` | 34 min | 34:37 | 382 | Month lengths by tests (leap year, February, odd/even month, July/August). A "quasi base seven" counter supplies the print code of each next day directly. |
| `calendar-03-vanderburgh.ti59` | 26 min | 25:59 | 452 | ML-20 SBR 086 day numbers give the month length as a difference, SBR 177 the weekday. One general print-buffer packing routine serves every line. |
| `calendar-04-skillman.ti59` | 7.5 min | 7:28 | 308 | A block of consecutive registers, each holding the print code of one day, from which any line is packed. The revision replaces x:t comparisons by INV Dsz and uses equally spaced GTOs for a double-indirect jump. |
| `calendar-05-vanderburgh.ti59` | under 5 min | 4:51 | 720 | Swinnen's doubled print codes (two days per register, via Galidas). HIR 5-8 fill the print buffer directly instead of Op 1-4. Prestored data in the program area. |
| `calendar-06-cargile.ti59` | 2:57 | 2:56 | 320 | HIR print-code processing with chosen integer/fraction parts: the integer part 2 of an entry is also the pointer step (the "2-trick"). As much code in line as memory allows. |
| `calendar-07-calidas.ti59` | 2:38.6 | 2:38 | 366 | Full 13-digit data packing. One division (start weekday + month length) / 7 gives the number of full rows and the next month's start day. The last line is packed in reverse order. |
| `calendar-08-acosta.ti59` | 1:23 | 1:21 | 398 | Fast mode (Neef, applied to Galidas' program by Hanson). Separate print commands so that calculation goes on while the printer runs (Snow). The "hi2" fast-mode entry from inside the program, which frees the ML-20 module for the preparation. |
| `calendar-09-dispatch.ti59` | (2026) | 1:16 | 397 | Each month record holds the address of a small routine for the change of month length (GTO Ind). The month loop reads the record first and jumps to the routine, which copies at most four table entries, sets a threshold and goes on to the header lines. A 13th record ends the run, so no month counter is needed. The number of rows follows from one comparison. The preparation is plain arithmetic in fast mode, so no module is needed. The SST fast-mode entry is typed. |

The emulator times match the published ones within a few seconds, although
the published times are for other years. The last four programs share one
row engine (Galidas' table of two-day entries); with it a printed line costs
0.89 s, and 61 to 64 lines a year are most of the run time. The later gains
come from the work per month. Fast mode and its entry methods, including
Acosta's "hi2", are explained in `rom/fastmode.md`; the timing tools are in
`tools/agentic/`.

Measured the same way, counting all program run time after the year is
keyed in (Acosta's normal-mode preparation, the new program's fast-mode
preparation):

| Year | Acosta | `calendar-09-dispatch` |
|---|---|---|
| 1900 | 82.6 s | 76.3 s |
| 2000 | 83.5 s | 78.3 s |
| 2024 | 81.8 s | 76.4 s |
| 2026 | 80.8 s | 75.2 s |

Both programs print the same lines for every year from 1899 to 2101, and
the dates agree with Python's `calendar` module. Acosta's program
prints any number of months from any start month; the new one prints one
whole year.
