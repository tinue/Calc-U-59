#!/usr/bin/env bash
# Build the headless harness shared library used by tools/headless/ti59.py.
# Core/ is compiled unmodified; output goes to tools/headless/build/ (ignored).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CORE="$HERE/../../Core"
mkdir -p "$HERE/build"
clang++ -std=c++17 -O2 -shared -fPIC -o "$HERE/build/libti59headless.dylib" \
  "$HERE/capi.cpp" "$CORE/TI59Machine.cpp" "$CORE/TMC0501.cpp" "$CORE/ROM.cpp" "$CORE/RAM.cpp"
echo "built $HERE/build/libti59headless.dylib"
