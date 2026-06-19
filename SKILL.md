---
name: calc-u-59-design
description: Use this skill to generate well-branded interfaces and assets for Calc-U 59, either for production or throwaway prototypes/mocks/etc. Contains essential design guidelines, colors, type, fonts, assets, and UI kit components for prototyping the help website of a TI-59 calculator emulator.
user-invocable: true
---

Read the `README.md` file within this skill, and explore the other available files.

The system is built around the **Calc-U 59 emulator app** for Mac, iPhone, and iPad (a TI Programmable 59 emulator). The visual DNA — pure-black OLED background, dark brown function keys with cream silkscreen, golden-yellow accent keys, cream number keys, mahogany display strip with a red LED — should appear in every artifact you produce. The canonical visual reference is `assets/app-screenshot.png`; brand mark is `assets/app-icon.png`.

**Scope:** this design system is for the EMULATOR APP, not the underlying 1977 calculator. Help-site copy should explain installing, syncing, modules, settings, file formats, the bottom toolbar — not how AOS arithmetic or registers work on real hardware.

Key files:
- `colors_and_type.css` — all color and typography tokens. Load this first; wrap your content in `<div class="calcu">`.
- `assets/app-screenshot.png` — canonical app screenshot; `assets/app-icon.png` — brand mark.
- `index.html` + `Pages.jsx` / `Calculator.jsx` / `components.jsx` — the help website (loads at the project root for GitHub Pages). Copy components from here rather than reinventing.
- `CREDITS.md` — every asset + its license. `fonts/` — self-hosting setup.
- `preview/` — small specimen cards demonstrating colors, type, spacing, components, brand.

If creating visual artifacts (slides, mocks, throwaway prototypes, etc), copy assets out and create static HTML files for the user to view. If working on production code, you can copy assets and read the rules here to become an expert in designing with this brand.

If the user invokes this skill without any other guidance, ask them what they want to build or design, ask some questions (target page? help topic? availability strip? release notes?), and act as an expert designer who outputs HTML artifacts _or_ production code, depending on the need. Default to plain HTML (no Jekyll, no build step) — this brand is GitHub Pages bound.

Hard rules, do not break:
- No emoji.
- No icon libraries. The `<K>` keycap pill IS the icon system; six hand-drawn SF-Symbol-likes cover the toolbar.
- Headings are uppercase Barlow Condensed with 0.06em tracking.
- Page background is pure `#000` (OLED black). No warm paper, no gradients.
- Accent is golden yellow `#F0C040` — not orange.
- Soft radii (6 / 7 / 10 px). No pills, no harsh squares.
- No bluish-purple gradients, no glassmorphism, no playful copy.
- Plain static HTML for the help site (GitHub Pages target). No Jekyll, no build step.
