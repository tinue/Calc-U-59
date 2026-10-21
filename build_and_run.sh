#!/usr/bin/env bash
# Build and start the Qt6 app (local development). Extra arguments, e.g. a
# .ti59 state file, are passed to the app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
"$ROOT/tools/build_qt.sh"
case "$(uname)" in
    Darwin) open "$ROOT/Qt6/build/Calc-U-59.app" --args "$@" ;;
    *) exec "$ROOT/Qt6/build/Calc-U-59" "$@" ;;
esac
