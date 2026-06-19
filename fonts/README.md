# Self-hosting the fonts

The site currently loads fonts from Google Fonts / jsDelivr via `@import` in `colors_and_type.css`. For **www.calcu59.ch** you should serve them from your own domain. Two reasons:

1. **Privacy / law.** Loading Google Fonts from Google's CDN sends every visitor's IP to Google. A German court (LG München I, 2022) ruled that a GDPR violation; Swiss FADP expectations are similar. Self-hosting keeps visitor data on your domain.
2. **Reliability + speed.** No dependency on Google being reachable; no extra DNS/TLS to `fonts.googleapis.com` + `fonts.gstatic.com`.

## Steps

1. **Download the WOFF2 files** (all SIL OFL 1.1 — free to self-host):
   - **Archivo** — weights 400, 500, 600, 700, 800 + italics 400/500/600. Get from <https://gwfh.mranftl.com/fonts/archivo> (google-webfonts-helper bundles the `OFL.txt` for you).
   - **Barlow Condensed** — weights 600, 700. <https://gwfh.mranftl.com/fonts/barlow-condensed>
   - **IBM Plex Mono** — weights 400, 500, 600. <https://gwfh.mranftl.com/fonts/ibm-plex-mono>
   - **DSEG7 Classic** — already a file; grab `DSEG7Classic-Bold.woff2` + the repo's `OFL.txt` from <https://github.com/keshikan/DSEG>.
2. **Drop the `.woff2` files into this `fonts/` folder**, plus each family's `OFL.txt` (license compliance).
3. **Swap the CSS:** in `colors_and_type.css`, delete the three Google `@import` lines and the DSEG7 `@font-face` `src` URL, and `@import "fonts/self-hosted.css";` instead (or paste its contents). A ready-to-use `self-hosted.css` is in this folder — adjust the filenames to match exactly what you downloaded.

## Verify it worked

Open the live site → DevTools → **Network** → filter **Font** → reload. Every `.woff2` should load from `calcu59.ch`, status 200. Then check **Computed → Rendered Fonts** on a heading: it should read `Archivo`.
