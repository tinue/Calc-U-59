// Calc-U 59 — Help site pages
// User scope: this guide explains the EMULATOR APP, not the underlying
// TI-59 calculator hardware.

const { useState: useStateApp } = React;

const STARTED_SECTIONS = [
  { title: "Start here", items: [
    { id: "overview", label: "Overview", href: "/getting-started/" },
  ]},
  { title: "Setup", items: [
    { id: "install-mobile", label: "Installing on iPhone and iPad", href: "/getting-started/install-iphone-ipad/" },
    { id: "install-mac", label: "Installing on Mac", href: "/getting-started/install-mac/" },
  ]},
  { title: "Using the emulator", items: [
    { id: "state-files", label: "Loading a state file", href: "/getting-started/state-files/" },
    { id: "debugger", label: "Using the debugger", href: "/getting-started/debugger/" },
    { id: "printer", label: "Printer and card reader", href: "/getting-started/printer/" },
  ]},
  { title: "Help", items: [
    // `jump: true` rather than a topic: the FAQ has exactly one copy, on its
    // own page. This item is a real navigation to it, not an in-page topic
    // switch that would need its own titles/notes/topicBody entry here.
    { id: "faq", label: "FAQ", href: "/faq/", jump: true },
    // Not a page on this site: the README lives on GitHub, so this is an
    // ordinary outbound link rather than a route that would only exist to
    // point somewhere else.
    { id: "readme", label: "Main README", href: "https://github.com/tinue/Calc-U-59/blob/main/README.md", external: true },
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
        <div className="wrap hero">
          <div className="hero-copy">
            <p className="eyebrow">TI-59 emulator for Mac, iPhone and iPad</p>
            <h1 className="page-title">Calc-U <em>59</em></h1>
            <p className="lede">Calc-U 59 is a <strong style={{ color: "var(--fg)" }}>TI-59, TI-58 and TI-58C emulator</strong> for macOS, iPhone and iPad. It runs the original Texas Instruments ROM, reads and writes virtual magnetic cards, emulates the PC-100C printer and all fourteen Solid State Software modules, and includes a CPU-level debugger. You can <a href="/play/">try it in your browser</a> before you install anything.</p>
            <div style={{ display: "flex", gap: 12, flexWrap: "wrap" }}>
              <a className="btn primary" href="/getting-started/">Getting started <span style={{opacity:.5}}>→</span></a>
              <a className="btn secondary" href="/reference/">App reference</a>
            </div>
          </div>
          {/* Placed by .hero into the right-hand column on a wide screen and
              directly under the pitch once the hero stacks. */}
          <div className="hero-shot">
            <img
              src="/assets/app-screenshot.png"
              alt="The Calc-U 59 TI-59 emulator running on an iPhone, showing the red LED display, the cue card and the full key matrix"
            />
          </div>
          <div className="hero-cards grid-2">
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
      </section>

      {/* Topic cards */}
      <div className="wrap">
        <h2 className="section">Where to start</h2>
        <div className="grid-3">
          <TopicCard num="01" eyebrow="Setup" title="Installing on iPhone and iPad" href="/install/iphone-ipad/">
            The App Store install path, plus what happens on first launch.
          </TopicCard>
          <TopicCard num="02" eyebrow="Setup" title="Installing on Mac" href="/install/mac/">
            GitHub Releases, the DMG, and Gatekeeper the first time you open the app.
          </TopicCard>
          <TopicCard num="03" eyebrow="Files" title="Loading a state file" href="/state-files/">
            What a .ti59 file contains and how the parser treats each section.
          </TopicCard>
          <TopicCard num="04" eyebrow="Debug" title="Using the debugger" href="/debugger/">
            CALCULATOR, CPU, LOG, freeze/step, and the binary trace file.
          </TopicCard>
          <TopicCard num="05" eyebrow="Hardware" title="Printer and card reader" href="/getting-started/printer/">
            What the PC-100C panel does and how card files are managed.
          </TopicCard>
          <TopicCard num="06" eyebrow="Help" title="FAQ" href="/faq/">
            Answers to the questions users actually hit first.
          </TopicCard>
        </div>

        {/* What the emulator actually reproduces. Written for someone who
            arrived from a search engine and has not yet decided whether
            this is the TI-59 emulator they were looking for. */}
        <h2 className="section">What Calc-U 59 emulates</h2>
        <div className="prose panel" style={{ padding: 20, lineHeight: 1.7 }}>
          <p style={{ marginTop: 0 }}>
            Calc-U 59 emulates the <strong>TI Programmable 59</strong> that Texas Instruments
            introduced in 1977, along with its two smaller siblings, the <strong>TI-58</strong> and
            the constant-memory <strong>TI-58C</strong>. It is not a reimplementation of the maths in
            Swift: the app runs the calculators' original ROM through an emulated TMC0501 processor,
            so AOS precedence, the 13-digit internal precision, the flashing overflow display and the
            documented quirks all behave the way the hardware did.
          </p>
          <ul style={{ margin: "0 0 12px", paddingLeft: 20 }}>
            <li>Switchable <strong>TI-59 / TI-58 / TI-58C</strong> models, with the correct memory partition and startup state for each.</li>
            <li>All fourteen <strong>Solid State Software</strong> library modules, from the Master Library to the RPN Simulator — <a href="/modules/">see the full list</a>.</li>
            <li><strong>Magnetic cards</strong> read and written as files, synced between your devices over iCloud.</li>
            <li>The <strong>PC-100C thermal printer</strong>, in both a dot-matrix view and a copyable text view.</li>
            <li>A <a href="/debugger/">CPU-level debugger</a> with a live program listing, a ROM instruction trace, and binary trace capture for offline analysis.</li>
            <li>Plain-text <a href="/state-files/">.ti59 state files</a> that carry a program, the registers, a cue card and a module selection in one readable file.</li>
          </ul>
          <p style={{ marginBottom: 0 }}>
            New to these machines, or trying to work out which model you owned?{" "}
            <a href="/what-is-a-ti-59/">Start with the background on the TI-59 and TI-58 →</a>
          </p>
        </div>

        {/* App-icon strip */}
        <div className="panel" style={{
          marginTop: 48, display: "flex", alignItems: "center", gap: 24,
        }}>
          <img src="/assets/app-icon.png" alt=""
               style={{ width: 80, height: 80, borderRadius: 18, flex: "0 0 auto" }}/>
          <div>
            <h3 className="sub" style={{ margin: "0 0 4px" }}>Available now</h3>
            <p style={{ margin: 0, fontSize: 14 }}>
              The Mac build ships free from <a href="https://github.com/tinue/Calc-U-59/releases/latest">GitHub Releases</a>.
              The iPhone and iPad build is on the <a href="https://apps.apple.com/us/app/calc-u-59/id6761413142">App Store</a>.
              The source code is on <a href="https://github.com/tinue/Calc-U-59">GitHub</a>.
            </p>
          </div>
        </div>
      </div>
    </main>
  );
}

/* =============================================================
   WHAT IS A TI-59 — background page.

   Scope exception, and a deliberate one. The rest of this site documents
   the app and stays away from the 1977 hardware. This page exists because
   the people looking for the app search for the machine — "TI-59
   emulator", "TI-58C simulator", "TI-59 magnetic card" — and had nothing
   here to land on. It orients a newcomer and hands them to the app; it is
   not a substitute for the TI Personal Programming manual.
   ============================================================= */
function AboutTi59Page({ onNav }) {
  const models = [
    {
      code: "TI-59",
      name: "TI Programmable 59",
      year: "May 1977",
      body: "The top of the range. Up to 960 program steps or 100 data registers, traded against each other in steps of 80 and 10, plus a magnetic card reader in the side for saving programs. Memory was volatile: switch it off and the program was gone unless it was on a card.",
    },
    {
      code: "TI-58",
      name: "TI Programmable 58",
      year: "May 1977",
      body: "The same calculator with half the memory — up to 480 steps or 60 registers — and no card reader. Library modules still worked, so it lost storage rather than capability.",
    },
    {
      code: "TI-58C",
      name: "TI Programmable 58C",
      year: "1979",
      body: "A TI-58 with constant memory. The C is the whole point: programs and registers survived being switched off, which removed most of the reason to want a card reader in the first place.",
    },
  ];

  return (
    <main className="wrap-narrow">
      <p className="eyebrow">Background</p>
      <h1 className="page-title">What is a TI-59?</h1>
      <p className="lede">
        A short orientation to the Texas Instruments TI-59, TI-58 and TI-58C — the machines
        Calc-U 59 emulates — for anyone who arrived here looking for one and wants to know
        what they are dealing with.
      </p>

      <div className="prose" style={{ marginTop: 24 }}>
        <p>
          The <strong>TI Programmable 59</strong> was Texas Instruments' flagship programmable
          calculator, introduced on 24 May 1977 at a list price of around $300. It succeeded
          the SR-52, and for the rest of the decade it was the machine engineers, surveyors,
          navigators and financial analysts actually carried. Its rival was the Hewlett-Packard
          HP-67; the TI had roughly twice the memory, the HP had RPN and better build quality,
          and people argued about it for years.
        </p>
        <p>
          You programmed it by recording keystrokes. In learn mode every key you pressed became
          a program step, and the ten user-defined keys — <K tone="dark">A</K> through{" "}
          <K tone="dark">E</K> and their primed second functions — were the entry points. That
          sounds primitive, and it is, but the instruction set includes conditionals, loops,
          subroutines and indirect register addressing, which makes the TI-59 Turing-complete.
          People wrote games for it.
        </p>
      </div>

      <h2 className="section">The three models</h2>
      <div style={{ display: "grid", gap: 12 }}>
        {models.map(m => (
          <div key={m.code} className="panel" style={{ padding: 20, lineHeight: 1.7 }}>
            <div style={{ display: "flex", alignItems: "baseline", gap: 12, marginBottom: 6 }}>
              <h3 className="sub" style={{ margin: 0 }}>{m.code}</h3>
              <span style={{ color: "var(--fg-3)", fontSize: 13 }}>{m.name} · {m.year}</span>
            </div>
            <p style={{ margin: 0, color: "var(--fg-2)" }}>{m.body}</p>
          </div>
        ))}
      </div>
      <p style={{ marginTop: 12, color: "var(--fg-2)", lineHeight: 1.7 }}>
        Calc-U 59 emulates all three. The model selector in the bottom toolbar switches between
        them, and each starts with the memory partition and power-on state that model really had.
      </p>

      <h2 className="section">Algebraic Operating System</h2>
      <div className="prose panel" style={{ padding: 20, lineHeight: 1.7 }}>
        <p style={{ marginTop: 0 }}>
          These calculators use <strong>AOS</strong> — Algebraic Operating System — rather than the
          RPN found on contemporary Hewlett-Packard machines. You enter an expression roughly as it
          is written on paper, with up to nine levels of parentheses, and the calculator applies
          operator precedence when you press <K tone="yellow">=</K>. Emulating AOS convincingly is
          the part that catches out reimplementations: the pending-operation stack has observable
          edge cases that only fall out correctly if you run the original ROM, which is what
          Calc-U 59 does.
        </p>
        <p style={{ marginBottom: 0 }}>
          One of the library modules, <strong>RP</strong>, is an RPN Simulator — Texas Instruments
          shipped a way to make its algebraic calculator behave like an HP.
        </p>
      </div>

      <h2 className="section">Magnetic cards</h2>
      <div className="prose panel" style={{ padding: 20, lineHeight: 1.7 }}>
        <p style={{ marginTop: 0 }}>
          The TI-59's card reader took small magnetic strips, one quarter of the machine's memory
          per side. The card did double duty: once read, it slid into a slot above the keyboard so
          the labels written along its top edge sat directly beneath the{" "}
          <K tone="dark">A</K>–<K tone="dark">E</K> keys and told you what each one did in the
          program you had just loaded. That is what the cue card on screen in Calc-U 59 is
          reproducing.
        </p>
        <p style={{ marginBottom: 0 }}>
          In the emulator, cards are files. They live in iCloud storage, so a program written on a
          Mac is on the iPhone by the time you pick it up. The card reader mechanism was also the
          most failure-prone part of the original hardware, which is a reasonable argument for
          emulating one instead of restoring one.
        </p>
      </div>

      <h2 className="section">Solid State Software modules</h2>
      <div className="prose panel" style={{ padding: 20, lineHeight: 1.7 }}>
        <p style={{ marginTop: 0 }}>
          The TI-58 and TI-59 were the first handheld calculators with removable ROM program
          modules. A module held up to 5,000 program steps and ran straight from ROM, leaving user
          memory free. The Master Library came in the box; Applied Statistics, Surveying, Aviation,
          Marine Navigation, Securities Analysis and the rest were sold separately, and the
          complete set is now hard to find and expensive.
        </p>
        <p style={{ marginBottom: 0 }}>
          Calc-U 59 includes all fourteen. <a href="/modules/">See the module list →</a>
        </p>
      </div>

      <h2 className="section">The PC-100C printer</h2>
      <div className="prose panel" style={{ padding: 20, lineHeight: 1.7 }}>
        <p style={{ margin: 0 }}>
          The calculator docked into a thermal printer — the PC-100A, B or C — and locked in place
          with a key. Beyond printing results, it was how you got a readable listing of a program
          with mnemonics instead of raw numeric key codes, dumped the data registers, or traced
          execution. It is emulated in Calc-U 59, including the paper strip, which you can copy as
          plain text rather than squinting at dot-matrix output.{" "}
          <a href="/getting-started/printer/">Printer and card reader →</a>
        </p>
      </div>

      <h2 className="section">Try one</h2>
      <div className="prose panel" style={{ padding: 20, lineHeight: 1.7 }}>
        <p style={{ marginTop: 0 }}>
          The quickest way to see whether this is the machine you remember is to use one. The{" "}
          <a href="/play/">browser emulator</a> runs the same emulation core compiled to
          WebAssembly, with the Master Library loaded, and needs no installation. The full app,
          with the printer, the card reader and the debugger, is{" "}
          <a href="/install/mac/">free on the Mac</a> and{" "}
          <a href="/install/iphone-ipad/">on the App Store</a> for iPhone and iPad.
        </p>
        <p style={{ marginBottom: 0, color: "var(--fg-3)", fontSize: 13 }}>
          For the original operating manuals, program libraries and the wider TI-59 community,
          start at <a href="https://www.ti59.com/">ti59.com</a> and{" "}
          {/*
            http:// is deliberate and must stay: datamath.org serves no TLS at
            all — https:// fails the handshake outright ("tlsv1 alert internal
            error"), it does not merely warn. Promoting this to https breaks
            the link. Re-test before changing it; if they ever add a
            certificate, this is safe to flip.
          */}
          <a href="http://www.datamath.org/SCI/WEDGE/TI-59.htm">datamath.org</a>. This site only
          documents the emulator.
        </p>
      </div>

      <div style={{ marginTop: 24 }}>
        <BackButton onNav={onNav} />
      </div>
    </main>
  );
}

/* =============================================================
   GETTING STARTED — practical install, file, and debug guidance.
   ============================================================= */
// "overview" is the default because /getting-started/ is a hub: it is the
// most-linked page on the site and sits in the header nav. Defaulting to a
// topic would make it a byte-identical twin of that topic's own URL.
function GettingStartedPage({ initialTopic = "overview", onNav }) {
  const [topic, setTopic] = useStateApp(initialTopic);

  function handlePick(id) {
    setTopic(id);
    if (onNav) onNav({ page: "start", topic: id });
  }
  const titles = {
    overview: "Getting started with Calc-U 59",
    "install-mobile": "Installing on iPhone and iPad",
    "install-mac": "Installing on Mac",
    "state-files": "Loading a state file",
    debugger: "Using the debugger",
    printer: "Printer and card reader",
  };
  const notes = {
    overview: "Install the app, load a state file, drive the printer and card reader, and find your way around the debugger.",
    "install-mobile": "Use the App Store build, then configure the model and load presets from inside the app.",
    "install-mac": "Download the release from GitHub, then drag the app to Applications.",
    "state-files": "What .ti59/.ti58/.ti58c files contain and how the parser treats each section.",
    debugger: "CALCULATOR, CPU, LOG, freeze/step, and binary trace output.",
    printer: "The PC-100C panel, paper strip, copy/cut, and card file behaviour.",
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
    overview: (
      <div style={{ display: "grid", gap: 16, marginTop: 20 }}>
        <div className="panel" style={{ padding: 20, lineHeight: 1.7 }}>
          <p style={{ marginTop: 0 }}>
            Calc-U 59 runs the original Texas Instruments ROM, so the calculator in front of you behaves the way a TI-59, TI-58 or TI-58C did in 1977 — the same AOS arithmetic, the same 480 program steps traded against 60 data registers, the same Solid State Software modules.
          </p>
          <p style={{ marginBottom: 0 }}>
            Most people need three things: get the app installed, open a state file, and know where the printer and the debugger live. Each is a short page.
          </p>
        </div>

        <div style={{ display: "grid", gap: 12 }}>
          <TopicCard num="01" eyebrow="Setup" title="Installing on iPhone and iPad" href="/install/iphone-ipad/">
            Install from the App Store, pick the calculator model, and open .ti59 files from the file picker.
          </TopicCard>
          <TopicCard num="02" eyebrow="Setup" title="Installing on Mac" href="/install/mac/">
            Download the release from GitHub, drag it to Applications, and get past the first-launch Gatekeeper prompt.
          </TopicCard>
          <TopicCard num="03" eyebrow="Files" title="Loading a state file" href="/state-files/">
            What .ti59, .ti58 and .ti58c files contain, and how each section — partition, program, registers, keystrokes — is applied.
          </TopicCard>
          <TopicCard num="04" eyebrow="Hardware" title="Printer and card reader" href="/getting-started/printer/">
            The PC-100C panel in dot and text view, printing and advancing paper, copying the strip, and where card files are kept.
          </TopicCard>
          <TopicCard num="05" eyebrow="Debug" title="Using the debugger" href="/debugger/">
            The CALCULATOR, CPU and LOG tabs, freeze and step, F.START, and binary trace files for offline analysis.
          </TopicCard>
          <TopicCard num="06" eyebrow="Help" title="FAQ" href="/faq/">
            Where files live, how to capture a trace, and the other questions that come up first.
          </TopicCard>
        </div>
      </div>
    ),
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
  };

  return (
    <main className="wrap docs-layout">
      <DocsSidebar current={topic} onPick={handlePick} sections={STARTED_SECTIONS} />
      <article className="prose docs-article">
        <p className="eyebrow">Getting started</p>
        <h1 className="page-title compact">{titles[topic]}</h1>
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

  const cueCardLabelExample = `CUECARD:
Template: MagnetCard
Title: Roots & Powers
Banks: 1, 2
A: \\sqrt x
B: x^{2}
C: 1/x
D: x \\to y
E: \\blank
A': \\sum x_{i}
B': \\xbar
C': n
D': \\blank
E': \\blank`;

  const cueCardRowExample = `CUECARD:
Template: CueCard
Title: Compound Interest
Row1: Enter n, i, PV — press B for FV
Row1Align: center
Row2: RPN 5.1
Row2R: p. 3
Row2Align: left
Row2RAlign: right
Style: button`;

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

      <div className="panel" style={{ padding: 16, marginTop: 12 }}>
        <img
          src="/assets/cuecard-single-label.png"
          alt="MagnetCard cue card titled Example, with the Start label in the A key position and blank A′–E′ and B–E cells"
          style={{ width: "100%", height: "auto", display: "block", borderRadius: 8 }}
        />
      </div>

      <div className="panel" style={{ padding: 20, lineHeight: 1.7, marginTop: 12 }}>
        <p style={{ marginTop: 0 }}><strong>PARTITION:</strong> sets the step split between program memory and data registers.</p>
        <p><strong>PROGRAM:</strong> accepts sparse step listings, numeric keycodes, and the <strong>...</strong> gap marker.</p>
        <p><strong>REGISTERS:</strong> stores calculator variables as decimal numbers.</p>
        <p><strong>KEYSTROKES:</strong> injects matrix codes after the file loads. Wait lines are allowed between groups.</p>
        <p><strong>CUECARD:</strong> defines the on-screen cue card that appears with the loaded file or module.</p>
        <p><strong>SOLID-STATE-MODULE:</strong> and <strong>PRINTER:</strong> let a file select the matching module and printer state automatically.</p>
        <p style={{ marginBottom: 0 }}>
          This page covers enough to load and tweak existing files. The complete
          grammar — matrix code table, 2nd-function presses, the CUECARD field
          list, and the math-notation shorthand used in cue cards — is developer
          documentation kept in the GitHub repository:{" "}
          <a href="https://github.com/tinue/Calc-U-59/blob/main/reference/StateFileFormat.md" style={{ color: "var(--accent)", textDecoration: "none", borderBottom: "1px solid var(--accent)" }}>
            reference/StateFileFormat.md →
          </a>
        </p>
      </div>

      <h2 id="labeling-keys" className="section" style={{ marginTop: 24 }}>Labeling the A–E and A′–E′ keys</h2>
      <div className="panel" style={{ padding: 20, lineHeight: 1.7 }}>
        <p style={{ marginTop: 0 }}>
          The five plain keys (<strong>A–E</strong>) and their 2nd-function row
          (<strong>A′–E′</strong>) are exactly what real TI-59/58/58C cards
          label. A <strong>CUECARD:</strong> section can do the same thing
          on-screen — either as its own row of short per-key labels, or as one
          line of running text across the whole row.
        </p>
        <p>
          <strong>Template</strong> picks the background art and layout, and
          matches the real card it stands in for. On the real hardware,
          magnetic cards have a writable label area on the front and a
          magnetic coating on the back for the program; use{" "}
          <strong>MagnetCard</strong> if the state file is meant to end up
          written onto one (it also shows the <strong>Banks</strong> page
          badges). The TI-58 and TI-58C have no card reader, so their owners
          documented manually re-entered programs on cards with the same kind
          of writable front but no magnetic back — use{" "}
          <strong>CueCard</strong> for that case, or for any file that just
          wants an on-screen label without card art. Which of the two you pick
          for a given state file is mostly personal preference, except when
          the file is a step toward an actual magnetic card — then use{" "}
          <strong>MagnetCard</strong> to match. <strong>SolidStateCard</strong>{" "}
          reproduces the pre-printed cards that shipped with a Solid State
          Software module; real ones can't be edited by the module's user, and
          in the emulator they're normally only touched by the project's
          developer to document a built-in module — reach for it yourself
          only if you're prototyping your own module (it shows an{" "}
          <strong>ID</strong> like <code>ML-01</code> instead of Banks).
        </p>
        <p>
          Set fields <strong>A</strong> through <strong>E</strong> for the
          plain-key row, and <strong>A′</strong> through <strong>E′</strong>{" "}
          (a straight apostrophe also works: <code>A'</code>) for the
          2nd-function row. Leaving <strong>Row1</strong> or <strong>Row2</strong>{" "}
          out entirely is what makes that row show the label grid instead of a
          line of text — if you fill in Row1/Row2, the individual A–E labels for
          that row are not shown.
        </p>
        <p style={{ marginBottom: 0 }}>
          <strong>Row1</strong> replaces the A′–E′ grid with one line of
          running text, and <strong>Row2</strong> does the same for the A–E
          grid. <strong>Row2R</strong> is a second piece of text placed on the
          same line as Row2, right-aligned against it — handy for something
          like a page number or units note that shouldn't compete with the
          main label for space. Each of the three has its own alignment
          field — <strong>Row1Align</strong>, <strong>Row2Align</strong>,{" "}
          <strong>Row2RAlign</strong> — set to <code>left</code> (the
          default), <code>center</code>, or <code>right</code>.{" "}
          <strong>Style</strong> is <code>none</code> by default, or{" "}
          <code>button</code> to draw a border around the Row1/Row2/Row2R
          text, mimicking the boxed instruction labels real cards use.
        </p>
      </div>

      <div className="panel" style={{ padding: 20, marginTop: 12 }}>
        <pre style={{
          margin: 0,
          padding: 16,
          borderRadius: 8,
          background: "var(--bg-inset)",
          color: "var(--fg)",
          overflowX: "auto",
          lineHeight: 1.5,
          fontSize: 13,
        }}>{cueCardLabelExample}</pre>
      </div>

      <div className="panel" style={{ padding: 16, marginTop: 12 }}>
        <img
          src="/assets/cuecard-key-grid.png"
          alt="MagnetCard cue card titled Roots and Powers, with per-key labels on both the A′–E′ and A–E rows, including a merged x → y span"
          style={{ width: "100%", height: "auto", display: "block", borderRadius: 8 }}
        />
      </div>

      <div className="panel" style={{ padding: 20, marginTop: 12 }}>
        <pre style={{
          margin: 0,
          padding: 16,
          borderRadius: 8,
          background: "var(--bg-inset)",
          color: "var(--fg)",
          overflowX: "auto",
          lineHeight: 1.5,
          fontSize: 13,
        }}>{cueCardRowExample}</pre>
      </div>

      <div className="panel" style={{ padding: 16, marginTop: 12 }}>
        <img
          src="/assets/cuecard-row-text.png"
          alt="CueCard titled Compound Interest, with a centered, boxed Row1 instruction line and left-aligned Row2 / right-aligned Row2R text below it"
          style={{ width: "100%", height: "auto", display: "block", borderRadius: 8 }}
        />
      </div>

      <div className="panel" style={{ padding: 20, lineHeight: 1.7, marginTop: 12 }}>
        <p style={{ marginTop: 0 }}>
          A short set of LaTeX-style shortcuts expand to the Unicode symbols
          real TI-59 cards use in labels, so you don't need a Unicode picker —
          for example <code>\to</code> becomes an arrow, <code>\sqrt</code>{" "}
          becomes a root sign, <code>\sum</code> becomes Σ, and{" "}
          <code>{"x^{2}"}</code> becomes <code>x²</code>. The full token table
          is in <strong>reference/StateFileFormat.md</strong>.
        </p>
        <p style={{ marginBottom: 0 }}>
          To make one label visually span more than one key position, set the
          following cell(s) to <code>\blank</code> — for example{" "}
          <code>{"D: \\blank"}</code> right after a filled-in <strong>C</strong>{" "}
          merges D into C's column so the C label reads across both keys.
        </p>
      </div>

      <h2 className="section" style={{ marginTop: 24 }}>Loading a labeled card</h2>
      <div className="panel" style={{ padding: 20, lineHeight: 1.7 }}>
        <p style={{ marginTop: 0 }}><strong>From a state file</strong> — Load State File on a <code>.ti59</code>/<code>.ti58</code>/<code>.ti58c</code> file with a CUECARD section; it's applied immediately and stays until you load something else or reset.</p>
        <p><strong>Onto a virtual magnetic card</strong> — load a state file with the CUECARD you want active, then <strong>Write Magnetic Card</strong>: whatever cue card is on screen at that moment is saved into the card file along with the program or data. Reading that card back with <strong>Read Magnetic Card</strong> restores the label along with the contents.</p>
        <p style={{ marginBottom: 0 }}><strong>By editing the card file directly</strong> — virtual card files are plain text too (see the FAQ entry on where they live), with the same <code>CUECARD:</code> syntax as a state file. Add or edit that section in a text editor and the label shows the next time the card is read.</p>
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
            src="/assets/iphone-debug.png"
            alt="iPhone screenshot showing the CALCULATOR debug tab with program listing and registers"
            style={{ width: "auto", maxWidth: "60%", height: "auto", display: "block", borderRadius: 8, margin: "0 auto" }}
          />
        </div>
        <div className="panel" style={{ padding: 16 }}>
          <h3 className="sub" style={{ margin: "0 0 10px" }}>CALCULATOR tab — iPad</h3>
          <img
            src="/assets/ipad-13-2752x2064.png"
            alt="iPad screenshot showing the CALCULATOR debug tab"
            style={{ width: "100%", height: "auto", display: "block", borderRadius: 8 }}
          />
        </div>
        <div className="panel" style={{ padding: 16 }}>
          <h3 className="sub" style={{ margin: "0 0 10px" }}>CPU tab — iPad</h3>
          <img
            src="/assets/ipad-2752x2064-asm.png"
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
    <main className="wrap docs-split">
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

      <div className="docs-aside">
        <div className="panel" style={{ padding: 14 }}>
          <div style={{ position: "relative" }}>
            <img
              src="/assets/app-screenshot.png"
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
    {
      question: "How do I create the cards that label the A-E and A'-E' keys?",
      answer: (
        <>
          Add a <strong>CUECARD:</strong> section to a state file: set{" "}
          <strong>Template</strong> to <code>MagnetCard</code> or{" "}
          <code>CueCard</code>, then fill in fields <strong>A</strong>{" "}
          through <strong>E</strong> and <strong>A′</strong> through{" "}
          <strong>E′</strong> for the two key rows. Load that file (or write it
          onto a virtual magnetic card to keep the label with the card) and it
          appears on screen. See{" "}
          <a href="/state-files/#labeling-keys" style={{ color: "var(--accent)", textDecoration: "none", borderBottom: "1px solid var(--accent)" }}>
            Loading a state file → Labeling the A–E and A′–E′ keys
          </a>{" "}
          for the format, the math shortcuts, and the loading options.
        </>
      ),
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

      <div className="grid-2" style={{ marginTop: 24 }}>
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

/* =============================================================
   SOFTWARE — downloadable .ti59/.ti58/.ti58c programs and raw CPU
   assembly, sourced from examples/ in the main repository (that
   directory's own name is unrelated — these outgrew "examples" into a
   real software collection, hence the different name here). This is one
   of the copy-scope exceptions (with AboutTi59Page): most of these
   programs predate Calc-U 59 by decades, so the copy leans on the
   original TI-59/TI-58/TI-58C hardware and the magazines that published
   them — that's what someone who owned one, or is restoring one,
   actually searches for.
   ============================================================= */
function SoftwarePage({ onNav }) {
  const categories = [
    {
      heading: "The 1978 calendar printer competition",
      intro: "“52-Notes,” the TI programmable-calculator newsletter, ran a running competition through 1978 to write the fastest TI-59 program that prints a full year calendar on the PC-100 printer, using the Master Library module's date routines. Each entry improved on the last — all seven surviving programs are collected here, PC-100/PC-100C printer required.",
      items: [
        { file: "calendar-01-Weinberger.ti59", title: "Calendar Printer — Jared Weinberger", description: "The opening entry in the competition (52-Notes V3N5).", printer: true },
        { file: "calendar-02-cargile.ti59", title: "Calendar Printer — Lou Cargile", description: "A second V3N5 entry, Lou Cargile's first attempt at the calendar problem.", printer: true },
        { file: "calendar-03-vanderburgh.ti59", title: "Calendar Printer — Richard Vanderburgh", description: "A third V3N5 entry, checking for the ML module and warning the user if it's missing.", printer: true },
        { file: "calendar-04-skillman.ti59", title: "Calendar Printer — Bill Skillman", description: "V3N6: a faster print-buffer packing approach, down to about 7½ minutes per year.", printer: true },
        { file: "calendar-05-vanderburgh.ti59", title: "Calendar Printer — Richard Vanderburgh (revised)", description: "V3N6: Vanderburgh folds in Panos Galidas' doubled print-code method and further tightens it, to about 5½ minutes per year.", printer: true },
        { file: "calendar-06-cargile.ti59", title: "Calendar Printer — Lou Cargile (bugfix)", description: "V3N6: a correction to an earlier entry — a missing CLR' meant the 1st of a month could fail to print if it fell on a Thursday.", printer: true },
        { file: "calendar-07-calidas.ti59", title: "Calendar Printer — Panos Galidas", description: "V3N7: the fastest of the series, averaging 2 minutes 38.6 seconds per year over a five-year test span.", printer: true },
      ],
    },
    {
      heading: "PC-100 printer graphics and tricks",
      intro: "The PC-100/PC-100C thermal printer had an undocumented quirk: interrupting it mid-character exposes partial print heads, which the TI PPC user community turned into a small genre of printer-graphics demos through the early 1980s.",
      items: [
        { file: "characters.ti59", title: "Print character table", description: "Prints the full TI-59 print-code table with row and column headers." },
        { file: "characters-fastmode.ti59", title: "Print characters in Fast Mode", description: "K-J Meusch's version of the character table, using Fast Mode to print far faster than normal execution (TI PPC Notes V5N9-10, 1980).", printer: true },
        { file: "fast-grafik-3d-plot-part1.ti59", title: "Fast-Grafik 3-D Plot — Part 1", description: "Peter Poloczek's 3-D surface plotter for the PC-100, built on the printer-interrupt trick (TI PPC Notes V8N2, 1983). Load Part 2 after this one finishes, without resetting.", printer: true },
        { file: "fast-grafik-3d-plot-part2.ti59", title: "Fast-Grafik 3-D Plot — Part 2", description: "The second half of Poloczek's 3-D plotter. Requires Part 1 to have already run in the same session.", printer: true },
        { file: "printer-quirks.ti59", title: "Printer interrupt character table", description: "Dave Leising's print-code table showing each character both normally and interrupted mid-print (PPX Exchange, March/April 1982).", printer: true },
        { file: "stars-and-stripes.ti59", title: "Stars & Stripes", description: "Richard Snow's demonstration of PC-100 graphics capability, drawing a flag using the printer-interrupt technique (TI PPC Notes V6N4-5, 1981).", printer: true },
        { file: "texas-print.ti59", title: "“TI” logo — high-resolution printer graphics", description: "Frank Dever's high-resolution “TI” logo (PPX Exchange, March/April 1982). The program corrupts a program-step keycode on purpose to redirect the ROM's dispatcher mid-instruction — the file's header traces exactly which ROM address that lands on.", printer: true },
        { file: "trace-quirk.ti59", title: "Printer trace-mode quirk", description: "A keystroke sequence, found by a TI PPC club member, that puts a TI-58 or TI-59 into an undocumented trace mode once a printer is attached (TI PPC Notes V6N4-5, 1981).", printer: true },
      ],
    },
    {
      heading: "Diagnostics and self-tests",
      intro: "Factory-style diagnostics for checking whether a TI-59 or TI-58 is healthy — useful background if you're troubleshooting real hardware, and a good stress test for the emulation core.",
      items: [
        { file: "diag.ti59", title: "TI-59 calculator diagnostic", description: "The magnetic-card diagnostic Texas Instruments documented in the owner's manual, both card sides. Prints and displays “−.8888888888” when everything checks out.", printer: true },
        { file: "diag.ti58", title: "TI-58 calculator diagnostic", description: "The same diagnostic, resized to fit the TI-58's smaller memory partition.", printer: true },
        { file: "ram_test.ti59", title: "RAM test", description: "A roughly three-minute test of all data registers that prints “598-TEST-1” and reports the default memory partition; faulty registers are called out by address." },
        { file: "ram_test_full_fast.ti59", title: "Full RAM test (Fast Mode)", description: "George Thomson's test of all 100 data registers using indirect addressing and the STF fast-mode trick, printing any mismatch on the PC-100A/PC-100C (TI PPC Notes V9N5, 1985).", printer: true },
        { file: "repartition.ti58c", title: "TI-58C repartitioning reference", description: "Keystroke notes on how the TI-58C's constant-memory feature stores the partition setting, and how to reach the extra 32 steps (480–511) that are otherwise keyboard-only (TI PPC Notes V5N7, 1980)." },
      ],
    },
    {
      heading: "Fast Mode, keycodes and firmware curiosities",
      intro: "Fast Mode is an undocumented TI-58/TI-58C/TI-59 execution mode, discovered and written up by the TI PPC club over several years — these programs demonstrate it, along with a couple of other undocumented corners of the ROM.",
      items: [
        { file: "fastmode.ti59", title: "Fast Mode factorial demo (TI-59)", description: "Computes factorials in both normal and Fast Mode so the roughly 70% speed difference is directly comparable — 10! in about 4.6 seconds, 69! in about 31." },
        { file: "fastmode.ti58", title: "Fast Mode factorial demo (TI-58)", description: "The same Fast Mode factorial comparison, for the TI-58/TI-58C." },
        { file: "FastMode_Zero4.ti59", title: "Fast Mode zero-padding bug", description: "A mistyped Fast Mode program — one leading zero short of the documented five — that puts a real TI-59 into an unusual, reproducible misbehaving state. Kept as a regression case; it also uncovered a display-refresh bug in the emulator, fixed before v1.0.0." },
        { file: "firmware.ti59", title: "Firmware listing keystroke sequence", description: "An unusual keyboard sequence, originally described by TI PPC Notes editor Maurice Swinnen, that puts the TI-59 into a mode where the ROM firmware itself can be listed." },
        { file: "keycodes.ti59", title: "Print all keycodes", description: "Jared Weinberger's routine for generating and printing every TI-59 key code, using dynamic program-code modification (TI PPC Notes V5N4-5, 1980)." },
      ],
    },
    {
      heading: "Utilities",
      intro: "Small, self-contained programs that aren't tied to a particular magazine series.",
      items: [
        { file: "Integer-Base-Conversion.ti59", title: "Integer base conversion", description: "Converts an integer between arbitrary number bases — hex to binary to decimal and back — originally published in Computer Design magazine, 1980." },
        { file: "Frequency-Transformation.ti59", title: "Frequency transformation", description: "A filter-design program that transforms a normalized low-pass filter's cutoff frequencies, from the Artech House discrete-time filter design tables." },
        { file: "sum.ti59", title: "Sum of N numbers", description: "A deliberately simple program — sums N down to 1 — useful as a stopwatch for comparing execution speed across devices running the emulator." },
      ],
    },
    {
      heading: "CPU-level assembly examples",
      intro: "These target the TMC0501 CPU inside the calculator directly, as raw opcodes rather than a keystroke program, loaded through the app's Debug panel ASM Overlay. They only run in the native Mac/iPhone/iPad app, not the browser emulator below.",
      items: [
        { file: "assembly/simple_count.asm", title: "Simple counter", description: "The smallest useful ASM overlay example: increments a counter on the display in a tight loop, about 1185 times a second." },
        { file: "assembly/stopwatch.asm", title: "Stopwatch", description: "A precisely timed stopwatch built on the WAIT Dn instruction rather than counting cycles — 222 increments per second, 4.5011 ms each." },
        { file: "assembly/DPT.asm", title: "Decimal-point / LED afterglow test", description: "Cycles the decimal-point-and-comma nibble across every digit position, demonstrating the emulator's simulated LED afterglow." },
        { file: "assembly/Decoder.asm", title: "7-segment decoder edge case (known non-working)", description: "A real-hardware timing edge case — a phase-shifted WAIT before SET IDLE exposes all 16 hex segment patterns on real silicon. Documented here for the CPU-emulation detail, but it does not reproduce on Calc-U 59: the emulator's display is a phase-independent snapshot, so the timing quirk this program depends on has nothing to act on." },
      ],
    },
  ];

  return (
    <main className="wrap-narrow">
      <p className="eyebrow">Software</p>
      <h1 className="page-title">TI-59 Software Collection</h1>
      <p className="lede">
        Programs written for real TI-59, TI-58 and TI-58C hardware, from the 1978 <em>52-Notes</em> calendar
        competition to TI PPC club printer-graphics tricks and factory diagnostics — collected here as
        loadable state files, whether or not you have Calc-U 59 installed yet.
      </p>

      <div className="panel" style={{ padding: 20, marginTop: 24, lineHeight: 1.7 }}>
        <p style={{ marginTop: 0 }}>
          Each entry below is a <strong>.ti59</strong>, <strong>.ti58</strong> or <strong>.ti58c</strong>{" "}
          <a href="/state-files/">state file</a> — the calculator's program, registers and (where the
          original used one) magnetic-card cue card, ready to load. Programs marked <strong>Requires printer</strong>{" "}
          need the emulated PC-100/PC-100C — available in the full app, not the browser emulator below.
        </p>
        <p style={{ marginBottom: 0 }}>
          Get <a href="/install/mac/">Calc-U 59 for Mac</a> or{" "}
          <a href="/install/iphone-ipad/">for iPhone and iPad</a>, then open a downloaded file, or try the{" "}
          <a href="/play/">browser emulator</a> first — it has no printer, but the utilities below that don't
          need one will run.
        </p>
      </div>

      {categories.map((cat) => (
        <React.Fragment key={cat.heading}>
          <h2 className="section">{cat.heading}</h2>
          <p style={{ color: "var(--fg-2)", lineHeight: 1.7, marginTop: -8 }}>{cat.intro}</p>
          <div style={{ display: "grid", gap: 12 }}>
            {cat.items.map((it) => (
              <div key={it.file} className="panel" style={{ padding: 20, lineHeight: 1.7 }}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", flexWrap: "wrap", gap: "4px 16px" }}>
                  <h3 className="sub" style={{ margin: 0 }}>{it.title}</h3>
                  <a className="btn secondary" href={`/software-files/${it.file}`} download>
                    Download {it.file.replace(/^assembly\//, "")}
                  </a>
                </div>
                <p style={{ margin: "8px 0 0", color: "var(--fg-2)" }}>{it.description}</p>
                {it.printer ? (
                  <p style={{ margin: "8px 0 0", fontSize: 13, color: "var(--fg-3)" }}>Requires the PC-100/PC-100C printer.</p>
                ) : null}
              </div>
            ))}
          </div>
        </React.Fragment>
      ))}

      <h2 className="section">Source and format</h2>
      <div className="prose panel" style={{ padding: 20, lineHeight: 1.7 }}>
        <p style={{ marginTop: 0 }}>
          These files are maintained in the <a href="https://github.com/tinue/Calc-U-59/tree/main/examples">
          examples/ directory</a> of the Calc-U 59 repository — its name predates this collection outgrowing
          "examples" — together with a few internal debugging and screenshot-test files not listed here. The{" "}
          <a href="/state-files/">state file format</a> and the debugger's ASM Overlay are both documented if
          you want to write your own.
        </p>
        <p style={{ marginBottom: 0, color: "var(--fg-3)", fontSize: 13 }}>
          Most of these programs were originally published in <em>52-Notes</em>, <em>TI PPC Notes</em> and{" "}
          <em>PPX Exchange</em> — the newsletters of the TI Programmable Calculator user community in the
          late 1970s and early 1980s — or on the{" "}
          <a href="https://www.hpmuseum.org/forum/">HP Museum forum</a>, where TI material is also archived and
          discussed.
        </p>
      </div>

      <div style={{ marginTop: 24 }}>
        <BackButton onNav={onNav} />
      </div>
    </main>
  );
}

// PlayCalculator lays itself out from a fixed 360px grid multiplied by
// `scale`, so a constant 1.4 is a hard 504px — wider than any iPhone in
// portrait, which is why the fifth key column used to run off the page.
// Measure the container instead of the window: .wrap-narrow's gutters change
// at the 620px breakpoint, and the element already knows what it was given.
function useFittedScale(max, min) {
  const ref = React.useRef(null);
  const [scale, setScale] = React.useState(max);
  React.useEffect(() => {
    const el = ref.current;
    if (!el) return;
    function measure() {
      // 8px: the focus ring PlayCalculator permanently reserves around itself.
      setScale(Math.max(min, Math.min(max, (el.clientWidth - 8) / 360)));
    }
    measure();
    if (typeof ResizeObserver === "undefined") {
      window.addEventListener("resize", measure);
      return () => window.removeEventListener("resize", measure);
    }
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, [max, min]);
  return [ref, scale];
}

function PlayPage({ onNav }) {
  const [holderRef, scale] = useFittedScale(1.4, 0.7);
  return (
    <main className="wrap-narrow">
      <div ref={holderRef} style={{ display: "flex", justifyContent: "center" }}>
        <PlayCalculator scale={scale} keyboard />
      </div>
      <div style={{ textAlign: "center", marginTop: 12 }}>
        <a className="btn secondary" href="/app/">Open as a standalone app <span style={{opacity:.5}}>→</span></a>
      </div>

      <h1 className="page-title" style={{ marginTop: 32 }}>TI-59 emulator, online</h1>
      <div className="prose">
        <p>
          The calculator above is a working <strong>Texas Instruments TI-59 emulator running in
          your browser</strong> — no install, no account, nothing to download. It is the real
          emulation core from the Calc-U 59 app, compiled to WebAssembly, executing the original
          TI-59 ROM. Debugger, printer, and card reader are not part of this build;
          everything else works.
        </p>
        <p>
          Module 01 (Master Library) is loaded by default. Switch modules, load one of the curated
          presets, or upload your own <strong>.ti59</strong> file below the keyboard — uploads are
          read entirely in your browser and never leave your machine. For more programs to try,
          including several that need the full app's PC-100 printer, see the{" "}
          <a href="/software/">TI-59 Software Collection</a>.
        </p>
        <p>
          Press <strong>2nd</strong> then <strong>Pgm</strong> then a two-digit program number to
          bring up that program's cue card, the same way it works on the module itself.
        </p>
        <p>
          For the TI-58 and TI-58C models, the PC-100C printer, magnetic cards and the CPU
          debugger, use the full app: <a href="/install/mac/">free on the Mac</a>, or{" "}
          <a href="/install/iphone-ipad/">on the App Store</a> for iPhone and iPad. If you are
          not sure what any of this is, <a href="/what-is-a-ti-59/">start here</a>.
        </p>
        <p>
          Prefer this without the browser chrome? <a href="/app/">Open the standalone app</a> — the
          same calculator alone at its own address, installable to your phone's home screen for a
          one-tap, full-screen launch.
        </p>
      </div>

      <h2 className="section" style={{ marginTop: 32 }}>Use your keyboard</h2>
      <div className="prose">
        <p>
          Click the calculator once and it takes your keystrokes — a golden outline shows when it
          has them. Click anywhere else, or press <K>Tab</K>, and the page gets the keyboard back.
        </p>
        <p>
          The number keys, the yellow operation keys, <strong>A</strong>–<strong>E</strong>, and
          <strong> EE</strong> <strong>(</strong> <strong>)</strong> are typeable. Everything else —
          2nd, STO, RCL, LRN and the rest — is click-only, so the keyboard stays out of the way of
          the page. Holding <K>Shift</K> while you press a letter gives you that key's second
          function: <K>Shift</K> + <K>A</K> is <strong>A'</strong>.
        </p>
      </div>

      <KeyboardLegend />

      <div style={{ marginTop: 24 }}>
        <BackButton onNav={onNav} />
      </div>
    </main>
  );
}

// Rendered straight from keyboard-map.js's own table, so the published legend
// can't drift away from the bindings that actually run.
function KeyboardLegend() {
  if (typeof TI59_KEYBOARD_LEGEND === "undefined") return null;
  return (
    <div style={{
      marginTop: 16,
      display: "grid",
      gridTemplateColumns: "repeat(auto-fill, minmax(190px, 1fr))",
      gap: "10px 20px",
    }}>
      {TI59_KEYBOARD_LEGEND.map((entry, i) => (
        <div key={i} style={{ display: "flex", alignItems: "baseline", gap: 8 }}>
          <span style={{ flex: "0 0 auto" }}>
            <KSeq steps={entry.keys.map((k) => (k === "…" ? "…" : { label: k }))} />
          </span>
          <span style={{
            fontFamily: "var(--font-keycap)",
            color: "var(--accent)",
            fontSize: 14,
          }}>{entry.label}</span>
          {entry.note ? (
            <span style={{ fontFamily: "var(--font-body)", fontSize: 12, color: "var(--fg-3)" }}>
              {entry.note}
            </span>
          ) : null}
        </div>
      ))}
    </div>
  );
}

Object.assign(window, {
  HomePage,
  AboutTi59Page,
  GettingStartedPage,
  InstallMobilePage,
  InstallMacPage,
  StateFilesPage,
  DebuggerPage,
  ReferencePage,
  ModulesPage,
  FaqPage,
  PlayPage,
  SoftwarePage,
});
