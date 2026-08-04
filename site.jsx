// Calc-U 59 — client-side router.
//
// Lifted out of index.html so the same code can be precompiled once and
// shared by every prerendered page. Each route in routes.js is a real
// static HTML file on disk (built by .seo/build.js), so a crawler or a
// cold visitor gets complete markup with no JavaScript; this file takes
// over afterwards and makes subsequent navigation instant.

function pathForTarget(target) {
  var page = typeof target === "string" ? target : target.page;
  var topic = typeof target === "string" ? null : target.topic;

  if (topic) {
    for (var i = 0; i < ROUTES.length; i++) {
      if (ROUTES[i].page === page && ROUTES[i].topic === topic) return ROUTES[i].path;
    }
  }
  for (var j = 0; j < ROUTES.length; j++) {
    if (ROUTES[j].page === page && !ROUTES[j].canonical) return ROUTES[j].path;
  }
  return "/";
}

// Old #hash links (shared bookmarks, forum posts, the previous sitemap)
// land on "/" and are rewritten in place before React ever renders, so
// they never register as a separate URL.
function redirectLegacyHash() {
  var raw = (window.location.hash || "").replace(/^#/, "");
  if (!raw) return false;
  var target = LEGACY_HASHES[raw];
  if (!target) return false;
  window.location.replace(target);
  return true;
}

function useRouter() {
  var initial = matchRoute(window.location.pathname) || matchRoute("/");
  var state = React.useState(initial);
  var route = state[0];
  var setRoute = state[1];

  React.useEffect(function () {
    function onPop() {
      var next = matchRoute(window.location.pathname) || matchRoute("/");
      setRoute(next);
    }
    window.addEventListener("popstate", onPop);
    return function () { window.removeEventListener("popstate", onPop); };
  }, []);

  // Stable identity: onNav is handed to every page and to the delegated
  // click listener below, and a fresh function each render would tear
  // down and re-add that listener on every state change.
  var onNav = React.useCallback(function (target) {
    var path = typeof target === "string" && target.charAt(0) === "/"
      ? normalizePath(target)
      : pathForTarget(target);
    if (normalizePath(window.location.pathname) === path) return;
    var next = matchRoute(path);
    if (!next) { window.location.href = path; return; }
    window.history.pushState({}, "", path);
    setRoute(next);
    window.scrollTo(0, 0);
  }, []);

  return { route: route, onNav: onNav };
}

// One delegated listener instead of an onClick on every link: the nav,
// the sidebar and the topic cards all emit ordinary <a href="/faq/">, so
// they stay real, crawlable, middle-clickable links and still navigate
// without a reload.
function useLinkInterception(onNav) {
  React.useEffect(function () {
    function onClick(e) {
      if (e.defaultPrevented || e.button !== 0) return;
      if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
      var a = e.target.closest ? e.target.closest("a") : null;
      if (!a) return;
      if (a.target && a.target !== "_self") return;
      if (a.hasAttribute("download")) return;
      var href = a.getAttribute("href");
      if (!href || href.charAt(0) !== "/") return;
      if (!matchRoute(href)) return;
      e.preventDefault();
      onNav(href);
    }
    document.addEventListener("click", onClick);
    return function () { document.removeEventListener("click", onClick); };
  }, [onNav]);
}

function App() {
  var router = useRouter();
  var route = router.route;
  var onNav = router.onNav;
  useLinkInterception(onNav);

  var page = route.page;
  return (
    <>
      <SiteHeader page={page} />
      {page === "home"           && <HomePage onNav={onNav} />}
      {page === "about"          && <AboutTi59Page onNav={onNav} />}
      {page === "start"          && <GettingStartedPage key={route.topic} initialTopic={route.topic} onNav={onNav} />}
      {page === "play"           && <PlayPage onNav={onNav} />}
      {page === "install-mobile" && <InstallMobilePage onNav={onNav} />}
      {page === "install-mac"    && <InstallMacPage onNav={onNav} />}
      {page === "state-files"    && <StateFilesPage onNav={onNav} />}
      {page === "debugger"       && <DebuggerPage onNav={onNav} />}
      {page === "ref"            && <ReferencePage onNav={onNav} />}
      {page === "modules"        && <ModulesPage onNav={onNav} />}
      {page === "software"       && <SoftwarePage onNav={onNav} />}
      {page === "faq"            && <FaqPage onNav={onNav} />}
      <SiteFooter />
    </>
  );
}

if (typeof window !== "undefined" && document.getElementById("root")) {
  if (!redirectLegacyHash()) {
    ReactDOM.createRoot(document.getElementById("root")).render(<App />);
  }
}

Object.assign(window, { App, pathForTarget });
