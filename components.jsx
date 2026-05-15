// Calc-U 59 — Reusable components for the help site (React 18 + Babel)

const { useState, useEffect, useRef, useMemo } = React;

/* =============================================================
   Header / nav
   ============================================================= */
function SiteHeader({ page, onNav }) {
  const items = [
    { id: "home",     label: "Overview" },
    { id: "start",    label: "Getting Started" },
    { id: "ref",      label: "App Reference" },
    { id: "modules",  label: "Modules" },
    { id: "faq",      label: "FAQ" },
  ];
  return (
    <header className="site-header">
      <div className="inner">
        <a className="brand" onClick={() => onNav("home")}>
          <img className="app-icon" src="assets/app-icon.png" alt="Calc-U 59 app icon" />
          <div className="wm">
            <span className="top">Calc-U <em>59</em></span>
            <span className="sub">User Guide</span>
          </div>
        </a>
        <nav className="nav">
          {items.map(i => (
            <a key={i.id}
               className={page === i.id ? "active" : ""}
               onClick={() => onNav(i.id)}>
              {i.label}
            </a>
          ))}
          <a href="https://github.com/tinue/Calc-U-59">Github</a>
        </nav>
        <a className="nav-cta" href="https://apps.apple.com/us/app/calc-u-59/id6761413142">App Store</a>
      </div>
    </header>
  );
}

/* =============================================================
   Footer
   ============================================================= */
function SiteFooter() {
  return (
    <footer className="site-footer">
      <div className="inner">
        <strong style={{
          fontFamily: "var(--font-key)",
          letterSpacing: ".06em",
          textTransform: "uppercase",
          color: "var(--fg-2)",
        }}>Calc-U 59</strong>
        <a href="https://github.com/tinue/Calc-U-59">GitHub</a>
        <a href="https://github.com/tinue/Calc-U-59/blob/main/CHANGELOG.md">Release notes</a>
        <a href="https://github.com/tinue/Calc-U-59/blob/main/PRIVACY.md">Privacy</a>
        <span className="credits">© 2026 · TI-59 emulator for Mac, iPhone, iPad</span>
      </div>
    </footer>
  );
}

/* =============================================================
   Keystroke pills
   ============================================================= */
function K({ tone = "dark", children }) {
  return <span className={`k ${tone}`}>{children}</span>;
}
function KSeq({ steps }) {
  return (
    <span className="kseq">
      {steps.map((s, i) =>
        typeof s === "string"
          ? <span key={i} className="sep">{s}</span>
          : <K key={i} tone={s.tone}>{s.label}</K>
      )}
    </span>
  );
}

/* =============================================================
   Topic card
   ============================================================= */
function TopicCard({ num, eyebrow, title, children, onClick }) {
  return (
    <div className="panel" onClick={onClick}
         style={{
           cursor: onClick ? "pointer" : "default",
           display: "flex", flexDirection: "column", gap: 10,
           transition: "border-color .15s, transform .15s",
         }}
         onMouseEnter={e => e.currentTarget.style.borderColor = "var(--accent-deep)"}
         onMouseLeave={e => e.currentTarget.style.borderColor = "var(--stroke)"}>
      <div style={{ display: "flex", alignItems: "baseline", gap: 12 }}>
        <span style={{
          fontFamily: "var(--font-display)",
          color: "var(--led-red)",
          fontSize: 26,
          letterSpacing: ".04em",
          textShadow: "0 0 8px rgba(255,38,20,.4)",
        }}>{num}</span>
        <span className="eyebrow" style={{ margin: 0, color: "var(--accent)" }}>{eyebrow}</span>
      </div>
      <h3 style={{
        fontFamily: "var(--font-key)", fontWeight: 700, fontSize: 22,
        textTransform: "uppercase", letterSpacing: ".05em",
        margin: 0, color: "var(--fg)",
      }}>{title}</h3>
      <div style={{ color: "var(--fg-2)", fontSize: 14, lineHeight: 1.55 }}>{children}</div>
    </div>
  );
}

/* =============================================================
   Docs sidebar (used on docs pages; placeholder right now)
   ============================================================= */
function DocsSidebar({ current, onPick, sections }) {
  return (
    <aside style={{
      width: 240, flex: "0 0 240px",
      borderRight: "1px solid var(--stroke)",
      paddingRight: 20,
    }}>
      {sections.map(sec => (
        <div key={sec.title} style={{ marginBottom: 24 }}>
          <div className="eyebrow" style={{ marginBottom: 6, color: "var(--fg-3)" }}>{sec.title}</div>
          <ul style={{ listStyle: "none", padding: 0, margin: 0 }}>
            {sec.items.map(it => (
              <li key={it.id}>
                <a
                  onClick={() => onPick(it.id)}
                  style={{
                    display: "block",
                    padding: "5px 10px", marginLeft: -12, paddingLeft: 12,
                    fontFamily: "var(--font-body)",
                    fontSize: 14,
                    color: current === it.id ? "var(--fg)" : "var(--fg-2)",
                    background: current === it.id ? "rgba(240,192,64,.06)" : "transparent",
                    borderLeft: current === it.id ? "2px solid var(--accent)" : "2px solid transparent",
                    cursor: "pointer", textDecoration: "none",
                  }}>
                  {it.label}
                </a>
              </li>
            ))}
          </ul>
        </div>
      ))}
    </aside>
  );
}

/* =============================================================
   Placeholder block — used while help content is unwritten.
   Visible signal that a section is intentionally empty.
   ============================================================= */
function Placeholder({ title, note }) {
  return (
    <div style={{
      border: "1px dashed var(--stroke-2)",
      borderRadius: 8,
      padding: "28px 24px",
      background: "rgba(240,192,64,.02)",
      color: "var(--fg-3)",
      display: "flex", flexDirection: "column", gap: 6,
      maxWidth: 620,
    }}>
      <span className="eyebrow" style={{ margin: 0, color: "var(--accent-deep)" }}>To be written</span>
      <div style={{
        fontFamily: "var(--font-key)", fontWeight: 700, fontSize: 18,
        textTransform: "uppercase", letterSpacing: ".05em", color: "var(--fg-2)",
      }}>{title}</div>
      {note && <div style={{ fontSize: 13, lineHeight: 1.5 }}>{note}</div>}
    </div>
  );
}

Object.assign(window, {
  SiteHeader, SiteFooter, K, KSeq, TopicCard, DocsSidebar, Placeholder
});


