# Golden data for the Shared/ ports

Logic that moved from the Swift app into `Shared/` (C++) is checked against
the Swift original it replaced. Each `*_main.swift` here is a small driver
that is compiled together with that original Swift file — read from the git
commit that still had it — and prints its results. `gen.sh` writes them to
`tests/golden/<name>.txt`, and the C++ tests in `tests/` compare the port
against them.

```sh
tools/goldens/gen.sh            # all goldens
tools/goldens/gen.sh keynames   # one
```

The goldens are committed. Regenerate only when a driver changes; the
reference is the Swift code at the pinned commit, not the current tree.

| Golden | Swift original (commit) | C++ port | Test |
|---|---|---|---|
| `keynames` | `App/TI59KeyNames.swift` (66537d3) | `Shared/KeyNames.cpp` | `tests/shared_tables_tests.cpp` |
| `formats` | `App/StateFileLoader.swift`, `CueCardContent.swift`, `RegisterLineHelpers.swift` (66537d3) | `Shared/StateFile.cpp`, `CardFile.cpp`, `CueCard.cpp`, `Bcd.cpp` | `tests/shared_formats_tests.cpp` |

The `formats` driver parses every example state file plus
`tests/fixtures/{statefiles,cards}/` (edge cases), so adding an example adds
a golden case — regenerate after adding one.
