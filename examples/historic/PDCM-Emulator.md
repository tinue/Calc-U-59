# Trying PDCM in the emulator

This is the short way into PDCM, the card-swapping system for the TI-59. On a
real calculator you would first key in 756 steps and write them to two magnetic
cards. In Calc-U-59 a preset does that for you, so you begin where
[`PDCM.md`](PDCM.md) reaches "6. The first start: generation".

Read sections 1 to 3 of `PDCM.md` first if you don't know yet what PDCM is for.
This guide tells you what to press; `PDCM.md` explains why.

The whole session below was played through the code all three apps share, with
the same steps of fitting and feeding cards. It was not clicked through in the
apps themselves, so a button may look a little different on your screen.

## How a card goes in

Where `PDCM.md` says "push in the card", the emulator takes two steps:

1. **Fit the card.** Press the **Crd** button and pick the file. The card now sits
   above the keys. Nothing has been read or written yet.
2. **Feed a side.** Press a top corner of the card: top-left for side 1, top-right
   for side 2.

For a card that doesn't exist yet, use the **Crd** button with the plus sign and
type a name. It is created when it is first written.

PDCM can wait as long as you like while you do this. A number in a corner of a
card is the bank stored on that side. A corner without a number is an empty side.

## Step 1: Make the two cards

Load the preset `pdcm-make-cards.ti59` from `examples/historic/`. It runs by
itself for a moment and leaves two new card files in your card folder:

| File | Corner | Strip | Bank |
|---|---|---|---|
| `PDCM-1` | top-left, side 1 | **11.-03** | 1 |
| `PDCM-1` | top-right, side 2 | **-998.-03** | 2 |
| `PDCM-2` | top-left, side 1 | **-999.-03** | 3 |
| `PDCM-2` | top-right, side 2 | **1.-03** | 1 |

They are the same cards you would have after sections 4 and 5 of `PDCM.md`. You
only need this step once. Running the preset again rewrites these two cards and
leaves your other cards alone.

In the browser emulator, cards last only until you close the page. Download any
card you want to keep.

## Step 2: Start from a clean calculator

Press **Reset**. The calculator now knows nothing about PDCM except what is on
the cards. Then press:

```
4 2nd Op 17 CLR
```

This sets the partition to 639.39, which every PDCM card expects. The printer
stays on from the preset. Leave it on, because PDCM prints what it asks for.

## Step 3: The first start

| Do this | The display or printer shows |
|---|---|
| Fit `PDCM-1`, press its **top-left** corner | strip 11.-03 is read |
| `RST` `R/S` | `-999. -03` |
| `2nd St flg 7` | still `-999. -03`; generation is now requested |
| `R/S`, fit `PDCM-2`, press its **top-left** corner | `-998. -03` |
| `R/S`, fit `PDCM-1`, press its **top-right** corner | `-1. 00` |
| `2nd St flg 8`, `R/S` | prints `30. STO`; no card is wanted, since -1 is new |
| `R/S`, 12 times | prints the rest of the registers, ending with `7. HIR` |
| `. 0 1 1`, `R/S` | prints `0. FLAG` |
| `R/S`, 8 times | prints `DATA AREA NOT EMPTY`, shows `0.1` |
| `R/S` | `-1. 00`: time to save your settings |
| `R/S`, then the **Crd** button with the plus sign, name it `PDCM-Settings`, press its **top-left** corner | `0. 00` |
| `2nd St flg 8`, `R/S` | prints `0.2 O.K` |

PDCM is running. In this first run you accepted 0 for everything except `7. HIR`,
the next strip to load. `PDCM.md` section 6 says what each setting means.

## Step 4: Use a C-memory

Store 25 in C-memory 135, which is register 19 on data card 4:

| Do this | The display shows |
|---|---|
| `CLR` `25` `+` `135` `SBR` `4 8 0` | `4. 00`: PDCM wants card 4 |
| `2nd St flg 8`, `R/S` | card 4 is new, so nothing is read |
| `0` `)` `STO` `2nd Ind` `3 1` | `25.` |

Press `RCL 1 9` to see it: `25.`

From here on, every C-memory on another card causes the two stops described in
`PDCM.md` section 7: one to save the old card, one to read the new one. Give each
data card its own file, such as `PDCM-Data4`, and feed its top-left corner.

## Step 5: Shut down

| Do this | The display or printer shows |
|---|---|
| `CLR` `. 0 0 1` `SBR` `5 6 7` | `1. -03` |
| `R/S`, fit `PDCM-2`, press its **top-right** corner | `4. 00`: save data card 4 |
| `R/S`, the **Crd** button with the plus sign, name it `PDCM-Data4`, press its **top-left** corner | `-2. 00` |
| `2nd St flg 8`, `R/S` | `-2. 00` again; card -2 is new, so nothing is read |
| `R/S`, the **Crd** button with the plus sign, name it `PDCM-State`, press its **top-left** corner | prints `GOOD-BYE FROM PDCM`, shows `1.1` |

Your cards now hold everything. You can close the app.

At a later shutdown `PDCM-State` already exists, so fit it with the plain **Crd**
button. Each time `-2. 00` appears, press `R/S` and feed its top-left corner, and
leave out flag 8. Likewise for a data card you already have.

## Step 6: Start again

No generation this time:

| Do this | The display or printer shows |
|---|---|
| **Reset**, then `4 2nd Op 17 CLR` | |
| Fit `PDCM-1`, press its **top-left** corner | strip 11.-03 is read |
| `RST` `R/S` | `-999. -03` |
| `R/S`, fit `PDCM-2`, press its **top-left** corner | `-998. -03` |
| `R/S`, fit `PDCM-1`, press its **top-right** corner | `-2. 00` |
| `R/S`, fit `PDCM-State`, press its **top-left** corner | prints `0.2 O.K` |

To prove that the value survived, read C-memory 135 back:

| Do this | The display shows |
|---|---|
| `CLR` `135` `SBR` `4 8 0` | `4. 00` |
| `R/S`, fit `PDCM-Data4`, press its **top-left** corner | the reading finishes |
| `RCL` `2nd Ind` `3 1` | `25.` |

## What next

- **See a program use it:** load `pdcm-card-tricks.ti59`. It starts the system and
  runs a demo with all its card changes by itself, in about a minute and a half.
  The demo uses cards kept in memory, so it leaves your card files alone.
- **Write your own:** `PDCM.md` section 8 has the rules and the demo's listing.
  Start from step 2 above, key your strip in, and save it with `1 2nd Write` on a
  fresh card. Then start the system as in step 3 or step 6.
- **If something looks wrong:** `PDCM.md` section 10 lists the usual causes. The
  most common is simply the wrong side of a card, which PDCM answers by showing
  the same number again.
