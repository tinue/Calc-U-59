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
            CALCULATOR, CPU, LOG, freeze/step, and the binary trace file.
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
    debugger: "CALCULATOR, CPU, LOG, freeze/step, and binary trace output.",
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
            The debug pane has three tabs: <strong>CALCULATOR</strong>, <strong>CPU</strong>, and <strong>LOG</strong>.
            CALCULATOR shows the program listing and live register state, CPU is the instruction trace inspector, and LOG displays raw debug output plus the trace capture toggle.
          </p>
          <p style={{ marginBottom: 0 }}>
            The most powerful feature is the TRACE toggle in LOG—it records a binary session file that you can export and analyze with the <code>read_trace.py</code> tool to understand ROM sequences in detail.
          </p>
        </div>
        <div className="panel" style={{ padding: 20, lineHeight: 1.7 }}>
          <p style={{ marginTop: 0 }}>
            Quick start:
          </p>
          <ol style={{ margin: 0, paddingLeft: 20 }}>
            <li>Use the CALCULATOR tab to inspect registers and step through your program.</li>
            <li>Switch to CPU if you want to trace the actual ROM instructions that ran (including jumps and subroutine calls).</li>
            <li>Use TRACE in the LOG tab to capture a longer sequence (reset, keystroke processing, etc.) for offline analysis.</li>
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
          { q: "Can I see what the emulator is doing internally?", a: "Yes. Use the debug pane: CALCULATOR for program state and live registers, CPU for the ROM instruction trace, and LOG for text output plus trace controls. For analyzing sequences, TRACE is more useful than the CPU tab." },
          { q: "How do I get a trace file?", a: "Open the debug pane, switch to LOG, and turn TRACE on. The app writes a binary session file to the configured trace location. You can then export it and analyze it with read_trace.py." },
          { q: "What does the CALCULATOR tab show versus the CPU tab?", a: "CALCULATOR shows the instruction that will execute next, with registers in their current state before it runs. CPU shows instructions that already ran, with registers in the state after each one. STEP and RESUME also work differently per tab and are only enabled in the tab that caused the current freeze — using them in the wrong tab is prevented." },
          { q: "My trace file is 190 MB. Is that normal?", a: "Yes, for long sessions. But when you convert it to text with read_trace.py using the --clean and --skip-repeating flags, it compresses to a fraction of that size because the tool deduplicates repetitive loops." },
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
      <p className="lede">The debug pane combines a program-level view, a CPU-level instruction trace, and a trace capture tool for analyzing the emulator's behavior in detail.</p>

      <div className="panel" style={{ padding: 20, lineHeight: 1.7, marginTop: 24 }}>
        <h3 className="sub" style={{ marginTop: 0, marginBottom: 12 }}>Overview</h3>
        <p style={{ margin: 0 }}>
          The debug pane has three tabs: <strong>CALCULATOR</strong>, <strong>CPU</strong>, and <strong>LOG</strong>.
        </p>
        <ul style={{ margin: "8px 0 0", paddingLeft: 20 }}>
          <li><strong>CALCULATOR</strong> — Program listing (copied from RAM), registers, flags, and HIR values at the current moment. Shows the instruction that will execute <em>next</em>. Useful for stepping through your own programs.</li>
          <li><strong>CPU</strong> — Execution trace: the actual sequence of ROM instructions that ran. Shows the instruction that just <em>finished</em> and the register state <em>after</em> it executed. You can scroll back through the history.</li>
          <li><strong>LOG</strong> — Raw debug output, SCOM register inspection, and the TRACE toggle. Most useful for capturing session files for deep analysis.</li>
        </ul>
      </div>

      <div className="panel" style={{ padding: 20, lineHeight: 1.7, marginTop: 12 }}>
        <h3 className="sub" style={{ marginTop: 0, marginBottom: 12 }}>CALCULATOR tab</h3>
        <p style={{ marginTop: 0 }}>
          The CALCULATOR tab shows a window into program memory (copied from RAM) centred on the current step. The highlighted instruction is the one that will execute <strong>next</strong>. After a jump (GTO, SBR, etc.) the listing jumps to the new location — it does not show where you came from, because it is not a trace.
        </p>
        <p>
          Registers and flags reflect the calculator state <strong>right now</strong>, before the highlighted instruction runs.
        </p>
        <p style={{ marginBottom: 0 }}>
          <strong>STEP in CALCULATOR mode</strong> — pressing Step runs the CPU until the program counter changes (i.e. until the next user-visible step advances), then freezes again. This is the right tool for tracing through a keystroke-driven program one step at a time.
        </p>
      </div>

      <div className="panel" style={{ padding: 20, lineHeight: 1.7, marginTop: 12 }}>
        <h3 className="sub" style={{ marginTop: 0, marginBottom: 12 }}>CPU tab</h3>
        <p style={{ marginTop: 0 }}>
          The CPU tab shows the actual ROM instructions that executed, in order. Each entry represents an instruction that <strong>already ran</strong>; registers and flags are in the state <em>after</em> that instruction completed.
        </p>
        <p>
          Because it is a true execution trace, you can see jumps, subroutine calls, and PREG transitions — the address changes visibly in the listing. You can also scroll back through past entries to review earlier execution.
        </p>
        <p style={{ marginBottom: 0 }}>
          <strong>STEP in CPU mode</strong> — pressing Step executes exactly one ROM instruction, then freezes. This is the right tool when you want to follow the ROM's internal logic one opcode at a time.
        </p>
        <p style={{ marginTop: 8, marginBottom: 0 }}>
          <strong>Note on TEST/JUMP flags:</strong> because state is captured <em>after</em> each instruction, a TEST shows the flag it set, but the following JUMP shows the auto-restored condition (usually 1). This is expected behaviour — it is not a bug.
        </p>
      </div>

      <div className="panel" style={{ padding: 20, lineHeight: 1.7, marginTop: 12 }}>
        <h3 className="sub" style={{ marginTop: 0, marginBottom: 12 }}>Freeze controls</h3>
        <p style={{ marginTop: 0 }}>
          The toolbar above the debug pane offers <strong>FREEZE</strong>, <strong>F.START</strong> (Freeze on Start), <strong>ARMED</strong>, <strong>RESUME</strong>, and <strong>STEP</strong>.
        </p>
        <ul style={{ margin: "8px 0", paddingLeft: 20 }}>
          <li><strong>FREEZE</strong> — stops the CPU immediately.</li>
          <li><strong>F.START (CALCULATOR tab)</strong> — arms the debugger so it freezes the first time the calculator-level program counter changes. This is triggered by pressing R/S, launching a program via a label, or any similar action. Useful for catching the very start of a program run.</li>
          <li><strong>F.START (CPU tab)</strong> — arms the debugger so it freezes the moment the calculator leaves the keyboard scan loop. This happens when you press any key (which causes the ROM to exit the idle loop and start processing the keystroke) or when the calculator is reset. Useful for catching the very first ROM instruction of a key-press handler.</li>
          <li><strong>ARMED</strong> — shown in yellow when F.START is active; click it to cancel.</li>
          <li><strong>RESUME</strong> — resumes execution from the frozen state.</li>
          <li><strong>STEP</strong> — advances one step (semantics differ per tab, see above).</li>
        </ul>
        <p style={{ marginTop: 8, marginBottom: 0, color: "var(--fg-2)" }}>
          Only one F.START arm can be active at a time. Pressing F.START in one tab while the other is already ARMED silently transfers the arm. Once frozen, RESUME and STEP are only available in the tab that caused the freeze — the other tab's buttons are disabled to prevent accidental cross-tab interactions.
        </p>
      </div>

      <div className="panel" style={{ padding: 20, lineHeight: 1.7, marginTop: 12 }}>
        <h3 className="sub" style={{ marginTop: 0, marginBottom: 12 }}>iPhone behaviour</h3>
        <p style={{ marginTop: 0 }}>
          On iPhone, the debugger panel is full-screen and covers the calculator. This is different from iPad and Mac, where both views are visible at the same time.
        </p>
        <ul style={{ margin: "8px 0 0", paddingLeft: 20 }}>
          <li>Switching to the <strong>CPU</strong> tab resets the heat map, because the CPU trace was not running while CALCULATOR was visible. Exception: if the CPU is already frozen when you switch, the heat map is preserved.</li>
          <li>The selected tab (CALCULATOR, CPU, LOG) is remembered when you navigate away from the debugger and return.</li>
          <li><strong>F.START in CALCULATOR</strong> works best in landscape or on iPad/Mac, where you can press a key on the calculator while the tab is watching. On iPhone you would need to go back to the calculator, press the key, then return to the debugger.</li>
          <li><strong>F.START in CPU</strong> arms in the background and fires as soon as you press any key (or reset the calculator), regardless of which tab or screen is visible — the freeze is waiting for a ROM-level scan-loop exit, not a screen interaction.</li>
        </ul>
      </div>

      <div className="panel" style={{ padding: 20, lineHeight: 1.7, marginTop: 12 }}>
        <h3 className="sub" style={{ marginTop: 0, marginBottom: 12 }}>TRACE and LOG: for session capture and analysis</h3>
        <p style={{ marginTop: 0 }}>
          The <strong>LOG</strong> panel serves two main purposes:
        </p>
        <ul style={{ margin: "8px 0", paddingLeft: 20 }}>
          <li><strong>Raw SCOM inspection</strong> — Shows the low-level scratch memory that the ROM uses. The CALCULATOR view displays decoded SCOM values (like HIR section), but LOG shows the raw hex.</li>
          <li><strong>TRACE toggle</strong> — Records a binary session file while the calculator is running. This is the most thorough way to understand sequences like the reset routine or key-processing flow.</li>
        </ul>

        <p style={{ marginTop: 12, marginBottom: 12 }}>
          <strong>To capture and analyze a sequence:</strong>
        </p>
        <ol style={{ margin: 0, paddingLeft: 20 }}>
          <li>Switch to the LOG tab and toggle TRACE on.</li>
          <li>Perform the action you want to analyze (e.g., press <strong>Reset</strong>, or execute a ROM subroutine).</li>
          <li>Toggle TRACE off to stop recording.</li>
          <li>Export the trace file (use the Files app on iOS to email it, or find it on Mac).</li>
          <li>On a computer with Python, download the <code>read_trace.py</code> tool from the <a href="https://github.com/tinue/Calc-U-59/tree/main/tools" style={{ color: "var(--accent)", textDecoration: "none", borderBottom: "1px solid var(--accent)" }}>Calc-U-59 tools folder</a>.</li>
          <li>Run: <code style={{ background: "var(--bg-inset)", padding: "2px 6px", borderRadius: 4 }}>python3 ./read_trace.py --clean --skip-repeating CALCU59_TRACE.bin &gt; CALCU59_TRACE.txt</code></li>
          <li>Open the resulting text file to see the full execution trace as human-readable disassembly.</li>
        </ol>

        <p style={{ marginTop: 12, marginBottom: 0 }}>
          The binary trace file can be large (190 MB for a long session), but the text output is much smaller (57 kB) because the tool deduplicates repetitive loops — especially the keyboard scan loop that runs continuously. This makes it practical to analyze even long traces.
        </p>
      </div>

      <div className="panel" style={{ padding: 20, lineHeight: 1.7, marginTop: 12 }}>
        <h3 className="sub" style={{ marginTop: 0, marginBottom: 12 }}>When to use each tool</h3>
        <ul style={{ margin: 0, paddingLeft: 20 }}>
          <li><strong>CALCULATOR tab</strong> — Stepping through your own program one step at a time, checking registers and flags at each step.</li>
          <li><strong>CPU tab</strong> — Tracing the ROM's internal instruction flow, reviewing jumps and subroutine calls, scrolling back through execution history.</li>
          <li><strong>TRACE (in LOG)</strong> — Capturing a complete ROM sequence for offline analysis (reset routine, memory writes, keyboard processing, etc.).</li>
          <li><strong>Debug logging (in LOG)</strong> — Low or High level logging is mainly used by the developer for debugging specific issues. When enabled, you will see all memory writes and other hardware events. This has limited utility for regular app users.</li>
        </ul>
      </div>

      <div style={{ marginTop: 16, display: "grid", gap: 12 }}>
        <div className="panel" style={{ padding: 16 }}>
          <h3 className="sub" style={{ margin: "0 0 10px" }}>CALCULATOR tab — iPhone</h3>
          <img
            src="assets/iphone-debug.png"
            alt="iPhone screenshot showing the CALCULATOR debug tab with program listing and registers"
            style={{ width: "auto", maxWidth: "60%", height: "auto", display: "block", borderRadius: 8, margin: "0 auto" }}
          />
        </div>
        <div className="panel" style={{ padding: 16 }}>
          <h3 className="sub" style={{ margin: "0 0 10px" }}>CALCULATOR tab — iPad</h3>
          <img
            src="assets/ipad-13-2752x2064.png"
            alt="iPad screenshot showing the CALCULATOR debug tab"
            style={{ width: "100%", height: "auto", display: "block", borderRadius: 8 }}
          />
        </div>
        <div className="panel" style={{ padding: 16 }}>
          <h3 className="sub" style={{ margin: "0 0 10px" }}>CPU tab — iPad</h3>
          <img
            src="assets/ipad-2752x2064-asm.png"
            alt="iPad screenshot showing the CPU debug tab with execution trace"
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
            The debug pane has three tabs: <strong>CALCULATOR</strong>, <strong>CPU</strong>, and <strong>LOG</strong>.
          </p>
          <ul style={{ margin: "8px 0 0", paddingLeft: 20 }}>
            <li><strong>CALCULATOR</strong> — Program listing (from RAM) centred on the next instruction to execute, with live registers and flags.</li>
            <li><strong>CPU</strong> — Execution trace of ROM instructions that already ran. State shown is <em>after</em> each instruction. Scrollable history, one-opcode step.</li>
            <li><strong>LOG</strong> — Text output, raw SCOM register dumps, and the TRACE toggle. Use TRACE to capture a binary session file for detailed analysis with read_trace.py.</li>
          </ul>
          <p style={{ marginTop: 8, marginBottom: 0 }}>
            The CALCULATOR and CPU tabs have different step semantics: CALCULATOR advances until the program counter changes; CPU advances exactly one ROM opcode.
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
      answer: "They are regular .ti59, .ti58, or .ti58c text files that can be anywhere on the file system. On Mac, the preset picker opens them from disk; on iPhone and iPad, use the built-in file picker.",
    },
    {
      question: "Are there examples of state files?",
      answer: "Yes. The GitHub repository includes an 'examples' folder with a selection of .ti59, .ti58, and .ti58c files.",
    },
    {
      question: "What are the 'assembly' examples here for?",
      answer: "This feature is still a bit experimental. You can load these examples on the 'CPU' tab of the debugger. Use the buttons at the bottom to select a file, and run it.",
    },
    {
      question: "The emulator always complains about 'ASM run timed out before HOLD (8192 step(s))' when I try to start an assembly program. What can I do?",
      answer: "Click away the error, click 'Freeze', then click 'Resume', and you should be on your way.",
    },
    {
      question: "Where do virtual magnetic cards live?",
      answer: "The virtual cards are stored in the app's iCloud storage. On iOS and iPadOS, use the card picker to load or save them. On Mac, they are also available in the file picker under the 'iCloud Drive/Calc-U-59' folder.",
    },
    {
      question: "Where is the TI-58C state file?",
      answer: "The TI-58C state file is stored in the app's iCloud storage (ti58c.mem). The file is written and loaded automatically when you switch to the TI-58C model.",
    },
    {
      question: "Can I see what the emulator is doing internally?",
      answer: "Yes. Use the debug pane: CALCULATOR for program state and registers, CPU for the ROM instruction trace, and LOG for text output plus trace controls.",
    },
    {
      question: "How do I get a trace file?",
      answer: "Open the debug pane, switch to LOG, and turn TRACE on. The app writes a binary session file to the configured trace location.",
    },
    {
      question: "What can I do with a trace file?",
      answer: "You first need to download the trace file to your computer. If you use the Mac emulator, this is already a given. When you generate the trace file with an iPad, then use 'Settings' to choose a good location. One option is to save the file directly to iCloud, and let the iPad sync it for you. Retrieve the file from iCloud on your PC. Download the 'read_trace.py' script from GitHub to convert the binary file to a readable format. The script is available in the 'tools' directory of the GitHub repository.",
    },
    {
      question: "Why does switching to the CPU tab reset the heat map?",
      answer: "The CPU tab only traces while it is visible. When you switch to it, the heat map resets because any activity since you last left would be missing anyway. Exception: if the CPU is already frozen when you switch, the heat map is left intact — there is nothing new to miss.",
    },
    {
      question: "What does F.START do in the CPU tab?",
      answer: "In the CPU tab, F.START arms a scan-loop exit trigger: it freezes the moment the calculator leaves the keyboard idle loop — either because you pressed a key (the ROM exits the loop to handle the keystroke) or because the calculator was reset. This lets you catch the very first ROM opcode of a key-press handler without having to time a manual FREEZE. Only one F.START can be armed at a time; arming one tab silently disarms the other.",
    },
    {
      question: "How can I step through the reset routine?",
      answer: "Switch to the CPU tab and press F.START (Freeze on Start). Then go to the calculator and press Reset — the CPU will freeze at the first ROM instruction of the reset routine. Use STEP to walk through it one opcode at a time.",
    },
    {
      question: "I used F.START in the CPU tab, the freeze triggered on a keypress — but after RESUME the key seems lost. Why?",
      answer: "This is expected. The ROM's key-debouncing logic registers a keypress only for a very short window. When F.START fires, the CPU freezes at the first instruction after the scan loop exits — but that window has already passed by the time you press RESUME or STEP. The key handler never sees the keypress and the calculator returns to idle. Use a TRACE capture instead: it records the full keystroke sequence without stopping the emulator, so the debounce window is never interrupted.",
    },
    {
      question: "Is there a faster way to read long printer output?",
      answer: "Yes. Copy or cut the output, and paste it into a text editor.",
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

function ModulesPage({ onNav }) {
  const modules = [
    { code: "ML", name: "Master Library" },
    { code: "ST", name: "Applied Statistics" },
    { code: "RE", name: "Investment" },
    { code: "SY", name: "Surveying" },
    { code: "NG", name: "Marine Navigation" },
    { code: "AV", name: "Aviation" },
    { code: "LE", name: "Leisure Library" },
    { code: "SA", name: "Securities Analysis" },
    { code: "BD", name: "Business Decisions" },
    { code: "MU", name: "Math/Utilities" },
    { code: "EE", name: "EE Library" },
    { code: "SE", name: "Structural Engineering" },
    { code: "AG", name: "Agriculture" },
    { code: "RP", name: "RPN Simulator" },
  ];
  return (
    <main className="wrap">
      <p className="eyebrow">Modules</p>
      <h1 className="page-title">Library modules</h1>
      <p className="lede">The module picker changes the Solid State Software library loaded into the emulator. That affects the cue card, the available programs, and the labels shown on screen.</p>

      <div className="panel" style={{ padding: 20, marginTop: 24, lineHeight: 1.7 }}>
        <p style={{ marginTop: 0 }}>
          Keep the selected module aligned with the file you are loading. If a state file includes a <strong>SOLID-STATE-MODULE:</strong> line, the emulator can switch to that module automatically.
        </p>
        <p style={{ marginBottom: 0 }}>
          If the cue card or program list looks unexpected, the module selection is the first thing to check.
        </p>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(2, 1fr)", gap: 12, marginTop: 24 }}>
        {modules.map(m => (
          <div key={m.code} className="panel"
               style={{ display: "grid", gridTemplateColumns: "auto 1fr", gap: 16, alignItems: "center" }}>
            <div style={{
              background: "linear-gradient(180deg,#1a0c08,#2c1812)",
              color: "var(--accent)",
              fontFamily: "var(--font-key)", fontWeight: 700,
              padding: "8px 12px", borderRadius: 4,
              letterSpacing: ".05em", fontSize: 13,
              minWidth: 70, textAlign: "center",
              border: "1px solid var(--stroke-warm)",
            }}>{m.code}</div>
            <div>
              <h3 className="sub" style={{ margin: 0 }}>{m.name}</h3>
            </div>
          </div>
        ))}
      </div>

      <h2 className="section">Per-module details</h2>
      <div className="panel" style={{ padding: 20, lineHeight: 1.7 }}>
        <p style={{ marginTop: 0 }}>
          Each module has its own cue card content and program selection. The app loads the matching ROM/library data together with the module metadata so the on-screen card stays in sync with the selected library.
        </p>
        <p style={{ marginBottom: 0 }}>
          This is an emulator feature, not a historical TI-59 walkthrough: the purpose is to make the active module understandable while you use the app.
        </p>
      </div>

      <div style={{ marginTop: 24 }}>
        <BackButton onNav={onNav} />
      </div>
    </main>
  );
}

function PlayPage({ onNav }) {
  return (
    <main className="wrap-narrow">
      <div style={{ display: "flex", justifyContent: "center" }}>
        <PlayCalculator scale={1.4} />
      </div>

      <h1 className="page-title" style={{ marginTop: 32 }}>Try it right here</h1>
      <p style={{ lineHeight: 1.7, color: "var(--fg-2)" }}>
        This is the real emulation core — compiled to WebAssembly and running entirely in your
        browser — not a screenshot. Debugger, printer, and card reader are not part of this build;
        everything else works.
      </p>
      <p style={{ lineHeight: 1.7, color: "var(--fg-2)" }}>
        Module 01 (Master Library) is loaded by default. Switch modules, load one of the curated
        presets, or upload your own <strong>.ti59</strong> file below the keyboard — uploads are
        read entirely in your browser and never leave your machine.
      </p>
      <p style={{ lineHeight: 1.7, color: "var(--fg-2)" }}>
        Press <strong>2nd</strong> then <strong>Pgm</strong> then a two-digit program number to
        bring up that program's cue card, the same way it works on the module itself.
      </p>

      <div style={{ marginTop: 24 }}>
        <BackButton onNav={onNav} />
      </div>
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
  PlayPage,
});
