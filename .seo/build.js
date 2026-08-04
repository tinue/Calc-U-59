#!/usr/bin/env node
//
// Calc-U 59 — static site build.
//
//   node .seo/build.js
//
// Two jobs, both of which exist for the same reason: before this, the
// entire site was one URL whose body was an empty <div id="root"> filled
// in by an in-browser Babel transform. Crawlers indexed nothing.
//
//   1. Precompile every .jsx to plain .js in docs/build/. This drops the
//      3.1 MB babel.min.js runtime transform from the critical path.
//   2. Prerender every route in routes.js with ReactDOMServer into a real
//      static HTML file at a real URL, with its own <title>, description,
//      canonical, Open Graph tags and JSON-LD. The React app boots on top
//      and takes over navigation, so behaviour is unchanged.
//
// Zero npm dependencies: React and Babel are the copies already vendored
// in docs/vendor/ for the browser; the one extra file, the server
// renderer, is vendored alongside this script.
//
// Run it after editing any .jsx, or let .github/workflows/build-site.yml
// (see .seo/README.md) run it on push.

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const SEO = __dirname;
const DOCS = path.join(SEO, "..");
const OUT_JS = path.join(DOCS, "build");

const { ROUTES, ORIGIN } = require(path.join(DOCS, "routes.js"));
const { PAGES, FALLBACK } = require(path.join(SEO, "pages.js"));

const read = (p) => fs.readFileSync(p, "utf8");
const log = (...a) => console.log("  ", ...a);

/* ------------------------------------------------------------------ *
 * 1. Sandbox
 *
 * The .jsx files are browser scripts, not modules: they declare things
 * at top level and hand them out with Object.assign(window, {...}). So
 * the renderer needs a `window`, and everything has to be evaluated in
 * one script — top-level `const` is shared across <script> tags via the
 * global lexical environment in a browser, and concatenation is how you
 * reproduce that in a VM context.
 * ------------------------------------------------------------------ */
function makeSandbox() {
  const noop = () => {};
  const stubEl = () => ({
    style: {}, dataset: {}, classList: { add: noop, remove: noop, toggle: noop },
    setAttribute: noop, getAttribute: () => null, appendChild: noop,
    addEventListener: noop, removeEventListener: noop, getContext: () => null,
  });

  const sandbox = {
    console, process,
    setTimeout, clearTimeout, setInterval, clearInterval,
    queueMicrotask, TextEncoder, TextDecoder, URL, Uint8Array, Math, Date, JSON,
    navigator: { userAgent: "calcu59-static-build", platform: "node" },
    location: { pathname: "/", hash: "", search: "", href: ORIGIN + "/", replace: noop, assign: noop },
    history: { length: 1, pushState: noop, replaceState: noop, back: noop, state: null },
    requestAnimationFrame: () => 0,
    cancelAnimationFrame: noop,
    matchMedia: () => ({ matches: false, addEventListener: noop, removeEventListener: noop }),
    // Anything that would reach the network or spawn a thread is a hard
    // error rather than a silent no-op: it should only ever be called
    // from an effect, which never runs during renderToStaticMarkup.
    fetch: () => { throw new Error("fetch() called during static render"); },
    Worker: function () { throw new Error("new Worker() during static render"); },
    localStorage: { getItem: () => null, setItem: noop, removeItem: noop },
    document: {
      documentElement: stubEl(),
      body: stubEl(),
      createElement: stubEl,
      getElementById: () => null,
      querySelector: () => null,
      querySelectorAll: () => [],
      addEventListener: noop,
      removeEventListener: noop,
    },
  };
  sandbox.window = sandbox;
  sandbox.self = sandbox;
  sandbox.globalThis = sandbox;
  return vm.createContext(sandbox);
}

const sandbox = makeSandbox();

function runFile(file, label) {
  try {
    vm.runInContext(read(file), sandbox, { filename: label || file });
  } catch (e) {
    throw new Error(`while evaluating ${label || file}: ${e.message}`);
  }
}

log("loading React, ReactDOMServer and Babel…");
runFile(path.join(DOCS, "vendor", "react.production.min.js"));
runFile(path.join(SEO, "vendor", "react-dom-server-legacy.browser.production.min.js"));
runFile(path.join(DOCS, "vendor", "babel.min.js"));

const React = sandbox.React;
const ReactDOMServer = sandbox.ReactDOMServer;
const Babel = sandbox.Babel;
if (!React || !ReactDOMServer || !Babel) {
  throw new Error("vendored React / ReactDOMServer / Babel did not expose their globals");
}

/* ------------------------------------------------------------------ *
 * 2. Compile .jsx → build/*.js
 *
 * Load order matters and mirrors what index.html used to do by hand.
 * routes.js and the two data files are already plain JS and are copied
 * through untouched so there is exactly one source of truth for them.
 * ------------------------------------------------------------------ */
const PLAIN = ["routes.js", "cuecard-data.js", "keyboard-map.js"];
const JSX = [
  "components.jsx",
  "Calculator.jsx",
  "cuecard.jsx",
  "led-display.jsx",
  "PlayCalculator.jsx",
  "Pages.jsx",
  "site.jsx",
];

// The order the browser loads them in. Data before the components that
// read it; site.js last, because it mounts.
const SCRIPT_ORDER = [
  "routes.js",
  "cuecard-data.js",
  "keyboard-map.js",
  "components.js",
  "Calculator.js",
  "cuecard.js",
  "led-display.js",
  "PlayCalculator.js",
  "Pages.js",
  "site.js",
];

fs.rmSync(OUT_JS, { recursive: true, force: true });
fs.mkdirSync(OUT_JS, { recursive: true });

fs.writeFileSync(
  path.join(OUT_JS, "README.md"),
  "Generated by `node .seo/build.js`. Do not edit by hand — edit the .jsx\n" +
  "sources in docs/ and rebuild.\n"
);

const compiled = {};
for (const name of PLAIN) {
  const code = read(path.join(DOCS, name));
  compiled[name] = code;
  fs.writeFileSync(path.join(OUT_JS, name), code);
}
for (const name of JSX) {
  const out = name.replace(/\.jsx$/, ".js");
  const src = read(path.join(DOCS, name));
  let code;
  try {
    code = Babel.transform(src, {
      presets: ["react"],
      sourceType: "script",
      compact: false,
      comments: true,
    }).code;
  } catch (e) {
    throw new Error(`Babel failed on ${name}: ${e.message}`);
  }
  compiled[out] = code;
  fs.writeFileSync(path.join(OUT_JS, out), code);
  log(`compiled ${name} → build/${out}`);
}

/* ------------------------------------------------------------------ *
 * 3. Evaluate the compiled site so we can render it
 *
 * One concatenated script, for the top-level-`const`-sharing reason
 * above. site.js self-mounts only when document.getElementById("root")
 * returns something, and the stub returns null, so nothing happens here.
 * ------------------------------------------------------------------ */
log("evaluating the compiled site…");
const bundle = SCRIPT_ORDER.map((n) => "\n;/* === " + n + " === */\n" + compiled[n]).join("");
vm.runInContext(bundle, sandbox, { filename: "calcu59-bundle.js" });

const COMPONENTS = {
  home: "HomePage",
  about: "AboutTi59Page",
  start: "GettingStartedPage",
  play: "PlayPage",
  "install-mobile": "InstallMobilePage",
  "install-mac": "InstallMacPage",
  "state-files": "StateFilesPage",
  debugger: "DebuggerPage",
  ref: "ReferencePage",
  modules: "ModulesPage",
  examples: "ExamplesPage",
  faq: "FaqPage",
};

// The playable calculator is a WebAssembly worker; there is no honest
// static form of it. Stub it for the prerender so /play/ still ships a
// crawlable page of prose, and let the client render the real thing.
const RealPlayCalculator = sandbox.PlayCalculator;
sandbox.PlayCalculator = function StaticPlayCalculatorPlaceholder() {
  return React.createElement(
    "div",
    {
      className: "panel",
      style: { padding: 24, textAlign: "center", color: "var(--fg-3)", maxWidth: 420 },
    },
    "Loading the TI-59 emulator…"
  );
};

function renderRoute(route) {
  const name = COMPONENTS[route.page];
  const Page = sandbox[name];
  if (!Page) throw new Error(`no component for page "${route.page}" (expected ${name})`);
  const props = { onNav: () => {} };
  if (route.topic) props.initialTopic = route.topic;
  return ReactDOMServer.renderToStaticMarkup(
    React.createElement(
      React.Fragment,
      null,
      React.createElement(sandbox.SiteHeader, { page: route.page }),
      React.createElement(Page, props),
      React.createElement(sandbox.SiteFooter)
    )
  );
}

/* ------------------------------------------------------------------ *
 * 4. <head> and structured data
 * ------------------------------------------------------------------ */
const APP_STORE = "https://apps.apple.com/us/app/calc-u-59/id6761413142";
const REPO = "https://github.com/tinue/Calc-U-59";
const OG_IMAGE = ORIGIN + "/assets/app-icon.png";

const esc = (s) =>
  String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

function softwareApplicationLd() {
  return {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "Calc-U 59",
    alternateName: ["Calc-U-59", "TI-59 Emulator"],
    applicationCategory: "UtilitiesApplication",
    applicationSubCategory: "Calculator emulator",
    operatingSystem: "macOS, iOS, iPadOS",
    url: ORIGIN + "/",
    downloadUrl: APP_STORE,
    installUrl: APP_STORE,
    softwareHelp: ORIGIN + "/getting-started/",
    codeRepository: REPO,
    image: OG_IMAGE,
    description:
      "Emulator and debugger for the Texas Instruments TI-59, TI-58 and TI-58C programmable " +
      "calculators, running the original ROM on macOS, iOS and iPadOS.",
    featureList: [
      "TI-59, TI-58 and TI-58C models",
      "All 14 Solid State Software library modules",
      "Magnetic card read and write, synced over iCloud",
      "PC-100C thermal printer emulation",
      "CPU-level debugger with ROM instruction trace",
      "Plain-text .ti59 state files",
    ],
    offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    isAccessibleForFree: true,
  };
}

function faqLd() {
  // Mirrors what FaqPage renders. Kept as a build-time read of the same
  // source so the markup and the structured data cannot disagree.
  const src = read(path.join(DOCS, "Pages.jsx"));
  const block = src.slice(src.indexOf("function FaqPage"));
  const entries = [];
  const re = /question:\s*"((?:[^"\\]|\\.)*)"\s*,\s*answer:\s*"((?:[^"\\]|\\.)*)"/g;
  let m;
  while ((m = re.exec(block))) {
    const unescape = (s) => s.replace(/\\"/g, '"').replace(/\\'/g, "'").replace(/\\\\/g, "\\");
    entries.push({
      "@type": "Question",
      name: unescape(m[1]),
      acceptedAnswer: { "@type": "Answer", text: unescape(m[2]) },
    });
  }
  if (!entries.length) throw new Error("FAQ structured data: parsed 0 questions out of Pages.jsx");
  log(`FAQ structured data: ${entries.length} questions`);
  return { "@context": "https://schema.org", "@type": "FAQPage", mainEntity: entries };
}

function breadcrumbLd(route, meta) {
  const items = [{ "@type": "ListItem", position: 1, name: "Calc-U 59", item: ORIGIN + "/" }];
  const segs = route.path.split("/").filter(Boolean);
  let acc = "";
  segs.forEach((s, i) => {
    acc += "/" + s;
    items.push({
      "@type": "ListItem",
      position: i + 2,
      name: i === segs.length - 1 ? meta.heading : s.replace(/-/g, " "),
      item: ORIGIN + acc + "/",
    });
  });
  return { "@context": "https://schema.org", "@type": "BreadcrumbList", itemListElement: items };
}

// React and ReactDOM first: build/site.js calls ReactDOM.createRoot, and
// every component closes over React. Babel is deliberately absent — that is
// the whole point of precompiling to build/.
//
// All of them are `defer`, which both keeps them off the critical path and
// guarantees execution in document order, so the vendored globals exist
// before the first build/ script runs.
const VENDOR_SCRIPTS = [
  "/vendor/react.production.min.js",
  "/vendor/react-dom.production.min.js",
];

function scripts() {
  return VENDOR_SCRIPTS.concat(SCRIPT_ORDER.map((n) => "/build/" + n))
    .map((src) => `<script src="${src}" defer></script>`)
    .join("\n");
}

function renderPage(route) {
  const meta = PAGES[route.canonical || route.path] || PAGES[route.path] || FALLBACK;
  const canonical = ORIGIN + (route.canonical || route.path);
  const isHome = route.path === "/";

  const ld = [];
  if (isHome) ld.push(softwareApplicationLd());
  if (route.page === "faq" && !route.canonical) ld.push(faqLd());
  if (!isHome) ld.push(breadcrumbLd(route, meta));

  const body = renderRoute(route);

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(meta.title)}</title>
<meta name="description" content="${esc(meta.description)}">
<link rel="canonical" href="${esc(canonical)}">

<meta property="og:type" content="website">
<meta property="og:site_name" content="Calc-U 59">
<meta property="og:url" content="${esc(canonical)}">
<meta property="og:title" content="${esc(meta.title)}">
<meta property="og:description" content="${esc(meta.description)}">
<meta property="og:image" content="${esc(OG_IMAGE)}">
<meta property="og:image:alt" content="Calc-U 59 app icon">
<meta name="twitter:card" content="summary">
<meta name="twitter:title" content="${esc(meta.title)}">
<meta name="twitter:description" content="${esc(meta.description)}">
<meta name="twitter:image" content="${esc(OG_IMAGE)}">

<link rel="icon" type="image/png" href="/assets/app-icon.png">
<link rel="apple-touch-icon" href="/assets/app-icon.png">
<meta name="theme-color" content="#000000">
<meta name="apple-itunes-app" content="app-id=6761413142">
<link rel="stylesheet" href="/colors_and_type.css">
<link rel="stylesheet" href="/styles.css">
${ld.map((o) => `<script type="application/ld+json">\n${JSON.stringify(o, null, 2)}\n</script>`).join("\n")}
</head>
<body>
<div id="root">${body}</div>
${scripts()}
</body>
</html>
`;
}

/* ------------------------------------------------------------------ *
 * 5. Write it all out
 * ------------------------------------------------------------------ */
log("prerendering routes…");
const written = [];
for (const route of ROUTES) {
  const html = renderPage(route);
  const dir = route.path === "/" ? DOCS : path.join(DOCS, route.path.replace(/^\/|\/$/g, ""));
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, "index.html");
  fs.writeFileSync(file, html);
  written.push(route);
  log(`${route.path}  →  ${path.relative(DOCS, file)}${route.canonical ? "  (canonical: " + route.canonical + ")" : ""}`);
}

// sitemap: self-canonical pages only. Listing a page whose canonical
// points elsewhere is a contradiction search engines are entitled to
// distrust.
const indexable = ROUTES.filter((r) => !r.canonical);
const today = new Date().toISOString().slice(0, 10);
const sitemap =
  `<?xml version="1.0" encoding="UTF-8"?>\n` +
  `<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n` +
  indexable
    .map(
      (r) =>
        `  <url>\n    <loc>${ORIGIN}${r.path}</loc>\n` +
        `    <lastmod>${today}</lastmod>\n` +
        `    <priority>${r.path === "/" ? "1.0" : "0.8"}</priority>\n  </url>\n`
    )
    .join("") +
  `</urlset>\n`;
fs.writeFileSync(path.join(DOCS, "sitemap.xml"), sitemap);
log(`sitemap.xml  →  ${indexable.length} URLs`);

fs.writeFileSync(
  path.join(DOCS, "robots.txt"),
  `# https://www.calcu59.ch/\nUser-agent: *\nAllow: /\n\n` +
    `# The design preview and the installable PWA shell: no useful text to\n` +
    `# index, and /app/ would compete with /play/.\n` +
    `#\n` +
    `# /build/ and /vendor/ are deliberately NOT disallowed. They hold every\n` +
    `# script the pages load, and a crawler that cannot fetch them renders a\n` +
    `# page without its JavaScript — which reports as a blocked resource and\n` +
    `# leaves /play/'s calculator invisible.\n` +
    `Disallow: /app/\nDisallow: /preview/\n\n` +
    `Sitemap: ${ORIGIN}/sitemap.xml\n`
);
log("robots.txt");

// GitHub Pages serves 404.html for unknown paths. Give it the homepage
// chrome rather than the default Pages 404, and keep it out of the index.
const notFound = renderPage({ path: "/", page: "home" })
  .replace("<title>", '<meta name="robots" content="noindex">\n<title>')
  .replace(/<link rel="canonical"[^>]*>\n/, "");
fs.writeFileSync(path.join(DOCS, "404.html"), notFound);
log("404.html");

// Jekyll would otherwise refuse to publish .seo/ — harmless — but also
// anything else that starts with a dot or underscore. Be explicit.
fs.writeFileSync(path.join(DOCS, ".nojekyll"), "");

console.log(`\nBuilt ${written.length} pages, ${indexable.length} indexable.\n`);
