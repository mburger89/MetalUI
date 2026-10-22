# Retained single miss (C14-j) - design

Item C14-j: one miss per changed `.equatable()` occurrence (the double miss), and a trace that names every failing conjunct.
Branch `perf/retained-single-miss` from `195ff2c8`. Rulings: [`../2026-10-21-retained-single-miss-decisions.md`](../2026-10-21-retained-single-miss-decisions.md) (prefix `DM-`). Record: `../../record/140-retained-single-miss.md` (written at the Record phase).
No public API (package trace sink only), no divergence (labels 695-704 untouched), no SwiftUI claim (no observable behaviour moves: the oracle is a retention-off twin and `METALUI_VERIFY_RETAINED=1`; gpui has no retained-paint analogue, so no probe applies, `DM-H`).

## 1. What was found (read, not yet measured on a fixture)

MetalCreator's warm fillet drag (`fillet-trace.log`, read-only): 2768 `retained miss` lines, **1124 with an empty reason list** (41 %); the log
is pairs of consecutive frames over the same 16 occurrences: frame A names `observed`/`serial`/`interior` (a real change), frame A+1 names
nothing (15 of 16; `versions` for 1). The code explains it (`DM-B`):

1. `EquatableComponent.buildGroup` opens the build observation window only when `entry.needsObservation` (`record == nil || !record.coverageComplete`, `SB-V`).
   A standing complete record means "the sessions of the frame it was made in are still armed", so a steady frame opens none.
2. A *changed* occurrence (the getter re-ran: `serial` moved; or a read fired: `observedChange`) is **certain to miss** at paint
   (`valid` needs `old.contentSerial == entry.serial && !observedChange`), but its build and prepaint already ran **unobserved** because the
   old record was complete. The record made by the miss therefore has `coverageComplete = build.observed && prepaintObserved = false`.
3. Next frame: `needsObservation` is true, build and prepaint observe, but the decision's `valid` has `old.coverageComplete == false`: a second
   miss, all of `traceMiss`'s named conjuncts equal, so the line prints `[]`. That record is complete; the third frame hits.

So a changed occurrence costs two misses and two full paints. `traceMiss` cannot name the cause because `coverageComplete`, the ledger identity
(`phase.replayed`), the `RW-S` rule and the `ReplayKey` fields `nodeCount`/`shapeInterior` are not in it.
Two further causes can print an empty list today and are covered by the same trace: `RW-S` (a record made while the prepaint could leave no
ledger takes one miss to gain it) and a key difference in a field `traceMiss` omits.

## 2. Lane 1 - the trace names every failing conjunct (files: new `RetainedTrace.swift`, `RetainedSubtree.swift` call sites only, `RetainedPrepaint.swift` trace lines, `ContentMemo.swift` fire cause, test file `RetainedTraceTests.swift`)

* **`RetainedTrace` (package enum, `RetainedTrace.swift`).** `static var sink: (@MainActor (String) -> Void)?` (default `nil`); `static var active: Bool { retainedTraces || sink != nil }`;
  every print in `RetainedSubtree`/`RetainedPrepaint`/`ContentMemo`/`EquatableComponent` becomes `RetainedTrace.emit(_:)` behind `if RetainedTrace.active` with the string built inside the guard (`DM-C`). With the sink `nil` and the env unset nothing is built.
  `RetainedTrace.pathLength` reads `METALUI_TRACE_RETAINED_PATH` once, default 120 (`DM-F`); `sbPathTail(_:)` replaces the `suffix(60)`/`suffix(40)` calls.
* **Paint decision.** The `valid` conjunction of `retainedPaintDecision` is split into `PaintInvalidation` (a struct of the booleans, one case per conjunct) computed by one pure function used by the decision and by the trace, so the two cannot drift:
  `observed`, `serial`, `coverage.build`, `coverage.prepaint` (which half: `record.coverageBuild`/`coverageObserved` are two bits, the `Bool` stays their conjunction), `versions`, `pointer`, `ledger.identity` (`phase.replayed` set, `old.prepaint !== replayed`), `ledger.gain` (`RW-S`),
  plus `key.<field>` for **every** stored `ReplayKey` field through `ReplayKey.describeDifference(from:)` (rects, interior, shapeInterior, nodeCount, each `ambient` member, extras), guarded by a Mirror count so a new field owes a row (`DM-D`).
  A miss whose list would be empty prints `unclassified` and increments `RetainedTrace.unclassified`; no test may see it nonzero.
* **Prepaint decision.** Every `guard` conjunct of `retainedPrepaintDecision` names itself when it fails (quarantine, no record, no ledger, observed, coverage half, serial, versions, pointer in ledger, record cannot move, ledger key differs by field via `PrepaintKey.describeDifference`), one line per prepaint decision that does not replay, prefixed `prepaint`; paint lines are prefixed `paint` and carry `phase.replayed`/`grafted`/`redo` flags.
* **Fire cause.** `withObservationTracking`'s `onChange` carries no key path (probe `docs/probes/observation-fire-cause.swift`, `DM-E`). Behind `RetainedTrace.active`, `RetainedHandle.fire()` and `ContentMemoHandle.fire()` record `Thread.callStackSymbols` top frames, demangled, filtered to the writer (`<Model>.<property>.setter`, `withMutation`), into a `MemoFlags`-adjacent locked `lastFireCause: String?` on the entry; `traceMiss` prints it after `observed`. Zero cost off: the capture is inside the guard.
* **Tests (Swift Testing, `RetainedTraceTests.swift`; all use the sink, never stdout).**
  1. `thePaintTraceNamesEachConjunctWhenItFailsAlone` (arguments: one per `PaintInvalidation` case): pure-function unit over hand-built inputs where exactly one conjunct is false; asserts the case and the printed name. Red before: no function exists (compile); the pre-change `traceMiss` printed `[]` for coverage, ledger identity, `RW-S`, `nodeCount`, `shapeInterior`. Mutation: delete a case's `if` from the reasons function (reddens that argument only); swap `coverage.build`/`coverage.prepaint` (reddens their two arguments).
  2. `aFixtureMissNamesCoverageObservedSerialAndTheLedgerGain` (window level, `TestApp`, the fixture of lane 2's `DoubleMissFixture` arms `.value`, `.observed`, `.ledgerGain`): steps the script and asserts the sink saw `serial`, `observed` + a cause naming the model property, `coverage.build` on the frame after a change (today's behaviour, before lane 2) and `ledger.gain`. Mutation: make `retainedPaintDecision` read a private copy of `valid` instead of the shared function (reddens: the decision and the names disagree, asserted by `theDecisionAndTheTraceShareOneFunction`, which compares `valid` with `reasons.isEmpty` over every window-level frame).
  3. `noMissLineEverHasAnEmptyReasonList` (bracket `.value`/`.panels`, zoom, fillet-drag arms, retention on, sink collecting): every `miss` line has a nonempty list and `unclassified == 0`. Mutation: remove `key.nodeCount` from `describeDifference` and force a node-count change in a unit arm (reddens via `unclassified`).
  4. `thePrepaintTraceNamesTheFailingGuard` (one argument per guard: quarantine, observed, coverage, serial, versions, pointer, ledger key field): window-level where reachable, else the extracted `PrepaintInvalidation` pure function like 1. Mutation as 1.
  5. `theFireCauseNamesTheWritingProperty`: a `@MainActor @Observable` model whose `radius` write fires a retained session; the cause string contains `radius`. Skipped with a named reason where symbols are stripped (`-c release` guard `#if DEBUG`); Darwin and Linux debug both run it. Mutation: capture nothing (reddens).
  6. `theTraceCostsNothingWhenOff`: Darwin only, `countAllocations`, differential and floor-corrected (`PA-J`): a steady 16-occurrence frame with the sink `nil` allocates no more than the frame at `4a` baseline plus zero (`RetainedTrace.linesBuilt` also `== 0`). Mutation: build the string before the `active` check (reddens both).
  7. `thePathSuffixIsAtLeast120ByDefaultAndConfigurable`: `sbPathTail` of a 200-char path is 120, of a set `pathLength` that length. Mutation: `suffix(60)` (reddens).
  8. Typecheck guard `TR.1` (`RetainedTraceCompileGuards.swift`): a plain import cannot name `RetainedTrace.sink` (package). Mutated red once by making it `public` in a scratch copy.

## 3. Lane 2 - one miss per changed occurrence (files: `EquatableComponent.swift`, `ContentMemo.swift` (`needsObservation`), `RetainedSubtree.swift` `retainedPaintDecision`/`finishRetainedPaint`/`RetainedRecord`, `RetainedPrepaint.swift` `RetainedPhase` observation flag, fixture `DoubleMissFixture.swift`, tests `RetainedSingleMissTests.swift`)

Starts after lane 1 has landed (one agent at a time here, and the trace is its instrument: step 0 runs the fixture with it and records which conjunct names each second miss, confirming `DM-B` before any code moves).

* **`DoubleMissFixture` (`Tests/MetalUITestingTests`, `TestApp`).** One parent `Component` looping over 8 value-typed `NodeView: Equatable` components with `.equatable()` in a `ForEach` (the shape of MetalCreator's `CanvasLayers`); each draws a rect, a text and a `Button` (hitbox, so a prepaint ledger exists), the parent re-runs each step. Arms: `.value` (the step changes K of the 8 values, `serial` case), `.observed` (the node reads an `@Observable` property, `observed` case), `.moved` (the step changes one node's origin, key-only), `.ledgerGain` (the node is a field-bearing view whose first frame is a creating write, `RW-S`). Script: warm 3 frames, then S steps of one changed-occurrence-set each followed by one settle frame.
* **The change (`DM-C`, `DM-G`).** (a) `needsObservation` gains the certain-miss predicate `record.contentSerial != serial || observedChange`, read at build and again at prepaint (`prepaintObserved`), so the build and prepaint windows are observed on the frame of a change and the record made by that miss is `coverageComplete` the same frame; a steady frame is unchanged (no session). (b) `RW-S`: a hit whose old record has no ledger and whose frame produced one **adopts it** when every read of the ledger is in the record's versions or is unchanged since the record's own frame (`refreshLedger`'s subset rule, extended); otherwise the miss stays (`DM-G`; verify mode is the oracle, a difference keeps the miss and is recorded). (c) key-only misses (`.moved`) are measured; if the inheritance of the standing build session is sound under verify it lands as `DM-D2`, else carried (named below).
* **Tests (`RetainedSingleMissTests.swift`).**
  1. `aChangedOccurrenceCostsOneMissAndTheNextFrameHits` (arguments: `.value`, `.observed`, `.ledgerGain`): over the script, `retainedMisses == changedOccurrences` and `retainedHits` is up by the same count over the frames after the changes (conservation `hits + misses` unchanged from the retention-count at warm). **Red on arrival: 2 per change today** (measured in the red run; step 0 prints the table). Mutation: restore `needsObservation` to `record == nil || !coverageComplete` (reddens `.value`, `.observed`); drop (b)'s adoption (reddens `.ledgerGain`).
  2. `theDoubleMissFixtureStillMissesTwiceWhereItIsNotFixed` (`.moved`, only if `DM-D2` is carried): pins 2 and names `DM-D2` so the carry cannot rot; flips with the fix.
  3. `theSingleMissFrameEqualsRetentionOff` (all arms): scene, hitboxes and accessibility via `RPSnapshot` equal a retention-off twin (`window.testingRetainedSubtrees = false`) every script frame. Mutation: adopt the ledger with the reads check removed (reddens `.ledgerGain`).
  4. `aStaleSessionStillFiresAfterTheSameFrameRecord`: after the change frame, write the observed property; the next frame must miss (the record made in the change frame is armed, not silently complete). Mutation: mark `coverageComplete = true` without running the windows (reddens). This is the soundness pin of (a).
  5. `aLedgerWhoseReadsAreNotNamedStillMisses`: negative control of (b). Mutation: adopt unconditionally.
  6. The whole suite under `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` (existing tests; the verify run is the value-identity proof). `theFilletDragReasonsAreProfiled`'s `<= frames` miss bound and the bracket/zoom/panels literals are re-read and, where they move, **moved by ruling with numbers** (`DM-I`), never loosened.
* **Report (record §140):** before/after tables on `DoubleMissFixture` (all arms), the bracket fixture (`.value`, `.panels`), the zoom fixture and the fillet drag (misses, hits, element requests, prepaints, contentEvaluations per frame); pins count work, never time.

## 4. Invariants and what must not move

`METALUI_VERIFY_RETAINED=1`/`METALUI_VERIFY_LAYOUT_MEMO=1` whole suite; the fourteen images 0 px against `195ff2c8`; `theSevenRetentionSlotsAreMutuallyDistinct`; MO- flags stay locked (no new unlocked flag; `lastFireCause` is under the `MemoFlags` lock or the main actor only); a new `StateTable` write site would owe a journal event (none planned); framework reads through `readState`/`peek`; no goldens; no test sleeps. After lane 1 the existing `print` lines keep their text prefixes where tests or docs grep them (`retained miss`, `retained first-or-dropped`, `retained refused`, `retained ineligible`) and gain `paint`/`prepaint` after the word `retained`; the doc mentions (record §109 §341) are historical and not edited.

## 5. Deferred, by name

* Key-only misses (a changed origin or interior with the same value), unless `DM-D2` lands: owner C14-k; reason: the prepaint reads depend on the rects, so a build-half inheritance needs verify evidence on a fixture that does not exist yet.
* A key path for a fire cause (not available from `withObservationTracking`): owner a Swift Observation SPI revisit (`DM-E`); the writer's symbol is the carried substitute.
* The `versions` second cause in the log (one occurrence per frame, a `@State` written by input): named by the trace; fix only if lane 2's step 0 shows it is the same mechanism.
* Windows/Linux trace symbol quality (release symbol stripping): the cause is best-effort, never read by a decision.

## 6. Demo and human checks

No demo section (counters, not looks). No human-check group (nothing a person sees; `METALUI_TRACE_RETAINED=1` is read by developers). `docs/testing.md` gains one sentence on `RetainedTrace.sink` at the Record phase.
