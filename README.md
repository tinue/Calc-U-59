# Calc-U 59 — Design System

A design system for the **Calc-U 59 help website** — the user guide for a TI Programmable 59 emulator app available on Mac, iPhone, and iPad. This system is built to be served as **plain HTML on GitHub Pages** (no Jekyll, no build step).

The visual language is sampled directly from the running application (see `assets/app-screenshot.png`) and the app icon (`assets/app-icon.png`).

> **Important scope note:** This guide explains the **emulator app** — installing it, navigating its UI, switching modules, syncing programs — **not** how to operate a real TI-59 calculator. Keep that in mind when writing new pages: assume the reader is learning the app, not the 1977 hardware.

---

## Source materials

| Source | Path / link | Status |
|---|---|---|
| iPhone screenshot of the running app | `assets/app-screenshot.png` | ✅ canonical visual reference |
| App icon (1024×1024) | `assets/app-icon.png` | ✅ used for header, brand cards, hero |
| GitHub repository | <https://github.com/tinue/Calc-U-59> | ⚠️ not reachable from the sandbox; visuals are reconstructed from the screenshot. Browse the repo yourself to expand the system. |
| Related emulator (sibling reference) | <https://github.com/TurboGit/ti5x_android> | optional — same hardware, different platform |

---

## CONTENT FUNDAMENTALS

The site is the user guide for an emulator app — niche, technical, and proud of it.

- **Voice:** confident, concise, slightly reverent. The reader chose to install a 49-year-old calculator on their phone; treat them as an enthusiast, not a beginner.
- **Person:** Second-person "you" for instructions ("tap the TI-59 picker"). First-person plural only for editorial framing.
- **Casing:** Headings are **UPPERCASE** in Barlow Condensed — the visual rhyme with the keycap silkscreen. Body copy is sentence case.
- **Tone examples:**
  - ✅ "Tap the **TI-59** picker in the bottom toolbar to load a different module."
  - ✅ "Programs sync via iCloud. There is no account to create."
  - ❌ "Ready to crunch some numbers? Let's go! 🚀"
  - ❌ "Whoops! That module isn't loaded."
- **What to write about:** installing, syncing, importing programs, the bottom toolbar, the module picker, settings (sound, precision, angle mode), file formats, differences from the real TI-59. **Do not** write tutorials on what AOS is, how registers work, or how to program in keystroke language — that's calculator content, not app content.
- **Keystrokes** are typographic, never plain text. Use the `<K tone="yellow">2nd</K> <K tone="dark">LRN</K>` component — colored to match the physical key tone.
- **Emoji:** none.
- **Numerals:** spell one through nine in prose; numerals for 10+ and always for step numbers, register addresses, and keystroke counts.

---

## VISUAL FOUNDATIONS

### Colors

The palette is sampled from `assets/app-screenshot.png`. The app is **OLED-black** — there is no warm-paper background anywhere in the product.

| Token | Hex | Role |
|---|---|---|
| `--bg` / `--bg-black` | `#000000` | App + site background |
| `--bg-elevated` | `#14100c` | Card / panel above black |
| `--bg-inset` | `#1A130D` | Code, well, sidebar active state |
| `--key-dark` | `#2A1F15` | Dark brown function-key face |
| `--key-cream` | `#EFE4CC` | Cream number-key face |
| `--accent-yellow` | `#F0C040` | **Primary accent.** 2nd, CLR, ÷×−+= keys, CTA buttons, active nav |
| `--display-bezel` | `#2C1812` | Mahogany strip around the LED |
| `--led-bg` | `#1A0606` | Behind the segments |
| `--led-red` | `#FF2614` | Lit segment red |
| `--silk-cream` | `#D4C4A0` | Labels printed *above* keys |
| `--ios-blue` | `#0A84FF` | iOS toolbar tint ("TI-59" picker, links) |
| `--fg` / `--fg-2` / `--fg-3` | `#EFE4CC` / `#B8A880` / `#7A6A55` | Primary / secondary / tertiary text on black |

Note that the accent is **golden yellow**, not orange. The earlier draft had it wrong — the running app uses `#F0C040` for accent keys and CTAs.

### Typography

Period-correct **Swiss grotesque**, modeled on TI's late-1970s manuals (set in Helvetica). Four faces:

1. **DSEG7 Classic** (`--font-display`) — 7-segment LED face for the red readout. **Substitution flag:** closest free font to the bubble-LED segments.
2. **Archivo** (`--font-key` headings + `--font-body` body) — neutral Helvetica analog. Carries page titles, section headings, nav, buttons, eyebrows, and all running text. Letterspaced bold uppercase headings mirror the manual's "INTRODUCTION" treatment; its **italic** powers the *Solid State Software* signature phrase.
3. **Barlow Condensed** (`--font-keycap`) — condensed sans, used **only** for the device keycaps and the "MASTER LIBRARY DIAGNOSTIC" strip. Condensed type belongs on the device, not the page.
4. **IBM Plex Mono** (`--font-mono`) — code / keystroke / file-format listings.

All four are **SIL OFL 1.1** — see `CREDITS.md`. To self-host (recommended for the `.ch` domain), see `fonts/README.md`.

> The big shift from the first draft: headings moved from condensed (Barlow) to regular-width grotesque (Archivo). TI's manual headers are regular-width Helvetica Bold, *not* condensed — so Archivo is more period-correct. Condensed is now reserved strictly for the keycaps.

### Backgrounds and surfaces

- **Page background is pure `#000000`.** No gradient, no texture, no paper warmth.
- Cards are `--bg-elevated` (`#14100C`) with a hairline `--stroke` border and a faint two-layer shadow.
- The **mahogany display strip** is its own component — dark wood-toned gradient with a 1px warm hairline border, containing the LED window and the module-instruction overlay text. Replicate it via the `<Display>` component in `Calculator.jsx` rather than redrawing.
- The **module header strip** ("MASTER LIBRARY DIAGNOSTIC  ML-01") sits below the LED window in `--silk-mahogany` orange-tan (`#C89858`) — a signature element.

### Borders, radii, and shadows

- Radii are **soft, not pill**: `--radius-key-cream 6px`, `--radius-key 7px`, `--radius-card 10px`, `--radius-display 10px`. Larger than the previous draft — the iOS app uses softer rounding than the physical device.
- **Three physical-button shadow recipes** (one per key tone). Each has a hard 1px bottom bevel + a 2–4px soft cast + an inset top highlight. See `--shadow-key`, `--shadow-key-cream`, `--shadow-key-yellow`.
- Pressed state replaces the elevation with `inset 0 2px 4px rgba(0,0,0,.6)` and translates the key 1px down.
- LED display uses `--shadow-led-glow` — two-layer red glow that sells the phosphor.

### Hover & press states

- **Primary CTAs**: hover lifts brightness 6%. No transform on click.
- **Keycaps (interactive)**: press inset shadow + 1px translateY.
- **Nav links**: hover wash in `rgba(240,192,64,.06)`; active page gets a 2px yellow `box-shadow: inset 0 -2px 0` underline.
- **Sidebar links**: active gets a 2px left border in `--accent` plus the same yellow wash.
- **Links in prose**: iOS blue (`--link`), underline on hover only.

### Animation

- **Sparing.** Only `transition: 0.15s ease` on color/background changes.
- No bounces, no springs, no scroll-driven effects. The brand is mid-century-industrial-meets-iOS — neither half wants gimmicky motion.

### Transparency and blur

- The site header uses `backdrop-filter: blur(6px)` over `#000` — barely visible, but lets content peek through on long pages.
- Inside the calculator: the small "›" chevron control in the display has a 12% warm-tan wash for affordance. That's it.

### Imagery

- The hero assets are the screenshot (`assets/app-screenshot.png`) and the app icon (`assets/app-icon.png`). Treat them on pure black; any device-frame mockup should be on black too.
- App icon corner radii follow Apple's continuous-curve squircle. The provided PNG already has the corner shape baked in — render flat, do not add additional rounding.

### Layout rules

- Max content width: **1120px**. Narrow variant: **820px**.
- Section headings use uppercase Barlow Condensed @ 0.06em tracking.
- A consistent **eyebrow** sits above each heading: 11px Barlow Condensed @ 0.18em tracking in `--accent`.
- The **App Reference** page uses a sticky right rail (the live calculator) so readers can inspect the UI while reading any annotation.

---

## ICONOGRAPHY

The brand uses **no general-purpose icon library**. Here is the system's full icon vocabulary:

1. **The app icon** (`assets/app-icon.png`) — dark brown rounded square with a yellow-outlined calculator illustration and a red "59" LED. Used at 40px in the site header, 64–160px in brand contexts, and as the favicon.
2. **The `<K>` keycap pill** — the system's primary "icon." When you need to refer to a calculator action, render the actual key as a small pill (cream / dark / yellow) — not an abstract glyph.
3. **The mahogany "module token"** — narrow bordered rectangle used in the display strip (`[SBR]`, `[CLR]`, `[STO]`) to indicate a key referenced inside an on-display instruction. Implemented as the `<Token>` component in `Calculator.jsx`.
4. **iOS bottom-toolbar SF-Symbol-likes** — six hand-drawn SVG glyphs that mimic Apple's SF Symbols for the live app's bottom bar: `SymbolUndo`, `SymbolChevrons`, `SymbolDownload`, `SymbolPlus`, `SymbolShare`, `SymbolGear`. **Flag:** these are reasonable approximations, not real SF Symbols (SF is not redistributable). If you can ship an Apple-platform-only build, switch to real SF Symbols at runtime.

**Hard rules:**

- **No emoji.** Not in prose, not in nav, not in callouts.
- **No Unicode-as-icon hacks** (`▶`, `⚙`, `✓`, `⚠`). Use the SF-symbol-likes or Barlow Condensed labels instead.
- **No external icon CDNs** (Lucide / Heroicons / Feather / Font Awesome). The vocabulary above is the whole vocabulary.
- **No SVG illustrations of the calculator hardware.** The `<Calculator>` React component IS the illustration — render it inline.

If a future page truly needs a glyph the system doesn't cover (e.g. a download-availability chip), commission a specific monochrome SVG with 1.6px stroke, no fills, square line caps — to match the SF-symbol-likes already in `Calculator.jsx`.

**Photographic assets** in `assets/`:
- `app-icon.png` — 1024×1024 app icon
- `app-screenshot.png` — full iPhone screenshot of the live app

---

## File index

Files live at the **project root** so they map 1:1 to the `gh-pages` branch root that GitHub Pages serves at `www.calcu59.ch`.

```
── Site (deploy to gh-pages branch) ───────────────────────────
index.html                      · landing page — entry point
styles.css                      · site-level CSS on top of colors_and_type.css
components.jsx                  · SiteHeader, SiteFooter, K, KSeq, TopicCard, DocsSidebar, Placeholder
Calculator.jsx                  · pixel-faithful recreation of the iOS app
Pages.jsx                       · 5 pages — Home has prose, others are scaffolding
PlayCalculator.jsx              · #play — real WASM-compiled emulator core, playable in-browser (built from tools/build_wasm.sh in the main repo)
colors_and_type.css             · shared with the design system
CNAME                           · "www.calcu59.ch" — GitHub Pages custom domain
assets/
  app-icon.png                  · 1024² app icon (also serves as favicon)
  app-screenshot.png            · iPhone screenshot — canonical visual reference

── Design-system source (stays on main; not deployed) ─────────
README.md                       · this file
SKILL.md                        · Agent-Skill manifest for Claude Code
preview/                        · Design System tab cards (~700px wide each)
  colors-brand.html             · 8 brand-palette swatches
  colors-semantic.html          · semantic surface tokens
  colors-foreground.html        · text colors on dark + on cream
  type-headings.html            · H1–H4 specimen
  type-body.html                · body + inline (code, kbd, link)
  type-led-display.html         · LED with module header strip
  spacing-radii.html            · 4→64 spacing + 6/7/10 radii
  spacing-elevation.html        · dark / cream / yellow / pressed / LED shadows
  components-keycaps.html       · three-tone keycap component
  components-buttons.html       · primary / secondary / ghost
  components-cards.html         · panel + accent callout
  components-keystroke.html     · keystroke sequence + module strip
  brand-logo.html               · app icon + wordmark lockup
  brand-app-icon.html           · icon at 4 sizes
  brand-hero.html               · iPhone screenshot in hero context
```

---

## How to use

1. Drop `colors_and_type.css` into your page and wrap content in `<div class="calcu">`.
2. The site is **plain static HTML** at the project root — no build step. The React + JSX + Babel pipeline runs in the browser via CDN scripts. Open `index.html` directly in a browser, or run `python3 -m http.server` for proper relative-path serving.
3. To write a new help page, copy the `Placeholder` pattern in `Pages.jsx`: an eyebrow, a `page-title` H1, then a `<Placeholder>` block. Replace the placeholder with prose when ready. The intent is to keep page chrome solid while content remains TBD.
4. Use `<K tone="cream|dark|yellow">` for any key reference. **Never** type keystrokes as ASCII like `[2nd] [LRN]` — the typographic version is part of the brand.

---

## Deploy workflow

Site files (everything in the **Site** block above) live on a `gh-pages` branch; design-system source lives on `main`. Recommended setup with `git worktree`:

```bash
# one-time, from your main checkout
git checkout --orphan gh-pages
git rm -rf .                  # start the branch empty
git commit --allow-empty -m "init gh-pages"
git push origin gh-pages

# from now on, work the site in a worktree
git worktree add docs gh-pages
cp index.html styles.css *.jsx CNAME docs/
cp -r assets colors_and_type.css docs/
cd docs && git add . && git commit -m "deploy" && git push
```

After enabling GH Pages on the `gh-pages` branch in repo settings and pointing DNS at GitHub's IPs, the site is live at `www.calcu59.ch`. The `CNAME` file is what binds the custom domain — GitHub reads it on every deploy.

---

## Known gaps / open questions

- **GitHub repo (`tinue/Calc-U-59`) was not accessible** from the build sandbox. The screenshot and icon are the only first-party app references. If the repo contains source (Swift / SwiftUI?), reading it will reveal authoritative naming for settings, file paths, and toolbar labels — please re-attach or provide a public-fetch URL when convenient.
- **No information yet on:** macOS-specific UI variants, iPad layout, the print-cradle (PC-100A) emulation surface, the settings panel contents. The Home + Reference pages reserve space for these without inventing details.
- **Fonts are substitutes:** DSEG7 Classic for the LED, Barlow Condensed for headings/keycaps. Genuine TI silkscreen fonts welcome.
- **SF Symbols are approximations:** the six bottom-toolbar icons in `Calculator.jsx` are hand-drawn SVG. They're close to Apple's set but not identical.

Explore the source repos for more context: <https://github.com/tinue/Calc-U-59> and the related <https://github.com/TurboGit/ti5x_android>. Reading either will improve the next pass of this design system.
