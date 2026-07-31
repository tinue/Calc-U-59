# The static build

**Every `.jsx` edit needs `node .seo/build.js` before you commit.** That is the
only rule. The rest of this file explains how the site is put together.

```bash
cd docs
node .seo/build.js     # compile + prerender. No dependencies.
node .seo/check.js     # verify. Optional: npm i --no-save jsdom for the boot check.
```

## How the site is built

The site is authored as React components but published as plain static HTML.
`build.js` does two things:

1. **Compiles** every `.jsx` to plain `.js` in `build/`, so no visitor pays for
   an in-browser Babel transform.
2. **Prerenders** every route in `routes.js` to a real HTML file at a real URL,
   with its own `<title>`, description, canonical, Open Graph tags and JSON-LD.
   `site.jsx` boots on top and takes over navigation, so the site still behaves
   like a single-page app once loaded.

The prerendered markup is the output of the same components, rendered by
`ReactDOMServer` instead of `ReactDOM`, so the design is identical either way.
A visitor with no JavaScript, and every crawler, gets complete markup.

## How the SEO works

Each piece has one home, and `check.js` asserts the result:

| Concern | Where it lives |
|---|---|
| URLs | `ROUTES` in `routes.js` — one entry per page. Trailing slash is canonical. |
| Title and description | `PAGES` in `.seo/pages.js`. **Edit this** to change how a page reads in a result list. |
| Canonical | Derived from the route: self-canonical unless the entry sets `canonical`. |
| `<h1>`, body copy | The component in `Pages.jsx`. One `<h1>` per page. |
| Open Graph / Twitter | `renderPage()` in `build.js`, from the same title and description. |
| Structured data | `build.js`: `SoftwareApplication` on the home page, `FAQPage` on `/faq/` (parsed out of `Pages.jsx` so markup and JSON-LD cannot disagree), `BreadcrumbList` everywhere else. |
| `sitemap.xml` | Generated from `ROUTES` — self-canonical pages only. |
| `robots.txt` | Generated. Blocks `/app/` and `/preview/`; deliberately does **not** block `/build/` or `/vendor/`, which hold the scripts a crawler needs to render the page. |
| `404.html` | The home page chrome, `noindex`, no canonical. GitHub Pages serves it for unknown paths. |

Two rules are easy to break by accident:

- **One page, one job.** Two URLs that render the same markup compete with each
  other. If a route restates another page, give it a `canonical` in `routes.js`
  pointing at the primary; it stays reachable but leaves the sitemap. This is
  why `/getting-started/` renders an `overview` topic of its own rather than
  defaulting to one of its sidebar topics — that would make it a byte-identical
  twin of `/getting-started/install-iphone-ipad/`.
- **A canonical must name a page that says the same thing.** Pointing one at a
  page with different content gets the canonical ignored. If a topic has no
  real equivalent elsewhere, either let it stand on its own — as
  `/getting-started/printer/` does — or make it an outbound link instead of a
  route, as the GitHub README is.

## Files

| Path | Role |
|---|---|
| `.seo/build.js` | The build. Compile, prerender, sitemap, robots, 404. |
| `.seo/check.js` | 400-odd assertions over the output. Run it before pushing. |
| `.seo/pages.js` | Per-page `<title>` and meta description. |
| `.seo/vendor/` | `react-dom-server`, the one file not already vendored for the browser. |
| `routes.js` | The URL map. Shared by the browser router and the build. |
| `site.jsx` | Client router. |
| `build/` | Generated. Never edit; never hand-fix. |

Generated and safe to delete before a rebuild: `build/`, `index.html`,
`404.html`, `robots.txt`, `sitemap.xml`, and the `index.html` inside every route
directory (`faq/`, `play/`, `modules/`, …).

Hand-written and never touched by the build: every `.jsx`, `styles.css`,
`colors_and_type.css`, `assets/`, `fonts/`, `wasm/`, `presets/`, and all of
`app/` — the installable PWA still uses the in-browser Babel path and is
unaffected.

## Adding a page

1. Write the component in `Pages.jsx` and export it via the `Object.assign(window, …)`
   block at the bottom.
2. Add it to `COMPONENTS` in `.seo/build.js`.
3. Add a route to `ROUTES` in `routes.js`.
4. Add a title and description to `PAGES` in `.seo/pages.js`.
5. Render it in `App()` in `site.jsx`.
6. Link to it from somewhere — an orphan page is a page search engines discount.
7. `node .seo/build.js && node .seo/check.js`

## Keeping it from going stale

The one failure mode worth guarding: someone edits a `.jsx`, commits, and the
published HTML still shows the old text. `check.js` will not catch that — it
validates the last build, not whether the build is current.

CI covers it. `.github/workflows/build-site.yml`, **on this branch**, runs on
every push to `gh-pages`: it rebuilds, runs `check.js`, and commits the result
if the output differs. Actions runs the copy of a workflow that lives on the
branch being pushed, and `gh-pages`'s root is the site, so paths inside that
file have no `docs/` prefix.

Two things keep it from looping: pushes made with `GITHUB_TOKEN` do not trigger
workflows, and a build whose output is already current stages nothing. The push
*does* trigger the Pages deployment, which is the point.

## After deploying

- Verify the site in [Google Search Console](https://search.google.com/search-console)
  and submit `https://www.calcu59.ch/sitemap.xml`. Do the same in
  [Bing Webmaster Tools](https://www.bing.com/webmasters), which also feeds
  DuckDuckGo.
- Use the URL Inspection tool on `/play/` and `/what-is-a-ti-59/` and request
  indexing. Those two are the pages most likely to match a cold search.
- The App Store listing and the GitHub repository both rank already. Link from
  each of them to `https://www.calcu59.ch/` — the repository's About field and
  its README are the cheapest, strongest links available.
