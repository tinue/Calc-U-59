# The Calendar Printer Competition

Source: [Calendar printing](https://www.ti59.com/calend.htm), by Palmer Hanson

A calendar printing program was one of the challenges accepted for HP and TI programmers during the so-called friendly competition sponsored by by Richard Vanderburgh of 52 Notes and Richard Nelson of the PPC Calculator Journal. For the TI-59 the effort ran from May 1978 through May 1981 and involved many of the most innovative programmers including the work of seven of the "TI-59 People" listed elsewhere in this site. The first calendar printing programs for the TI-59/PC-100 by Jaren Weinberger and Lou Cargile were published in the May 1978 issue of 52 Notes (v3n5). The programs required thirty-four minutes to print out a year. Richard Vanderburgh included a program of his own in the same issue which was based on the Weinberger and Cargile programs but which reduced the print time for a year to twenty-six minutes. The next issue of 52 Notes (v3n6, June 1978) published a revised program by Lou Cargile and Fred Fitzgerald which reduced the print time for a year to ten minutes, a program by Bill Skillman with a print time of seven and one-half minutes, a program by Panos Galidas using code methods devised by Maurice Swinnen which printed a year in five and one-half minutes, and a program by Richard Vanderburgh using the methods devised by Maurice, Bill and Panos which printed a year in five minutes. The July 1978 issue of 52 Notes (v3n7) published even faster programs by Lou Cargile and Panos Galidas that used HIR commands to increase the time to print a year to just under three minutes. The September 1978 issue of 52 Notes published a program by Panos Galidas which would print a year in just two minutes thirty-nine seconds. The program included extensive use of HIR commands and data packing using all thirteen digits of the data registers. At that time the best times for the HP product line were of the order of six minutes. Both the TI and HP programmers seem to have decided that they had done about all they could do and there was no further activity on calendar printing for almost two years.

Soon after the advent of the HP-41 in early 1980, Roger Hill wrote a program for that machine which would print a year in two minutes nineteen seconds. The July/August 1980 issue of the PPC Calculator Journal (v7n5) published Roger's program and claimed the lead for the HP product line for the first time. Their lead was short-lived, for Palmer Hanson had applied Martin Neef's fast mode technique to Panosa Galidas' program and the August 1980 issue of TI PPC Notes (v5n7) published his program which would print a year in only one minute thirty-two seconds. The December 1980 issue of TI PPC Notes (v5n9-10) reported that Palmer had reduced the printout time for the TI-59 to one minute twenty-six seconds by incorporating an idea by Richard Snow to separate print commands so that calculations would continue while printing was in progress. Late in 1980 Roger Hill responded with an HP-41 program which would print a year in just one minute fourteen seconds. That time was just one second more that the thoretical minimum printing time. Finally, in mid-1981 Patrick Acosta incorporated fast mode entry using the h12 technique into Palmer's program which made room for other improvements which reduced the print time for the TI-59 to one minute twenty-three seconds. That program was not published until March 1984 in the v9n2 issue of TI PPC Notes.

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
| Roger Hill, HP-41 | PPC Journal v7n5 (Jul/Aug 1980) | 2:19 | N/A — HP-41 program, not TI-59 | Elsewhere reported as 2:17 |
| Palmer Hanson (Neef's fast mode applied to Galidas's program) | TI PPC Notes v5n7 (Aug 1980) | 1:32 | **missing** | Confirmed present as a full listing on the source page, needs to be captured; elsewhere reported as 1:31; combines Galidas's v3n9p3-4 program with Neef's Fast Mode from v5n6p4 |
| Palmer Hanson (Richard Snow idea) | TI PPC Notes v5n9-10 (Dec 1980) | 1:26 | **missing** | v5n9-10 is a short article mentioning several programs; only the 1:26 one is actually listed and needs to be captured — the others it mentions were never published |
| Roger Hill, HP-41 (late 1980) | not given in the narrative | 1:14 | N/A — HP-41 program, not TI-59 | Elsewhere identified as PPC Journal v7n5p15 |
| Acosta | TI PPC Notes v9n2 (written mid-1981, published Mar 1984) | 1:23 | `calendar-08-acosta.ti59` | — |

Note: TI PPC Notes v5n8 — not mentioned in the narrative text at all — contains no calendar program listing of its own, only narrative text confirming Roger Hill's HP-41 program (2:17) and reaffirming that Palmer Hanson's v5n7 entry (1:31) was still the TI-59 champion.

### Missing TI-59 programs to look for

Both of these are confirmed present as full listings on the source page and just need to be captured:

1. **Palmer Hanson — TI PPC Notes v5n7** (Aug 1980, 1:32 per the narrative / 1:31 per the v5n8 follow-up, combines Galidas's v3n9p3-4 program with Neef's Fast Mode from v5n6p4).
2. **Palmer Hanson — TI PPC Notes v5n9-10** (Dec 1980, 1:26, incorporating Richard Snow's split-print idea) — the only program actually listed in this short article; the others it mentions were never published.

Described in the narrative, but no matching full listing found on the source page — status unclear, may not exist in recoverable form:

- **Cargile & Fitzgerald (revised) — 52 Notes v3n6** (10 min).

Never published, so not recoverable — mentioned only secondhand in other articles, despite the narrative implying independent publication:

- **Galidas (Swinnen method) — 52 Notes v3n6** (5.5 min) — per Vanderburgh's own v3n6 article, only his modified version was ever printed.
- **Galidas (HIR) — 52 Notes v3n7** (July 1978, ~3:15–3:17 per other articles' mentions) — no separate listing exists in v3n7 itself; distinct from the September v3n9 program already captured as `calendar-07-calidas.ti59`.

Not applicable (HP-41, not TI-59): Roger Hill's v7n5 (2:19, elsewhere 2:17) and late-1980 (1:14) programs.
