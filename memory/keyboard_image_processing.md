---
name: keyboard_image_processing
description: Know-how for generating ti59_keyboard.png from refs/TI-59.jpg — calibration details, current errors, and what to fix on the redo
type: project
---

## How the image is generated

Script: `tools/process_keyboard.py`
Source: `refs/TI-59.jpg` → `refs/ti59_keyboard.png` (also copied to `App/Assets.xcassets/ti59_keyboard.imageset/`)

Pipeline:
1. Auto-detect calculator bounds by scanning for non-white pixels (threshold: R,G,B all > 235), 6px margin
2. Crop, scale to 1200px wide → output 1200×2098
3. Illustration treatment: contrast 1.35×, color saturation 1.5×, UnsharpMask(r=1.5, 120%, t=2), posterize 6 bits
4. Black out display area rectangle (hardcoded normalized coords)
5. Rounded corners (radius ≈ 42px = 3.5% of width)
6. Save as RGBA PNG

## Source image

`refs/TI-59.png` (896×1195 RGBA, clean vector/illustration artwork, white background).
No illustration treatment needed — it's already artwork quality.

## Calibrated normalized coordinates (current image 1200×2321)

Display black rect (auto-detected from red pixels + 10px/7px margin):
  CGRect(x: 0.2267, y: 0.0948, width: 0.5825, height: 0.0349)
Keyboard area: y=0.295..0.968, x=0.035..0.965
Cell size: 0.1860 wide × 0.0748 tall (5 cols × 9 rows)

## How display rect is detected

Script scans for red-dominant pixels (R > 140, R/G > 2.0, R/B > 2.0) to find the LED digit
bounding box automatically. A small margin (MARGIN_X / MARGIN_Y) is added.
This means re-running the script on any new artwork will auto-calibrate the display rect.

## Where constants live in the Swift layer

`App/Views/KeyboardView.swift`:
- `displayRect`: normalized CGRect for the LED overlay (must match blacked-out area in PNG)
- `keyRects`: computed from `kbTop`, `kbLeft`, `cellW`, `cellH` constants
- `imageAspect`: 1200.0 / <actual height> — update if output height changes

**Why:** The image has calibration errors that need fixing. Preserving the pipeline know-how avoids re-deriving the processing approach from scratch.
**How to apply:** When the user asks to redo or fix the calculator image, run `tools/process_keyboard.py`, visually verify output, re-measure the rectangles, and update both the script constants and `KeyboardView.swift`.
