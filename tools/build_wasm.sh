#!/usr/bin/env bash
# Compile Core/ + docs/wasm/bindings.cpp into docs/wasm/ti59-core.{js,wasm}
# for the playable web calculator (docs/#play).
#
# Requires emcc on PATH (e.g. `brew install emscripten`). Re-run whenever
# Core/ or bindings.cpp changes — the output is committed, same as
# docs/assets/*.png; there's no CI build step for it (see the plan).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CORE_DIR="$REPO_ROOT/Core"
WASM_DIR="$REPO_ROOT/docs/wasm"

if ! command -v emcc >/dev/null 2>&1; then
  echo "error: emcc not found on PATH. Install with 'brew install emscripten'." >&2
  exit 1
fi

emcc \
  -O3 \
  -std=c++17 \
  --bind \
  -s MODULARIZE=1 \
  -s EXPORT_NAME=createTI59CoreModule \
  -s ENVIRONMENT=web,worker \
  -s ALLOW_MEMORY_GROWTH=1 \
  -s NO_EXIT_RUNTIME=1 \
  -o "$WASM_DIR/ti59-core.js" \
  "$CORE_DIR/TI59Machine.cpp" \
  "$CORE_DIR/TMC0501.cpp" \
  "$CORE_DIR/ROM.cpp" \
  "$CORE_DIR/RAM.cpp" \
  "$WASM_DIR/bindings.cpp"

echo "wrote $WASM_DIR/ti59-core.js and ti59-core.wasm"
