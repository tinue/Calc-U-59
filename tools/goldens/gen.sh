#!/usr/bin/env bash
# Regenerate tests/golden/* from the Swift originals. Each golden is produced
# by compiling the Swift file being replaced together with a small driver.
# Run once before deleting/rewriting the Swift implementation; afterwards the
# committed goldens are the reference. See tools/goldens/README.md.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/goldens"
mkdir -p "$OUT"
# The Swift originals are deleted once ported, so sources are read from the
# git commit that still had them.
gen() {  # gen <name> <driver> <git ref> <repo-relative swift sources...>
    local name=$1 driver=$2 ref=$3; shift 3
    local src="$OUT/$name.src"
    rm -rf "$src" && mkdir -p "$src"
    # Top-level code is only allowed in a file named main.swift.
    cp "$ROOT/tools/goldens/$driver" "$src/main.swift"
    local files=("$src/main.swift")
    for f in "$@"; do
        git -C "$ROOT" show "$ref:$f" > "$src/$(basename "$f")"
        files+=("$src/$(basename "$f")")
    done
    swiftc -O -o "$OUT/$name" "${files[@]}"
    "$OUT/$name" > "$ROOT/tests/golden/$name.txt"
    echo "wrote tests/golden/$name.txt"
}
want() { [ "${1:-}" = "$SEL" ] || [ "$SEL" = all ]; }
SEL="${1:-all}"

want keynames && gen keynames keynames_main.swift 66537d3 App/TI59KeyNames.swift
true
