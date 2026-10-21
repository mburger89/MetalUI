# 135 — `@GestureState` and `phaseAnimator`

Branch `feat/gesture-state` from `1bdead8d` (master: sample app and SDL GPU gaps merged in at the Record phase, `11dca65e`). **Not a plan task**: item G1 of
the gpui-gap priority list (user request 2026-10-02, round 2 started 2026-10-21). Spec `docs/superpowers/specs/2026-10-21-gesture-state-design.md`; rulings
`GS-A`…`GS-S` in the new decisions doc `docs/superpowers/2026-10-21-gesture-state-decisions.md` (next unused `GS-T`); probe `docs/probes/swiftui-gesture-state.swift`
(arms `G1`–`G13`, `P1`–`P10`, the instrument of `swiftui-input-followups.swift`).

**Numbering.** Written as §135 from the start. Master published §136 (sample app) and §137 (SDL GPU gaps) while this branch was open; §133 and §134 belong to the
two other sibling lines (C14-i, L1) and are not on master yet, so 135 is free and stands. The merge with master `11dca65e` was clean (no conflict); the divergence
label range 645–654 and the group letter `GS` were reserved for this branch, and no other branch took either.

**Status: LANDED — every agent-doable clause is built; the looks and the probe re-take are owed to a human** (`docs/verification/human-checks.md` group GS, §9).
Two lanes (lane 1 `@GestureState`, lane 2 `phaseAnimator`), disjoint source files, each red first, each verified `ok: true`; this Record phase re-took the suite,
the counts, the inventory scripts and the demo comparison (§6).

## §0 Baseline, design session and critic round (2026-10-21)

- **Baseline** at `1bdead8d`: **4117 tests in 3 suites** (native, unfiltered), 0 goldens, 3683 public declarations in the census, 158 live divergences.
- **Carried items.** `IF-E`/`IF-F`/`IF-K`/`GC-` (every `onCancelled` path), `IX-B`, `ID-F`, `LK-I` (`keyframeAnimator`'s scope), `AN-Y`, `RW-`/`RK-F`, `theSevenRetentionSlotsAreMutuallyDistinct`.
  `IF-A` and `LK-H` had deferred the two features; this record discharges both.
- **Probe.** `swiftui-gesture-state.swift`, run by the designer on 2026-10-21 with the screen **unlocked** (lock probe: no `CGSSessionScreenIsLocked`, `displayAsleep main: 0`):
  `G1` the positive control, `G2`/`G5b` taps (never run), `G3`/`G4`/`G12` a long press ending, held or failing, `G5` a drag below its minimum, `G6` two states on one gesture,
  `G7`–`G7e` one state on two simultaneous gestures (the separating arms), `G8`–`G11` reads in callbacks and the reset's transaction, `G13` declaration order; `P1`–`P9`
  the stepping, `P3` the separating arm for `P2`, `P10` content independent of the phase. Reduce Motion (`R`) is **not measurable** by an agent: the key is read-only.
  gpui has no counterpart for either feature (a gpui view resets its own state in its mouse-up handler; its animations have no phases): nothing is claimed from gpui.
- **Critic round** (`GS-O`, `GS-P`): the critic could not re-run the probe (locked screen), so the header's lines stood **unverified by the critic** and three pins carry
  "recorded, not re-taken"; and lane 2 was forbidden to edit `Retained*.swift` (C14-i's files), so a red `.equatable()` arm is pinned as measured, not fixed.

## §1 What landed

**Lane 1 — `@GestureState` and `Gesture.updating(_:body:)`** (`Sources/MetalUI/GestureState.swift`, `Gesture.swift`, `SpatialGestures.swift`, a three-line edit of `Window.swift`):

- **`GestureState<Value>`** is a `@MainActor` property wrapper holding a `State<Value>` and a `GestureStateBox<Value>` (the dirty set and the per-event base, per slot). It
  conforms to `BindableState`, so `StateBinder` seeds it exactly as `@State` — the `$state<n>` slot, the occurrence aliasing of `ID-F` — and **no reserved name is added**
  (`GS-A`, `GS-Q` 1); reads are `StateTable.peek`, writes `StateTable.write`, which already taints the retained, prepaint and memo-journal logs. The eight spellings of the interface
  census (`init(wrappedValue:)`, `init(initialValue:)`, each with `resetTransaction:` or `reset:`, and the two `ExpressibleByNilLiteral` ones); `wrappedValue` is get-only,
  `projectedValue` is the state itself (`GS-B`).
- **`updating(_:body:)`** `(Value, inout State, inout Transaction) -> Void` on `DragGesture`, `LongPressGesture`, `MagnifyGesture`, `RotateGesture`, and on `TapGesture`/
  `SpatialTapGesture` where it compiles and **never runs** (probe `G2`, `G5b`); it returns the receiver's own type with the update stored, so it chains with `onChanged`/
  `onEnded` as SwiftUI's does. Updates and `onChanged` run in **declaration order** (`GS-E`, probe `G6`, `G13`).
- **The reset.** `GestureLeaf` gained one hook, `finished`, queued by the arena in `fail(_:)` and in `act(_:)` just before the leaf's ended callback, and handed back by `cancel()`/
  `abandon()` through `ArenaLeaf.owesFinish` — so the state resets at the release (before `onEnded`), when a long press ends while held or fails (not at the release), and on every
  `onCancelled` path of `IF-E`/`IF-F`/`GC-`: a dropped arena, a lost release, key loss, window close (`GS-C`, probe `G1`, `G4`, `G8`, `G12`). It runs **once per leaf** and the
  reset itself only if the slot is dirty (`GS-D`). The audit of every site that discards an arena without `cancel()`/`abandon()` found each paired with one or unreachable for an
  undecided leaf; **no new `cancel()` was needed** (`GS-Q` 5).
- **Writes** (`GS-D`): every body of one event starts from the value committed before the event (`GestureStateBatch.current`, bumped once per `Window.runGestureCallbacks`
  call), writes its copy back always, and the last body run wins; ending any writer resets the whole slot. **Transactions** (`GS-F`): the update runs under its transaction
  only when the body set an animation, the reset under `resetTransaction` (then the `reset:` closure's writes) only when that animates — the existing `parkTransaction` path, so an
  animated reset is divergence 99's one root transaction for the next build.
- **Divergence 645** (the order of two simultaneous writers) is taken with **646**, the `@MainActor` on `updating` and `reset:` (`GS-N`, `GS-S`; guard GS.5 `theUpdatingBodyAndTheResetClosureAreMainActor` (pins the method's isolation; a body-only mutation survives, measured)).

**Lane 2 — `phaseAnimator` and `PhaseAnimator`** (`Sources/MetalUI/PhaseAnimator.swift`, an internal `Animation.nominalDuration`):

- **`PhaseAnimator<Phase: Equatable, Content: ElementGroup>`** and `phaseAnimator(_:trigger:content:animation:)` / `phaseAnimator(_:content:animation:)` in both vocabularies,
  `keyframeAnimator`'s pair line for line (`GS-H`): a **transparent scope** (no node, no identity level), its record a non-generic `PhaseRecord` in the window's `AnimationStore`
  keyed `$phase<depth>` — never a `StateTable` slot, the seven slots unmoved — sharing `keyframeDepth`'s counter (the names differ, so no collision) and swept like a keyframe record.
- **Stepping** (`GS-I`, probe `P1`–`P9`): the first phase is built with no `animation` call; with no trigger the animator steps `1, 2, 0, 1, …` forever, with a trigger it runs `1, 2, … , 0`
  once per change and ends (no change runs nothing, a change mid-run restarts at once from `phases[1]`); each phase is held for `Animation.nominalDuration` of the animation just
  entered; a nil animation snaps and the next step follows at once; equal neighbours step with no wait; fewer than two phases run nothing. A step's start is its **scheduled** time (no
  drift at 60 Hz, no burst after a stall); a build takes at most one step. While running it calls `noteActiveAnimation()` and **never `requestAnotherFrame()`**.
- **Transaction** (`GS-J`): the content is built under `inherited with animation = animation(phase)` on the build that took the step (layout, re-pushed in paint, prepaint pushes
  nothing: `AN-Y`'s shape). **Reduce Motion is not changed and not claimed** (`GS-K`: unmeasurable, human check GS3). An empty phase list traps naming `phaseAnimator`.

## §2 Tests and guards, per file

Lane 1 (21 tests, 4 of them guards):

- `Tests/MetalUITestingTests/GestureStateTests.swift` (15): `aDragUpdatingMovesAViewDuringTheDragAndSnapsBackAtTheRelease` (`G1`),
  `theResetRunsBeforeOnEndedAndOnChangedReadsTheWrite` (`G8`), `updatingOrderFollowsDeclarationAgainstOnChanged` (`G13`, `G6`),
  `aLongPressUpdatingIsTrueFromThePressAndResetsWhenItEndsWhileHeld` (`G4`), `aLongPressThatFailsResetsAtTheFailureNotTheRelease` (`G3`, `G12`),
  `aTapGestureUpdatingCompilesAndNeverRuns` (`G2`, `G5b`), `updatingBeginsWithTheFirstRecognizedChange` (`G5`), `everyCancelPathResetsOnce` (arms (a)–(g), one per `IF-F`/`GC-`
  path, the reset closure counted == 1), `aDisabledOwnerResetsAtTheReleaseAndNotBefore`, `theResetClosureAndTransactionApply` (`G9`–`G11`),
  `simultaneousWritersStartFromTheEventsCommittedValueAndTheLastWins` (645, pinned wrong on purpose), `anyWriterEndingResetsTheSharedState` (`G7b`, `G7c`),
  `aGestureStateIsAStateSlotNotAnEighth`, `aGestureStateWriteIsAStateWriteForTheMemoAndRetainedPaths`, `anElementValuePlacedTwiceResetsItsOwnOccurrence` (`ID-F`).
- `Tests/MetalUITestingTests/GuideMirrorsGestureState.swift` (2): the `docs/guides/input.md` snap-back chip and its animated return
  (`theInputGuideAGestureStateSnapsBackAtTheRelease`, `theInputGuideTheResetTransactionAnimatesTheReturn`), mirrored byte for byte (`DG-C`).
- `Tests/MetalUITests/GestureStateCompileGuards.swift` (4 plain-import guards, each mutated red once): the eight spellings compile for an outside module; `updating` chains on the
  concrete gestures and does not compile on a composition; `wrappedValue` has no setter; `GestureStateBox` is unreachable.

Lane 2 (18 tests, 2 of them guards):

- `Tests/MetalUITests/PhaseAnimatorTests.swift` (14): the cycle (`P1`), the trigger run and its separating arm (`P2`, `P3`), a mid-run bump (`P4`), a nil animation (`P5`, recorded, not
  re-taken), step spacing from the animation's duration (`P6`, `P9`), one phase and equal neighbours (`P7`, `P8`), each phase's content built under its animation, the scheduled step
  that does not drift and a stalled frame that steps once, the sweep, transparency to identity and the `StateTable`, `requestAnotherFrame` never raised, proposal content kept proposal,
  the empty-list trap (exit test).
- `Tests/MetalUITestingTests/PhaseAnimatorRetainedTests.swift` (1): `aPhaseAnimatorInsideAnEquatableComponentKeepsSteppingGSP` — refused by name every frame (`timeVarying`), never
  skipped, replayed or grafted, one phase per 0.4 s tick (`GS-R` 7).
- `Tests/MetalUITestingTests/GuideMirrorsPhaseAnimator.swift` (1): the `docs/guides/drawing-and-gpu.md` pulse and triggered swing; `GuideDocCheck.deniedNames` is now empty.
- `Tests/MetalUITests/PhaseAnimatorCompileGuards.swift` (2 guards, each mutated red once): the SwiftUI call shape compiles for an outside module, a `Self`-returning decoration after it does not
  (`LK-T` item 2), `Phase` must be `Equatable`.

**Typecheck guards:** six new (four lane 1, two lane 2). **Goldens:** 0. **Inventory:** four rows in `closeout-inventory-map.tsv` (`GestureState.swift`, `PhaseAnimator.swift`, the
`updating` members, two `F` rows); census re-recorded.

## §3 Probes

`docs/probes/swiftui-gesture-state.swift`, header holds the recorded output verbatim (2026-10-21, macOS 27.0.1, Apple Swift 6.4, screen unlocked). Positive controls: `G1`, `P2`;
separating arms: `G2`/`G5b` (a tap never runs), `G7d` against `G7e` (declaration order decides the writer), `P3` (no change, nothing runs), `P5` (nil animation), `P10`.
**Not re-taken:** `G7`, `G7e` (the claim behind divergence 645) and `P5`: the screen was locked at the critic round, at both lanes and at this Record phase, so 645's row and
three pins carry "recorded 2026-10-21, not re-taken" (`GS-O`); human check GS7 re-takes them byte for byte.

## §4 Divergences

**645**, **646** (`@MainActor` on `updating` and `reset:`) added, **236** amended (record §04). Retired: none. SwiftUI's own end-of-run content call and its not re-calling
content that ignores the phase (`P2` `c0@1.2`, `P10`; unpinned, unobservable but by side effect, `GS-I`). Not built, named: `updating` on a composed gesture, the
`GestureStateGesture` type, `PlaceholderContentView` (`phaseAnimator`'s content receives the element itself, as `keyframeAnimator`'s, divergence 169's rule).

## §5 Red runs and mutations

Every test was red first: lane 1's at `4792c5ee` (`unknown attribute 'GestureState'`), lane 2's at `fa6fd884` (`value of type has no member 'phaseAnimator'`).

**Lane 1** (the implementer's seventeen mutations and four guard mutations, run on a filtered set of `GestureStateTests`, the guards, the mirror and the gesture and arena suites):

| mutation | reddened |
|---|---|
| M1 delete `finished`'s queue in `act` and `fail` | 12 tests including `aDragUpdatingMovesAViewDuringTheDragAndSnapsBackAtTheRelease`, `everyCancelPathResetsOnce`, `theInputGuideAGestureStateSnapsBackAtTheRelease` |
| M2 queue `finished` after the ended callback | `theResetRunsBeforeOnEndedAndOnChangedReadsTheWrite` |
| M3 updates always before `onChanged` | `updatingOrderFollowsDeclarationAgainstOnChanged` |
| M4 remove `finished` from the long-press ended arm | `aLongPressUpdatingIsTrueFromThePressAndResetsWhenItEndsWhileHeld` |
| M5 remove the queue from `fail` | `aLongPressThatFailsResetsAtTheFailureNotTheRelease`, `everyCancelPathResetsOnce` |
| M6 wire the tap's ended callback to the update | `aTapGestureUpdatingCompilesAndNeverRuns` |
| M7 run the update at the press | `updatingBeginsWithTheFirstRecognizedChange`, `aDragThatNeverBeganIsNotCancelled`, `aSecondaryDragActivatesAtItsMinimumDistance` |
| M8 `cancel()` stops draining the finish callbacks | `everyCancelPathResetsOnce` |
| M9 `abandon()` stops draining | **green by design**: `abandon()`'s later `resolve()` returns what `cancel` left, a correct alternative spelling |
| M11 ignore `resetTransaction` | `theResetClosureAndTransactionApply`, `theInputGuideTheResetTransactionAnimatesTheReturn` |
| M12 park a nil-animation transaction | **green**: plausibly equivalent (`withTransaction` of an animation-less transaction changes nothing) |
| M13 take `base` from the live value every time | `simultaneousWritersStartFromTheEventsCommittedValueAndTheLastWins` |
| M14 give the box its own slot name | `aGestureStateIsAStateSlotNotAnEighth`, `aGestureStateWriteIsAStateWriteForTheMemoAndRetainedPaths` |
| M16 resolve with `slotID` only | `anElementValuePlacedTwiceResetsItsOwnOccurrence` |
| M17 remove the dirty guard | `anyWriterEndingResetsTheSharedState` |
| GG1–GG4 (guard mutations) | `theEightGestureStateSpellingsCompileForAnOutsideModule`, `updatingChainsOnTheConcreteGestures`, `aGestureStateWrappedValueHasNoSetter`, `theGestureStateBoxIsNotReachable` |

The verifier re-ran the **unmutated** full suite once (4138 tests, matching) and re-ran none of these. **Named gaps:** `aDisabledOwnerResetsAtTheReleaseAndNotBefore`'s mutation
("run the reset at the disable") has no recorded red; M10 and M15 are not in the verifier's table. The no-version-bump mutation `aGestureStateWriteIsAStateWriteForTheMemoAndRetainedPaths` is
named for could not be spelled at this Record phase (§5.1).

**Lane 2** (the implementer's twenty-one mutations on a filtered set, each named in its test's header as `Mutation:`: the first step, `requestAnotherFrame()` for the note, a run that stops at the
last phase, a trigger change that continues the old run, a nil animation waiting `.default`, a fixed 0.4 s step, equal neighbours waiting, the previous phase's animation, `stepStart = now`,
the sweep keeping the record, a typed entry dropping the transaction, the removed precondition, the note of the active animation removed, the guards' two). The verifier re-ran **one on the
full suite**: a trigger run that never ends (`if r.running, r.stepsTaken >= count { r.running = false }` replaced by `if false, …`) reddened `aTriggerRunsEveryPhaseOnceAndReturnsToTheFirstP2P3`,
`onePhaseRunsNothingAndEqualNeighboursStepWithoutWaitP7P8` and `theDrawingGuideAPulseCyclesAndASwingRunsOncePerTrigger`, then restored (`git status --short` empty).

### §5.1 Record-phase mutation

The mutation `aGestureStateWriteIsAStateWriteForTheMemoAndRetainedPaths` is named for (a write that does not bump the slot's version) was **attempted and could not be spelled**:
`StateTable.storage` and `Entry.version` are `private`, and `GestureState.write` has no other writer than `StateTable.write` (which bumps and taints; every spelling that avoids the bump means a private store beside the
table, a rewrite of `update`/`finish`/`peek` rather than a one-line mutation). The source was restored (`git status --short` empty). The test is proven red by M14 and M1 only; the bump itself rests on
`StateTable.write` being the one funnel (`GS-A`) and on `everyStateWriteSiteIsClassified` staying green. **Named gap**, not a claim.

## §6 The demo and the fourteen images

Both demos are existing env-gated ones, each section its own function or `Component` (Windows' 1 MB stack, `everyProductionTreeBuildsOnAOneMegabyteThread`): lane 1's drag chip and hold chip
in `InputFollowupsDemo.swift` (`gestureStateChips()`, `GestureStateDragChip`, `GestureStateHoldChip`, under `METALUI_CANVAS_DEMO=1`), lane 2's `PhasesDemo` in `LooksDemo.swift`'s keyframes row
(`METALUI_LOOKS_DEMO=1`, no new click target: the trigger is the row's own "Shake" count). The default `demoContent()` is untouched. Guides: `docs/guides/input.md` (the snap-back chip) and
`docs/guides/drawing-and-gpu.md` (the pulse and the swing), mirrored by hand (`DG-C`, `DG-D`).

**The fourteen offscreen images** (`docs/probes/demo-pixels/compare.sh <scratch> 1bdead8d HEAD`, controls non-zero as recorded): **0 px, scene identical in all fourteen** against `1bdead8d` at the Record phase's head `37d9bbff`
(lane 2 had read the same at its own head).

## §7 Verification, counts

Measured at the Record phase on the merged tree (this branch merged with master `11dca65e`, §136 and §137), after `swift package clean`, locked screen:

- **Root, native, unfiltered:** `swift build --build-system native --build-tests` 0 `error:`, the only `warning:` SwiftPM's deprecation notice; `swift test --build-system native --no-parallel`: **4159 tests in 5 suites**
  (master's 4120 + lane 1's 21 + lane 2's 18), 0 goldens, **257 typecheck guards** (251 + the six new, by addition: there is no counter), failed with exactly the five `AppKitPresentationTests` sheet issues of `CI-AF` (`appKitCancelledDialogArrivesAsQueuedInput`,
  `appKitDismissPresentationEndsTheSheetAndAnswersNothing`, `appKitOpenDialogIsASheetWithTheDeclaredTypes`, `appKitSaveDialogCarriesTheNameTypesAndExportPrompt`, `appKitSecondDialogWhileASheetIsUpAnswersFalse`) and nothing else;
  `FR-J no-argument frame: succeeded=true`; 1115 s on a shared Mac. (Lane 1's own run at `2c871688` read 4138; lane 2's with the AppKit suites skipped 4135.)
- **Default build system:** `swift build --build-tests` 0 `warning:`.
- **Verify switches:** `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1`, `--skip AppKitPresentationTests`: **4150 tests in 5 suites passed**, no trap, 0 issues (4159 less the nine skipped).
- **Inventory:** `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing; the census is **3710** declarations (3683 + 27: lane 1's 17, lane 2's 10), re-recorded after the final source edit (the header comment of
  `Gesture.swift` moved lines).
- **Linux image** (`metalui-portable`, OrbStack, volume `metalui-root-build-gesture-state`): `MetalUITestingTests` + the portable tests **451** in 2 suites, `MetalUILayoutTests` **233**, `MetalUICoreTests` **138**,
  the cross-platform **22**, all passed (lane 2's retained arm and both guide mirrors included; `PhaseAnimatorTests` and the guards are macOS-only targets). `Backends/SDL` untouched, not re-taken.
- **Divergences:** 645, 646 added, 236 amended; the header's count is 160 (next-label line left for the merge) (`docs/divergences.md`).

## §8 Hazards

- **A state written by two simultaneous gestures** resolves in declaration order, not SwiftUI's last-declared (645); the probe lines behind it were not re-taken.
- **An animated reset is divergence 99's one root transaction**: a reset that animates while another animated write lands in the same build shares one animation.
- **`finished` is the only place a reset is queued.** A new arena exit that skips both `fail(_:)` and `act(_:)` would leave a state stuck at its dragged value; `everyCancelPathResetsOnce` has one arm per
  `IF-F`/`GC-` path and the audit (`GS-Q` 5) lists the discard sites. A new site that drops an arena owes a pin there.
- **A cycling `phaseAnimator` is refused by the retained paths every frame** (`timeVarying`, counted), as a live keyframe animator is; an idle trigger animator at rest is not pinned (C14-i owns it).
- **Write from input, never from a phase** still holds: `updating` bodies run from the arena under `StateDispatch`; a phase-time write of a `GestureState` is as stale as any `@State` one.
- **`phaseAnimator` shares `keyframeDepth`'s counter** (`GS-H`): a retained graft that must key the phase depth would be a one-line addition in `RetainedGraft.swift`, a file this item does not own.

## §9 Deferrals, owed and owners

- **Owed to a human:** group GS (GS1–GS7, `docs/verification/human-checks.md`), most importantly GS3 (Reduce Motion for `phaseAnimator`; the counter-ruling is one `snaps` read, `GS-K`) and GS7 (the
  probe re-take, `GS-O`). Record §03 carries the entry.
- **Owed, not a look:** the unlocked root run (five `AppKitPresentationTests` sheet issues of `CI-AF` read on a locked screen), the `swift build --build-tests` default-build-system re-take on the
  merged tree if master moves.
- **Deferred, owner none** (`GS-N`): `updating` on composed gestures and the `GestureStateGesture` type (additive later), `PlaceholderContentView`, SwiftUI's end-of-run content call, Reduce Motion
  for `phaseAnimator`, SwiftUI's non-`@MainActor` `updating`/`reset:` closures. `drawText`'s deferral (`GT-F`) is untouched.
- **Carried to C14-i** (`GS-P`): whether a settled trigger animator at rest replays or grafts.

## §10 Documents changed at the Record phase

`CLAUDE.md`/`AGENTS.md` (the `GS-` prefix, the `GS-` paragraph, the counts bullet, the record map, two stale sentences), `docs/api-overview.md` (a `@GestureState` paragraph, a Phases paragraph, the
Input follow-ups and not-built lists), `docs/divergences.md` (645 row from lane 1, 236 and the not-built row amended), `docs/record/04-divergences.md`, `docs/record/03-verified-on-real-hardware.md`,
`docs/record/README.md`, `docs/verification/human-checks.md` (group GS), `README.md`, `Gesture.swift`'s header and `onCancelled` comment, `docs/probes/closeout-public-api.tsv` (re-recorded), the spec's
Status, and the decisions doc (`GS-S`, next unused `GS-T`). `docs/migration.md`: nothing breaking — no defaultless requirement, no changed signature; `GestureState` and `PhaseAnimator` are new names.
