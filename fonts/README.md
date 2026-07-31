# Self-hosting the fonts

**Done — this is the current state, not a plan.** `colors_and_type.css` does
`@import "fonts/self-hosted.css"`, and every `.woff2` in this folder is served
from `calcu59.ch`. Two reasons, and they are why it must stay that way:

1. **Privacy / law.** Loading Google Fonts from Google's CDN sends every visitor's IP to Google. A German court (LG München I, 2022) ruled that a GDPR violation; Swiss FADP expectations are similar. Self-hosting keeps visitor data on your domain.
2. **Reliability + speed.** No dependency on Google being reachable; no extra DNS/TLS to `fonts.googleapis.com` + `fonts.gstatic.com`.

The reasoning is not font-specific. It is why the site loads **nothing** from
a third party — React and the WASM core are vendored too — and why it carries
no analytics. `.seo/check.js` fails the build on any off-origin resource, so
re-introducing a CDN `@import` here will be caught rather than shipped.

## Steps — how it was done, and how to add or replace a family

1. **Download the WOFF2 files** (all SIL OFL 1.1 — free to self-host):
   - **Archivo** — weights 400, 500, 600, 700, 800 + italics 400/500/600. Get from <https://gwfh.mranftl.com/fonts/archivo> (google-webfonts-helper bundles the `OFL.txt` for you).
   - **Barlow Condensed** — weights 600, 700. <https://gwfh.mranftl.com/fonts/barlow-condensed>
   - **IBM Plex Mono** — weights 400, 500, 600. <https://gwfh.mranftl.com/fonts/ibm-plex-mono>
   - **DSEG7 Classic** — already a file; grab `DSEG7Classic-Bold.woff2` + the repo's `OFL.txt` from <https://github.com/keshikan/DSEG>.
2. **Drop the `.woff2` files into this `fonts/` folder**, plus each family's `OFL.txt` (license compliance).
3. **Wire it into the CSS:** `colors_and_type.css` already carries `@import "fonts/self-hosted.css";` and no Google `@import`. Add the new family's `@font-face` block to `self-hosted.css`, with filenames matching exactly what you downloaded.

## Verify it worked

Open the live site → DevTools → **Network** → filter **Font** → reload. Every `.woff2` should load from `calcu59.ch`, status 200. Then check **Computed → Rendered Fonts** on a heading: it should read `Archivo`.
