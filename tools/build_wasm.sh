#!/usr/bin/env bash
# Build the playable web calculator's engine (docs/play/, docs/app/): Core/ +
# Shared/ + docs/wasm/bindings.cpp into docs/wasm/ti59-core.{js,wasm}, and copy
# the ROM text files it loads into docs/wasm/roms/.
#
# Requires emcc on PATH (e.g. `brew install emscripten`). Re-run whenever
# Core/, Shared/, roms/ or bindings.cpp change — the output is committed in the
# docs/ worktree, there is no CI step for it.
#
# Single-threaded (no -pthread): GitHub Pages can't send the headers
# SharedArrayBuffer needs, so SessionController runs in Threading::Cooperative.
# -fexceptions: Shared/ reports ROM and file errors with exceptions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WASM_DIR="$REPO_ROOT/docs/wasm"

if ! command -v emcc >/dev/null 2>&1; then
  echo "error: emcc not found on PATH. Install with 'brew install emscripten'." >&2
  exit 1
fi

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
  -o "$WASM_DIR/ti59-core.js" \
  "$REPO_ROOT"/Core/*.cpp \
  "$REPO_ROOT"/Shared/*.cpp \
  "$WASM_DIR/bindings.cpp"

# The TI-59's ROM and constants, the module catalogue and every module image:
# the files the worker hands SessionController's ResourceReader.
rm -rf "$WASM_DIR/roms"
mkdir -p "$WASM_DIR/roms"
cp "$REPO_ROOT"/roms/calculator/TMC0582.txt "$REPO_ROOT"/roms/calculator/TMC0583.txt \
   "$REPO_ROOT"/roms/calculator/TMC0571B.txt \
   "$REPO_ROOT"/roms/calculator/TMC0582-CONST-K.txt "$REPO_ROOT"/roms/calculator/TMC0583-CONST-K.txt \
   "$REPO_ROOT"/roms/solid-state/*.txt "$WASM_DIR/roms/"

echo "wrote $WASM_DIR/ti59-core.js, ti59-core.wasm and roms/"
