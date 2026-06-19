#!/usr/bin/env bash
# Copy screenshot state files into the booted simulator's app Documents folder.
#
# Run once after installing the app on the simulator, before executing the
# AppStoreScreenshots test class.  Also suitable as a scheme pre-action:
#   Shell: /bin/bash
#   Script: $SRCROOT/scripts/setup-screenshot-fixtures.sh
#   Provide build settings from: Calc-U-59 (the app target)
#
# The script exits 0 even when the container does not exist yet (first-ever run).
# In that case, launch the app once manually (or let AppStoreScreenshots.setUp do it),
# then re-run this script before executing the test.

set -euo pipefail

BUNDLE_ID="ch.erzberger.calcu59"
SRCROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
FILES_DIR="$SRCROOT/examples/debug"

FILES=(
    "screenshot_leisure_start.ti59"
    "screenshot_leisure_run.ti59"
)

CONTAINER=$(xcrun simctl get_app_container booted "$BUNDLE_ID" data 2>/dev/null || true)
if [ -z "$CONTAINER" ]; then
    echo "warning: app container not found for $BUNDLE_ID on booted simulator." >&2
    echo "  Launch the app once, then re-run this script." >&2
    exit 0
fi

DOCS="$CONTAINER/Documents"
mkdir -p "$DOCS"

for FILE in "${FILES[@]}"; do
    SRC="$FILES_DIR/$FILE"
    if [ ! -f "$SRC" ]; then
        echo "error: source file not found: $SRC" >&2
        exit 1
    fi
    cp "$SRC" "$DOCS/$FILE"
    echo "Copied $FILE → $DOCS/"
done
