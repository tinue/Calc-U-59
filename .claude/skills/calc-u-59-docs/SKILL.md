---
name: calc-u-59-docs
description: Use this skill when working on the Calc-U-59 developer documentation (reference/, root markdown files) or deciding where documentation belongs. Covers the developer-vs-end-user split (the user guide lives at calc-u.org/59/ in the separate calc-u-site repository) and the reference architecture docs. Trigger on any task that touches reference/*.md, README.md, CHANGELOG.md, TODO.md, or PRIVACY.md. Also trigger when the user says "update documentation" (or similar) after finishing Core/, Shared/, App/, Qt6/ or Web/ work on a release branch — see the Release Documentation Update Workflow section, which updates the user guide in ../calc-u-site as well.
user-invocable: true
---

# Calc-U-59 Documentation

This skill covers the reference architecture docs (`reference/`) and root markdown files, and where the user guide lives.

---

## Documentation Policy: two audiences, two locations

- **The user guide (https://calc-u.org/59/, repository `calc-u-site`) is
  the *only* place for end-user documentation** — installing, operating,
  syncing, modules, settings, and the debug panel from a user's point of
  view. If you're about to write something an app user (not a contributor)
  would want to read, it goes there, not in `reference/` or a root markdown
  file.
- **Everything in the main repository (`reference/`, root markdown files,
  `.claude/skills/`) is developer documentation** — for contributors, the
  project owner, and AI agents working on the code. It assumes the reader
  can read Swift/C++/Qt and doesn't need app-usage instructions.
- **`README.md` links to the website exactly once, prominently** (the "User
  Guide" section) rather than re-explaining or indexing end-user content.
  Technical facts that a developer needs but an end user doesn't — the
  `.ti59` file format, the CUECARD grammar, the debug API — live in
  `reference/` even though the website mentions that such things exist and
  links back here for anyone who wants them.
- **Skill files (`.claude/skills/*/SKILL.md`) must not duplicate content
  that already has a home in a developer-accessible markdown file.** A human
  developer reads `reference/*.md`; only the agent reads skill files. If a
  skill and a reference doc say the same thing, delete it from the skill and
  link to the doc instead — see `calc-u-59-statefiles/SKILL.md` for the
  pattern (a few navigation aids, everything else is one link to
  `reference/StateFileFormat.md`).

---

## The user guide (`calc-u.org/59/`)

The end-user website is https://calc-u.org/59/, the `59/` folder of the
separate repository `calc-u-site` (checked out beside this one as
`../calc-u-site`, GitHub `tinue/calc-u-site`). It has its own `CLAUDE.md`
and skills (`site-59` for content and build, `site-59-design` for the
design system); work on the site from there, under those rules, and commit
there. Nothing about the site's build, design or URL map belongs in this
repository.

The playable calculator on the site (`/59/play/`, the installable app at
`/59/calc/app/`) is this repository's web client, imported from a release's
`Calc-U-59-web.zip` — calc-u-59-web skill and `reference/WebClient.md`.

The `docs/` folder some clones still have (a worktree of the old `gh-pages`
branch that served `www.calcu59.ch`) is retired: don't edit it.

---

## Reference Architecture Docs (`reference/`)

These are AI-generated documents produced by reading the source code alongside hardware documentation. They describe the emulator's internals, not the user-facing app.

The list of documents with a line on each is `README.md` § "Appendix:
Documentation Index" (`reference/` and `rom/`); keep it current when adding
or removing a document.

The Qt6 app has no reference doc of its own: its class map and build live in
the `calc-u-59-qt` skill, its feature placement in `FrontendParity.md`.
ROM-level documentation (`rom/*-ROM-Guide.md`, `rom/fastmode.md`,
`rom/printerinterrupt.md`) sits beside the annotated listings in `rom/`.

There is no end-user guide in `reference/` — that content lives on the
website (`calc-u-site`'s `59/Pages.jsx`, e.g. `DebuggerPage`) and is out of
scope here.

When updating these files, keep the provenance notice at the top intact — it signals that the content is best-effort reverse-engineering, not authoritative hardware documentation.

---

## Root Markdown Files

| File | Purpose |
|------|---------|
| `README.md` | Project overview for GitHub, how to build the apps and the web client, and the index of every developer document — keep the index current when adding or removing a document |
| `CHANGELOG.md` | Version history (keep entries under the correct version heading) |
| `TODO.md` | Development task list |
| `PRIVACY.md` | App Store privacy policy |
| `THIRD-PARTY-NOTICES.md` | Qt6 (LGPLv3), web-client (React, Archivo) and ROM-image notices; shipped with the Windows and Linux packages |
| `ideas/*.md` | Unimplemented design proposals and feasibility analyses (e.g. `KeypressLatch.md`, `Pico.md`, `CardRecovery.md`) — not current behavior, don't treat as authoritative |

---

## Release Documentation Update Workflow

Triggered by the user saying **"update documentation"** (or similar) after finishing work on `Core/`, `Shared/`, `App/`, `Qt6/` or `Web/` for a release. The current dev branch (`dev-X.Y.Z`) always starts at the HEAD of the previous release tag — that tag, not `main` and not an arbitrary commit count, is the diff base.

1. **Find the base commit — verify, don't trust a single command blindly.**
   `git describe --tags --abbrev=0` alone can mislead (a mistagged or extra tag), so cross-check two ways:
   ```bash
   git branch --show-current                        # e.g. dev-1.6.0 → target release 1.6.0
   git tag --list --sort=-v:refname                  # find the entry just below the target version
   git merge-base HEAD v<previous-version>            # should equal...
   git rev-parse v<previous-version>                  # ...this, exactly
   ```
   If `merge-base` and `rev-parse` don't match, the dev branch has extra commits beyond a clean fork point (rebasing, cherry-picks, etc.) — stop and ask the user which commit is the real base rather than guessing.

2. **Review what actually changed.**
   ```bash
   git log <base-commit>..HEAD --oneline
   git diff <base-commit>..HEAD --stat
   ```
   Read the full diff for `Core/`, `Shared/`, `App/`, `Bridge/`, `Qt6/`, `Web/` and `roms/` — that's where documented facts live. Skip doc-only or test-only commits already made earlier in the same session.

3. **Update `CHANGELOG.md`.** Confirm every user-facing change from step 2 has an entry under the current `[X.Y.Z] - work in progress` heading, in the existing style (bold **Area** prefix, `### Fixes` subsection for bug fixes). Don't add a release date — that happens at release time.

4. **Update reference docs** (`reference/CoreArchitecture.md`, `reference/SharedArchitecture.md`, `reference/AppArchitecture.md`, `reference/DebugAPI.md`, `reference/StateFileFormat.md`, `reference/FrontendParity.md`, `reference/WebClient.md`) for anything the diff invalidated: register model, SCOM layout, PC encoding, machine variants, bridge/debug API surface, settings, file formats. Keep each file's provenance notice intact.

5. **Update the user guide in `../calc-u-site` too.** Every documentation update covers both repositories. Invoke the site's `site-59` skill and follow that repository's `CLAUDE.md`. Update its pages for anything user-facing in any GUI: new settings, module behavior, install steps (Mac, iOS, Windows, Linux), state-file directives, speed or accuracy. Also update the site's copies of files that came from here: articles derived from `rom/*.md` and the example files under `59/software-files/` (its software sync check finds the drift). Build, check and test the site as its skill says, and commit there. Leave the web client alone: the site fetches `59/calc/` from a release by its own rules (`site-59`, § "After a Calc-U-59 release", step 1), so pinning a build is not part of this step. A change that only needs a website update, with nothing in `Core/`/`Shared/`/`App/`/`Qt6/`/`Web/`/`roms/`, needs no `CHANGELOG.md` entry.

6. **The web client** (`Web/`): if the diff touched `Core/`, `Shared/`, `roms/` or `Web/`, build and test it as the calc-u-59-web skill says. The site picks up a new build by pinning the release's `Calc-U-59-web.zip`.

7. **Commit, never push, in both repositories.** Main-repo changes (`CHANGELOG.md`, `reference/`, `README.md`, `TODO.md`, `tools/`) commit from this repo's root; site changes commit in `../calc-u-site`, where a push publishes the site, so push there only when the user asks.

---

## Global Rules

1. **Compile, don't run.** Do not launch the Xcode iOS Simulator or run the built Mac app — that is the user's job. When runtime verification is needed, ask the user to launch the app and explain precisely what behaviour or output to look for.

2. **Commit often, never push.** Commit after each logical unit of work. Never run `git push`.

3. **Build on macOS.** Verify Swift-facing changes with a macOS build; build for iOS only when explicitly required (commands: `calc-u-59-swift` skill, § "Build Verification"). Doc-only changes need no build.

4. **Cite your sources.** When referencing a hardware spec, standard, or external document, include the https URL (or a pointer to the local reference file) inline in the relevant documentation paragraph or code comment.
