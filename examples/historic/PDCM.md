# PDCM: an operating system for the TI-59

PDCM was published by Horst Umlauf as "Karten-Tricks" in the German magazine
CHIP, issue 8/1979, pp. 40-44. His corrections, written in reply to readers who
could not get it running, are in CHIP 10/1979, p. 12. This guide follows the
corrected version.

> **How this guide was made.** It was written by an AI (Claude) from the two
> articles and the program itself. The key sequences were run on the Calc-U-59
> emulator, which executes the original TI ROM, but not on a real calculator.
> The keying tricks were tried on samples of each kind; nobody has keyed in all
> 756 steps this way. The demo program in section 8 is new. The article had
> none, which is what its readers complained about.

If you only want to watch it work, load `pdcm-card-tricks.ti59` in Calc-U-59.
The preset holds all the cards, starts the system and runs the demo by itself.
To work the system yourself without keying anything in, follow
[`PDCM-Emulator.md`](PDCM-Emulator.md). The rest of this guide is for doing it
all by hand.

## 1. The problem PDCM solves

You know the limit: 960 steps or 100 registers, and everything has to fit at
once. Magnetic cards hold more, but your program has to manage them. It must
stop at the right moment, write the old data out, read the new data in, and hope
that you pushed in the right card. Every program solves this again in its own
way.

PDCM does this work once, for all your programs. A program simply says "I want
memory number 135" or "continue at step 125 of program strip 123". PDCM then:

1. works out which card holds it,
2. shows you that card's number and stops,
3. waits for R/S and reads the card,
4. checks that it was the right card, and asks again if it wasn't.

So you get something like virtual memory, with you as the disk drive.

## 2. Three words you need

- **Strip:** one side of a magnetic card. PDCM treats each side as a separate
  unit with its own number.
- **C-memory:** a numbered memory that lives on a data strip rather than in the
  calculator. The number has no fixed limit.
- **Eng display:** PDCM always shows card numbers in Eng format, so you can tell
  them from your own results. The strip number `.012` appears as `12. -03`, and
  this guide writes it `12.-03`. **Write these numbers on your cards exactly as
  they are displayed.**

If the calculator stops with a display that is *not* in Eng, PDCM is not waiting
for you. Either you can start something, or a program has stopped.

## 3. How the memory is divided

PDCM always uses partition `4 2nd Op 17`, which gives 639.39.

| Part | Holds | Used for |
|---|---|---|
| Block 1 | steps 000-239 | your main program strip |
| Block 2 | steps 240-479 | a strip with your subroutines |
| Block 3 | steps 480-639 and R30-R39 | PDCM's routines and its working registers |
| Block 4 | R00-R29 | the current data card |

Only blocks 1, 2 and 4 are ever swapped. Block 3 stays in the calculator, so R30
to R39 are the only registers that survive a change of data card.

## 4. Building it: keying in

You need to enter three listings, 756 steps in all. They are in Bild 9 of the
article and, with their mnemonics, in the `CARD:` blocks of
`pdcm-card-tricks.ti59`.

| Listing | Steps | In the preset |
|---|---|---|
| a | 000-435 | `mem:S11` and `mem:S998` |
| c | 480-639 | `mem:S999` |
| b | 000-159 | `mem:S1` |

The caption of Bild 9 is wrong. Use the strip numbers in section 5 below.

Most of it is ordinary keying. A few reminders:

- An address takes three digits: `GTO 5 6 6` appears as the two steps `05 66`.
- `RCL 2nd Ind 3 2` is stored as the single step `73` with `32` after it. The
  same goes for `STO 2nd Ind` (`72`). `RTN` in the listing is `INV SBR` (`92`).
- Digits inside a listing are often printer text. `1 6 1 3 3 7 1 3` is "DATA".
  Key them like any number.

### The steps you cannot key directly

PDCM uses a few steps the keyboard refuses to enter. Each one has a trick. Do
them where the listing reaches them, while everything behind is still empty,
because `Del` moves all later steps.

**HIR n** (keycode `82`, here for `82 17`). This also explains why a `STO` is
keyed: it makes the calculator accept `82` as an operand.

```
STO 8 2  STO 1 7        4 steps: 42 82 42 17
BST BST BST BST         back to the first STO
2nd Del  SST            removes it; 82 stays, go past it
2nd Del  SST            removes the second STO; 17 stays, go past it
```

**Dsz with a register above 9** (here `97 32 00 24`). A normally keyed `Dsz` only
takes registers 0-9, so key one, replace it by `STO`, and put the `Dsz` back:

```
2nd Dsz 1 0 2 4         4 steps: 97 01 00 24
BST BST BST BST         back to the Dsz
STO 3 2                 overwrites two steps: 42 32 00 24
BST BST                 back to the STO
2nd Dsz                 overwrites it: 97 32 00 24
SST SST SST             go on behind the address
```

**Lbl HIR and SBR HIR** (`76 82` and `71 82`):

```
STO 8 2                 2 steps: 42 82
BST BST                 back to the STO
2nd Lbl  (or SBR)       overwrites it
SST                     go on behind the 82
```

Where you need them:

| Listing | HIR n | Dsz | Other |
|---|---|---|---|
| a | 174, 178, 182, 186, 190, 230, 242 | 030, 168, 216, 279 | Lbl HIR at 284 |
| b | 033, 037, 041, 045, 049, 143 | 029, 078 | |
| c | 585, 599, 611, 619 | | SBR HIR at 613 |

The listings have no checksum. With a printer, compare `2nd List` against the
article line by line before you write the cards. A wrong digit may show up only
much later, in a rarely used branch.

## 5. Building it: writing the cards

Do it in this order, so that listing b does not overwrite a before a is saved.
Two magnetic cards are enough.

1. Turn the calculator off and on. Press `4 2nd Op 17 CLR`.
2. Press `RST LRN`, key in **listing a**, press `LRN`.
3. Press `1 2nd Write` and push in the first card. Mark that side **11.-03**.
4. Press `2 2nd Write` and push in the other side. Mark it **-998.-03**.
5. Press `GTO 4 8 0 LRN`, key in **listing c**, press `LRN`.
6. Press `3 2nd Write` and use the second card. Mark that side **-999.-03**.
7. Turn the calculator off and on. Press `4 2nd Op 17 CLR`.
8. Press `RST LRN`, key in **listing b**, press `LRN`.
9. Press `1 2nd Write` and use the other side of the second card. Mark it
   **1.-03**.

Keep some blank cards ready, and mark two sides **-1. 00** and **-2. 00**. Card
-1 holds your standard settings, and card -2 holds the state at shutdown.

## 6. The first start: generation

The first time, PDCM has no settings yet. You give them to it in a run called
*generation*, and it prints what it is asking for.

| Do this | What happens |
|---|---|
| `4 2nd Op 17 CLR` | partition 639.39 |
| Push in **11.-03** | the strip is read |
| `RST R/S` | shows `-999. -03` (`RST` alone does not start anything, whatever the article says) |
| `2nd St flg 7` | requests generation |
| `R/S`, push in **-999.-03** | shows `-998. -03` |
| `R/S`, push in **-998.-03** | shows `-1. 00` |
| `2nd St flg 8`, `R/S` | card -1 is new, so nothing is read; prints `30. STO` |

PDCM now shows each setting, printing its name. Key in a new value or leave it,
and press `R/S`:

| Printed | What it is | Suggestion |
|---|---|---|
| `30. STO` | base number for C-memories (see section 8) | 0 |
| `33. STO` ... `39. STO` | your own registers | 0 |
| `3. HIR` ... `6. HIR` | HIR registers | 0 |
| `7. HIR` | **the next strip to load** | `.011`, or your own strip |
| `0. FLAG` ... `6. FLAG` | flags: anything but 0 sets it | 0 |
| `7. DATA` | the first data card | 0 |

`7. HIR` must not be 0. If everything is 0, PDCM decides that it has nothing to
do and starts asking all over again.

Then it finishes:

| Do this | What happens |
|---|---|
| | prints `DATA AREA NOT EMPTY`, `DESTRUCT = ST FLG 8`, shows `0.1`. This is normal here: your settings are in the data area |
| `R/S` | shows `-1. 00`: time to save the settings |
| `R/S`, push in the card **-1. 00** | settings written; shows `0. 00`, the first data card |
| `2nd St flg 8`, `R/S` | card 0 is new; prints `0.2 O.K` |

The system is now running. If you named a strip other than `.011`, PDCM shows its
number and you feed it in with `R/S`.

**Without a printer:** you see the values but not their names, so counting is
hard. At the first `0` in the display, press `SBR 4 1 4` instead. It takes the
standard settings and asks for `-999.-03` and `-998.-03` once more. Then press
`R/S` at `0.1`.

## 7. Using the system: C-memories

Once you see `O.K`, try it from the keyboard. Store 25 in C-memory 135:

```
25 + 135 SBR 4 8 0
```

135 is on data card 4, so PDCM shows `4. 00`. The card doesn't exist yet, so
press `2nd St flg 8 R/S`. PDCM prepares an empty card and returns. Now finish:

```
0 ) STO 2nd Ind 3 1
```

The odd formula is needed because `SBR 480` destroys the display. Your value
waits in the pending addition, and `0 )` brings it back. `SBR 480` leaves the
register number in R31, and `STO Ind 31` stores through it. In detail:

```
card     = Int((n + R30 - 1) / 29)     135 -> card 4
register = n + R30 - 29 x card         135 -> R19
```

Each data card holds 29 values, in R01-R29. R00 holds the card's own number, so
**your programs must never change R00**.

To read a value back:

```
135 SBR 4 8 0   RCL 2nd Ind 3 1
```

### What a card change looks like

Whenever a new data card is needed, you get two stops:

| Display | Meaning | You do |
|---|---|---|
| old card's number | it has to be saved | `R/S`, push in that card |
| new card's number | it has to be read | `R/S`, push in that card |

For the second stop, on a card's first use, press `2nd St flg 8 R/S` and don't
push in anything. You get an empty card with the right number.

PDCM checks only the card it reads. If it was the wrong one, the number simply
appears again. **Nothing checks the card it writes:** whatever you push in gets
overwritten. That is why the marks on your cards matter.

### Flag 8: don't save this card

If flag 8 is set when a card change begins, the first stop is skipped and the old
card is not saved. A program sets it when it only read data.

**A trap:** after `O.K`, flag 8 is set, because PDCM assumes that nothing has
changed yet. If you store into the card that is already active, the next card
change throws that value away. A program that writes should therefore begin with
`INV 2nd St flg 8`, as the demo does.

While PDCM waits at a stop, the article allows only these keys: `CE`, `(INV) 2nd
St flg n`, `(INV) 2nd Fix n` and `R/S`.

## 8. Writing your own program

Your program goes into block 1 (steps 000-239) on its own strip. It needs only
one thing: a way for PDCM to recognize it. Choose a number below 1, such as
`.012`, and put this anywhere on the strip:

```
2nd Lbl 2nd Lbl . 0 1 2 INV SBR
```

A block 2 strip is the same, but with a negative number and `Lbl HIR` (see
section 4): `Lbl HIR . 1 1 1 +/- INV SBR`.

Your program may use:

- **C-memories**, as in section 7.
- **R33-R39**, for counters and anything that must survive card changes.
- **R01-R29** directly, if you handle the data card yourself.

Leave these alone: R00, R30, R31, R32, flags 7 and 8, and `2nd CMs`. `Dsz` on a
register above 9 needs the trick from section 4, and `Op 20`-`Op 39` work on R00-R09
only.

If different programs need separate C-memories, give them different base numbers
in R30. A program using memories 1-200 leaves the next one free to start at 201.

### Moving between strips

| You want | In a program | Note |
|---|---|---|
| Load data card 12 of strip .123 | `12.123 SBR 5 0 8` | Whole numbers and 0 belong to C-memories. The article reserves 1-25 for data of the same-numbered module program |
| Go to step 125 of strip .123 | `125.123 GTO 5 6 6` | From the keyboard, follow it with `R/S` |
| Call step 125 of strip .123 | `125.123 SBR 5 6 7` | PDCM reloads your strip afterwards |
| Load block 2 strip -.111 | `.111 +/- SBR 6 1 0` | Don't call it from a block 2 strip |

Three things to watch:

- **T is lost** in all of these except `SBR 610`, and after `SBR 567` the display
  holds a strip number. Pass results in R33-R39.
- **Don't use `SBR 567` for the strip that is already loaded.** It doesn't record
  who called, so it asks afterwards for whichever strip it noted last.
- **A subroutine called by `SBR 567` must not use `Op 03` or `Op 00`.** PDCM's
  return address is in HIR 7, which shares its memory with the print zone of
  `Op 03`. Likewise `Op 04` shares memory with HIR 8 during `SBR 610`.

### An example: the demo

Strip **12.-03** writes the squares of 20, 40 and 60 to C-memories, which lie on
three different data cards. Then it moves on to the next strip.

```
000  Lbl A
002  INV St flg 8                  we are going to write
005  3 STO 34                      three rounds
008  20 STO 33                     first memory number
012  ( RCL 33 x² + RCL 33 SBR 480 0 ) STO Ind 31
026  20 SUM 33
030  Dsz 34 012                    register 34: use the trick
034  .013 GTO 566                  on to strip 13.-03
050  16323117 Op 04                the text DONE
060  3 Op 06 RTN                   a subroutine that prints it
064  Lbl Lbl .012 RTN
```

Strip **13.-03** reads them back, calls the subroutine on the other strip, and
shuts down.

```
000  3 STO 34
003  20 STO 33
007  RCL 33 Prt SBR 480 RC* 31 Prt
016  20 SUM 33
020  Dsz 34 007
024  50.012 SBR 567                print DONE on strip 12.-03
033  .001 SBR 567                  shut down
040  Lbl Lbl .013 RTN
```

Write each strip with `1 2nd Write`, with nothing else in block 1. Then:

1. At a start, enter `.012` for `7. HIR`, and feed the strip when it is asked for.
2. Press `A`, and follow the displays. A card goes through the reader 15 times,
   and the `KEYSTROKES:` section of the preset lists each one.

The printout ends like this:

```
    20.
   400.
    40.
  1600.
    60.
  3600.
     3.    DONE
GOOD-BYE FROM PDCM
```

## 9. Stopping and starting again

**To stop,** press `CLR . 0 0 1 SBR 5 6 7`. PDCM saves your registers, HIR
registers and flags on card -2, so you can continue later.

| Display | You do |
|---|---|
| `1. -03` | `R/S`, push in **1.-03** |
| your data card's number (only if it changed) | `R/S`, push in that card |
| `-2. 00`, once or twice | Each time: `R/S`, push in card **-2** |

Only at the very first shutdown, when card -2 doesn't exist yet, press `2nd St
flg 8 R/S` without a card at the first `-2. 00`.

It prints `GOOD-BYE FROM PDCM` and shows `1.1`. You may now turn the calculator
off.

**To start again,** you need no generation:

| Do this | What happens |
|---|---|
| `4 2nd Op 17 CLR`, push in **11.-03** | the strip is read |
| `RST R/S` | shows `-999. -03` |
| `R/S`, push in **-999.-03** | shows `-998. -03` |
| `R/S`, push in **-998.-03** | shows `-2. 00` |
| `R/S`, push in card **-2** | prints `0.2 O.K` |
| `R/S`, push in the strip it shows | your last strip is back; skipped if that was 11.-03 |

Your R33-R39, HIR registers and flags are back. Card -2 is now the active data
card, so PDCM asks for your data card only when a program needs it. Card -2
exists only after a first shutdown, so the very first start must be a generation.

**To reset,** if the registers have become unusable: press `CLR . 0 1 1 SBR 5 6
7` and feed the strips. This is a generation again, starting from the settings
on card -1. At `-1. 00`, press `R/S` and push in card -1.

## 10. When something goes wrong

| What you see | Why | What to do |
|---|---|---|
| The same card number comes back | wrong card, or a card that was never written | Push in the right one, or use `2nd St flg 8 R/S` on first use |
| Display blinks | an error, e.g. a bad step number | `CLR`, then find out why |
| A strange number after `SBR 567` or `GTO 566` | your program stopped with digits in the display, and new digits were appended (`77` then `10.012` gives `7710.012`) | Press `CLR` before keying a number |
| Asked for `-998.-03` unexpectedly | `SBR 610` replaced block 2, and strip 11.-03 wants its part back | Feed it |
| All the settings are asked for again | `7. HIR` and everything else was 0 | Enter a strip number for `7. HIR` |
| `DATA AREA NOT EMPTY` at a normal start | there are values in R01-R29 from before | `R/S` saves them to the next card; set flag 8 first if they don't matter |
| A value has disappeared | flag 8 was set during a card change | See "Flag 8" in section 7 |
