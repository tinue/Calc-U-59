// Calc-U 59 — Faithful recreation of the iOS app UI.
// Reference: assets/app-screenshot.png. Numeric ops work; many program-mode
// keys are decorative. This component is the centerpiece of the UI kit.

const {
  useState: useStateCalc
} = React;

// ---- Key bank (module scope: shared with PlayCalculator.jsx) ----
// tone: cream | dark | yellow
// top labels: their color hints (silk-cream / silk-yellow / silk-mahogany)
// mathVar: the six keys whose face names a variable (x, t, y), not an
// abbreviation — real hardware sets these in lowercase italic math notation
// (confirmed against ti59_base.png: "ln" upright + italic "x", "x⇄t" fully
// italic, etc.), unlike every other key's plain uppercase legend.
// Row/col positions here are also the UI grid coordinates the emulation
// worker's pressUIKey() expects, so there is exactly one copy to keep true.
const CALC_D = "dark",
  CALC_C = "cream",
  CALC_Y = "yellow";
const CALC_ROWS = [[{
  top: "A'",
  label: "A",
  tone: CALC_D
}, {
  top: "B'",
  label: "B",
  tone: CALC_D
}, {
  top: "C'",
  label: "C",
  tone: CALC_D
}, {
  top: "D'",
  label: "D",
  tone: CALC_D
}, {
  top: "E'",
  label: "E",
  tone: CALC_D
}], [{
  top: "",
  label: "2nd",
  tone: CALC_Y
}, {
  top: "",
  label: "INV",
  tone: CALC_D
}, {
  top: "log",
  label: "lnx",
  tone: CALC_D,
  mathVar: true
}, {
  top: "CP",
  label: "CE",
  tone: CALC_D
}, {
  top: "",
  label: "CLR",
  tone: CALC_Y
}], [{
  top: "Pgm",
  label: "LRN",
  tone: CALC_D
}, {
  top: "P→R",
  label: "x⇄t",
  tone: CALC_D,
  mathVar: true
}, {
  top: "sin",
  label: "x²",
  tone: CALC_D,
  mathVar: true
}, {
  top: "cos",
  label: "√x",
  tone: CALC_D,
  mathVar: true
}, {
  top: "tan",
  label: "1/x",
  tone: CALC_D,
  mathVar: true
}], [{
  top: "Ins",
  label: "SST",
  tone: CALC_D
}, {
  top: "CMs",
  label: "STO",
  tone: CALC_D
}, {
  top: "Exc",
  label: "RCL",
  tone: CALC_D
}, {
  top: "Prd",
  label: "SUM",
  tone: CALC_D
}, {
  top: "Ind",
  label: "yˣ",
  tone: CALC_D,
  mathVar: true
}], [{
  top: "Del",
  label: "BST",
  tone: CALC_D
}, {
  top: "Eng",
  label: "EE",
  tone: CALC_D
}, {
  top: "Fix",
  label: "(",
  tone: CALC_D
}, {
  top: "Int",
  label: ")",
  tone: CALC_D
}, {
  top: "|x|",
  label: "÷",
  tone: CALC_Y
}], [{
  top: "Pause",
  label: "GTO",
  tone: CALC_D
}, {
  top: "x=t",
  label: "7",
  tone: CALC_C
}, {
  top: "Nop",
  label: "8",
  tone: CALC_C
}, {
  top: "Op",
  label: "9",
  tone: CALC_C
}, {
  top: "Deg",
  label: "×",
  tone: CALC_Y
}], [{
  top: "Lbl",
  label: "SBR",
  tone: CALC_D
}, {
  top: "x≥t",
  label: "4",
  tone: CALC_C
}, {
  top: "Σ+",
  label: "5",
  tone: CALC_C
}, {
  top: "x̄",
  label: "6",
  tone: CALC_C
}, {
  top: "Rad",
  label: "−",
  tone: CALC_Y
}], [{
  top: "St flg",
  label: "RST",
  tone: CALC_D
}, {
  top: "If flg",
  label: "1",
  tone: CALC_C
}, {
  top: "D.MS",
  label: "2",
  tone: CALC_C
}, {
  top: "π",
  label: "3",
  tone: CALC_C
}, {
  top: "Grad",
  label: "+",
  tone: CALC_Y
}], [{
  top: "Write",
  label: "R/S",
  tone: CALC_D
}, {
  top: "Dsz",
  label: "0",
  tone: CALC_C
}, {
  top: "Adv",
  label: ".",
  tone: CALC_C
}, {
  top: "Prt",
  label: "+/-",
  tone: CALC_C
}, {
  top: "List",
  label: "=",
  tone: CALC_Y
}]];
function Calculator({
  scale = 1
}) {
  const [display, setDisplay] = useStateCalc("-1,234567 8-90");
  const [acc, setAcc] = useStateCalc(null);
  const [op, setOp] = useStateCalc(null);
  const [fresh, setFresh] = useStateCalc(true);
  const [shift, setShift] = useStateCalc(null);
  const press = k => {
    if (k === "2nd") {
      setShift(shift === "2nd" ? null : "2nd");
      return;
    }
    if (k === "INV") {
      setShift(shift === "INV" ? null : "INV");
      return;
    }
    if (k === "CLR") {
      setDisplay("0.");
      setAcc(null);
      setOp(null);
      setFresh(true);
      setShift(null);
      return;
    }
    if (k === "CE") {
      setDisplay("0.");
      setFresh(true);
      setShift(null);
      return;
    }
    if (/^[0-9]$/.test(k)) {
      const next = fresh || display === "0." || /[-,a-z]/i.test(display) ? k + "." : display.endsWith(".") ? display.slice(0, -1) + k + "." : display + k;
      setDisplay(next);
      setFresh(false);
      setShift(null);
      return;
    }
    if (k === ".") {
      if (!display.includes(".") || fresh) {
        setDisplay(fresh ? "0." : display.endsWith(".") ? display : display + ".");
        setFresh(false);
      }
      setShift(null);
      return;
    }
    if (k === "+/-") {
      const n = parseFloat(display);
      if (!isNaN(n)) setDisplay(formatLED(-n));
      setShift(null);
      return;
    }
    if (["+", "-", "×", "÷"].includes(k)) {
      const cur = parseFloat(display);
      const next = acc == null || op == null || isNaN(cur) ? isNaN(cur) ? 0 : cur : applyOp(acc, cur, op);
      setAcc(next);
      setDisplay(formatLED(next));
      setOp(k);
      setFresh(true);
      setShift(null);
      return;
    }
    if (k === "=") {
      const cur = parseFloat(display);
      const next = acc == null || op == null ? cur : applyOp(acc, cur, op);
      setDisplay(formatLED(next));
      setAcc(null);
      setOp(null);
      setFresh(true);
      setShift(null);
      return;
    }
    if (k === "√x") {
      setDisplay(formatLED(Math.sqrt(parseFloat(display) || 0)));
      setFresh(true);
      setShift(null);
      return;
    }
    if (k === "x²") {
      setDisplay(formatLED(Math.pow(parseFloat(display) || 0, 2)));
      setFresh(true);
      setShift(null);
      return;
    }
    if (k === "1/x") {
      setDisplay(formatLED(1 / (parseFloat(display) || 1)));
      setFresh(true);
      setShift(null);
      return;
    }
    if (k === "lnx") {
      setDisplay(formatLED(Math.log(parseFloat(display) || 1)));
      setFresh(true);
      setShift(null);
      return;
    }
    setShift(null);
  };
  return /*#__PURE__*/React.createElement("div", {
    className: "calcu-device",
    style: {
      width: `${360 * scale}px`,
      background: "#000",
      padding: `${10 * scale}px ${12 * scale}px ${8 * scale}px`,
      fontFamily: "var(--font-keycap)",
      userSelect: "none"
    }
  }, /*#__PURE__*/React.createElement(Display, {
    scale: scale,
    text: display,
    shift: shift
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "grid",
      gap: 8 * scale,
      marginTop: 14 * scale
    }
  }, CALC_ROWS.map((row, ri) => /*#__PURE__*/React.createElement("div", {
    key: ri,
    style: {
      display: "grid",
      gridTemplateColumns: "repeat(5, 1fr)",
      gap: 8 * scale
    }
  }, row.map((kc, ci) => /*#__PURE__*/React.createElement(CalcKey, {
    key: ci,
    kc: kc,
    scale: scale,
    onPress: press
  }))))), /*#__PURE__*/React.createElement(BottomToolbar, {
    scale: scale
  }));
}

/* ============================================================
   Display — mahogany strip + LED window + module reference panel
   ============================================================ */
function Display({
  scale,
  text,
  shift
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      background: "linear-gradient(180deg,#1a0c08 0%,#2c1812 50%,#1a0c08 100%)",
      borderRadius: 10 * scale,
      padding: `${10 * scale}px ${10 * scale}px ${0}px`,
      border: `1px solid #3a2418`,
      boxShadow: "0 1px 0 rgba(255,200,100,.04), inset 0 0 0 1px rgba(0,0,0,.4)",
      position: "relative"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      background: "#0a0302",
      borderRadius: 4 * scale,
      padding: `${10 * scale}px ${12 * scale}px ${4 * scale}px`,
      position: "relative",
      boxShadow: "inset 0 2px 8px rgba(0,0,0,.8)",
      overflow: "hidden"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      inset: `${10 * scale}px ${12 * scale}px ${4 * scale}px`,
      fontFamily: "var(--font-display)",
      fontSize: 26 * scale,
      color: "#3a0e08",
      letterSpacing: ".04em",
      textAlign: "right",
      lineHeight: 1,
      whiteSpace: "nowrap",
      overflow: "hidden"
    }
  }, "~8.8.8.8.8.8.8.8-8.8."), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "relative",
      fontFamily: "var(--font-display)",
      fontSize: 26 * scale,
      color: "#ff2614",
      textShadow: "0 0 10px rgba(255,38,20,.7), 0 0 22px rgba(255,38,20,.3)",
      letterSpacing: ".04em",
      textAlign: "right",
      lineHeight: 1,
      whiteSpace: "nowrap",
      overflow: "hidden"
    }
  }, text), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      justifyContent: "space-between",
      marginTop: 6 * scale,
      color: "#5a3018",
      fontFamily: "var(--font-keycap)",
      fontSize: 9 * scale,
      letterSpacing: ".12em",
      textTransform: "uppercase"
    }
  }, /*#__PURE__*/React.createElement("span", null, "Solid State Software"), /*#__PURE__*/React.createElement("span", null, "TI \xA91977"))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      justifyContent: "space-between",
      alignItems: "center",
      padding: `${8 * scale}px 2px ${2 * scale}px`,
      color: "#c89858",
      fontFamily: "var(--font-keycap)",
      fontWeight: 700,
      fontSize: 11 * scale,
      letterSpacing: ".05em"
    }
  }, /*#__PURE__*/React.createElement("span", null, "MASTER LIBRARY DIAGNOSTIC"), /*#__PURE__*/React.createElement("span", null, "ML-01")), /*#__PURE__*/React.createElement("div", {
    style: {
      color: "#a87830",
      fontFamily: "var(--font-keycap)",
      fontWeight: 500,
      fontSize: 10 * scale,
      letterSpacing: ".04em",
      padding: `${2 * scale}px ${2 * scale}px ${6 * scale}px`,
      lineHeight: 1.6
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      textAlign: "center"
    }
  }, "DIAGNOSTIC: ", /*#__PURE__*/React.createElement(Token, {
    scale: scale
  }, "SBR"), " ", /*#__PURE__*/React.createElement(Token, {
    scale: scale
  }, "=")), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      justifyContent: "space-between",
      marginTop: 2
    }
  }, /*#__PURE__*/React.createElement("span", null, "L.R. INIT: ", /*#__PURE__*/React.createElement(Token, {
    scale: scale
  }, "SBR"), " ", /*#__PURE__*/React.createElement(Token, {
    scale: scale
  }, "CLR")), /*#__PURE__*/React.createElement("span", null, "PRINT: mm ", /*#__PURE__*/React.createElement(Token, {
    scale: scale
  }, "STO"), " 00"))), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      top: 8 * scale,
      right: 8 * scale,
      width: 24 * scale,
      height: 24 * scale,
      borderRadius: 4 * scale,
      background: "rgba(180,140,80,.12)",
      border: "1px solid rgba(180,140,80,.25)",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      color: "#c89858",
      fontSize: 14 * scale,
      fontFamily: "var(--font-body)"
    }
  }, "\u203A"));
}
function Token({
  scale,
  children
}) {
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline-block",
      border: "1px solid #a87830",
      padding: `0 ${5 * scale}px`,
      borderRadius: 2,
      letterSpacing: ".05em",
      color: "#c89858",
      fontFamily: "var(--font-keycap)",
      fontWeight: 700
    }
  }, children);
}

/* ============================================================
   Single key (top label + button)
   ============================================================ */
// forcePressed lets an outside caller light a key that no pointer is touching —
// PlayCalculator.jsx uses it so a physical-keyboard press looks exactly like a
// clicked one. The decorative <Calculator> demo passes nothing and is unaffected.
//
// onDown/onUp (PlayCalculator.jsx) drive the real emulator press/release from
// actual pointer down/up, instead of a synthetic fixed hold measured from
// onClick — see PlayCalculator.jsx's pointerDown/pointerUp for why. The
// decorative <Calculator> demo doesn't pass these; it keeps using onPress via
// onClick exactly as before.
function CalcKey({
  kc,
  scale,
  onPress,
  onDown,
  onUp,
  forcePressed = false
}) {
  const [pointerPressed, setPointerPressed] = useStateCalc(false);
  const pressed = pointerPressed || forcePressed;
  const setPressed = setPointerPressed;
  const styleByTone = {
    cream: {
      background: pressed ? "linear-gradient(180deg,#d8c8a8,#c0b08c)" : "linear-gradient(180deg,#efe4cc 0%,#d8c8a8 100%)",
      color: "#1a130d",
      shadow: pressed ? "inset 0 2px 4px rgba(0,0,0,.45)" : "0 1px 0 #6a5a3c, 0 2px 3px rgba(0,0,0,.5), inset 0 1px 0 rgba(255,255,255,.4)"
    },
    dark: {
      background: pressed ? "linear-gradient(180deg,#1a1208,#100a04)" : "linear-gradient(180deg,#2a1f15 0%,#1f1610 100%)",
      color: "#efe4cc",
      shadow: pressed ? "inset 0 2px 4px rgba(0,0,0,.6)" : "0 1px 0 #000, 0 2px 4px rgba(0,0,0,.5), inset 0 1px 0 rgba(255,200,100,.05)"
    },
    yellow: {
      background: pressed ? "linear-gradient(180deg,#d8a830,#b88a20)" : "linear-gradient(180deg,#f0c040 0%,#d8a830 100%)",
      color: "#2a1f10",
      shadow: pressed ? "inset 0 2px 4px rgba(0,0,0,.5)" : "0 1px 0 #5a3c10, 0 2px 3px rgba(0,0,0,.5), inset 0 1px 0 rgba(255,255,255,.25)"
    }
  }[kc.tone];
  const topColor = kc.tone === "yellow" ? "#e8b840" : kc.top && /[A-E]'/.test(kc.top) ? "#d4c4a0" : "#d4c4a0";

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
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      alignItems: "center",
      gap: 2 * scale
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: "var(--font-keycap)",
      fontWeight: 500,
      fontSize: 11 * scale,
      height: 14 * scale,
      letterSpacing: ".04em",
      color: topColor,
      lineHeight: 1
    }
  }, kc.top || "\u00A0"), /*#__PURE__*/React.createElement("button", {
    onMouseDown: () => {
      setPressed(true);
      onDown && onDown(kc.label);
    },
    onMouseUp: () => {
      setPressed(false);
      onUp && onUp(kc.label);
    },
    onMouseLeave: () => {
      setPressed(false);
      onUp && onUp(kc.label);
    },
    onTouchStart: () => {
      setPressed(true);
      onDown && onDown(kc.label);
    },
    onTouchEnd: () => {
      setPressed(false);
      onUp && onUp(kc.label);
    },
    onClick: e => {
      if (onDown) {
        // Keyboard/assistive-tech activation (Tab, then Enter/Space)
        // dispatches only a synthetic click — no mousedown/touchstart —
        // and that synthetic click's detail is 0. A real mouse click's
        // detail is >=1 and is already fully handled by the
        // mousedown/mouseup pair above; treating it here too would
        // press-and-release the key twice per click.
        if (e.detail === 0) {
          onDown(kc.label);
          onUp && onUp(kc.label);
        }
      } else if (onPress) {
        onPress(kc.label);
      }
    },
    style: {
      width: keyWidth,
      height: keyHeight,
      background: styleByTone.background,
      color: styleByTone.color,
      border: 0,
      borderRadius: keyRadius,
      // No blanket text-transform: CALC_ROWS' label strings are already
      // cased the way real hardware sets them ("2nd", not "2ND"; the six
      // mathVar keys lowercase). Forcing uppercase here fought that.
      fontFamily: "var(--font-keycap)",
      fontStyle: kc.mathVar ? "italic" : "normal",
      fontWeight: 700,
      fontSize: kc.label.length > 3 ? 14 * scale : 16 * scale,
      letterSpacing: ".04em",
      boxShadow: styleByTone.shadow,
      cursor: "pointer",
      transform: pressed ? "translateY(1px)" : "none",
      padding: 0
    }
  }, kc.label));
}

/* ============================================================
   Bottom iOS toolbar
   ============================================================ */
function BottomToolbar({
  scale
}) {
  const icoSize = 22 * scale;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 14 * scale,
      paddingTop: 14 * scale,
      paddingBottom: 6 * scale,
      paddingLeft: 4 * scale,
      paddingRight: 4 * scale
    }
  }, /*#__PURE__*/React.createElement(SymbolUndo, {
    size: icoSize,
    color: "#ff9f0a"
  }), /*#__PURE__*/React.createElement("button", {
    style: {
      background: "transparent",
      border: 0,
      color: "#0a84ff",
      fontFamily: "-apple-system, system-ui, sans-serif",
      fontSize: 17 * scale,
      fontWeight: 600,
      display: "flex",
      alignItems: "center",
      gap: 4,
      padding: 0,
      cursor: "pointer"
    }
  }, "TI-59 ", /*#__PURE__*/React.createElement(SymbolChevrons, {
    size: icoSize * 0.7,
    color: "#0a84ff"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(SymbolDownload, {
    size: icoSize,
    color: "#8e8e93"
  }), /*#__PURE__*/React.createElement(SymbolPlus, {
    size: icoSize,
    color: "#8e8e93"
  }), /*#__PURE__*/React.createElement(SymbolShare, {
    size: icoSize,
    color: "#8e8e93"
  }), /*#__PURE__*/React.createElement(SymbolGear, {
    size: icoSize,
    color: "#8e8e93"
  }));
}

/* ============================================================
   Inline SF-Symbol-ish icons (no external deps)
   ============================================================ */
function _S({
  size,
  color,
  d,
  sw = 1.6,
  fill = "none"
}) {
  return /*#__PURE__*/React.createElement("svg", {
    width: size,
    height: size,
    viewBox: "0 0 24 24",
    fill: fill,
    stroke: color,
    strokeWidth: sw,
    strokeLinecap: "round",
    strokeLinejoin: "round",
    style: {
      flex: "0 0 auto"
    }
  }, /*#__PURE__*/React.createElement("path", {
    d: d
  }));
}
function SymbolUndo({
  size,
  color
}) {
  return /*#__PURE__*/React.createElement("svg", {
    width: size,
    height: size,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: color,
    strokeWidth: "2",
    strokeLinecap: "round",
    strokeLinejoin: "round"
  }, /*#__PURE__*/React.createElement("path", {
    d: "M3 12 a 9 9 0 1 0 3-6.7"
  }), /*#__PURE__*/React.createElement("polyline", {
    points: "3 4 3 9 8 9"
  }));
}
function SymbolChevrons({
  size,
  color
}) {
  return /*#__PURE__*/React.createElement(_S, {
    size: size,
    color: color,
    sw: 2.2,
    d: "M8 9 L12 6 L16 9 M8 15 L12 18 L16 15"
  });
}
function SymbolDownload({
  size,
  color
}) {
  return /*#__PURE__*/React.createElement("svg", {
    width: size,
    height: size,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: color,
    strokeWidth: "1.6",
    strokeLinecap: "round",
    strokeLinejoin: "round"
  }, /*#__PURE__*/React.createElement("rect", {
    x: "3.5",
    y: "4",
    width: "17",
    height: "16",
    rx: "3"
  }), /*#__PURE__*/React.createElement("path", {
    d: "M12 9 V 16 M9 13 L 12 16 L 15 13"
  }));
}
function SymbolPlus({
  size,
  color
}) {
  return /*#__PURE__*/React.createElement("svg", {
    width: size,
    height: size,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: color,
    strokeWidth: "1.6",
    strokeLinecap: "round",
    strokeLinejoin: "round"
  }, /*#__PURE__*/React.createElement("rect", {
    x: "3.5",
    y: "4",
    width: "17",
    height: "16",
    rx: "3"
  }), /*#__PURE__*/React.createElement("path", {
    d: "M8 12 H 16 M12 8 V 16"
  }));
}
function SymbolShare({
  size,
  color
}) {
  return /*#__PURE__*/React.createElement("svg", {
    width: size,
    height: size,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: color,
    strokeWidth: "1.6",
    strokeLinecap: "round",
    strokeLinejoin: "round"
  }, /*#__PURE__*/React.createElement("rect", {
    x: "3.5",
    y: "4",
    width: "17",
    height: "16",
    rx: "3"
  }), /*#__PURE__*/React.createElement("path", {
    d: "M12 14 V 7 M9 10 L 12 7 L 15 10"
  }));
}
function SymbolGear({
  size,
  color
}) {
  // 8-tooth gearshape: rectangular teeth around a ring with a center hole.
  // Matches SF Symbols `gearshape` silhouette.
  const teeth = [];
  const tw = 2.0; // tooth width
  const th = 2.4; // tooth height (outside ring)
  const r = 7.5; // outer ring radius
  for (let i = 0; i < 8; i++) {
    const a = i * 45 * Math.PI / 180;
    const cx = 12 + Math.cos(a) * (r + th / 2);
    const cy = 12 + Math.sin(a) * (r + th / 2);
    teeth.push(/*#__PURE__*/React.createElement("rect", {
      key: i,
      x: cx - tw / 2,
      y: cy - th / 2,
      width: tw,
      height: th,
      transform: `rotate(${i * 45} ${cx} ${cy})`,
      fill: color,
      stroke: "none",
      rx: "0.4"
    }));
  }
  return /*#__PURE__*/React.createElement("svg", {
    width: size,
    height: size,
    viewBox: "0 0 24 24",
    fill: "none"
  }, teeth, /*#__PURE__*/React.createElement("circle", {
    cx: "12",
    cy: "12",
    r: "7",
    fill: color
  }), /*#__PURE__*/React.createElement("circle", {
    cx: "12",
    cy: "12",
    r: "3.2",
    fill: "#000"
  }));
}
function applyOp(a, b, op) {
  switch (op) {
    case "+":
      return a + b;
    case "-":
      return a - b;
    case "×":
      return a * b;
    case "÷":
      return a / b;
    default:
      return b;
  }
}
function formatLED(n) {
  if (!isFinite(n) || isNaN(n)) return "Error";
  const s = Math.abs(n) < 1e-6 || Math.abs(n) >= 1e10 ? n.toExponential(6) : (Math.round(n * 1e8) / 1e8).toString();
  return s.includes(".") ? s : s + ".";
}
Object.assign(window, {
  Calculator,
  Display,
  CalcKey,
  BottomToolbar,
  CALC_ROWS,
  SymbolUndo,
  SymbolChevrons,
  SymbolDownload,
  SymbolPlus,
  SymbolShare,
  SymbolGear
});