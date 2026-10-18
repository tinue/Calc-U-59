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
    "$OUT/$name" "${GEN_ARGS[@]+"${GEN_ARGS[@]}"}" > "$ROOT/tests/golden/$name.txt"
    echo "wrote tests/golden/$name.txt"
}
want() { [ "${1:-}" = "$SEL" ] || [ "$SEL" = all ]; }
SEL="${1:-all}"

GEN_ARGS=()
want keynames && gen keynames keynames_main.swift 66537d3 App/TI59KeyNames.swift

# Inputs: every example state file plus the edge-case fixtures, sorted so the
# golden is stable.
GEN_ARGS=()
while IFS= read -r f; do GEN_ARGS+=("$f"); done < <(
    find "$ROOT/examples" "$ROOT/tests/fixtures/statefiles" "$ROOT/tests/fixtures/cards" \
        -type f \( -name '*.ti59' -o -name '*.ti58' -o -name '*.ti58c' -o -name '*.u59' \) | LC_ALL=C sort)
want formats && gen formats formats_main.swift 66537d3 \
    App/StateFileLoader.swift App/CueCardContent.swift App/RegisterLineHelpers.swift App/MachineModel.swift
true
