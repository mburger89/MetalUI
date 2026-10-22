# Retained move miss and the drag ambient miss - design (C14-k, C14-l)

Items C14-k and C14-l, carried from C14-j (record 140, `DM-`). Branch `perf/retained-move-miss` from `b1c1269f`. Rulings `AM-A`...`AM-I` in
[`../2026-10-22-retained-move-miss-decisions.md`](../2026-10-22-retained-move-miss-decisions.md). Record 146 (written at the Record phase).
Divergence labels 755-764: **none taken**. **No public API** (every new declaration is `package` or internal; no inventory row; census unmoved).
No SwiftUI probe and no gpui comparison: no observable behaviour moves (output is value-identical to a retention-off twin, `AM-H`).

## 1 What the code does today (inventory)

- `ContentMemoStore.Entry.needsObservation` (`ContentMemo.swift`) is true for no record, an incomplete record, a certain miss (serial moved or `observedChange`).
  It is read at build (`EquatableComponent.buildGroup`: `observed` -> `RetainedBuild.observed` -> `record.coverageBuild`) and at prepaint
  (`retainedPrepaintPhase`: `RetainedPhase.prepaintObserved` -> `record.coveragePrepaint`, `finishRetainedPaint`).
- A **key-only miss** is a record that is valid on every conjunct but whose `ReplayKey` differs (an equal value, an unchanged serial, nothing fired) and whose
  translation is refused (a fractional device-pixel move, `FS-M`). It is the `.moved` arm of `DoubleMissFixture` (`Tests/MetalUITestingTests/DoubleMissFixture.swift`).
  Its build and prepaint windows were closed (`needsObservation` read a clean, complete record) and the key is only known at paint, so the record the miss makes has
  `coverageBuild == false` and `coveragePrepaint == false`, and the next unchanged frame misses on `[coverage.build, coverage.prepaint]` (measured h4 m4 / h4 m4, record 140 section 2).
- The ambient half of the key (`AmbientKey`, `retainedAmbientKey()`, read at paint) holds `environment` (the whole `EnvironmentFingerprint`), `snappingTransaction`
  and `disablesAnimations` of `Frame.transactionTop`. The prepaint ledger's key (`RetainedPrepaint.swift`, `retainedPrepaintKey`) holds the same members.
  MetalCreator's post-C14-j log shows two occurrences near the root (paths of nine `positional(0)`..., 20-21 misses each) and some leaves missing with
  `[key.ambient.environment, key.ambient.disablesAnimations]` together, in paint (187) and prepaint (187), and the same occurrences with
  `[coverage.build, coverage.prepaint, key.ambient.disablesAnimations]` (178) one frame later: **the 179/178 `coverage` lines are the second frame after an ambient miss**, not
  after a geometry move, so C14-k's fix alone does not remove them (`AM-C`).
- The trace (`RetainedTrace.swift`): `tail(of:length:)` is `String(path.suffix(n))` (cuts mid component, `ional(0)/positional(1)...`); the fire cause is
  `writerCause()`, the first demangled `.setter` frame of `Thread.callStackSymbols`, `?` where the setter is inlined (release) or on Windows (`DM-E`).
- Not in scope, named in section 7: `[noRecord]` (148) and `first-or-dropped` (166) lines, which follow a paint refusal clearing the record (`ineligible ... because stateWrite`).

## 2 Lane 1 (C14-k): a key-only miss makes a record that hits the next frame

Files: `Sources/MetalUI/RetainedSubtree.swift` (`RetainedPhase`, `retainedPrepaintPhase`, the miss branch of `retainedPaintDecision`, `finishRetainedPaint`),
`Sources/MetalUI/EquatableComponent.swift` and `RetainedBuild` (a `closedOnRecord` flag), tests `RetainedMoveMissTests.swift`, `DoubleMissFixture.swift` (new arms),
the `.moved` pin of `RetainedSingleMissTests.swift`. **Lane 2 does not touch these.**

1. **Prepaint half, a predictor (`AM-A`).** `retainedPrepaintPhase` already reads the occurrence's geometry (`readRetainedGeometry`) before it returns. After it,
   `prepaintObserved` (now `var`) is also true when the standing record exists and `phase.rects`/`interior`/`shapeInterior` differ from `record.key`'s. Over-observing is sound
   (it opens a session a miss will not need); a wrong "no" falls back to today's honest second miss. A steady hit frame opens no session (the geometry is equal).
2. **Build half, inherited (`AM-B`).** `RetainedBuild` records `closedOnRecord` (the build window was closed *because* `needsObservation` read a complete, clean record). At the paint
   decision's miss branch, when `valid` held (no other conjunct failed) and `old.key.describeDifference(from: key)` names only `key.rects`, `key.interior`, `key.shapeInterior`
   (ambient and `nodeCount` equal), the phase notes `inheritsBuildCoverage`; `finishRetainedPaint` sets `record.coverageBuild = phase.build.observed || phase.inheritsBuildCoverage`.
   Precedent: `DM-L` (`observed || descendantRan`) and the equivalent mutation m9 of record 140.
3. **Coverage after a change** is measured by lane 2 (`AM-J`): lane 1 builds nothing for it and does not depend on lane 2's fixture.

**Tests (all `RetainedMoveMissTests` unless named; each red on arrival where it counts work).**

| test | asserts | red before | mutation that must redden it |
|---|---|---|---|
| `aMovedOccurrenceCostsOneMissAndTheNextFrameHits` | `.moved` arm: change frame h4 m4 (the moved ones miss once), settle frame **h8 m0**, third frame h8 m0; misses per moved occurrence == 1 over the script | settle h4 m4 | m1 predictor off (`prepaintObserved` as before); m2 inheritance off; each alone reddens it (the trace names `coverage.prepaint` or `coverage.build`) |
| `theMovedFrameEqualsRetentionOff` | scene, hitboxes, accessibility, tallies, bounds equal a retention-off twin every step of the script (the oracle, as `theSingleMissFrameEqualsRetentionOff`; says it is the oracle, not the instrument) | n/a (oracle) | none expected alone |
| `aWriteAfterAMovedMissIsStillSeen` | arm `.movedPlain` (a plain child reading an observed radius under a moved node): write after the miss and after the hit that replayed it; frame equals the twin, the occurrence misses | n/a (soundness) | m3 inherit coverage on *every* miss (drop the geometry-only and `valid` guards) |
| `anAmbientMissDoesNotInheritBuildCoverage` | a miss whose key differs in `ambient.environment` (a custom environment key written above) leaves `coverageBuild == false` and the next frame names `coverage.build`: the inheritance is geometry-only (`AM-B`) | n/a | m3 |
| `aSteadyFrameOpensNoMoveWindow` | steady hit frames open 0 build and 0 prepaint sessions (`RetainedTestingHooks.windowsOpened`, package) | n/a | m4 predictor always true |
| `theKeyOnlyArmStillCostsTwoFramesOfMisses` (existing, `RetainedSingleMissTests`) | **flipped** to the new numbers and renamed `theKeyOnlyArmCostsOneMiss` | it is the negative control record 140 left, red when the fix lands | m1/m2 |

Verify mode: the whole suite under `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` (the soundness arms run there too).
Lane 1 reports before/after misses per frame on every `DoubleMissFixture` arm, `BracketFixture` (`.value`, `.panels`), `ZoomFixture` and `FilletDragFixture` (all arms).

## 3 Lane 2 (C14-l): the drag ambient miss, the path cut, the release cause

Files: `RetainedTrace.swift`, `RetainedPrepaint.swift` (`retainedPrepaintKey`), `EnvironmentValues.swift` (`EnvironmentFingerprint.differences(from:)`), a new
`Sources/MetalUI/RetainedTransactionKey.swift`, the **one line region of `retainedKey(_:)`** in `RetainedSubtree.swift` (lane 1 edits other functions of that file; the
two merge by hunk), tests `RetainedAmbientMissTests.swift`, `RetainedTraceTests.swift`, `DragAmbientFixture.swift`, probes under `docs/probes/`.

**(1) The ambient miss.** Step 0 is a measurement, in order:
- `EnvironmentFingerprint.differences(from:)` names the differing field(s); the trace prints `key.ambient.environment.<field>` (a `Mirror` guard,
  `everyEnvironmentFingerprintFieldIsNamedWhenItDiffersAlone`, owes a row per field as `everyReplayKeyFieldIsNamedWhenItDiffersAlone` does).
- `DragAmbientFixture`: N=8 `.equatable()` panels under one parent; a `DragGesture` with `@GestureState` whose `updating` body sets `transaction.disablesAnimations = true`
  (SwiftUI's idiom, `GS-`) and writes an `@Observable` radius read by one panel; frames: drag-write frame, settle frame, alternating. It must reproduce
  `ambient.disablesAnimations` flipping on the write frame (the update's transaction is parked and consumed by one build, `AN-Y`, so the next build's root transaction differs).
  If the environment half does not reproduce in the fixture, the lane models MetalCreator's likely source from the trace's named field and says which.
- **`disablesAnimations`/`snappingTransaction` (`AM-D`).** Both only decide whether an animation *starts*, which needs a value that changed, which a valid record has none of
  (a changed value moves the serial, fires, or moves a keyed geometry/ambient field). They leave the key for a record that holds **no animation touches**
  (`RetainedRecord.touches.isEmpty`): `retainedKey` and `retainedPrepaintKey` zero the two fields when the entry's standing record is touch-free (`RetainedTransactionKey.swift`).
  A record with touches keeps them (belt and braces: a separating arm is looked for with `.animation(_:value:)`, a transition and a mid-flight `withAnimation`; if none separates,
  the equivalence is recorded as `DM-O` was, not hidden). A new record made under an insensitive old one carries a normalised key and misses once if it turns out sensitive (sound).
- **`environment` (`AM-E`).** No environment read-set tracking is built (reads are plain struct property reads: nothing to hook). The measurement names the field; the lane
  rules from it: a field that is a function of another keyed field (`windowSize` = `contentSize` in `layerOpacityScale`) leaves the fingerprint comparison; a field an occurrence legitimately reads stays
  (a miss is correct). If the field is neither, the environment half is **carried as C14-m** with the named field as evidence, and the pin below is stated for the disablesAnimations half.

**(2) The path cut (`AM-F`).** `tail(of:length:)` cuts at a `/` boundary: if the path fits it is unchanged; else the longest run of whole trailing components such that
`"…/" + run` has at most `length` characters; a single last component longer than that prints `"…" + its last (length-1) characters`. Never starts mid component.

**(3) The fire cause (`AM-G`).** `writerCause()` becomes a pure `writerCause(from symbols: [String]) -> String` over the demangled frames of `callStackSymbols`:
the `.setter` frame when present (debug, unchanged); else the **nearest frame above the observation machinery** (`ObservationRegistrar`, `ObservationTracking`,
`withObservationTracking`, `MetalUI.RetainedSession`/`MemoFlags`, closures of those) that is not a `swift_`/`$sSc`... runtime frame, printed as `via <demangled function>`
(in release the setter is inlined into the writer, so this is the writer's own function, e.g. a closure in the app's view); `release-inlined` when no such frame exists;
`?` only where `symbolicatedStacks` is false (Windows). A release probe `docs/probes/observation-fire-cause-release.swift` (`-O`, positive control the debug
setter, separating arm an inlined setter) records what the frames are before the rule rests on it (`AM-G` evidence). `Event.matches(_:)` of the macOS 27
`withObservationTracking(options:)` cannot enumerate a key path, only test a candidate, and exists only on `anyAppleOS 27.0`: recorded, not used.

**Tests (`RetainedAmbientMissTests`, `RetainedTraceTests`).**

| test | asserts | red before | mutation that must redden it |
|---|---|---|---|
| `aSteadyDragCostsExactlyTheChangedPanelsMisses` | `DragAmbientFixture`, 6 drag frames: misses per frame == changed panels (1), hits N-1, no `disablesAnimations` in any reason list; scene equals the retention-off twin | misses on all panels on alternate frames | `retainedKey` always real (normalisation off); `retainedPrepaintKey` alone left real (reddens the prepaint count) |
| `aTouchfulRecordStillKeysTheTransaction` | a panel with an animated value keeps the two fields (miss on a flip) | n/a | normalise unconditionally (ignoring `touches`) - **may be an equivalent mutant**; reported either way |
| `theTraceNamesTheDifferingEnvironmentFields` + guard `everyEnvironmentFingerprintFieldIsNamedWhenItDiffersAlone` | one field flipped alone names `key.ambient.environment.<field>` | prints bare `environment` | drop one row |
| `aTraceSuffixIsCutAtASlash` | cases: fits, cut at a boundary starts with `…/`, an over-long last component, `length` 1; replaces `RetainedTraceTests` lines 143-146's `suffix` equality | mid-component cut | revert to `suffix(n)` |
| `aFireCauseNamesTheWriterFrameOrSaysReleaseInlined` | pure function over synthetic symbol lists: a setter frame, only a caller frame behind machinery, framework-only; a live debug write names the setter (skips Windows, `symbolicatedStacks`) | `?` | return `?` |
| `theTraceCostsNothingWhenOff` (existing) | `linesBuilt`/`pathsBuilt` stay 0; the new differences/frames are built inside the autoclosure | n/a | build `differences` outside it |

Lane 2 also owns the `[coverage.build, coverage.prepaint]` measurement (`AM-J`): on `DragAmbientFixture` with the `disablesAnimations` flip it records which cause each remaining `coverage` line has, before and after `AM-D`, and names any residue.
Lane 2 reports before/after misses per frame on `DragAmbientFixture`, bracket, zoom and fillet fixtures.

## 4 Invariants and gates

`METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` passes the whole suite (`AppKitPresentationTests` skipped on a locked screen); the fourteen images 0 px against `b1c1269f`
(`docs/probes/demo-pixels/compare.sh`); native unfiltered run reads one summary line (4307 at `b1c1269f` plus new tests) and `FR-J no-argument frame: succeeded=true`;
0 `warning:` on both build systems; inventory and undocumented scripts print nothing; Linux image (`metalui-portable`) `MetalUITestingTests` and the portable tests;
`MO-` flags stay locked, no new `StateTable` write site (no journal event owed), identity, hit testing, accessibility, animation, focus, `List` windowing, `Deferred` and text input unmoved.
A test relying on stack symbols skips Windows. Every new guard is mutated red once.

## 5 Demo

`METALUI_RETAINED_DEMO=1` gains nothing (counts, not looks). `docs/verification/human-checks.md`: **no additions** (no visible change; the fourteen images and the twin differentials are the check).
MetalCreator's fillet drag re-run with `METALUI_TRACE_RETAINED=1` against the merged branch is the end-to-end figure (the user's, not edited from here).

## 6 Merge order

Lane 1 and lane 2 are independent (no shared fixture; `AM-J`). Either order merges (`RetainedSubtree.swift` hunks are disjoint; `retainedKey` vs the decision).

## 7 Deferred, with reason and owner

- **`[noRecord]` / `first-or-dropped` lines** (148 / 166): they follow `retained paint ineligible ... because stateWrite`, which clears the standing record. A write to `StateTable` during paint
  is a different cause (an ineligible reason, `RW-`), not a coverage or key fact. Owner: C14-m, with the named writer.
- **Environment read-set narrowing** (an occurrence keyed on only the environment fields it read): no hook exists for plain struct reads; only if `AM-E`'s measurement shows a field no cheaper rule covers. Owner: C14-m.
- **An ambient miss's prepaint half** cannot be predicted (paint-only ambient, `SB-AA`); removed by removing the miss (`AM-D`/`AM-E`), not by a predictor.
- **MetalCreator end-to-end number.** Owner: the user.
