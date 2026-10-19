// Cue card drawing for the playable web calculator (/play/). The card comes
// from the worker, resolved and laid out by the main repo's Shared/CueCard
// (which card shows, its label spans with \blank cells merged, its ink
// colour); this file only draws it, after App/Views/CueCardView.swift:
//   - topSpans are the A′–E′ row, bottomSpans the A–E row; the key letters
//     themselves are never drawn — the physical keys sit below the card.
//   - MagnetCard bank badges are not drawn: on real hardware they are
//     mostly hidden under the LED display.
//   - MagnetCard shows its full 5-cell grid even where a row is empty, as
//     the printed card does (source-material/MagnetCard.svg).
//
// Sizes follow the `scale` prop like the rest of PlayCalculator.jsx; colours,
// borders and layout structure are in calc.css.

// MagnetCard: fill the columns no span covers, so every cell keeps its frame.
// A space ( ) rather than "", which can collapse the row's line box.
function cueCardMagnetCells(spans) {
  const out = [];
  let col = 0;
  for (const s of spans) {
    for (; col < s.start; col++) out.push({ start: col, end: col, label: "\u00a0" });
    out.push(s);
    col = s.end + 1;
  }
  for (; col < 5; col++) out.push({ start: col, end: col, label: "\u00a0" });
  return out;
}

const { useRef: useCueCardRef, useState: useCueCardState, useLayoutEffect: useCueCardLayoutEffect, useMemo: useCueCardMemo } = React;

// Port of CueCardView.cellFittingFontSize: one shared font size per row,
// shrunk (down to 40% of the base size, same floor Swift uses) just
// enough that every cell's text fits on a single line — never wrapped,
// never overflowing into the next row and jumping the card's (and so the
// whole calculator's) height. Swift computes this from character counts
// against known SwiftUI-image-relative geometry; here the layout is
// plain CSS grid, so it's simpler and more accurate to measure the
// actual rendered DOM (scrollWidth vs clientWidth) instead of guessing
// column pixel widths analytically.
function CueCardGridRow({ spans, showDividers, dividerColor, scale, baseFontSize }) {
  const cellRefs = useCueCardRef([]);
  const [fontSize, setFontSize] = useCueCardState(baseFontSize);

  useCueCardLayoutEffect(() => {
    // Reset to the natural size first (direct DOM write, bypassing React
    // state) so the measurement below reflects the un-shrunk width, not
    // whatever size a previous card happened to leave this row at.
    cellRefs.current.forEach((el) => { if (el) el.style.fontSize = baseFontSize + "px"; });
    let minRatio = 1;
    cellRefs.current.forEach((el) => {
      if (el && el.clientWidth > 0 && el.scrollWidth > el.clientWidth) {
        minRatio = Math.min(minRatio, el.clientWidth / el.scrollWidth);
      }
    });
    setFontSize(Math.max(baseFontSize * 0.4, baseFontSize * minRatio));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [spans, baseFontSize]);

  if (spans.length === 0) return null;
  cellRefs.current = [];
  return (
    <div className="cuecard-gridrow">
      {spans.map((s, idx) => (
        <div
          key={idx}
          ref={(el) => { cellRefs.current[idx] = el; }}
          className="cuecard-cell"
          style={{
            gridColumn: `${s.start + 1} / ${s.end + 2}`,
            fontSize,
            padding: `0 ${2 * scale}px`,
            borderLeft: showDividers && s.start > 0 ? `1px solid ${dividerColor}` : "none",
            whiteSpace: "nowrap",
            overflow: "hidden",
          }}
        >
          {s.label}
        </div>
      ))}
    </div>
  );
}

// row1/row2/row2R free-text rows: Swift uses .lineLimit(1) here (truncate,
// not shrink) — matched with plain CSS ellipsis rather than the grid's
// measured shrink-to-fit, since these are single unsplit strings, not a
// row of independently-sized cells.
function CueCardAlignedText({ text, align, boxed, scale }) {
  return (
    <div
      className={`cuecard-row align-${align}` + (boxed ? " cuecard-row-boxed" : "")}
      style={{
        fontSize: 10 * scale,
        padding: boxed ? `${1 * scale}px ${5 * scale}px` : 0,
        whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis",
      }}
    >
      {text}
    </div>
  );
}

// Matches source-material/MagnetCard.svg: a solid gold card face.
const CUECARD_MAGNET_BG = "#d2a92b";

function CueCard({ card, scale = 1 }) {
  const isMagnet = !!card && card.template === "MagnetCard";
  // Memoized on card identity so CueCardGridRow's shrink-to-fit layout
  // effect (dep: spans) runs once per card, not on every re-render.
  const topSpans = useCueCardMemo(
    () => (!card || card.row1 ? null : isMagnet ? cueCardMagnetCells(card.topSpans) : card.topSpans),
    [card]
  );
  const bottomSpans = useCueCardMemo(
    () => (!card || card.row2 || card.row2R ? null : isMagnet ? cueCardMagnetCells(card.bottomSpans) : card.bottomSpans),
    [card]
  );
  if (!card) return null;
  const isSolidState = card.template === "SolidStateCard";
  const boxed = card.style === "button";

  // The printed templates take Shared's ink; the plain CueCard is drawn as a
  // dark card in the calculator's own colours (calc.css), where ink would vanish.
  const showDividers = isSolidState || isMagnet;
  const textColor = showDividers ? card.ink : undefined;
  const dividerColor = showDividers ? `color-mix(in srgb, ${card.ink} 45%, transparent)` : "transparent";
  // Exactly one gap per divider — the header's own paddingBottom already
  // separates it from the top row, so the top row only needs paddingTop
  // to balance the (symmetric) bottom row's divider line. Previously both
  // marginTop AND paddingTop were applied on top of CueCardGridRow's own
  // marginTop, tripling the gap and making a fully-populated card much
  // taller than the real card artwork.
  const topRowStyle = showDividers ? { paddingTop: 3 * scale } : {};
  const bottomRowStyle = showDividers
    ? { borderTop: `1px solid ${dividerColor}`, paddingTop: 3 * scale }
    : {};

  return (
    <div
      className="cuecard"
      style={{ padding: `${6 * scale}px ${8 * scale}px`, color: textColor, background: isMagnet ? CUECARD_MAGNET_BG : undefined }}
    >
      <div
        className="cuecard-header"
        style={{
          fontSize: 12 * scale, gap: 12 * scale, color: textColor,
          borderBottom: showDividers ? `1px solid ${dividerColor}` : "none",
          paddingBottom: showDividers ? 3 * scale : 0,
        }}
      >
        <span className="cuecard-title" style={{ whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
          {card.title}
        </span>
        {isSolidState && card.id ? <span className="cuecard-id" style={{ fontSize: 11 * scale, color: textColor }}>{card.id}</span> : null}
      </div>

      <div style={{ color: textColor, ...topRowStyle }}>
        {card.row1 ? (
          <CueCardAlignedText text={card.row1} align={card.row1Align} boxed={boxed} scale={scale} />
        ) : (
          <CueCardGridRow spans={topSpans} showDividers={showDividers} dividerColor={dividerColor} scale={scale} baseFontSize={10 * scale} />
        )}
      </div>

      <div style={{ color: textColor, ...bottomRowStyle }}>
        {card.row2 || card.row2R ? (
          <div className="cuecard-row-pair" style={{ gap: 10 * scale }}>
            <CueCardAlignedText text={card.row2} align={card.row2Align} boxed={boxed} scale={scale} />
            {card.row2R ? <CueCardAlignedText text={card.row2R} align={card.row2RAlign} boxed={boxed} scale={scale} /> : null}
          </div>
        ) : (
          <CueCardGridRow spans={bottomSpans} showDividers={showDividers} dividerColor={dividerColor} scale={scale} baseFontSize={10 * scale} />
        )}
      </div>
    </div>
  );
}
