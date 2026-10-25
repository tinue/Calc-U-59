---
name: calc-u-59-web
description: Use this skill when working on the Calc-U-59 web client (Web/) — the browser calculator on Core/ + Shared/ compiled to WebAssembly: the React components in Web/src/, the engine worker, Web/bindings.cpp, calc.css, the installable PWA in Web/app/, Web/build.sh and Web/dist/, the Playwright tests in Web/tests/, and the `web` job in .github/workflows/build.yml. Also trigger when SessionController's or Platform's interface changes (bindings.cpp is the web's adapter), or when the website needs to know how to embed the client.
user-invocable: true
---

# Calc-U-59 Web Client

The third GUI next to the Swift and Qt6 apps: `Core/` + `Shared/` compiled
with Emscripten, run single-threaded in a Web Worker; React only draws and
forwards input. Two layouts: wide (as the macOS/Qt window: calculator,
printer, debugger) and portrait (as the iPhone: calculator and printer
pages; the PWA). Orient new GUI work on the Qt app's widget of the same
name (`WebClient.md` § "Layout of `Web/`" maps them).

Layout, build steps, the `dist/` contract, mounting, location independence,
the render rule, styling, the PWA and `MANIFEST.json`:
**`reference/WebClient.md`**. Don't restate them here. Everything that isn't
drawing: `reference/SharedArchitecture.md`. Feature placement:
`reference/FrontendParity.md` (the Web column).

The website (https://calc-u.org/59/, repository `calc-u-site`) only
*embeds* a built `dist/`, imported from a release's `Calc-U-59-web.zip`.
Never edit the calculator there, nor in an old `docs/` worktree — those
copies are generated or retired.

## Rules

1. **No logic in `Web/`.** Parsing, timing, key sequencing, layout numbers,
   cue-card resolution all belong in `Shared/` (calc-u-59-shared skill) —
   the JS draws what the worker posts. `bindings.cpp` translates types only,
   like `Qt6/app/EmulatorController`.
2. **Parity** (CLAUDE.md § "Frontend Parity"): a user-visible change to a
   feature the web has needs the matching change in the apps, or a
   `Pending` row in `FrontendParity.md` — and the reverse. Update the table
   either way.
3. **Location-independent.** No root-relative URL anywhere: resolve against
   `CALC_BASE` (`calc.js`'s own URL, `src/engine.js`), the worker's or the service worker's
   location, or the page (`app/`). New files the PWA needs offline go into
   `app/sw.js`'s `CORE_ASSETS` (build.js fails on a missing one).
4. **Render has no side effects.** `fetch`, `new Worker`, listeners and
   timers start in effects only; module-level code reads nothing but
   `document.currentScript`/`location`. The site prerenders with stubs that
   throw.
5. **`calc.js` exposes `PlayCalculator` only.** The sources are concatenated
   into one closure; a new file goes into `SOURCES` in `build.js`, in load
   order. Its props (`WebClient.md` § "Mounting it") and the stable hooks
   are the contract — changing them is a change for the website too.
6. **The client brings its own styling.** Tokens live in `calc.css` on
   `.calcu-client`, never `:root`; don't depend on the host's CSS. Fonts and
   React are self-hosted in `Web/` (no CDN).
7. **Assets have one source:** ROMs from `roms/`, artwork from
   `App/Assets.xcassets`, presets from `examples/` (listed in
   `presets.json`), the icon from `Qt6/resources/linux/` (derived from
   `App/AppIcon.icon`). `build.sh` copies them; never commit copies.
8. **Build and test before committing:** `Web/build.sh && Web/run-tests.sh`.
   Also after any `Core/` or `Shared/` change (CLAUDE.md).
9. **Commit often, never push.**

## Build and test

```bash
Web/build.sh                       # → Web/dist/ (~15 s)
Web/run-tests.sh                   # all tests, at / and under /anything/calc/
Web/run-tests.sh -g "cue card"     # extra args go to playwright test
python3 -m http.server 8000 -d Web/dist   # look at it: http://localhost:8000/
```

The tests (`tests/play-calculator.spec.js`) drive `dist/index.html` and
`dist/app/` through the real engine: arithmetic by bitmap identity of the LED
canvas, the hit test and drag, the physical keyboard, models and the TI-58C
constant memory, settings, cue cards, presets, the card folder, the printer,
the debugger and trace download, the portrait pages, the service worker's
precache. Key presses after a program stops can extend its last entry, as
on the real calculator — press CLR first. `tests/prerender.spec.js` renders `calc.js`
in Node. Ports 8059 and 8060 (`CALCU_WEB_PORT` moves both).

CI: job `web` in `.github/workflows/build.yml` (emsdk pinned to the local
`emcc --version`; bump both together) builds, tests and uploads
`Calc-U-59-web-<version>.zip`; `release` attaches it as `Calc-U-59-web.zip`.
