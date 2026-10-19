// Calc-U 59 — the calculator's key bank and key chrome, after the iOS app.
// PlayCalculator.jsx builds the playable calculator from CALC_ROWS and
// <CalcKey>.

const { useState: useStateCalc } = React;

// ---- Key bank (module scope: shared with PlayCalculator.jsx) ----
// tone: cream | dark | yellow
// top labels: their color hints (silk-cream / silk-yellow / silk-mahogany)
// label casing matches real hardware exactly ("2nd", not "2ND"; lnx/x⇄t/x²/
// √x/1/x/yˣ lowercase) — see CalcKey, which no longer force-uppercases.
// Row/col positions here are the grid coordinates PlayCalculator.jsx sends the
// worker (Shared/KeyMatrix.hpp's matrixCode(row, col)).
const CALC_D = "dark", CALC_C = "cream", CALC_Y = "yellow";
const CALC_ROWS = [
  [
    {top:"A'",label:"A",tone:CALC_D}, {top:"B'",label:"B",tone:CALC_D},
    {top:"C'",label:"C",tone:CALC_D}, {top:"D'",label:"D",tone:CALC_D}, {top:"E'",label:"E",tone:CALC_D}
  ],
  [
    {top:"",label:"2nd",tone:CALC_Y}, {top:"",label:"INV",tone:CALC_D},
    {top:"log",label:"lnx",tone:CALC_D}, {top:"CP",label:"CE",tone:CALC_D}, {top:"",label:"CLR",tone:CALC_Y}
  ],
  [
    {top:"Pgm",label:"LRN",tone:CALC_D}, {top:"P→R",label:"x⇄t",tone:CALC_D},
    {top:"sin",label:"x²",tone:CALC_D}, {top:"cos",label:"√x",tone:CALC_D}, {top:"tan",label:"1/x",tone:CALC_D}
  ],
  [
    {top:"Ins",label:"SST",tone:CALC_D}, {top:"CMs",label:"STO",tone:CALC_D},
    {top:"Exc",label:"RCL",tone:CALC_D}, {top:"Prd",label:"SUM",tone:CALC_D}, {top:"Ind",label:"yˣ",tone:CALC_D}
  ],
  [
    {top:"Del",label:"BST",tone:CALC_D}, {top:"Eng",label:"EE",tone:CALC_D},
    {top:"Fix",label:"(",tone:CALC_D}, {top:"Int",label:")",tone:CALC_D}, {top:"|x|",label:"÷",tone:CALC_Y}
  ],
  [
    {top:"Pause",label:"GTO",tone:CALC_D}, {top:"x=t",label:"7",tone:CALC_C},
    {top:"Nop",label:"8",tone:CALC_C}, {top:"Op",label:"9",tone:CALC_C}, {top:"Deg",label:"×",tone:CALC_Y}
  ],
  [
    {top:"Lbl",label:"SBR",tone:CALC_D}, {top:"x≥t",label:"4",tone:CALC_C},
    {top:"Σ+",label:"5",tone:CALC_C}, {top:"x̄",label:"6",tone:CALC_C}, {top:"Rad",label:"−",tone:CALC_Y}
  ],
  [
    {top:"St flg",label:"RST",tone:CALC_D}, {top:"If flg",label:"1",tone:CALC_C},
    {top:"D.MS",label:"2",tone:CALC_C}, {top:"π",label:"3",tone:CALC_C}, {top:"Grad",label:"+",tone:CALC_Y}
  ],
  [
    {top:"Write",label:"R/S",tone:CALC_D}, {top:"Dsz",label:"0",tone:CALC_C},
    {top:"Adv",label:".",tone:CALC_C}, {top:"Prt",label:"+/-",tone:CALC_C}, {top:"List",label:"=",tone:CALC_Y}
  ],
];

/* ============================================================
   Single key (top label + button)
   ============================================================ */
// forcePressed lets an outside caller light a key that no pointer is touching —
// PlayCalculator.jsx uses it so a physical-keyboard press looks exactly like a
// clicked one. onDown/onUp drive the emulator's press/release from the actual
// pointer down/up.
function CalcKey({ kc, scale, onDown, onUp, forcePressed = false }) {
  const [pointerPressed, setPointerPressed] = useStateCalc(false);
  const pressed = pointerPressed || forcePressed;

  const styleByTone = {
    cream: {
      background: pressed
        ? "linear-gradient(180deg,#d8c8a8,#c0b08c)"
        : "linear-gradient(180deg,#efe4cc 0%,#d8c8a8 100%)",
      color: "#1a130d",
      shadow: pressed
        ? "inset 0 2px 4px rgba(0,0,0,.45)"
        : "0 1px 0 #6a5a3c, 0 2px 3px rgba(0,0,0,.5), inset 0 1px 0 rgba(255,255,255,.4)",
    },
    dark: {
      background: pressed
        ? "linear-gradient(180deg,#1a1208,#100a04)"
        : "linear-gradient(180deg,#2a1f15 0%,#1f1610 100%)",
      color: "#efe4cc",
      shadow: pressed
        ? "inset 0 2px 4px rgba(0,0,0,.6)"
        : "0 1px 0 #000, 0 2px 4px rgba(0,0,0,.5), inset 0 1px 0 rgba(255,200,100,.05)",
    },
    yellow: {
      background: pressed
        ? "linear-gradient(180deg,#d8a830,#b88a20)"
        : "linear-gradient(180deg,#f0c040 0%,#d8a830 100%)",
      color: "#2a1f10",
      shadow: pressed
        ? "inset 0 2px 4px rgba(0,0,0,.5)"
        : "0 1px 0 #5a3c10, 0 2px 3px rgba(0,0,0,.5), inset 0 1px 0 rgba(255,255,255,.25)",
    },
  }[kc.tone];

  const topColor = kc.tone === "yellow" ? "#e8b840" : "#d4c4a0";

  // Cream ("white") number keys stay wider than the dark/yellow function
  // keys, matching real hardware's relative proportions — but the ratios
  // are no longer tied to real hardware's exact numbers (6:3 / 4.5:3):
  // at this larger overall scale, those ratios left too much visible gap
  // between keys, so both are widened further to fill more of their grid
  // column while still leaving a visible gap. Purely horizontal — height
  // is unaffected.
  const keyHeight = 20 * scale;
  const keyRadius = 3 * scale;
  const keyWidth = keyHeight * (kc.tone === "cream" ? 2.6 : 2.1);

  return (
    <div style={{ display:"flex", flexDirection:"column", alignItems:"center", gap: 2*scale }}>
      {/* Upright, same family as the keycap below \u2014 real hardware's 2nd-function
          legends (log, sin, P\u2192R, x=t, \u2026) are plain, not italicized; confirmed
          against App/Assets.xcassets/ti59_base.imageset/ti59_base.png. */}
      <span style={{
        fontFamily: "var(--font-keycap)",
        fontWeight: 500,
        fontSize: 11 * scale,
        height: 14 * scale,
        letterSpacing: ".04em",
        color: topColor,
        lineHeight: 1,
      }}>{kc.top || "\u00A0"}</span>
      <button
        onMouseDown={() => { setPointerPressed(true); onDown && onDown(kc.label); }}
        onMouseUp={() => { setPointerPressed(false); onUp && onUp(kc.label); }}
        onMouseLeave={() => { setPointerPressed(false); onUp && onUp(kc.label); }}
        onTouchStart={() => { setPointerPressed(true); onDown && onDown(kc.label); }}
        // preventDefault here suppresses the mousedown/mouseup/click "compatibility"
        // cascade Safari synthesizes after a touch it still classifies as a tap.
        // Without it, a touch held past PlayCalculator.jsx's PLAY_KEY_HOLD_MS floor
        // (so its own release already fired synchronously, right at touch-up) gets
        // a second, independent press/release cycle from that synthetic cascade —
        // a real second digit landing right when the finger lifts. Brief taps and
        // genuine long presses were never affected (the synthetic release either
        // lands before the real one, or Safari suppresses the whole cascade for a
        // long hold); this only happens in between. Real mouse/trackpad clicks are
        // immune by construction — a click there isn't a translation of a touch,
        // so there's no separate cascade to suppress. (preventDefault is skipped
        // on touchstart/touchmove: React marks the delegated root listener for
        // those passive by default, so it would just warn and do nothing there.)
        onTouchEnd={(e) => { e.preventDefault(); setPointerPressed(false); onUp && onUp(kc.label); }}
        onClick={(e) => {
          if (onDown) {
            // Keyboard/assistive-tech activation (Tab, then Enter/Space)
            // dispatches only a synthetic click — no mousedown/touchstart —
            // and that synthetic click's detail is 0. A real mouse click's
            // detail is >=1 and is already fully handled by the
            // mousedown/mouseup pair above; treating it here too would
            // press-and-release the key twice per click.
            if (e.detail === 0) { onDown(kc.label); onUp && onUp(kc.label); }
          }
        }}
        style={{
          width: keyWidth,
          height: keyHeight,
          background: styleByTone.background,
          color: styleByTone.color,
          border: 0,
          borderRadius: keyRadius,
          // No blanket text-transform: CALC_ROWS' label strings are already
          // cased the way real hardware sets them ("2nd", not "2ND"; lnx/
          // x⇄t/x²/√x/1/x/yˣ lowercase). Forcing uppercase here fought that.
          // No italic anywhere on the real keyboard face either.
          fontFamily: "var(--font-keycap)",
          fontWeight: 700,
          fontSize: kc.label.length > 3 ? 14 * scale : 16 * scale,
          letterSpacing: ".04em",
          boxShadow: styleByTone.shadow,
          cursor: "pointer",
          transform: pressed ? "translateY(1px)" : "none",
          padding: 0,
        }}>
        {kc.label}
      </button>
    </div>
  );
}
