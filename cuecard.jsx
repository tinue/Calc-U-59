// Cue card rendering for the playable web calculator (#play).
// Depends on docs/cuecard-data.js being loaded first (newCueCard,
// applyCueCardLine, cueCardFromPacked — parsing lives there, kept JSX-free
// so calc-engine-worker.js can also use it via importScripts()).
//
// Loaded as a plain (non-module) Babel script alongside the other
// docs/*.jsx files. Exposes global: CueCard (React component).

function CueCardLabelRow({ labels }) {
  return (
    <div className="cuecard-labels">
      {["A", "B", "C", "D", "E"].map((k, i) => (
        <div className="cuecard-label" key={k}>
          <span className="cuecard-label-2nd">{labels[i]}</span>
          <span className="cuecard-label-key">{k}</span>
          <span className="cuecard-label-plain">{labels[i + 5]}</span>
        </div>
      ))}
    </div>
  );
}

function CueCard({ card }) {
  if (!card) return null;
  const isSolidState = card.template === "SolidStateCard";
  const isMagnet = card.template === "MagnetCard";
  return (
    <div className={`cuecard cuecard-${card.style === "button" ? "button" : "plain"}`}>
      <div className="cuecard-header">
        <span className="cuecard-title">{card.title}</span>
        {isSolidState && card.id ? <span className="cuecard-id">{card.id}</span> : null}
        {isMagnet && (card.banks[0] != null || card.banks[1] != null) ? (
          <span className="cuecard-banks">
            {card.banks[0] != null ? `Bank ${card.banks[0]}` : ""}
            {card.banks[0] != null && card.banks[1] != null ? " / " : ""}
            {card.banks[1] != null ? `Bank ${card.banks[1]}` : ""}
          </span>
        ) : null}
      </div>
      {(card.row1 || card.row2 || card.row2R) ? (
        <div className="cuecard-rows">
          {card.row1 ? <div className={`cuecard-row align-${card.row1Align}`}>{card.row1}</div> : null}
          {(card.row2 || card.row2R) ? (
            <div className="cuecard-row-pair">
              {card.row2 ? <span className={`align-${card.row2Align}`}>{card.row2}</span> : <span />}
              {card.row2R ? <span className={`align-${card.row2RAlign}`}>{card.row2R}</span> : null}
            </div>
          ) : null}
        </div>
      ) : null}
      {card.labels.some((l) => l) ? <CueCardLabelRow labels={card.labels} /> : null}
    </div>
  );
}
