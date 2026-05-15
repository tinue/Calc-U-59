// Calc-U 59 — Help site pages
// User scope: this guide explains the EMULATOR APP, not the underlying
// TI-59 calculator hardware.

const { useState: useStateApp } = React;

const STARTED_SECTIONS = [
  { title: "Setup", items: [
    { id: "install-mobile", label: "Installing on iPhone and iPad" },
    { id: "install-mac", label: "Installing on Mac" },
  ]},
  { title: "Using the emulator", items: [
    { id: "state-files", label: "Loading a state file" },
    { id: "debugger", label: "Using the debugger" },
    { id: "printer", label: "Printer and card reader" },
  ]},
  { title: "Help", items: [
    { id: "faq", label: "FAQ" },
    { id: "readme", label: "Main README" },
  ]},
];

function BackButton({ label = "← Return to start", onNav, fallback = "home" }) {
  function handleBack() {
    if (history.length > 1) { history.back(); }
    else { onNav(fallback); }
  }
  return <button className="btn secondary" onClick={handleBack}>{label}</button>;
}

/* =============================================================
   HOME — overview page.
   ============================================================= */
function HomePage({ onNav }) {
  return (
    <main>
      {/* Hero */}
      <section style={{ borderBottom: "1px solid var(--stroke)" }}>
        <div className="wrap" style={{
          display: "grid", gridTemplateColumns: "1.1fr auto", gap: 64,
          alignItems: "center", paddingTop: 56, paddingBottom: 56,
        }}>
          <div>
            <p className="eyebrow">User guide</p>
            <h1 className="page-title">Calc-U <em>59</em></h1>
            <p className="lede">This guide is for the <strong style={{ color: "var(--fg)" }}>emulator app</strong>: installing it, loading state files, using the printer and debug tools, and understanding the settings that affect a session. It deliberately avoids the original TI-59 operating manual.</p>
            <div style={{ display: "flex", gap: 12 }}>
              <button className="btn primary" onClick={() => onNav("start")}>Getting started <span style={{opacity:.5}}>→</span></button>
              <button className="btn secondary" onClick={() => onNav("ref")}>App reference</button>
            </div>
            <div style={{
              marginTop: 20,
              display: "grid",
              gridTemplateColumns: "repeat(2, minmax(0, 1fr))",
              gap: 12,
            }}>
              <div className="panel" style={{ padding: 16 }}>
                <h3 className="sub" style={{ margin: "0 0 6px" }}>iPhone and iPad</h3>
                <p style={{ margin: 0, fontSize: 14, lineHeight: 1.6 }}>
                  Install from the App Store, then open the app and pick a model. State files load from the file picker inside the app.
                </p>
              </div>
              <div className="panel" style={{ padding: 16 }}>
                <h3 className="sub" style={{ margin: "0 0 6px" }}>Mac</h3>
                <p style={{ margin: 0, fontSize: 14, lineHeight: 1.6 }}>
                  Download the release from GitHub, drag the app to Applications, then use right-click <strong>Open</strong> the first time if macOS blocks it.
                </p>
              </div>
            </div>
          </div>
          <div style={{ display: "flex", justifyContent: "center" }}>
            <img
              src="assets/app-screenshot.png"
              alt="Calc-U 59 running on iPhone"
              style={{
                height: 620,
                width: "auto",
                display: "block",
                borderRadius: 44,
                boxShadow: "0 10px 40px rgba(0,0,0,.7), 0 0 0 1px rgba(255,200,100,.06)",
              }}
            />
          </div>
        </div>
      </section>

      {/* Topic cards */}
      <div className="wrap">
        <h2 className="section">Where to start</h2>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 16 }}>
          <TopicCard num="01" eyebrow="Setup" title="Installing on iPhone and iPad" onClick={() => onNav("install-mobile")}>
            The App Store install path, plus what happens on first launch.
          </TopicCard>
          <TopicCard num="02" eyebrow="Setup" title="Installing on Mac" onClick={() => onNav("install-mac")}>
            GitHub Releases, the DMG, and Gatekeeper the first time you open the app.
          </TopicCard>
          <TopicCard num="03" eyebrow="Files" title="Loading a state file" onClick={() => onNav("state-files")}>
            What a .ti59 file contains and how the parser treats each section.
          </TopicCard>
          <TopicCard num="04" eyebrow="Debug" title="Using the debugger" onClick={() => onNav("debugger") }>
            LIVE, CPU, LOG, freeze/step, and the binary trace file.
          </TopicCard>
          <TopicCard num="05" eyebrow="Hardware" title="Printer and card reader" onClick={() => onNav("ref")}>
            What the PC-100C panel does and how card files are managed.
          </TopicCard>
          <TopicCard num="06" eyebrow="Help" title="FAQ" onClick={() => onNav("faq")}>
            Answers to the questions users actually hit first.
          </TopicCard>
        </div>

        {/* App-icon strip */}
        <div className="panel" style={{
          marginTop: 48, display: "flex", alignItems: "center", gap: 24,
        }}>
          <img src="assets/app-icon.png" alt=""
               style={{ width: 80, height: 80, borderRadius: 18, flex: "0 0 auto" }}/>
          <div>
            <h3 className="sub" style={{ margin: "0 0 4px" }}>Available now</h3>
            <p style={{ margin: 0, fontSize: 14 }}>
              The Mac build ships from GitHub Releases. The mobile build is installed from the App Store.
            </p>
          </div>
        </div>
      </div>
    </main>
  );
}

/* =============================================================
   GETTING STARTED — practical install, file, and debug guidance.
   ============================================================= */
function GettingStartedPage({ initialTopic = "install-mobile", onNav }) {
  const [topic, setTopic] = useStateApp(initialTopic);

  function handlePick(id) {
    setTopic(id);
    if (onNav) onNav({ page: "start", topic: id });
  }
  const titles = {
    "install-mobile": "Installing on iPhone and iPad",
    "install-mac": "Installing on Mac",
    "state-files": "Loading a state file",
    debugger: "Using the debugger",
    printer: "Printer and card reader",
    faq: "FAQ",
    readme: "Main README",
  };
  const notes = {
    "install-mobile": "Use the App Store build, then configure the model and load presets from inside the app.",
    "install-mac": "Download the release from GitHub, then drag the app to Applications.",
    "state-files": "What .ti59/.ti58/.ti58c files contain and how the parser treats each section.",
    debugger: "LIVE, CPU, LOG, freeze/step, and binary trace output.",
    printer: "The PC-100C panel, paper strip, copy/cut, and card file behaviour.",
    faq: "Concise answers to the questions that usually come up first.",
    readme: "Complete project overview, build instructions, and technical documentation.",
  };

  const stateFileExample = `PARTITION: 479
PROGRAM:
002 76 11 42 00
...
REGISTERS:
00 = 1.2345
H00 = 9.999
KEYSTROKES:
21 84 65 83 95
Wait: 1s
CUECARD:
SOLID-STATE-MODULE: ML
PRINTER: on`;

  const topicBody = {
    "install-mobile": (
      <div style={{ display: "grid", gap: 16, marginTop: 20 }}>
        <div className="panel" style={{ padding: 20 }}>
          <h3 className="sub" style={{ marginTop: 0 }}>iPhone and iPad</h3>
          <ol style={{ margin: 0, paddingLeft: 20, lineHeight: 1.7 }}>
            <li>Open the App Store and install Calc-U 59.</li>
            <li>Launch the app and choose the calculator model in the toolbar or Settings.</li>
            <li>Use the preset file picker for .ti59, .ti58, or .ti58c files.</li>
          </ol>
          <p style={{ marginBottom: 0, lineHeight: 1.65 }}>
            The mobile build uses the standard iOS app flow: there is no special setup beyond the App Store install.
          </p>
        </div>
      </div>
    ),
    "install-mac": (
      <div style={{ display: "grid", gap: 16, marginTop: 20 }}>
        <div className="panel" style={{ padding: 20 }}>
          <h3 className="sub" style={{ marginTop: 0 }}>Mac</h3>
          <ol style={{ margin: 0, paddingLeft: 20, lineHeight: 1.7 }}>
            <li>Download the latest release DMG from GitHub.</li>
            <li>Drag Calc-U-59.app to Applications.</li>
            <li>On first launch, use right-click <strong>Open</strong> if Gatekeeper intervenes.</li>
          </ol>
          <p style={{ marginBottom: 0, lineHeight: 1.65 }}>
            After that, macOS treats the app like any other notarized application.
          </p>
        </div>
      </div>
    ),
    "state-files": (
      <div style={{ display: "grid", gap: 16, marginTop: 20 }}>
        <div className="panel" style={{ padding: 20 }}>
          <p style={{ marginTop: 0, lineHeight: 1.7 }}>
            State files are plain UTF-8 text. The parser understands a small set of section headers and ignores comments after <strong>#</strong>.
            You can include only the sections you need.
          </p>
          <pre style={{
            margin: 0,
            padding: 16,
            borderRadius: 8,
            background: "var(--bg-inset)",
            color: "var(--fg)",
            overflowX: "auto",
            lineHeight: 1.5,
            fontSize: 13,
          }}>{stateFileExample}</pre>
        </div>
        <div className="panel" style={{ padding: 20, lineHeight: 1.7 }}>
          <p style={{ marginTop: 0 }}><strong>PARTITION:</strong> sets the step split between program memory and data registers. If it is omitted, the emulator uses the model default.</p>
          <p><strong>PROGRAM:</strong> accepts sparse step listings, numeric keycodes, and the <strong>...</strong> gap marker.</p>
          <p><strong>REGISTERS:</strong> stores calculator variables as decimal numbers. On TI-58C, hidden registers can be written as <strong>H00</strong> through <strong>H03</strong>.</p>
          <p><strong>KEYSTROKES:</strong> injects matrix codes after the file loads. Wait lines are allowed between groups.</p>
          <p><strong>CUECARD:</strong> defines the on-screen cue card that appears with the loaded file or module.</p>
          <p style={{ marginBottom: 0 }}><strong>SOLID-STATE-MODULE:</strong> and <strong>PRINTER:</strong> let a file select the matching module and printer state automatically.</p>
        </div>
      </div>
    ),
    debugger: (
      <div style={{ display: "grid", gap: 16, marginTop: 20 }}>
        <div className="panel" style={{ padding: 20, lineHeight: 1.7 }}>
          <p style={{ marginTop: 0 }}>
            The debug pane has three tabs: <strong>LIVE</strong>, <strong>CPU</strong>, and <strong>LOG</strong>.
            LIVE is the real-time calculator view, CPU is the instruction-level inspector, and LOG shows printable debug output plus trace controls.
          </p>
          <p>
            Freeze the machine when you want to inspect a specific moment. While frozen, the CPU tab shows a scrollable history with step and resume controls.
          </p>
          <p style={{ marginBottom: 0 }}>
            Use the trace button when you need a binary session file for deeper analysis. The emulator writes <strong>TI59_TRACE.bin</strong> or the model-specific equivalent to the configured trace folder.
          </p>
        </div>
        <div className="panel" style={{ padding: 20, lineHeight: 1.7 }}>
          <p style={{ marginTop: 0 }}>
            Good ways to use the debugger:
          </p>
          <ol style={{ margin: 0, paddingLeft: 20 }}>
            <li>Check the LIVE tab for current registers, flags, and display state.</li>
            <li>Freeze before a difficult instruction and step forward one instruction at a time.</li>
            <li>Turn on TRACE only when you need the binary capture, then turn it off again so the file stays small.</li>
          </ol>
        </div>
      </div>
    ),
    printer: (
      <div style={{ display: "grid", gap: 16, marginTop: 20 }}>
        <div className="panel" style={{ padding: 20, lineHeight: 1.7 }}>
          <p style={{ marginTop: 0 }}>
            The printer view mimics the PC-100C. Use the on/off badge at the top of the printer view to connect or disconnect it, then switch between dot view and text view depending on whether you want realism or easy copying.
          </p>
          <p>
            <strong>PRINT</strong> feeds output, <strong>ADV</strong> advances the paper, and the copy and cut buttons are available on all builds (including iOS and iPadOS) for clipboard/export work.
          </p>
          <p style={{ marginBottom: 0 }}>
            If you enable printer trace in the app, the emulator records printer activity together with the rest of the session state.
          </p>
        </div>
        <div className="panel" style={{ padding: 20, lineHeight: 1.7 }}>
          <p style={{ marginTop: 0, marginBottom: 0 }}>
            Card files live in the app’s card storage and can be loaded or saved from the card picker. The app filters the visible files to the supported card extensions and hides the iCloud placeholder entries.
          </p>
        </div>
      </div>
    ),
    faq: (
      <div style={{ display: "grid", gap: 8, marginTop: 20 }}>
        {[
          { q: "Where do state files live?", a: "They are regular .ti59, .ti58, or .ti58c text files. On Mac, the preset picker opens them from disk; on iPhone and iPad, use the built-in file picker." },
          { q: "What should I check first if a file opens wrong?", a: "Check the partition, then the selected module, then the printer setting. Those three control the most visible parts of a loaded preset." },
          { q: "Can I see what the emulator is doing internally?", a: "Yes. Use the debug pane: LIVE for real-time state, CPU for instruction history, and LOG for text output plus trace controls." },
          { q: "How do I get a trace file?", a: "Open the debug pane, switch to LOG, and turn TRACE on. The app writes a binary session file to the configured trace location." },
          { q: "Why does the display look different between models?", a: "Calc-U 59 can start in TI-59, TI-58, or TI-58C mode. The model affects the startup state, memory layout, and the available controls." },
          { q: "Is there a faster way to read long printer output?", a: "Yes. Switch the printer view to text mode, then copy or cut the strip on any build if you want a plain-text version quickly." },
        ].map((item, i) => (
          <div key={i} className="panel" style={{ padding: "16px 20px", display: "grid", gap: 8 }}>
            <span style={{ fontFamily: "var(--font-key)", fontWeight: 700, fontSize: 16, textTransform: "uppercase", letterSpacing: ".05em", color: "var(--fg)" }}>{item.q}</span>
            <p style={{ margin: 0, lineHeight: 1.7, color: "var(--fg-2)" }}>{item.a}</p>
          </div>
        ))}
      </div>
    ),
    readme: (
      <div style={{ display: "grid", gap: 16, marginTop: 20 }}>
        <div className="panel" style={{ padding: 20, lineHeight: 1.7 }}>
          <p style={{ marginTop: 0 }}>
            The main README on GitHub contains the complete project overview, build instructions, technical architecture, and development guidelines.
          </p>
          <p style={{ marginBottom: 0 }}>
            <a href="https://github.com/tinue/Calc-U-59/blob/main/README.md" style={{ color: "var(--accent)", textDecoration: "none", borderBottom: "1px solid var(--accent)" }}>View the README on GitHub →</a>
          </p>
        </div>
      </div>
    ),
  };

  return (
    <main className="wrap" style={{ display: "flex", gap: 32, alignItems: "flex-start" }}>
      <DocsSidebar current={topic} onPick={handlePick} sections={STARTED_SECTIONS} />
      <article style={{ flex: 1, minWidth: 0 }} className="prose">
        <p className="eyebrow">Getting started</p>
        <h1 className="page-title" style={{ fontSize: 40 }}>{titles[topic]}</h1>
        <p className="lede">{notes[topic]}</p>
        {topicBody[topic]}
      </article>
    </main>
  );
}

/* =============================================================
   DETAIL PAGES — dedicated targets for home topic cards.
   ============================================================= */
function InstallMobilePage({ onNav }) {
  return (
    <main className="wrap-narrow">
      <p className="eyebrow">Setup</p>
      <h1 className="page-title">Installing on iPhone and iPad</h1>
      <p className="lede">Use the App Store build, then configure the model and load presets from inside the app.</p>

      <div className="panel" style={{ padding: 20, lineHeight: 1.7, marginTop: 24 }}>
        <ol style={{ margin: 0, paddingLeft: 20 }}>
          <li>Open the <a href="https://apps.apple.com/us/app/calc-u-59/id6761413142" style={{ color: "var(--accent)", textDecoration: "none", borderBottom: "1px solid var(--accent)" }}>App Store</a> and install Calc-U 59.</li>
          <li>Launch the app and choose the calculator model in the toolbar or Settings.</li>
          <li>Use the preset file picker for .ti59, .ti58, or .ti58c files.</li>
        </ol>
      </div>

      <div className="panel" style={{ padding: 20, lineHeight: 1.7, marginTop: 12 }}>
        <p style={{ marginTop: 0 }}>
          The mobile build follows the standard iOS app flow: there is no extra setup after install.
        </p>
        <p style={{ marginBottom: 0 }}>
          On iPhone and on iPad in portrait, the calculator uses the same key layout as the app screenshot; on iPad in landscape, the layout mirrors the Mac view.
        </p>
      </div>

      <div style={{ marginTop: 24 }}>
        <BackButton onNav={onNav} />
      </div>
    </main>
  );
}

function InstallMacPage({ onNav }) {
  return (
    <main className="wrap-narrow">
      <p className="eyebrow">Setup</p>
      <h1 className="page-title">Installing on Mac</h1>
      <p className="lede">Download the release from GitHub, then drag the app to Applications. On first launch, use right-click <strong>Open</strong> if Gatekeeper blocks it.</p>

      <div className="panel" style={{ padding: 20, lineHeight: 1.7, marginTop: 24 }}>
        <ol style={{ margin: 0, paddingLeft: 20 }}>
          <li>Download the latest release DMG from <a href="https://github.com/tinue/Calc-U-59/releases/latest" style={{ color: "var(--accent)", textDecoration: "none", borderBottom: "1px solid var(--accent)" }}>GitHub</a>.</li>
          <li>Double-click the DMG file to open it and show the installer window.</li>
          <li>Drag Calc-U-59.app to the Applications folder.</li>
          <li>Eject the disk image and launch the app from Applications.</li>
          <li>On first launch, if macOS blocks the app with a Gatekeeper prompt, right-click the app icon and choose <strong>Open</strong> to approve it.</li>
        </ol>
      </div>

      <div className="panel" style={{ padding: 20, lineHeight: 1.7, marginTop: 12 }}>
        <p style={{ margin: 0 }}>
          After first approval, macOS treats the app like any other notarized application. You can then open it normally with a double-click.
        </p>
      </div>

      <div style={{ marginTop: 24 }}>
        <BackButton onNav={onNav} />
      </div>
    </main>
  );
}

function StateFilesPage({ onNav }) {
  const stateFileExample = `# 800 steps, 19 data registers (R00–R19) — "2 OP 17"
PARTITION: 799.19
# Magnetic card with one Label
CUECARD:
Template: MagnetCard
Title: Example
Banks: 1,2
A: Start
# Load the Master Library
SOLID-STATE-MODULE: ML
# Force Printer On
PRINTER: on
# Program Listing
PROGRAM:
001  76  LBL
002  11. A
003  89  π
004  95  =
005  91  R/S
# Data Registers
REGISTERS:
00 = 3.141592653589793   # π  (verify RCL 00 → 3.141592654)
# Type some keys after load / reset
KEYSTROKES:
84   3
11   A
Wait: 2s
43   RCL
92   0
92   0`;

  return (
    <main className="wrap-narrow">
      <p className="eyebrow">Files</p>
      <h1 className="page-title">Loading a state file</h1>
      <p className="lede">State files are plain UTF-8 text with named sections. You can include only the sections you need.</p>

      <div className="panel" style={{ padding: 20, marginTop: 24 }}>
        <pre style={{
          margin: 0,
          padding: 16,
          borderRadius: 8,
          background: "var(--bg-inset)",
          color: "var(--fg)",
          overflowX: "auto",
          lineHeight: 1.5,
          fontSize: 13,
        }}>{stateFileExample}</pre>
      </div>

      <div className="panel" style={{ padding: 20, lineHeight: 1.7, marginTop: 12 }}>
        <p style={{ marginTop: 0 }}><strong>PARTITION:</strong> sets the step split between program memory and data registers.</p>
        <p><strong>PROGRAM:</strong> accepts sparse step listings, numeric keycodes, and the <strong>...</strong> gap marker.</p>
        <p><strong>REGISTERS:</strong> stores calculator variables as decimal numbers.</p>
        <p><strong>KEYSTROKES:</strong> injects matrix codes after the file loads. Wait lines are allowed between groups.</p>
        <p><strong>CUECARD:</strong> defines the on-screen cue card that appears with the loaded file or module.</p>
        <p style={{ marginBottom: 0 }}><strong>SOLID-STATE-MODULE:</strong> and <strong>PRINTER:</strong> let a file select the matching module and printer state automatically.</p>
      </div>

      <div style={{ marginTop: 24 }}>
        <BackButton onNav={onNav} />
      </div>
    </main>
  );
}

function DebuggerPage({ onNav }) {
  return (
    <main className="wrap-narrow">
      <p className="eyebrow">Debug</p>
      <h1 className="page-title">Using the debugger</h1>
      <p className="lede">The debug pane combines real-time calculator state, instruction history, and trace capture in one place.</p>

      <div className="panel" style={{ padding: 20, lineHeight: 1.7, marginTop: 24 }}>
        <p style={{ marginTop: 0 }}>
          The debug pane has three tabs: <strong>LIVE</strong>, <strong>CPU</strong>, and <strong>LOG</strong>.
          LIVE is the real-time calculator view, CPU is the instruction-level inspector, and LOG shows printable debug output plus trace controls.
        </p>
        <p>
          Freeze the machine when you want to inspect a specific moment. While frozen, the CPU tab shows a scrollable history with step and resume controls.
        </p>
        <p style={{ marginBottom: 0 }}>
          Use the trace toggle when you need a binary session file for deeper analysis.
        </p>
      </div>

      <div className="panel" style={{ padding: 20, lineHeight: 1.7, marginTop: 12 }}>
        <p style={{ marginTop: 0 }}>Good ways to use the debugger:</p>
        <ol style={{ margin: 0, paddingLeft: 20 }}>
          <li>Check the LIVE tab for current registers, flags, and display state.</li>
          <li>Freeze before a difficult instruction and step forward one instruction at a time.</li>
          <li>Turn on TRACE only when you need binary capture, then turn it off again to keep files small.</li>
        </ol>
      </div>

      <div style={{ marginTop: 16, display: "grid", gap: 12 }}>
        <div className="panel" style={{ padding: 16 }}>
          <h3 className="sub" style={{ margin: "0 0 10px" }}>LIVE tab</h3>
          <img
            src="assets/ipad-13-2752x2064.png"
            alt="iPad screenshot showing the LIVE debug tab"
            style={{ width: "100%", height: "auto", display: "block", borderRadius: 8 }}
          />
        </div>
        <div className="panel" style={{ padding: 16 }}>
          <h3 className="sub" style={{ margin: "0 0 10px" }}>CPU tab</h3>
          <img
            src="assets/ipad-2752x2064-asm.png"
            alt="iPad screenshot showing the CPU debug tab"
            style={{ width: "100%", height: "auto", display: "block", borderRadius: 8 }}
          />
        </div>
      </div>

      <div style={{ marginTop: 24 }}>
        <BackButton onNav={onNav} />
      </div>
    </main>
  );
}

/* =============================================================
   APP REFERENCE — emulator controls and screen regions.
   ============================================================= */
function ReferencePage({ onNav }) {
  return (
    <main className="wrap" style={{ display: "grid", gridTemplateColumns: "1fr 380px", gap: 48, alignItems: "flex-start" }}>
      <div>
        <p className="eyebrow">App Reference</p>
        <h1 className="page-title">Every control,<br/>annotated.</h1>
        <p className="lede">This page explains the emulator controls as they behave in the app: the calculator, the printer, the debug pane, and the settings that affect a session.</p>

        <h2 className="section">The calculator</h2>
        <div className="panel" style={{ padding: 20, lineHeight: 1.7 }}>
          <p style={{ marginTop: 0 }}>
            The calculator view is the main working surface. On iPhone and on iPad in portrait, it uses the same key layout as the app screenshot; on iPad in landscape, the layout mirrors the Mac view.
          </p>
          <p>
            The top display area shows the current number and status indicators, the cue card area directly beneath it shows module/context notes, and the keyboard area contains the full key matrix for normal operation.
          </p>
          <p style={{ marginBottom: 0 }}>
            Bottom toolbar (left to right): <strong>Reset</strong> (long press: <strong>Reset + Memory wipe</strong>), <strong>Model selector</strong> (TI-59/TI-58/TI-58C), <strong>Read Magnetic Card</strong>, <strong>Write Magnetic Card</strong>, <strong>Load State File</strong>, <strong>Settings</strong>.
          </p>
        </div>

        <h2 className="section">The printer</h2>
        <div className="panel" style={{ padding: 20, lineHeight: 1.7 }}>
          <p style={{ marginTop: 0 }}>
            The printer view has a PC-100C badge at the top, a dot/text toggle, and hardware-style buttons for print and advance. On all builds (including iOS and iPadOS), you can also copy the paper strip to the clipboard or cut it away when it gets too long.
          </p>
          <p style={{ marginBottom: 0 }}>
            The text view is useful when you want to read or copy output quickly. The dot view is the closer match to the physical printer.
          </p>
        </div>

        <h2 className="section">The debug pane</h2>
        <div className="panel" style={{ padding: 20, lineHeight: 1.7 }}>
          <p style={{ marginTop: 0 }}>
            The debug pane has three tabs: LIVE, CPU, and LOG. LIVE shows the current calculator state in real time. CPU switches to a live or frozen instruction inspector depending on whether the machine is paused. LOG is for text output, register dumps, trace toggles, and ASM overlay controls.
          </p>
          <p style={{ marginBottom: 0 }}>
            If you only need one thing from this pane, it is the trace toggle: it records a session file that can be used for deeper debugging later.
          </p>
        </div>

        <h2 className="section">Settings</h2>
        <div className="panel" style={{ padding: 20, lineHeight: 1.7 }}>
          <p style={{ marginTop: 0 }}>
            The settings sheet controls the startup model, the active Solid State module, keyboard feedback on iOS, the LED font style, and the trace-file location.
          </p>
          <p style={{ marginBottom: 0 }}>
            The trace-file size limit is also adjustable on macOS and on iPad in landscape so long debug sessions do not grow without bound. This mainly prevents iCloud storage overcommit when trace files are written to iCloud Drive.
          </p>
        </div>

        <div style={{ marginTop: 24 }}>
          <BackButton onNav={onNav} />
        </div>
      </div>

      <div style={{ position: "sticky", top: 96 }}>
        <div className="panel" style={{ padding: 14 }}>
          <div style={{ position: "relative" }}>
            <img
              src="assets/app-screenshot.png"
              alt="Calc-U 59 main app screenshot with annotated interface regions and toolbar buttons"
              style={{ width: "100%", height: "auto", display: "block", borderRadius: 10 }}
            />

            <div style={{ position: "absolute", top: "10%", left: "48%", transform: "translateX(-50%)", background: "rgba(0,0,0,.72)", color: "var(--accent)", border: "1px solid var(--accent)", borderRadius: 999, padding: "4px 8px", fontFamily: "var(--font-key)", fontSize: 11, letterSpacing: ".06em", textTransform: "uppercase" }}>Display</div>
            <div style={{ position: "absolute", top: "21%", left: "50%", transform: "translateX(-50%)", background: "rgba(0,0,0,.72)", color: "var(--accent)", border: "1px solid var(--accent)", borderRadius: 999, padding: "4px 8px", fontFamily: "var(--font-key)", fontSize: 11, letterSpacing: ".06em", textTransform: "uppercase" }}>Cue card</div>
            <div style={{ position: "absolute", top: "36%", left: "50%", transform: "translateX(-50%)", background: "rgba(0,0,0,.72)", color: "var(--accent)", border: "1px solid var(--accent)", borderRadius: 999, padding: "4px 8px", fontFamily: "var(--font-key)", fontSize: 11, letterSpacing: ".06em", textTransform: "uppercase" }}>Keyboard</div>

              <div style={{ position: "absolute", bottom: "2.1%", left: "6%", width: 22, height: 22, borderRadius: 999, background: "var(--accent)", color: "#21170f", fontFamily: "var(--font-key)", fontWeight: 700, fontSize: 12, display: "grid", placeItems: "center" }}>1</div>
              <div style={{ position: "absolute", bottom: "2.1%", left: "17%", width: 22, height: 22, borderRadius: 999, background: "var(--accent)", color: "#21170f", fontFamily: "var(--font-key)", fontWeight: 700, fontSize: 12, display: "grid", placeItems: "center" }}>2</div>
              <div style={{ position: "absolute", bottom: "2.1%", left: "62%", width: 22, height: 22, borderRadius: 999, background: "var(--accent)", color: "#21170f", fontFamily: "var(--font-key)", fontWeight: 700, fontSize: 12, display: "grid", placeItems: "center" }}>3</div>
              <div style={{ position: "absolute", bottom: "2.1%", left: "70%", width: 22, height: 22, borderRadius: 999, background: "var(--accent)", color: "#21170f", fontFamily: "var(--font-key)", fontWeight: 700, fontSize: 12, display: "grid", placeItems: "center" }}>4</div>
              <div style={{ position: "absolute", bottom: "2.1%", left: "80%", width: 22, height: 22, borderRadius: 999, background: "var(--accent)", color: "#21170f", fontFamily: "var(--font-key)", fontWeight: 700, fontSize: 12, display: "grid", placeItems: "center" }}>5</div>
              <div style={{ position: "absolute", bottom: "2.1%", left: "89%", width: 22, height: 22, borderRadius: 999, background: "var(--accent)", color: "#21170f", fontFamily: "var(--font-key)", fontWeight: 700, fontSize: 12, display: "grid", placeItems: "center" }}>6</div>
              <div style={{ position: "absolute", top: "6%", right: "8%", width: 22, height: 22, borderRadius: 999, background: "var(--accent)", color: "#21170f", fontFamily: "var(--font-key)", fontWeight: 700, fontSize: 12, display: "grid", placeItems: "center" }}>7</div>
          </div>

          <ol style={{ margin: "12px 0 0", paddingLeft: 20, lineHeight: 1.65, color: "var(--fg-2)", fontSize: 14 }}>
            <li><strong>Reset</strong> (long press: Reset + Memory wipe)</li>
            <li><strong>Model selector</strong> (TI-59 / TI-58 / TI-58C)</li>
            <li><strong>Read Magnetic Card</strong></li>
            <li><strong>Write Magnetic Card</strong></li>
            <li><strong>Load State File</strong></li>
            <li><strong>Settings</strong></li>
            <li><strong>Swipe to printer</strong></li>
          </ol>
        </div>
      </div>
    </main>
  );
}

/* =============================================================
   FAQ — direct answers.
   ============================================================= */
function FaqPage({ onNav }) {
  const faqs = [
    {
      question: "Where do state files live?",
      answer: "They are regular .ti59, .ti58, or .ti58c text files. On Mac, the preset picker opens them from disk; on iPhone and iPad, use the built-in file picker.",
    },
    {
      question: "What should I check first if a file opens wrong?",
      answer: "Check the partition, then the selected module, then the printer setting. Those three control the most visible parts of a loaded preset.",
    },
    {
      question: "Can I see what the emulator is doing internally?",
      answer: "Yes. Use the debug pane: LIVE for real-time state, CPU for instruction history, and LOG for text output plus trace controls.",
    },
    {
      question: "How do I get a trace file?",
      answer: "Open the debug pane, switch to LOG, and turn TRACE on. The app writes a binary session file to the configured trace location.",
    },
    {
      question: "Why does the display look different between models?",
      answer: "Calc-U 59 can start in TI-59, TI-58, or TI-58C mode. The model affects the startup state, memory layout, and the available controls.",
    },
    {
      question: "Is there a faster way to read long printer output?",
      answer: "Yes. Switch the printer view to text mode, then copy or cut the strip on any build if you want a plain-text version quickly.",
    },
  ];
  return (
    <main className="wrap-narrow">
      <p className="eyebrow">Help</p>
      <h1 className="page-title">FAQ</h1>
      <p className="lede">Concise answers to the questions that usually come up first.</p>
      <div style={{ display: "flex", flexDirection: "column", gap: 8, marginTop: 24 }}>
        {faqs.map((item, i) => (
          <div key={i} className="panel" style={{
            padding: "16px 20px",
            display: "grid", gap: 8,
          }}>
            <span style={{
              fontFamily: "var(--font-key)", fontWeight: 700, fontSize: 16,
              textTransform: "uppercase", letterSpacing: ".05em",
              color: "var(--fg)",
            }}>{item.question}</span>
            <p style={{ margin: 0, lineHeight: 1.7, color: "var(--fg-2)" }}>{item.answer}</p>
          </div>
        ))}
      </div>

      <div style={{ marginTop: 24 }}>
        <BackButton onNav={onNav} />
      </div>
    </main>
  );
}

function ModulesPage() {
  return (
    <main className="wrap-narrow" style={{ paddingTop: 48 }}>
      <Placeholder title="Modules" note="Coming soon." />
    </main>
  );
}

Object.assign(window, {
  HomePage,
  GettingStartedPage,
  InstallMobilePage,
  InstallMacPage,
  StateFilesPage,
  DebuggerPage,
  ReferencePage,
  ModulesPage,
  FaqPage,
});
