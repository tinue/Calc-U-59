#!/usr/bin/env bash
# Warn when a branch changes one GUI but not the other (CLAUDE.md
# § "Frontend Parity"): App/ (Swift) vs Qt6/app/ (Qt). Touching
# reference/FrontendParity.md counts as acknowledging the gap (a Pending row).
#
#   tools/check_parity.sh [base]     # base defaults to main
#
# Exit status 1 = one-sided change without a parity-table update.
set -euo pipefail
BASE="${1:-main}"
changed="$(git diff --name-only "$(git merge-base "$BASE" HEAD)"...HEAD; git diff --name-only HEAD)"

swift=$(printf '%s\n' "$changed" | grep -E '^App/' | grep -vE '^App/(Assets\.xcassets|AppIcon\.icon)/' || true)
qt=$(printf '%s\n' "$changed" | grep -E '^Qt6/app/' || true)
table=$(printf '%s\n' "$changed" | grep -E '^reference/FrontendParity\.md$' || true)

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
