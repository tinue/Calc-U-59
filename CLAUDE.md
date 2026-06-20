# Project Context

## Skills

Invoke the right skill before starting work in each area:

| Skill | Invoke for |
|-------|-----------|
| `calc-u-59-core` | C++ emulation core (`Core/`, `tools/`, ROM disassembly, trace infrastructure) |
| `calc-u-59-swift` | Swift/SwiftUI app (`App/`, `App/Views/`, `Bridge/`) |
| `calc-u-59-docs` | Documentation and website (`docs/`, `reference/`, root markdown files) |
| `calc-u-59-statefiles` | Writing `.ti59`/`.ti58`/`.ti58c` state files — format, matrix codes, KEYSTROKES sequences |
| `calc-u-59-uitesting` | XCUITest UI tests (`Calc-U-59UITests/`) — file picker navigation, accessibility identifiers, orientation |

## Architecture Reference

Architecture facts (register model, SCOM layout, PC encoding, machine variants, trace API) live in:

- `reference/CoreArchitecture.md` — C++ emulation core
- `reference/AppArchitecture.md` — Swift app and bridge layer
- `reference/DebugAPI.md` — debug panel and bridge API

Do not restate these facts in CLAUDE.md, skills, or memory files — link to the reference doc instead.
