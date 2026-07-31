// Calc-U 59 — Help site pages
// User scope: this guide explains the EMULATOR APP, not the underlying
// TI-59 calculator hardware.

const {
  useState: useStateApp
} = React;
const STARTED_SECTIONS = [{
  title: "Start here",
  items: [{
    id: "overview",
    label: "Overview",
    href: "/getting-started/"
  }]
}, {
  title: "Setup",
  items: [{
    id: "install-mobile",
    label: "Installing on iPhone and iPad",
    href: "/getting-started/install-iphone-ipad/"
  }, {
    id: "install-mac",
    label: "Installing on Mac",
    href: "/getting-started/install-mac/"
  }]
}, {
  title: "Using the emulator",
  items: [{
    id: "state-files",
    label: "Loading a state file",
    href: "/getting-started/state-files/"
  }, {
    id: "debugger",
    label: "Using the debugger",
    href: "/getting-started/debugger/"
  }, {
    id: "printer",
    label: "Printer and card reader",
    href: "/getting-started/printer/"
  }]
}, {
  title: "Help",
  items: [{
    id: "faq",
    label: "FAQ",
    href: "/getting-started/faq/"
  },
  // Not a page on this site: the README lives on GitHub, so this is an
  // ordinary outbound link rather than a route that would only exist to
  // point somewhere else.
  {
    id: "readme",
    label: "Main README",
    href: "https://github.com/tinue/Calc-U-59/blob/main/README.md",
    external: true
  }]
}];
function BackButton({
  label = "← Return to start",
  onNav,
  fallback = "home"
}) {
  function handleBack() {
    if (history.length > 1) {
      history.back();
    } else {
      onNav(fallback);
    }
  }
  return /*#__PURE__*/React.createElement("button", {
    className: "btn secondary",
    onClick: handleBack
  }, label);
}

/* =============================================================
   HOME — overview page.
   ============================================================= */
function HomePage({
  onNav
}) {
  return /*#__PURE__*/React.createElement("main", null, /*#__PURE__*/React.createElement("section", {
    style: {
      borderBottom: "1px solid var(--stroke)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "wrap hero"
  }, /*#__PURE__*/React.createElement("div", {
    className: "hero-copy"
  }, /*#__PURE__*/React.createElement("p", {
    className: "eyebrow"
  }, "TI-59 emulator for Mac, iPhone and iPad"), /*#__PURE__*/React.createElement("h1", {
    className: "page-title"
  }, "Calc-U ", /*#__PURE__*/React.createElement("em", null, "59")), /*#__PURE__*/React.createElement("p", {
    className: "lede"
  }, "Calc-U 59 is a ", /*#__PURE__*/React.createElement("strong", {
    style: {
      color: "var(--fg)"
    }
  }, "TI-59, TI-58 and TI-58C emulator"), " for macOS, iPhone and iPad. It runs the original Texas Instruments ROM, reads and writes virtual magnetic cards, emulates the PC-100C printer and all fourteen Solid State Software modules, and includes a CPU-level debugger. You can ", /*#__PURE__*/React.createElement("a", {
    href: "/play/"
  }, "try it in your browser"), " before you install anything."), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      gap: 12,
      flexWrap: "wrap"
    }
  }, /*#__PURE__*/React.createElement("a", {
    className: "btn primary",
    href: "/getting-started/",
    style: {
      textDecoration: "none"
    }
  }, "Getting started ", /*#__PURE__*/React.createElement("span", {
    style: {
      opacity: .5
    }
  }, "\u2192")), /*#__PURE__*/React.createElement("a", {
    className: "btn secondary",
    href: "/reference/",
    style: {
      textDecoration: "none"
    }
  }, "App reference"))), /*#__PURE__*/React.createElement("div", {
    className: "hero-shot"
  }, /*#__PURE__*/React.createElement("img", {
    src: "/assets/app-screenshot.png",
    alt: "The Calc-U 59 TI-59 emulator running on an iPhone, showing the red LED display, the cue card and the full key matrix"
  })), /*#__PURE__*/React.createElement("div", {
    className: "hero-cards grid-2"
  }, /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 16
    }
  }, /*#__PURE__*/React.createElement("h3", {
    className: "sub",
    style: {
      margin: "0 0 6px"
    }
  }, "iPhone and iPad"), /*#__PURE__*/React.createElement("p", {
    style: {
      margin: 0,
      fontSize: 14,
      lineHeight: 1.6
    }
  }, "Install from the App Store, then open the app and pick a model. State files load from the file picker inside the app.")), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 16
    }
  }, /*#__PURE__*/React.createElement("h3", {
    className: "sub",
    style: {
      margin: "0 0 6px"
    }
  }, "Mac"), /*#__PURE__*/React.createElement("p", {
    style: {
      margin: 0,
      fontSize: 14,
      lineHeight: 1.6
    }
  }, "Download the release from GitHub, drag the app to Applications, then use right-click ", /*#__PURE__*/React.createElement("strong", null, "Open"), " the first time if macOS blocks it."))))), /*#__PURE__*/React.createElement("div", {
    className: "wrap"
  }, /*#__PURE__*/React.createElement("h2", {
    className: "section"
  }, "Where to start"), /*#__PURE__*/React.createElement("div", {
    className: "grid-3"
  }, /*#__PURE__*/React.createElement(TopicCard, {
    num: "01",
    eyebrow: "Setup",
    title: "Installing on iPhone and iPad",
    href: "/install/iphone-ipad/"
  }, "The App Store install path, plus what happens on first launch."), /*#__PURE__*/React.createElement(TopicCard, {
    num: "02",
    eyebrow: "Setup",
    title: "Installing on Mac",
    href: "/install/mac/"
  }, "GitHub Releases, the DMG, and Gatekeeper the first time you open the app."), /*#__PURE__*/React.createElement(TopicCard, {
    num: "03",
    eyebrow: "Files",
    title: "Loading a state file",
    href: "/state-files/"
  }, "What a .ti59 file contains and how the parser treats each section."), /*#__PURE__*/React.createElement(TopicCard, {
    num: "04",
    eyebrow: "Debug",
    title: "Using the debugger",
    href: "/debugger/"
  }, "CALCULATOR, CPU, LOG, freeze/step, and the binary trace file."), /*#__PURE__*/React.createElement(TopicCard, {
    num: "05",
    eyebrow: "Hardware",
    title: "Printer and card reader",
    href: "/getting-started/printer/"
  }, "What the PC-100C panel does and how card files are managed."), /*#__PURE__*/React.createElement(TopicCard, {
    num: "06",
    eyebrow: "Help",
    title: "FAQ",
    href: "/faq/"
  }, "Answers to the questions users actually hit first.")), /*#__PURE__*/React.createElement("h2", {
    className: "section"
  }, "What Calc-U 59 emulates"), /*#__PURE__*/React.createElement("div", {
    className: "prose panel",
    style: {
      padding: 20,
      lineHeight: 1.7
    }
  }, /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 0
    }
  }, "Calc-U 59 emulates the ", /*#__PURE__*/React.createElement("strong", null, "TI Programmable 59"), " that Texas Instruments introduced in 1977, along with its two smaller siblings, the ", /*#__PURE__*/React.createElement("strong", null, "TI-58"), " and the constant-memory ", /*#__PURE__*/React.createElement("strong", null, "TI-58C"), ". It is not a reimplementation of the maths in Swift: the app runs the calculators' original ROM through an emulated TMC0501 processor, so AOS precedence, the 13-digit internal precision, the flashing overflow display and the documented quirks all behave the way the hardware did."), /*#__PURE__*/React.createElement("ul", {
    style: {
      margin: "0 0 12px",
      paddingLeft: 20
    }
  }, /*#__PURE__*/React.createElement("li", null, "Switchable ", /*#__PURE__*/React.createElement("strong", null, "TI-59 / TI-58 / TI-58C"), " models, with the correct memory partition and startup state for each."), /*#__PURE__*/React.createElement("li", null, "All fourteen ", /*#__PURE__*/React.createElement("strong", null, "Solid State Software"), " library modules, from the Master Library to the RPN Simulator \u2014 ", /*#__PURE__*/React.createElement("a", {
    href: "/modules/"
  }, "see the full list"), "."), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "Magnetic cards"), " read and written as files, synced between your devices over iCloud."), /*#__PURE__*/React.createElement("li", null, "The ", /*#__PURE__*/React.createElement("strong", null, "PC-100C thermal printer"), ", in both a dot-matrix view and a copyable text view."), /*#__PURE__*/React.createElement("li", null, "A ", /*#__PURE__*/React.createElement("a", {
    href: "/debugger/"
  }, "CPU-level debugger"), " with a live program listing, a ROM instruction trace, and binary trace capture for offline analysis."), /*#__PURE__*/React.createElement("li", null, "Plain-text ", /*#__PURE__*/React.createElement("a", {
    href: "/state-files/"
  }, ".ti59 state files"), " that carry a program, the registers, a cue card and a module selection in one readable file.")), /*#__PURE__*/React.createElement("p", {
    style: {
      marginBottom: 0
    }
  }, "New to these machines, or trying to work out which model you owned?", " ", /*#__PURE__*/React.createElement("a", {
    href: "/what-is-a-ti-59/"
  }, "Start with the background on the TI-59 and TI-58 \u2192"))), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      marginTop: 48,
      display: "flex",
      alignItems: "center",
      gap: 24
    }
  }, /*#__PURE__*/React.createElement("img", {
    src: "/assets/app-icon.png",
    alt: "",
    style: {
      width: 80,
      height: 80,
      borderRadius: 18,
      flex: "0 0 auto"
    }
  }), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("h3", {
    className: "sub",
    style: {
      margin: "0 0 4px"
    }
  }, "Available now"), /*#__PURE__*/React.createElement("p", {
    style: {
      margin: 0,
      fontSize: 14
    }
  }, "The Mac build ships free from ", /*#__PURE__*/React.createElement("a", {
    href: "https://github.com/tinue/Calc-U-59/releases/latest"
  }, "GitHub Releases"), ". The iPhone and iPad build is on the ", /*#__PURE__*/React.createElement("a", {
    href: "https://apps.apple.com/us/app/calc-u-59/id6761413142"
  }, "App Store"), ". The source code is on ", /*#__PURE__*/React.createElement("a", {
    href: "https://github.com/tinue/Calc-U-59"
  }, "GitHub"), ".")))));
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
function AboutTi59Page({
  onNav
}) {
  const models = [{
    code: "TI-59",
    name: "TI Programmable 59",
    year: "May 1977",
    body: "The top of the range. Up to 960 program steps or 100 data registers, traded against each other in steps of 80 and 10, plus a magnetic card reader in the side for saving programs. Memory was volatile: switch it off and the program was gone unless it was on a card."
  }, {
    code: "TI-58",
    name: "TI Programmable 58",
    year: "May 1977",
    body: "The same calculator with half the memory — up to 480 steps or 60 registers — and no card reader. Library modules still worked, so it lost storage rather than capability."
  }, {
    code: "TI-58C",
    name: "TI Programmable 58C",
    year: "1979",
    body: "A TI-58 with constant memory. The C is the whole point: programs and registers survived being switched off, which removed most of the reason to want a card reader in the first place."
  }];
  return /*#__PURE__*/React.createElement("main", {
    className: "wrap-narrow"
  }, /*#__PURE__*/React.createElement("p", {
    className: "eyebrow"
  }, "Background"), /*#__PURE__*/React.createElement("h1", {
    className: "page-title"
  }, "What is a TI-59?"), /*#__PURE__*/React.createElement("p", {
    className: "lede"
  }, "A short orientation to the Texas Instruments TI-59, TI-58 and TI-58C \u2014 the machines Calc-U 59 emulates \u2014 for anyone who arrived here looking for one and wants to know what they are dealing with."), /*#__PURE__*/React.createElement("div", {
    className: "prose",
    style: {
      marginTop: 24
    }
  }, /*#__PURE__*/React.createElement("p", null, "The ", /*#__PURE__*/React.createElement("strong", null, "TI Programmable 59"), " was Texas Instruments' flagship programmable calculator, introduced on 24 May 1977 at a list price of around $300. It succeeded the SR-52, and for the rest of the decade it was the machine engineers, surveyors, navigators and financial analysts actually carried. Its rival was the Hewlett-Packard HP-67; the TI had roughly twice the memory, the HP had RPN and better build quality, and people argued about it for years."), /*#__PURE__*/React.createElement("p", null, "You programmed it by recording keystrokes. In learn mode every key you pressed became a program step, and the ten user-defined keys \u2014 ", /*#__PURE__*/React.createElement(K, {
    tone: "dark"
  }, "A"), " through", " ", /*#__PURE__*/React.createElement(K, {
    tone: "dark"
  }, "E"), " and their primed second functions \u2014 were the entry points. That sounds primitive, and it is, but the instruction set includes conditionals, loops, subroutines and indirect register addressing, which makes the TI-59 Turing-complete. People wrote games for it.")), /*#__PURE__*/React.createElement("h2", {
    className: "section"
  }, "The three models"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "grid",
      gap: 12
    }
  }, models.map(m => /*#__PURE__*/React.createElement("div", {
    key: m.code,
    className: "panel",
    style: {
      padding: 20,
      lineHeight: 1.7
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "baseline",
      gap: 12,
      marginBottom: 6
    }
  }, /*#__PURE__*/React.createElement("h3", {
    className: "sub",
    style: {
      margin: 0
    }
  }, m.code), /*#__PURE__*/React.createElement("span", {
    style: {
      color: "var(--fg-3)",
      fontSize: 13
    }
  }, m.name, " \xB7 ", m.year)), /*#__PURE__*/React.createElement("p", {
    style: {
      margin: 0,
      color: "var(--fg-2)"
    }
  }, m.body)))), /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 12,
      color: "var(--fg-2)",
      lineHeight: 1.7
    }
  }, "Calc-U 59 emulates all three. The model selector in the bottom toolbar switches between them, and each starts with the memory partition and power-on state that model really had."), /*#__PURE__*/React.createElement("h2", {
    className: "section"
  }, "Algebraic Operating System"), /*#__PURE__*/React.createElement("div", {
    className: "prose panel",
    style: {
      padding: 20,
      lineHeight: 1.7
    }
  }, /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 0
    }
  }, "These calculators use ", /*#__PURE__*/React.createElement("strong", null, "AOS"), " \u2014 Algebraic Operating System \u2014 rather than the RPN found on contemporary Hewlett-Packard machines. You enter an expression roughly as it is written on paper, with up to nine levels of parentheses, and the calculator applies operator precedence when you press ", /*#__PURE__*/React.createElement(K, {
    tone: "yellow"
  }, "="), ". Emulating AOS convincingly is the part that catches out reimplementations: the pending-operation stack has observable edge cases that only fall out correctly if you run the original ROM, which is what Calc-U 59 does."), /*#__PURE__*/React.createElement("p", {
    style: {
      marginBottom: 0
    }
  }, "One of the library modules, ", /*#__PURE__*/React.createElement("strong", null, "RP"), ", is an RPN Simulator \u2014 Texas Instruments shipped a way to make its algebraic calculator behave like an HP.")), /*#__PURE__*/React.createElement("h2", {
    className: "section"
  }, "Magnetic cards"), /*#__PURE__*/React.createElement("div", {
    className: "prose panel",
    style: {
      padding: 20,
      lineHeight: 1.7
    }
  }, /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 0
    }
  }, "The TI-59's card reader took small magnetic strips, one quarter of the machine's memory per side. The card did double duty: once read, it slid into a slot above the keyboard so the labels written along its top edge sat directly beneath the", " ", /*#__PURE__*/React.createElement(K, {
    tone: "dark"
  }, "A"), "\u2013", /*#__PURE__*/React.createElement(K, {
    tone: "dark"
  }, "E"), " keys and told you what each one did in the program you had just loaded. That is what the cue card on screen in Calc-U 59 is reproducing."), /*#__PURE__*/React.createElement("p", {
    style: {
      marginBottom: 0
    }
  }, "In the emulator, cards are files. They live in iCloud storage, so a program written on a Mac is on the iPhone by the time you pick it up. The card reader mechanism was also the most failure-prone part of the original hardware, which is a reasonable argument for emulating one instead of restoring one.")), /*#__PURE__*/React.createElement("h2", {
    className: "section"
  }, "Solid State Software modules"), /*#__PURE__*/React.createElement("div", {
    className: "prose panel",
    style: {
      padding: 20,
      lineHeight: 1.7
    }
  }, /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 0
    }
  }, "The TI-58 and TI-59 were the first handheld calculators with removable ROM program modules. A module held up to 5,000 program steps and ran straight from ROM, leaving user memory free. The Master Library came in the box; Applied Statistics, Surveying, Aviation, Marine Navigation, Securities Analysis and the rest were sold separately, and the complete set is now hard to find and expensive."), /*#__PURE__*/React.createElement("p", {
    style: {
      marginBottom: 0
    }
  }, "Calc-U 59 includes all fourteen. ", /*#__PURE__*/React.createElement("a", {
    href: "/modules/"
  }, "See the module list \u2192"))), /*#__PURE__*/React.createElement("h2", {
    className: "section"
  }, "The PC-100C printer"), /*#__PURE__*/React.createElement("div", {
    className: "prose panel",
    style: {
      padding: 20,
      lineHeight: 1.7
    }
  }, /*#__PURE__*/React.createElement("p", {
    style: {
      margin: 0
    }
  }, "The calculator docked into a thermal printer \u2014 the PC-100A, B or C \u2014 and locked in place with a key. Beyond printing results, it was how you got a readable listing of a program with mnemonics instead of raw numeric key codes, dumped the data registers, or traced execution. It is emulated in Calc-U 59, including the paper strip, which you can copy as plain text rather than squinting at dot-matrix output.", " ", /*#__PURE__*/React.createElement("a", {
    href: "/getting-started/printer/"
  }, "Printer and card reader \u2192"))), /*#__PURE__*/React.createElement("h2", {
    className: "section"
  }, "Try one"), /*#__PURE__*/React.createElement("div", {
    className: "prose panel",
    style: {
      padding: 20,
      lineHeight: 1.7
    }
  }, /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 0
    }
  }, "The quickest way to see whether this is the machine you remember is to use one. The", " ", /*#__PURE__*/React.createElement("a", {
    href: "/play/"
  }, "browser emulator"), " runs the same emulation core compiled to WebAssembly, with the Master Library loaded, and needs no installation. The full app, with the printer, the card reader and the debugger, is", " ", /*#__PURE__*/React.createElement("a", {
    href: "/install/mac/"
  }, "free on the Mac"), " and", " ", /*#__PURE__*/React.createElement("a", {
    href: "/install/iphone-ipad/"
  }, "on the App Store"), " for iPhone and iPad."), /*#__PURE__*/React.createElement("p", {
    style: {
      marginBottom: 0,
      color: "var(--fg-3)",
      fontSize: 13
    }
  }, "For the original operating manuals, program libraries and the wider TI-59 community, start at ", /*#__PURE__*/React.createElement("a", {
    href: "https://www.ti59.com/"
  }, "ti59.com"), " and", " ", /*#__PURE__*/React.createElement("a", {
    href: "http://www.datamath.org/SCI/WEDGE/TI-59.htm"
  }, "datamath.org"), ". This site only documents the emulator.")), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 24
    }
  }, /*#__PURE__*/React.createElement(BackButton, {
    onNav: onNav
  })));
}

/* =============================================================
   GETTING STARTED — practical install, file, and debug guidance.
   ============================================================= */
// "overview" is the default because /getting-started/ is a hub: it is the
// most-linked page on the site and sits in the header nav. Defaulting to a
// topic would make it a byte-identical twin of that topic's own URL.
function GettingStartedPage({
  initialTopic = "overview",
  onNav
}) {
  const [topic, setTopic] = useStateApp(initialTopic);
  function handlePick(id) {
    setTopic(id);
    if (onNav) onNav({
      page: "start",
      topic: id
    });
  }
  const titles = {
    overview: "Getting started with Calc-U 59",
    "install-mobile": "Installing on iPhone and iPad",
    "install-mac": "Installing on Mac",
    "state-files": "Loading a state file",
    debugger: "Using the debugger",
    printer: "Printer and card reader",
    faq: "FAQ"
  };
  const notes = {
    overview: "Install the app, load a state file, drive the printer and card reader, and find your way around the debugger.",
    "install-mobile": "Use the App Store build, then configure the model and load presets from inside the app.",
    "install-mac": "Download the release from GitHub, then drag the app to Applications.",
    "state-files": "What .ti59/.ti58/.ti58c files contain and how the parser treats each section.",
    debugger: "CALCULATOR, CPU, LOG, freeze/step, and binary trace output.",
    printer: "The PC-100C panel, paper strip, copy/cut, and card file behaviour.",
    faq: "Concise answers to the questions that usually come up first."
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
    overview: /*#__PURE__*/React.createElement("div", {
      style: {
        display: "grid",
        gap: 16,
        marginTop: 20
      }
    }, /*#__PURE__*/React.createElement("div", {
      className: "panel",
      style: {
        padding: 20,
        lineHeight: 1.7
      }
    }, /*#__PURE__*/React.createElement("p", {
      style: {
        marginTop: 0
      }
    }, "Calc-U 59 runs the original Texas Instruments ROM, so the calculator in front of you behaves the way a TI-59, TI-58 or TI-58C did in 1977 \u2014 the same AOS arithmetic, the same 480 program steps traded against 60 data registers, the same Solid State Software modules."), /*#__PURE__*/React.createElement("p", {
      style: {
        marginBottom: 0
      }
    }, "Most people need three things: get the app installed, open a state file, and know where the printer and the debugger live. Each is a short page.")), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "grid",
        gap: 12
      }
    }, /*#__PURE__*/React.createElement(TopicCard, {
      num: "01",
      eyebrow: "Setup",
      title: "Installing on iPhone and iPad",
      href: "/install/iphone-ipad/"
    }, "Install from the App Store, pick the calculator model, and open .ti59 files from the file picker."), /*#__PURE__*/React.createElement(TopicCard, {
      num: "02",
      eyebrow: "Setup",
      title: "Installing on Mac",
      href: "/install/mac/"
    }, "Download the release from GitHub, drag it to Applications, and get past the first-launch Gatekeeper prompt."), /*#__PURE__*/React.createElement(TopicCard, {
      num: "03",
      eyebrow: "Files",
      title: "Loading a state file",
      href: "/state-files/"
    }, "What .ti59, .ti58 and .ti58c files contain, and how each section \u2014 partition, program, registers, keystrokes \u2014 is applied."), /*#__PURE__*/React.createElement(TopicCard, {
      num: "04",
      eyebrow: "Hardware",
      title: "Printer and card reader",
      href: "/getting-started/printer/"
    }, "The PC-100C panel in dot and text view, printing and advancing paper, copying the strip, and where card files are kept."), /*#__PURE__*/React.createElement(TopicCard, {
      num: "05",
      eyebrow: "Debug",
      title: "Using the debugger",
      href: "/debugger/"
    }, "The CALCULATOR, CPU and LOG tabs, freeze and step, F.START, and binary trace files for offline analysis."), /*#__PURE__*/React.createElement(TopicCard, {
      num: "06",
      eyebrow: "Help",
      title: "FAQ",
      href: "/faq/"
    }, "Where files live, how to capture a trace, and the other questions that come up first."))),
    "install-mobile": /*#__PURE__*/React.createElement("div", {
      style: {
        display: "grid",
        gap: 16,
        marginTop: 20
      }
    }, /*#__PURE__*/React.createElement("div", {
      className: "panel",
      style: {
        padding: 20
      }
    }, /*#__PURE__*/React.createElement("h3", {
      className: "sub",
      style: {
        marginTop: 0
      }
    }, "iPhone and iPad"), /*#__PURE__*/React.createElement("ol", {
      style: {
        margin: 0,
        paddingLeft: 20,
        lineHeight: 1.7
      }
    }, /*#__PURE__*/React.createElement("li", null, "Open the App Store and install Calc-U 59."), /*#__PURE__*/React.createElement("li", null, "Launch the app and choose the calculator model in the toolbar or Settings."), /*#__PURE__*/React.createElement("li", null, "Use the preset file picker for .ti59, .ti58, or .ti58c files.")), /*#__PURE__*/React.createElement("p", {
      style: {
        marginBottom: 0,
        lineHeight: 1.65
      }
    }, "The mobile build uses the standard iOS app flow: there is no special setup beyond the App Store install."))),
    "install-mac": /*#__PURE__*/React.createElement("div", {
      style: {
        display: "grid",
        gap: 16,
        marginTop: 20
      }
    }, /*#__PURE__*/React.createElement("div", {
      className: "panel",
      style: {
        padding: 20
      }
    }, /*#__PURE__*/React.createElement("h3", {
      className: "sub",
      style: {
        marginTop: 0
      }
    }, "Mac"), /*#__PURE__*/React.createElement("ol", {
      style: {
        margin: 0,
        paddingLeft: 20,
        lineHeight: 1.7
      }
    }, /*#__PURE__*/React.createElement("li", null, "Download the latest release DMG from GitHub."), /*#__PURE__*/React.createElement("li", null, "Drag Calc-U-59.app to Applications."), /*#__PURE__*/React.createElement("li", null, "On first launch, use right-click ", /*#__PURE__*/React.createElement("strong", null, "Open"), " if Gatekeeper intervenes.")), /*#__PURE__*/React.createElement("p", {
      style: {
        marginBottom: 0,
        lineHeight: 1.65
      }
    }, "After that, macOS treats the app like any other notarized application."))),
    "state-files": /*#__PURE__*/React.createElement("div", {
      style: {
        display: "grid",
        gap: 16,
        marginTop: 20
      }
    }, /*#__PURE__*/React.createElement("div", {
      className: "panel",
      style: {
        padding: 20
      }
    }, /*#__PURE__*/React.createElement("p", {
      style: {
        marginTop: 0,
        lineHeight: 1.7
      }
    }, "State files are plain UTF-8 text. The parser understands a small set of section headers and ignores comments after ", /*#__PURE__*/React.createElement("strong", null, "#"), ". You can include only the sections you need."), /*#__PURE__*/React.createElement("pre", {
      style: {
        margin: 0,
        padding: 16,
        borderRadius: 8,
        background: "var(--bg-inset)",
        color: "var(--fg)",
        overflowX: "auto",
        lineHeight: 1.5,
        fontSize: 13
      }
    }, stateFileExample)), /*#__PURE__*/React.createElement("div", {
      className: "panel",
      style: {
        padding: 20,
        lineHeight: 1.7
      }
    }, /*#__PURE__*/React.createElement("p", {
      style: {
        marginTop: 0
      }
    }, /*#__PURE__*/React.createElement("strong", null, "PARTITION:"), " sets the step split between program memory and data registers. If it is omitted, the emulator uses the model default."), /*#__PURE__*/React.createElement("p", null, /*#__PURE__*/React.createElement("strong", null, "PROGRAM:"), " accepts sparse step listings, numeric keycodes, and the ", /*#__PURE__*/React.createElement("strong", null, "..."), " gap marker."), /*#__PURE__*/React.createElement("p", null, /*#__PURE__*/React.createElement("strong", null, "REGISTERS:"), " stores calculator variables as decimal numbers. On TI-58C, hidden registers can be written as ", /*#__PURE__*/React.createElement("strong", null, "H00"), " through ", /*#__PURE__*/React.createElement("strong", null, "H03"), "."), /*#__PURE__*/React.createElement("p", null, /*#__PURE__*/React.createElement("strong", null, "KEYSTROKES:"), " injects matrix codes after the file loads. Wait lines are allowed between groups."), /*#__PURE__*/React.createElement("p", null, /*#__PURE__*/React.createElement("strong", null, "CUECARD:"), " defines the on-screen cue card that appears with the loaded file or module."), /*#__PURE__*/React.createElement("p", {
      style: {
        marginBottom: 0
      }
    }, /*#__PURE__*/React.createElement("strong", null, "SOLID-STATE-MODULE:"), " and ", /*#__PURE__*/React.createElement("strong", null, "PRINTER:"), " let a file select the matching module and printer state automatically."))),
    debugger: /*#__PURE__*/React.createElement("div", {
      style: {
        display: "grid",
        gap: 16,
        marginTop: 20
      }
    }, /*#__PURE__*/React.createElement("div", {
      className: "panel",
      style: {
        padding: 20,
        lineHeight: 1.7
      }
    }, /*#__PURE__*/React.createElement("p", {
      style: {
        marginTop: 0
      }
    }, "The debug pane has three tabs: ", /*#__PURE__*/React.createElement("strong", null, "CALCULATOR"), ", ", /*#__PURE__*/React.createElement("strong", null, "CPU"), ", and ", /*#__PURE__*/React.createElement("strong", null, "LOG"), ". CALCULATOR shows the program listing and live register state, CPU is the instruction trace inspector, and LOG displays raw debug output plus the trace capture toggle."), /*#__PURE__*/React.createElement("p", {
      style: {
        marginBottom: 0
      }
    }, "The most powerful feature is the TRACE toggle in LOG\u2014it records a binary session file that you can export and analyze with the ", /*#__PURE__*/React.createElement("code", null, "read_trace.py"), " tool to understand ROM sequences in detail.")), /*#__PURE__*/React.createElement("div", {
      className: "panel",
      style: {
        padding: 20,
        lineHeight: 1.7
      }
    }, /*#__PURE__*/React.createElement("p", {
      style: {
        marginTop: 0
      }
    }, "Quick start:"), /*#__PURE__*/React.createElement("ol", {
      style: {
        margin: 0,
        paddingLeft: 20
      }
    }, /*#__PURE__*/React.createElement("li", null, "Use the CALCULATOR tab to inspect registers and step through your program."), /*#__PURE__*/React.createElement("li", null, "Switch to CPU if you want to trace the actual ROM instructions that ran (including jumps and subroutine calls)."), /*#__PURE__*/React.createElement("li", null, "Use TRACE in the LOG tab to capture a longer sequence (reset, keystroke processing, etc.) for offline analysis.")))),
    printer: /*#__PURE__*/React.createElement("div", {
      style: {
        display: "grid",
        gap: 16,
        marginTop: 20
      }
    }, /*#__PURE__*/React.createElement("div", {
      className: "panel",
      style: {
        padding: 20,
        lineHeight: 1.7
      }
    }, /*#__PURE__*/React.createElement("p", {
      style: {
        marginTop: 0
      }
    }, "The printer view mimics the PC-100C. Use the on/off badge at the top of the printer view to connect or disconnect it, then switch between dot view and text view depending on whether you want realism or easy copying."), /*#__PURE__*/React.createElement("p", null, /*#__PURE__*/React.createElement("strong", null, "PRINT"), " feeds output, ", /*#__PURE__*/React.createElement("strong", null, "ADV"), " advances the paper, and the copy and cut buttons are available on all builds (including iOS and iPadOS) for clipboard/export work."), /*#__PURE__*/React.createElement("p", {
      style: {
        marginBottom: 0
      }
    }, "If you enable printer trace in the app, the emulator records printer activity together with the rest of the session state.")), /*#__PURE__*/React.createElement("div", {
      className: "panel",
      style: {
        padding: 20,
        lineHeight: 1.7
      }
    }, /*#__PURE__*/React.createElement("p", {
      style: {
        marginTop: 0,
        marginBottom: 0
      }
    }, "Card files live in the app\u2019s card storage and can be loaded or saved from the card picker. The app filters the visible files to the supported card extensions and hides the iCloud placeholder entries."))),
    faq: /*#__PURE__*/React.createElement("div", {
      style: {
        display: "grid",
        gap: 8,
        marginTop: 20
      }
    }, [{
      q: "Where do state files live?",
      a: "They are regular .ti59, .ti58, or .ti58c text files. On Mac, the preset picker opens them from disk; on iPhone and iPad, use the built-in file picker."
    }, {
      q: "What should I check first if a file opens wrong?",
      a: "Check the partition, then the selected module, then the printer setting. Those three control the most visible parts of a loaded preset."
    }, {
      q: "Can I see what the emulator is doing internally?",
      a: "Yes. Use the debug pane: CALCULATOR for program state and live registers, CPU for the ROM instruction trace, and LOG for text output plus trace controls. For analyzing sequences, TRACE is more useful than the CPU tab."
    }, {
      q: "How do I get a trace file?",
      a: "Open the debug pane, switch to LOG, and turn TRACE on. The app writes a binary session file to the configured trace location. You can then export it and analyze it with read_trace.py."
    }, {
      q: "What does the CALCULATOR tab show versus the CPU tab?",
      a: "CALCULATOR shows the instruction that will execute next, with registers in their current state before it runs. CPU shows instructions that already ran, with registers in the state after each one. STEP and RESUME also work differently per tab and are only enabled in the tab that caused the current freeze — using them in the wrong tab is prevented."
    }, {
      q: "My trace file is 190 MB. Is that normal?",
      a: "Yes, for long sessions. But when you convert it to text with read_trace.py using the --clean and --skip-repeating flags, it compresses to a fraction of that size because the tool deduplicates repetitive loops."
    }, {
      q: "Why does the display look different between models?",
      a: "Calc-U 59 can start in TI-59, TI-58, or TI-58C mode. The model affects the startup state, memory layout, and the available controls."
    }, {
      q: "Is there a faster way to read long printer output?",
      a: "Yes. Switch the printer view to text mode, then copy or cut the strip on any build if you want a plain-text version quickly."
    }].map((item, i) => /*#__PURE__*/React.createElement("div", {
      key: i,
      className: "panel",
      style: {
        padding: "16px 20px",
        display: "grid",
        gap: 8
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: {
        fontFamily: "var(--font-key)",
        fontWeight: 700,
        fontSize: 16,
        textTransform: "uppercase",
        letterSpacing: ".05em",
        color: "var(--fg)"
      }
    }, item.q), /*#__PURE__*/React.createElement("p", {
      style: {
        margin: 0,
        lineHeight: 1.7,
        color: "var(--fg-2)"
      }
    }, item.a))))
  };
  return /*#__PURE__*/React.createElement("main", {
    className: "wrap docs-layout"
  }, /*#__PURE__*/React.createElement(DocsSidebar, {
    current: topic,
    onPick: handlePick,
    sections: STARTED_SECTIONS
  }), /*#__PURE__*/React.createElement("article", {
    className: "prose docs-article"
  }, /*#__PURE__*/React.createElement("p", {
    className: "eyebrow"
  }, "Getting started"), /*#__PURE__*/React.createElement("h1", {
    className: "page-title compact"
  }, titles[topic]), /*#__PURE__*/React.createElement("p", {
    className: "lede"
  }, notes[topic]), topicBody[topic]));
}

/* =============================================================
   DETAIL PAGES — dedicated targets for home topic cards.
   ============================================================= */
function InstallMobilePage({
  onNav
}) {
  return /*#__PURE__*/React.createElement("main", {
    className: "wrap-narrow"
  }, /*#__PURE__*/React.createElement("p", {
    className: "eyebrow"
  }, "Setup"), /*#__PURE__*/React.createElement("h1", {
    className: "page-title"
  }, "Installing on iPhone and iPad"), /*#__PURE__*/React.createElement("p", {
    className: "lede"
  }, "Use the App Store build, then configure the model and load presets from inside the app."), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 20,
      lineHeight: 1.7,
      marginTop: 24
    }
  }, /*#__PURE__*/React.createElement("ol", {
    style: {
      margin: 0,
      paddingLeft: 20
    }
  }, /*#__PURE__*/React.createElement("li", null, "Open the ", /*#__PURE__*/React.createElement("a", {
    href: "https://apps.apple.com/us/app/calc-u-59/id6761413142",
    style: {
      color: "var(--accent)",
      textDecoration: "none",
      borderBottom: "1px solid var(--accent)"
    }
  }, "App Store"), " and install Calc-U 59."), /*#__PURE__*/React.createElement("li", null, "Launch the app and choose the calculator model in the toolbar or Settings."), /*#__PURE__*/React.createElement("li", null, "Use the preset file picker for .ti59, .ti58, or .ti58c files."))), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 20,
      lineHeight: 1.7,
      marginTop: 12
    }
  }, /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 0
    }
  }, "The mobile build follows the standard iOS app flow: there is no extra setup after install."), /*#__PURE__*/React.createElement("p", {
    style: {
      marginBottom: 0
    }
  }, "On iPhone and on iPad in portrait, the calculator uses the same key layout as the app screenshot; on iPad in landscape, the layout mirrors the Mac view.")), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 24
    }
  }, /*#__PURE__*/React.createElement(BackButton, {
    onNav: onNav
  })));
}
function InstallMacPage({
  onNav
}) {
  return /*#__PURE__*/React.createElement("main", {
    className: "wrap-narrow"
  }, /*#__PURE__*/React.createElement("p", {
    className: "eyebrow"
  }, "Setup"), /*#__PURE__*/React.createElement("h1", {
    className: "page-title"
  }, "Installing on Mac"), /*#__PURE__*/React.createElement("p", {
    className: "lede"
  }, "Download the release from GitHub, then drag the app to Applications. On first launch, use right-click ", /*#__PURE__*/React.createElement("strong", null, "Open"), " if Gatekeeper blocks it."), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 20,
      lineHeight: 1.7,
      marginTop: 24
    }
  }, /*#__PURE__*/React.createElement("ol", {
    style: {
      margin: 0,
      paddingLeft: 20
    }
  }, /*#__PURE__*/React.createElement("li", null, "Download the latest release DMG from ", /*#__PURE__*/React.createElement("a", {
    href: "https://github.com/tinue/Calc-U-59/releases/latest",
    style: {
      color: "var(--accent)",
      textDecoration: "none",
      borderBottom: "1px solid var(--accent)"
    }
  }, "GitHub"), "."), /*#__PURE__*/React.createElement("li", null, "Double-click the DMG file to open it and show the installer window."), /*#__PURE__*/React.createElement("li", null, "Drag Calc-U-59.app to the Applications folder."), /*#__PURE__*/React.createElement("li", null, "Eject the disk image and launch the app from Applications."), /*#__PURE__*/React.createElement("li", null, "On first launch, if macOS blocks the app with a Gatekeeper prompt, right-click the app icon and choose ", /*#__PURE__*/React.createElement("strong", null, "Open"), " to approve it."))), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 20,
      lineHeight: 1.7,
      marginTop: 12
    }
  }, /*#__PURE__*/React.createElement("p", {
    style: {
      margin: 0
    }
  }, "After first approval, macOS treats the app like any other notarized application. You can then open it normally with a double-click.")), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 24
    }
  }, /*#__PURE__*/React.createElement(BackButton, {
    onNav: onNav
  })));
}
function StateFilesPage({
  onNav
}) {
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
  return /*#__PURE__*/React.createElement("main", {
    className: "wrap-narrow"
  }, /*#__PURE__*/React.createElement("p", {
    className: "eyebrow"
  }, "Files"), /*#__PURE__*/React.createElement("h1", {
    className: "page-title"
  }, "Loading a state file"), /*#__PURE__*/React.createElement("p", {
    className: "lede"
  }, "State files are plain UTF-8 text with named sections. You can include only the sections you need."), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 20,
      marginTop: 24
    }
  }, /*#__PURE__*/React.createElement("pre", {
    style: {
      margin: 0,
      padding: 16,
      borderRadius: 8,
      background: "var(--bg-inset)",
      color: "var(--fg)",
      overflowX: "auto",
      lineHeight: 1.5,
      fontSize: 13
    }
  }, stateFileExample)), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 20,
      lineHeight: 1.7,
      marginTop: 12
    }
  }, /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 0
    }
  }, /*#__PURE__*/React.createElement("strong", null, "PARTITION:"), " sets the step split between program memory and data registers."), /*#__PURE__*/React.createElement("p", null, /*#__PURE__*/React.createElement("strong", null, "PROGRAM:"), " accepts sparse step listings, numeric keycodes, and the ", /*#__PURE__*/React.createElement("strong", null, "..."), " gap marker."), /*#__PURE__*/React.createElement("p", null, /*#__PURE__*/React.createElement("strong", null, "REGISTERS:"), " stores calculator variables as decimal numbers."), /*#__PURE__*/React.createElement("p", null, /*#__PURE__*/React.createElement("strong", null, "KEYSTROKES:"), " injects matrix codes after the file loads. Wait lines are allowed between groups."), /*#__PURE__*/React.createElement("p", null, /*#__PURE__*/React.createElement("strong", null, "CUECARD:"), " defines the on-screen cue card that appears with the loaded file or module."), /*#__PURE__*/React.createElement("p", null, /*#__PURE__*/React.createElement("strong", null, "SOLID-STATE-MODULE:"), " and ", /*#__PURE__*/React.createElement("strong", null, "PRINTER:"), " let a file select the matching module and printer state automatically."), /*#__PURE__*/React.createElement("p", {
    style: {
      marginBottom: 0
    }
  }, "This page covers enough to load and tweak existing files. The complete grammar \u2014 matrix code table, 2nd-function presses, the CUECARD field list, and the math-notation shorthand used in cue cards \u2014 is developer documentation kept in the GitHub repository:", " ", /*#__PURE__*/React.createElement("a", {
    href: "https://github.com/tinue/Calc-U-59/blob/main/reference/StateFileFormat.md",
    style: {
      color: "var(--accent)",
      textDecoration: "none",
      borderBottom: "1px solid var(--accent)"
    }
  }, "reference/StateFileFormat.md \u2192"))), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 24
    }
  }, /*#__PURE__*/React.createElement(BackButton, {
    onNav: onNav
  })));
}
function DebuggerPage({
  onNav
}) {
  return /*#__PURE__*/React.createElement("main", {
    className: "wrap-narrow"
  }, /*#__PURE__*/React.createElement("p", {
    className: "eyebrow"
  }, "Debug"), /*#__PURE__*/React.createElement("h1", {
    className: "page-title"
  }, "Using the debugger"), /*#__PURE__*/React.createElement("p", {
    className: "lede"
  }, "The debug pane combines a program-level view, a CPU-level instruction trace, and a trace capture tool for analyzing the emulator's behavior in detail."), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 20,
      lineHeight: 1.7,
      marginTop: 24
    }
  }, /*#__PURE__*/React.createElement("h3", {
    className: "sub",
    style: {
      marginTop: 0,
      marginBottom: 12
    }
  }, "Overview"), /*#__PURE__*/React.createElement("p", {
    style: {
      margin: 0
    }
  }, "The debug pane has three tabs: ", /*#__PURE__*/React.createElement("strong", null, "CALCULATOR"), ", ", /*#__PURE__*/React.createElement("strong", null, "CPU"), ", and ", /*#__PURE__*/React.createElement("strong", null, "LOG"), "."), /*#__PURE__*/React.createElement("ul", {
    style: {
      margin: "8px 0 0",
      paddingLeft: 20
    }
  }, /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "CALCULATOR"), " \u2014 Program listing (copied from RAM), registers, flags, and HIR values at the current moment. Shows the instruction that will execute ", /*#__PURE__*/React.createElement("em", null, "next"), ". Useful for stepping through your own programs."), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "CPU"), " \u2014 Execution trace: the actual sequence of ROM instructions that ran. Shows the instruction that just ", /*#__PURE__*/React.createElement("em", null, "finished"), " and the register state ", /*#__PURE__*/React.createElement("em", null, "after"), " it executed. You can scroll back through the history."), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "LOG"), " \u2014 Raw debug output, SCOM register inspection, and the TRACE toggle. Most useful for capturing session files for deep analysis."))), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 20,
      lineHeight: 1.7,
      marginTop: 12
    }
  }, /*#__PURE__*/React.createElement("h3", {
    className: "sub",
    style: {
      marginTop: 0,
      marginBottom: 12
    }
  }, "CALCULATOR tab"), /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 0
    }
  }, "The CALCULATOR tab shows a window into program memory (copied from RAM) centred on the current step. The highlighted instruction is the one that will execute ", /*#__PURE__*/React.createElement("strong", null, "next"), ". After a jump (GTO, SBR, etc.) the listing jumps to the new location \u2014 it does not show where you came from, because it is not a trace."), /*#__PURE__*/React.createElement("p", null, "Registers and flags reflect the calculator state ", /*#__PURE__*/React.createElement("strong", null, "right now"), ", before the highlighted instruction runs."), /*#__PURE__*/React.createElement("p", {
    style: {
      marginBottom: 0
    }
  }, /*#__PURE__*/React.createElement("strong", null, "STEP in CALCULATOR mode"), " \u2014 pressing Step runs the CPU until the program counter changes (i.e. until the next user-visible step advances), then freezes again. This is the right tool for tracing through a keystroke-driven program one step at a time.")), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 20,
      lineHeight: 1.7,
      marginTop: 12
    }
  }, /*#__PURE__*/React.createElement("h3", {
    className: "sub",
    style: {
      marginTop: 0,
      marginBottom: 12
    }
  }, "CPU tab"), /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 0
    }
  }, "The CPU tab shows the actual ROM instructions that executed, in order. Each entry represents an instruction that ", /*#__PURE__*/React.createElement("strong", null, "already ran"), "; registers and flags are in the state ", /*#__PURE__*/React.createElement("em", null, "after"), " that instruction completed."), /*#__PURE__*/React.createElement("p", null, "Because it is a true execution trace, you can see jumps, subroutine calls, and PREG transitions \u2014 the address changes visibly in the listing. You can also scroll back through past entries to review earlier execution."), /*#__PURE__*/React.createElement("p", {
    style: {
      marginBottom: 0
    }
  }, /*#__PURE__*/React.createElement("strong", null, "STEP in CPU mode"), " \u2014 pressing Step executes exactly one ROM instruction, then freezes. This is the right tool when you want to follow the ROM's internal logic one opcode at a time."), /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 8,
      marginBottom: 0
    }
  }, /*#__PURE__*/React.createElement("strong", null, "Note on TEST/JUMP flags:"), " because state is captured ", /*#__PURE__*/React.createElement("em", null, "after"), " each instruction, a TEST shows the flag it set, but the following JUMP shows the auto-restored condition (usually 1). This is expected behaviour \u2014 it is not a bug.")), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 20,
      lineHeight: 1.7,
      marginTop: 12
    }
  }, /*#__PURE__*/React.createElement("h3", {
    className: "sub",
    style: {
      marginTop: 0,
      marginBottom: 12
    }
  }, "Freeze controls"), /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 0
    }
  }, "The toolbar above the debug pane offers ", /*#__PURE__*/React.createElement("strong", null, "FREEZE"), ", ", /*#__PURE__*/React.createElement("strong", null, "F.START"), " (Freeze on Start), ", /*#__PURE__*/React.createElement("strong", null, "ARMED"), ", ", /*#__PURE__*/React.createElement("strong", null, "RESUME"), ", and ", /*#__PURE__*/React.createElement("strong", null, "STEP"), "."), /*#__PURE__*/React.createElement("ul", {
    style: {
      margin: "8px 0",
      paddingLeft: 20
    }
  }, /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "FREEZE"), " \u2014 stops the CPU immediately."), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "F.START (CALCULATOR tab)"), " \u2014 arms the debugger so it freezes the first time the calculator-level program counter changes. This is triggered by pressing R/S, launching a program via a label, or any similar action. Useful for catching the very start of a program run."), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "F.START (CPU tab)"), " \u2014 arms the debugger so it freezes the moment the calculator leaves the keyboard scan loop. This happens when you press any key (which causes the ROM to exit the idle loop and start processing the keystroke) or when the calculator is reset. Useful for catching the very first ROM instruction of a key-press handler."), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "ARMED"), " \u2014 shown in yellow when F.START is active; click it to cancel."), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "RESUME"), " \u2014 resumes execution from the frozen state."), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "STEP"), " \u2014 advances one step (semantics differ per tab, see above).")), /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 8,
      marginBottom: 0,
      color: "var(--fg-2)"
    }
  }, "Only one F.START arm can be active at a time. Pressing F.START in one tab while the other is already ARMED silently transfers the arm. Once frozen, RESUME and STEP are only available in the tab that caused the freeze \u2014 the other tab's buttons are disabled to prevent accidental cross-tab interactions.")), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 20,
      lineHeight: 1.7,
      marginTop: 12
    }
  }, /*#__PURE__*/React.createElement("h3", {
    className: "sub",
    style: {
      marginTop: 0,
      marginBottom: 12
    }
  }, "iPhone behaviour"), /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 0
    }
  }, "On iPhone, the debugger panel is full-screen and covers the calculator. This is different from iPad and Mac, where both views are visible at the same time."), /*#__PURE__*/React.createElement("ul", {
    style: {
      margin: "8px 0 0",
      paddingLeft: 20
    }
  }, /*#__PURE__*/React.createElement("li", null, "Switching to the ", /*#__PURE__*/React.createElement("strong", null, "CPU"), " tab resets the heat map, because the CPU trace was not running while CALCULATOR was visible. Exception: if the CPU is already frozen when you switch, the heat map is preserved."), /*#__PURE__*/React.createElement("li", null, "The selected tab (CALCULATOR, CPU, LOG) is remembered when you navigate away from the debugger and return."), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "F.START in CALCULATOR"), " works best in landscape or on iPad/Mac, where you can press a key on the calculator while the tab is watching. On iPhone you would need to go back to the calculator, press the key, then return to the debugger."), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "F.START in CPU"), " arms in the background and fires as soon as you press any key (or reset the calculator), regardless of which tab or screen is visible \u2014 the freeze is waiting for a ROM-level scan-loop exit, not a screen interaction."))), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 20,
      lineHeight: 1.7,
      marginTop: 12
    }
  }, /*#__PURE__*/React.createElement("h3", {
    className: "sub",
    style: {
      marginTop: 0,
      marginBottom: 12
    }
  }, "TRACE and LOG: for session capture and analysis"), /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 0
    }
  }, "The ", /*#__PURE__*/React.createElement("strong", null, "LOG"), " panel serves two main purposes:"), /*#__PURE__*/React.createElement("ul", {
    style: {
      margin: "8px 0",
      paddingLeft: 20
    }
  }, /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "Raw SCOM inspection"), " \u2014 Shows the low-level scratch memory that the ROM uses. The CALCULATOR view displays decoded SCOM values (like HIR section), but LOG shows the raw hex."), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "TRACE toggle"), " \u2014 Records a binary session file while the calculator is running. This is the most thorough way to understand sequences like the reset routine or key-processing flow.")), /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 12,
      marginBottom: 12
    }
  }, /*#__PURE__*/React.createElement("strong", null, "To capture and analyze a sequence:")), /*#__PURE__*/React.createElement("ol", {
    style: {
      margin: 0,
      paddingLeft: 20
    }
  }, /*#__PURE__*/React.createElement("li", null, "Switch to the LOG tab and toggle TRACE on."), /*#__PURE__*/React.createElement("li", null, "Perform the action you want to analyze (e.g., press ", /*#__PURE__*/React.createElement("strong", null, "Reset"), ", or execute a ROM subroutine)."), /*#__PURE__*/React.createElement("li", null, "Toggle TRACE off to stop recording."), /*#__PURE__*/React.createElement("li", null, "Export the trace file (use the Files app on iOS to email it, or find it on Mac)."), /*#__PURE__*/React.createElement("li", null, "On a computer with Python, download the ", /*#__PURE__*/React.createElement("code", null, "read_trace.py"), " tool from the ", /*#__PURE__*/React.createElement("a", {
    href: "https://github.com/tinue/Calc-U-59/tree/main/tools",
    style: {
      color: "var(--accent)",
      textDecoration: "none",
      borderBottom: "1px solid var(--accent)"
    }
  }, "Calc-U-59 tools folder"), "."), /*#__PURE__*/React.createElement("li", null, "Run: ", /*#__PURE__*/React.createElement("code", {
    style: {
      background: "var(--bg-inset)",
      padding: "2px 6px",
      borderRadius: 4
    }
  }, "python3 ./read_trace.py --clean --skip-repeating CALCU59_TRACE.bin > CALCU59_TRACE.txt")), /*#__PURE__*/React.createElement("li", null, "Open the resulting text file to see the full execution trace as human-readable disassembly.")), /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 12,
      marginBottom: 0
    }
  }, "The binary trace file can be large (190 MB for a long session), but the text output is much smaller (57 kB) because the tool deduplicates repetitive loops \u2014 especially the keyboard scan loop that runs continuously. This makes it practical to analyze even long traces.")), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 20,
      lineHeight: 1.7,
      marginTop: 12
    }
  }, /*#__PURE__*/React.createElement("h3", {
    className: "sub",
    style: {
      marginTop: 0,
      marginBottom: 12
    }
  }, "When to use each tool"), /*#__PURE__*/React.createElement("ul", {
    style: {
      margin: 0,
      paddingLeft: 20
    }
  }, /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "CALCULATOR tab"), " \u2014 Stepping through your own program one step at a time, checking registers and flags at each step."), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "CPU tab"), " \u2014 Tracing the ROM's internal instruction flow, reviewing jumps and subroutine calls, scrolling back through execution history."), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "TRACE (in LOG)"), " \u2014 Capturing a complete ROM sequence for offline analysis (reset routine, memory writes, keyboard processing, etc.)."), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "Debug logging (in LOG)"), " \u2014 Low or High level logging is mainly used by the developer for debugging specific issues. When enabled, you will see all memory writes and other hardware events. This has limited utility for regular app users."))), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 16,
      display: "grid",
      gap: 12
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 16
    }
  }, /*#__PURE__*/React.createElement("h3", {
    className: "sub",
    style: {
      margin: "0 0 10px"
    }
  }, "CALCULATOR tab \u2014 iPhone"), /*#__PURE__*/React.createElement("img", {
    src: "assets/iphone-debug.png",
    alt: "iPhone screenshot showing the CALCULATOR debug tab with program listing and registers",
    style: {
      width: "auto",
      maxWidth: "60%",
      height: "auto",
      display: "block",
      borderRadius: 8,
      margin: "0 auto"
    }
  })), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 16
    }
  }, /*#__PURE__*/React.createElement("h3", {
    className: "sub",
    style: {
      margin: "0 0 10px"
    }
  }, "CALCULATOR tab \u2014 iPad"), /*#__PURE__*/React.createElement("img", {
    src: "assets/ipad-13-2752x2064.png",
    alt: "iPad screenshot showing the CALCULATOR debug tab",
    style: {
      width: "100%",
      height: "auto",
      display: "block",
      borderRadius: 8
    }
  })), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 16
    }
  }, /*#__PURE__*/React.createElement("h3", {
    className: "sub",
    style: {
      margin: "0 0 10px"
    }
  }, "CPU tab \u2014 iPad"), /*#__PURE__*/React.createElement("img", {
    src: "assets/ipad-2752x2064-asm.png",
    alt: "iPad screenshot showing the CPU debug tab with execution trace",
    style: {
      width: "100%",
      height: "auto",
      display: "block",
      borderRadius: 8
    }
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 24
    }
  }, /*#__PURE__*/React.createElement(BackButton, {
    onNav: onNav
  })));
}

/* =============================================================
   APP REFERENCE — emulator controls and screen regions.
   ============================================================= */
function ReferencePage({
  onNav
}) {
  return /*#__PURE__*/React.createElement("main", {
    className: "wrap docs-split"
  }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("p", {
    className: "eyebrow"
  }, "App Reference"), /*#__PURE__*/React.createElement("h1", {
    className: "page-title"
  }, "Every control,", /*#__PURE__*/React.createElement("br", null), "annotated."), /*#__PURE__*/React.createElement("p", {
    className: "lede"
  }, "This page explains the emulator controls as they behave in the app: the calculator, the printer, the debug pane, and the settings that affect a session."), /*#__PURE__*/React.createElement("h2", {
    className: "section"
  }, "The calculator"), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 20,
      lineHeight: 1.7
    }
  }, /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 0
    }
  }, "The calculator view is the main working surface. On iPhone and on iPad in portrait, it uses the same key layout as the app screenshot; on iPad in landscape, the layout mirrors the Mac view."), /*#__PURE__*/React.createElement("p", null, "The top display area shows the current number and status indicators, the cue card area directly beneath it shows module/context notes, and the keyboard area contains the full key matrix for normal operation."), /*#__PURE__*/React.createElement("p", {
    style: {
      marginBottom: 0
    }
  }, "Bottom toolbar (left to right): ", /*#__PURE__*/React.createElement("strong", null, "Reset"), " (long press: ", /*#__PURE__*/React.createElement("strong", null, "Reset + Memory wipe"), "), ", /*#__PURE__*/React.createElement("strong", null, "Model selector"), " (TI-59/TI-58/TI-58C), ", /*#__PURE__*/React.createElement("strong", null, "Read Magnetic Card"), ", ", /*#__PURE__*/React.createElement("strong", null, "Write Magnetic Card"), ", ", /*#__PURE__*/React.createElement("strong", null, "Load State File"), ", ", /*#__PURE__*/React.createElement("strong", null, "Settings"), ".")), /*#__PURE__*/React.createElement("h2", {
    className: "section"
  }, "The printer"), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 20,
      lineHeight: 1.7
    }
  }, /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 0
    }
  }, "The printer view has a PC-100C badge at the top, a dot/text toggle, and hardware-style buttons for print and advance. On all builds (including iOS and iPadOS), you can also copy the paper strip to the clipboard or cut it away when it gets too long."), /*#__PURE__*/React.createElement("p", {
    style: {
      marginBottom: 0
    }
  }, "The text view is useful when you want to read or copy output quickly. The dot view is the closer match to the physical printer.")), /*#__PURE__*/React.createElement("h2", {
    className: "section"
  }, "The debug pane"), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 20,
      lineHeight: 1.7
    }
  }, /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 0
    }
  }, "The debug pane has three tabs: ", /*#__PURE__*/React.createElement("strong", null, "CALCULATOR"), ", ", /*#__PURE__*/React.createElement("strong", null, "CPU"), ", and ", /*#__PURE__*/React.createElement("strong", null, "LOG"), "."), /*#__PURE__*/React.createElement("ul", {
    style: {
      margin: "8px 0 0",
      paddingLeft: 20
    }
  }, /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "CALCULATOR"), " \u2014 Program listing (from RAM) centred on the next instruction to execute, with live registers and flags."), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "CPU"), " \u2014 Execution trace of ROM instructions that already ran. State shown is ", /*#__PURE__*/React.createElement("em", null, "after"), " each instruction. Scrollable history, one-opcode step."), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "LOG"), " \u2014 Text output, raw SCOM register dumps, and the TRACE toggle. Use TRACE to capture a binary session file for detailed analysis with read_trace.py.")), /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 8,
      marginBottom: 0
    }
  }, "The CALCULATOR and CPU tabs have different step semantics: CALCULATOR advances until the program counter changes; CPU advances exactly one ROM opcode.")), /*#__PURE__*/React.createElement("h2", {
    className: "section"
  }, "Settings"), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 20,
      lineHeight: 1.7
    }
  }, /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 0
    }
  }, "The settings sheet controls the startup model, the active Solid State module, keyboard feedback on iOS, the LED font style, and the trace-file location."), /*#__PURE__*/React.createElement("p", {
    style: {
      marginBottom: 0
    }
  }, "The trace-file size limit is also adjustable on macOS and on iPad in landscape so long debug sessions do not grow without bound. This mainly prevents iCloud storage overcommit when trace files are written to iCloud Drive.")), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 24
    }
  }, /*#__PURE__*/React.createElement(BackButton, {
    onNav: onNav
  }))), /*#__PURE__*/React.createElement("div", {
    className: "docs-aside"
  }, /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 14
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: "relative"
    }
  }, /*#__PURE__*/React.createElement("img", {
    src: "/assets/app-screenshot.png",
    alt: "Calc-U 59 main app screenshot with annotated interface regions and toolbar buttons",
    style: {
      width: "100%",
      height: "auto",
      display: "block",
      borderRadius: 10
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      top: "10%",
      left: "48%",
      transform: "translateX(-50%)",
      background: "rgba(0,0,0,.72)",
      color: "var(--accent)",
      border: "1px solid var(--accent)",
      borderRadius: 999,
      padding: "4px 8px",
      fontFamily: "var(--font-key)",
      fontSize: 11,
      letterSpacing: ".06em",
      textTransform: "uppercase"
    }
  }, "Display"), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      top: "21%",
      left: "50%",
      transform: "translateX(-50%)",
      background: "rgba(0,0,0,.72)",
      color: "var(--accent)",
      border: "1px solid var(--accent)",
      borderRadius: 999,
      padding: "4px 8px",
      fontFamily: "var(--font-key)",
      fontSize: 11,
      letterSpacing: ".06em",
      textTransform: "uppercase"
    }
  }, "Cue card"), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      top: "36%",
      left: "50%",
      transform: "translateX(-50%)",
      background: "rgba(0,0,0,.72)",
      color: "var(--accent)",
      border: "1px solid var(--accent)",
      borderRadius: 999,
      padding: "4px 8px",
      fontFamily: "var(--font-key)",
      fontSize: 11,
      letterSpacing: ".06em",
      textTransform: "uppercase"
    }
  }, "Keyboard"), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      bottom: "2.1%",
      left: "6%",
      width: 22,
      height: 22,
      borderRadius: 999,
      background: "var(--accent)",
      color: "#21170f",
      fontFamily: "var(--font-key)",
      fontWeight: 700,
      fontSize: 12,
      display: "grid",
      placeItems: "center"
    }
  }, "1"), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      bottom: "2.1%",
      left: "17%",
      width: 22,
      height: 22,
      borderRadius: 999,
      background: "var(--accent)",
      color: "#21170f",
      fontFamily: "var(--font-key)",
      fontWeight: 700,
      fontSize: 12,
      display: "grid",
      placeItems: "center"
    }
  }, "2"), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      bottom: "2.1%",
      left: "62%",
      width: 22,
      height: 22,
      borderRadius: 999,
      background: "var(--accent)",
      color: "#21170f",
      fontFamily: "var(--font-key)",
      fontWeight: 700,
      fontSize: 12,
      display: "grid",
      placeItems: "center"
    }
  }, "3"), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      bottom: "2.1%",
      left: "70%",
      width: 22,
      height: 22,
      borderRadius: 999,
      background: "var(--accent)",
      color: "#21170f",
      fontFamily: "var(--font-key)",
      fontWeight: 700,
      fontSize: 12,
      display: "grid",
      placeItems: "center"
    }
  }, "4"), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      bottom: "2.1%",
      left: "80%",
      width: 22,
      height: 22,
      borderRadius: 999,
      background: "var(--accent)",
      color: "#21170f",
      fontFamily: "var(--font-key)",
      fontWeight: 700,
      fontSize: 12,
      display: "grid",
      placeItems: "center"
    }
  }, "5"), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      bottom: "2.1%",
      left: "89%",
      width: 22,
      height: 22,
      borderRadius: 999,
      background: "var(--accent)",
      color: "#21170f",
      fontFamily: "var(--font-key)",
      fontWeight: 700,
      fontSize: 12,
      display: "grid",
      placeItems: "center"
    }
  }, "6"), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      top: "6%",
      right: "8%",
      width: 22,
      height: 22,
      borderRadius: 999,
      background: "var(--accent)",
      color: "#21170f",
      fontFamily: "var(--font-key)",
      fontWeight: 700,
      fontSize: 12,
      display: "grid",
      placeItems: "center"
    }
  }, "7")), /*#__PURE__*/React.createElement("ol", {
    style: {
      margin: "12px 0 0",
      paddingLeft: 20,
      lineHeight: 1.65,
      color: "var(--fg-2)",
      fontSize: 14
    }
  }, /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "Reset"), " (long press: Reset + Memory wipe)"), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "Model selector"), " (TI-59 / TI-58 / TI-58C)"), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "Read Magnetic Card")), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "Write Magnetic Card")), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "Load State File")), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "Settings")), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("strong", null, "Swipe to printer"))))));
}

/* =============================================================
   FAQ — direct answers.
   ============================================================= */
function FaqPage({
  onNav
}) {
  const faqs = [{
    question: "Where do state files live?",
    answer: "They are regular .ti59, .ti58, or .ti58c text files that can be anywhere on the file system. On Mac, the preset picker opens them from disk; on iPhone and iPad, use the built-in file picker."
  }, {
    question: "Are there examples of state files?",
    answer: "Yes. The GitHub repository includes an 'examples' folder with a selection of .ti59, .ti58, and .ti58c files."
  }, {
    question: "What are the 'assembly' examples here for?",
    answer: "This feature is still a bit experimental. You can load these examples on the 'CPU' tab of the debugger. Use the buttons at the bottom to select a file, and run it."
  }, {
    question: "The emulator always complains about 'ASM run timed out before HOLD (8192 step(s))' when I try to start an assembly program. What can I do?",
    answer: "Click away the error, click 'Freeze', then click 'Resume', and you should be on your way."
  }, {
    question: "Where do virtual magnetic cards live?",
    answer: "The virtual cards are stored in the app's iCloud storage. On iOS and iPadOS, use the card picker to load or save them. On Mac, they are also available in the file picker under the 'iCloud Drive/Calc-U-59' folder."
  }, {
    question: "Where is the TI-58C state file?",
    answer: "The TI-58C state file is stored in the app's iCloud storage (ti58c.mem). The file is written and loaded automatically when you switch to the TI-58C model."
  }, {
    question: "Can I see what the emulator is doing internally?",
    answer: "Yes. Use the debug pane: CALCULATOR for program state and registers, CPU for the ROM instruction trace, and LOG for text output plus trace controls."
  }, {
    question: "How do I get a trace file?",
    answer: "Open the debug pane, switch to LOG, and turn TRACE on. The app writes a binary session file to the configured trace location."
  }, {
    question: "What can I do with a trace file?",
    answer: "You first need to download the trace file to your computer. If you use the Mac emulator, this is already a given. When you generate the trace file with an iPad, then use 'Settings' to choose a good location. One option is to save the file directly to iCloud, and let the iPad sync it for you. Retrieve the file from iCloud on your PC. Download the 'read_trace.py' script from GitHub to convert the binary file to a readable format. The script is available in the 'tools' directory of the GitHub repository."
  }, {
    question: "Why does switching to the CPU tab reset the heat map?",
    answer: "The CPU tab only traces while it is visible. When you switch to it, the heat map resets because any activity since you last left would be missing anyway. Exception: if the CPU is already frozen when you switch, the heat map is left intact — there is nothing new to miss."
  }, {
    question: "What does F.START do in the CPU tab?",
    answer: "In the CPU tab, F.START arms a scan-loop exit trigger: it freezes the moment the calculator leaves the keyboard idle loop — either because you pressed a key (the ROM exits the loop to handle the keystroke) or because the calculator was reset. This lets you catch the very first ROM opcode of a key-press handler without having to time a manual FREEZE. Only one F.START can be armed at a time; arming one tab silently disarms the other."
  }, {
    question: "How can I step through the reset routine?",
    answer: "Switch to the CPU tab and press F.START (Freeze on Start). Then go to the calculator and press Reset — the CPU will freeze at the first ROM instruction of the reset routine. Use STEP to walk through it one opcode at a time."
  }, {
    question: "I used F.START in the CPU tab, the freeze triggered on a keypress — but after RESUME the key seems lost. Why?",
    answer: "This is expected. The ROM's key-debouncing logic registers a keypress only for a very short window. When F.START fires, the CPU freezes at the first instruction after the scan loop exits — but that window has already passed by the time you press RESUME or STEP. The key handler never sees the keypress and the calculator returns to idle. Use a TRACE capture instead: it records the full keystroke sequence without stopping the emulator, so the debounce window is never interrupted."
  }, {
    question: "Is there a faster way to read long printer output?",
    answer: "Yes. Copy or cut the output, and paste it into a text editor."
  }];
  return /*#__PURE__*/React.createElement("main", {
    className: "wrap-narrow"
  }, /*#__PURE__*/React.createElement("p", {
    className: "eyebrow"
  }, "Help"), /*#__PURE__*/React.createElement("h1", {
    className: "page-title"
  }, "FAQ"), /*#__PURE__*/React.createElement("p", {
    className: "lede"
  }, "Concise answers to the questions that usually come up first."), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      gap: 8,
      marginTop: 24
    }
  }, faqs.map((item, i) => /*#__PURE__*/React.createElement("div", {
    key: i,
    className: "panel",
    style: {
      padding: "16px 20px",
      display: "grid",
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: "var(--font-key)",
      fontWeight: 700,
      fontSize: 16,
      textTransform: "uppercase",
      letterSpacing: ".05em",
      color: "var(--fg)"
    }
  }, item.question), /*#__PURE__*/React.createElement("p", {
    style: {
      margin: 0,
      lineHeight: 1.7,
      color: "var(--fg-2)"
    }
  }, item.answer)))), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 24
    }
  }, /*#__PURE__*/React.createElement(BackButton, {
    onNav: onNav
  })));
}
function ModulesPage({
  onNav
}) {
  const modules = [{
    code: "ML",
    name: "Master Library"
  }, {
    code: "ST",
    name: "Applied Statistics"
  }, {
    code: "RE",
    name: "Investment"
  }, {
    code: "SY",
    name: "Surveying"
  }, {
    code: "NG",
    name: "Marine Navigation"
  }, {
    code: "AV",
    name: "Aviation"
  }, {
    code: "LE",
    name: "Leisure Library"
  }, {
    code: "SA",
    name: "Securities Analysis"
  }, {
    code: "BD",
    name: "Business Decisions"
  }, {
    code: "MU",
    name: "Math/Utilities"
  }, {
    code: "EE",
    name: "EE Library"
  }, {
    code: "SE",
    name: "Structural Engineering"
  }, {
    code: "AG",
    name: "Agriculture"
  }, {
    code: "RP",
    name: "RPN Simulator"
  }];
  return /*#__PURE__*/React.createElement("main", {
    className: "wrap"
  }, /*#__PURE__*/React.createElement("p", {
    className: "eyebrow"
  }, "Modules"), /*#__PURE__*/React.createElement("h1", {
    className: "page-title"
  }, "Library modules"), /*#__PURE__*/React.createElement("p", {
    className: "lede"
  }, "The module picker changes the Solid State Software library loaded into the emulator. That affects the cue card, the available programs, and the labels shown on screen."), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 20,
      marginTop: 24,
      lineHeight: 1.7
    }
  }, /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 0
    }
  }, "Keep the selected module aligned with the file you are loading. If a state file includes a ", /*#__PURE__*/React.createElement("strong", null, "SOLID-STATE-MODULE:"), " line, the emulator can switch to that module automatically."), /*#__PURE__*/React.createElement("p", {
    style: {
      marginBottom: 0
    }
  }, "If the cue card or program list looks unexpected, the module selection is the first thing to check.")), /*#__PURE__*/React.createElement("div", {
    className: "grid-2",
    style: {
      marginTop: 24
    }
  }, modules.map(m => /*#__PURE__*/React.createElement("div", {
    key: m.code,
    className: "panel",
    style: {
      display: "grid",
      gridTemplateColumns: "auto 1fr",
      gap: 16,
      alignItems: "center"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      background: "linear-gradient(180deg,#1a0c08,#2c1812)",
      color: "var(--accent)",
      fontFamily: "var(--font-key)",
      fontWeight: 700,
      padding: "8px 12px",
      borderRadius: 4,
      letterSpacing: ".05em",
      fontSize: 13,
      minWidth: 70,
      textAlign: "center",
      border: "1px solid var(--stroke-warm)"
    }
  }, m.code), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("h3", {
    className: "sub",
    style: {
      margin: 0
    }
  }, m.name))))), /*#__PURE__*/React.createElement("h2", {
    className: "section"
  }, "Per-module details"), /*#__PURE__*/React.createElement("div", {
    className: "panel",
    style: {
      padding: 20,
      lineHeight: 1.7
    }
  }, /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 0
    }
  }, "Each module has its own cue card content and program selection. The app loads the matching ROM/library data together with the module metadata so the on-screen card stays in sync with the selected library."), /*#__PURE__*/React.createElement("p", {
    style: {
      marginBottom: 0
    }
  }, "This is an emulator feature, not a historical TI-59 walkthrough: the purpose is to make the active module understandable while you use the app.")), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 24
    }
  }, /*#__PURE__*/React.createElement(BackButton, {
    onNav: onNav
  })));
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
function PlayPage({
  onNav
}) {
  const [holderRef, scale] = useFittedScale(1.4, 0.7);
  return /*#__PURE__*/React.createElement("main", {
    className: "wrap-narrow"
  }, /*#__PURE__*/React.createElement("div", {
    ref: holderRef,
    style: {
      display: "flex",
      justifyContent: "center"
    }
  }, /*#__PURE__*/React.createElement(PlayCalculator, {
    scale: scale,
    keyboard: true
  })), /*#__PURE__*/React.createElement("h1", {
    className: "page-title",
    style: {
      marginTop: 32
    }
  }, "TI-59 emulator, online"), /*#__PURE__*/React.createElement("div", {
    className: "prose"
  }, /*#__PURE__*/React.createElement("p", null, "The calculator above is a working ", /*#__PURE__*/React.createElement("strong", null, "Texas Instruments TI-59 emulator running in your browser"), " \u2014 no install, no account, nothing to download. It is the real emulation core from the Calc-U 59 app, compiled to WebAssembly, executing the original TI-59 ROM. Debugger, printer, and card reader are not part of this build; everything else works."), /*#__PURE__*/React.createElement("p", null, "Module 01 (Master Library) is loaded by default. Switch modules, load one of the curated presets, or upload your own ", /*#__PURE__*/React.createElement("strong", null, ".ti59"), " file below the keyboard \u2014 uploads are read entirely in your browser and never leave your machine."), /*#__PURE__*/React.createElement("p", null, "Press ", /*#__PURE__*/React.createElement("strong", null, "2nd"), " then ", /*#__PURE__*/React.createElement("strong", null, "Pgm"), " then a two-digit program number to bring up that program's cue card, the same way it works on the module itself."), /*#__PURE__*/React.createElement("p", null, "For the TI-58 and TI-58C models, the PC-100C printer, magnetic cards and the CPU debugger, use the full app: ", /*#__PURE__*/React.createElement("a", {
    href: "/install/mac/"
  }, "free on the Mac"), ", or", " ", /*#__PURE__*/React.createElement("a", {
    href: "/install/iphone-ipad/"
  }, "on the App Store"), " for iPhone and iPad. If you are not sure what any of this is, ", /*#__PURE__*/React.createElement("a", {
    href: "/what-is-a-ti-59/"
  }, "start here"), ".")), /*#__PURE__*/React.createElement("h2", {
    className: "section",
    style: {
      marginTop: 32
    }
  }, "Use your keyboard"), /*#__PURE__*/React.createElement("div", {
    className: "prose"
  }, /*#__PURE__*/React.createElement("p", null, "Click the calculator once and it takes your keystrokes \u2014 a golden outline shows when it has them. Click anywhere else, or press ", /*#__PURE__*/React.createElement(K, null, "Tab"), ", and the page gets the keyboard back."), /*#__PURE__*/React.createElement("p", null, "The number keys, the yellow operation keys, ", /*#__PURE__*/React.createElement("strong", null, "A"), "\u2013", /*#__PURE__*/React.createElement("strong", null, "E"), ", and", /*#__PURE__*/React.createElement("strong", null, " EE"), " ", /*#__PURE__*/React.createElement("strong", null, "("), " ", /*#__PURE__*/React.createElement("strong", null, ")"), " are typeable. Everything else \u2014 2nd, STO, RCL, LRN and the rest \u2014 is click-only, so the keyboard stays out of the way of the page. Holding ", /*#__PURE__*/React.createElement(K, null, "Shift"), " while you press a letter gives you that key's second function: ", /*#__PURE__*/React.createElement(K, null, "Shift"), " + ", /*#__PURE__*/React.createElement(K, null, "A"), " is ", /*#__PURE__*/React.createElement("strong", null, "A'"), ".")), /*#__PURE__*/React.createElement(KeyboardLegend, null), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 24
    }
  }, /*#__PURE__*/React.createElement(BackButton, {
    onNav: onNav
  })));
}

// Rendered straight from keyboard-map.js's own table, so the published legend
// can't drift away from the bindings that actually run.
function KeyboardLegend() {
  if (typeof TI59_KEYBOARD_LEGEND === "undefined") return null;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 16,
      display: "grid",
      gridTemplateColumns: "repeat(auto-fill, minmax(190px, 1fr))",
      gap: "10px 20px"
    }
  }, TI59_KEYBOARD_LEGEND.map((entry, i) => /*#__PURE__*/React.createElement("div", {
    key: i,
    style: {
      display: "flex",
      alignItems: "baseline",
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: "0 0 auto"
    }
  }, /*#__PURE__*/React.createElement(KSeq, {
    steps: entry.keys.map(k => k === "…" ? "…" : {
      label: k
    })
  })), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: "var(--font-keycap)",
      color: "var(--accent)",
      fontSize: 14
    }
  }, entry.label), entry.note ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: "var(--font-body)",
      fontSize: 12,
      color: "var(--fg-3)"
    }
  }, entry.note) : null)));
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
  PlayPage
});