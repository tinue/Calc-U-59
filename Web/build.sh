#!/usr/bin/env bash
# Build the web client into Web/dist/ (gitignored): the WASM engine (Core/ +
# Shared/ + bindings.cpp), the ROM files it loads, the calculator's script,
# stylesheet and fonts, the presets, the installable PWA and a demo page.
# reference/WebClient.md is the contract for what dist/ contains.
#
# Requires emcc on PATH (e.g. `brew install emscripten`; CI pins the version
# in .github/workflows/build.yml) and node. Re-run whenever Core/, Shared/,
# roms/ or anything in Web/ changes.
#
# Single-threaded (no -pthread): a static host can't be relied on to send
# the headers SharedArrayBuffer needs, so SessionController runs in
# Threading::Cooperative. -fexceptions: Shared/ reports ROM and file errors
# with exceptions.
set -euo pipefail

WEB="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$WEB/.." && pwd)"
DIST="$WEB/dist"

for tool in em++ node; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: $tool not found on PATH." >&2
    exit 1
  fi
done

rm -rf "$DIST"
mkdir -p "$DIST/wasm/roms" "$DIST/app" "$DIST/vendor" "$DIST/fonts"

em++ \
  -O3 \
  -std=c++17 \
  -fexceptions \
  --bind \
  -s MODULARIZE=1 \
  -s EXPORT_NAME=createTI59CoreModule \
  -s ENVIRONMENT=web,worker \
  -s ALLOW_MEMORY_GROWTH=1 \
  -s NO_EXIT_RUNTIME=1 \
  -o "$DIST/wasm/ti59-core.js" \
  "$REPO_ROOT"/Core/*.cpp \
  "$REPO_ROOT"/Shared/*.cpp \
  "$WEB/bindings.cpp"

# The TI-59's ROM and constants, the module catalogue and every module image:
# the files the worker hands SessionController's ResourceReader.
cp "$REPO_ROOT"/roms/calculator/TMC0582.txt "$REPO_ROOT"/roms/calculator/TMC0583.txt \
   "$REPO_ROOT"/roms/calculator/TMC0571B.txt \
   "$REPO_ROOT"/roms/calculator/TMC0582-CONST-K.txt "$REPO_ROOT"/roms/calculator/TMC0583-CONST-K.txt \
   "$REPO_ROOT"/roms/solid-state/*.txt "$DIST/wasm/roms/"

cp "$WEB/index.html" "$WEB/calc.css" "$WEB/calc-engine-worker.js" "$DIST/"
cp "$WEB"/fonts/* "$DIST/fonts/"
# React 18 for the PWA and the demo page; a host page brings its own.
cp "$WEB/vendor/react.production.min.js" "$WEB/vendor/react-dom.production.min.js" "$DIST/vendor/"
cp "$WEB/app/index.html" "$WEB/app/app.css" "$WEB/app/sw.js" "$WEB/app/manifest.json" "$DIST/app/"
# The app icon, derived from App/AppIcon.icon by tools/gen_qt_icons.sh.
cp "$REPO_ROOT/Qt6/resources/linux/calc-u-59.png" "$DIST/app/icon.png"

node "$WEB/build.js"

echo "wrote $DIST"
