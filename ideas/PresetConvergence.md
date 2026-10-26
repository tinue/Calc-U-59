# Preset Convergence with Calc-U-1600

*Status: idea / comparison, not implemented. Compares Calc-U-59 presets
(`.ti59` / `.ti58` / `.ti58c`, `reference/StateFileFormat.md`, as of 2.2.0)
with the Calc-U-1600 presets (`.pc1500` / `.pc1500a` / `.pc1600`, chapter 8
of `docs/User-Guide.md` in `../../sharp/Calc-U-1600`, format version 1), and
asks two questions: could the syntax be made more equal or unified, and do
both support the same things, adapted to their platform?*

Conclusion: keeping both syntaxes is the better choice. The step vocabulary
can largely converge, and each side has two or three features the other would
benefit from. Since 2.2.0, both formats share the same top-to-bottom section
model.

---

## Where they already match

- **Interleaved sections.** Calc-U-1600's `keys:` / `program:` blocks may
  repeat and run in file order. Calc-U-59 does the same since 2.2.0:
  `PROGRAM:` / `REGISTERS:` / `CUECARD:` after `KEYSTROKES:` form a reload.
- **Trace.** `Trace: run.bin` / `Trace: Off` (59) and `- trace: run.bin` /
  `- trace: off` (1600) behave the same.
- **Media by name.** Both use a name to mean the saved media folder:
  `ArmCard: Results` (59) and `slot-1: CE-1600M` / `floppy: Formatted` (1600).

## Why one syntax doesn't fit

| | Calc-U-59 | Calc-U-1600 |
|---|---|---|
| Shape | Line sections, `KEYWORD:` headers, case-insensitive | YAML-shaped `key: value` and `- verb: value` steps |
| Bulk content | Keycode and register lists, often hundreds of lines (`PROGRAM:` up to 960 steps) | Files by path (`program: file:`), or one `text: \|` block |
| Comments | `#` anywhere | `#`, except `type:` takes everything to the end of the line |
| Errors | Bad line reported, load goes on | All-or-nothing, fails before the machine starts |
| A key left out | Keep the current setting (`PRINTER:`, module) | Means "none" (a cold boot with nothing attached) |
| Running | Live playback at regular speed; keys wait for the scan loop | Full speed behind "Loading…"; a bare `wait:` waits for idle |

The last two rows are design differences, not accidents:
- A Calc-U-59 preset is applied to a running calculator, often as a demo.
- A Calc-U-1600 preset builds a machine from a cold boot.

Rewriting 59 keystrokes as `- key: 21` lines would bloat every file and break
the existing presets and the site's software files. Adding key names
(`2nd Pgm`) would also clash with the 59 convention that words on a
KEYSTROKES line are ignored as comments.

## Cheap convergence

1. **Wait units.** The 59 requires a unit (`Wait: 2s`, `500ms`); the 1600
   takes bare seconds (`wait: 2`). Let the 1600 accept `2s` / `500ms` too,
   which is purely additive.
2. **Case.** 59 directives are case-insensitive, so `wait: 2s` and
   `trace: x.bin` already work there. Docs for both could show the same
   lowercase spelling.
3. **Format version.** The 1600 requires `format-version: 1`; the 59 has
   none. 2.2.0 breaks old files (`SKIP-RESET:`, key 99), which makes it a
   natural point for an optional `FORMAT-VERSION: 2` in the 59. A future app
   could then say "newer format" instead of listing unknown directives.
4. **Naming new directives.** The 59 uses CamelCase (`FullSpeed:`,
   `ArmCard:`) and the 1600 uses kebab-case. Don't add aliases for the
   existing ones; agree on one style for anything new.

## Features one has and the other lacks

| Calc-U-59 | Calc-U-1600 |
|---|---|
| Keycodes (`21 31`) | `- key: shift` |
| — | `- type:` (a line, then ENTER) |
| `Wait: 2s` (a pause at the current speed) | `- wait: 2` (emulated seconds) |
| Every key waits for the scan loop | `- wait:` (until idle) |
| `Trace:` | `- trace:` |
| `FullSpeed:` / `RegularSpeed:` | Always full speed |
| `ZeroElapseTime:` / `ReportElapseTime:` | — |
| `PrinterTrace:`, `CutPaper:` | — |
| `DebugPanel:`, `Freeze:`, `FreezeOnStart:`, `Step:`, `Resume:` | — (the `debug:` block covers only DAP attach) |
| `ArmCard:`, `InsertCard:`, `CARD: mem:` blocks | Media mounted in the header only |
| — | `- expect:`, `- screenshot:`, `- syncclock:` |
| `ArmCard: <file name>` saves a written bank | `- saveas:` |

**Worth bringing to Calc-U-59:**
- **`Expect: <text>`** (the display contains it). This lets the `examples/`
  presets be checked in ctest, as the 1600's `tools/check_presets.sh` does,
  and gives the agentic tools (`tools/agentic/`) an assertion.
- **`Screenshot:`, plus a paper image.** This completes the reason for
  `CutPaper:`: something like `SavePaper: plot.png` followed by `CutPaper:`
  automates printer PNGs without XCUITest. App Store screenshots still need
  the UI tests.
- **A card file next to the preset** (the 1600's `slot-1-file:` pattern).
  The catch is that a 59 preset arrives as bytes, without its folder
  (`SessionController::loadStateFile`). On iOS (sandbox) and the web, a
  sibling file usually can't be read, so the 59 would probably keep `mem:`
  cards as the way to ship a self-contained file.

**Worth bringing to Calc-U-1600:**
- **Speed control and timing** (`FullSpeed:` / `RegularSpeed:`,
  `ZeroElapseTime:` / `ReportElapseTime:`). These would let a preset play
  visibly as a demo instead of always running behind "Loading…".
- **GUI controls** (`DebugPanel:`, `Freeze:`, `Step:`, `Resume:`), if the
  1600's debugger GUI should be scriptable.
- **Swapping media mid-script**, like `InsertCard:` (another floppy or side).

## Recommendation

Keep both syntaxes, apply points 1–4 above, and add `Expect:` and a
paper/screenshot directive to Calc-U-59. Those two give automated checks of
the shipped presets.
