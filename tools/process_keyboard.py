#!/usr/bin/env python3
"""
Process tools/TI-59.png → tools/ti59_keyboard.png
- Crops the calculator from white background
- Blacks out the display panel region
- Applies rounded corners
- Prints normalized layout measurements for KeyboardView.swift

The source is already clean vector/illustration artwork, so no
contrast/saturation/posterize treatment is needed.
"""

from pathlib import Path
from PIL import Image, ImageDraw

SRC  = Path(__file__).parent / "TI-59.png"
DST  = Path(__file__).parent / "ti59_keyboard.png"

TARGET_W = 1200

# ── Step 1: load and find calculator bounds ───────────────────────────────────

img = Image.open(SRC).convert("RGBA")
w, h = img.size
print(f"Source: {w}×{h}")

pixels = img.load()
min_x, min_y = w, h
max_x, max_y = 0, 0
for y in range(h):
    for x in range(w):
        r, g, b, a = pixels[x, y]
        if not (r > 235 and g > 235 and b > 235):
            min_x = min(min_x, x)
            min_y = min(min_y, y)
            max_x = max(max_x, x)
            max_y = max(max_y, y)

margin = 4
min_x = max(0, min_x - margin)
min_y = max(0, min_y - margin)
max_x = min(w - 1, max_x + margin)
max_y = min(h - 1, max_y + margin)

print(f"Calculator bounds in source: ({min_x},{min_y}) → ({max_x},{max_y})")
calc_w = max_x - min_x
calc_h = max_y - min_y

# ── Step 2: crop & resize ─────────────────────────────────────────────────────

cropped = img.crop((min_x, min_y, max_x + 1, max_y + 1)).convert("RGB")

scale    = TARGET_W / calc_w
out_h    = round(calc_h * scale)
out_size = (TARGET_W, out_h)
resized  = cropped.resize(out_size, Image.LANCZOS)
print(f"Output size: {TARGET_W}×{out_h}  (scale {scale:.3f})")

out = resized

# ── Step 3: detect display area via red-dominant pixels ───────────────────────
#
# The LED display in the artwork uses saturated red pixels (R >> G, R >> B).
# Scan the output image to find the bounding box of the LED digit area.

px = out.load()
led_min_x, led_min_y = out_size[0], out_size[1]
led_max_x, led_max_y = 0, 0

for y in range(out_size[1]):
    for x in range(out_size[0]):
        r, g, b = px[x, y]
        if r > 140 and r > g * 2.0 and r > b * 2.0:
            led_min_x = min(led_min_x, x)
            led_min_y = min(led_min_y, y)
            led_max_x = max(led_max_x, x)
            led_max_y = max(led_max_y, y)

print(f"\nRed-pixel (LED) bounding box (pixels): ({led_min_x},{led_min_y})–({led_max_x},{led_max_y})")
print(f"Red-pixel (LED) bounding box (norm):   "
      f"x={led_min_x/out_size[0]:.4f}..{led_max_x/out_size[0]:.4f}  "
      f"y={led_min_y/out_size[1]:.4f}..{led_max_y/out_size[1]:.4f}")

# ── Step 4: black out display area ───────────────────────────────────────────
#
# Use the detected LED bounding box with a small margin for the black rect.
# Fine-tune MARGIN_* if the artwork's bezel should be covered too.

# Asymmetric X margins: the LED pixels sit ~21px right of image centre.
# Enlarging the left margin by 2×offset centres the black rect on the image.
MARGIN_X_RIGHT = round(out_size[0] * 0.010)   # ~12px
MARGIN_X_LEFT  = MARGIN_X_RIGHT + round(out_size[0] * 0.035)  # +42px → ~54px
MARGIN_Y = round(out_size[1] * 0.003)   # ~7px top/bottom

disp_x1 = max(0, led_min_x - MARGIN_X_LEFT)
disp_y1 = max(0, led_min_y - MARGIN_Y)
disp_x2 = min(out_size[0] - 1, led_max_x + MARGIN_X_RIGHT)
disp_y2 = min(out_size[1] - 1, led_max_y + MARGIN_Y)

draw = ImageDraw.Draw(out)
draw.rectangle([disp_x1, disp_y1, disp_x2, disp_y2], fill=(0, 0, 0))

print(f"\nDisplay black rect (pixels): ({disp_x1},{disp_y1})–({disp_x2},{disp_y2})")
print(f"Display black rect (norm):   "
      f"x={disp_x1/out_size[0]:.4f}..{disp_x2/out_size[0]:.4f}  "
      f"y={disp_y1/out_size[1]:.4f}..{disp_y2/out_size[1]:.4f}")
print(f"  → CGRect(x: {disp_x1/out_size[0]:.4f}, y: {disp_y1/out_size[1]:.4f}, "
      f"width: {(disp_x2-disp_x1)/out_size[0]:.4f}, height: {(disp_y2-disp_y1)/out_size[1]:.4f})")

# ── Step 5: rounded corners ───────────────────────────────────────────────────

radius = round(TARGET_W * 0.025)  # ~30 px for 1200-wide
mask = Image.new("L", out_size, 0)
d    = ImageDraw.Draw(mask)
d.rounded_rectangle([0, 0, out_size[0]-1, out_size[1]-1], radius=radius, fill=255)

out_rgba = out.convert("RGBA")
out_rgba.putalpha(mask)

# ── Step 6: save ──────────────────────────────────────────────────────────────

out_rgba.save(DST, "PNG", optimize=True)
print(f"\nSaved → {DST}")

# ── Step 7: print layout guide for KeyboardView ───────────────────────────────
#
# Keyboard area measured from the artwork: y=0.310..0.975, x=0.030..0.970
# Adjust KB_* constants if the key grid shifts in the new artwork.

KB_TOP   = 0.295
KB_BOT   = 0.968
KB_LEFT  = 0.035
KB_RIGHT = 0.965

n_rows = 9
n_cols = 5
row_h = (KB_BOT - KB_TOP) / n_rows
col_w = (KB_RIGHT - KB_LEFT) / n_cols

print("\n// ── Normalized key rects for KeyboardView.swift ──────────────────────")
print(f"// Image size: {TARGET_W}×{out_h}")
print(f"// Keyboard area: y={KB_TOP:.3f}..{KB_BOT:.3f}  x={KB_LEFT:.3f}..{KB_RIGHT:.3f}")
print(f"// Cell size: {col_w:.4f} wide × {row_h:.4f} tall")
print()
print("private static let keyRects: [[CGRect]] = [")
for row in range(n_rows):
    rects = []
    for col in range(n_cols):
        x = KB_LEFT + col * col_w
        y = KB_TOP  + row * row_h
        rects.append(f"CGRect(x: {x:.4f}, y: {y:.4f}, width: {col_w:.4f}, height: {row_h:.4f})")
    print(f"    // row {row}")
    print(f"    [{', '.join(rects)}],")
print("]")
