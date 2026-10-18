#!/usr/bin/env bash
# Regenerate the Qt app's icons from the Swift app's Icon Composer source
# (App/AppIcon.icon, the only icon source). Run on a Mac after changing it;
# the outputs are committed because CI (Windows/Linux) has no actool:
#   Qt6/resources/macos/AppIcon.icns      local macOS development bundle
#   Qt6/resources/linux/calc-u-59.png     AppImage icon and window icon (256 px)
#   Qt6/resources/windows/calc-u-59.ico   exe icon (PNG-compressed, 16–256 px)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

xcrun actool "$ROOT/App/AppIcon.icon" --compile "$TMP" --app-icon AppIcon --platform macosx \
    --minimum-deployment-target 15.6 --target-device mac --output-partial-info-plist "$TMP/partial.plist" >/dev/null
cp "$TMP/AppIcon.icns" "$ROOT/Qt6/resources/macos/AppIcon.icns"

iconutil -c iconset "$TMP/AppIcon.icns" -o "$TMP/AppIcon.iconset"
# The compiled icns tops out at 256 px (128@2x).
cp "$TMP/AppIcon.iconset/icon_128x128@2x.png" "$ROOT/Qt6/resources/linux/calc-u-59.png"

for size in 16 32 48 64 128 256; do
    sips -z $size $size "$TMP/AppIcon.iconset/icon_128x128@2x.png" --out "$TMP/ico-$size.png" >/dev/null
done
python3 - "$TMP" "$ROOT/Qt6/resources/windows/calc-u-59.ico" <<'PY'
import struct, sys
tmp, out = sys.argv[1], sys.argv[2]
sizes = [16, 32, 48, 64, 128, 256]
images = [open(f"{tmp}/ico-{s}.png", "rb").read() for s in sizes]
header = struct.pack("<HHH", 0, 1, len(images))
offset = 6 + 16 * len(images)
entries = b""
for s, data in zip(sizes, images):
    dim = 0 if s == 256 else s  # 0 means 256 in the ICO directory
    entries += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(data), offset)
    offset += len(data)
open(out, "wb").write(header + entries + b"".join(images))
PY
echo "icons written to Qt6/resources/{macos,linux,windows}"
