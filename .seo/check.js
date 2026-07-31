#!/usr/bin/env node
//
// Calc-U 59 — post-build check.
//
//   node .seo/check.js
//
// Verifies the things that silently rot: that every route produced a
// file, that each file carries the head tags search engines need, that
// the prerendered markup is real text rather than an empty root, that
// internal links all resolve to a built page, and that the compiled
// bundle actually boots and renders the same page in a DOM.
//
// The last check needs jsdom, which is not vendored. Without it the
// static checks still run and the boot check reports as skipped:
//
//   npm install --no-save jsdom && node .seo/check.js

const fs = require("fs");
const path = require("path");

const SEO = __dirname;
const DOCS = path.join(SEO, "..");
const { ROUTES, ORIGIN, normalizePath } = require(path.join(DOCS, "routes.js"));

let failures = 0;
let checks = 0;
function ok(cond, msg) {
  checks++;
  if (!cond) { failures++; console.log("  FAIL  " + msg); }
}
function section(name) { console.log("\n" + name); }

const fileFor = (p) =>
  p === "/" ? path.join(DOCS, "index.html") : path.join(DOCS, p.replace(/^\/|\/$/g, ""), "index.html");

/* ---- per-page head + body ---------------------------------------- */
section("pages");
const built = new Map();
for (const route of ROUTES) {
  const file = fileFor(route.path);
  if (!fs.existsSync(file)) { ok(false, `${route.path}: not built`); continue; }
  const html = fs.readFileSync(file, "utf8");
  built.set(normalizePath(route.path), html);

  const title = (html.match(/<title>([^<]*)<\/title>/) || [])[1] || "";
  const desc = (html.match(/<meta name="description" content="([^"]*)"/) || [])[1] || "";
  const canon = (html.match(/<link rel="canonical" href="([^"]*)"/) || [])[1] || "";
  const root = html.slice(html.indexOf('<div id="root">'));
  const text = root.replace(/<script[\s\S]*?<\/script>/g, "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();

  ok(title.length > 15 && title.length <= 75, `${route.path}: title length ${title.length} — "${title}"`);
  ok(desc.length >= 110 && desc.length <= 175, `${route.path}: description length ${desc.length}`);
  ok(canon === ORIGIN + (route.canonical || route.path), `${route.path}: canonical is "${canon}"`);
  ok(/<h1[^>]*>/.test(root), `${route.path}: no <h1> in prerendered markup`);
  ok(text.length > 700, `${route.path}: only ${text.length} chars of prerendered text`);
  ok(/og:title/.test(html) && /og:description/.test(html), `${route.path}: missing Open Graph tags`);
  ok(html.includes("/build/site.js"), `${route.path}: does not load the app bundle`);

  // Every script the page names must exist, and React has to be among them:
  // without it site.js throws on ReactDOM.createRoot and the page is frozen
  // at its prerendered markup. That is invisible on a prose page and only
  // shows up on /play/, where the markup is a placeholder.
  const srcs = [...html.matchAll(/<script[^>]+src="([^"]+)"/g)].map((m) => m[1]);
  for (const src of srcs) {
    ok(fs.existsSync(path.join(DOCS, src.replace(/^\//, ""))), `${route.path}: script ${src} missing`);
  }
  ok(srcs.some((s) => /react\./.test(s)), `${route.path}: does not load React`);
  ok(srcs.some((s) => /react-dom\./.test(s)), `${route.path}: does not load ReactDOM`);
  ok(srcs.findIndex((s) => /react-dom\./.test(s)) < srcs.indexOf("/build/site.js"),
     `${route.path}: ReactDOM is not loaded before site.js`);
}

// Exactly one title per indexable page, or they compete with each other.
section("uniqueness");
const titles = new Map();
for (const route of ROUTES.filter((r) => !r.canonical)) {
  const html = built.get(normalizePath(route.path));
  if (!html) continue;
  const t = (html.match(/<title>([^<]*)<\/title>/) || [])[1];
  ok(!titles.has(t), `duplicate <title> on ${route.path} and ${titles.get(t)}: "${t}"`);
  titles.set(t, route.path);
}

/* ---- internal links resolve -------------------------------------- */
section("internal links");
for (const [p, html] of built) {
  const hrefs = [...html.matchAll(/href="(\/[^"]*)"/g)].map((m) => m[1]);
  for (const href of new Set(hrefs)) {
    if (/\.(css|png|js|xml|txt|json|woff2?)$/.test(href)) {
      ok(fs.existsSync(path.join(DOCS, href.replace(/^\//, ""))), `${p}: asset ${href} missing`);
    } else {
      ok(built.has(normalizePath(href)), `${p}: link ${href} has no built page`);
    }
  }
  ok(!/href="#(?!\s)/.test(html.slice(html.indexOf('<div id="root">'))), `${p}: still contains a legacy #hash link`);
}

/* ---- crawl files -------------------------------------------------- */
section("crawl files");
const sitemap = fs.readFileSync(path.join(DOCS, "sitemap.xml"), "utf8");
const robots = fs.readFileSync(path.join(DOCS, "robots.txt"), "utf8");
for (const route of ROUTES) {
  const listed = sitemap.includes(`<loc>${ORIGIN}${route.path}</loc>`);
  ok(listed === !route.canonical, `sitemap: ${route.path} should ${route.canonical ? "not " : ""}be listed`);
}
ok(robots.includes(`Sitemap: ${ORIGIN}/sitemap.xml`), "robots.txt: no Sitemap line");
ok(fs.existsSync(path.join(DOCS, "404.html")), "404.html missing");
ok(fs.existsSync(path.join(DOCS, ".nojekyll")), ".nojekyll missing");
ok(/noindex/.test(fs.readFileSync(path.join(DOCS, "404.html"), "utf8")), "404.html is not noindex");

/* ---- the bundle actually boots ------------------------------------ */
async function bootChecks() {
section("client boot");
let JSDOM;
try { ({ JSDOM } = require("jsdom")); } catch (_) {}
if (!JSDOM) {
  console.log("  SKIP  jsdom not installed — run: npm install --no-save jsdom");
} else {
  // The scripts are read out of each page's own <script src> tags rather
  // than from a list here. A hardcoded list proves the bundle works; it
  // cannot prove the page actually loads it, and a page that omitted React
  // would still pass while rendering nothing in a real browser.

  // jsdom returns null from getContext("2d") unless the optional native
  // `canvas` package is installed. led-display.jsx draws the LED digits
  // there, so /play/ gets a no-op 2D context: enough to prove the page
  // mounts and the component tree renders, not enough to check pixels.
  const stub2d = () => {
    const noop = () => {};
    return {
      save: noop, restore: noop, beginPath: noop, arc: noop, fill: noop,
      clearRect: noop, setTransform: noop, transform: noop, translate: noop,
      fillStyle: "", filter: "",
    };
  };

  const pages = ["/", "/play/", "/faq/", "/what-is-a-ti-59/", "/modules/", "/getting-started/debugger/"];
  for (const p of pages) {
    const html = built.get(normalizePath(p));
    const errors = [];
    const dom = new JSDOM(html, {
      url: ORIGIN + p,
      runScripts: "outside-only",
      pretendToBeVisual: true,
    });
    const w = dom.window;
    w.addEventListener("error", (e) => errors.push(String(e.error || e.message)));
    // The prerendered markup is what a crawler sees; wipe it first so the
    // check proves the client rendered it, not that it was already there.
    w.document.getElementById("root").innerHTML = "";
    w.Worker = function () { this.postMessage = () => {}; this.terminate = () => {}; };
    if (!w.HTMLCanvasElement.prototype.getContext.__stubbed) {
      w.HTMLCanvasElement.prototype.getContext = Object.assign(stub2d, { __stubbed: true });
    }
    w.fetch = () => Promise.resolve({ json: () => Promise.resolve([]), text: () => Promise.resolve("") });
    const srcs = [...html.matchAll(/<script[^>]+src="([^"]+)"/g)].map((m) => m[1]);
    try {
      for (const src of srcs) {
        w.eval(fs.readFileSync(path.join(DOCS, src.replace(/^\//, "")), "utf8"));
      }
    } catch (e) {
      ok(false, `${p}: bundle threw — ${e.message}`);
      continue;
    }
    // createRoot renders concurrently; let its scheduler drain.
    for (let i = 0; i < 20; i++) await new Promise((r) => setTimeout(r, 5));

    const rendered = w.document.getElementById("root").textContent.replace(/\s+/g, " ").trim();
    ok(rendered.length > 400, `${p}: client render produced ${rendered.length} chars`);
    ok(/Calc-U/.test(rendered), `${p}: client render is missing the header`);
    ok(errors.length === 0, `${p}: runtime errors — ${errors.join("; ")}`);
    dom.window.close();
  }
}
}

bootChecks().then(() => {
  console.log(`\n${checks - failures}/${checks} checks passed.\n`);
  process.exit(failures ? 1 : 0);
});
