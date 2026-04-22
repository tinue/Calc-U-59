# Assembly Examples

All assembly examples in this directory are derived from the PDF:

**Calculators TI–58/59 HW programming guide**  
Written by Hynek Sladský

## File Format

### `.asm` files
Assembly source code with comments explaining the operations and expected behavior. These are human-readable and useful for understanding the program logic.

### `.hex` files
Machine code (hexadecimal opcodes) ready to load into the emulator. Use these with the experimental **ASM** tab in the debug section:

1. Open the emulator
2. Go to the **Debug** panel (toggle with debug button)
3. Select the **ASM** tab
4. Load a `.hex` file using the file picker
5. Click **Run** to execute the program

The loaded code will execute in the calculator's ROM space and update the display in real-time.
