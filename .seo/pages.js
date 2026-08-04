// Per-page <head> content for the static build, keyed by the route path
// in ../routes.js. Build-time only — never shipped to the browser.
//
// Rules of thumb used here:
//   title       ≤ 60 chars where possible, most distinctive words first,
//               brand last. Every title carries a model name, because
//               "TI-59" / "TI-58C" is what people actually type.
//   description 140–160 chars, written as a sentence a human would read
//               in a result list, not a keyword list.

const PAGES = {
  "/": {
    title: "Calc-U 59 — TI-59, TI-58 and TI-58C Emulator for Mac, iPhone and iPad",
    description:
      "A TI-59, TI-58 and TI-58C emulator that runs the original Texas Instruments ROM: all 14 library modules, magnetic cards, PC-100C printer and a CPU debugger.",
    heading: "Calc-U 59 — TI-59 emulator",
  },

  "/what-is-a-ti-59/": {
    title: "What is a TI-59? The TI-58, TI-58C and TI-59 explained",
    description:
      "The Texas Instruments TI-59, TI-58 and TI-58C programmable calculators of 1977: memory, AOS, magnetic cards, Solid State Software modules and the PC-100C printer.",
    heading: "What is a TI-59?",
  },

  "/play/": {
    title: "Online TI-59 Emulator — run a TI-59 in your browser",
    description:
      "Use a working Texas Instruments TI-59 in your browser. The real emulation core compiled to WebAssembly, with the Master Library module loaded. No install, no account.",
    heading: "TI-59 emulator, online",
  },

  "/getting-started/": {
    title: "Getting Started with the Calc-U 59 TI-59 Emulator",
    description:
      "Install Calc-U 59 on iPhone, iPad or Mac, load a .ti59 state file, use the PC-100C printer and card reader, and find your way around the debugger.",
    heading: "Getting started",
  },
  "/getting-started/printer/": {
    title: "PC-100C Printer and Magnetic Card Reader — Calc-U 59",
    description:
      "How the emulated TI-59 PC-100C thermal printer works in Calc-U 59: dot and text views, print and advance, copying the paper strip, and where card files live.",
    heading: "Printer and card reader",
  },

  "/install/iphone-ipad/": {
    title: "Install the TI-59 Emulator on iPhone and iPad",
    description:
      "Install Calc-U 59, the TI-59 emulator, from the App Store on iPhone and iPad, choose the calculator model, and open .ti59, .ti58 and .ti58c files.",
    heading: "Installing on iPhone and iPad",
  },
  "/install/mac/": {
    title: "Install the TI-59 Emulator on Mac (free download)",
    description:
      "Download the free Calc-U 59 TI-59 emulator for macOS from GitHub Releases, drag it to Applications, and get past the first-launch Gatekeeper prompt.",
    heading: "Installing on Mac",
  },

  "/state-files/": {
    title: ".ti59 State Files — format and how to load one",
    description:
      "The plain-text .ti59, .ti58 and .ti58c state file format: PARTITION, PROGRAM, REGISTERS, KEYSTROKES, CUECARD, SOLID-STATE-MODULE and PRINTER sections explained.",
    heading: "Loading a state file",
  },
  "/debugger/": {
    title: "TI-59 CPU Debugger — program listing, ROM trace, TRACE capture",
    description:
      "Step through TI-59 programs and the original ROM opcodes: the CALCULATOR, CPU and LOG tabs, freeze and step, F.START, and binary trace files for offline analysis.",
    heading: "Using the debugger",
  },
  "/reference/": {
    title: "App Reference — every Calc-U 59 control, annotated",
    description:
      "A guided tour of the Calc-U 59 TI-59 emulator: the calculator view, the bottom toolbar, the PC-100C printer, the three debug tabs, and every setting.",
    heading: "App reference",
  },
  "/modules/": {
    title: "TI-59 Solid State Software Modules — all 14 libraries",
    description:
      "Every Solid State Software library module included in Calc-U 59, from the Master Library and Applied Statistics to Aviation, Surveying and the RPN Simulator.",
    heading: "Library modules",
  },
  "/examples/": {
    title: "TI-59 Example Programs — Calendar Printer, RAM Test, Fast Mode",
    description:
      "Downloadable TI-59 and TI-58 programs: the 1978 calendar printer competition, PC-100 printer graphics tricks, RAM and diagnostic self-tests, and Fast Mode demos.",
    heading: "Example programs",
  },

  "/faq/": {
    title: "Calc-U 59 FAQ — TI-59 emulator questions answered",
    description:
      "Where state files and virtual magnetic cards live, how to capture and read a trace file, what F.START does, and the other questions that come up first.",
    heading: "FAQ",
  },
};

// Routes that exist but should consolidate onto another page carry a
// canonical in routes.js; they inherit their <title> from the target and
// get a short, distinct description so they are never the better match.
const FALLBACK = {
  title: "Calc-U 59 — TI-59, TI-58 and TI-58C Emulator",
  description:
    "Calc-U 59 is a TI-59, TI-58 and TI-58C emulator for Mac, iPhone and iPad that runs the original Texas Instruments ROM.",
  heading: "Calc-U 59",
};

module.exports = { PAGES, FALLBACK };
