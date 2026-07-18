// Standalone Calc-U 59 app — mounts PlayCalculator with controls={false}
// (calculator face only: no module switcher, preset picker, Queue Card, or
// file upload) and a scale computed from the viewport instead of the fixed
// scale docs/#play uses inside its article column.

const { useState: useAppState, useEffect: useAppEffect } = React;

function computeScale() {
  const width = window.visualViewport ? window.visualViewport.width : window.innerWidth;
  const safeWidth = width - 32; // leaves room for #root's padding
  return Math.max(0.8, Math.min(1.6, safeWidth / 360));
}

function StandaloneApp() {
  const [scale, setScale] = useAppState(computeScale());

  useAppEffect(() => {
    function onResize() { setScale(computeScale()); }
    window.addEventListener("resize", onResize);
    window.addEventListener("orientationchange", onResize);
    return () => {
      window.removeEventListener("resize", onResize);
      window.removeEventListener("orientationchange", onResize);
    };
  }, []);

  return <PlayCalculator scale={scale} controls={false} />;
}

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/app/sw.js");
}

ReactDOM.createRoot(document.getElementById("root")).render(<StandaloneApp />);
