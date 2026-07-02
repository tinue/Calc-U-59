# Redesign & Refactoring Recommendations

Findings from a full-codebase review (Core/, Bridge/, App/, App/Views/) that need a
design decision or a coordinated refactoring rather than a spot fix. Nothing here is
urgent; the app works. Items are ordered by expected payoff.

---

## 1. Threading model of `EmulatorViewModel` (highest priority)

**Problem.** The view model mixes three execution contexts — the main thread (SwiftUI,
60 Hz `tick()`), the serial `emulQueue` (the step loop), and ad-hoc background queues
(persist writes) — and shares plain Swift properties between them with no
synchronization:

- `isRunning`, `isFullSpeedMode`, `persistPending`, `pendingFreezeOnPCChange`,
  `pendingCPUScanLoopFreeze`, `_cpuFreezeSeenLoop`, `_cpuFreezeArmPC` are read inside
  the tight step loop on `emulQueue` and written from the main thread (and vice
  versa). These are data races in the Swift memory model, even if they behave in
  practice on arm64.
- Worse, `@Observable` properties are *mutated from the emulation thread* on the
  freeze paths (`freezeOwner`, `freezeReason`, `pendingCPUScanLoopFreeze` inside
  `startEmulationLoop()`), and their `didSet` observers (`updateDebugTraceFlags`)
  run on that thread too. SwiftUI observation is not thread-safe; this can produce
  missed or corrupted invalidations.

**Recommendation.**

- Make `EmulatorViewModel` `@MainActor`. All observable state then lives on the main
  actor by construction.
- Extract the step loop into a small non-observable `EmulationLoop` class that owns
  the thread/queue and communicates with the view model through:
  - a handful of `ManagedAtomic`/`OSAllocatedUnfairLock`-protected control words
    (`running`, `fullSpeed`, `freezeRequest`), written by the view model, read by
    the loop; and
  - main-actor callbacks (`onBreakpointHit`, `onFreezeTriggered`) for the rare
    loop→UI notifications, dispatched with `Task { @MainActor in … }`.
- The freeze-arm logic (`pendingFreezeOnPCChange` / scan-loop freeze) belongs inside
  `EmulationLoop`, parameterized by the trigger; the view model should only arm and
  disarm it.

This is the single change that removes an entire class of latent bugs and makes the
rest of the file reviewable.

## 2. Split `EmulatorViewModel` (2,700 lines, ~10 responsibilities)

The class currently owns: the step loop, display refresh, key routing, printer state,
card reader flow, TI-58C persistence, state-file load/apply, card-file encode/decode,
cue-card resolution, debug log ring buffer, trace-file writing, ASM overlay flow, two
freeze machines, the live/CPU debug snapshot builders, and the ROM heatmap
accumulator. Suggested decomposition (each piece already has a natural seam):

| New type | Moves out of the view model |
|---|---|
| `EmulationLoop` (see §1) | step loop, batch pacing, freeze triggers |
| `DebugController` | freeze/step API, live+CPU snapshot builders, inspector history, heatmap, breakpoints, trace-flag ownership (`updateDebugTraceFlags`) |
| `CardController` | swipe state machine, `.U59` encode/parse (`encodeCardFileToText`, `parseCardFile` is already in StateFileLoader.swift — unify there) |
| `ConstantMemoryStore` | TI-58C persist/load, debounce timer, text encode/decode |
| `DebugLog` | ring buffer, 1 Hz display refresh, dump commands |

The view model keeps: display state, model selection, error message, and references
to the above. Views already talk to it through narrow slices, so this is mostly
mechanical file movement plus constructor wiring.

## 3. `resetMachine()` — racy and effectively dead "clear registers" block

`resetMachine()` calls `unfreeze()` (which **restarts the emulation loop**) before
`machine?.reset()` and before reading `partitionProgramRegs`. Consequences:

- The ROM's power-on sequence runs concurrently with the register writes below it.
- Immediately after `reset()` SCOM is zeroed, so `partitionProgramRegs` reads 0,
  `dataRegCount == totalRegs`, and the loop `for regNum in dataRegCount..<totalRegs`
  is **empty** — the "clear out-of-range registers" block clears nothing on the
  normal path.
- Even when the partition is live, the range is wrong for asymmetric partitions:
  clearing should start at `programRegs`, not at `dataRegCount`
  (they only coincide at the 50/50 split). E.g. partition 80:39 would clear
  RAM[40..119], clobbering program registers 40–79.

**Recommendation.** Decide the intended semantics of a soft reset first (clear data
registers? preserve everything? clear only what the switched model can't address?),
then implement it as: stop loop → `emulQueue.sync {}` → reset → apply register
policy → restart loop — mirroring the sequence `applyParsedState` already gets right.

## 4. Trace/security-scoped-resource lifecycle in `TraceWriter` / `AppSettings`

- `AppSettings.traceDirectory()` calls `startAccessingSecurityScopedResource()` on
  the *directory* URL every time it is called (including the discarded
  `_ = AppSettings.traceDirectory()` in `cIndicatorDebug.didSet`) and never stops it.
- `TraceWriter.close()` calls `stopAccessingSecurityScopedResource()` on the trace
  *file* URL, which never had a matching `start`. The start/stop pair never balances.
- Switching models while TRACE is on replaces `traceWriter` without closing the old
  session file (no SESSION_END record) and leaves `cIndicatorDebug == true` with a
  writer that was never opened.

**Recommendation.** Give `TraceWriter` sole ownership of the scoped URL: resolve the
bookmark once in `open()`, keep the *directory* URL it started access on, and stop
access on exactly that URL in `close()`. Have `EmulatorViewModel.start(model:)`
close the old writer (or carry the open session over) before replacing it.

## 5. C++ core: `TMC0501::step()` is a 500-line monolith

Functional and well-commented, but hard to modify safely. Low-risk structural moves
that don't change behaviour:

- Extract the peripheral I/O dispatch (`case 0x8:` — card, printer, RAM_OP) and the
  library-module dispatch (`case 0xE:`) into private member functions
  (`execPeripheralIO(opcode)`, `execLibraryOp(opcode)`). The printer and card logic
  are self-contained state machines already.
- Consider dedicated `CardReader` and `Printer` member objects. TMC0501 currently
  carries ~15 printer fields and ~8 card fields; both talk to the CPU only through
  `EXT`, `KR`, `FLG_BUSY`, and the key matrix, so the interface is small.
- The duplicated post-step epilogue (trace/`m_cSteps`/`m_pollSteps` accounting exists
  twice: once on the branch early-return path, once at the end) should be a single
  `finishStep(tf)` helper. Note while doing so: the branch path skips the PREG
  latch/redirect blocks — verify against hardware traces whether that is intentional
  and document it either way.

## 6. Parallel printer queues → one struct

`m_prnLines` (text) and `m_prnCodeLines` (dot codes) are two queues kept in lockstep
by convention, with the "deferred code-line commit" logic ensuring indices align.
Swift then re-pairs them by index (`printerLines[i]` / `printerCodeLines[i]`). One
`struct PrinterLine { std::string text; PrinterCodeLine codes; }` queue (and one
drain call over the bridge) removes the whole index-alignment problem, including the
`flushPendingIfActive()` ordering subtleties around PRT_FEED.

## 7. Bridge marshalling cost and shape

- `drainCpuFrames`/`readCpuFrames` box every 397-byte frame into an `NSValue`, which
  Swift immediately unboxes with `getValue(&f)`. At 60 Hz with up to 1024 frames this
  is thousands of allocations per second while the CPU panel is open. Replace with a
  buffer-based API (`fill(buffer: UnsafeMutablePointer<TICpuFrame>, max:) -> UInt32`)
  or hand Swift an `NSData` of packed frames.
- `buildLiveSnapshot` runs `snapshotCPU()` (full SCOM copy under the machine mutex)
  and `tick()` runs another one each frame, plus `checkProgramNumber()` a third at
  2 Hz. One snapshot per tick, passed to all consumers, halves mutex traffic.
- Model numbering (0/1/2) is duplicated as magic numbers in `initWithModel:`,
  `TraceWriter` (twice), and `MachineModel`. Expose one enum through the bridge
  header and derive the rest.

## 8. State duplicated between core and Swift that could drift

- `MachineModel.cardSwitchCol` (Swift) duplicates `TI59Machine::cardSwitchCol()`
  (C++); the Swift copy appears unused by the emulation path — delete or derive it.
- `ProgramSource` (Swift) mirrors PRG SOURCE values also interpreted in
  `LiveDebugView.resolvedProgramSource`. Several views still compare against raw
  literals (`case 0, 4:`, `case 8:` in `buildLiveSnapshot`); use the enum everywhere.
- The PC/return-stack "base-80" decoding exists twice in `buildLiveSnapshot`
  (once inline for six return levels, once in `decodeProgramCounter`). A single
  `decodeBase80(nibbles:)` helper with the six-level loop would replace ~40 lines.

## 9. Dead / vestigial code

- `App/Views/CPUDebugView.swift` (425 lines) is not embedded in the app (only its own
  preview references it). Delete it, or move it to an `Attic/` group excluded from
  the targets; its presence invites confusion with `CPUInspectorView` (the project
  skill already warns about exactly this).
- `TraceWriter`'s `sessionSuppressedTotal` is always 0 (dedup was removed) and the
  payload writes a constant `UInt32(0)` "suppressed count" — candidates for removal
  at the next trace-format version bump.
- `ROMLoader.loadModuleCueCards(moduleID:)` is a thin wrapper apparently unused.

## 10. Smaller quality items (roll into any nearby work)

- `CalculatorView`'s macOS ⌘-key detection polls `NSEvent.modifierFlags` in a 50 ms
  `while true` task. `NSEvent.addLocalMonitorForEvents(matching: .flagsChanged)` is
  event-driven and removes the poll.
- `CardStorage._resolvedURL` is written from a background thread in `warmUp()` and
  read from the main thread — make it a `let` resolved before first use, or protect
  it (fits naturally if CardStorage becomes part of `CardController`, §2).
- `cuecards.txt` is re-read and re-parsed from disk on every module lookup
  (`romFilename(forModuleID:)`, `loadModuleCardsAndMetadata`, `loadAllModuleMetadata`
  — three separate parsers over the same file). Parse once into a `[ModuleID:
  ModuleInfo]` cache at startup and derive all three queries from it.
- `parseStateFile` grows by keyword `if` chains in two places (pre-scan in
  `loadStateFile` duplicates directive parsing done again inside `parseStateFile`).
  Parse once, then let the caller inspect `LoadStateResult.model`/`skipReset`.
- `LiveDebugSnapshot.hir1…hir8` as eight scalar properties forces the switch in
  `buildLiveSnapshot`; a `[Double]` of count 8 simplifies both builder and view.
- `EmulatorViewModel.pendingOpsCount` reads SCOM[13] nibble 0 with a "TBD: exact bit
  position" comment, and the same nibble is decoded as the angle mode elsewhere —
  resolve experimentally or remove the field until it is known.

---

## Explicitly *not* recommended

- Rewriting the emulation core's instruction dispatch as a jump table or
  per-instruction classes. The current switch mirrors the hardware decode fields,
  is fast, and its comments carry irreplaceable reverse-engineering knowledge.
- Replacing the `m_keyMutex` "one big lock" policy in `TI59Machine`. It is simple,
  documented, and uncontended in practice (UI touches it at 60 Hz, batches hold it
  for ~284 instructions). Finer-grained locking would add risk for no measurable
  gain.
