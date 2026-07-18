# Credits & Licenses — Calc-U 59 website

Every third-party asset used on **www.calcu59.ch**, with its source and license. The goal: only openly-licensed material, with a paper trail. Keep this file current whenever an asset is added.

---

## Fonts

All fonts are licensed under the **SIL Open Font License 1.1** (OFL) — free for commercial use, web embedding, and self-hosting. OFL obligations: keep the `OFL.txt` license file with the font when redistributing the font files; don't sell the fonts on their own; don't release a modified version under the reserved font name.

| Font | Use on site | Author / Foundry | License | Source |
|---|---|---|---|---|
| **Archivo** | Headings + body | Omnibus-Type | SIL OFL 1.1 | <https://fonts.google.com/specimen/Archivo> |
| **Barlow Condensed** | Device keycaps only | Jeremy Tribby | SIL OFL 1.1 | <https://fonts.google.com/specimen/Barlow+Condensed> |
| **IBM Plex Mono** | Code / keystroke listings | IBM | SIL OFL 1.1 | <https://fonts.google.com/specimen/IBM+Plex+Mono> |
| **DSEG7 Classic** | LED display readout | keshikan (けしかん) | SIL OFL 1.1 | <https://github.com/keshikan/DSEG> |

> **Delivery:** currently loaded from Google Fonts / jsDelivr via `@import` in `colors_and_type.css`. For the `.ch` domain, self-hosting is recommended (privacy + reliability) — see `fonts/README.md`. When self-hosting, place each font's `OFL.txt` in `fonts/`.

---

## Images

| Asset | Description | Rights holder | Status |
|---|---|---|---|
| `assets/app-icon.png` | Calc-U 59 app icon | Project author (you) | ✅ owned |
| `assets/app-screenshot.png` | iPhone screenshot of the app | Project author | ✅ owned |
| `assets/iphone-debug.png` | iPhone debugger screenshot | Project author | ✅ owned |
| `assets/ipad-13-2752x2064.png` | iPad CALCULATOR-tab screenshot | Project author | ✅ owned |
| `assets/ipad-2752x2064-asm.png` | iPad CPU-tab screenshot | Project author | ✅ owned |

All imagery on the site is the project author's own work (screenshots of, and the icon for, the Calc-U 59 app). No third-party photographs are used. (A photo of a physical TI-59, `TI59.png`, was removed from the project because its provenance was unverified.)

---

## Icons

No icon library is used. The site's icon vocabulary is:
- The **app icon** (above).
- The **`<K>` keycap pill** — original CSS, no external asset.
- **iOS-toolbar glyphs** — original SVG paths hand-drawn in `Calculator.jsx` (download, plus, share, gear, undo, chevrons). They resemble Apple's SF Symbols but are **not** SF Symbols (which are license-restricted and Apple-platform-only); they are generic, originally-drawn shapes.

---

## Trademarks (not copyright)

“TI-59”, “TI-58”, “TI-58C”, “Texas Instruments”, “Solid State Software”, and “Master Library” are trademarks of Texas Instruments and/or their respective owners. They are used on this site **descriptively** (nominative use) to identify what the app emulates. The site carries a non-affiliation disclaimer in its footer and does **not** reproduce TI's logo or scanned manual pages.

---

## Reference material (not published)

The original TI-59 owner's manual and ad material were consulted **privately** to match the typographic style (Helvetica → Archivo). No scans or copyrighted manual text are reproduced on the public site.

---

## Code

- **React 18 / ReactDOM** (18.3.1, production builds) — MIT, self-hosted in `vendor/`.
- **Babel Standalone** (7.29.0) — MIT, self-hosted in `vendor/`.
- Site source (HTML/CSS/JSX) — authored for this project.
