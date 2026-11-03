// Service worker for the standalone Calc-U 59 app (scope: this directory).
// Precaches the app shell plus everything the calculator needs to run all
// three models offline — the WASM engine, every model's ROM and constants,
// the artwork, every Solid State module, the presets, the fonts and scripts —
// so the installed app opens and runs fully offline after the first launch.
//
// Every path is relative to this script, so the app works wherever the
// client is hosted. Web/build.js checks that each one exists in dist/ and
// stamps CACHE_NAME with a hash of their contents; the activate handler
// drops this app's older caches. The scope is part of the name: the origin
// may be shared with the host site, or with another copy of the client.
const CACHE_PREFIX = `calcu59-app ${self.registration.scope} `;
const CACHE_NAME = CACHE_PREFIX + "__CACHE_VERSION__";

const CORE_ASSETS = [
  "./",
  "index.html",
  "app.css",
  "app.js",
  "manifest.json",
  "icon.png",

  "../vendor/react.production.min.js",
  "../vendor/react-dom.production.min.js",

  "../calc.js",
  "../calc.css",
  "../calc-engine-worker.js",

  "../fonts/archivo-400.woff2",
  "../fonts/archivo-700.woff2",

  "../img/ti59_base.png",
  "../img/ti58_base.png",
  "../img/CueCard.png",
  "../img/MagnetCard.png",
  "../img/SolidStateCard.png",

  "../presets/manifest.json",

  "../wasm/ti59-core.js",
  "../wasm/ti59-core.wasm",
  // Every file in wasm/roms/ and every preset; Web/build.js fills them in.
  /*__GENERATED_ASSETS__*/
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(CORE_ASSETS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)
          .map((key) => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

// Cache-first: the calculator's own files are versioned by CACHE_NAME
// above, not by URL, so serving stale-then-network-updating isn't worth the
// complexity here. Falls back to network for anything not precached.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;

  event.respondWith(caches.match(event.request).then((cached) => cached || fetch(event.request)));
});
