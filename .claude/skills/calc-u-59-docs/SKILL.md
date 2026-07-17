---
name: calc-u-59-docs
description: Use this skill when working on the Calc-U-59 documentation or help website (docs/, reference/, root markdown files). Covers the GitHub Pages static site (HTML + client-side React), the design system, and the reference architecture docs. Trigger on any task that touches docs/*.html, docs/*.jsx, docs/*.css, reference/*.md, README.md, CHANGELOG.md, TODO.md, or PRIVACY.md. Also trigger when the user says "update documentation" (or similar) after finishing Core/ and/or App/ work on a release branch — see the Release Documentation Update Workflow section.
user-invocable: true
---

# Calc-U-59 Documentation & Website

This skill covers the help website (`docs/`), reference architecture docs (`reference/`), and root markdown files.

---

## Help Website (`docs/`)

**Hosting:** GitHub Pages at `www.calcu59.ch`  
**Stack:** Static HTML + client-side React 18 loaded from CDN with Babel browser transpiler. No build step, no npm, no Jekyll.

**Git setup — worktree:** `docs/` is a separate git worktree tracking the `gh-pages` branch, not the main repo branch. It is listed in `.gitignore` so it is invisible to the main repo's `git status`. Always commit docs changes from inside `docs/`:

```bash
git -C /path/to/Calc-U-59/docs add <files>
git -C /path/to/Calc-U-59/docs commit -m "..."
```

Do **not** use the root repo's git commands for docs files — they will show nothing staged and the changes will appear lost.

Key files:

| File | Role |
|------|------|
| `docs/index.html` | Entry point; loads React and Babel from CDN |
| `docs/Pages.jsx` | Page content: home, install, debugger, … |
| `docs/Calculator.jsx` | Interactive calculator component |
| `docs/components.jsx` | Reusable UI components |
| `docs/styles.css` | Main stylesheet |
| `docs/colors_and_type.css` | Design tokens (colors, typography) — load this first |
| `docs/preview/` | 16 HTML specimen cards for colors, type, spacing, components |
| `docs/assets/` | App icon, iPad screenshots, device photo |
| `docs/CNAME` | Custom domain record (`www.calcu59.ch`) |

There is also a dedicated design skill at `docs/SKILL.md` that covers generating branded interfaces and visual assets. Do not duplicate its content here — use it when the task is primarily visual or brand-driven.

**The playable web calculator (`docs/#play`)** is a real, WASM-compiled build of the emulation core, not a mock — see `docs/PlayCalculator.jsx`, `docs/calc-engine-worker.js`, `docs/wasm/`. It's built from `tools/pack_roms.py` and `tools/build_wasm.sh` in the main repo; see the Release Documentation Update Workflow below for when to re-run them.

---

## Design System Rules

These are hard constraints — do not break them.

| Rule | Value |
|------|-------|
| Background | `#000` OLED black only — no gradients, no warm paper |
| Accent | `#F0C040` golden yellow — not orange, not warm yellow |
| Headings | Uppercase Barlow Condensed, `0.06em` letter-spacing |
| Radii | 6 / 7 / 10 px — no full pills, no sharp squares |
| Icons | `<K>` keycap pill system only — no emoji, no icon libraries |
| Copy scope | Explains installing, syncing, modules, settings, file formats, the bottom toolbar — not TI-59 hardware internals or AOS arithmetic |

All color and typography tokens are in `docs/colors_and_type.css`. Wrap content in `<div class="calcu">`.

---

## Reference Architecture Docs (`reference/`)

These are AI-generated documents produced by reading the source code alongside hardware documentation. They describe the emulator's internals, not the user-facing app.

| File | Content |
|------|---------|
| `reference/CoreArchitecture.md` | C++ emulation core: TMC0501, SCOM, register model |
| `reference/AppArchitecture.md` | Swift app structure and EmulatorViewModel |
| `reference/DebugAPI.md` | Debug panel and bridge API |
| `reference/USERGUIDE.md` | User-facing guide to the app |

When updating these files, keep the provenance notice at the top intact — it signals that the content is best-effort reverse-engineering, not authoritative hardware documentation.

---

## Root Markdown Files

| File | Purpose |
|------|---------|
| `README.md` | Project overview for GitHub |
| `CHANGELOG.md` | Version history (keep entries under the correct version heading) |
| `TODO.md` | Development task list |
| `PRIVACY.md` | App Store privacy policy |

---

## Release Documentation Update Workflow

Triggered by the user saying **"update documentation"** (or similar) after finishing work on `Core/` and/or `App/` for a release. The current dev branch (`dev-X.Y.Z`) always starts at the HEAD of the previous release tag — that tag, not `main` and not an arbitrary commit count, is the diff base.

1. **Find the base commit — verify, don't trust a single command blindly.**
   This repo has at least one tag anomaly (`v1.6.0` and `v1.5.0` point at the exact same commit — a past tagging mistake), so `git describe --tags --abbrev=0` alone can silently mislead. Cross-check two ways:
   ```bash
   git branch --show-current                        # e.g. dev-1.6.0 → target release 1.6.0
   git tag --list --sort=-v:refname                  # find the entry just below the target version
   git merge-base HEAD v<previous-version>            # should equal...
   git rev-parse v<previous-version>                  # ...this, exactly
   ```
   If `merge-base` and `rev-parse` don't match, the dev branch has extra commits beyond a clean fork point (rebasing, cherry-picks, etc.) — stop and ask the user which commit is the real base rather than guessing.

2. **Review what actually changed.**
   ```bash
   git log <base-commit>..HEAD --oneline
   git diff <base-commit>..HEAD --stat
   ```
   Read the full diff for `Core/`, `App/`, `Bridge/`, and `roms/` — that's where documented facts live. Skip doc-only or test-only commits already made earlier in the same session.

3. **Update `CHANGELOG.md`.** Confirm every user-facing change from step 2 has an entry under the current `[X.Y.Z] - work in progress` heading, in the existing style (bold **Area** prefix, `### Fixes` subsection for bug fixes). Don't add a release date — that happens at release time.

4. **Update reference docs** (`reference/CoreArchitecture.md`, `reference/AppArchitecture.md`, `reference/DebugAPI.md`, `reference/USERGUIDE.md`) for anything the diff invalidated: register model, SCOM layout, PC encoding, machine variants, bridge/debug API surface, settings, file formats. Keep each file's provenance notice intact.

5. **Update the help website** (`docs/Pages.jsx`, `docs/PlayCalculator.jsx`, etc.) if the change is user-facing — new settings, module behavior, install steps, state-file directives. `docs/` is a separate git worktree — commit there, not from the main repo (see above).

6. **Rebuild the WASM calculator (`docs/#play`) only if it's actually affected.** Check whether the diff from step 2 touched:
   - `Core/*.cpp` / `Core/*.hpp` — specifically anything reachable from `docs/wasm/bindings.cpp`'s bound surface (ROM/library/constants loading, key press/release, display snapshot, program/register writes, `stepN`/`stepCycles`, `insertedModuleNumber`). If `TI59Machine`'s public API itself changed, check `bindings.cpp`'s bound-method list against `Core/TI59Machine.hpp` before assuming a plain rebuild covers it — a new or changed method may need a matching binding.
   - `roms/calculator/*.txt`, `roms/solid-state/*.txt` (including `roms/solid-state/cuecards.txt`) — any of these changing means `tools/pack_roms.py` must be re-run to regenerate `docs/wasm/roms/*.json`.

   If either applies:
   ```bash
   python3 tools/pack_roms.py   # only if roms/*.txt changed
   tools/build_wasm.sh          # only if Core/ or bindings.cpp changed
   ```
   Then run `helpsite-unit-tests/run-tests.sh` — `play-calculator.spec.js` covers arithmetic, module cue cards, and preset loading through the real WASM core end to end — before committing.

   If neither `Core/` nor `roms/*.txt` changed (most releases are Swift-only UI/debugger work), skip this step entirely.

7. **Commit in both places, never push.** Main-repo changes (`CHANGELOG.md`, `reference/`, `README.md`, `TODO.md`, `tools/`) commit from the repo root; `docs/` changes commit from inside `docs/` (separate worktree/branch — see above). Two separate commits, following the "commit often, never push" rule below.

---

## Global Rules

1. **Compile, don't run.** Do not launch the Xcode iOS Simulator or run the built Mac app — that is the user's job. When runtime verification is needed, ask the user to launch the app and explain precisely what behaviour or output to look for.

2. **Commit often, never push.** Commit after each logical unit of work. Never run `git push`.

3. **iOS and macOS both must work.** Any Swift changes accompanying documentation updates must leave both platforms building. Both targets must succeed before declaring the task done.

4. **Cite your sources.** When referencing a hardware spec, standard, or external document, include the https URL (or a pointer to the local reference file) inline in the relevant documentation paragraph or code comment.
