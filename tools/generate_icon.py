#!/usr/bin/env python3
import json
import os
from PIL import Image, ImageDraw, ImageFont

# ── Configuration ─────────────────────────────────────────────────────────────

ICON_TEXT = "59"
COLOR_YELLOW = (212, 174, 89)
COLOR_BROWN  = (46, 39, 30)
COLOR_BLACK  = (0, 0, 0)

APPICONSET_PATH = "App/Assets.xcassets/AppIcon.appiconset"
CONTENTS_JSON_PATH = os.path.join(APPICONSET_PATH, "Contents.json")
FONT_PATH = "/System/Library/Fonts/Supplemental/Arial.ttf"

# ── Icon Generation ───────────────────────────────────────────────────────────

def create_icon(size_px):
    """Generates a PIL Image for the icon at the given size."""
    # 1. Background (Black calculator body)
    img = Image.new("RGB", (size_px, size_px), COLOR_BLACK)
    draw = ImageDraw.Draw(img)
    
    # 2. Key Shape (Brown rounded rect)
    #    Let's make the key fill about 80% of the icon
    margin = size_px * 0.1
    x0, y0 = margin, margin
    x1, y1 = size_px - margin, size_px - margin
    
    # Rounded corners: radius ~ 15% of the key size
    key_w = x1 - x0
    radius = key_w * 0.15
    
    draw.rounded_rectangle((x0, y0, x1, y1), radius=radius, fill=COLOR_BROWN)
    
    # 3. Text "59" (Yellow)
    #    Scale font to fit nicely within the key
    font_size = int(size_px * 0.5)
    try:
        font = ImageFont.truetype(FONT_PATH, font_size)
    except IOError:
        # Fallback if specific font not found (though checked in plan)
        font = ImageFont.load_default()
        print(f"Warning: Could not load {FONT_PATH}, using default font.")

    # Center text
    # Pillow 8.0+ uses getbbox or getlength. 
    # textsize is deprecated in recent Pillow versions.
    try:
        # Recent Pillow
        left, top, right, bottom = font.getbbox(ICON_TEXT)
        text_w = right - left
        text_h = bottom - top
        # Adjust for baseline
        # Usually we want to center strictly visually
        # Draw position is top-left of the text box
        text_x = (size_px - text_w) / 2 - left
        text_y = (size_px - text_h) / 2 - top
    except AttributeError:
        # Older Pillow
        text_w, text_h = draw.textsize(ICON_TEXT, font=font)
        text_x = (size_px - text_w) / 2
        text_y = (size_px - text_h) / 2

    draw.text((text_x, text_y), ICON_TEXT, font=font, fill=COLOR_YELLOW)
    
    return img

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    if not os.path.exists(APPICONSET_PATH):
        print(f"Error: Path {APPICONSET_PATH} does not exist.")
        return

    # Load Contents.json to find what we need to generate
    with open(CONTENTS_JSON_PATH, 'r') as f:
        contents = json.load(f)

    # We will update contents in place
    images = contents.get("images", [])
    
    # Track generated files to avoid regenerating duplicates (though unlikely with this structure)
    # Actually, we should just iterate the JSON and generate what is asked.
    
    for entry in images:
        idiom = entry.get("idiom")
        size_str = entry.get("size")
        scale_str = entry.get("scale", "1x")
        
        # Parse size "1024x1024" -> 1024
        try:
            w_str, h_str = size_str.split('x')
            base_w = int(float(w_str)) # float because sometimes "1024.0"
            base_h = int(float(h_str))
        except ValueError:
            print(f"Skipping invalid size format: {size_str}")
            continue
            
        # Parse scale "2x" -> 2
        scale = 1
        if scale_str.endswith("x"):
            try:
                scale = int(float(scale_str[:-1]))
            except ValueError:
                pass
        
        final_w = base_w * scale
        final_h = base_h * scale
        
        # Determine filename
        # e.g. "icon_32x32@2x.png" or "icon_1024x1024.png"
        if scale > 1:
            filename = f"icon_{base_w}x{base_h}@{scale}x.png"
        else:
            filename = f"icon_{base_w}x{base_h}.png"
            
        # Specific case for ios-marketing or universal 1024
        # The JSON has multiple 1024 entries. We can use the same file for them.
        # But let's generate unique files if the entry properties differ significantly?
        # Actually, for "universal" 1024x1024, it appears multiple times (Any, Dark, Tinted).
        # We'll use the filename we constructed.
        
        # Add filename to entry
        entry["filename"] = filename
        
        # Generate and save
        out_path = os.path.join(APPICONSET_PATH, filename)
        if not os.path.exists(out_path): # generate if not exists, or always overwrite?
            # Always overwrite to ensure updated design
            print(f"Generating {filename} ({final_w}x{final_h})...")
            img = create_icon(final_w)
            img.save(out_path)
        else:
            # If we want to force update, we should overwrite.
            # But maybe we generated it for a previous entry (e.g. Dark/Tinted might map to same).
            # If filename is same, content is same.
            pass

    # Save updated Contents.json
    with open(CONTENTS_JSON_PATH, 'w') as f:
        json.dump(contents, f, indent=2)
    
    print("Done. Icons generated and Contents.json updated.")

if __name__ == "__main__":
    main()
