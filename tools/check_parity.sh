#!/usr/bin/env bash
# Warn when a branch changes one GUI but not the others (CLAUDE.md
# § "Frontend Parity"): App/ (Swift), Qt6/app/ (Qt), Web/src/ + Web/app/ +
# Web/calc.css (web). Touching reference/FrontendParity.md counts as
# acknowledging the gap (a Pending row). A Swift + Qt change without the web
# is not flagged: much of the apps is outside the web's scope, and the
# table's Web column says which.
#
#   tools/check_parity.sh [base]     # base defaults to main
#
# Exit status 1 = one-sided change without a parity-table update.
set -euo pipefail
BASE="${1:-main}"
changed="$(git diff --name-only "$(git merge-base "$BASE" HEAD)"...HEAD; git diff --name-only HEAD)"

swift=$(printf '%s\n' "$changed" | grep -E '^App/' | grep -vE '^App/(Assets\.xcassets|AppIcon\.icon)/' || true)
qt=$(printf '%s\n' "$changed" | grep -E '^Qt6/app/' || true)
web=$(printf '%s\n' "$changed" | grep -E '^Web/(src/|app/|calc\.css$)' || true)
table=$(printf '%s\n' "$changed" | grep -E '^reference/FrontendParity\.md$' || true)

if [ -n "$web" ] && [ -z "$swift$qt" ] && [ -z "$table" ]; then
    echo "Web client changed without an app change or a FrontendParity.md update:"
    printf '  %s\n' $web
    exit 1
fi
if [ -n "$swift" ] && [ -z "$qt" ] && [ -z "$table" ]; then
    echo "Swift GUI changed without a Qt6 change or a FrontendParity.md update:"
    printf '  %s\n' $swift
    exit 1
fi
if [ -n "$qt" ] && [ -z "$swift" ] && [ -z "$table" ]; then
    echo "Qt6 GUI changed without a Swift change or a FrontendParity.md update:"
    printf '  %s\n' $qt
    exit 1
fi
echo "parity check: ok"
