// Standalone Calc-U 59 app — mounts PlayCalculator with controls={false}
// (calculator face only: no module switcher, preset picker, Queue Card, or
// file upload) and a scale computed from the viewport instead of the fixed
// scale docs/#play uses inside its article column.

const { useState: useAppState, useEffect: useAppEffect, useRef: useAppRef } = React;

function computeScale() {
  const width = window.visualViewport ? window.visualViewport.width : window.innerWidth;
  const safeWidth = width - 32; // leaves room for #root's padding
  return Math.max(0.8, Math.min(1.6, safeWidth / 360));
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

// SymbolShare comes from Calculator.jsx, loaded before this script in
// app/index.html.
function InstallBanner({ mode, onInstall, onDismiss }) {
  if (mode === "none") return null;
  return (
    <div className="install-banner">
      {mode === "ios" && <SymbolShare size={16} color="var(--accent)" />}
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
  const [scale, setScale] = useAppState(computeScale());
  const [installMode, install] = useInstallPrompt();
  const [dismissed, setDismissed] = useAppState(false);

  useAppEffect(() => {
    function onResize() { setScale(computeScale()); }
    window.addEventListener("resize", onResize);
    window.addEventListener("orientationchange", onResize);
    return () => {
      window.removeEventListener("resize", onResize);
      window.removeEventListener("orientationchange", onResize);
    };
  }, []);

  return (
    <>
      <PlayCalculator scale={scale} controls={false} />
      {!dismissed && (
        <InstallBanner mode={installMode} onInstall={install} onDismiss={() => setDismissed(true)} />
      )}
    </>
  );
}

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/app/sw.js");
}

ReactDOM.createRoot(document.getElementById("root")).render(<StandaloneApp />);
