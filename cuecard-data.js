// Cue-card parsing (no JSX/React) for the playable web calculator (#play).
// JS port of App/CueCardContent.swift — same math-token table, same
// key:value line parser, same field names — so packed module JSON
// (tools/pack_roms.py output) and preset-embedded CUECARD: sections
// (parsed by state-file-parser.js) can share one data shape.
//
// Deliberately plain (non-module, non-JSX) so it loads identically via
// a classic <script> tag on the main thread and via importScripts() in
// calc-engine-worker.js. Rendering (React) lives in cuecard.jsx, which
// depends on this file being loaded first.
//
// Exposes globals: expandMathTokens, newCueCard, applyCueCardLine,
// cueCardFromPacked.

// Verbatim (script + regenerated) copy of the token table in
// App/CueCardContent.swift — do not hand-edit; regenerate from the Swift
// source if it changes.
const MATH_TOKENS = [
  ["\\lambda", "λ"],
  ["\\Lambda", "Λ"],
  ["\\sigma", "σ"],
  ["\\Sigma", "Σ"],
  ["\\mu", "μ"],
  ["\\theta", "θ"],
  ["\\Theta", "Θ"],
  ["\\alpha", "α"],
  ["\\beta", "β"],
  ["\\epsilon", "ε"],
  ["\\Epsilon", "Ε"],
  ["\\Delta", "Δ"],
  ["\\pi", "π"],
  ["\\Pi", "Π"],
  ["\\xbar", "x̄"],
  ["\\ybar", "ȳ"],
  ["\\zbar", "z̄"],
  ["\\nbar", "n̄"],
  ["\\mbar", "m̄"],
  ["\\leftrightarrows", "⇄"],
  ["\\leftrightarrow", "↔"],
  ["\\updownarrow", "↕"],
  ["\\leftarrow", "←"],
  ["\\to", "→"],
  ["\\sqrt", "√"],
  ["\\cbrt", "∛"],
  ["\\fourthroot", "∜"],
  ["\\triangle", "△"],
  ["\\angle", "∠"],
  ["\\inf", "∞"],
  ["\\sum", "∑"],
  ["\\product", "∏"],
  ["\\integral", "∫"],
  ["\\approx", "≈"],
  ["\\neq", "≠"],
  ["\\leq", "≤"],
  ["\\geq", "≥"],
  ["\\blank", "​"],
  ["^{-1}", "⁻¹"],
  ["^{-2}", "⁻²"],
  ["^{-3}", "⁻³"],
  ["^{-}", "⁻"],
  ["^{+}", "⁺"],
  ["^{*}", "ˣ"],
  ["^{n}", "ⁿ"],
  ["^{T}", "ᵀ"],
  ["^{x}", "ˣ"],
  ["^{X}", "ˣ"],
  ["^{y}", "ʸ"],
  ["^{Y}", "ʸ"],
  ["^{z}", "ᶻ"],
  ["^{Z}", "ᶻ"],
  ["^{0}", "⁰"],
  ["^{1}", "¹"],
  ["^{2}", "²"],
  ["^{3}", "³"],
  ["^{4}", "⁴"],
  ["^{5}", "⁵"],
  ["^{6}", "⁶"],
  ["^{7}", "⁷"],
  ["^{8}", "⁸"],
  ["^{9}", "⁹"],
  ["_{-1}", "₋₁"],
  ["_{-}", "₋"],
  ["_{+}", "₊"],
  ["_{0}", "₀"],
  ["_{1}", "₁"],
  ["_{2}", "₂"],
  ["_{3}", "₃"],
  ["_{4}", "₄"],
  ["_{5}", "₅"],
  ["_{6}", "₆"],
  ["_{7}", "₇"],
  ["_{8}", "₈"],
  ["_{9}", "₉"],
  ["_{i}", "ᵢ"],
  ["_{j}", "ⱼ"],
  ["_{a}", "ₐ"],
  ["_{e}", "ₑ"],
  ["_{o}", "ₒ"],
  ["_{x}", "ₓ"],
  ["_{X}", "ₓ"],
  ["_{y}", "ᵧ"],
  ["_{Y}", "ᵧ"],
  ["_{n}", "ₙ"],
  ["_{m}", "ₘ"],
  ["_{k}", "ₖ"],
];

function expandMathTokens(input) {
  let result = input;
  for (const [token, unicode] of MATH_TOKENS) {
    result = result.split(token).join(unicode);
  }
  return result;
}

function newCueCard() {
  return {
    template: "CueCard",
    title: "",
    banks: [null, null],
    id: "",
    labels: ["", "", "", "", "", "", "", "", "", ""], // [A',B',C',D',E', A,B,C,D,E]
    row1: "", row1Align: "center",
    row2: "", row2Align: "left",
    row2R: "", row2RAlign: "left",
    style: "none",
  };
}

const LABEL_INDEX = {
  a: 5, b: 6, c: 7, d: 8, e: 9,
  "a'": 0, "a′": 0, "b'": 1, "b′": 1, "c'": 2, "c′": 2,
  "d'": 3, "d′": 3, "e'": 4, "e′": 4,
};

function parseAlign(value) {
  const v = value.toLowerCase();
  return v === "right" || v === "center" ? v : "left";
}

// Mutates `card` in place from one "Key: value" line — mirrors
// CueCardContent.parseLine, including math-token expansion on every
// free-text field.
function applyCueCardLine(card, line) {
  const idx = line.indexOf(":");
  if (idx < 0) return;
  const key = line.slice(0, idx).trim().toLowerCase();
  const value = line.slice(idx + 1).trim();

  switch (key) {
    case "template":
      if (value === "CueCard" || value === "MagnetCard" || value === "SolidStateCard") {
        card.template = value;
      }
      return;
    case "title":
      card.title = expandMathTokens(value);
      return;
    case "banks": {
      const parts = value.split(",");
      const left = parts[0] !== undefined ? parts[0].trim() : "";
      const right = parts[1] !== undefined ? parts[1].trim() : "";
      card.banks = [left === "" ? null : parseInt(left, 10), right === "" ? null : parseInt(right, 10)];
      return;
    }
    case "id":
      card.id = expandMathTokens(value);
      return;
    case "idalign":
      return; // deprecated, ignored
    case "row1":
      card.row1 = expandMathTokens(value);
      return;
    case "row2":
      card.row2 = expandMathTokens(value);
      return;
    case "row2r":
      card.row2R = expandMathTokens(value);
      return;
    case "style":
      if (value.toLowerCase() === "none" || value.toLowerCase() === "button") {
        card.style = value.toLowerCase();
      }
      return;
    case "row1align":
      card.row1Align = parseAlign(value);
      return;
    case "row2align":
      card.row2Align = parseAlign(value);
      return;
    case "row2ralign":
      card.row2RAlign = parseAlign(value);
      return;
    default: {
      const labelIdx = LABEL_INDEX[key];
      if (labelIdx !== undefined) {
        card.labels[labelIdx] = expandMathTokens(value);
      }
    }
  }
}

// Parse a JSON cue-card record (already { key: value, ... } shaped, as
// packed by tools/pack_roms.py) into a card object — no line parsing
// needed since the packer already applied the field mapping.
function cueCardFromPacked(record) {
  const card = newCueCard();
  Object.assign(card, record);
  return card;
}
