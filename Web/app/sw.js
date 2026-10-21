// Service worker for the standalone Calc-U 59 app (scope: this directory).
// Precaches the app shell plus the calculator's fixed dependencies — the
// WASM engine, the TI-59 ROM files and module 01 (Master Library, the only
// module the app uses — there's no module switcher), and the fonts and
// scripts the calculator face renders with — so the installed app opens and
// runs fully offline after the first launch.
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
  "../fonts/barlow-condensed-600.woff2",
  "../fonts/barlow-condensed-700.woff2",

  "../wasm/ti59-core.js",
  "../wasm/ti59-core.wasm",
  // Module.requiredRomFiles() in Web/bindings.cpp
  "../wasm/roms/TMC0582.txt",
  "../wasm/roms/TMC0583.txt",
  "../wasm/roms/TMC0571B.txt",
  "../wasm/roms/TMC0582-CONST-K.txt",
  "../wasm/roms/TMC0583-CONST-K.txt",
  "../wasm/roms/cuecards.txt",
  "../wasm/roms/TMC0541.txt",
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
// complexity here. Falls back to network for anything not precached, and
// quietly caches same-origin GETs it fetches along the way.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;

  event.respondWith(
    caches.match(event.request).then((cached) => {
      if (cached) return cached;
      return fetch(event.request).then((response) => {
        if (response.ok && new URL(event.request.url).origin === self.location.origin) {
          const copy = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
        }
        return response;
      });
    })
  );
});
