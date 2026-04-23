# Assembly Examples

All assembly examples in this directory are derived from the PDF:

**Calculators TI–58/59 HW programming guide**  
Written by Hynek Sladský

## File Format

Each example is a single `.asm` file with two sections:

```
PROGRAM:
; human-readable assembly listing with comments
1800:   01D8    MOV     A.ALL,#0
        ...

HEX:
01D8 01DB ...
```

The `PROGRAM:` section is the annotated assembly source — for reading and understanding the code. The `HEX:` section contains the raw opcodes that are loaded into the emulator. The loader ignores everything before `HEX:` and parses only what follows.

## How to Run

1. Open the emulator and show the **Debug** panel.
2. Select the **CPU** tab.
3. In the **ASM Overlay** section at the bottom, click **Select File** and pick a `.asm` file.
4. Click **Run** to execute the program.

The loaded code runs in the calculator's ROM overlay area (`0x1800–0x1FFF`) and updates the display in real-time.
