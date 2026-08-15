// Calc-U 59 — single source of truth for the site's URL map.
//
// Loaded twice, deliberately:
//   • in the browser, by site.jsx, to turn a pathname into a page id
//   • in Node, by .seo/build.js, to prerender one static HTML file per
//     route and to emit sitemap.xml
//
// Every indexable page needs a real path here. Hash URLs (#faq) are the
// old scheme and survive only as redirects — see LEGACY_HASHES.
(function (factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  if (typeof window !== "undefined") Object.assign(window, api);
})(function () {
  // canonical: omit for self-canonical (indexable). Set it when the route
  // is a real URL a visitor can reach but a near-duplicate of another page,
  // so search engines consolidate onto the primary.
  var ROUTES = [
    { path: "/",                                     page: "home" },
    { path: "/what-is-a-ti-59/",                     page: "about" },
    { path: "/play/",                                page: "play" },
    { path: "/getting-started/",                     page: "start", topic: "overview" },
    { path: "/install/iphone-ipad/",                 page: "install-mobile" },
    { path: "/install/mac/",                         page: "install-mac" },
    { path: "/presets/",                             page: "presets" },
    { path: "/presets/tutorial/",                    page: "preset-tutorial" },
    { path: "/debugger/",                            page: "debugger" },
    { path: "/reference/",                           page: "ref" },
    { path: "/modules/",                             page: "modules" },
    { path: "/software/",                            page: "software" },
    { path: "/faq/",                                 page: "faq" },

    // "State files" was the old name for what the app UI (and now the
    // site) calls a "preset". Both real URLs below still resolve — old
    // links and bookmarks keep working — but their canonical points at
    // the current name so search engines consolidate onto it.
    { path: "/state-files/",                         page: "presets", canonical: "/presets/" },

    // Sidebar deep links inside Getting Started. Most restate a standalone
    // page, so they point their canonical at it; "printer" is the one topic
    // with no standalone equivalent, so it stands on its own.
    //
    // A canonical here must name a page that says the same thing. That is
    // why /getting-started/ itself renders the "overview" topic and not one
    // of these: were it to render a topic, the two URLs would be identical
    // markup claiming different canonicals.
    //
    // No /getting-started/faq/ entry: the FAQ sidebar item is a real link to
    // /faq/ (see Pages.jsx's STARTED_SECTIONS), not an in-page topic, so
    // there is exactly one URL and one copy of the FAQ content.
    { path: "/getting-started/install-iphone-ipad/", page: "start", topic: "install-mobile", canonical: "/install/iphone-ipad/" },
    { path: "/getting-started/install-mac/",         page: "start", topic: "install-mac",    canonical: "/install/mac/" },
    { path: "/getting-started/presets/",             page: "start", topic: "presets",        canonical: "/presets/" },
    { path: "/getting-started/debugger/",            page: "start", topic: "debugger",       canonical: "/debugger/" },
    { path: "/getting-started/printer/",             page: "start", topic: "printer" },

    // Old sidebar deep link, kept reachable — see the /state-files/ note above.
    { path: "/getting-started/state-files/",         page: "start", topic: "presets",        canonical: "/presets/" }
  ];

  // Old #hash URLs → new paths. Anything already shared or linked keeps
  // working; site.jsx rewrites them with location.replace on first paint.
  var LEGACY_HASHES = {
    "":                       "/",
    "home":                   "/",
    "play":                   "/play/",
    "start":                  "/getting-started/",
    "start/install-mobile":   "/getting-started/install-iphone-ipad/",
    "start/install-mac":      "/getting-started/install-mac/",
    "start/state-files":      "/getting-started/state-files/",
    "start/debugger":         "/getting-started/debugger/",
    "start/printer":          "/getting-started/printer/",
    "start/faq":              "/faq/",
    // The README is no longer a page here, only a link out to GitHub.
    "start/readme":           "/getting-started/",
    "install-mobile":         "/install/iphone-ipad/",
    "install-mac":            "/install/mac/",
    "state-files":            "/state-files/",
    "debugger":               "/debugger/",
    "ref":                    "/reference/",
    "modules":                "/modules/",
    "faq":                    "/faq/"
  };

  // Trailing slash is canonical; "/faq" and "/faq/" resolve identically.
  function normalizePath(pathname) {
    var p = (pathname || "/").split("?")[0].split("#")[0];
    if (p.charAt(0) !== "/") p = "/" + p;
    if (p.slice(-1) !== "/") p += "/";
    return p;
  }

  function matchRoute(pathname) {
    var p = normalizePath(pathname);
    for (var i = 0; i < ROUTES.length; i++) {
      if (ROUTES[i].path === p) return ROUTES[i];
    }
    return null;
  }

  return {
    ROUTES: ROUTES,
    LEGACY_HASHES: LEGACY_HASHES,
    normalizePath: normalizePath,
    matchRoute: matchRoute,
    ORIGIN: "https://www.calcu59.ch"
  };
});
