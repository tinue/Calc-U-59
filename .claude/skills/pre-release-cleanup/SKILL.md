---
name: pre-release-cleanup
description: Run close to a release to audit GUI parity, simplification, docs (both repositories), changelog and screenshots, fix what is simple, and report what stands between the branch and a release.
disable-model-invocation: true
---

# Pre-release cleanup

Bring the release branch to a releasable state. Each gate below ends in one
status for the final report: **green**, **fixed** (was off, now green) or
**open** (needs work beyond this session, with the reason). The gates run in
this order because each one's result feeds the next: parity fixes change code,
simplification reshapes it, and the docs describe what remains.

Commit each logical fix on the current branches, and leave pushing to the user.
Invoke the area skill from the `CLAUDE.md` table before changing anything in
that area.

## 0. Baseline

1. Take the target version from the branch name (`dev-X.Y.Z`) and confirm it
   equals `MARKETING_VERSION`.
2. Find **base**, the previous release tag, as the `calc-u-59-docs` skill's
   Release Documentation Update Workflow, step 1, describes. Every "this
   release" below means `base..HEAD`.
3. In `../calc-u-site`, confirm the branch is `59/X.Y.Z`. Its rules are in that
   repository's `CLAUDE.md`.
4. Confirm both working trees are clean. If either is dirty or on another
   branch, ask before going on: your commits would mix with the user's work.

## 1. GUI parity

`tools/check_parity.sh <base>` is only a first filter: it passes as soon as
both apps were touched anywhere. The real audit is by feature.

1. List every user-visible change of this release from `CHANGELOG.md` and
   `git log <base>..HEAD`.
2. For each change, find its implementation in the Swift app, the Qt app and,
   where the Web column of `reference/FrontendParity.md` puts it in scope, the
   web client. Read the code, including the platform conditions around it.
3. Check its row in `FrontendParity.md` against what you found. Also look for
   non-GUI logic this release added in `App/`, `Qt6/app/` or `Web/`; it belongs
   in `Shared/`.

Done when every change has a verdict for every GUI in scope.

Sort each gap:

- **Simple:** a GUI-only change in the pattern of its counterpart, such as
  wiring an existing `Shared/` call, a label, or a table row. Fix it.
- **Bigger:** it needs new `Shared/` logic, a new view, or a design decision, or
  it is unclear whether the difference is deliberate. **Halt here**: finish the
  simple fixes, enter plan mode and present a plan for the big gaps. The later
  gates would otherwise document code that is about to change. Run them after
  the plan is done or the user defers it; a deferred gap stays **open**.

A `Pending` row added in this release counts as a gap unless the user accepts
it. Older `Pending` rows are listed in the report without blocking.

## 2. Simplification age

Read `git log --stat simplified..HEAD`, after the parity fixes.

- **Fresh:** every commit is docs, changelog, examples or similar, or a small
  code fix in one spot that adds no new function or file.
- **Stale:** any larger code change in `Core/`, `Shared/`, `App/`, `Bridge/`,
  `Qt6/`, `Web/` or `tools/`.

If stale, name the commits and ask whether to run `/simplify` now. On yes, run
it and continue. On no, the gate stays **open**.

## 3. Documentation of this release

Follow the `calc-u-59-docs` skill's Release Documentation Update Workflow, for
`reference/` and for the user guide in `../calc-u-site` (with its `site-59`
skill). The workflow's changelog step only needs completeness here, since gate
5 reworks the text.

Done when each user-visible change and each changed developer fact (file format,
directive, setting, API, architecture) points to a passage in the right
repository that describes its final state, and the site's build, check and tests
pass.

## 4. Documentation consistency

Sweep `README.md`, `CLAUDE.md`, `TODO.md`, `reference/`, `rom/*.md`,
`.claude/skills/` and the site's `59/Pages.jsx`. A read-only subagent per group
keeps the file dumps out of this context; verify each finding before editing.

Look for:

- **Contradictions:** the same fact stated differently. The code decides which
  is right, or a measurement for hardware numbers.
- **Retired terms:** every name this release removed, renamed or replaced, still
  used as current anywhere. Past `CHANGELOG.md` entries stay as they are.
- **Duplication:** one fact with several homes. Keep it where the
  `calc-u-59-docs` documentation policy puts it and link from the others. The
  site may mention a developer topic and link to it.
- **Broken indexes:** `README.md`'s document index against the files on disk, and
  relative links and section references that no longer resolve.

Fix them in place. A contradiction you cannot settle from code goes in the
report as **open**. `ideas/` holds proposals and is out of scope.

## 5. Changelog

Rework the `[X.Y.Z] - work in progress` section so it reads as the difference
between `base` and this release for someone using the app. Leave the heading
undated; `release --rc` dates it.

1. **Missing entries:** go through `git log <base>..HEAD` and the diff, and add
   a line, in the existing style, for each change that the next check says
   belongs here but has none. Judge by the code as well as the commit subjects:
   a commit can carry more than its subject says.
2. **User-visible:** remove or rewrite lines about refactoring, tests, tooling
   and internals. A single new example file gets no line. Emulation accuracy
   gains always get one, and so does any other behaviour change a user can
   notice.
3. **Net change:** compare each line with `base`.
   - Describe a feature changed several times during the release in its final
     form only.
   - Drop anything added and removed again within the release.
   - For each line under `### Fixes`, confirm in `git show <base>:<path>` that
     the released version had the bug. A bug born and fixed within this release
     has no line. If the wrong behaviour reached users, it stays.
4. **App Store marker:** the unmarked lines become the iOS app's What's New, so
   ask of each line whether an iOS user gets this.
   - No: mark it `<!-- appstore: skip -->`.
   - Partly: split the line, or reword it so it holds for iOS, with the other
     clients in a separate skipped line.
   - Wording needed only for the store: `<!-- appstore: only -->`.

   Unmarked lines must also avoid the words in `notes_forbidden` in
   `release.yaml`. `release --dry-run` reports violations and changes nothing.

Done when every commit of this release is either covered by a line or
deliberately left out, and every line, old or new, has passed these checks.

## 6. Screenshots

Report here and change nothing until the user agrees. Running the script drives
the simulators and takes a while.

**App Store set** (`appstore/screenshots/`, on the `appstore` worktree branch):

1. Compare the file list with the `run_named_test` entries in
   `bin/run-screenshots`, to catch missing or orphaned shots.
2. For each shot, take its date from `git -C appstore log -1 --format=%cI --
   screenshots/<file>`, then list later commits on this branch touching `App/`,
   `App/Assets.xcassets`, `Calc-U-59UITests/ScreenshotTests.swift`,
   `examples/screentest/` or GUI-related `Shared/` files.
3. Open each shot that has such commits and decide whether the change is visible
   in it on iOS. A later commit alone proves nothing: a Mac-only change or a
   change to a screen the shot does not show leaves it current.

**Site set** (images under `59/assets/` that `59/Pages.jsx` shows): open them
and compare them with the current UI as the code and App Store set describe it.

If a shot is out of date, list it with the commit that outdated it and propose
the narrowest command: `bin/run-screenshots [filter]`. The iPhone Duo shot needs
the simulator opened flat first. If the user agrees, run it, check the new
images, and commit them in the `appstore` worktree. Site images are copied over
by hand, so name the copies needed. Otherwise the gate stays **open**.

## 7. Builds

Run all of these, including when this session changed no code: a release needs
them passing on the final tree.

- The three builds in `CLAUDE.md` § "Frontend Parity": CMake with ctest,
  `xcodebuild` for macOS, and `Web/build.sh && Web/run-tests.sh`.
- `tools/build_qt.sh`.
- The site's build, check and tests, as `site-59` describes.

If code changed after gate 2, re-judge the simplification age.

## 8. Report

End with this report, every gate included:

```markdown
## Pre-release cleanup: X.Y.Z (<base>..<short HEAD>)

| Gate | Status | Note |
|---|---|---|
| GUI parity | | |
| Simplification age | | |
| Docs of this release: this repository | | |
| Docs of this release: calc-u-site | | |
| Docs consistency | | |
| Changelog | | |
| Screenshots | | |
| Builds | | |

### Needs extra work
Each open item: what is wrong, why it was not done here, and the proposed next
step. Older `Pending` parity rows go here too, marked as not blocking.

### Done
What changed, by gate, with commit hashes per repository.

### Result
```

Under **Result**, write `ALL GREEN: ready for release` only if every gate is
green or fixed and you verified that in this session. Otherwise write
`NOT GREEN` and the number of open items. After open items are resolved, re-check
those gates plus builds and post the report again, so the user receives an
all-green report.
