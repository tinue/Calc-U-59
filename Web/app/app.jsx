// Standalone Calc-U 59 app — mounts PlayCalculator (../calc.js) in the
// portrait layout, sized to the viewport (minus the safe-area padding), as
// the iPhone app: calculator and printer pages, the control bar, Settings.

const { useState: useAppState, useEffect: useAppEffect, useRef: useAppRef } = React;

// The page's height. Installed on iOS with the black-translucent status bar,
// WebKit reports the viewport without the status bar (an iPhone 18 Pro Max:
// 894 of 956 points) although the page fills the screen and the safe-area
// insets cover the status bar too; full width in standalone means the whole
// screen, so its height is the screen's. Only iOS: `navigator.standalone` is
// Apple's, and elsewhere (Android) `screen` includes the system bars the page
// doesn't cover, while the viewport is right.
function pageHeight() {
  const vv = window.visualViewport;
  const h = vv ? vv.height : window.innerHeight;
  if (window.navigator.standalone !== true) return h;
  const portrait = window.innerWidth <= window.innerHeight;
  const [short, long] = [Math.min(screen.width, screen.height), Math.max(screen.width, screen.height)];
  const [sw, sh] = portrait ? [short, long] : [long, short];
  return window.innerWidth === sw ? Math.max(h, sh) : h;
}

function viewportSize() {
  const vv = window.visualViewport;
  const root = document.getElementById("root");
  const cs = getComputedStyle(root);
  const padX = parseFloat(cs.paddingLeft) + parseFloat(cs.paddingRight);
  const padY = parseFloat(cs.paddingTop) + parseFloat(cs.paddingBottom);
  const page = pageHeight();
  const w = (vv ? vv.width : window.innerWidth) - padX;
  // The whole screen of the device it was installed on.
  return { width: Math.floor(w), height: Math.floor(page - padY), page };
}

// Install affordance. Android/Chrome/Edge fire `beforeinstallprompt`, which
// lets a real button trigger the browser's own install dialog — genuine
// one-tap install. iOS Safari has no equivalent: Apple has never shipped a
// way to trigger "Add to Home Screen" programmatically, so the best this can
// do there is detect iOS and point at the manual gesture. Both branches stay
// silent once the app is already running standalone (nothing left to
// install) and silent everywhere neither applies (desktop Firefox, Safari on
// a Mac, ...) rather than show a button that would do nothing.
//
// iPadOS 13+ Safari reports a desktop-Mac user agent by default, so a plain
// UA sniff misses every iPad; a real Mac never reports touch points, an iPad
// does, and that's what tells the two apart.
function useInstallPrompt() {
  const [mode, setMode] = useAppState("none");
  const deferredRef = useAppRef(null);

  useAppEffect(() => {
    const standalone =
      window.matchMedia("(display-mode: standalone)").matches ||
      window.navigator.standalone === true;
    if (standalone) return;

    const isIOS =
      (/iPad|iPhone|iPod/.test(navigator.userAgent) ||
        (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)) &&
      !window.MSStream;
    if (isIOS) { setMode("ios"); return; }

    function onPrompt(e) {
      e.preventDefault();
      deferredRef.current = e;
      setMode("installable");
    }
    function onInstalled() { setMode("none"); }
    window.addEventListener("beforeinstallprompt", onPrompt);
    window.addEventListener("appinstalled", onInstalled);
    return () => {
      window.removeEventListener("beforeinstallprompt", onPrompt);
      window.removeEventListener("appinstalled", onInstalled);
    };
  }, []);

  async function install() {
    const evt = deferredRef.current;
    if (!evt) return;
    evt.prompt();
    await evt.userChoice;
    deferredRef.current = null;
    setMode("none");
  }

  return [mode, install];
}

// iOS's Share symbol, for the Add to Home Screen hint.
function SymbolShare({ size, color }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3.5" y="4" width="17" height="16" rx="3" />
      <path d="M12 14 V 7 M9 10 L 12 7 L 15 10" />
    </svg>
  );
}

function InstallBanner({ mode, onInstall, onDismiss }) {
  if (mode === "none") return null;
  return (
    <div className="install-banner">
      {mode === "ios" && <SymbolShare size={16} color="#0a84ff" />}
      <span className="install-banner-text">
        {mode === "installable"
          ? "Install Calc-U 59 for one-tap, full-screen launches."
          : "Add to Home Screen: tap Share, then “Add to Home Screen”."}
      </span>
      {mode === "installable" && (
        <button type="button" className="install-banner-cta" onClick={onInstall}>Install</button>
      )}
      <button type="button" className="install-banner-close" aria-label="Dismiss" onClick={onDismiss}>×</button>
    </div>
  );
}

function StandaloneApp() {
  const [size, setSize] = useAppState(viewportSize);
  const [installMode, install] = useInstallPrompt();
  const [dismissed, setDismissed] = useAppState(false);

  useAppEffect(() => {
    function onResize() { setSize(viewportSize()); }
    window.addEventListener("resize", onResize);
    window.addEventListener("orientationchange", onResize);
    return () => {
      window.removeEventListener("resize", onResize);
      window.removeEventListener("orientationchange", onResize);
    };
  }, []);

  // app.css sizes html, body and #root by this rather than by 100%/100dvh,
  // which are the short viewport.
  useAppEffect(() => {
    document.documentElement.style.setProperty("--app-height", `${size.page}px`);
  }, [size.page]);

  return (
    <>
      <PlayCalculator layout="portrait" width={size.width} height={size.height} keyboard={true} />
      {!dismissed && (
        <InstallBanner mode={installMode} onInstall={install} onDismiss={() => setDismissed(true)} />
      )}
    </>
  );
}

// Next to this script, so the app works wherever it is hosted; its scope is
// this directory.
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register(new URL("sw.js", document.currentScript.src));
}

ReactDOM.createRoot(document.getElementById("root")).render(<StandaloneApp />);
