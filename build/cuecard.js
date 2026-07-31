// Cue card rendering for the playable web calculator (#play).
// Ported from App/Views/CueCardView.swift's actual field usage — NOT a
// re-imagining. Notably:
//   - There is no rendered "A"/"B"/"C"/"D"/"E" key-name label anywhere.
//     labels[0..4] (the primed/2nd-function values) render as one grid
//     row, labels[5..9] (the plain values) render as a second grid row —
//     the physical A-E keys sit below the real card, so the letter itself
//     is never drawn on the card.
//   - Bank/page-arrow badges (MagnetCard's "1 ◄" / "► 2") are not
//     reproduced at all — on real hardware they're mostly hidden under
//     the LED display anyway, and carry no information the rest of the
//     card doesn't already show.
//   - A run of consecutive "\blank" (U+200B) cells after a label merges
//     into that label's column span (getColumnSpans/gridRowLabels in
//     Swift) instead of rendering as separate empty cells — SolidStateCard
//     only; MagnetCard always shows its full 5-cell grid framework, per
//     source-material/MagnetCard.svg.
//
// Sizing is driven by a `scale` prop (matching every other piece of
// PlayCalculator.jsx — CalcKey, PlayDisplay) rather than fixed CSS px
// values: at the calculator's default scale=1.4, fixed sizing left this
// card's text much smaller than the physical A-E key labels sitting
// directly below it, reading as illegibly tiny next to them. Colors,
// borders, and layout structure stay in styles.css; text/spacing sizes
// are inline so they track the same scale everything else does.
//
// Depends on docs/cuecard-data.js being loaded first (newCueCard,
// applyCueCardLine, cueCardFromPacked, expandMathTokens — parsing lives
// there, kept JSX-free so calc-engine-worker.js can also use it via
// importScripts()).
//
// Loaded as a plain (non-module) Babel script alongside the other
// docs/*.jsx files. Exposes global: CueCard (React component).

// CUECARD_BLANK_MARKER comes from cuecard-data.js (loaded first), which
// owns the \blank token expansion this marker must stay in sync with.

// Port of CueCardView.getColumnSpans: labels[rowIndex*5 .. rowIndex*5+4],
// merging trailing \blank cells into the preceding label's span.
//
// forceAllCells (MagnetCard only): the real magnet-card artwork
// (source-material/MagnetCard.svg) always shows the full 5-cell grid
// framework with its dividers, even for entirely empty rows — unlike
// SolidStateCard, which only ever shows cells that actually have content.
function cueCardColumnSpans(labels, rowIndex, forceAllCells) {
  const base = rowIndex * 5;
  if (forceAllCells) {
    const spans = [];
    for (let i = 0; i < 5; i++) {
      const label = labels[base + i];
      // A truly empty string can collapse a cell's (and so the whole
      // row's) natural line-box height in some browsers/fonts — a plain
      // "" doesn't reliably reserve the same vertical space a populated
      // cell gets.   forces a real line box, same trick CalcKey uses
      // for its top-label span ({kc.top || " "}) for the same reason.
      spans.push({
        start: i,
        end: i,
        label: label && label !== CUECARD_BLANK_MARKER ? label : " "
      });
    }
    return spans;
  }
  const spans = [];
  let i = 0;
  while (i < 5) {
    const label = labels[base + i];
    if (!label || label === CUECARD_BLANK_MARKER) {
      i += 1;
      continue;
    }
    let end = i;
    while (end + 1 < 5 && labels[base + end + 1] === CUECARD_BLANK_MARKER) end += 1;
    spans.push({
      start: i,
      end,
      label
    });
    i = end + 1;
  }
  return spans;
}
const {
  useRef: useCueCardRef,
  useState: useCueCardState,
  useLayoutEffect: useCueCardLayoutEffect,
  useMemo: useCueCardMemo
} = React;

// Port of CueCardView.cellFittingFontSize: one shared font size per row,
// shrunk (down to 40% of the base size, same floor Swift uses) just
// enough that every cell's text fits on a single line — never wrapped,
// never overflowing into the next row and jumping the card's (and so the
// whole calculator's) height. Swift computes this from character counts
// against known SwiftUI-image-relative geometry; here the layout is
// plain CSS grid, so it's simpler and more accurate to measure the
// actual rendered DOM (scrollWidth vs clientWidth) instead of guessing
// column pixel widths analytically.
function CueCardGridRow({
  spans,
  showDividers,
  dividerColor,
  scale,
  baseFontSize
}) {
  const cellRefs = useCueCardRef([]);
  const [fontSize, setFontSize] = useCueCardState(baseFontSize);
  useCueCardLayoutEffect(() => {
    // Reset to the natural size first (direct DOM write, bypassing React
    // state) so the measurement below reflects the un-shrunk width, not
    // whatever size a previous card happened to leave this row at.
    cellRefs.current.forEach(el => {
      if (el) el.style.fontSize = baseFontSize + "px";
    });
    let minRatio = 1;
    cellRefs.current.forEach(el => {
      if (el && el.clientWidth > 0 && el.scrollWidth > el.clientWidth) {
        minRatio = Math.min(minRatio, el.clientWidth / el.scrollWidth);
      }
    });
    setFontSize(Math.max(baseFontSize * 0.4, baseFontSize * minRatio));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [spans, baseFontSize]);
  if (spans.length === 0) return null;
  cellRefs.current = [];
  return /*#__PURE__*/React.createElement("div", {
    className: "cuecard-gridrow"
  }, spans.map((s, idx) => /*#__PURE__*/React.createElement("div", {
    key: idx,
    ref: el => {
      cellRefs.current[idx] = el;
    },
    className: "cuecard-cell",
    style: {
      gridColumn: `${s.start + 1} / ${s.end + 2}`,
      fontSize,
      padding: `0 ${2 * scale}px`,
      borderLeft: showDividers && s.start > 0 ? `1px solid ${dividerColor}` : "none",
      whiteSpace: "nowrap",
      overflow: "hidden"
    }
  }, s.label)));
}

// row1/row2/row2R free-text rows: Swift uses .lineLimit(1) here (truncate,
// not shrink) — matched with plain CSS ellipsis rather than the grid's
// measured shrink-to-fit, since these are single unsplit strings, not a
// row of independently-sized cells.
function CueCardAlignedText({
  text,
  align,
  boxed,
  scale
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: `cuecard-row align-${align}` + (boxed ? " cuecard-row-boxed" : ""),
    style: {
      fontSize: 10 * scale,
      padding: boxed ? `${1 * scale}px ${5 * scale}px` : 0,
      whiteSpace: "nowrap",
      overflow: "hidden",
      textOverflow: "ellipsis"
    }
  }, text);
}

// Matches CueCardView.swift's solidLayout.textColor exactly (0xC4,0x92,0x23)
// — a muted gold, distinct from the brighter --accent-yellow used for keys.
// Real hardware/Swift renders EVERY piece of text on a SolidStateCard in
// this one color (title, ID, both grid rows) — there's no white/gold mix.
const CUECARD_SOLID_STATE_GOLD = "#c49223";

// Matches source-material/MagnetCard.svg: solid gold card face (#d2a92b)
// with black text throughout. The real card also has small left/right
// page-arrow badges printed on it (visible in the reference photo, mostly
// hidden under the LED display on real hardware) — deliberately not
// reproduced here; they're not load-bearing information.
const CUECARD_MAGNET_BG = "#d2a92b";
const CUECARD_MAGNET_TEXT = "#1a1207";
const CUECARD_MAGNET_DIVIDER = "rgba(26,18,7,.4)";
function CueCard({
  card,
  scale = 1
}) {
  const isMagnet = !!card && card.template === "MagnetCard";
  // Memoized on card identity so CueCardGridRow's shrink-to-fit layout
  // effect (dep: spans) runs once per card instead of re-measuring — with
  // a forced synchronous reflow — on every parent re-render, which at the
  // display's message rate was the most expensive per-frame work on the
  // page while a card was visible.
  const topSpans = useCueCardMemo(() => !card || card.row1 ? null : cueCardColumnSpans(card.labels, 0, isMagnet), [card]);
  const bottomSpans = useCueCardMemo(() => !card || card.row2 || card.row2R ? null : cueCardColumnSpans(card.labels, 1, isMagnet), [card]);
  if (!card) return null;
  const isSolidState = card.template === "SolidStateCard";
  const boxed = card.style === "button";
  const textColor = isSolidState ? CUECARD_SOLID_STATE_GOLD : isMagnet ? CUECARD_MAGNET_TEXT : undefined;
  const dividerColor = isSolidState ? "rgba(196,146,35,.5)" : isMagnet ? CUECARD_MAGNET_DIVIDER : "transparent";
  const showDividers = isSolidState || isMagnet;
  // Exactly one gap per divider — the header's own paddingBottom already
  // separates it from the top row, so the top row only needs paddingTop
  // to balance the (symmetric) bottom row's divider line. Previously both
  // marginTop AND paddingTop were applied on top of CueCardGridRow's own
  // marginTop, tripling the gap and making a fully-populated card much
  // taller than the real card artwork.
  const topRowStyle = showDividers ? {
    paddingTop: 3 * scale
  } : {};
  const bottomRowStyle = showDividers ? {
    borderTop: `1px solid ${dividerColor}`,
    paddingTop: 3 * scale
  } : {};
  return /*#__PURE__*/React.createElement("div", {
    className: "cuecard",
    style: {
      padding: `${6 * scale}px ${8 * scale}px`,
      color: textColor,
      background: isMagnet ? CUECARD_MAGNET_BG : undefined
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "cuecard-header",
    style: {
      fontSize: 12 * scale,
      gap: 12 * scale,
      color: textColor,
      borderBottom: showDividers ? `1px solid ${dividerColor}` : "none",
      paddingBottom: showDividers ? 3 * scale : 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "cuecard-title",
    style: {
      whiteSpace: "nowrap",
      overflow: "hidden",
      textOverflow: "ellipsis"
    }
  }, card.title), isSolidState && card.id ? /*#__PURE__*/React.createElement("span", {
    className: "cuecard-id",
    style: {
      fontSize: 11 * scale,
      color: textColor
    }
  }, card.id) : null), /*#__PURE__*/React.createElement("div", {
    style: {
      color: textColor,
      ...topRowStyle
    }
  }, card.row1 ? /*#__PURE__*/React.createElement(CueCardAlignedText, {
    text: card.row1,
    align: card.row1Align,
    boxed: boxed,
    scale: scale
  }) : /*#__PURE__*/React.createElement(CueCardGridRow, {
    spans: topSpans,
    showDividers: showDividers,
    dividerColor: dividerColor,
    scale: scale,
    baseFontSize: 10 * scale
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      color: textColor,
      ...bottomRowStyle
    }
  }, card.row2 || card.row2R ? /*#__PURE__*/React.createElement("div", {
    className: "cuecard-row-pair",
    style: {
      gap: 10 * scale
    }
  }, /*#__PURE__*/React.createElement(CueCardAlignedText, {
    text: card.row2,
    align: card.row2Align,
    boxed: boxed,
    scale: scale
  }), card.row2R ? /*#__PURE__*/React.createElement(CueCardAlignedText, {
    text: card.row2R,
    align: card.row2RAlign,
    boxed: boxed,
    scale: scale
  }) : null) : /*#__PURE__*/React.createElement(CueCardGridRow, {
    spans: bottomSpans,
    showDividers: showDividers,
    dividerColor: dividerColor,
    scale: scale,
    baseFontSize: 10 * scale
  })));
}