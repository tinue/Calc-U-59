// Cue card rendering for the playable web calculator (#play).
// Ported from App/Views/CueCardView.swift's actual field usage — NOT a
// re-imagining. Notably:
//   - There is no rendered "A"/"B"/"C"/"D"/"E" key-name label anywhere.
//     labels[0..4] (the primed/2nd-function values) render as one grid
//     row, labels[5..9] (the plain values) render as a second grid row —
//     the physical A-E keys sit below the real card, so the letter itself
//     is never drawn on the card.
//   - Bank badges (MagnetCard only) are bare numbers ("1", "2"), not
//     "Bank 1" text.
//   - A run of consecutive "\blank" (U+200B) cells after a label merges
//     into that label's column span (getColumnSpans/gridRowLabels in
//     Swift) instead of rendering as separate empty cells.
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

const CUECARD_BLANK_MARKER = "​";

// Port of CueCardView.getColumnSpans: labels[rowIndex*5 .. rowIndex*5+4],
// merging trailing \blank cells into the preceding label's span.
function cueCardColumnSpans(labels, rowIndex) {
  const base = rowIndex * 5;
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
    spans.push({ start: i, end, label });
    i = end + 1;
  }
  return spans;
}

function CueCardGridRow({ spans, showDividers, scale }) {
  if (spans.length === 0) return null;
  return (
    <div className="cuecard-gridrow" style={{ marginTop: 3 * scale }}>
      {spans.map((s, idx) => (
        <div
          key={idx}
          className={"cuecard-cell" + (showDividers && s.start > 0 ? " cuecard-cell-divider" : "")}
          style={{
            gridColumn: `${s.start + 1} / ${s.end + 2}`,
            fontSize: 10 * scale,
            padding: `0 ${2 * scale}px`,
          }}
        >
          {s.label}
        </div>
      ))}
    </div>
  );
}

function CueCardAlignedText({ text, align, boxed, scale }) {
  return (
    <div
      className={`cuecard-row align-${align}` + (boxed ? " cuecard-row-boxed" : "")}
      style={{ fontSize: 10 * scale, marginTop: 3 * scale, padding: boxed ? `${1 * scale}px ${5 * scale}px` : 0 }}
    >
      {text}
    </div>
  );
}

// Matches CueCardView.swift's solidLayout.textColor exactly (0xC4,0x92,0x23)
// — a muted gold, distinct from the brighter --accent-yellow used for keys.
// Real hardware/Swift renders EVERY piece of text on a SolidStateCard in
// this one color (title, ID, both grid rows) — there's no white/gold mix.
const CUECARD_SOLID_STATE_GOLD = "#c49223";

function CueCard({ card, scale = 1 }) {
  if (!card) return null;
  const isSolidState = card.template === "SolidStateCard";
  const isMagnet = card.template === "MagnetCard";
  const boxed = card.style === "button";

  const topSpans = card.row1 ? null : cueCardColumnSpans(card.labels, 0);
  const bottomSpans = (card.row2 || card.row2R) ? null : cueCardColumnSpans(card.labels, 1);

  // MagnetCard/CueCard templates still use the old default coloring —
  // matching their real card artwork (different background per template)
  // is a separate follow-up, not done here.
  const textColor = isSolidState ? CUECARD_SOLID_STATE_GOLD : undefined;
  const dividerStyle = isSolidState
    ? { borderTop: "1px solid rgba(196,146,35,.5)", paddingTop: 3 * scale, marginTop: 3 * scale }
    : {};

  return (
    <div className="cuecard" style={{ padding: `${6 * scale}px ${8 * scale}px`, color: textColor }}>
      <div
        className="cuecard-header"
        style={{
          fontSize: 12 * scale, gap: 12 * scale, color: textColor,
          borderBottom: isSolidState ? "1px solid rgba(196,146,35,.5)" : "none",
          paddingBottom: isSolidState ? 3 * scale : 0,
        }}
      >
        <span className="cuecard-title">{card.title}</span>
        {isSolidState && card.id ? <span className="cuecard-id" style={{ fontSize: 11 * scale, color: textColor }}>{card.id}</span> : null}
      </div>

      {isMagnet && (card.banks[0] != null || card.banks[1] != null) ? (
        <div className="cuecard-banks" style={{ fontSize: 11 * scale, marginTop: 2 * scale }}>
          <span>{card.banks[0] != null ? card.banks[0] : ""}</span>
          <span>{card.banks[1] != null ? card.banks[1] : ""}</span>
        </div>
      ) : null}

      <div style={{ color: textColor }}>
        {card.row1 ? (
          <CueCardAlignedText text={card.row1} align={card.row1Align} boxed={boxed} scale={scale} />
        ) : (
          <CueCardGridRow spans={topSpans} showDividers={isSolidState} scale={scale} />
        )}
      </div>

      <div style={{ color: textColor, ...dividerStyle }}>
        {card.row2 || card.row2R ? (
          <div className="cuecard-row-pair" style={{ gap: 10 * scale }}>
            <CueCardAlignedText text={card.row2} align={card.row2Align} boxed={boxed} scale={scale} />
            {card.row2R ? <CueCardAlignedText text={card.row2R} align={card.row2RAlign} boxed={boxed} scale={scale} /> : null}
          </div>
        ) : (
          <CueCardGridRow spans={bottomSpans} showDividers={isSolidState} scale={scale} />
        )}
      </div>
    </div>
  );
}
