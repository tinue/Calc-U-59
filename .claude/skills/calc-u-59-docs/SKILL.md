---
name: calc-u-59-docs
description: Use this skill when working on the Calc-U-59 documentation or help website (docs/, reference/, root markdown files). Covers the GitHub Pages static site (HTML + client-side React), the design system, and the reference architecture docs. Trigger on any task that touches docs/*.html, docs/*.jsx, docs/*.css, reference/*.md, README.md, CHANGELOG.md, TODO.md, or PRIVACY.md.
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

## Global Rules

1. **Compile, don't run.** Do not launch the Xcode iOS Simulator or run the built Mac app — that is the user's job. When runtime verification is needed, ask the user to launch the app and explain precisely what behaviour or output to look for.

2. **Commit often, never push.** Commit after each logical unit of work. Never run `git push`.

3. **iOS and macOS both must work.** Any Swift changes accompanying documentation updates must leave both platforms building. Both targets must succeed before declaring the task done.

4. **Cite your sources.** When referencing a hardware spec, standard, or external document, include the https URL (or a pointer to the local reference file) inline in the relevant documentation paragraph or code comment.
