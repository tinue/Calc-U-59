#!/usr/bin/env python3
"""
Generate PC-100C font data files.
Produces a reviewable/editable .txt and a visual .svg.
Pixel grid: 5 columns x 7 rows. '#' = dot on, '.' = dot off.
Codes are octal (tens digit 0-7, units digit 0-7).

Usage:
  python3 tools/gen_font.py            # reads PC-100C-Font-pixels.txt, writes SVG
  python3 tools/gen_font.py --init     # also rewrites the txt from hardcoded defaults
"""

import sys
import re

TXT_PATH = "refs/PC-100C-Font-pixels.txt"
SVG_PATH = "refs/PC-100C-Font-pixels.svg"


def parse_txt(path):
    """Parse the editable text file into [(code_int, label, [7 rows]), ...]."""
    chars = []
    with open(path) as f:
        lines = f.readlines()

    i = 0
    while i < len(lines):
        line = lines[i].rstrip("\n")
        # Skip blank lines and comments
        if not line or line.startswith(";"):
            i += 1
            continue
        # Header line: "NN [label]"
        m = re.match(r'^([0-7]{2})\s+\[(.+)\]', line)
        if not m:
            i += 1
            continue
        code = int(m.group(1), 8)
        label = m.group(2)
        rows = []
        i += 1
        while i < len(lines) and len(rows) < 7:
            r = lines[i].rstrip("\n")
            i += 1
            if not r or r.startswith(";"):
                continue
            # Stop if we hit the next character's header
            if re.match(r'^[0-7]{2}\s+\[', r):
                i -= 1  # put it back
                break
            # Validate / fix width
            if len(r) < 5:
                r = r.ljust(5, ".")
                print(f"  WARNING: char {oct(code)} ({label}) row '{r}' padded to 5")
            elif len(r) > 5:
                r = r[:5]
                print(f"  WARNING: char {oct(code)} ({label}) row truncated to 5")
            rows.append(r)
        if len(rows) != 7:
            print(f"  WARNING: char {oct(code)} ({label}) has {len(rows)} rows (expected 7)")
            while len(rows) < 7:
                rows.append(".....")
        chars.append((code, label, rows))
    return chars


# ── Hardcoded defaults (used only with --init) ────────────────────────────────
_DEFAULT_CHARS = [
    # ── Row 0 ─────────────────────────────────────────────────────────────
    (0o00, "space", [
        ".....",
        ".....",
        ".....",
        ".....",
        ".....",
        ".....",
        ".....",
    ]),
    (0o01, "0", [
        ".###.",
        "#...#",
        "#...#",
        "#...#",
        "#...#",
        "#...#",
        ".###.",
    ]),
    (0o02, "1", [
        "..#..",
        ".##..",
        "..#..",
        "..#..",
        "..#..",
        "..#..",
        ".###.",
    ]),
    (0o03, "2", [
        ".###.",
        "#...#",
        "....#",
        "..##.",
        ".#...",
        "#....",
        "#####",
    ]),
    (0o04, "3", [
        ".###.",
        "#...#",
        "....#",
        ".###.",
        "....#",
        "#...#",
        ".###.",
    ]),
    (0o05, "4", [
        "...#.",
        "..##.",
        ".#.#.",
        "#..#.",
        "#####",
        "...#.",
        "...#.",
    ]),
    (0o06, "5", [
        "#####",
        "#....",
        "####.",
        "....#",
        "....#",
        "#...#",
        ".###.",
    ]),
    (0o07, "6", [
        ".###.",
        "#....",
        "#....",
        "####.",
        "#...#",
        "#...#",
        ".###.",
    ]),
    # ── Row 1 ─────────────────────────────────────────────────────────────
    (0o10, "7", [
        "#####",
        "....#",
        "...#.",
        "..#..",
        "..#..",
        "..#..",
        "..#..",
    ]),
    (0o11, "8", [
        ".###.",
        "#...#",
        "#...#",
        ".###.",
        "#...#",
        "#...#",
        ".###.",
    ]),
    (0o12, "9", [
        ".###.",
        "#...#",
        "#...#",
        ".####",
        "....#",
        "#...#",
        ".###.",
    ]),
    (0o13, "A", [
        "..#..",
        ".#.#.",
        "#...#",
        "#...#",
        "#####",
        "#...#",
        "#...#",
    ]),
    (0o14, "B", [
        "####.",
        "#...#",
        "#...#",
        "####.",
        "#...#",
        "#...#",
        "####.",
    ]),
    (0o15, "C", [
        ".###.",
        "#...#",
        "#....",
        "#....",
        "#....",
        "#...#",
        ".###.",
    ]),
    (0o16, "D", [
        "####.",
        "#...#",
        "#...#",
        "#...#",
        "#...#",
        "#...#",
        "####.",
    ]),
    (0o17, "E", [
        "#####",
        "#....",
        "#....",
        "####.",
        "#....",
        "#....",
        "#####",
    ]),
    # ── Row 2 ─────────────────────────────────────────────────────────────
    (0o20, "-", [
        ".....",
        ".....",
        ".....",
        "#####",
        ".....",
        ".....",
        ".....",
    ]),
    (0o21, "F", [
        "#####",
        "#....",
        "#....",
        "####.",
        "#....",
        "#....",
        "#....",
    ]),
    (0o22, "G", [
        ".####",
        "#....",
        "#....",
        "#.###",
        "#...#",
        "#...#",
        ".####",
    ]),
    (0o23, "H", [
        "#...#",
        "#...#",
        "#...#",
        "#####",
        "#...#",
        "#...#",
        "#...#",
    ]),
    (0o24, "I", [
        ".###.",
        "..#..",
        "..#..",
        "..#..",
        "..#..",
        "..#..",
        ".###.",
    ]),
    (0o25, "J", [
        "..###",
        "....#",
        "....#",
        "....#",
        "....#",
        "#...#",
        ".###.",
    ]),
    (0o26, "K", [
        "#...#",
        "#..#.",
        "#.#..",
        "##...",
        "#.#..",
        "#..#.",
        "#...#",
    ]),
    (0o27, "L", [
        "#....",
        "#....",
        "#....",
        "#....",
        "#....",
        "#....",
        "#####",
    ]),
    # ── Row 3 ─────────────────────────────────────────────────────────────
    (0o30, "M", [
        "#...#",
        "##.##",
        "#.#.#",
        "#...#",
        "#...#",
        "#...#",
        "#...#",
    ]),
    (0o31, "N", [
        "#...#",
        "##..#",
        "#.#.#",
        "#..##",
        "#...#",
        "#...#",
        "#...#",
    ]),
    (0o32, "O", [
        ".###.",
        "#...#",
        "#...#",
        "#...#",
        "#...#",
        "#...#",
        ".###.",
    ]),
    (0o33, "P", [
        "####.",
        "#...#",
        "#...#",
        "####.",
        "#....",
        "#....",
        "#....",
    ]),
    (0o34, "Q", [
        ".###.",
        "#...#",
        "#...#",
        "#...#",
        "#.#.#",
        "#..#.",
        ".##.#",
    ]),
    (0o35, "R", [
        "####.",
        "#...#",
        "#...#",
        "####.",
        "#.#..",
        "#..#.",
        "#...#",
    ]),
    (0o36, "S", [
        ".###.",
        "#...#",
        "#....",
        ".###.",
        "....#",
        "#...#",
        ".###.",
    ]),
    (0o37, "T", [
        "#####",
        "..#..",
        "..#..",
        "..#..",
        "..#..",
        "..#..",
        "..#..",
    ]),
    # ── Row 4 ─────────────────────────────────────────────────────────────
    (0o40, ".", [
        ".....",
        ".....",
        ".....",
        ".....",
        ".....",
        ".##..",
        ".##..",
    ]),
    (0o41, "U", [
        "#...#",
        "#...#",
        "#...#",
        "#...#",
        "#...#",
        "#...#",
        ".###.",
    ]),
    (0o42, "V", [
        "#...#",
        "#...#",
        "#...#",
        "#...#",
        ".#.#.",
        ".#.#.",
        "..#..",
    ]),
    (0o43, "W", [
        "#...#",
        "#...#",
        "#...#",
        "#.#.#",
        "#.#.#",
        "##.##",
        "#...#",
    ]),
    (0o44, "X", [
        "#...#",
        "#...#",
        ".#.#.",
        "..#..",
        ".#.#.",
        "#...#",
        "#...#",
    ]),
    (0o45, "Y", [
        "#...#",
        "#...#",
        ".#.#.",
        "..#..",
        "..#..",
        "..#..",
        "..#..",
    ]),
    (0o46, "Z", [
        "#####",
        "....#",
        "...#.",
        "..#..",
        ".#...",
        "#....",
        "#####",
    ]),
    (0o47, "+", [
        ".....",
        "..#..",
        "..#..",
        "#####",
        "..#..",
        "..#..",
        ".....",
    ]),
    # ── Row 5 ─────────────────────────────────────────────────────────────
    (0o50, "x(mul)", [
        ".....",
        "#...#",
        ".#.#.",
        "..#..",
        ".#.#.",
        "#...#",
        ".....",
    ]),
    (0o51, "*", [
        "..#..",
        "#.#.#",
        ".###.",
        "..#..",
        ".###.",
        "#.#.#",
        "..#..",
    ]),
    (0o52, "Gamma", [
        "#####",
        "#....",
        "#....",
        "#....",
        "#....",
        "#....",
        "#....",
    ]),
    (0o53, "m", [
        ".....",
        ".....",
        "##.#.",
        "#.#.#",
        "#.#.#",
        "#.#.#",
        "#...#",
    ]),
    (0o54, "e", [
        ".....",
        ".....",
        ".###.",
        "#...#",
        "#####",
        "#....",
        ".###.",
    ]),
    (0o55, "(", [
        "...#.",
        "..#..",
        ".#...",
        ".#...",
        ".#...",
        "..#..",
        "...#.",
    ]),
    (0o56, ")", [
        ".#...",
        "..#..",
        "...#.",
        "...#.",
        "...#.",
        "..#..",
        ".#...",
    ]),
    (0o57, ";", [
        ".....",
        ".##..",
        ".##..",
        ".....",
        ".##..",
        "..#..",
        ".#...",
    ]),
    # ── Row 6 ─────────────────────────────────────────────────────────────
    (0o60, "dagger", [
        "..#..",
        "..#..",
        "#####",
        "..#..",
        "..#..",
        "..#..",
        "..#..",
    ]),
    (0o61, "%", [
        "##..#",
        "##.#.",
        "...#.",
        "..#..",
        ".#...",
        ".#.##",
        "#..##",
    ]),
    (0o62, "?(62)", [   # unclear in scan — placeholder
        ".###.",
        "#...#",
        "....#",
        "..##.",
        "..#..",
        ".....",
        "..#..",
    ]),
    (0o63, "/", [
        ".....",
        "....#",
        "...#.",
        "..#..",
        ".#...",
        "#....",
        ".....",
    ]),
    (0o64, "=", [
        ".....",
        ".....",
        "#####",
        ".....",
        "#####",
        ".....",
        ".....",
    ]),
    (0o65, "\"", [
        ".#.#.",
        ".#.#.",
        ".....",
        ".....",
        ".....",
        ".....",
        ".....",
    ]),
    (0o66, "?(66)", [   # unclear in scan — placeholder (looks like x or similar)
        "#...#",
        ".#.#.",
        "..#..",
        ".#.#.",
        "#...#",
        ".....",
        ".....",
    ]),
    (0o67, "Sigma", [
        "#####",
        "#....",
        ".#...",
        "..#..",
        ".#...",
        "#....",
        "#####",
    ]),
    # ── Row 7 ─────────────────────────────────────────────────────────────
    (0o70, "Xi/3bars", [
        "#####",
        ".....",
        "#####",
        ".....",
        "#####",
        ".....",
        ".....",
    ]),
    (0o71, "?(71)", [   # unclear in scan
        ".###.",
        "#...#",
        "....#",
        "...##",
        "....#",
        "#...#",
        ".###.",
    ]),
    (0o72, "div", [
        ".....",
        "..#..",
        ".....",
        "#####",
        ".....",
        "..#..",
        ".....",
    ]),
    (0o73, "!", [
        "..#..",
        "..#..",
        "..#..",
        "..#..",
        "..#..",
        ".....",
        "..#..",
    ]),
    (0o74, "||", [
        ".#.#.",
        ".#.#.",
        ".#.#.",
        ".#.#.",
        ".#.#.",
        ".#.#.",
        ".#.#.",
    ]),
    (0o75, "tri-up", [
        "..#..",
        "..#..",
        ".#.#.",
        ".#.#.",
        "#...#",
        "#...#",
        "#####",
    ]),
    (0o76, "pi", [
        ".....",
        "#####",
        ".#.#.",
        ".#.#.",
        ".#.#.",
        ".#.#.",
        ".#.#.",
    ]),
    (0o77, "Sigma2", [
        "#####",
        "....#",
        "...#.",
        "..#..",
        ".#...",
        "#....",
        "#####",
    ]),
]  # end _DEFAULT_CHARS

# ── Text output ───────────────────────────────────────────────────────────────

def write_txt(path, chars):
    lines = [
        "; PC-100C Printer Font — 5×7 dot matrix",
        "; Format: octal code, label, then 7 rows of 5 chars ('#'=on, '.'=off)",
        "; Codes are octal: tens digit 0-7 (rows), units digit 0-7 (cols)",
        "; Characters marked ?(NN) are unclear in the scan — please correct.",
        "",
    ]
    for code, label, rows in chars:
        lines.append(f"{oct(code)[2:]:>02s} [{label}]")
        lines.extend(rows)
        lines.append("")
    with open(path, "w") as f:
        f.write("\n".join(lines))
    print(f"Wrote {path}")

# ── SVG output ────────────────────────────────────────────────────────────────

DOT  = 9      # px per filled dot
GAP  = 2      # px gap between dots
STEP = DOT + GAP   # 11 px per grid position

GRID_W = 5 * STEP - GAP   # 53
GRID_H = 7 * STEP - GAP   # 75

CELL_W  = 90
CELL_H  = 115
LABEL_H = 16   # height for label at bottom
PAD     = 20   # outer padding

COLS = 8
ROWS = 8

SVG_W = COLS * CELL_W + 2 * PAD
SVG_H = ROWS * CELL_H + 2 * PAD + 30  # +30 for title


def svg_char(x0, y0, code, label, rows):
    parts = []
    # Cell background
    parts.append(
        f'<rect x="{x0}" y="{y0}" width="{CELL_W}" height="{CELL_H}" '
        f'fill="#f8f8f8" stroke="#ccc" stroke-width="0.5"/>'
    )
    # Octal code label at top
    parts.append(
        f'<text x="{x0 + CELL_W//2}" y="{y0 + 12}" '
        f'text-anchor="middle" font-family="monospace" font-size="10" fill="#888">'
        f'{oct(code)[2:]:>02s}'
        f'</text>'
    )
    # Dot grid
    gx = x0 + (CELL_W - GRID_W) // 2
    gy = y0 + 18
    # Background dots (off)
    for row in range(7):
        for col in range(5):
            dx = gx + col * STEP
            dy = gy + row * STEP
            parts.append(
                f'<rect x="{dx}" y="{dy}" width="{DOT}" height="{DOT}" '
                f'fill="#e0e0e0" rx="1.5"/>'
            )
    # On dots
    for row, rowstr in enumerate(rows):
        for col, ch in enumerate(rowstr):
            if ch == '#':
                dx = gx + col * STEP
                dy = gy + row * STEP
                parts.append(
                    f'<rect x="{dx}" y="{dy}" width="{DOT}" height="{DOT}" '
                    f'fill="#1a1a1a" rx="1.5"/>'
                )
    # Character name label at bottom
    color = "#c00" if label.startswith("?") else "#333"
    parts.append(
        f'<text x="{x0 + CELL_W//2}" y="{y0 + CELL_H - 4}" '
        f'text-anchor="middle" font-family="monospace" font-size="9" fill="{color}">'
        f'{label}'
        f'</text>'
    )
    return "\n".join(parts)


def write_svg(path, chars):
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'width="{SVG_W}" height="{SVG_H}">',
        '<rect width="100%" height="100%" fill="white"/>',
        f'<text x="{SVG_W//2}" y="18" text-anchor="middle" '
        f'font-family="sans-serif" font-size="14" font-weight="bold" fill="#222">'
        f'PC-100C Printer Font — 5×7 dot matrix</text>',
        f'<text x="{SVG_W//2}" y="34" text-anchor="middle" '
        f'font-family="sans-serif" font-size="10" fill="#888">'
        f'Red = uncertain character.  Code shown in octal (tens×8 + units).</text>',
    ]

    # Column headers
    for col in range(8):
        cx = PAD + col * CELL_W + CELL_W // 2
        parts.append(
            f'<text x="{cx}" y="{PAD + 52}" text-anchor="middle" '
            f'font-family="monospace" font-size="11" font-weight="bold" fill="#444">{col}</text>'
        )

    for i, (code, label, rows) in enumerate(chars):
        row_i = i // 8
        col_i = i % 8
        x0 = PAD + col_i * CELL_W
        y0 = PAD + 40 + row_i * CELL_H
        if col_i == 0:
            parts.append(
                f'<text x="{PAD - 5}" y="{y0 + CELL_H//2 + 4}" '
                f'text-anchor="end" font-family="monospace" font-size="11" '
                f'font-weight="bold" fill="#444">{row_i}</text>'
            )
        parts.append(svg_char(x0, y0, code, label, rows))

    parts.append('</svg>')
    with open(path, "w") as f:
        f.write("\n".join(parts))
    print(f"Wrote {path}")


SWIFT_PATH = "App/PC100CFont.swift"


def write_swift(path, chars):
    """Generate Swift font data file."""
    def row_to_bits(row):
        val = 0
        for col, ch in enumerate(row):
            if ch == '#':
                val |= (0x10 >> col)
        return val

    lines = [
        "// Auto-generated by tools/gen_font.py — edit refs/PC-100C-Font-pixels.txt and re-run.",
        "// PC-100C printer font: 64 characters × 7 rows.",
        "// Each UInt8 row: bit 4 = leftmost column, bit 0 = rightmost.",
        "",
        "let pc100cFont: [[UInt8]] = [",
    ]
    for code, label, rows in chars:
        bits = [row_to_bits(r) for r in rows]
        hex_vals = ", ".join(f"0x{b:02X}" for b in bits)
        lines.append(f"    [{hex_vals}],  // {oct(code)[2:]:>02s}: {label}")
    lines.append("]")
    lines.append("")
    with open(path, "w") as f:
        f.write("\n".join(lines))
    print(f"Wrote {path}")


if __name__ == "__main__":
    if "--init" in sys.argv:
        write_txt(TXT_PATH, _DEFAULT_CHARS)
    chars = parse_txt(TXT_PATH)
    write_svg(SVG_PATH, chars)
    write_swift(SWIFT_PATH, chars)
