// Calc-U 59 — Reusable components for the help site (React 18 + Babel)

const { useState, useEffect, useRef, useMemo } = React;

/* =============================================================
   Header / nav
   ============================================================= */
function SiteHeader({ page }) {
  // Real paths, not #hashes: every one of these is a static HTML file on
  // disk, so they are crawlable links first and SPA transitions second
  // (site.jsx intercepts the click).
  const items = [
    { id: "home",     label: "Overview",        href: "/" },
    { id: "start",    label: "Getting Started", href: "/getting-started/" },
    { id: "play",     label: "Play",            href: "/play/" },
    { id: "ref",      label: "App Reference",   href: "/reference/" },
    { id: "modules",  label: "Modules",         href: "/modules/" },
    { id: "faq",      label: "FAQ",             href: "/faq/" },
  ];
  // Under 1060px the links collapse behind a disclosure button (styles.css).
  // They are hidden with CSS rather than unmounted, so the markup a crawler
  // gets from .seo/build.js is identical on both layouts.
  const [menuOpen, setMenuOpen] = useState(false);

  // site.jsx navigates without a reload, so nothing else would ever close
  // the panel — it would sit open on top of the page it just opened.
  useEffect(() => { setMenuOpen(false); }, [page]);

  return (
    <header className="site-header">
      <div className="inner">
        <a className="brand" href="/">
          <img className="app-icon" src="/assets/app-icon.png" alt="Calc-U 59 — TI-59 emulator app icon" />
          <div className="wm">
            <span className="top">Calc-U <em>59</em></span>
            <span className="sub">User Guide</span>
          </div>
        </a>
        <button
          type="button"
          className="nav-toggle"
          aria-expanded={menuOpen}
          aria-controls="site-nav"
          aria-label={menuOpen ? "Close menu" : "Open menu"}
          onClick={() => setMenuOpen(open => !open)}>
          {/* Three bars drawn in CSS. No icon library, per the design rules. */}
          <span className="nav-toggle-bars" aria-hidden="true"><i /><i /><i /></span>
        </button>
        {/* Closes on any click inside: an in-site link is intercepted into an
            SPA transition, and an external one leaves anyway. */}
        <div id="site-nav"
             className={menuOpen ? "nav-panel open" : "nav-panel"}
             onClick={() => setMenuOpen(false)}>
          <nav className="nav">
            {items.map(i => (
              <a key={i.id}
                 href={i.href}
                 className={page === i.id ? "active" : ""}>
                {i.label}
              </a>
            ))}
            <a href="https://github.com/tinue/Calc-U-59">Github</a>
          </nav>
          <a className="nav-cta" href="https://apps.apple.com/us/app/calc-u-59/id6761413142" title="Calc-U 59 TI-59 emulator on the App Store">App Store</a>
        </div>
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
        <a href="/what-is-a-ti-59/">What is a TI-59?</a>
        <a href="/play/">Online emulator</a>
        <a href="https://github.com/tinue/Calc-U-59">GitHub</a>
        <a href="https://github.com/tinue/Calc-U-59/blob/main/CHANGELOG.md">Release notes</a>
        <a href="https://github.com/tinue/Calc-U-59/blob/main/PRIVACY.md">Privacy</a>
        <span className="credits">© 2026 · TI-59, TI-58 and TI-58C emulator for Mac, iPhone and iPad</span>
        <p className="disclaimer">
          Calc-U 59 is an independent project and is not affiliated with, authorized,
          or endorsed by Texas Instruments. “TI-59”, “TI-58”, “TI-58C”, “Texas
          Instruments”, “Solid State Software”, and “Master Library” are trademarks of
          their respective owners, used here for descriptive purposes only.
        </p>
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
// Renders as a real <a href> when given one — same chrome as before, but
// the card becomes a crawlable internal link instead of a click handler
// that only exists once JavaScript has run.
function TopicCard({ num, eyebrow, title, children, href, onClick }) {
  const Tag = href ? "a" : "div";
  return (
    <Tag className="panel" href={href} onClick={onClick}
         style={{
           cursor: (href || onClick) ? "pointer" : "default",
           display: "flex", flexDirection: "column", gap: 10,
           transition: "border-color .15s, transform .15s",
           textDecoration: "none", color: "inherit",
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
    </Tag>
  );
}

/* =============================================================
   Docs sidebar (used on docs pages; placeholder right now)
   ============================================================= */
function DocsSidebar({ current, onPick, sections }) {
  return (
    // Sizing lives in styles.css (.docs-sidebar) so the 900px breakpoint can
    // turn the rail into a full-width block above the article.
    <aside className="docs-sidebar">
      {sections.map(sec => (
        <div key={sec.title} style={{ marginBottom: 24 }}>
          <div className="eyebrow" style={{ marginBottom: 6, color: "var(--fg-3)" }}>{sec.title}</div>
          <ul style={{ listStyle: "none", padding: 0, margin: 0 }}>
            {sec.items.map(it => (
              <li key={it.id}>
                <a
                  href={it.href || ("/getting-started/" + it.id + "/")}
                  {...(it.external
                    ? { target: "_blank", rel: "noopener" }
                    : it.jump
                      // A real navigation to another page, not an in-page topic
                      // switch: no onClick of our own, so the click falls through
                      // to site.jsx's delegated listener, which already intercepts
                      // any same-site <a href> into an SPA transition.
                      ? {}
                      : { onClick: e => { e.preventDefault(); onPick(it.id); } })}
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


