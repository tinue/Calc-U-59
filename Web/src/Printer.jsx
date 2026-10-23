// The PC-100C panel (Qt6/app/PrinterWidget, App/Views/PrinterView): header
// with the connect pill (connecting resets) and the dot/text toggle; the
// paper strip, newest line at the bottom, drawn as dots at the printer's
// proportions — only the lines in view — or as text; PRINT and ADV act on
// press and release, T latches TRACE, copy puts the text and a 600 dpi
// image on the clipboard, cut copies and clears.

const PAPER_DOT = "rgb(31,31,31)";

function Toast({ text }) {
  return text ? <div className="calcu-toast" role="status">{text}</div> : null;
}

function PaperDots({ geo, printer }) {
  const scrollRef = React.useRef(null);
  const canvasRef = React.useRef(null);
  const [size, setSize] = React.useState({ w: 0, h: 0 });
  const tops = React.useMemo(() => stripTops(printer.lines), [printer.version]);

  React.useEffect(() => {
    const el = scrollRef.current;
    const ro = new ResizeObserver(() => setSize({ w: el.clientWidth, h: el.clientHeight }));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const stripW = Math.max(0, size.w - 2 * geo.paddingX);
  const pitch = stripW / geo.widthUnits;
  const stripH = printer.heightUnits * pitch + 2 * geo.paddingY;

  const draw = () => {
    const el = scrollRef.current, canvas = canvasRef.current;
    if (!el || !canvas || size.w === 0) return;
    const ctx = sizeCanvas(canvas, size.w, size.h);
    ctx.clearRect(0, 0, size.w, size.h);
    // The strip sits at the bottom while it is shorter than the view.
    const offset = Math.max(0, size.h - stripH);
    const top = el.scrollTop - offset - geo.paddingY;
    ctx.save();
    ctx.translate(geo.paddingX, -top);
    paintStrip(ctx, printer.lines, tops, pitch, geo, PAPER_DOT, top, top + size.h);
    ctx.restore();
  };

  // Keep the newest line in view.
  React.useLayoutEffect(() => {
    const el = scrollRef.current;
    el.scrollTop = el.scrollHeight;
    draw();
  }, [printer.version, size.w, size.h]);

  return (
    <div className="calcu-paper">
      <canvas ref={canvasRef} className="calcu-paper-canvas" style={{ width: size.w, height: size.h }} aria-hidden="true" />
      <div className="calcu-paper-scroll" ref={scrollRef} onScroll={draw}>
        <div style={{ height: Math.max(stripH, size.h) }} />
      </div>
    </div>
  );
}

function PaperText({ printer }) {
  const ref = React.useRef(null);
  React.useLayoutEffect(() => { ref.current.scrollTop = ref.current.scrollHeight; }, [printer.version]);
  return <pre className="calcu-paper calcu-paper-text" ref={ref}>{printer.lines.map((l) => l.text).join("\n")}</pre>;
}

async function copyStrip(geo, printer) {
  const text = printer.lines.map((l) => l.text).join("\n");
  const px = printer.copyPixelsPerUnit;
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(geo.widthUnits * px);
  canvas.height = Math.max(1, Math.round(printer.heightUnits * px));
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = "#fff";
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  paintStrip(ctx, printer.lines, stripTops(printer.lines), px, geo, "#000", 0, canvas.height);
  try {
    const png = await new Promise((resolve) => canvas.toBlob(resolve, "image/png"));
    await navigator.clipboard.write([new ClipboardItem({
      "text/plain": new Blob([text], { type: "text/plain" }),
      "image/png": png,
    })]);
  } catch (e) {
    await navigator.clipboard.writeText(text);  // no image clipboard here
  }
}

function HoldButton({ onHold, children, ...rest }) {
  return (
    <button
      type="button"
      onPointerDown={(e) => { e.currentTarget.setPointerCapture(e.pointerId); onHold(true); }}
      onPointerUp={() => onHold(false)}
      onPointerCancel={() => onHold(false)}
      onKeyDown={(e) => { if ((e.key === " " || e.key === "Enter") && !e.repeat) onHold(true); }}
      onKeyUp={(e) => { if (e.key === " " || e.key === "Enter") onHold(false); }}
      {...rest}
    >{children}</button>
  );
}

function Printer({ engine }) {
  const data = useEngine(engine, (s) => s.data);
  const printer = useEngine(engine, (s) => s.printer);
  const [textView, setTextView] = React.useState(false);
  const [toast, setToast] = React.useState("");
  const [narrow, setNarrow] = React.useState(false);
  const rootRef = React.useRef(null);
  const dot = (on) => (on ? "●" : "○");
  const empty = printer.lines.length === 0;

  React.useEffect(() => {
    const el = rootRef.current;
    const ro = new ResizeObserver(() => setNarrow(el.clientWidth < 180));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const showToast = (t) => { setToast(t); setTimeout(() => setToast(""), 1800); };
  const copy = () => copyStrip(data.printer, printer).then(() => showToast("Copied to clipboard"), () => showToast("Copy failed"));

  return (
    <div className="calcu-printer" data-panel="printer" ref={rootRef}>
      <div className="calcu-printer-header">
        <span />
        <button type="button" className="calcu-pill" aria-pressed={printer.connected}
          title="Connect or disconnect the PC-100C (resets the calculator)"
          onClick={() => engine.call("setPrinterConnected", !printer.connected)}>
          PC-100C <span className={printer.connected ? "calcu-dot-on" : ""}>{dot(printer.connected)}</span>
        </button>
        <button type="button" className="calcu-iconbutton" aria-label={textView ? "Dot view" : "Text view"}
          onClick={() => setTextView(!textView)}>{textView ? "•••" : "☰"}</button>
      </div>
      {data && !textView && <PaperDots geo={data.printer} printer={printer} />}
      {data && textView && <PaperText printer={printer} />}
      <div className="calcu-printer-bar">
        <HoldButton className="calcu-pill" onHold={(p) => engine.call("pressPrinterPrint", p)}>{narrow ? "PRN" : "PRINT"}</HoldButton>
        <button type="button" className="calcu-pill" aria-pressed={printer.trace} title="TRACE"
          onClick={() => engine.call("togglePrinterTrace")}>T {dot(printer.trace)}</button>
        <HoldButton className="calcu-pill" onHold={(p) => engine.call("pressPrinterAdv", p)}>ADV</HoldButton>
        <span className="calcu-spacer" />
        <button type="button" className="calcu-pill" disabled={empty} title="Copy" aria-label="Copy" onClick={copy}>⧉</button>
        <button type="button" className="calcu-pill" disabled={empty} title="Cut" aria-label="Cut"
          onClick={() => copy().finally(() => engine.call("cutPaper"))}>✂</button>
      </div>
      <Toast text={toast} />
    </div>
  );
}
